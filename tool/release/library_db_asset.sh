#!/usr/bin/env bash
# The full library DB of a SeforimLibrary release, for packaging and CI.
#
#   library_db_asset.sh download <dir>        -> prints <dir>/seforim.db.zst or <dir>/seforim.zdb
#   library_db_asset.sh path <dir>            -> prints whichever of the two <dir> holds
#   library_db_asset.sh expand <asset> <out.db>
#
# Up to DB schema 5 the release asset is seforim.db.zst; from schema 6 it is
# seforim-schema<N>.zdb plus <name>.manifest.json (SeforimLibrary
# .github/scripts/db_asset_names.sh). The highest schema this app reads wins.
# A zdb is exported with zvfs_cli built from this checkout.
#
# LIBRARY_DB_RELEASE_TAG pins the release (one tag per workflow run; default latest);
# LIBRARY_DB_RELEASE_API overrides the release JSON URL (file:// in the tests);
# ZVFS_CLI points at a prebuilt zvfs_cli.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
release_tag=${LIBRARY_DB_RELEASE_TAG:-}
releases=https://api.github.com/repos/Otzaria/SeforimLibrary/releases
if [ -n "$release_tag" ]; then default_api="$releases/tags/$release_tag"; else default_api="$releases/latest"; fi
release_api=${LIBRARY_DB_RELEASE_API:-$default_api}
usage='usage: library_db_asset.sh download <dir> | path <dir> | expand <asset> <out.db>'

