#!/usr/bin/env bash
# Fetch the prebuilt library search index that Otzaria/SeforimLibrary publishes
# alongside every database release, and verify it belongs to THIS build.
#
#   fetch_prebuilt_library_index.sh <index-dir> <seforim.db.zst> \
#       <talmud_bavli_latest.tar.zst> <pubspec.lock>
#
# רקע: בעבר כל בנייה הריצה `otzaria build-release-index` על כל הספרייה —
# ‏118 דקות מול 12 דקות לאותה חבילה בלי האינדקס (ריצה 34779834547), ושני jobs
# נוספים המתינו לה. האינדקס תלוי רק ב-seforim.db ובמנוע החיפוש, ולכן הוא נבנה
# פעם אחת אחרי שחרור הספרייה (ראה build-library-index.yml שם) ונשמר על אותו
# release. כאן רק מורידים אותו ומאמתים שהוא שייך בדיוק לבנייה הזאת.
set -euo pipefail

usage='usage: fetch_prebuilt_library_index.sh <index-dir> <seforim.db.zst> <talmud_bavli_latest.tar.zst> <pubspec.lock>'
index_dir=${1:?$usage}
database_archive=${2:?$usage}
talmud_archive=${3:?$usage}
pubspec_lock=${4:?$usage}

# The same release the database itself is taken from. Overridable so the
# packaging test can serve a fixture instead of the network.
base_url=${PREBUILT_LIBRARY_INDEX_BASE_URL:-https://github.com/Otzaria/SeforimLibrary/releases/latest/download}
provenance_name=otzaria-library-index.provenance.json
archive_name=otzaria-library-index.tar.zst
manifest_name="$archive_name.manifest.json"

fail() { echo "::error::$*" >&2; exit 1; }

[ -f "$database_archive" ] || fail "database archive not found: $database_archive"
[ -f "$talmud_archive" ] || fail "Talmud Bavli archive not found: $talmud_archive"
[ -f "$pubspec_lock" ] || fail "pubspec.lock not found: $pubspec_lock"
[ ! -e "$index_dir" ] || fail "index directory must not exist yet: $index_dir"

# Beside the target, never in /tmp: the parts, the reassembled archive and the
# expanded index are several GiB each, and a `mv` out of /tmp onto the workspace
# volume would copy the whole tree a second time.
mkdir -p "$(dirname "$index_dir")"
work=$(mktemp -d "$(dirname "$index_dir")/.prebuilt-index.XXXXXX")
trap 'rm -rf "$work"' EXIT

fetch() { # fetch <name>
  curl -fsSL --retry 3 --retry-delay 5 -o "$work/$1" "$base_url/$1" \
    || fail "cannot download $1 from $base_url — has build-library-index.yml run for this database release yet?"
}

hash_file() { sha256sum "$1" | awk '{print $1}'; }
hash_stdin() { sha256sum | awk '{print $1}'; }

fetch "$provenance_name"
read_provenance() { # read_provenance <jq-path>
  jq -er "$1" "$work/$provenance_name" \
    || fail "$provenance_name has no $1 — it was written by an older build-library-index.yml"
}

schema=$(read_provenance '.schemaVersion')
[ "$schema" = 1 ] || fail "$provenance_name is schemaVersion $schema; this build reads 1"

library_tag=$(read_provenance '.libraryReleaseTag')

# ‏1. האינדקס נבנה בדיוק מה-DB שנארז כאן. seforim.db.zst מגיע מ-
# releases/latest/download, ו-"latest" עלול להתחלף בין שתי ההורדות — ההשוואה
# הזו היא מה שהופך את הזוג לאטומי.
expected_database=$(read_provenance '.seforimDbZstSha256')
actual_database=$(hash_file "$database_archive")
[ "$expected_database" = "$actual_database" ] || fail \
  "the stored index was built from seforim.db.zst $expected_database (release $library_tag) but this build packages $actual_database — rerun build-library-index.yml in Otzaria/SeforimLibrary for the current database release"

# ‏2. סכמת האינדקס של המנוע שנפתר כאן. זו אותה השוואה שהאפליקציה עושה אצל
# המשתמש — גרסת חבילה שונה בלי שינוי סכמה אינה פוסלת (ה-lock אינו ב-git ו-^ נפתר מחדש).
expected_engine=$(read_provenance '.searchEngineVersion')
package_config="$(dirname "$pubspec_lock")/.dart_tool/package_config.json"
[ -f "$package_config" ] || fail "package_config.json not found next to $pubspec_lock — run flutter pub get first"
engine_root=$(jq -er '.packages[] | select(.name == "otzaria_search_engine") | .rootUri' "$package_config") \
  || fail "package_config.json resolves no otzaria_search_engine"
engine_root=${engine_root#file://}
engine_source="$engine_root/rust/src/api/search_engine.rs"
[ -f "$engine_source" ] || fail "search engine source not found: $engine_source"
engine_const() { # engine_const <NAME>
  sed -nE "s/^(pub(\([a-z]+\))? )?const $1: [^=]+= \"?([^\";]+)\"?;.*/\3/p" "$engine_source" | head -n1
}
required_format=$(engine_const INDEX_FORMAT)
required_schema=$(engine_const INDEX_SCHEMA_VERSION)
[ -n "$required_format" ] && [ -n "$required_schema" ] \
  || fail "cannot read INDEX_FORMAT / INDEX_SCHEMA_VERSION from $engine_source"

# ‏3. אותה קבוצת כרכי תלמוד. הכרכים אינם מאונדקסים, אבל הם יושבים בעץ הקטלוג
# ולכן קובעים את catalogueOrder — החצי העליון של כל מזהה מסמך. סט אחר מזיז את
# הסדר של כמעט כל הספרייה מול מה שהאפליקציה תחשב אצל המשתמש, והבדיקה שבאפליקציה
# משווה רק מספר רוויזיה ולכן לא הייתה תופסת זאת.
#
# ההשוואה היא על **שמות** הכרכים ולא על בתי הארכיון:
# ‏_addBundledTalmudBavliPdfBooksToCategory גוזר כל כותרת ב-getTitleFromPath
# וממקם אותה ליד ספר הטקסט בעל אותה כותרת. סריקה מחודשת של אותן מסכתות באיכות
# אחרת משנה כל בית בארכיון ואינה משנה דבר בסדר — ולכן אסור לה להפיל בנייה.
volume_names() { # volume_names <talmud tar.zst>  — חייב להיות זהה לצד הבונה
  zstd -d -c "$1" | tar -tf - | sed 's#.*/##' | grep -i '\.pdf$' | LC_ALL=C sort -u
}
expected_volumes_digest=$(read_provenance '.talmudVolumesDigest')
actual_volumes_digest=$(volume_names "$talmud_archive" | hash_stdin)
[ "$expected_volumes_digest" = "$actual_volumes_digest" ] || fail \
  "the stored index was built against a different set of bundled Talmud volumes ($(read_provenance '.talmudVolumes') of them, name-set $expected_volumes_digest; this build packages name-set $actual_volumes_digest) — rerun build-library-index.yml in Otzaria/SeforimLibrary so the catalogue order matches"

echo "Prebuilt index: release $library_tag, engine $expected_engine, $(jq -r '.catalogueBooks // "an unreported number of"' "$work/$provenance_name") books in the catalogue"

fetch "$manifest_name"
parts=$(jq -er '.parts[].name' "$work/$manifest_name") \
  || fail "$manifest_name lists no parts"
[ -n "$parts" ] || fail "$manifest_name lists no parts"
while IFS= read -r part; do
  [ "$part" = "$(basename "$part")" ] || fail "unsafe part name in manifest: $part"
  fetch "$part"
done <<< "$parts"

# assemble_split_asset.sh verifies every part and the reassembled archive
# against the manifest; this only pins the manifest itself to the provenance,
# so a manifest swapped for another release cannot pass.
bash "$(dirname "$0")/assemble_split_asset.sh" "$work/$manifest_name"
expected_archive=$(read_provenance '.indexArchiveSha256')
actual_archive=$(hash_file "$work/$archive_name")
[ "$expected_archive" = "$actual_archive" ] || fail \
  "$archive_name hashes $actual_archive but $provenance_name records $expected_archive"

mkdir -p "$work/extract"
# The parts are no longer needed and are the same size again as the archive.
rm -f "$work/$archive_name".part-*
zstd -d -c "$work/$archive_name" | tar -C "$work/extract" -xf -
rm -f "$work/$archive_name"
[ -d "$work/extract/index" ] || fail "$archive_name does not contain an index/ directory"
index_meta="$work/extract/index/otzaria_index_meta.json"
[ -f "$index_meta" ] || fail "$archive_name has no index/otzaria_index_meta.json"
found_format=$(jq -er '.format' "$index_meta") || fail "otzaria_index_meta.json has no format"
found_schema=$(jq -er '.schema_version' "$index_meta") || fail "otzaria_index_meta.json has no schema_version"
[ "$found_format" = "$required_format" ] && [ "$found_schema" = "$required_schema" ] || fail \
  "the stored index is $found_format schema $found_schema (engine $expected_engine) but this build's otzaria_search_engine requires $required_format schema $required_schema — rerun build-library-index.yml in Otzaria/SeforimLibrary with otzaria_run_id set to a build of this revision"
mv "$work/extract/index" "$index_dir"
[ -n "$(find "$index_dir" -mindepth 1 -maxdepth 1 -print -quit)" ] \
  || fail "the extracted index is empty"
echo "Prebuilt index installed at $index_dir ($(du -sh "$index_dir" | cut -f1))"
