"""Apply the human review ledger to the baseline dictionary.

  py tool/acronyms_pipeline/merge.py --baseline baseline.json [--import export.csv ...] [--out assets/Acronyms.json]
  py tool/acronyms_pipeline/merge.py --baseline baseline.json --check          # verify assets/Acronyms.json = baseline + ledger

Ledger rows enter the dictionary if they are `approved` (a named human reviewer and a review date), or `agent_approved`
from a source flagged `merge_agent_checked` in data/sources.json (an AI agent checked the conversion of a human-written
reference; the row keeps its honest `agent:` reviewer id).  The baseline
is never rewritten: existing keys and meanings keep their order; a new meaning is appended to its key's list, a new key
is inserted at its alphabetical position.  The output is byte-for-byte reproducible from (baseline, ledger).
"""
import argparse
import bisect
import csv
import datetime
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import filters  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
LEDGER = os.path.join(HERE, "data", "decisions.csv")
SOURCES = os.path.join(HERE, "data", "sources.json")
REMOVALS = os.path.join(HERE, "data", "baseline_removals.csv")
REMOVAL_COLUMNS = ["key", "expansion", "reason"]
# Only these reasons delete a baseline meaning: the "meaning" is the key itself (or another acronym) and decodes nothing.
# Gematria values (ט״ו = חמישה עשר) stay listed in the CSV as suggestions; they can be useful and are not deleted.
REMOVAL_REASONS = {"same_as_key", "expansion_is_acronym", "structure_chars"}
COLUMNS = ["key", "expansion", "status", "source", "reference", "notes", "reviewer", "reviewed_at"]
STATUSES = {"pending", "approved", "agent_approved", "rejected", "needs_review"}
# Agent decisions stay in the review queue, except for sources flagged `merge_agent_checked` (see enters()).
INCLUDED = {"approved"}
REVIEWED = INCLUDED | {"agent_approved"}
AGENT_REVIEWER = re.compile(r"^agent:[\w.\-]+$")
# a reviewer id that names a tool or an AI agent can never approve
AUTOMATED_NAMES = ("claude", "gpt", "gemini", "opus", "sonnet", "haiku", "copilot", "codex", "chatbot", "robot", "agent",
                   "automat", "קלוד", "אוטומט", "סוכן", "רובוט")
AUTOMATED_WORDS = {"ai", "bot", "llm", "auto", "model", "script", "tool"}


def is_automated_reviewer(name):
    """True for a reviewer id that names a tool, a model or an agent (claude_code, Auto-Review, ChatGPT...)."""
    low = (name or "").lower()
    if any(n in low for n in AUTOMATED_NAMES):
        return True
    return bool(AUTOMATED_WORDS & set(re.split(r"[\W_]+", low)))


def valid_date(text):
    try:
        datetime.date.fromisoformat(text or "")
        return True
    except ValueError:
        return False


def load_sources():
    with open(SOURCES, encoding="utf-8") as f:
        return json.load(f)["sources"]


def read_ledger(path=LEDGER):
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8-sig", newline="") as f:  # -sig: review-page exports start with a BOM
        return [{k: (v or "") for k, v in row.items() if k} for row in csv.DictReader(f)]


def write_ledger(rows, path=LEDGER):
    rows = sorted(rows, key=lambda r: (filters.key_signature(r["key"]), filters.meaning_signature(r["expansion"])))
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, COLUMNS, lineterminator="\n", extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)


def read_removals(path=REMOVALS):
    """(key, meaning) pairs of the baseline that are dropped: meanings that decode nothing (see clean_baseline.py)."""
    if not os.path.exists(path):
        return set()
    with open(path, encoding="utf-8", newline="") as f:
        return {(r["key"], r["expansion"]) for r in csv.DictReader(f) if r["reason"] in REMOVAL_REASONS}


def ledger_id(row):
    return (filters.key_signature(row["key"]), filters.meaning_signature(row["expansion"]))


def import_exports(ledger, paths):
    """Merge review-page exports into the ledger; a later decision replaces an earlier one for the same pair."""
    by_id = {ledger_id(r): r for r in ledger}
    for p in paths:
        for row in read_ledger(p):
            row = {c: (row.get(c) or "").strip() for c in COLUMNS}
            if row["status"] == "pending":
                continue
            by_id[ledger_id(row)] = row
    return list(by_id.values())


def validate(rows, sources):
    """Returns a list of problems (empty = fine).  Strict for approved rows."""
    problems = []
    seen = set()
    for i, r in enumerate(rows, 2):
        where = f"decisions.csv:{i} {r['key']} / {r['expansion']}"
        if r["status"] not in STATUSES:
            problems.append(f"{where}: unknown status {r['status']!r}")
            continue
        if ledger_id(r) in seen:
            problems.append(f"{where}: duplicate decision")
        seen.add(ledger_id(r))
        if r["status"] not in REVIEWED:
            continue
        src = sources.get(r["source"])
        if src is None:
            problems.append(f"{where}: unknown source {r['source']!r}")
        elif src.get("status") != "allowed":
            problems.append(f"{where}: source {r['source']!r} is {src.get('status')}")
        if not r["reference"].strip():
            problems.append(f"{where}: approved without a reference")
        if r["status"] == "agent_approved":
            if not AGENT_REVIEWER.match(r["reviewer"]):
                problems.append(f"{where}: agent_approved needs reviewer 'agent:<model>' ({r['reviewer']!r})")
        elif not r["reviewer"].strip() or is_automated_reviewer(r["reviewer"]):
            problems.append(f"{where}: approved without a human reviewer ({r['reviewer']!r})")
        if not valid_date(r["reviewed_at"]):
            problems.append(f"{where}: approved without a valid review date (YYYY-MM-DD)")
        reasons, _, _ = filters.check_expansion(r["key"], r["expansion"])
        if reasons:
            problems.append(f"{where}: fails the noise filters: {','.join(reasons)}")
        if filters.normalize_key(r["key"]) != r["key"] or not filters.KEY_RE.match(r["key"]):
            problems.append(f"{where}: key is not in dictionary spelling (letters, gershayim before the last letters)")
        if filters.normalize_expansion(r["expansion"]) != r["expansion"]:
            problems.append(f"{where}: expansion is not normalised (invisible chars, nikud, quotes, edge punctuation)")
    return problems


