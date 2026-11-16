"""בקרת איכות אוטומטית על קובץ מילון מיוצא, מול הגיבוי המקורי ומודל הביניים.

מחזיר קוד יציאה 1 אם נכשלה בדיקה כלשהי. הבדיקות (ראו README, "בדיקות איכות"):
  JSON/UTF-8 ופורמט, תאימות מבנה, מפתחות/פירושים ריקים, הפרדת משמעויות ב-***,
  שימור כל פירוש קיים (או שינוי מתועד ומאושר), כפילויות מיותרות, מיון, מילונים אחרים ללא שינוי,
  תחביר אוצריא (parse), אי-הכנסת טקסט חשוד (תווים זרים/לטיניים/סוגריים לא מאוזנים).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

from common import (
    MARKS_RE,
    hebrew_sort_key,
    load_config,
    normalize_gloss,
    normalize_key,
    parse_sense,
    read_jsonl,
    split_senses,
    work_dir,
)
from add_bavli import drop_placeholders
from normalize import gloss_issues

REGRESSION_WORDS = ("אברא", "אהני", "אגמרך", "איבעי")


class Report:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.warnings: list[str] = []
        self.counts: dict[str, Any] = {}

    def check(self, ok: bool, message: str, *, warn: bool = False) -> None:
        if not ok:
            (self.warnings if warn else self.failures).append(message)


def validate(
    path: Path,
    baseline_path: Path,
    snapshot: dict[str, Any],
    merge_log: list[dict[str, Any]] | None,
    target: str,
    post_layers: list[str] | None = None,
) -> Report:
    rep = Report()
    raw = path.read_bytes()
    rep.check(not raw.startswith(b"\xef\xbb\xbf"), "הקובץ מתחיל ב-BOM")
    rep.check(b"\r" not in raw, "הקובץ מכיל CR (סוף שורה צריך להיות LF)")
    try:
        text = raw.decode("utf-8")
        data = json.loads(text)
    except Exception as exc:  # noqa: BLE001
        rep.failures.append(f"JSON/UTF-8 לא תקין: {exc}")
        return rep
    original = json.loads(baseline_path.read_text(encoding="utf-8"))
    rep.check(text == json.dumps(data, ensure_ascii=False, indent=2), "הפורמט שונה מ-json.dumps(indent=2, ensure_ascii=False) — יגרום ל-diff רועש")

    # מבנה
    rep.check(list(data.keys()) == list(original.keys()), "שמות/סדר המילונים העליונים השתנו")
    for name, entries in data.items():
        ok = isinstance(entries, list) and all(isinstance(e, dict) and len(e) == 1 for e in entries)
        rep.check(ok, f"מבנה שגוי במילון {name}")
        if not ok:
            return rep
        for entry in entries:
            for key, value in entry.items():
                rep.check(isinstance(key, str) and isinstance(value, str), f"{name}: מפתח/ערך שאינם מחרוזת: {key!r}")
    # שאר המילונים זהים לגיבוי, פרט לשכבת drop_placeholders (ערכי מילוי שנמחקו, ושום דבר אחר).
    expected_others = json.loads(json.dumps(original))
    if "drop_placeholders" in (post_layers or []):
        drop_placeholders(expected_others)
    for name in original:
        if name != target:
            rep.check(data.get(name) == expected_others[name], f"המילון «{name}» שונה (אסור)")

    entries = [(k, v) for e in data[target] for k, v in e.items()]
    rep.counts["entries"] = len(entries)
    rep.counts["original_entries"] = len(original[target])

    # ריקים
    rep.check(all(k.strip() for k, _ in entries), "קיים מפתח ריק")
    rep.check(all(v.strip() for _, v in entries), "קיים ערך ריק")
    rep.check(all(len(split_senses(v)) >= 1 for _, v in entries), "ערך ללא אף משמעות אחרי פיצול ***")
    rep.check(all("****" not in v and not v.strip().startswith("***") and not v.strip().endswith("***") for _, v in entries), "הפרדת *** שבורה")

    # שימור קיים
    out_by_norm: dict[str, list[str]] = {}
    for k, v in entries:
        out_by_norm.setdefault(normalize_key(k), []).append(v)
    modified_ids = {row["sense_id"] for row in (merge_log or []) if row.get("change") == "modify_existing_sense"}
    lost = []
    for rec_id, snap in snapshot.items():
        if snap["dictionary"] != target:
            continue
        values = out_by_norm.get(normalize_key(snap["key"]), [])
        joined = {s for v in values for s in split_senses(v)}
        for index, sense in enumerate(snap["senses"]):
            if sense not in joined and f"{rec_id}-s{index + 1}" not in modified_ids:
                lost.append((snap["key"], sense))
    rep.check(not lost, f"{len(lost)} פירושים קיימים אבדו ללא שינוי מתועד, למשל {lost[:3]}")
    rep.counts["modified_existing_senses"] = len(modified_ids)

    # מילים לרגרסיה
    for word in REGRESSION_WORDS:
        before = [list(e.values())[0] for e in original[target] if normalize_key(list(e)[0]) == word]
        after = [v for k, v in entries if normalize_key(k) == word]
        after_senses = [s for v in after for s in split_senses(v)]
        # כל משמעות מקורית נשמרת כפי שהיא, או כתחילית של משמעות מורחבת (שינוי שאושר במפורש; ראו confirm_modify_existing)
        rep.check(
            bool(before) and all(b in after or any(a.startswith(b) for a in after) or all(any(a.startswith(s) for a in after_senses) for s in split_senses(b)) for b in before),
            f"רגרסיה: הערך «{word}» השתנה/נעלם",
        )

    # כפילויות מיותרות בתוך ערך
    dup_in_entry = []
    for k, v in entries:
        seen = set()
        for sense in split_senses(v):
            norm = normalize_gloss(parse_sense(sense)["text"])
            if norm in seen:
                dup_in_entry.append((k, sense))
            seen.add(norm)
    original_dups = 0
    for e in original[target]:
        k, v = list(e.items())[0]
        seen = set()
        for sense in split_senses(v):
            norm = normalize_gloss(parse_sense(sense)["text"])
            original_dups += norm in seen
            seen.add(norm)
    rep.counts["duplicate_senses_in_entry"] = len(dup_in_entry)
    rep.counts["duplicate_senses_in_entry_original"] = original_dups
    rep.check(len(dup_in_entry) <= original_dups, f"נוספו כפילויות פירוש בתוך ערך: {dup_in_entry[:3]}")

    # מפתחות כפולים מנורמלים (מעבר למה שהיה במקור)
    norm_counts: dict[str, int] = {}
    for k, _ in entries:
        norm_counts[normalize_key(k)] = norm_counts.get(normalize_key(k), 0) + 1
    orig_counts: dict[str, int] = {}
    for e in original[target]:
        k = list(e)[0]
        orig_counts[normalize_key(k)] = orig_counts.get(normalize_key(k), 0) + 1
    new_dups = [k for k, c in norm_counts.items() if c > orig_counts.get(k, 0) and c > 1]
    rep.check(not new_dups, f"מפתחות מנורמלים כפולים חדשים: {new_dups[:5]}")

    # מיון
    keys = [k for k, _ in entries]
    rep.check(keys == sorted(keys, key=lambda k: hebrew_sort_key(k)) or _sorted_with_values(entries), "הערכים אינם ממוינים")

    # תחביר אוצריא וטקסט חשוד — רק בפירושים חדשים (לא בקיימים)
    existing_senses = {s for snap in snapshot.values() for s in snap["senses"]}
    suspicious = []
    for k, v in entries:
        for sense in split_senses(v):
            if sense in existing_senses:
                continue
            parsed = parse_sense(sense)
            bad = gloss_issues(parsed["text"]) if not parsed["expression"] else gloss_issues(parsed["text"])
            if not parsed["text"]:
                bad.append("empty_after_parse")
            if bad:
                suspicious.append((k, sense, bad))
    rep.check(not suspicious, f"{len(suspicious)} פירושים חדשים עם בעיות איכות, למשל {suspicious[:3]}")
    new_keys = [k for k, _ in entries if normalize_key(k) not in orig_counts]
    rep.check(all(re.fullmatch(r"[א-ת \-\"'׳״]+", strip(k)) for k in new_keys), "מפתחות חדשים עם תווים חריגים", warn=False)
    rep.counts["new_keys"] = len(new_keys)
    rep.counts["new_senses_total"] = sum(1 for k, v in entries for s in split_senses(v) if s not in existing_senses)
    rep.counts["bytes"] = len(raw)
    return rep


def strip(text: str) -> str:
    return MARKS_RE.sub("", text)


def _sorted_with_values(entries: list[tuple[str, str]]) -> bool:
    keyed = [hebrew_sort_key(k) + (v,) for k, v in entries]
    return keyed == sorted(keyed)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("path", nargs="?", help="קובץ לבדיקה (ברירת מחדל: work/export/merged.dictionary.json)")
    parser.add_argument("--tag", default="merged")
    args = parser.parse_args()
    cfg = load_config()
    path = Path(args.path) if args.path else work_dir(cfg, "export", f"{args.tag}.dictionary.json")
    snapshot = json.loads(work_dir(cfg, "baseline", "regression_snapshot.json").read_text(encoding="utf-8"))
    log_path = work_dir(cfg, "merge", f"{args.tag}_log.jsonl")
    log = read_jsonl(log_path) if log_path.exists() else []
    report = validate(
        path,
        work_dir(cfg, "baseline", "dictionary.original.json"),
        snapshot,
        log,
        cfg["target_dictionary"],
        cfg.get("post_layers", []),
    )
    print(json.dumps(report.counts, ensure_ascii=False, indent=2))
    for warning in report.warnings:
        print("WARN:", warning)
    for failure in report.failures:
        print("FAIL:", failure)
    print("OK" if not report.failures else f"{len(report.failures)} בדיקות נכשלו")
    sys.exit(1 if report.failures else 0)


if __name__ == "__main__":
    main()
