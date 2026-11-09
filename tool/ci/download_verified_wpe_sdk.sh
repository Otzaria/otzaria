#!/usr/bin/env bash
# Download the pinned WPE SDK through GitHub's release-assets API first.
# The regular /releases/download/ edge can return 504 even when the API works.
# Never unpack a response that does not match the independently pinned SHA-256.
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "usage: $0 <arch> <version> <expected-sha256> <destination>" >&2
  exit 2
fi
arch="$1"
version="$2"
expected_sha="$3"
destination="$4"

case "$version/$arch" in
  2.48.7/x86_64) asset_id=540161229 ;;
  2.48.7/aarch64) asset_id=540319689 ;;
  *)
    echo "::error::No pinned WPE release asset ID for $version/$arch" >&2
    exit 2
    ;;
esac

if ! [[ "$expected_sha" =~ ^[a-f0-9]{64}$ ]]; then
  echo "::error::Invalid WPE SHA-256 pin" >&2
  exit 2
fi

asset="wpe-runtime-${version}-linux-${arch}.tar.zst"
api_url="https://api.github.com/repos/Otzaria/otzaria-wpe-runtime/releases/assets/${asset_id}"
release_url="https://github.com/Otzaria/otzaria-wpe-runtime/releases/download/wpe-2.48.7-print-to-pdf/${asset}"
mkdir -p "$(dirname "$destination")"
partial="$(mktemp "${destination}.partial.XXXXXX")"
trap 'rm -f "$partial"' EXIT

common_curl=(--fail --silent --show-error --location --retry 3 --retry-delay 5
             --connect-timeout 20 --max-time 300)
api_headers=(-H 'Accept: application/octet-stream' -H 'X-GitHub-Api-Version: 2022-11-28')
if [ -n "${GITHUB_TOKEN:-}" ]; then
  api_headers+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

download_and_verify() {
  local url="$1"
  shift
  : > "$partial"
  if ! curl "${common_curl[@]}" "$@" --output "$partial" "$url"; then
    return 1
  fi
  # GitHub may answer HTTP 200 with JSON metadata instead of binary data.
  # Checking the expected artifact hash also protects against this case.
  if ! printf '%s  %s\n' "$expected_sha" "$partial" | sha256sum --check --status; then
    echo "::warning::WPE download did not match the pinned SHA-256" >&2
    return 1
  fi
}

echo "Downloading pinned $asset via GitHub release-assets API (asset id $asset_id)"
if ! download_and_verify "$api_url" "${api_headers[@]}"; then
  echo "::warning::Verified WPE API download unavailable; trying the release URL" >&2
  if ! download_and_verify "$release_url"; then
    echo "::error::WPE SDK unavailable or failed SHA-256 verification via both endpoints" >&2
    exit 1
  fi
fi

mv -f "$partial" "$destination"
echo "Verified WPE SHA-256: $expected_sha"
