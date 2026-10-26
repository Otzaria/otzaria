#!/usr/bin/env bash
# Expand the downloaded library assets into the library folder that both the Linux FULL
# bundle and the regular installers' library asset ship, so the two cannot drift apart.
#
#   stage_bundled_library.sh <library_db-dir> <library-dir>
set -euo pipefail

usage='usage: stage_bundled_library.sh <library_db-dir> <library-dir>'
src=${1:?$usage}
dest=${2:?$usage}

mkdir -p "$dest"
zstd -d -c --long=31 --memory=2048MB "$src/seforim.db.zst" > "$dest/seforim.db"
zstd -d -c --long=31 --memory=2048MB "$src/otzar-HB_catalog.db.zst" > "$dest/otzar-HB_catalog.db"
zstd -d -c --long=31 --memory=2048MB "$src/talmud_bavli_latest.tar.zst" | tar -xf - -C "$dest"
# בלי קובץ הגרסה בתיקייה, בדיקת העדכון הראשונה של האפליקציה מורידה את
# התלמוד (~440MB) מחדש; ה-sha256 של הארכיון הוא ה-digest שהיא משווה מולו.
sha256sum "$src/talmud_bavli_latest.tar.zst" \
  | cut -d' ' -f1 > "$dest/תלמוד בבלי/.version"
# מילון החיפוש המקורב (lexical.db) — אינו דחוס, מועתק כמות שהוא ליד seforim.db.
cp "$src/lexical.db" "$dest/lexical.db"
# אותו כלל כמו בתלמוד: בלי סימון גרסה המילון (~57MB) יורד מחדש בבדיקה הראשונה.
sha256sum "$src/lexical.db" \
  | cut -d' ' -f1 > "$dest/lexical.db.version"
