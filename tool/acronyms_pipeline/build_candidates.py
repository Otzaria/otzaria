"""Turn raw source material into a deduplicated, filtered list of review candidates.

  py tool/acronyms_pipeline/build_candidates.py --baseline baseline.json --out-dir OUT \
      --jastrow jastrow_raw.json --corpus corpus_summary.json [--leads leads.jsonl --samples samples.json]

Nothing produced here is approved.  Every candidate is written with status `pending`; only a human decision in
data/decisions.csv (see merge.py) can put a meaning into the dictionary.

Outputs (in OUT): candidates.jsonl, review.csv (Hebrew columns), report.json, report.md
"""
import argparse
import collections
import csv
import hashlib
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import filters  # noqa: E402
import merge  # noqa: E402

JASTROW_REF = "Jastrow, Hebrew or Aramaic Abbreviations, שורה {line}"
SPAN = re.compile(r'<span dir="rtl">(.*?)</span>')
ENTRY = re.compile(r'^\s*<span dir="rtl">(.*?)</span>\s*=\s*(.*)$')

# thresholds for corpus-derived candidates
MIN_COUNT, MIN_BOOKS = 3, 3
STRONG_COUNT, STRONG_BOOKS = 6, 4
# thresholds for Dicta leads (attestation of the acronym itself)
LEAD_MIN_COUNT, LEAD_MIN_BOOKS, LEAD_MAX_OPTIONS = 5, 3, 3
LEAD_COOCCUR = 2


def cid(key, expansion):
    return hashlib.sha1(f"{filters.key_signature(key)}|{filters.meaning_signature(expansion)}".encode()).hexdigest()[:12]


# ------------------------------------------------------------------------------------------------------------
# sources
# ------------------------------------------------------------------------------------------------------------
def read_jastrow(path):
    with open(path, encoding="utf-8") as f:
        lines = json.load(f)
    for row in lines:
        m = ENTRY.match(row["raw"])
        if not m:
            continue
        for exp in SPAN.findall(m.group(2)):
            yield {
                "key": m.group(1),
                "expansion": exp,
                "source": "jastrow-sefaria",
                "reference": JASTROW_REF.format(line=row["line"]),
                "evidence": [],
            }