def enters(row, sources, human_only=False):
    """`approved` (a named human) always enters.  `agent_approved` enters only when its source is flagged
    `merge_agent_checked` in sources.json: a published reference whose text was written by people and whose
    conversion an AI agent checked.  The flag is per source, so every such source is a visible, reviewable decision."""
    if row["status"] == "approved":
        return True
    return (row["status"] == "agent_approved" and not human_only and
            bool((sources or {}).get(row["source"], {}).get("merge_agent_checked")))


def apply(baseline, rows, human_only=False, removals=(), sources=None):
    """baseline: dict (ordered).  Returns (new dict, stats).

    `removals`: (key, meaning) pairs of the baseline to drop first; a key left without meanings is dropped too.
    Everything else keeps its order; a new meaning is appended, a new key is inserted alphabetically."""
    removals = set(removals)
    removed_pairs = removed_keys = 0
    if removals:
        pruned = {}
        for k, v in baseline.items():
            kept = [m for m in v if (k, m) not in removals]
            removed_pairs += len(v) - len(kept)
            if kept:
                pruned[k] = kept
            else:
                removed_keys += 1
        baseline = pruned
    approved = [r for r in rows if enters(r, sources, human_only)]
    approved.sort(key=lambda r: (r["key"], filters.meaning_signature(r["expansion"])))
    keys = list(baseline)
    out = {k: list(v) for k, v in baseline.items()}
    by_sig = {}
    for k in keys:
        by_sig.setdefault(filters.key_signature(k), []).append(k)
    sig_meanings = {}
    for k, v in out.items():
        sig_meanings.setdefault(filters.key_signature(k), set()).update(filters.meaning_signature(m) for m in v)
    new_keys, new_meanings, skipped = [], 0, 0
    for r in approved:
        sig = filters.key_signature(r["key"])
        ms = filters.meaning_signature(r["expansion"])
        if ms in sig_meanings.get(sig, ()):
            skipped += 1  # already present under that key (possibly spelled differently)
            continue
        sig_meanings.setdefault(sig, set()).add(ms)
        existing = by_sig.get(sig)
        if existing:
            out[existing[0]].append(r["expansion"])
            new_meanings += 1
        else:
            pos = bisect.bisect_right(keys, r["key"])
            keys.insert(pos, r["key"])
            by_sig[sig] = [r["key"]]
            out[r["key"]] = [r["expansion"]]
            new_keys.append(r["key"])
            new_meanings += 1
    ordered = {}
    for k in keys:
        ordered[k] = out[k]
    return ordered, {"approved_rows": len(approved), "human_approved_rows": sum(r["status"] == "approved" for r in approved),
                     "agent_approved_rows": sum(r["status"] == "agent_approved" for r in approved), "new_keys": len(new_keys), "new_meanings": new_meanings, "already_present": skipped,
                     "removed_meanings": removed_pairs, "removed_keys": removed_keys}


def dump(d):
    """Same layout as the shipped file: 4-space indent, CRLF, no trailing newline."""
    return json.dumps(d, ensure_ascii=False, indent=4).replace("\n", "\r\n").encode("utf-8")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--baseline", required=True, help="Acronyms.json as it is on the base branch (git show upstream/dev:assets/Acronyms.json)")
    ap.add_argument("--import", dest="imports", action="append", default=[], help="review-page export CSV to fold into the ledger")
    ap.add_argument("--out", help="write the merged dictionary here")
    ap.add_argument("--human-only", action="store_true", help="leave out agent_approved rows even from sources that are flagged merge_agent_checked")
    ap.add_argument("--check", action="store_true", help="verify that --target equals baseline + ledger")
    ap.add_argument("--target", default=os.path.join(HERE, "..", "..", "assets", "Acronyms.json"))
    a = ap.parse_args()

    sys.stdout.reconfigure(encoding="utf-8")
    ledger = read_ledger()
    if a.imports:
        ledger = import_exports(ledger, a.imports)
    problems = validate(ledger, load_sources())
    for p in problems:
        print("PROBLEM:", p)
    if problems:
        sys.exit(1)  # nothing is written: a bad row never reaches decisions.csv
    if a.imports:
        write_ledger(ledger)
        print(f"ledger updated: {len(ledger)} rows")
    with open(a.baseline, encoding="utf-8") as f:
        baseline = json.load(f)
    merged, stats = apply(baseline, ledger, a.human_only, read_removals(), load_sources())
    print(stats)
    data = dump(merged)
    if a.check:
        with open(a.target, "rb") as f:
            ok = f.read() == data
        print("target == baseline + ledger:", ok)
        sys.exit(0 if ok else 1)
    if a.out:
        with open(a.out, "wb") as f:
            f.write(data)
        print("wrote", a.out)


if __name__ == "__main__":
    main()
