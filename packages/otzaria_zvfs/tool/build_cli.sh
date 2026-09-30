#!/usr/bin/env sh
# Builds the production zvfs_cli with a plain C compiler (no cmake, no test
# hooks). Usage: tool/build_cli.sh [out=build/zvfs_cli]; CC and CFLAGS apply.
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-"$here/build/zvfs_cli"}
cc=${CC:-cc}
mkdir -p "$(dirname "$out")"

# Keep in sync with hook/build.dart and test/c/CMakeLists.txt.
libs=
case "$("$cc" -dumpmachine 2>/dev/null || true)" in
  *mingw* | *windows* | *cygwin*) libs=-lbcrypt ;; # BCryptGenRandom
esac
# shellcheck disable=SC2086
"$cc" -std=gnu99 -O2 ${CFLAGS:-} \
  -DZSTD_DISABLE_ASM=1 -DZSTD_LEGACY_SUPPORT=0 -DZSTD_TRACE=0 \
  -DZSTDLIB_VISIBLE= -DZSTDERRORLIB_VISIBLE= -DZDICTLIB_VISIBLE= \
  -DZSTDLIB_STATIC_API= -DZDICTLIB_STATIC_API= \
  -I"$here/src" -I"$here/third_party/zstd/lib" -I"$here/third_party/sqlite" \
  "$here"/third_party/zstd/lib/common/*.c \
  "$here"/third_party/zstd/lib/compress/*.c \
  "$here"/third_party/zstd/lib/decompress/*.c \
  "$here"/third_party/zstd/lib/dictBuilder/*.c \
  "$here"/src/*.c "$here/tool/zvfs_cli.c" \
  -o "$out" -pthread $libs
echo "built $out"
