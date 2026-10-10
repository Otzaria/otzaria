#!/bin/sh
# The pinned assistant art (installer/assistant_art.pin.json) into <dest>: only the
# images the Linux assistant draws — icons, badges, logo, book frames; text is native.
#   sh fetch_art.sh <dest>
set -eu

here="$(cd "$(dirname "$0")" && pwd)"
pin="${OTZARIA_ASSISTANT_ART_PIN:-$here/../../../installer/assistant_art.pin.json}"
dest="${1:?usage: fetch_art.sh <dest>}"

field() {
  sed -n "s/^[[:space:]]*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$pin" | head -n 1
}
version="$(field version)"
url="$(field url)"
sha256="$(field sha256 | tr 'A-F' 'a-f')"
echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "fetch_art.sh: bad version in $pin: '$version'" >&2; exit 1; }
echo "$sha256" | grep -Eq '^[0-9a-f]{64}$' || { echo "fetch_art.sh: bad sha256 in $pin" >&2; exit 1; }
case "$url" in
  https://github.com/Otzaria/*) ;;
  *) echo "fetch_art.sh: url in $pin is not an Otzaria GitHub release: $url" >&2; exit 1 ;;
esac

# The stamp, not the presence of files, says which zip the folder came from.
stamp="$dest/.pinned-sha256"
if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$sha256" ]; then
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 30 --max-time 300 -o "$work/art.zip" "$url"
actual="$(sha256sum "$work/art.zip" | cut -d' ' -f1)"
if [ "$actual" != "$sha256" ]; then
  echo "fetch_art.sh: SHA-256 mismatch for $url: pinned $sha256, downloaded $actual" >&2
  exit 1
fi

mkdir -p "$work/zip" "$work/art"
unzip -q "$work/art.zip" -d "$work/zip"
# The .isi is written with CRLF line ends (it is read on Windows).
declared="$(tr -d '\r' < "$work/zip/assistant_art.isi" | sed -n 's/^#define AA_ART_VERSION "\(.*\)"/\1/p' | head -n 1)"
[ "$declared" = "$version" ] || { echo "fetch_art.sh: assistant_art.isi declares '$declared', but the pin is $version" >&2; exit 1; }

# 200% icons and badges (drawn at 40/72 px, sharp at scale 2); the book only exists at
# 250%.
cp "$work"/zip/ico_*_200.png "$work"/zip/badge_*_200.png \
  "$work"/zip/book_*_250.png "$work/art/"
printf '%s' "$sha256" > "$work/art/.pinned-sha256"

rm -rf "$dest"
mkdir -p "$(dirname "$dest")"
mv "$work/art" "$dest"
echo "Assistant art $version ($(ls "$dest" | wc -l | tr -d ' ') files) is in $dest"
