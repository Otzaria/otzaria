"""Build a single self-contained HTML page for the human review of candidates.

  py tool/acronyms_pipeline/make_review_page.py --candidates OUT/candidates.jsonl --out OUT/review.html [--tiers A,B,C]

The page runs locally (no server).  The reviewer types their name, approves / rejects each candidate and exports a CSV
that `merge.py --import` folds into data/decisions.csv.  Progress is kept in the browser's localStorage.
Nothing is approved by default, and a candidate that comes only from a Dicta lead cannot be approved without a
reference typed by the reviewer.
"""
import argparse
import hashlib
import json
import os
import sys

import merge

TEMPLATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "review_page.html")


def ledger_candidates(ledger, baseline):
    existing = {}
    for key, meanings in baseline.items():
        existing.setdefault(merge.filters.key_signature(key), []).extend(meanings)
    rows = []
    for r in ledger:
        if r["status"] not in {"pending", "agent_approved", "needs_review"}:
            continue
        key, expansion = r["key"], r["expansion"]
        source = r["source"]
        reference = r["reference"]
        if source == "agent-verified-reference":
            source, reference = "human-verified-reference", ""
        rows.append({"id": hashlib.sha1(f"{merge.filters.key_signature(key)}|{merge.filters.meaning_signature(expansion)}".encode()).hexdigest()[:12],
                     "key": key, "expansion": expansion, "tier": "לבדיקה אנושית", "sources": [source],
                     "reference": reference, "evidence": [f"הצעה בלבד ({r['status']}): {r['notes']}"],
                     "flags": [], "existing": existing.get(merge.filters.key_signature(key), []),
                     "key_count": 0, "key_books": 0, "count": 0, "books": 0, "cooccur": 0})
    return rows


def main():
    ap = argparse.ArgumentParser()
    inputs = ap.add_mutually_exclusive_group(required=True)
    inputs.add_argument("--candidates")
    inputs.add_argument("--ledger", nargs="?", const=merge.LEDGER, help="prepare unverified ledger rows for human review")
    ap.add_argument("--baseline", default=os.path.join(merge.HERE, "..", "..", "assets", "Acronyms.json"))
    ap.add_argument("--offset", type=int, default=0)
    ap.add_argument("--limit", type=int, default=100, help="batch size (default 100)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--tiers", default="A,B,C", help="comma separated tiers to include (default A,B,C)")
    a = ap.parse_args()
    tiers = set(a.tiers.split(","))
    rows = []
    if a.offset < 0 or a.limit < 1:
        ap.error("offset must be non-negative and limit must be positive")
    if a.ledger:
        with open(a.baseline, encoding="utf-8") as f:
            rows = ledger_candidates(merge.read_ledger(a.ledger), json.load(f))
    else:
        with open(a.candidates, encoding="utf-8") as f:
            for line in f:
                c = json.loads(line)
                if c["tier"] in tiers and c["status"] == "pending":
                    rows.append({k: c[k] for k in ("id", "key", "expansion", "tier", "sources", "reference", "evidence", "flags",
                                                   "existing", "key_count", "key_books", "count", "books", "cooccur")})
    rows = rows[a.offset:a.offset + a.limit]
    with open(TEMPLATE, encoding="utf-8") as f:
        html = f.read()
    # Escape HTML delimiters without changing the JSON value.
    data = json.dumps(rows, ensure_ascii=False).replace("<", "\\u003c")
    with open(a.out, "w", encoding="utf-8") as f:
        f.write(html.replace("/*__DATA__*/[]", data).replace("acronyms-review-v1", "acronyms-review-" + hashlib.sha256(data.encode()).hexdigest()[:16]))
    sys.stdout.reconfigure(encoding="utf-8")
    print(f"{len(rows)} candidates -> {a.out}")


if __name__ == "__main__":
    main()
