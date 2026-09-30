#!/usr/bin/env bash
# בונה חבילות עדכון דיפרנציאליות לארכיטקטורה אחת: מול עד N השחרורים
# הקודמים שיש להם מניפסט, ובנוסף מול היציב האחרון — שבו נמצא רוב המשתמשים.
#
# כל מעבר מפיק **שתי** חבילות: ה-patch, שהלקוח מנסה קודם, ו-`-files` —
# אותם קבצים דחוסים במלואם, שממנה מושלם כל ערך שה-patch שלו אינו ישים.
#
# usage: build_update_packages.sh <arch> <new-tag> <new-manifest> <new-archive> <out-dir> [base-count]
#   UPDATE_PACKAGES_PLATFORM=windows (ברירת מחדל) | macos | linux
#   הארכיון: ה-ZIP הנייד ב-Windows, otzaria-macos.zip ב-macOS, וחבילת
#   ה-FULL ב-Linux — ממנה נפרס app/ בלבד.
#
# הכלי הוא אופטימיזציה: כישלון כאן משאיר את המשתמשים על המתקין המלא.
set -euo pipefail

arch=${1:?usage: build_update_packages.sh <arch> <new-tag> <new-manifest> <new-archive> <out-dir> [base-count]}
new_tag=${2:?missing new release tag}
new_manifest=${3:?missing new app file manifest}
new_zip=${4:?missing new release archive}
out_dir=${5:?missing output directory}
base_count=${6:-2}

source_repo=${UPDATE_PACKAGES_SOURCE_REPO:-Otzaria/otzaria}
platform=${UPDATE_PACKAGES_PLATFORM:-windows}
manifest_asset="otzaria-app-files-${platform}-${arch}.json"

# שם נכס הארכיון שממנו נפרס עץ ההתקנה של שחרור הבסיס.
case "$platform" in
  windows)
    base_asset="otzaria-windows.zip"
    [ "$arch" = "x64" ] || base_asset="otzaria-windows_${arch}.zip"
    ;;
  macos) base_asset="otzaria-macos.zip" ;;
  linux)
    base_asset="otzaria-linux-full.tar.zst"
    [ "$arch" = "x64" ] || base_asset="otzaria-linux-full-${arch}.tar.zst"
    ;;
  *) echo "::error::unknown platform $platform"; exit 1 ;;
esac

# פורס ארכיון (קובץ, או `-` לקלט רגיל) אל <dest> ומדפיס את שורש ההתקנה.
extract_tree() {
  local source=$1 dest=$2
  mkdir -p "$dest"
  case "$platform" in
    windows)
      unzip -q -o "$source" -d "$dest"
      echo "$dest"
      ;;
    macos)
      # bsdtar משחזר את ה-symlinks של ditto; __MACOSX נשאר מחוץ ל-.app.
      bsdtar -xf "$source" -C "$dest"
      find "$dest" -mindepth 1 -maxdepth 1 -name '*.app' -type d -print -quit
      ;;
    linux)
      # רק app/ — הספרייה המצורפת (כמעט 2GB) אינה נכתבת לדיסק.
      if [ "$source" = - ]; then
        zstd -dc --long=31 | tar -x -C "$dest" otzaria-linux-full/app
      else
        zstd -dc --long=31 "$source" | tar -x -C "$dest" otzaria-linux-full/app
      fi
      echo "$dest/otzaria-linux-full/app"
      ;;
  esac
}

[ -f "$new_manifest" ] || { echo "::warning::$new_manifest is missing - no update packages for $platform $arch"; exit 0; }

mkdir -p "$out_dir"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# חבילת FULL מעל 2 GiB מתפרסמת בחלקים (split_release_asset.sh) ומורכבת כאן.
assemble=$(dirname "$0")/assemble_split_asset.sh
if [ ! -f "$new_zip" ] && [ -f "$new_zip.manifest.json" ]; then
  bash "$assemble" "$new_zip.manifest.json" "$work/new-archive" >&2 \
    && new_zip="$work/new-archive"
fi
[ -f "$new_zip" ] || { echo "::warning::$new_zip is missing - no update packages for $platform $arch"; exit 0; }

