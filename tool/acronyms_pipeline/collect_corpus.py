"""Find acronyms that are attested in the library text, and places where the text spells them out.

Two steps (the scan is slow: ~1 hour of CPU for the full library; run the shards in parallel):

  py -I collect_corpus.py scan  <shard> <nshards> <shard.pkl> --db seforim.db
  py -I collect_corpus.py merge <summary.json> <shard0.pkl> <shard1.pkl> ... --db seforim.db \
        [--sample-keys keys.txt --samples-out samples.json]

`scan` reads `line_content` of the library database read-only.  For every line it records
  - each acronym-looking token (letters, gershayim, one last letter): count, books, a few sample lines
  - each time the text itself expands one:  `רמב"ם (רבי משה בן מימון)`, `(ר"י) ... `, `ר"ל = ...`
    (only when the letters of the acronym fit the initials of the words, see filters.aligns)
`merge` joins the shards, adds book titles and short contexts, and writes the summary used by build_candidates.py.
"""
import argparse
import json
import os
import pickle
import re
import sqlite3
import sys

import zstandard as z

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import filters  # noqa: E402

HEB = "א-ת"
FOLD = filters.FOLD
PREF = filters.PREFIX_LETTERS
TAGS = re.compile(r"<[^>]*>")

TOKEN = re.compile(rf"(?<![{HEB}])([{HEB}]{{1,9}}\"[{HEB}])(?![{HEB}\"])")
WORD = re.compile(rf"^[{HEB}'\-]+$")
BRACKET_AFTER = re.compile(rf"([{HEB}]{{1,9}}\"[{HEB}])(?![{HEB}\"])\s*[\(\[]\s*([^\(\)\[\]\"]{{3,70}}?)\s*[\)\]]")
BRACKET_BEFORE = re.compile(rf"([{HEB}'\- ]{{3,80}}?)\s*[\(\[]\s*([{HEB}]{{1,9}}\"[{HEB}])\s*[\)\]]")
CONNECT_AFTER = re.compile(
    rf"([{HEB}]{{1,9}}\"[{HEB}])(?![{HEB}\"])\s*(?:היינו|דהיינו|הוא|הם|פירוש|פי'|פירושו|הכוונה|ר\"ל|כלומר|=|–|-|:)\s+([{HEB}'\- ]{{3,70}})"
)
CAP_BOOKS, CAP_SAMPLES = 40, 30


def _clean(t):
    t = filters.NIKUD.sub("", filters.clean_text(TAGS.sub(" ", t)))
    return t.replace("־", " ")  # maqaf separates words (בית־דין)


def words_of(s):
    out = []
    for w in s.strip(" .,;:!?()[]").split():
        w = w.strip(".,;:!?()[]")
        if not w or not WORD.match(w):
            return None
        out.append(w)
    return out


def resolve(token, words):
    """Key letters (prefix letters stripped) if the token's letters fit the words, else None."""
    letters = token.replace('"', "")  # final letters stay: the key is shown as written (רמב"ם)
    for cut in range(4):
        if cut and (len(letters) - cut < 2 or letters[cut - 1] not in PREF):
            break
        rest = letters[cut:]
        if 2 <= len(rest) <= len(words) * 2 and filters.aligns(rest, words):
            return rest
    return None


def open_db(path):
    c = sqlite3.connect(f"file:{path}?mode=ro&immutable=1", uri=True)
    dicts = {i: z.ZstdDecompressor(dict_data=z.ZstdCompressionDict(d)) for i, d in c.execute("select id,dict from zstd_dict")}
    return c, dicts


def line_text(blob, dicts, plain):
    if isinstance(blob, str):
        return blob
    fp = z.get_frame_parameters(blob)
    return (dicts.get(fp.dict_id) if fp.dict_id else plain).decompress(blob).decode("utf-8")


