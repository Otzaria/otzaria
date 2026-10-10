#!/usr/bin/env bash
# מושך את העיצוב הנעוץ של המסייע (installer/assistant_art.pin.json — המקום היחיד שנוקב בגרסה)
# ופורס ל-<dest> רק את מה שהמסייע ל-macOS מצייר כתמונה: סמלי הכרטיסים, תגי המצב ופריימי הספר.
# כל הטקסט מצויר בגופן המערכת, ולכן תמונות הכותרת של Windows אינן נפרסות.
#   bash tool/download_assistant/macos/fetch_art.sh <dest>
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIN="${OTZARIA_ASSISTANT_ART_PIN:-$HERE/../../../installer/assistant_art.pin.json}"
DEST="${1:?usage: fetch_art.sh <dest>}"

VERSION="$(plutil -extract version raw -o - "$PIN")"
URL="$(plutil -extract url raw -o - "$PIN")"
SHA256="$(plutil -extract sha256 raw -o - "$PIN" | tr 'A-F' 'a-f')"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "::error::bad version in $PIN: '$VERSION'" >&2; exit 1; }
[[ "$SHA256" =~ ^[0-9a-f]{64}$ ]] || { echo "::error::bad sha256 in $PIN" >&2; exit 1; }
[[ "$URL" == https://github.com/Otzaria/* ]] || { echo "::error::url in $PIN is not an Otzaria GitHub release: $URL" >&2; exit 1; }

# החותמת, ולא קיום הקבצים, אומרת מאיזה zip התיקייה הגיעה.
STAMP="$DEST/.pinned-sha256"
if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$SHA256" ]; then
  echo "Assistant art $VERSION is already in $DEST"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 30 --max-time 300 -o "$WORK/art.zip" "$URL"
ACTUAL="$(shasum -a 256 "$WORK/art.zip" | cut -d' ' -f1)"
if [ "$ACTUAL" != "$SHA256" ]; then
  echo "::error::SHA-256 mismatch for $URL: pinned $SHA256, downloaded $ACTUAL" >&2
  exit 1
fi

mkdir -p "$WORK/zip" "$WORK/art"
unzip -q "$WORK/art.zip" -d "$WORK/zip"
# ה-.isi נכתב בשורות CRLF (הוא נקרא ב-Windows).
DECLARED="$(tr -d '\r' < "$WORK/zip/assistant_art.isi" | sed -n 's/^#define AA_ART_VERSION "\(.*\)"/\1/p' | head -1)"
[ "$DECLARED" = "$VERSION" ] || { echo "::error::assistant_art.isi declares '$DECLARED', but the pin is $VERSION" >&2; exit 1; }

# Retina: סמלים ותגים ב-200%, הספר ב-250% מוקטן ל-440 פיקסלים (220 נקודות ב-2x).
cp "$WORK"/zip/ico_*_200.png "$WORK"/zip/badge_*_200.png "$WORK/art/"
for frame in "$WORK"/zip/book_*_250.png; do
  sips -Z 440 "$frame" --out "$WORK/art/$(basename "$frame")" >/dev/null
done
printf '%s' "$SHA256" > "$WORK/art/.pinned-sha256"

rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
mv "$WORK/art" "$DEST"
echo "Assistant art $VERSION ($(ls "$DEST" | wc -l | tr -d ' ') files) is in $DEST"
