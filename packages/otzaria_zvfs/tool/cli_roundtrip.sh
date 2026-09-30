#!/usr/bin/env sh
# Roundtrip of a built zvfs_cli: fixture -> convert -> verify -> info -> export,
# byte-equal to the source. Usage: tool/cli_roundtrip.sh <zvfs_cli>
set -eu

cli=$1
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

python3 - "$dir/src.db" <<'EOF'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.executescript("""
PRAGMA page_size=4096;
CREATE TABLE book(id INTEGER PRIMARY KEY, title TEXT);
CREATE TABLE line(id INTEGER PRIMARY KEY, bookId INT, content TEXT, extra BLOB);
CREATE INDEX idx_line ON line(bookId);
""")
word = "שלום "
db.executemany("INSERT INTO book VALUES(?,?)", [(i, "book %d" % i) for i in range(1, 51)])
db.executemany("INSERT INTO line VALUES(?,?,?,?)", [
    (i, i % 50, "line %d %s" % (i, word * (i % 40)),
     bytes((i * 7 + k) % 256 for k in range(3000)) if i % 97 == 0 else None)
    for i in range(1, 20001)])
db.commit()
db.close()
EOF

det="--uuid-from-content --created-ms 0"
# shellcheck disable=SC2086
"$cli" convert "$dir/src.db" "$dir/a.zdb" --dict seforim-v1 --level 3 --threads 4 $det
"$cli" verify "$dir/a.zdb"
"$cli" info --json "$dir/a.zdb" > "$dir/info.json"
python3 - "$dir/info.json" "$dir/src.db" <<'EOF'
import json, os, sys
i = json.load(open(sys.argv[1]))
assert i["formatMajor"] == 1 and i["formatMinor"] >= 2, i
assert i["dictName"] == "seforim-v1" and i["dictId"] > 0, i
assert len(i["fileUuid"]) == 32 and len(i["contentXxh64"]) == 16, i
assert i["logicalSize"] == os.path.getsize(sys.argv[2]) and i["pageSize"] == 4096, i
assert i["level"] == 3 and i["createdUnixMs"] == 0, i
assert i["lockGap"] is False and i["gapStart"] == 0 and i["gapEnd"] == 0, i
assert i["overlay"]["present"] is False, i
print("info ok:", i["fileUuid"], i["contentXxh64"])
EOF
"$cli" export "$dir/a.zdb" "$dir/out.db"
cmp "$dir/src.db" "$dir/out.db"

# reproducible output: the thread count does not change a byte
# shellcheck disable=SC2086
"$cli" convert "$dir/src.db" "$dir/b.zdb" --dict seforim-v1 --level 3 --threads 1 $det
cmp "$dir/a.zdb" "$dir/b.zdb"
if command -v zstd >/dev/null 2>&1; then
  zstd -q "$dir/src.db" -o "$dir/src.db.zst"
  # shellcheck disable=SC2086
  "$cli" convert - "$dir/c.zdb" --zstd --level 3 $det < "$dir/src.db.zst"
  cmp "$dir/a.zdb" "$dir/c.zdb"
fi

# export refuses a base with an overlay
: > "$dir/a.zdb-zovl"
if "$cli" export "$dir/a.zdb" "$dir/out2.db" 2>/dev/null; then
  echo "export accepted a base with an overlay" >&2
  exit 1
fi
echo "cli roundtrip ok"
