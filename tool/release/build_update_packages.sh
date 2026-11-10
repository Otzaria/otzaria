#!/usr/bin/env bash
# בונה חבילות עדכון דיפרנציאליות לארכיטקטורה אחת: מול עד N השחרורים
# הקודמים שיש להם מניפסט, ובנוסף מול Latest — שבו נמצא רוב המשתמשים.
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

# חלקי בסיס Linux מוזרמים לאותו מפענח; רק app/ נכתב לדיסק.
download_linux_base() {
  local manifest="$base/$base_asset.manifest.json"
  if gh release download "$tag" --repo "$source_repo" \
    --pattern "$base_asset.manifest.json" --dir "$base" >/dev/null 2>&1; then
    python3 "$(dirname "$0")/stream_split_release_asset.py" \
      "$tag" "$source_repo" "$manifest" "$base_asset"
  else
    gh release download "$tag" --repo "$source_repo" \
      --pattern "$base_asset" --output - 2>/dev/null
  fi
}

[ -f "$new_manifest" ] || { echo "::warning::$new_manifest is missing - no update packages for $platform $arch"; exit 0; }
[ -f "$new_zip" ] || { echo "::warning::$new_zip is missing - no update packages for $platform $arch"; exit 0; }

mkdir -p "$out_dir"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

new_root=$(extract_tree "$new_zip" "$work/new")
[ -n "$new_root" ] && [ -d "$new_root" ] || { echo "::warning::$new_zip holds no install tree"; exit 0; }

latest_tag=$(gh api "repos/$source_repo/releases/latest" --jq .tag_name)
# השחרורים הקודמים נשארים בסיסים גם אם לא היו Latest.
mapfile -t candidates < <(
  # לפי גרסה ולא לפי createdAt: הוא נגזר מהקומיט וחוזר על עצמו בין שחרורים,
  # ובשוויון הסדר שרירותי. ההשוואה מספרית ומרופדת ל-4 חלקים (0.9.97.2 > 0.9.97+789).
  gh release list --repo "$source_repo" --limit 40 \
    --json tagName,isDraft \
    --jq 'map(select(.isDraft | not))
      | map(. + {key: (.tagName | sub("^v"; "") | split("+") as $p
          | (($p[0] | split(".") | map(try tonumber catch 0)) + [0, 0, 0, 0])[:4]
            + [($p[1] // "0") | try tonumber catch 0])})
      | sort_by(.key) | reverse
      | .[].tagName' |
    awk -v current="$new_tag" '$1 != current'
)

if [ "$latest_tag" != "$new_tag" ] && ! printf '%s\n' "${candidates[@]}" | grep -Fxq "$latest_tag"; then
  candidates+=("$latest_tag")
fi
built=0
latest_covered=false
for tag in "${candidates[@]}"; do
  # אחרי N בסיסים נדרש גם Latest, אף כשאינו בין 40 השחרורים האחרונים.
  if [ "$built" -ge "$base_count" ]; then
    [ "$latest_covered" = false ] && [ "$tag" = "$latest_tag" ] || continue
  fi
  base="$work/base"
  rm -rf "$base"
  mkdir -p "$base"

  if ! gh release download "$tag" --repo "$source_repo" \
    --pattern "$manifest_asset" --dir "$base" >/dev/null 2>&1; then
    echo "$tag has no $manifest_asset - skipping"
    continue
  fi

  if [ "$platform" = linux ]; then
    old_root=$(download_linux_base |
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

  # הגנרטור הוא Dart בלבד; dart run מפעיל גם build hooks של האפליקציה.
  if ! dart tool/release/generate_update_package.dart \
    --old-manifest "$base/$manifest_asset" --old-dir "$old_root" \
    --new-manifest "$new_manifest" --new-dir "$new_root" \
    --out-dir "$out_dir" --verify; then
    echo "::warning::could not build an update package from $tag - skipping"
    continue
  fi
  built=$((built + 1))
  [ "$tag" = "$latest_tag" ] && latest_covered=true
  [ "$built" -ge "$base_count" ] && [ "$latest_covered" = true ] && break
done

if [ "$built" -eq 0 ]; then
  echo "::warning::no update packages were built for $platform $arch"
fi
echo "built $built update package(s) for $platform $arch"
