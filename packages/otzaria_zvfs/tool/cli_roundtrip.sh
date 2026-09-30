#!/usr/bin/env sh
# Roundtrip of a built zvfs_cli: fixture -> convert -> verify -> info -> export,
# byte-equal to the source; train, --dict-file, freelist zeroing, compact.
# Usage: tool/cli_roundtrip.sh <zvfs_cli>
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

# a path outside the ANSI code page (Windows takes the arguments as UTF-16)
# shellcheck disable=SC2086
"$cli" convert "$dir/src.db" "$dir/ספר.zdb" --dict seforim-v1 --level 3 $det
cmp "$dir/a.zdb" "$dir/ספר.zdb"
"$cli" verify "$dir/ספר.zdb"

# training is reproducible; a trained dictionary goes in with --dict-file
"$cli" train "$dir/src.db" "$dir/t1.dict" 600 16 7 --fastcover --k 200 --d 8
"$cli" train "$dir/src.db" "$dir/t2.dict" 600 16 7 --fastcover --k 200 --d 8
cmp "$dir/t1.dict" "$dir/t2.dict"
"$cli" train "$dir/src.db" "$dir/l1.inc" 600 16 7 --name test-v9
"$cli" train "$dir/src.db" "$dir/l2.inc" 600 16 7 --name test-v9
cmp "$dir/l1.inc" "$dir/l2.inc"
grep -q 'k_test_v9\[' "$dir/l1.inc"
# shellcheck disable=SC2086
"$cli" convert "$dir/src.db" "$dir/d.zdb" --dict-file "$dir/t1.dict" --level 3 $det
"$cli" verify "$dir/d.zdb"
"$cli" info --json "$dir/d.zdb" > "$dir/dinfo.json"
python3 - "$dir/dinfo.json" "$dir/t1.dict" <<'EOF'
import json, os, sys
i = json.load(open(sys.argv[1]))
d = open(sys.argv[2], "rb").read()
assert i["dictName"] == "t1" and i["dictLength"] == len(d), i
assert i["dictId"] == int.from_bytes(d[4:8], "little") and i["dictId"] > 0, i
print("dict-file ok:", i["dictName"], i["dictId"], i["dictLength"])
EOF
"$cli" export "$dir/d.zdb" "$dir/d.db"
cmp "$dir/src.db" "$dir/d.db"

# freelist leaves: zeroed by default, kept with --keep-freelist
cp "$dir/src.db" "$dir/fl.db"
python3 -c "import sqlite3, sys; d = sqlite3.connect(sys.argv[1]); d.execute('DELETE FROM line WHERE id > 6000'); d.commit()" "$dir/fl.db"
# shellcheck disable=SC2086
"$cli" convert "$dir/fl.db" "$dir/fl.zdb" --level 3 $det | tee "$dir/fl.out"
grep -Eq ' [1-9][0-9]* freelist pages zeroed' "$dir/fl.out"
"$cli" export "$dir/fl.zdb" "$dir/fl_out.db"
# shellcheck disable=SC2086
"$cli" convert "$dir/fl.db" "$dir/flk.zdb" --level 3 --keep-freelist $det
"$cli" export "$dir/flk.zdb" "$dir/flk_out.db"
cmp "$dir/fl.db" "$dir/flk_out.db"
python3 - "$dir/fl.db" "$dir/fl_out.db" <<'EOF'
import sqlite3, sys
def dump(p):
    d = sqlite3.connect(p)
    assert d.execute("PRAGMA integrity_check").fetchone()[0] == "ok", p
    return list(d.iterdump()), d.execute("PRAGMA freelist_count").fetchone()[0]
a, b = dump(sys.argv[1]), dump(sys.argv[2])
assert a == b and a[1] > 0, (len(a[0]), len(b[0]), a[1], b[1])
print("freelist ok:", a[1], "free pages")
EOF

# compaction without an overlay: same content, every frame but the first copied
"$cli" compact "$dir/fl.zdb" "$dir/flc.zdb" --level 3 | tee "$dir/flc.out"
grep -q ' freelist pages zeroed' "$dir/flc.out"
"$cli" verify "$dir/flc.zdb"
"$cli" export "$dir/flc.zdb" "$dir/flc_out.db"
cmp "$dir/fl_out.db" "$dir/flc_out.db"

# export refuses a base with an overlay
: > "$dir/a.zdb-zovl"
if "$cli" export "$dir/a.zdb" "$dir/out2.db" 2>/dev/null; then
  echo "export accepted a base with an overlay" >&2
  exit 1
fi
echo "cli roundtrip ok"
