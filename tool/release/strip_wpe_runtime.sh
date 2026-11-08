#!/usr/bin/env bash
# Strip only WPE-owned ELF files after they have been copied into an Otzaria bundle.
# The SDK in /opt/wpe-sdk remains untouched so build/link diagnostics keep full symbols.
set -euo pipefail
shopt -s nullglob

LIBDIR="${1:?usage: strip_wpe_runtime.sh <bundle-lib-dir>}"
[ -d "$LIBDIR" ] || { echo "bundle lib dir not found: $LIBDIR" >&2; exit 2; }

for tool in strip readelf ldd stat readlink; do
  command -v "$tool" >/dev/null || { echo "required tool missing: $tool" >&2; exit 2; }
done

root="$(readlink -f "$LIBDIR")"
declare -A seen=()
before_total=0
after_total=0
count=0

candidates=(
  "$LIBDIR"/libWPEWebKit-2.0.so*
  "$LIBDIR"/libWPEPlatform-2.0.so*
  "$LIBDIR"/libwpe-1.0.so*
  "$LIBDIR"/libWPEInjectedBundle.so
  "$LIBDIR"/WPEWebProcess
  "$LIBDIR"/WPENetworkProcess
  "$LIBDIR"/WPEGPUProcess
)

for candidate in "${candidates[@]}"; do
  [ -e "$candidate" ] || continue
  real="$(readlink -f "$candidate")"
  case "$real" in
    "$root"/*) ;;
    *) echo "refusing to strip WPE target outside bundle: $candidate -> $real" >&2; exit 3 ;;
  esac
  [ -f "$real" ] || continue

  identity="$(stat -Lc '%d:%i' "$real")"
  [ -z "${seen[$identity]+x}" ] || continue
  seen[$identity]=1

  # Ignore non-ELF files even if a future package happens to reuse one of these names.
  readelf -h "$real" >/dev/null 2>&1 || continue

  before="$(stat -Lc '%s' "$real")"
  dynamic_before="$(readelf -d "$real" 2>/dev/null | grep -E '\((NEEDED|SONAME)\)' | sed 's/^[[:space:]]*//' || true)"

  strip --strip-unneeded -- "$real"

  dynamic_after="$(readelf -d "$real" 2>/dev/null | grep -E '\((NEEDED|SONAME)\)' | sed 's/^[[:space:]]*//' || true)"
  if [ "$dynamic_before" != "$dynamic_after" ]; then
    echo "dynamic dependency metadata changed while stripping: $real" >&2
    diff -u <(printf '%s\n' "$dynamic_before") <(printf '%s\n' "$dynamic_after") || true
    exit 4
  fi

  ldd_output="$(ldd "$real" 2>&1 || true)"
  if grep -q 'not found' <<<"$ldd_output"; then
    echo "unresolved dependency after stripping: $real" >&2
    echo "$ldd_output" >&2
    exit 5
  fi

  after="$(stat -Lc '%s' "$real")"
  if [ "$after" -gt "$before" ]; then
    echo "strip unexpectedly grew $real ($before -> $after)" >&2
    exit 6
  fi
  before_total=$((before_total + before))
  after_total=$((after_total + after))
  count=$((count + 1))
  printf 'wpe_strip_file\t%s\t%s\t%s\t%s\n' "$before" "$after" "$((before-after))" "${real#"$root"/}"
done

[ "$count" -gt 0 ] || { echo "no WPE ELF files found in $LIBDIR" >&2; exit 7; }
printf 'wpe_strip_elf_count\t%s\n' "$count"
printf 'wpe_strip_before_bytes\t%s\n' "$before_total"
printf 'wpe_strip_after_bytes\t%s\n' "$after_total"
printf 'wpe_strip_savings_bytes\t%s\n' "$((before_total-after_total))"