def read_corpus(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    for e in data["expansions"]:
        if e["count"] < MIN_COUNT or e["books"] < MIN_BOOKS:
            continue
        refs = e["refs"]
        yield {
            "key": e["key"],
            "expansion": e["expansion"],
            "source": "otzaria-corpus",
            "reference": "; ".join(f"{r['book']} (שורה {r['line']})" for r in refs[:2]),
            "evidence": [f"{r['book']}: …{r['context']}…" for r in refs[:3]],
            "count": e["count"],
            "books": e["books"],
        }
    return


def read_leads(path, tokens, samples):
    """Dicta options for acronyms that really occur in the library.  Leads only."""
    with open(path, encoding="utf-8") as f:
        for line in f:
            row = json.loads(line)
            key = row["key"]
            stat = tokens.get(filters.key_signature(key))
            if not stat or stat["count"] < LEAD_MIN_COUNT or stat["books"] < LEAD_MIN_BOOKS:
                continue
            for exp in row["options"][:LEAD_MAX_OPTIONS]:
                yield {
                    "key": key,
                    "expansion": exp,
                    "source": "dicta-lead",
                    "reference": "",
                    "evidence": [],
                    "samples": samples.get(filters.key_signature(key), []),
                }


# ------------------------------------------------------------------------------------------------------------
# helpers
# ------------------------------------------------------------------------------------------------------------
def cooccurs(expansion, contexts):
    """How many of the sample lines that contain the acronym also contain the expansion phrase (prefix tolerant)."""
    words = filters.meaning_signature(expansion).split()
    if not words:
        return 0
    pat = re.compile(r"(?<![א-ת])[" + filters.PREFIX_LETTERS + r"]?" + r"\s+".join(map(re.escape, words)))
    n = 0
    for ctx in contexts:
        if pat.search(filters.meaning_signature(ctx)):
            n += 1
    return n


def prefix_variant_of_baseline(key, expansion, base_sigs):
    """True when key = prefix letters + an existing key and the meaning is just the same meaning with that prefix
    (ובהגר"א = ובהגאון רבי אליהו).  The app does not need such duplicates."""
    letters = filters.key_signature(key)
    cand = filters.meaning_signature(expansion)
    for cut in (1, 2, 3):
        if len(letters) - cut < 2 or letters[cut - 1] not in filters.PREFIX_LETTERS:
            break
        meanings = base_sigs.get(letters[cut:])
        if not meanings:
            continue
        stripped = cand
        for _ in range(cut):
            if stripped and stripped[0] in filters.PREFIX_LETTERS:
                stripped = stripped[1:]
        if cand in meanings or stripped in meanings:
            return True
    return False


# ------------------------------------------------------------------------------------------------------------
# main
# ------------------------------------------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--baseline", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--jastrow")
    ap.add_argument("--corpus")
    ap.add_argument("--leads")
    ap.add_argument("--samples")
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    os.makedirs(a.out_dir, exist_ok=True)

    with open(a.baseline, encoding="utf-8") as f:
        baseline = json.load(f)
    base_sigs = collections.defaultdict(set)
    base_plene = collections.defaultdict(set)
    base_display = {}
    for k, v in baseline.items():
        s = filters.key_signature(k)
        base_sigs[s].update(filters.meaning_signature(m) for m in v)
        base_plene[s].update(filters.plene_signature(m) for m in v)
        base_display.setdefault(s, []).extend(v)

    tokens, samples = {}, {}
    corpus = None
    if a.corpus:
        with open(a.corpus, encoding="utf-8") as f:
            corpus = json.load(f)
        tokens = corpus["tokens"]
    if a.samples:
        with open(a.samples, encoding="utf-8") as f:
            samples = json.load(f)

    raw = []
    if a.jastrow:
        raw += list(read_jastrow(a.jastrow))
    if a.corpus:
        raw += list(read_corpus(a.corpus))
    if a.leads:
        raw += list(read_leads(a.leads, tokens, samples))

    ledger = merge.read_ledger()
    problems = merge.validate(ledger, merge.load_sources())
    if problems:
        sys.exit("decisions.csv is invalid:\n" + "\n".join(problems))
    decided = {merge.ledger_id(r): r for r in ledger}

    rejected = collections.Counter()
    rejected_by_source = collections.defaultdict(collections.Counter)
    collected = collections.Counter(r["source"] for r in raw)
    grouped = {}
    examples = collections.defaultdict(list)

    def reject(reason, src, key, exp):
        rejected[reason] += 1
        rejected_by_source[src][reason] += 1
        if len(examples[reason]) < 6:
            examples[reason].append(f"{key} ← {exp}")

    for r in raw:
        key = filters.normalize_key(r["key"])
        if not filters.KEY_RE.match(key) or len(filters.key_signature(key)) < 2:
            reject("bad_key", r["source"], r["key"], r["expansion"])
            continue
        reasons, flags, exp = filters.check_expansion(key, r["expansion"])
        if reasons:
            for why in reasons:
                reject(why, r["source"], key, r["expansion"])
            continue
        sig = filters.key_signature(key)
        msig = filters.meaning_signature(exp)
        if msig in base_sigs.get(sig, ()):
            reject("duplicate_existing", r["source"], key, exp)
            continue
        if filters.plene_signature(exp) in base_plene.get(sig, ()):
            reject("spelling_variant_existing", r["source"], key, exp)
            continue
        if prefix_variant_of_baseline(key, exp, base_sigs):
            reject("prefix_variant", r["source"], key, exp)
            continue
        if r["source"] == "dicta-lead" and "letters_do_not_align" in flags:
            reject("lead_letters_do_not_align", r["source"], key, exp)
            continue
        gk = (sig, filters.plene_signature(exp))
        c = grouped.get(gk)
        if c is None:
            c = grouped[gk] = {
                "id": cid(key, exp),
                "key": key,
                "expansion": exp,
                "sources": [],
                "reference": "",
                "evidence": [],
                "flags": set(),
                "count": 0,
                "books": 0,
                "cooccur": 0,
            }
        else:
            rejected["duplicate_in_run"] += 1
            rejected_by_source[r["source"]]["duplicate_in_run"] += 1
        if r["source"] not in c["sources"]:
            c["sources"].append(r["source"])
        c["flags"].update(flags)
        if r["source"] != "dicta-lead" and r["reference"]:
            c["reference"] = (c["reference"] + " | " if c["reference"] else "") + r["reference"]
        c["evidence"] += [e for e in r["evidence"] if e not in c["evidence"]]
        c["count"] = max(c["count"], r.get("count", 0))
        c["books"] = max(c["books"], r.get("books", 0))
        if r["source"] == "dicta-lead":
            c["cooccur"] = max(c["cooccur"], cooccurs(exp, r["samples"]))
            for ctx in r["samples"][:3]:
                if len(c["evidence"]) < 3:
                    c["evidence"].append(f"הקשר לדוגמה: …{ctx}…")

    cands = []
    for c in grouped.values():
        stat = tokens.get(filters.key_signature(c["key"]))
        c["key_count"], c["key_books"] = (stat["count"], stat["books"]) if stat else (0, 0)
        srcs = set(c["sources"])
        if "jastrow-sefaria" in srcs:
            tier = "A"
        elif "otzaria-corpus" in srcs and c["count"] >= STRONG_COUNT and c["books"] >= STRONG_BOOKS:
            tier = "A"
        elif "otzaria-corpus" in srcs:
            tier = "B"
        elif c["cooccur"] >= LEAD_COOCCUR:
            tier = "C"
        else:
            tier = "D"
        c["tier"] = tier
        c["flags"] = sorted(c["flags"])
        c["existing"] = base_display.get(filters.key_signature(c["key"]), [])
        c["status"] = "pending"
        d = decided.get((filters.key_signature(c["key"]), filters.meaning_signature(c["expansion"])))
        if d:
            c["status"] = d["status"]
        cands.append(c)
    cands.sort(key=lambda c: (c["tier"], -c["key_count"], c["key"], c["expansion"]))

    with open(os.path.join(a.out_dir, "candidates.jsonl"), "w", encoding="utf-8") as f:
        for c in cands:
            f.write(json.dumps(c, ensure_ascii=False) + "\n")

    tier_names = {"A": "א: ג'סטרו או פענוח מפורש בכמה ספרים", "B": "ב: פענוח מפורש בספרייה", "C": "ג: רמז דיקטה + הופעה משותפת בטקסט",
                  "D": "ד: רמז דיקטה בלבד (עדיפות נמוכה)"}
    with open(os.path.join(a.out_dir, "review.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["מזהה", "דרגה", "ראשי תיבות", "פענוח מוצע", "פירושים קיימים במילון", "מקור", "אסמכתה", "הקשר מהספרייה",
                    "הופעות בספרייה", "דגלים", "סטטוס", "בודק", "תאריך אישור", "הערות"])
        for c in cands:
            w.writerow([c["id"], tier_names[c["tier"]], c["key"], c["expansion"], " | ".join(c["existing"][:6]), ", ".join(c["sources"]),
                        c["reference"], " || ".join(c["evidence"][:2]), c["key_count"], ", ".join(c["flags"]), c["status"], "", "", ""])

    base_meanings = sum(len(v) for v in baseline.values())
    status = collections.Counter(c["status"] for c in cands)
    approved_rows = [r for r in ledger if r["status"] == "approved"]
    merged, stats = merge.apply(baseline, ledger)
    # the baseline must survive untouched: every original meaning stays, in the same order
    changed = [k for k, v in baseline.items() if merged.get(k, [])[: len(v)] != v]
    no_reference = sum(1 for c in cands if not c["reference"])
    report = {
        "baseline_keys": len(baseline),
        "baseline_meanings": base_meanings,
        "collected_by_source": dict(collected),
        "collected_total": len(raw),
        "rejected_by_reason": dict(rejected.most_common()),
        "rejected_by_source": {s: dict(c.most_common()) for s, c in rejected_by_source.items()},
        "rejected_examples": dict(examples),
        "candidates_total": len(cands),
        "candidates_by_tier": dict(collections.Counter(c["tier"] for c in cands)),
        "candidates_by_source": dict(collections.Counter("+".join(c["sources"]) for c in cands)),
        "candidates_new_keys": sum(1 for c in cands if not c["existing"]),
        "candidates_without_reference": no_reference,
        "decisions": dict(status),
        "pending": status.get("pending", 0),
        "approved_in_ledger": len(approved_rows),
        "final_keys": len(merged),
        "final_meanings": sum(len(v) for v in merged.values()),
        "merge_stats": stats,
        "original_entries_changed": changed,
    }
    with open(os.path.join(a.out_dir, "report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
    with open(os.path.join(a.out_dir, "report.md"), "w", encoding="utf-8") as f:
        f.write(render_report(report, tier_names))
    print(render_report(report, tier_names))


def render_report(r, tier_names):
    L = ["# דוח איכות: מילון ראשי התיבות", ""]
    L += [f"- מפתחות במאגר המקורי: **{r['baseline_keys']:,}**, פירושים: **{r['baseline_meanings']:,}**",
          f"- זוגות שנאספו מכל המקורות: **{r['collected_total']:,}** ({', '.join(f'{k}: {v:,}' for k, v in r['collected_by_source'].items())})",
          f"- מועמדים שנותרו אחרי הסינון: **{r['candidates_total']:,}** ({r['candidates_new_keys']:,} במפתח חדש)",
          f"- ממתינים לבדיקה ידנית: **{r['pending']:,}**",
          f"- אושרו בפועל בידי אדם (decisions.csv): **{r['approved_in_ledger']:,}**",
          f"- מועמדים בלי אסמכתה: **{r['candidates_without_reference']:,}** (רמזי דיקטה: האסמכתה נדרשת מהבודק)",
          f"- סופי: **{r['final_keys']:,}** מפתחות, **{r['final_meanings']:,}** פירושים",
          f"- ערכים מקוריים ששונו: **{len(r['original_entries_changed'])}**", ""]
    L += ["## מועמדים לפי דרגה", ""] + [f"- {tier_names[t]}: {n:,}" for t, n in sorted(r["candidates_by_tier"].items())] + [""]
    L += ["## נפסלו לפי סיבה", ""] + [f"- {k}: {v:,}" for k, v in r["rejected_by_reason"].items()] + [""]
    L += ["## נפסלו לפי מקור", ""]
    for s, c in r["rejected_by_source"].items():
        L.append(f"- {s}: " + ", ".join(f"{k} {v:,}" for k, v in c.items()))
    L += ["", "## דוגמאות לפסילות", ""]
    for reason, ex in r["rejected_examples"].items():
        L.append(f"- {reason}: " + "; ".join(ex))
    return "\n".join(L) + "\n"


if __name__ == "__main__":
    main()
