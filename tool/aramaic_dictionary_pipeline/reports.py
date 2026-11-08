"""דו"חות חובה (CSV + חוברת XLSX אחת): work/reports/<tag>/*.csv ו-all_reports.xlsx

 1 all_entries           כל הערכים (קיימים וחדשים), פירוש לשורה
 2 new_entries           מפתחות חדשים שנוספו
 3 exact_duplicates      כפילויות מדויקות שאוחדו (תמיכה בפירוש קיים / ניסוח שקול)
 4 semantic_duplicates   כפילויות סמנטיות שאוחדו (החלטות אנושיות/הצעות סוכן בלבד)
 5 multi_sense_entries   ערכים בעלי כמה משמעויות, ומשמעויות שונות שנוספו
 6 conflicting_sources   סתירות בין מקורות
 7 rejected              ערכים שנפסלו וסיבות
 8 pending_manual        ממתינים לאישור ידני (כולל הצעות המערכת והסוכן)
 9 extraction_corrections תיקוני חילוץ/OCR (לא הופעל OCR: ראו README)
10 changes_vs_original   כל שינוי ביחס למילון המקורי
11 stats_by_source
12 stats_by_pdf_page
13 sources_and_licenses
"""

from __future__ import annotations

import argparse
import csv
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from common import load_config, read_jsonl, work_dir
from merge import load_decisions

LICENSES = [
    ["מילון פשיטא / שיח ישראל / אונקלוס (קיימים)", "assets/dictionary.json, commit 12ec974e3 (Y-PLONI)", "לא מתועד ב-repo", "לא נגענו בתוכן; המקור והרישיון אינם מתועדים ב-repo — מומלץ לברר מול המתחזקים", "ללא שינוי"],
    ["שפתי גיטין / שפתי ברכות", "הרב יצחק אביקסיס, daf-yomi.com", "כל הזכויות שמורות למחבר (עמוד זכויות ב-PDF); היתר מיוחד להכנסה לאוצריא — לפי דיווח המשתמש", "יש לתעד היתר בכתב: היקף (הפצה, שינוי/מיון/עיבוד), נוסח ייחוס. אין להפיץ לפני שהתיעוד מושלם", "חומר בהיתר מיוחד — להפריד מחומר ברישיון ציבורי"],
    ["ויקימילון העברי", "he.wiktionary.org (קטגוריה: ערכים בשפה הארמית)", "CC BY-SA 4.0", "חובת ייחוס (שם המקור, קישור לגרסה/היסטוריית עריכה), ציון שינויים, ושיתוף זהה (ShareAlike) לחומר נגזר", "חומר ברישיון ציבורי; לא להכניס לפלט המופץ עד הסדרת הייחוס והתאימות לתנאי ההפצה של אוצריא"],
]


