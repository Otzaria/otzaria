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

cat > "$tmp/bin/curl" <<'SH'
#!/usr/bin/env bash
echo 'simulated 503 from direct GitHub release' >&2
exit 22
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

bash "$tmp/source/embed_onnxruntime_macos.sh"
out="$TARGET_BUILD_DIR/$WRAPPER_NAME/Contents"
cmp "$tmp/release/onnxruntime-osx-arm64-1.28.0/lib/libonnxruntime.1.28.0.dylib" "$out/Frameworks/libonnxruntime.dylib"
cmp "$tmp/release/onnxruntime-osx-arm64-1.28.0/LICENSE" "$out/Resources/onnxruntime/LICENSE"
cmp "$tmp/release/onnxruntime-osx-arm64-1.28.0/ThirdPartyNotices.txt" "$out/Resources/onnxruntime/ThirdPartyNotices.txt"

# A valid cache never uses either download route.
ONNX_TEST_DISABLE_GH=1 bash "$tmp/source/embed_onnxruntime_macos.sh"

# Corrupt cache may not be accepted. Fallback is now disabled, so this fails.
cache="$tmp/cache/onnxruntime/onnxruntime-osx-arm64-1.28.0.tgz"
printf corrupt > "$cache"
if ONNX_TEST_DISABLE_GH=1 bash "$tmp/source/embed_onnxruntime_macos.sh"; then
  echo 'corrupt cached archive was accepted' >&2
  exit 1
fi

# A newly downloaded but wrong archive fails the same pinned SHA check.
printf malicious > "$tmp/wrong.tgz"
if ONNX_TEST_ARCHIVE="$tmp/wrong.tgz" bash "$tmp/source/embed_onnxruntime_macos.sh"; then
  echo 'untrusted downloaded archive was accepted' >&2
  exit 1
fi

# Exact contents restore the cache.
bash "$tmp/source/embed_onnxruntime_macos.sh"
[ "$(shasum -a 256 "$cache" | awk '{print $1}')" = "$sha" ]
printf 'PASS: API fallback, signed fixture extraction, cache, bad cache, wrong asset\n'