fail() { echo "::error::$*" >&2; exit 1; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

size_of() { wc -c < "$1" | tr -d ' '; }

max_readable_schema() {
  local schema
  schema=$(sed -nE 's/.*static const int readableDbSchemaVersion = ([0-9]+);.*/\1/p' \
    "$repo/lib/data/constants/database_constants.dart" | head -n1)
  [ -n "$schema" ] || fail "cannot read readableDbSchemaVersion from lib/data/constants/database_constants.dart"
  echo "$schema"
}

fetch() { # fetch <url> <out>
  local auth=()
  case "$1" in
    https://api.github.com/*)
      [ -z "${GH_TOKEN:-}" ] || auth=(-H "Authorization: Bearer $GH_TOKEN")
      ;;
  esac
  curl -fsSL --retry 3 --retry-delay 5 ${auth[@]+"${auth[@]}"} -o "$2" "$1"
}

cmd_path() {
  local dir=${1:?$usage} found=()
  [ ! -f "$dir/seforim.zdb" ] || found+=("$dir/seforim.zdb")
  [ ! -f "$dir/seforim.db.zst" ] || found+=("$dir/seforim.db.zst")
  [ "${#found[@]}" = 1 ] || fail "$dir must hold exactly one of seforim.zdb and seforim.db.zst (found ${#found[@]})"
  echo "${found[0]}"
}

cmd_download() {
  local dir=${1:?$usage} max_schema work selection
  max_schema=$(max_readable_schema)
  mkdir -p "$dir"
  work=$(mktemp -d "$dir/.library-db.XXXXXX")
  # shellcheck disable=SC2064
  trap "rm -rf '$work'" EXIT

  fetch "$release_api" "$work/release.json" || fail "cannot read the release from $release_api"
  # One |-separated line: tag, schema, name, url, size, digest, manifest url, manifest digest.
  selection=$(python3 - "$work/release.json" "$max_schema" <<'EOF'
import json, re, sys
release = json.load(open(sys.argv[1], encoding="utf-8"))
max_schema = int(sys.argv[2])
assets = {a["name"]: a for a in release.get("assets", [])}
best = None
unreadable = []
for name, asset in assets.items():
    if name == "seforim.db.zst":
        schema = 0  # schema <= 5; the name is reserved for it
    else:
        m = re.fullmatch(r"seforim-schema([1-9][0-9]*)\.zdb", name)
        if not m:
            continue
        schema = int(m.group(1))
        if schema > max_schema:
            unreadable.append(name)
            continue
    if best is None or schema > best[0]:
        best = (schema, asset)
if best is None:
    detail = " (only %s, above schema %d)" % (", ".join(unreadable), max_schema) if unreadable else ""
    sys.exit("release %s has no seforim.db.zst or seforim-schema<N>.zdb asset this app reads%s"
             % (release.get("tag_name"), detail))
schema, asset = best
manifest = assets.get(asset["name"] + ".manifest.json", {}) if schema else {}
print("|".join(str(v) for v in [
    release.get("tag_name") or "", schema, asset["name"], asset["browser_download_url"],
    asset["size"], asset.get("digest") or "",
    manifest.get("browser_download_url", ""), manifest.get("digest") or "",
]))
EOF
) || fail "no full library DB in $release_api"

  local tag schema name url size digest manifest_url manifest_digest local_name actual
  IFS='|' read -r tag schema name url size digest manifest_url manifest_digest <<< "$selection"
  if [ -n "$release_tag" ] && [ "$tag" != "$release_tag" ]; then
    fail "$release_api is release $tag, not the pinned $release_tag"
  fi
  if [ "$schema" = 0 ]; then local_name=seforim.db.zst; else local_name=seforim.zdb; fi
  echo "library DB: $name from release $tag ($size bytes)" >&2

  fetch "$url" "$work/$local_name" || fail "cannot download $name from $url"
  [ "$(size_of "$work/$local_name")" = "$size" ] || fail "$name downloaded as $(size_of "$work/$local_name") bytes but the release lists $size"
  actual=$(sha256_of "$work/$local_name")
  if [ -n "$digest" ]; then
    [ "sha256:$actual" = "$digest" ] || fail "$name hashes sha256:$actual but the release publishes $digest"
  fi

  if [ "$schema" != 0 ]; then
    [ -n "$manifest_url" ] || fail "release $tag publishes $name without $name.manifest.json"
    fetch "$manifest_url" "$work/manifest.json" || fail "cannot download $name.manifest.json"
    if [ -n "$manifest_digest" ]; then
      [ "sha256:$(sha256_of "$work/manifest.json")" = "$manifest_digest" ] \
        || fail "$name.manifest.json does not match the digest the release publishes"
    fi
    python3 - "$work/manifest.json" "$name" "$size" "$actual" "$schema" <<'EOF' || fail "$name does not match $name.manifest.json"
import json, sys
path, name, size, sha256, schema = sys.argv[1:]
m = json.load(open(path, encoding="utf-8"))
problems = [f"{key} is {m.get(key)!r}, expected {want!r}" for key, want in [
    ("manifestVersion", 1), ("file", name), ("size", int(size)),
    ("sha256", sha256), ("dbSchemaVersion", int(schema)),
] if m.get(key) != want]
if problems:
    sys.exit("; ".join(problems))
EOF
  fi

  rm -f "$dir/seforim.db.zst" "$dir/seforim.zdb"
  mv "$work/$local_name" "$dir/$local_name"
  echo "$dir/$local_name"
}

cmd_expand() {
  local asset=${1:?$usage} out=${2:?$usage} cli build_dir=
  [ -f "$asset" ] || fail "library DB asset not found: $asset"
  [ ! -e "$out" ] || fail "$out already exists"
  mkdir -p "$(dirname "$out")"
  case "$asset" in
    *.db.zst)
      # --memory raises zstd's refusal threshold for the 2 GiB window the stream declares.
      zstd -d -q -c --long=31 --memory=2048MB "$asset" > "$out.part"
      mv "$out.part" "$out"
      ;;
    *.zdb)
      cli=${ZVFS_CLI:-}
      if [ -z "$cli" ]; then
        build_dir=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/zvfs-cli.XXXXXX")
        cli="$build_dir/zvfs_cli"
        sh "$repo/packages/otzaria_zvfs/tool/build_cli.sh" "$cli" >&2
      fi
      "$cli" verify "$asset" >&2 || fail "$asset failed zvfs verify"
      "$cli" export "$asset" "$out" >&2 || fail "cannot export $asset"
      [ -z "$build_dir" ] || rm -rf "$build_dir"
      ;;
    *) fail "unknown library DB asset: $asset" ;;
  esac
}

case "${1:-}" in
  download) shift; cmd_download "$@" ;;
  path) shift; cmd_path "$@" ;;
  expand) shift; cmd_expand "$@" ;;
  *) fail "$usage" ;;
esac