def write_csv(path: Path, header: list[str], rows: list[list[Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8-sig", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(header)
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--tag", default="merged")
    args = parser.parse_args()
    cfg = load_config()
    out = work_dir(cfg, "reports", args.tag, "x").parent
    existing = [r for r in read_jsonl(work_dir(cfg, "baseline", "existing_records.jsonl"))]
    entries = read_jsonl(work_dir(cfg, "merge", f"{args.tag}_entries.jsonl"))
    log = read_jsonl(work_dir(cfg, "merge", f"{args.tag}_log.jsonl"))
    pending = read_jsonl(work_dir(cfg, "merge", f"{args.tag}_pending.jsonl"))
    claims = {c["claim_id"]: c for c in read_jsonl(work_dir(cfg, "merge", "claims.jsonl"))}
    rejected_norm = read_jsonl(work_dir(cfg, "merge", "rejected.jsonl"))
    auto = read_jsonl(work_dir(cfg, "merge", "auto_decisions.jsonl"))
    queue = {q["item_id"]: q for q in read_jsonl(work_dir(cfg, "merge", "queue.jsonl"))}
    decisions = load_decisions(work_dir(cfg, "review", "decisions.jsonl"))
    agent_path = work_dir(cfg, "review", "agent_suggestions.jsonl")
    agent = load_decisions(agent_path) if agent_path.exists() else {}
    target = cfg["target_dictionary"]
    sheets: dict[str, tuple[list[str], list[list[Any]]]] = {}

    def add(name: str, header: list[str], rows: list[list[Any]]) -> None:
        sheets[name] = (header, rows)
        write_csv(out / f"{name}.csv", header, rows)

    # 1
    rows = []
    for e in entries:
        for s in e["senses"]:
            rows.append([e["display_key"], s["raw"], s["origin"], s["status"], s["sense_id"], len(s["support"])])
    for r in existing:
        if r["dictionary"] != target:
            for s in r["senses"]:
                rows.append([r["key"], s["raw"], "existing:" + r["dictionary"], "existing_not_modified", s["sense_id"], 0])
    add("01_all_entries", ["key", "sense", "origin", "status", "sense_id", "supporting_claims"], rows)

    # 2
    add(
        "02_new_entries",
        ["key", "senses", "origin", "status"],
        [[e["display_key"], " *** ".join(s["raw"] for s in e["senses"]), e["senses"][0]["origin"], e["senses"][0]["status"]] for e in entries if not e["existing_records"]],
    )
    # 3-4
    def dup_rows(kind_filter) -> list[list[Any]]:
        return [[l["key"], l.get("text", ""), l["class"], l["reason"], l["status"], l["decision"]] for l in log if l["change"] == "support_existing" and kind_filter(l["class"])]
    add("03_exact_duplicates", ["key", "existing_sense", "class", "reason", "status", "decision"], dup_rows(lambda c: c == "exact_duplicate"))
    add("04_semantic_duplicates", ["key", "existing_sense", "class", "reason", "status", "decision"], dup_rows(lambda c: c != "exact_duplicate"))
    # 5
    rows = []
    for e in entries:
        if len(e["senses"]) > 1:
            rows.append([e["display_key"], len(e["senses"]), " *** ".join(s["raw"] for s in e["senses"]), "; ".join(sorted({s["status"] for s in e["senses"]}))])
    add("05_multi_sense_entries", ["key", "senses_count", "senses", "statuses"], rows)
    # 6
    rows = []
    for q in queue.values():
        cls = set(q["system_proposal"]["classes"]) | ({agent[q["item_id"]]["class"]} if q["item_id"] in agent else set())
        if "conflicting_sources" in cls or q["evidence_other_dictionaries"] and q["existing_senses"] and q["system_proposal"]["classes"] == ["distinct_sense"]:
            rows.append([q["display_key"], " | ".join(s["raw"] for s in q["existing_senses"]), " | ".join(c["gloss"] for g in q["groups"] for c in g), " | ".join(s["raw"] for s in q["evidence_other_dictionaries"]), ",".join(sorted(cls))])
    add("06_conflicting_sources", ["key", "existing", "new_claims", "other_dictionaries", "classes"], rows)
    # 7
    rows = [[r["source"], r["record_id"], r["key"], r["gloss"], r["reason"]] for r in rejected_norm]
    rows += [[ "review", l["item_id"], l["key"], "", l.get("reason", "")] for l in log if l["change"] == "reject_item"]
    add("07_rejected", ["source", "record_id", "key", "gloss", "reason"], rows)
    # 8
    rows = []
    for item in pending:
        p, a = item["system_proposal"], agent.get(item["item_id"])
        rows.append([
            item["item_id"], item["kind"], item["display_key"],
            " | ".join(s["raw"] for s in item["existing_senses"]),
            " | ".join(c["gloss"] for g in item["groups"] for c in g),
            ",".join(p["classes"]), p["confidence"], " ; ".join(p["notes"]),
            a["action"] if a else "", a.get("class", "") if a else "", a.get("confidence", "") if a else "",
            a.get("needs_human", "") if a else "", a.get("rationale", "") if a else "",
        ])
    add("08_pending_manual", ["item_id", "kind", "key", "existing", "new_claims", "system_classes", "system_confidence", "system_notes", "agent_action", "agent_class", "agent_confidence", "agent_needs_human", "agent_rationale"], rows)
    # 9
    pages_rows: list[list[Any]] = []
    corrections: list[list[Any]] = []
    for source in ("siftey_gitin", "siftey_brachot"):
        for r in read_jsonl(work_dir(cfg, "extract", f"{source}_entries.jsonl")):
            for flag in r["flags"]:
                if flag in ("niqqud_lost", "wrapped_translation", "stacked_translation", "wrapped_aramaic", "orphan_diacritic"):
                    corrections.append([source, r["record_id"], r["pdf_page"], flag, r["aramaic"], r["hebrew_original"], r["hebrew_clean"]])
    add("09_extraction_corrections", ["source", "record_id", "pdf_page", "correction", "aramaic", "hebrew_original", "hebrew_clean"], corrections)
    # 10
    rows = []
    for l in log:
        rows.append([l["change"], l["key"], l.get("text") or l.get("new", ""), l.get("old", ""), l.get("class", ""), l.get("reason", ""), l.get("status", ""), l.get("decision", "")])
    add("10_changes_vs_original", ["change", "key", "text_or_new", "old", "class", "reason", "status", "decision"], rows)
    # 11
    by_source: dict[str, Counter] = defaultdict(Counter)
    for d in auto:
        for s in d["sources"]:
            by_source[s][f"auto_{d['action']}"] += 1
    for q in queue.values():
        for g in q["groups"]:
            for c in g:
                for s in c["sources"]:
                    by_source[s]["queue_claims"] += 1
    for source in ("siftey_gitin", "siftey_brachot"):
        rows_src = read_jsonl(work_dir(cfg, "extract", f"{source}_entries.jsonl"))
        by_source[source]["extracted_rows"] = len(rows_src)
        by_source[source]["rows_low_confidence"] = sum(1 for r in rows_src if r["confidence"] < 0.9)
    keys = sorted({k for c in by_source.values() for k in c})
    add("11_stats_by_source", ["source", *keys], [[s, *[by_source[s][k] for k in keys]] for s in sorted(by_source)])
    # 12
    rows = []
    for source in ("siftey_gitin", "siftey_brachot"):
        with open(work_dir(cfg, "extract", f"{source}_pages.csv"), encoding="utf-8-sig") as fh:
            page_stats = list(csv.DictReader(fh))
        approved_ids = {o["record_id"] for d in auto for cid in [d["claim_id"]] for o in claims[cid]["occurrences"]}
        pending_ids = {o["record_id"] for q in pending for g in q["groups"] for c in g for o in c["occurrences"]}
        by_page: dict[int, Counter] = defaultdict(Counter)
        for r in read_jsonl(work_dir(cfg, "extract", f"{source}_entries.jsonl")):
            by_page[r["pdf_page"]]["approved_auto" if r["record_id"] in approved_ids else "pending" if r["record_id"] in pending_ids else "other"] += 1
        for ps in page_stats:
            n = int(ps["page"])
            reason = "" if ps["has_text_layer"] == "1" else ("מכתב הסכמה (תמונה)" if int(ps["images"]) > 10 else "עמוד ריק")
            rows.append([source, n, ps["has_text_layer"], reason, ps["entries"], ps["low_confidence"], by_page[n]["approved_auto"], by_page[n]["pending"], ps["letter_diff"], ps["header_daf"]])
    add("12_stats_by_pdf_page", ["source", "pdf_page", "has_text_layer", "no_text_reason", "entries_extracted", "low_confidence", "approved_auto", "pending", "letter_diff_vs_page_text", "header_daf"], rows)
    # 13
    add("13_sources_and_licenses", ["source", "origin", "rights_statement", "obligations_and_status", "distribution_class"], LICENSES)

    try:
        import openpyxl

        wb = openpyxl.Workbook()
        wb.remove(wb.active)
        for name, (header, rows) in sheets.items():
            ws = wb.create_sheet(name[:31])
            ws.sheet_view.rightToLeft = True
            ws.append(header)
            for row in rows:
                ws.append([str(v)[:32000] if isinstance(v, str) else v for v in row])
        wb.save(out / "all_reports.xlsx")
    except ImportError:
        print("openpyxl לא מותקן — נוצרו CSV בלבד")
    print(json.dumps({name: len(rows) for name, (_, rows) in sheets.items()}, ensure_ascii=False, indent=1))
    print("reports in", out)


if __name__ == "__main__":
    main()