new_root=$(extract_tree "$new_zip" "$work/new")
[ -n "$new_root" ] && [ -d "$new_root" ] || { echo "::warning::$new_zip holds no install tree"; exit 0; }

# השחרורים הקודמים, החדש ביותר תחילה, בלי טיוטות ובלי השחרור הנוכחי.
mapfile -t candidates < <(
  # לפי גרסה ולא לפי createdAt: הוא נגזר מהקומיט וחוזר על עצמו בין שחרורים,
  # ובשוויון הסדר שרירותי. ההשוואה מספרית ומרופדת ל-4 חלקים (0.9.97.2 > 0.9.97+789).
  gh release list --repo "$source_repo" --limit 40 \
    --json tagName,isDraft,isPrerelease \
    --jq 'map(select(.isDraft | not))
      | map(. + {key: (.tagName | sub("^v"; "") | split("+") as $p
          | (($p[0] | split(".") | map(try tonumber catch 0)) + [0, 0, 0, 0])[:4]
            + [($p[1] // "0") | try tonumber catch 0])})
      | sort_by(.key) | reverse
      | .[] | "\(.tagName) \(if .isPrerelease then "pre" else "stable" end)"' |
    awk -v current="$new_tag" '$1 != current'
)

built=0
stable_covered=false
for entry in "${candidates[@]}"; do
  tag=${entry% *}
  kind=${entry##* }
  # אחרי N הבסיסים ממשיכים רק עד היציב האחרון: בין שני יציבים יש לעיתים
  # כמה שחרורי dev, ובלעדיו משתמשי היציב לא היו מוצאים חבילה.
  if [ "$built" -ge "$base_count" ]; then
    [ "$stable_covered" = false ] && [ "$kind" = stable ] || continue
  fi
  base="$work/base"
  rm -rf "$base"
  mkdir -p "$base"

  if ! gh release download "$tag" --repo "$source_repo" \
    --pattern "$manifest_asset" --dir "$base" >/dev/null 2>&1; then
    echo "$tag has no $manifest_asset - skipping"
    continue
  fi

  if [ "$platform" = linux ] && gh release download "$tag" --repo "$source_repo" \
    --pattern "$base_asset.manifest.json" --dir "$base" >/dev/null 2>&1; then
    old_root=""
    if gh release download "$tag" --repo "$source_repo" \
      --pattern "$base_asset.part-*" --dir "$base" >/dev/null 2>&1 &&
      bash "$assemble" "$base/$base_asset.manifest.json" "$base/$base_asset" >&2; then
      rm -f "$base/$base_asset".part-*
      old_root=$(extract_tree "$base/$base_asset" "$base/root") || old_root=""
      rm -f "$base/$base_asset"
    fi
  elif [ "$platform" = linux ]; then
    old_root=$(gh release download "$tag" --repo "$source_repo" \
      --pattern "$base_asset" --output - 2>/dev/null |
      extract_tree - "$base/root") || old_root=""
  elif gh release download "$tag" --repo "$source_repo" \
    --pattern "$base_asset" --dir "$base" >/dev/null 2>&1; then
    old_root=$(extract_tree "$base/$base_asset" "$base/root") || old_root=""
    rm -f "$base/$base_asset"
  else
    old_root=""
  fi
  if [ -z "$old_root" ] || [ ! -d "$old_root" ]; then
    echo "::warning::$tag has $manifest_asset but no usable $base_asset - skipping"
    continue
  fi

  if ! dart run tool/release/generate_update_package.dart \
    --old-manifest "$base/$manifest_asset" --old-dir "$old_root" \
    --new-manifest "$new_manifest" --new-dir "$new_root" \
    --out-dir "$out_dir" --verify; then
    echo "::warning::could not build an update package from $tag - skipping"
    continue
  fi
  built=$((built + 1))
  [ "$kind" = stable ] && stable_covered=true
  [ "$built" -ge "$base_count" ] && [ "$stable_covered" = true ] && break
done

if [ "$built" -eq 0 ]; then
  echo "::warning::no update packages were built for $platform $arch"
fi
echo "built $built update package(s) for $platform $arch"
