#!/usr/bin/env bash
# Offline contract for the exact macOS Xcode ONNX embed build phase.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/source" "$tmp/package/runtimes/osx-arm64/native" "$tmp/bin" "$tmp/app/Otzaria.app"
cp "$script_dir/embed_onnxruntime_macos.sh" "$tmp/source/"
printf 'fixture-binary' > "$tmp/package/runtimes/osx-arm64/native/libonnxruntime.dylib"
printf 'license' > "$tmp/package/LICENSE"
printf 'notices' > "$tmp/package/ThirdPartyNotices.txt"
fixture="$tmp/fixture.nupkg"
(cd "$tmp/package" && zip -qr "$fixture" .)
sha="$(shasum -a 256 "$fixture" | awk '{print $1}')"
cat > "$tmp/source/onnxruntime_release.txt" <<EOF
version 1.28.0
package microsoft.ml.onnxruntime.1.28.0.nupkg $sha
darwin-arm64 runtimes/osx-arm64/native/libonnxruntime.dylib
EOF

# The mock validates the exact CLI arguments. It can produce a valid download,
# a partial transfer with an HTTP error, an elapsed timeout or a DNS failure.
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
[ "$url" = 'https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/1.28.0/microsoft.ml.onnxruntime.1.28.0.nupkg' ]
[ "$retries" = 3 ] && [ "$connect_timeout" = 30 ]
[ "$max_time" = 300 ] && [ "$retry_max_time" = 600 ]
[ -n "$output" ]
case "${ONNX_TEST_CURL_MODE:-success}" in
  success) cp "$ONNX_TEST_ARCHIVE" "$output" ;;
  404|503) printf partial > "$output"; echo "synthetic HTTP $ONNX_TEST_CURL_MODE" >&2; exit 22 ;;
  timeout) printf partial > "$output"; echo 'synthetic curl exit 28 (timeout)' >&2; exit 28 ;;
  network) echo 'synthetic curl exit 6 (DNS failure)' >&2; exit 6 ;;
  *) exit 91 ;;
esac
SH
chmod +x "$tmp/bin/curl"

export PATH="$tmp/bin:$PATH"
export ONNX_TEST_ARCHIVE="$fixture"
export OTZARIA_BUILD_CACHE="$tmp/cache"
export TARGET_BUILD_DIR="$tmp/app"
export WRAPPER_NAME=Otzaria.app
export DERIVED_FILE_DIR="$tmp/derived"
export CODE_SIGNING_ALLOWED=NO
cache="$tmp/cache/onnxruntime/microsoft.ml.onnxruntime.1.28.0.nupkg"
out="$TARGET_BUILD_DIR/$WRAPPER_NAME/Contents"
embed() { bash "$tmp/source/embed_onnxruntime_macos.sh"; }
assert_good_archive() {
  [ -f "$cache" ] && [ ! -e "$cache.part" ]
  [ "$(shasum -a 256 "$cache" | awk '{print $1}')" = "$sha" ]
}

# A direct download embeds the platform's library and the notices.
ONNX_TEST_CURL_MODE=success embed
assert_good_archive
cmp "$tmp/package/runtimes/osx-arm64/native/libonnxruntime.dylib" "$out/Frameworks/libonnxruntime.dylib"
cmp "$tmp/package/LICENSE" "$out/Resources/onnxruntime/LICENSE"
cmp "$tmp/package/ThirdPartyNotices.txt" "$out/Resources/onnxruntime/ThirdPartyNotices.txt"

# A verified cache needs no network.
ONNX_TEST_CURL_MODE=network embed
assert_good_archive

# Every download error fails explicitly and leaves no partial archive behind.
for mode in 404 503 timeout network; do
  rm -rf "$tmp/cache"
  if ONNX_TEST_CURL_MODE="$mode" embed; then
    echo "download failure ($mode) was accepted" >&2
    exit 1
  fi
  [ ! -e "$cache" ] && [ ! -e "$cache.part" ]
done

# A corrupt cache is never used: it is downloaded again, or the build fails.
ONNX_TEST_CURL_MODE=success embed
printf corrupt > "$cache"
if ONNX_TEST_CURL_MODE=timeout embed; then
  echo 'corrupt cached archive was accepted' >&2
  exit 1
fi
ONNX_TEST_CURL_MODE=success embed
assert_good_archive

# A downloaded archive with another digest is rejected.
rm -rf "$tmp/cache"
printf malicious > "$tmp/wrong.nupkg"
if ONNX_TEST_CURL_MODE=success ONNX_TEST_ARCHIVE="$tmp/wrong.nupkg" embed; then
  echo 'untrusted downloaded archive was accepted' >&2
  exit 1
fi
[ ! -e "$cache" ] && [ ! -e "$cache.part" ]
printf 'PASS: download, cache, HTTP errors, timeout, network, corrupt cache, wrong digest\n'
