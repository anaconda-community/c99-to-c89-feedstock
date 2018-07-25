#!/bin/bash

set -x

# $(dirname $(dirname $(dirname $(which 7z))))/usr/lib/p7zip/7z x -aoa -o$PWD/clang LLVM*${ARCH}.exe || exit 1
curl -O http://releases.llvm.org/3.9.1/LLVM-3.9.1-win64.exe
# We need a libclang. No one builds them statically for Windows unfortunately (though the
# libav binaries have been built this way). I rename the libclang.dll in these to avoid
# conflicts with conda-forge's clangdev (which we cannot use at present due to compat).
# LLVM 6 has changed too much and is no longer compatible. It is at the ABI level, but
# not semantically (Assertion failed: n_tokens == 2, file convert.c, line 559).
7z x -aoa -o$PWD/clang LLVM*.exe || exit 1

CLANGDIR=${PWD}/clang
# Rename libclang.dll to avoid conflicts. Sorry. No one builds static libclangs on Windows for some reason?
cp ${CLANGDIR}/bin/libclang.dll ${CLANGDIR}/bin/c99-to-c89-libclang.dll
# Create an import library for c99-to-c89-libclang.dll
gendef ${CLANGDIR}/bin/c99-to-c89-libclang.dll - > c99-to-c89-libclang.dll.def
sed -i 's|LIBRARY "libclang.dll"|LIBRARY "c99-to-c89-libclang.dll"|' c99-to-c89-libclang.dll.def
if [[ ${ARCH} == 32 ]]; then
  MS_MACH=X86
else
  MS_MACH=X64
fi
if [[ ${vc} == 9 ]]; then
  SNPRINTF=-Dsnprintf=_snprintf
fi
lib /def:c99-to-c89-libclang.dll.def /out:$(cygpath -m ${CLANGDIR}/lib/c99-to-c89-libclang.lib) /machine:${MS_MACH}

if ! CFLAGS="${CFLAGS} -I${BUILD_PREFIX}/Library/include ${SNPRINTF}" CLANGDIR=${PWD}/clang make -f Makefile.w32; then
  echo "ERROR :: Build failed"
  exit 1
fi
cp c99*.exe ${CLANGDIR}/bin/c99-to-c89-libclang.dll ${PREFIX}/Library/bin

# This file should be passed to the CMake command-line as:
# -DCMAKE_C_COMPILER="c99-to-c89-cmake-nmake-wrap.bat"
# I have given it a very specific name as I do not know that it will work for any other CMake.
# We set the some debug flags so that we see the contents of the @response files and so that
# temporaries are retained.
pushd ${PREFIX}/Library/bin
  echo "@echo off"                                          > c99-to-c89-cmake-nmake-wrap.bat
  echo "echo cd %CD%"                                      >> c99-to-c89-cmake-nmake-wrap.bat
  echo "setlocal EnableExtensions EnableDelayedExpansion"  >> c99-to-c89-cmake-nmake-wrap.bat
  echo "if \"%VERBOSE_CM%\"==\"1\" ("                      >> c99-to-c89-cmake-nmake-wrap.bat
  echo "  set C99_TO_C89_WRAP_DEBUG_LEVEL=1"               >> c99-to-c89-cmake-nmake-wrap.bat
  echo "  set C99_TO_C89_WRAP_SAVE_TEMPS=1"                >> c99-to-c89-cmake-nmake-wrap.bat
  echo "  set C99_TO_C89_WRAP_NO_LINE_DIRECTIVES=1"        >> c99-to-c89-cmake-nmake-wrap.bat
  echo "  set C99_TO_C89_CONV_DEBUG_LEVEL=1"               >> c99-to-c89-cmake-nmake-wrap.bat
  echo ")"                                                 >> c99-to-c89-cmake-nmake-wrap.bat
  echo "%~dp0c99wrap.exe -keep cl %*"                      >> c99-to-c89-cmake-nmake-wrap.bat
popd
