#!/usr/bin/env bash
set -euo pipefail

archive=${1:?usage: split_release_asset.sh <archive> <output-dir> [part-size-bytes]}
output_dir=${2:?usage: split_release_asset.sh <archive> <output-dir> [part-size-bytes]}
part_size=${3:-1992294400}
github_limit=2147483648

[ -f "$archive" ] || { echo "archive not found: $archive" >&2; exit 1; }
case "$part_size" in
  ''|*[!0-9]*) echo "part size must be a positive integer" >&2; exit 1 ;;
esac
[ "$part_size" -gt 0 ] || { echo "part size must be positive" >&2; exit 1; }
[ "$part_size" -lt "$github_limit" ] || {
  echo "part size must remain below GitHub's 2 GiB per-asset limit" >&2
  exit 1
}

mkdir -p "$output_dir"
[ -z "$(find "$output_dir" -mindepth 1 -maxdepth 1 -print -quit)" ] || {
  echo "output directory must be empty: $output_dir" >&2
  exit 1
}

base=$(basename "$archive")
split -b "$part_size" -d -a 3 -- "$archive" "$output_dir/$base.part-"

file_size() {
  if stat -c '%s' "$1" >/dev/null 2>&1; then
    stat -c '%s' "$1"
  else
    stat -f '%z' "$1"
  fi
}

parts_json=$(
  for part in "$output_dir/$base.part-"*; do
    size=$(file_size "$part")
    [ "$size" -lt "$github_limit" ] || {
      echo "part exceeds GitHub's limit: $part ($size bytes)" >&2
      exit 1
    }
    sha=$(sha256sum "$part" | awk '{print $1}')
    jq -n \
      --arg name "$(basename "$part")" \
      --arg sha256 "$sha" \
      --argjson size "$size" \
      '{name: $name, size: $size, sha256: $sha256}'
  done | jq -s '.'
)

archive_size=$(file_size "$archive")
archive_sha=$(sha256sum "$archive" | awk '{print $1}')
manifest="$output_dir/$base.manifest.json"
jq -n \
  --arg archive "$base" \
  --arg sha256 "$archive_sha" \
  --argjson size "$archive_size" \
  --argjson partSizeLimit "$part_size" \
  --argjson githubAssetLimit "$github_limit" \
  --argjson parts "$parts_json" \
  '{
    schemaVersion: 1,
    archive: $archive,
    size: $size,
    sha256: $sha256,
    partSizeLimit: $partSizeLimit,
    githubAssetLimit: $githubAssetLimit,
    parts: $parts
  }' > "$manifest"

jq -e '.parts | length > 0' "$manifest" >/dev/null
echo "Created $(jq '.parts | length' "$manifest") parts and $manifest"
