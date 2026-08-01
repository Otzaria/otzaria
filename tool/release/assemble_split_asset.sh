#!/usr/bin/env bash
set -euo pipefail

manifest=${1:?usage: assemble_split_asset.sh <manifest.json> [output-file]}
[ -f "$manifest" ] || { echo "manifest not found: $manifest" >&2; exit 1; }

manifest_dir=$(cd "$(dirname "$manifest")" && pwd)
archive_name=$(jq -er '.archive' "$manifest")
[ "$archive_name" = "$(basename "$archive_name")" ] || {
  echo "unsafe archive name in manifest: $archive_name" >&2
  exit 1
}
output=${2:-$manifest_dir/$archive_name}
[ ! -e "$output" ] || { echo "output already exists: $output" >&2; exit 1; }

expected_count=$(jq -er '.parts | length' "$manifest")
[ "$expected_count" -gt 0 ] || { echo "manifest contains no parts" >&2; exit 1; }

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

while IFS=$'\t' read -r part_name expected_sha; do
  [ "$part_name" = "$(basename "$part_name")" ] || {
    echo "unsafe part name in manifest: $part_name" >&2
    exit 1
  }
  part="$manifest_dir/$part_name"
  [ -f "$part" ] || { echo "missing part: $part_name" >&2; exit 1; }
  actual_sha=$(hash_file "$part")
  [ "$actual_sha" = "$expected_sha" ] || {
    echo "checksum mismatch: $part_name" >&2
    exit 1
  }
done < <(jq -r '.parts[] | [.name, .sha256] | @tsv' "$manifest")

touch "$output"
for part_name in $(jq -r '.parts[].name' "$manifest"); do
  cat "$manifest_dir/$part_name" >> "$output"
done

expected_archive_sha=$(jq -er '.sha256' "$manifest")
actual_archive_sha=$(hash_file "$output")
[ "$actual_archive_sha" = "$expected_archive_sha" ] || {
  echo "archive checksum mismatch: $output" >&2
  exit 1
}
echo "Reassembled and verified: $output"
