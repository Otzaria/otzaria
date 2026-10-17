#!/usr/bin/env bash
# Download the latest SeforimLibrary full DB to <out-file>: the single asset, or,
# above GitHub's asset limit, its parts joined and verified through the manifest.
set -euo pipefail

out=${1:?usage: download_library_db.sh <out-file>}
base=${SEFORIM_LIBRARY_DOWNLOAD_BASE:-https://github.com/Otzaria/SeforimLibrary/releases}
here=$(cd "$(dirname "$0")" && pwd)
# Schema 6+ ships under its own name, newest first; seforim.db.zst is reserved for schema 5 and older.
names=(seforim-schema7.db.zst seforim-schema6.db.zst seforim.db.zst)

fetch() { curl -L --fail --retry 3 --silent --show-error -o "$2" "$1"; }

# One tag for every file, so "latest" cannot move between the manifest and its parts.
tag=${SEFORIM_LIBRARY_TAG:-}
if [ -z "$tag" ]; then
  latest=$(curl --fail --retry 3 --silent --show-error -o /dev/null -w '%{redirect_url}' "$base/latest")
  tag=${latest##*/tag/}
  [ -n "$tag" ] && [ "$tag" != "$latest" ] || { echo "::error::cannot resolve the latest release of $base" >&2; exit 1; }
fi
download="$base/download/$tag"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

for name in "${names[@]}"; do
  if fetch "$download/$name" "$out" 2>/dev/null; then
    echo "Downloaded $name from $tag"
    exit 0
  fi
  rm -f "$out"
  manifest="$work/$name.manifest.json"
  fetch "$download/$name.manifest.json" "$manifest" 2>/dev/null || continue
  while IFS= read -r part; do
    case "$part" in ''|*/*|.|..) echo "::error::unsafe part name in $name.manifest.json: $part" >&2; exit 1 ;; esac
    fetch "$download/$part" "$work/$part"
  done < <(jq -r '.parts[].name' "$manifest")
  bash "$here/assemble_split_asset.sh" "$manifest" "$out"
  echo "Downloaded $name from $tag in $(jq '.parts | length' "$manifest") parts"
  exit 0
done

echo "::error::release $tag has no ${names[*]}, whole or split" >&2
exit 1
