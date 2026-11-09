#!/usr/bin/env bash
# Independent packaging regression contract for strip_wpe_runtime.sh.
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/strip_wpe_runtime.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/sdk" "$tmp/bundle/lib" "$tmp/outside"
cat > "$tmp/lib.c" <<'C'
#include <stdio.h>
__attribute__((visibility("default"))) void wpe_qa_export(void) { puts("WPE QA: ok"); }
C
cc -shared -fPIC -g -Wl,-soname,libWPEWebKit-2.0.so.1 \
  -o "$tmp/sdk/libWPEWebKit-2.0.so.1.5.12" "$tmp/lib.c"
cp "$tmp/sdk/libWPEWebKit-2.0.so.1.5.12" "$tmp/bundle/lib/"
ln -s libWPEWebKit-2.0.so.1.5.12 "$tmp/bundle/lib/libWPEWebKit-2.0.so.1"
sha_pre="$(sha256sum "$tmp/sdk/libWPEWebKit-2.0.so.1.5.12" | cut -d' ' -f1)"

bash "$script" "$tmp/bundle/lib" | tee "$tmp/test.tsv"
test "$(awk -F '\t' '$1=="wpe_strip_elf_count"{print $2}' "$tmp/test.tsv")" = 1
test "$(awk -F '\t' '$1=="wpe_strip_savings_bytes"{print $2}' "$tmp/test.tsv")" -gt 0
test "$(sha256sum "$tmp/sdk/libWPEWebKit-2.0.so.1.5.12" | cut -d' ' -f1)" = "$sha_pre"
test "$(readlink "$tmp/bundle/lib/libWPEWebKit-2.0.so.1")" = libWPEWebKit-2.0.so.1.5.12
readelf --dyn-syms "$tmp/bundle/lib/libWPEWebKit-2.0.so.1" | grep -q wpe_qa_export

# Dangling symlink must fail rather than silently skipping.
rm -rf "$tmp/bundle/lib"; mkdir "$tmp/bundle/lib"
ln -s missing.so "$tmp/bundle/lib/libWPEWebKit-2.0.so.1"
if bash "$script" "$tmp/bundle/lib" >"$tmp/out" 2>&1; then echo 'broken symlink accepted' >&2; exit 1; fi
grep -q 'broken WPE symlink' "$tmp/out"

# Escape via symlink must not change the external target.
rm "$tmp/bundle/lib/libWPEWebKit-2.0.so.1"
cp "$tmp/sdk/libWPEWebKit-2.0.so.1.5.12" "$tmp/outside/libWPEWebKit-2.0.so.1"
ln -s "$tmp/outside/libWPEWebKit-2.0.so.1" "$tmp/bundle/lib/libWPEWebKit-2.0.so.1"
if bash "$script" "$tmp/bundle/lib" >"$tmp/out" 2>&1; then echo 'external symlink accepted' >&2; exit 1; fi
grep -q 'outside bundle' "$tmp/out"

# Realpath alone cannot detect an external hard-link.
rm "$tmp/bundle/lib/libWPEWebKit-2.0.so.1"
ln "$tmp/outside/libWPEWebKit-2.0.so.1" "$tmp/bundle/lib/libWPEWebKit-2.0.so.1"
if bash "$script" "$tmp/bundle/lib" >"$tmp/out" 2>&1; then echo 'hard-link accepted' >&2; exit 1; fi
grep -q 'hard-linked' "$tmp/out"

# The containing directory must not be an alias pointing back into the SDK.
ln -s "$tmp/sdk" "$tmp/alias"
if bash "$script" "$tmp/alias" >"$tmp/out" 2>&1; then echo 'bundle-dir symlink accepted' >&2; exit 1; fi
grep -q 'symlinked bundle' "$tmp/out"

echo 'all strip fixture guards passed'
