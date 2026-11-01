"""List the meanings of the shipped dictionary that decode nothing, for removal by merge.py.

  py tool/acronyms_pipeline/clean_baseline.py --baseline baseline.json

Writes data/baseline_removals.csv (key, expansion, reason).  A meaning is listed when any noise filter in filters.check_expansion
rejects it; in the shipped file that is only:
  same_as_key / expansion_is_acronym   the meaning is the key again (רמ"בם = רמבם), no decoding
  gematria_number                      the number the letters stand for (תשפ"ו = שבע מאות שמונים ושש)
  letter_names / unexpected_characters / structure_chars         scraping leftovers
Meanings that are merely suspicious (letters do not match the words) are only flagged, not listed.
"""
import argparse
import csv
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import filters  # noqa: E402
import merge  # noqa: E402

def removals(baseline):
    out = []
    for key, meanings in baseline.items():
        for m in meanings:
            reasons, _, _ = filters.check_expansion(key, m)
            if reasons:
                out.append((key, m, reasons[0]))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--baseline", required=True)
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    with open(a.baseline, encoding="utf-8") as f:
        baseline = json.load(f)
    rows = removals(baseline)
    with open(merge.REMOVALS, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(merge.REMOVAL_COLUMNS)
        w.writerows(rows)
    by = {}
    for _, _, r in rows:
        by[r] = by.get(r, 0) + 1
    print(len(rows), "meanings listed", by)


if __name__ == "__main__":
    main()
