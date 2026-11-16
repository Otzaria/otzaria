"""הוספת ערכי "בבלי" (game.yilmedutorah.com) ל-"מילון פשיטא" וניקוי ערכי מילוי.

קלט: sources/bavli_entries.csv (מפתח, פירוש מוכן בפורמט אוצריא, וצורת המקור באתר לצורך תיעוד).

* ברירת מחדל: מוסיף את הערכים ל-"מילון פשיטא" בלבד, ממיין א-ב כמו export.py, ולא נוגע בשאר המילונים.
  הרצה חוזרת אינה משנה דבר (ערך שכבר קיים עם אותו פירוש מדולג).
* מפתח שכבר קיים באחד המילונים (אחרי הסרת ניקוד וגרשיים, כמו באפליקציה) מפסיק את ההרצה: לא נוסף פירוש שני בשקט.
* --drop-placeholders: מוחק מכל המילונים ערכי מילוי ("*", "(סימן)", פירוש ריק, מפתח בלי אות עברית).
  האפליקציה כבר מדלגת עליהם בטעינה (DictionaryLookupRepository._isPlaceholderEntry); המחיקה רק מנקה את הקובץ.
  סדר שאר הערכים נשמר, כי סדר הקובץ קובע מי נכנס להרחבות החיפוש כשיש יותר מ-16.
* --check: לא כותב; יוצא בקוד 1 אם הקובץ היה משתנה.

הפורמט זהה לקובץ ב-git: json.dumps(indent=2, ensure_ascii=False), LF, בלי שורה סופית.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path
from typing import Any

from common import hebrew_sort_key, load_config, repo_root

SOURCES_CSV = Path(__file__).resolve().parent / "sources" / "bavli_entries.csv"
PLACEHOLDER_MEANINGS = {"*", "(סימן)"}
_NIKUD = re.compile("[֑-ׇ]")
_HEBREW = re.compile("[א-ת]")
_QUOTES = ('"', "״", "'", "׳")


def app_key(raw: str) -> str:
    """מפתח כפי שהאפליקציה משווה אותו: בלי ניקוד, בלי גרשיים, רווחים מצומצמים."""
    text = _NIKUD.sub("", raw)
    for quote in _QUOTES:
        text = text.replace(quote, "")
    return re.sub(r"\s+", " ", text).strip()


def is_placeholder(key: str, meaning: str) -> bool:
    """אותו כלל כמו DictionaryLookupRepository._isPlaceholderEntry."""
    if not _HEBREW.search(key):
        return True
    parts = [p.strip() for p in meaning.split("***") if p.strip()]
    return all(p in PLACEHOLDER_MEANINGS or not _HEBREW.search(p) for p in parts)


def entry_of(item: dict[str, Any]) -> tuple[str, str]:
    key = next(iter(item))
    return key, str(item[key])


def read_bavli(path: Path = SOURCES_CSV) -> list[tuple[str, str]]:
    with path.open(encoding="utf-8", newline="") as fh:
        rows = [(r["key"], r["meaning"]) for r in csv.DictReader(fh)]
    keys = [app_key(k) for k, _ in rows]
    if len(set(keys)) != len(keys):
        raise SystemExit("bavli_entries.csv: מפתח כפול בקובץ המקור")
    for key, meaning in rows:
        if not key or not meaning.strip() or _NIKUD.search(key) or _NIKUD.search(meaning):
            raise SystemExit(f"bavli_entries.csv: ערך לא תקין: {key!r}")
    return rows


def add_bavli(data: dict[str, list], target: str, rows: list[tuple[str, str]]) -> tuple[int, int]:
    """מוסיף ל-data[target]; מחזיר (נוספו, דולגו כבר-קיימים). זורק SystemExit על התנגשות מפתח."""
    existing: dict[str, list[tuple[str, str, str]]] = {}
    for name, items in data.items():
        for item in items:
            key, meaning = entry_of(item)
            if not is_placeholder(key, meaning):
                existing.setdefault(app_key(key), []).append((name, key, meaning))
    added = skipped = 0
    new_items = []
    for key, meaning in rows:
        hits = existing.get(app_key(key), [])
        if any(name == target and k == key and m == meaning for name, k, m in hits):
            skipped += 1
            continue
        if hits:
            raise SystemExit(f"התנגשות מפתח {key!r} עם {[(n, k) for n, k, _ in hits]}: נדרשת הכרעה ידנית")
        new_items.append({key: meaning})
        added += 1
    merged = data[target] + new_items
    merged.sort(key=lambda item: hebrew_sort_key(entry_of(item)[0]) + (entry_of(item)[1],))
    data[target] = merged
    return added, skipped


def drop_placeholders(data: dict[str, list]) -> dict[str, int]:
    removed: dict[str, int] = {}
    for name, items in data.items():
        kept = [item for item in items if not is_placeholder(*entry_of(item))]
        if len(kept) != len(items):
            removed[name] = len(items) - len(kept)
            data[name] = kept
    return removed


def apply_post_layers(data: dict[str, list], target: str, layers: list[str]) -> list[str]:
    """מחיל על [data] את השכבות שבתצורה (`post_layers`), לפי הסדר; מחזיר תיאור קצר של כל אחת."""
    log = []
    for layer in layers:
        if layer == "bavli":
            added, skipped = add_bavli(data, target, read_bavli())
            log.append(f"bavli: +{added} ({skipped} כבר קיימים)")
        elif layer == "drop_placeholders":
            log.append(f"drop_placeholders: {drop_placeholders(data) or 'none'}")
        else:
            raise SystemExit(f"שכבה לא מוכרת ב-post_layers: {layer!r}")
    return log


def dump(data: dict[str, Any]) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--drop-placeholders", action="store_true", help="מחיקת ערכי מילוי מכל המילונים (במקום הוספת בבלי)")
    parser.add_argument("--check", action="store_true", help="בדיקה בלבד, בלי כתיבה")
    parser.add_argument("--asset", help="נתיב ל-dictionary.json (ברירת מחדל: assets/dictionary.json ב-repo)")
    args = parser.parse_args()
    cfg = load_config()
    asset = Path(args.asset) if args.asset else repo_root(cfg) / cfg["dictionary_asset"]
    before = asset.read_text(encoding="utf-8")
    data = json.loads(before)
    if before != dump(data):
        raise SystemExit(f"{asset}: הפורמט אינו json.dumps(indent=2) — לא נכתב דבר")
    if args.drop_placeholders:
        removed = drop_placeholders(data)
        print("removed placeholders:", removed or "none")
    else:
        added, skipped = add_bavli(data, cfg["target_dictionary"], read_bavli())
        print(f"added {added} entries to {cfg['target_dictionary']} ({skipped} already present)")
    after = dump(data)
    if after == before:
        print("no change")
        return
    if args.check:
        print("would change", asset)
        sys.exit(1)
    asset.write_text(after, encoding="utf-8", newline="\n")
    print("wrote", asset, f"({len(after.encode('utf-8'))} bytes)")


if __name__ == "__main__":
    main()
