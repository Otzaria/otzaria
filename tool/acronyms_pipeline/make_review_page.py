"""Build a single self-contained HTML page for the human review of candidates.

  py tool/acronyms_pipeline/make_review_page.py --candidates OUT/candidates.jsonl --out OUT/review.html [--tiers A,B,C]

The page runs locally (no server).  The reviewer types their name, approves / rejects each candidate and exports a CSV
that `merge.py --import` folds into data/decisions.csv.  Progress is kept in the browser's localStorage.
Nothing is approved by default, and a candidate that comes only from a Dicta lead cannot be approved without a
reference typed by the reviewer.
"""
import argparse
import json
import os
import sys

TEMPLATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "review_page.html")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--candidates", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--tiers", default="A,B,C", help="comma separated tiers to include (default A,B,C)")
    a = ap.parse_args()
    tiers = set(a.tiers.split(","))
    rows = []
    with open(a.candidates, encoding="utf-8") as f:
        for line in f:
            c = json.loads(line)
            if c["tier"] in tiers and c["status"] == "pending":
                rows.append({k: c[k] for k in ("id", "key", "expansion", "tier", "sources", "reference", "evidence", "flags",
                                               "existing", "key_count", "key_books", "count", "books", "cooccur")})
    with open(TEMPLATE, encoding="utf-8") as f:
        html = f.read()
    # "</" inside the JSON would end the script element early
    data = json.dumps(rows, ensure_ascii=False).replace("</", "<\\/").replace("<!--", "<\\!--")
    with open(a.out, "w", encoding="utf-8") as f:
        f.write(html.replace("/*__DATA__*/[]", data))
    sys.stdout.reconfigure(encoding="utf-8")
    print(f"{len(rows)} candidates -> {a.out}")


if __name__ == "__main__":
    main()
