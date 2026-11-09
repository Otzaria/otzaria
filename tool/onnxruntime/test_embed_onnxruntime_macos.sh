#!/usr/bin/env bash
# Offline contract for the exact macOS Xcode ONNX embed build phase.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/source" "$tmp/release/onnxruntime-osx-arm64-1.28.0/lib" "$tmp/bin" "$tmp/app/Otzaria.app"
cp "$script_dir/embed_onnxruntime_macos.sh" "$tmp/source/"
printf 'fixture-binary' > "$tmp/release/onnxruntime-osx-arm64-1.28.0/lib/libonnxruntime.1.28.0.dylib"
printf 'license' > "$tmp/release/onnxruntime-osx-arm64-1.28.0/LICENSE"
printf 'notices' > "$tmp/release/onnxruntime-osx-arm64-1.28.0/ThirdPartyNotices.txt"
fixture="$tmp/fixture.tgz"
tar -czf "$fixture" -C "$tmp/release" onnxruntime-osx-arm64-1.28.0
sha="$(shasum -a 256 "$fixture" | awk '{print $1}')"
cat > "$tmp/source/onnxruntime_release.txt" <<EOF
version 1.28.0
darwin-arm64 onnxruntime-osx-arm64-1.28.0.tgz $sha
EOF

# Both mocks validate exact CLI arguments. curl can produce a valid download,
# partial transfers, HTTP errors, an elapsed timeout or a DNS failure.
cat > "$tmp/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
output='' url='' retries='' connect_timeout='' max_time='' retry_max_time=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    -fsSL) shift ;;
    --retry) retries="$2"; shift 2 ;;
    --connect-timeout) connect_timeout="$2"; shift 2 ;;
    --max-time) max_time="$2"; shift 2 ;;
    --retry-max-time) retry_max_time="$2"; shift 2 ;;
    -o) output="$2"; shift 2 ;;
    https://*) url="$1"; shift ;;
    *) echo "unexpected curl argument: $1" >&2; exit 90 ;;
  esac
done
[ "$url" = 'https://github.com/microsoft/onnxruntime/releases/download/v1.28.0/onnxruntime-osx-arm64-1.28.0.tgz' ]
[ "$retries" = 3 ] && [ "$connect_timeout" = 30 ]
[ "$max_time" = 180 ] && [ "$retry_max_time" = 360 ]
[ -n "$output" ]
case "${ONNX_TEST_CURL_MODE:-503}" in
  success) cp "$ONNX_TEST_ARCHIVE" "$output" ;;
  503|504) printf partial > "$output"; echo "synthetic HTTP $ONNX_TEST_CURL_MODE" >&2; exit 22 ;;
  timeout) printf partial > "$output"; echo 'synthetic curl exit 28 (timeout)' >&2; exit 28 ;;
  network) echo 'synthetic curl exit 6 (DNS failure)' >&2; exit 6 ;;
  *) exit 91 ;;
esac
SH
cat > "$tmp/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = release ] && [ "$2" = download ] && [ "$3" = v1.28.0 ]
shift 3
repo='' pattern='' dir=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --pattern) pattern="$2"; shift 2 ;;
    --dir) dir="$2"; shift 2 ;;
    --clobber) shift ;;
    *) exit 40 ;;
  esac
done
[ "$repo" = microsoft/onnxruntime ]
[ "$pattern" = onnxruntime-osx-arm64-1.28.0.tgz ]
[ -n "$dir" ]
[ "${ONNX_TEST_DISABLE_GH:-0}" != 1 ] || exit 41
cp "$ONNX_TEST_ARCHIVE" "$dir/$pattern"
SH
chmod +x "$tmp/bin/curl" "$tmp/bin/gh"

export PATH="$tmp/bin:$PATH"
export ONNX_TEST_ARCHIVE="$fixture"
export GH_TOKEN=test-read-only-token
export OTZARIA_BUILD_CACHE="$tmp/cache"
export TARGET_BUILD_DIR="$tmp/app"
export WRAPPER_NAME=Otzaria.app
export DERIVED_FILE_DIR="$tmp/derived"
export CODE_SIGNING_ALLOWED=NO
cache="$tmp/cache/onnxruntime/onnxruntime-osx-arm64-1.28.0.tgz"
out="$TARGET_BUILD_DIR/$WRAPPER_NAME/Contents"

