"""שלב 12: ייצוא המודל הממוזג לקובץ dictionary.json במבנה שאוצריא יודעת לקרוא.

* רק "מילון פשיטא" משתנה; שאר המילונים (ושם/סדר המפתחות העליונים) נשמרים בדיוק, פרט לשכבות
  `post_layers` שבתצורה (add_bavli.py): ערכי בבלי נוספים ל"פשיטא", וערכי מילוי נמחקים מכל המילונים.
* ערך קיים שלא השתנה נכתב בטקסט המקורי, בייט-לבייט; הוספת משמעות מצמידה אותה אחרי
  ` *** ` לטקסט המקורי, ורק שינוי מאושר בפירוש קיים בונה את הערך מחדש.
* כל הערכים ממוינים א-ב לפי כלל יציב (common.hebrew_sort_key), *אחרי* המיזוג.
* הפורמט זהה לקובץ ב-git: json.dumps(indent=2, ensure_ascii=False), LF, בלי שורה סופית.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from add_bavli import apply_post_layers
from common import hebrew_sort_key, load_config, read_jsonl, repo_root, work_dir

SEP = " *** "


def record_id_of(sense_id: str) -> str:
    return sense_id.rsplit("-s", 1)[0]


def build_target_list(entries: list[dict[str, Any]]) -> list[dict[str, str]]:
    out: list[tuple[str, str]] = []
    for entry in entries:
        records = entry["existing_records"]
        if not records:
            out.append((entry["display_key"], SEP.join(s["raw"] for s in entry["senses"])))
            continue
        modified = any(s["status"].startswith("modified_") for s in entry["senses"])
        new_senses = [s for s in entry["senses"] if s["origin"] != "existing"]
        for index, rec in enumerate(records):
            own = [s for s in entry["senses"] if s["origin"] == "existing" and record_id_of(s["sense_id"]) == rec["record_id"]]
            own_modified = any(s["status"].startswith("modified_") for s in own)
            extra = new_senses if index == 0 else []
            if not own_modified and not extra:
                value = rec["raw_value"]
            elif not own_modified:
                value = rec["raw_value"] + SEP + SEP.join(s["raw"] for s in extra)
            else:
                value = SEP.join(s["raw"] for s in own + extra)
            out.append((rec["key"], value))
        del modified
    out.sort(key=lambda kv: hebrew_sort_key(kv[0]) + (kv[1],))
    return [{key: value} for key, value in out]


def dump(data: dict[str, Any]) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--tag", default="merged", help="קבצי המודל הממוזג (merge/<tag>_entries.jsonl)")
    parser.add_argument("--out", help="נתיב פלט (ברירת מחדל: work/export/<tag>.dictionary.json)")
    parser.add_argument("--write-asset", action="store_true", help="כתיבה ישירה ל-assets/dictionary.json ב-repo")
    args = parser.parse_args()
    cfg = load_config()
    original = json.loads(work_dir(cfg, "baseline", "dictionary.original.json").read_text(encoding="utf-8"))
    if args.write_asset and args.tag != "merged":
        parser.error("--write-asset מותר רק עם --tag merged (תצוגות מקדימות עם הצעות AI אינן נכתבות ל-assets)")
    entries = read_jsonl(work_dir(cfg, "merge", f"{args.tag}_entries.jsonl"))
    result = dict(original)  # שומר סדר ומפתחות עליונים
    result[cfg["target_dictionary"]] = build_target_list(entries)
    for line in apply_post_layers(result, cfg["target_dictionary"], cfg.get("post_layers", [])):
        print("layer", line)
    text = dump(result)
    out_path = Path(args.out) if args.out else work_dir(cfg, "export", f"{args.tag}.dictionary.json")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {out_path} ({len(text.encode('utf-8'))} bytes), {len(result[cfg['target_dictionary']])} entries in {cfg['target_dictionary']}")
    if args.write_asset:
        asset = repo_root(cfg) / cfg["dictionary_asset"]
        asset.write_text(text, encoding="utf-8", newline="\n")
        print(f"wrote {asset}")


if __name__ == "__main__":
    main()
