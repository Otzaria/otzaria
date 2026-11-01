#!/usr/bin/env bash
# Prints <version>[.<hotfix>]+<run_number>, independently of the source ref.
# Mirrors release_tag.ps1. Hotfix 0 keeps the 3-part tag that older clients can parse.
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: release_tag.sh <version> <git-ref> <run-number>" >&2
    exit 2
fi
VERSION=$1
REF=$2
RUN_NUMBER=$3
VERSION_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/version.json"

if command -v jq &>/dev/null; then
    FIELDS=$(jq -r '"\(.version) \(.hotfix // 0)"' "$VERSION_FILE")
elif command -v python3 &>/dev/null; then
    FIELDS=$(python3 -c 'import json, sys; d = json.load(open(sys.argv[1], encoding="utf-8")); print(d["version"], d.get("hotfix", 0))' "$VERSION_FILE")
else
    echo "Error: jq or python3 is required to parse version.json" >&2
    exit 1
fi
read -r FILE_VERSION HOTFIX <<< "$FIELDS"

if [[ "$FILE_VERSION" != "$VERSION" ]]; then
    echo "Error: version.json has '$FILE_VERSION' but pubspec.yaml has '$VERSION'" >&2
    exit 1
fi
if ! [[ "$HOTFIX" =~ ^(0|[1-9][0-9]?)$ ]]; then
    echo "Error: hotfix must be an integer 0-99 (got '$HOTFIX')" >&2
    exit 1
fi

BASE="$VERSION"
if (( HOTFIX > 0 )); then
    BASE="$VERSION.$HOTFIX"
fi
echo "$BASE+$RUN_NUMBER"
