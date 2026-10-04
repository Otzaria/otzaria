#!/bin/bash
# Xcode build phase: embeds Microsoft's ONNX Runtime (pinned in
# onnxruntime_release.txt) as Contents/Frameworks/libonnxruntime.dylib and
# signs it with the app's identity, so a Hardened Runtime app may load it.
# The license notices go to Contents/Resources/onnxruntime/: Frameworks holds code only.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
release_file="$script_dir/onnxruntime_release.txt"

version="$(awk '$1 == "version" { print $2 }' "$release_file")"
read -r asset sha256 < <(awk '$1 == "darwin-arm64" { print $2, $3 }' "$release_file")
[ -n "$version" ] && [ -n "$asset" ] || { echo "error: no pinned ONNX Runtime asset for darwin-arm64" >&2; exit 1; }

cache_dir="${OTZARIA_BUILD_CACHE:-$HOME/Library/Caches/otzaria-build-cache}/onnxruntime"
archive="$cache_dir/$asset"
if [ ! -f "$archive" ] || [ "$(shasum -a 256 "$archive" | cut -d ' ' -f 1)" != "$sha256" ]; then
  mkdir -p "$cache_dir"
  url="https://github.com/microsoft/onnxruntime/releases/download/v$version/$asset"
  echo "Downloading ONNX Runtime $version: $url"
  curl -fsSL --retry 3 --connect-timeout 30 -o "$archive.part" "$url"
  actual="$(shasum -a 256 "$archive.part" | cut -d ' ' -f 1)"
  if [ "$actual" != "$sha256" ]; then
    rm -f "$archive.part"
    echo "error: $asset SHA-256 is $actual, expected $sha256" >&2
    exit 1
  fi
  mv -f "$archive.part" "$archive"
fi

stem="${asset%.tgz}"
work_dir="${DERIVED_FILE_DIR:-$TMPDIR}/onnxruntime"
rm -rf "$work_dir"
mkdir -p "$work_dir"
tar -xzf "$archive" -C "$work_dir" \
  "$stem/lib/libonnxruntime.$version.dylib" "$stem/LICENSE" "$stem/ThirdPartyNotices.txt"

app="$TARGET_BUILD_DIR/$WRAPPER_NAME"
frameworks="$app/Contents/Frameworks"
notices="$app/Contents/Resources/onnxruntime"
mkdir -p "$frameworks" "$notices"
dylib="$frameworks/libonnxruntime.dylib"
cp -f "$work_dir/$stem/lib/libonnxruntime.$version.dylib" "$dylib"
cp -f "$work_dir/$stem/LICENSE" "$work_dir/$stem/ThirdPartyNotices.txt" "$notices/"

if [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  sign_args=(--force --sign "$EXPANDED_CODE_SIGN_IDENTITY")
  if [ "${ENABLE_HARDENED_RUNTIME:-NO}" = "YES" ]; then
    sign_args+=(--options runtime)
  fi
  # ad-hoc ("-") signing has no timestamp; notarization needs one for a real identity.
  if [ "$EXPANDED_CODE_SIGN_IDENTITY" != "-" ]; then
    sign_args+=(--timestamp)
  fi
  codesign "${sign_args[@]}" "$dylib"
fi