def scan(shard, nshards, out, db):
    c, dicts = open_db(db)
    plain = z.ZstdDecompressor()
    lo, hi = c.execute("select min(id), max(id) from line_content").fetchone()
    span = (hi - lo + 1 + nshards - 1) // nshards
    a, b = lo + shard * span, min(hi, lo + (shard + 1) * span - 1)
    tokens, expands = {}, {}
    nlines = 0
    cur = c.execute(
        "select lc.id, l.bookId, lc.content from line_content lc join line l on l.id = lc.id where lc.id between ? and ?", (a, b)
    )
    for lid, bid, blob in cur:
        nlines += 1
        if nlines % 500000 == 0:
            print(shard, nlines, flush=True)
        try:
            text = line_text(blob, dicts, plain)
        except Exception:
            continue
        if "״" not in text and '"' not in text:
            continue
        t = _clean(text)
        for m in TOKEN.finditer(t):
            key = m.group(1).replace('"', "")
            e = tokens.setdefault(key, [0, set(), []])
            e[0] += 1
            if len(e[1]) < CAP_BOOKS:
                e[1].add(bid)
            if len(e[2]) < CAP_SAMPLES:
                e[2].append((lid, bid))

        def record(token, words, pat):
            key = resolve(token, words)
            if not key:
                return
            ent = expands.setdefault((key, " ".join(words)), [0, set(), []])
            ent[0] += 1
            if len(ent[1]) < CAP_BOOKS:
                ent[1].add(bid)
            if len(ent[2]) < 5:
                ent[2].append((lid, bid, pat))

        for m in BRACKET_AFTER.finditer(t):
            ws = words_of(m.group(2))
            if ws and 2 <= len(ws) <= 8:
                record(m.group(1), ws, "after-bracket")
        for m in BRACKET_BEFORE.finditer(t):
            ws = words_of(m.group(1))
            if not ws:
                continue
            for n in range(2, min(8, len(ws)) + 1):
                if resolve(m.group(2), ws[-n:]):
                    record(m.group(2), ws[-n:], "before-bracket")
                    break
        for m in CONNECT_AFTER.finditer(t):
            ws = words_of(m.group(2))
            if not ws:
                continue
            for n in range(2, min(7, len(ws)) + 1):
                if resolve(m.group(1), ws[:n]):
                    record(m.group(1), ws[:n], "connector")
                    break
    with open(out, "wb") as f:
        pickle.dump({"range": (a, b), "lines": nlines, "tokens": tokens, "expands": expands}, f)
    print("done", shard, nlines, len(tokens), len(expands), flush=True)


def context(text, needle_re, width=(70, 90)):
    t = _clean(text)
    m = needle_re.search(t)
    if not m:
        return t[:160]
    return t[max(0, m.start() - width[0]): m.end() + width[1]].replace("\n", " ")


def merge(summary_path, shards, db, sample_keys=None, samples_out=None, min_token_count=3, min_expand_count=2):
    tokens, expands, lines = {}, {}, 0
    for p in shards:
        with open(p, "rb") as f:
            d = pickle.load(f)
        lines += d["lines"]
        for k, (n, books, samples) in d["tokens"].items():
            e = tokens.setdefault(k, [0, set(), []])
            e[0] += n
            e[1] |= books
            e[2] += [s for s in samples if len(e[2]) < CAP_SAMPLES]
        for k, (n, books, refs) in d["expands"].items():
            e = expands.setdefault(k, [0, set(), []])
            e[0] += n
            e[1] |= books
            e[2] += refs[: max(0, 5 - len(e[2]))]
    c, dicts = open_db(db)
    plain = z.ZstdDecompressor()
    titles = dict(c.execute("select id, title from book"))

    def fetch(lid):
        row = c.execute("select content from line_content where id=?", (lid,)).fetchone()
        return line_text(row[0], dicts, plain) if row else ""

    out_exp = []
    for (key, exp), (n, books, refs) in sorted(expands.items(), key=lambda kv: -kv[1][0]):
        if n < min_expand_count:
            continue
        shown = []
        for lid, bid, pat in refs[:3]:
            words = exp.split()
            needle = re.compile(r"\s+".join(map(re.escape, words)))
            shown.append({"book": titles.get(bid, str(bid)), "line": lid, "pattern": pat, "context": context(fetch(lid), needle)})
        out_exp.append({"key": key, "expansion": exp, "count": n, "books": len(books), "refs": shown})
    out_tok = {k: {"count": n, "books": len(b)} for k, (n, b, _) in tokens.items() if n >= min_token_count}
    with open(summary_path, "w", encoding="utf-8") as f:
        json.dump({"lines_scanned": lines, "tokens": out_tok, "expansions": out_exp}, f, ensure_ascii=False)
    print(f"{lines:,} lines; {len(out_tok):,} acronym tokens; {len(out_exp):,} explicit expansions -> {summary_path}")
    if sample_keys and samples_out:
        with open(sample_keys, encoding="utf-8") as f:
            wanted = {filters.key_signature(x.strip()) for x in f if x.strip()}
        res = {}
        for k in wanted:
            if k not in tokens:
                continue
            ctxs = []
            for lid, bid in tokens[k][2]:
                letters = k[:-1] + '"' + k[-1]
                ctxs.append(context(fetch(lid), re.compile(re.escape(letters))))
            res[k] = ctxs
        with open(samples_out, "w", encoding="utf-8") as f:
            json.dump(res, f, ensure_ascii=False)
        print(f"samples for {len(res):,} keys -> {samples_out}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("scan")
    s.add_argument("shard", type=int)
    s.add_argument("nshards", type=int)
    s.add_argument("out")
    s.add_argument("--db", required=True)
    m = sub.add_parser("merge")
    m.add_argument("summary")
    m.add_argument("shards", nargs="+")
    m.add_argument("--db", required=True)
    m.add_argument("--sample-keys")
    m.add_argument("--samples-out")
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    if a.cmd == "scan":
        scan(a.shard, a.nshards, a.out, a.db)
    else:
        merge(a.summary, a.shards, a.db, a.sample_keys, a.samples_out)


if __name__ == "__main__":
    main()
