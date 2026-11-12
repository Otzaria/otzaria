#!/usr/bin/env bash
# Uploads a build job's release assets straight to the run's draft release, and
# writes <record-dir>/uploaded-assets.json ({name, size, sha256} per asset) plus a
# copy of every JSON asset, so the publishing job never downloads the large files.
#
# usage: upload_release_assets.sh <release-id> <record-dir> [file...] [--optional file...] [--best-effort file...]
#   --optional tolerates missing files; --best-effort also tolerates upload failure.
#   A FULL package above the split threshold goes up as split_oversized_assets.sh
#   parts and manifest — the names the installers and the assistants read.
#   env: GH_TOKEN, GITHUB_REPOSITORY; GITHUB_API_URL and RELEASE_UPLOAD_URL override
#   the hosts. curl and jq only: build_linux runs in a container that has no gh.
set -euo pipefail

usage='usage: upload_release_assets.sh <release-id> <record-dir> [file...] [--optional file...] [--best-effort file...]'
release_id=${1:?$usage}
record_dir=${2:?$usage}
shift 2
: "${GH_TOKEN:?GH_TOKEN is not set}"
repo=${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}
api=${GITHUB_API_URL:-https://api.github.com}
upload_host=${RELEASE_UPLOAD_URL:-https://uploads.github.com}
attempts=${RELEASE_UPLOAD_ATTEMPTS:-5}
retry_delay=${RELEASE_UPLOAD_RETRY_DELAY:-15}
here=$(cd "$(dirname "$0")" && pwd)

file_size() { stat -c '%s' "$1" 2>/dev/null || stat -f '%z' "$1"; }

file_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1"
  else
    shasum -a 256 "$1"
  fi | awk '{print $1}'
}

github_api() { # github_api <method> <url>
  curl -fsSL --retry 3 --retry-delay 5 -X "$1" \
    -H "Authorization: Bearer $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" "$2"
}

# One JSON object per asset of the draft. A native jq on Windows writes CRLF.
list_assets() {
  local page=1 batch
  while :; do
    batch=$(github_api GET "$api/repos/$repo/releases/$release_id/assets?per_page=100&page=$page")
    jq -c '.[] | {id, name, size, state, digest}' <<<"$batch" | tr -d '\r'
    [ "$(jq length <<<"$batch" | tr -d '\r')" -eq 100 ] || break
    page=$((page + 1))
  done
}

# The same name, size and digest is already up: another job uploaded the same file
# (the assemble scripts), or an earlier attempt of this one did.
already_uploaded() { # already_uploaded <name> <size> <sha256>
  list_assets | jq -se --arg name "$1" --argjson size "$2" --arg digest "sha256:$3" \
    'any(.[]; .name == $name and .size == $size and .state == "uploaded" and .digest == $digest)' \
    >/dev/null
}

upload() { # upload <path> <name> <size> <sha256>
  local attempt id name_enc failure_level=${5:-error}
  for attempt in $(seq 1 "$attempts"); do
    if already_uploaded "$2" "$3" "$4"; then
      echo "$2 is already on the release"
      return 0
    fi
    # Like gh --clobber: a stale copy, or a failed attempt's half upload, holds the name.
    for id in $(list_assets | jq -r --arg name "$2" 'select(.name == $name) | .id' | tr -d '\r'); do
      github_api DELETE "$api/repos/$repo/releases/assets/$id" >/dev/null || true
    done
    # '+' (DEB/RPM build numbers) would turn into a space unencoded.
    name_enc=$(jq -rn --arg name "$2" '$name|@uri' | tr -d '\r')
    if curl -fsS -X POST --speed-limit 1024 --speed-time 120 \
      -H "Authorization: Bearer $GH_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -H "Content-Type: application/octet-stream" \
      -T "$1" -o /dev/null \
      "$upload_host/repos/$repo/releases/$release_id/assets?name=$name_enc"; then
      echo "Uploaded $2 ($3 bytes)"
      return 0
    fi
    echo "::warning::uploading $2 failed (attempt $attempt of $attempts)"
    [ "$attempt" -eq "$attempts" ] || sleep $((attempt * retry_delay))
  done
  echo "::$failure_level::could not upload $2 to release $release_id" >&2
  return 1
}

# Beside the workspace, not in /tmp: a hard link to a 2 GB package needs the same volume.
stage=$(mktemp -d "$PWD/.release-upload.XXXXXX")
records=$(mktemp "$PWD/.release-upload-record.XXXXXX")
trap 'rm -rf "$stage" "$records"' EXIT

mode=required
inputs=()
best_effort=()
for file in "$@"; do
  case "$file" in
    --optional) mode=optional; continue ;;
    --best-effort) mode=best_effort; continue ;;
  esac
  if [ ! -f "$file" ]; then
    if [ "$mode" != required ]; then
      echo "::warning::$file is missing - the release goes out without it"
      continue
    fi
    echo "::error::release asset not found: $file" >&2
    exit 1
  fi
  name=$(basename "$file")
  [[ "$name" =~ ^[A-Za-z0-9._+-]+$ ]] || { echo "::error::unsafe release asset name: $name" >&2; exit 1; }
  [ ! -e "$stage/$name" ] || { echo "::error::two release assets are named $name" >&2; exit 1; }
  # Splitting removes the staged name only, never the job's own file.
  ln "$file" "$stage/$name" 2>/dev/null || cp "$file" "$stage/$name"
  inputs+=("$name")
  [ "$mode" != best_effort ] || best_effort+=("$name")
done

# Splitting copies a FULL package into parts; the log shows whether the disk held it.
df -h "$stage" || true
bash "$here/split_oversized_assets.sh" "$stage" \
  'otzaria-*-windows-full.exe' \
  'otzaria-*-windows_arm64-full.exe' \
  'otzaria-linux-full.tar.zst' \
  'otzaria-linux-full-arm64.tar.zst' \
  'otzaria-macos-full.tar.zst'
df -h "$stage" || true

# The splitter adds the assemble scripts; only build_library_assets uploads them, since
# a Windows checkout may hold them with CRLF and two jobs would report different files.
for script in assemble_split_asset.sh assemble_split_asset.ps1; do
  [[ " ${inputs[*]-} " == *" $script "* ]] || rm -f -- "$stage/$script"
done

mkdir -p "$record_dir"
shopt -s nullglob
for path in "$stage"/*; do
  name=$(basename "$path")
  size=$(file_size "$path")
  sha=$(file_sha256 "$path")
  failure_level=error
  [[ " ${best_effort[*]-} " != *" $name "* ]] || failure_level=warning
  if ! upload "$path" "$name" "$size" "$sha" "$failure_level"; then
    [ "$failure_level" = warning ] || exit 1
    echo "::warning::$name upload failed - the release goes out without it"
    continue
  fi
  jq -n --arg name "$name" --argjson size "$size" --arg sha256 "$sha" \
    '{name: $name, size: $size, sha256: $sha256}' >>"$records"
  case "$name" in
    *.json) cp "$path" "$record_dir/$name" ;;
  esac
done
jq -s 'sort_by(.name)' "$records" >"$record_dir/uploaded-assets.json"
echo "Recorded $(jq length "$record_dir/uploaded-assets.json" | tr -d '\r') release assets in $record_dir"