# Inspect stdout/stderr from *every* invocation so both successful and failed
# downloads must keep GH_TOKEN secret. Do not print the captured token itself.
run_checked() {
  local status=0
  bash "$tmp/source/embed_onnxruntime_macos.sh" > "$tmp/output.log" 2>&1 || status=$?
  if [ -n "${GH_TOKEN:-}" ] && grep -Fq -- "$GH_TOKEN" "$tmp/output.log"; then
    echo 'GH_TOKEN was printed by the embed build phase' >&2
    exit 98
  fi
  cat "$tmp/output.log"
  return "$status"
}
assert_no_download_temps() {
  [ ! -e "$cache.part" ]
  [ -z "$(find "$tmp/cache/onnxruntime" -maxdepth 1 -name '.onnx-gh.*' -print -quit)" ]
}
assert_good_archive() {
  [ -f "$cache" ]
  [ "$(shasum -a 256 "$cache" | awk '{print $1}')" = "$sha" ]
  assert_no_download_temps
}

# Ordinary direct download must succeed without ever calling GitHub CLI.
ONNX_TEST_CURL_MODE=success ONNX_TEST_DISABLE_GH=1 run_checked
assert_good_archive
cmp "$tmp/release/onnxruntime-osx-arm64-1.28.0/lib/libonnxruntime.1.28.0.dylib" "$out/Frameworks/libonnxruntime.dylib"
cmp "$tmp/release/onnxruntime-osx-arm64-1.28.0/LICENSE" "$out/Resources/onnxruntime/LICENSE"
cmp "$tmp/release/onnxruntime-osx-arm64-1.28.0/ThirdPartyNotices.txt" "$out/Resources/onnxruntime/ThirdPartyNotices.txt"

# Verified cache works even with no network and a disabled fallback.
ONNX_TEST_CURL_MODE=network ONNX_TEST_DISABLE_GH=1 run_checked
assert_good_archive

# Each independent error triggers the same API fallback to the exact release.
for mode in 503 504 timeout network; do
  rm -rf "$tmp/cache"
  ONNX_TEST_CURL_MODE="$mode" run_checked
  assert_good_archive
done

# With no token, failure is explicit; no partial archive should survive.
rm -rf "$tmp/cache"
saved_token="$GH_TOKEN"
unset GH_TOKEN
if ONNX_TEST_CURL_MODE=504 run_checked; then
  echo 'fallback succeeded without GH_TOKEN' >&2
  exit 1
fi
export GH_TOKEN="$saved_token"
[ ! -e "$cache" ] && [ ! -e "$cache.part" ]

# Corrupt cache may not be accepted. Disable the fallback to force failure.
ONNX_TEST_CURL_MODE=503 run_checked
printf corrupt > "$cache"
if ONNX_TEST_CURL_MODE=timeout ONNX_TEST_DISABLE_GH=1 run_checked; then
  echo 'corrupt cached archive was accepted' >&2
  exit 1
fi
assert_no_download_temps

# A newly downloaded, incorrect archive fails the pinned SHA check.
printf malicious > "$tmp/wrong.tgz"
if ONNX_TEST_CURL_MODE=503 ONNX_TEST_ARCHIVE="$tmp/wrong.tgz" run_checked; then
  echo 'untrusted downloaded archive was accepted' >&2
  exit 1
fi
[ ! -e "$cache.part" ]

# Exact contents restore the cache; a second invocation must hit the cache.
ONNX_TEST_CURL_MODE=503 run_checked
assert_good_archive
ONNX_TEST_CURL_MODE=timeout ONNX_TEST_DISABLE_GH=1 run_checked
assert_good_archive
printf 'PASS: direct download, 503, 504, timeout, network, cache, corrupt cache, wrong digest, no token leak\n'
