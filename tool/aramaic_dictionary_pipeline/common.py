"""כלים משותפים לצינור הרחבת המילון הארמי-עברי: תצורה, נרמול, I/O ומיון."""

from __future__ import annotations

import hashlib
import json
import sys
import os
import re
import unicodedata
from pathlib import Path
from typing import Any, Iterable

PIPELINE_DIR = Path(__file__).resolve().parent

# ───────────────────────── תצורה ─────────────────────────


def load_config() -> dict[str, Any]:
    """config.json + config.local.json (דורס, עמוק) + משתני סביבה."""
    cfg = json.loads((PIPELINE_DIR / "config.json").read_text(encoding="utf-8"))
    local = PIPELINE_DIR / "config.local.json"
    if local.exists():
        _deep_update(cfg, json.loads(local.read_text(encoding="utf-8")))
    env_map = {
        "ARAMAIC_PIPELINE_WORK_DIR": ("work_dir",),
        "ARAMAIC_PIPELINE_GITIN_PDF": ("sources", "siftey_gitin", "pdf"),
        "ARAMAIC_PIPELINE_BRACHOT_PDF": ("sources", "siftey_brachot", "pdf"),
    }
    for env, path in env_map.items():
        if os.environ.get(env):
            node = cfg
            for part in path[:-1]:
                node = node[part]
            node[path[-1]] = os.environ[env]
    return cfg


def _deep_update(base: dict, extra: dict) -> None:
    for key, value in extra.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            _deep_update(base[key], value)
        else:
            base[key] = value


def repo_root(cfg: dict[str, Any]) -> Path:
    return (PIPELINE_DIR / cfg["otzaria_repo"]).resolve()


def work_dir(cfg: dict[str, Any], *parts: str) -> Path:
    base = Path(cfg["work_dir"])
    if not base.is_absolute():
        base = PIPELINE_DIR / base
    path = base.joinpath(*parts)
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


# ───────────────────────── I/O ─────────────────────────


def read_jsonl(path: Path, tolerate_truncated_tail: bool = False) -> list[dict[str, Any]]:
    """tolerate_truncated_tail: שורה אחרונה קטומה (קריסה באמצע כתיבה) מדולגת בהודעה במקום להפיל את הקריאה."""
    with open(path, "rb") as fh:
        lines = [line for line in fh if line.strip()]
    rows: list[dict[str, Any]] = []
    for index, line in enumerate(lines):
        try:
            rows.append(json.loads(line.decode("utf-8")))
        except (json.JSONDecodeError, UnicodeDecodeError):
            if tolerate_truncated_tail and index == len(lines) - 1:
                print(f"warning: {path.name}: skipping truncated last line", file=sys.stderr)
                continue
            raise
    return rows


def write_jsonl(path: Path, rows: Iterable[dict[str, Any]]) -> int:
    """כתיבה דטרמיניסטית (מפתחות ממוינים, בלי escape של עברית)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        for row in rows:
            fh.write(json.dumps(row, ensure_ascii=False, sort_keys=True))
            fh.write("\n")
            count += 1
    return count


def write_json(path: Path, data: Any, *, indent: int | None = 2) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=indent)
        fh.write("\n")


def stable_id(*parts: str, length: int = 12) -> str:
    """מזהה יציב בין הרצות: תלוי רק בתוכן החלקים."""
    digest = hashlib.sha1("\x1f".join(parts).encode("utf-8")).hexdigest()
    return digest[:length]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


# ───────────────────────── נרמול עברית ─────────────────────────

# זהה ל-removeVolwels באפליקציה: ניקוד וטעמים (U+0591..U+05C7).
MARKS_RE = re.compile("[֑-ׇ]")
# סימוני כיווניות ורוחב-אפס שאינם חלק מהמילה.
INVISIBLE_RE = re.compile("[​-‏‪-‮⁦-⁩﻿­]")
_QUOTE_MAP = str.maketrans(
    {
        "״": '"',
        "“": '"',
        "”": '"',
        "„": '"',
        "׳": "'",
        "‘": "'",
        "’": "'",
        "‚": "'",
        "´": "'",
        "`": "'",
    }
)
_DASH_MAP = str.maketrans({"–": "-", "—": "-", "‐": "-", "‑": "-", "־": "-"})
_FINALS = str.maketrans("ךםןףץ", "כמנפצ")
HEBREW_LETTER_RE = re.compile("[א-ת]")


MAQAF = chr(0x5BE)


def strip_marks(text: str) -> str:
    return MARKS_RE.sub("", text)


def clean_text(text: str) -> str:
    """NFC, הסרת תווי כיווניות, איחוד רווחים. שומר ניקוד ופיסוק כפי שהם."""
    text = unicodedata.normalize("NFC", text)
    text = INVISIBLE_RE.sub("", text)
    text = text.replace(" ", " ")
    return re.sub(r"\s+", " ", text).strip()


def normalize_key(text: str) -> str:
    """צורה מנורמלת למילת ערך — להשוואה וזיהוי כפילויות בלבד.

    מסירה ניקוד/טעמים, מאחדת גרשיים/מקפים, מצמצמת רווחים. *לא* ממירה אותיות
    (סופיות נשמרות, ה/א נבדלות) ולא מוחקת גרשיים: א"ל ≠ אל.
    """
    text = clean_text(text).replace(MAQAF, "-")  # מקף עברי נמצא בטווח הטעמים; בלי זה מילים מאוחדות
    text = strip_marks(text).translate(_QUOTE_MAP).translate(_DASH_MAP)
    text = text.replace("''", '"')  # גרשיים כפולים כתובים כשני גרשים
    text = re.sub(r"\s*-\s*", "-", text)
    return re.sub(r"\s+", " ", text).strip(" .,;:!?")


def normalize_gloss(text: str) -> str:
    """נרמול פירוש עברי להשוואת כפילויות מדויקות בלבד (בלי ניקוד/פיסוק קצה)."""
    text = strip_marks(clean_text(text).replace(MAQAF, "-")).translate(_QUOTE_MAP).translate(_DASH_MAP)
    text = re.sub(r"[.,;:!?]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def hebrew_sort_key(text: str) -> tuple[str, str, str]:
    """מיון א–ב יציב: אות-אחר-אות (סופיות כרגילות), רווח/מקף מסדרים לפני אות
    (מילה-אחר-מילה), גרשיים מתעלמים; שוויון נשבר לפי הצורה המנורמלת ואז המקורית."""
    key = normalize_key(text)
    primary = key.replace('"', "").replace("'", "").translate(_FINALS)
    primary = primary.replace("-", " ")
    return (primary, key, text)


# ───────────────────────── תחביר הפירושים של אוצריא ─────────────────────────

_EXPR_RE = re.compile(r"^\{([^{}]+)\}\s*")
_EXP_START_RE = re.compile(r"^\(=\s*([^)]+?)\)\s*")
_EXP_INLINE_RE = re.compile(r"\s+\(=\s*([^)]+?)\)\s*")


def split_senses(raw: str) -> list[str]:
    """מפצל ערך גולמי לפירושים כמו AramaicDictionaryEntryPresentation.parse."""
    normalized = re.sub(r"\s*\*\*\*\s*", "***", raw).strip()
    return [part.strip() for part in normalized.split("***") if part.strip()]


def parse_sense(raw: str) -> dict[str, Any]:
    """מפענח פירוש בודד כמו _parseMeaning באפליקציה: {צורה} (=הרחבה) טקסט."""
    expr_match = _EXPR_RE.match(raw)
    expression = expr_match.group(1).strip() if expr_match else None
    remaining = raw.strip() if not expr_match else raw[expr_match.end():].strip()
    expansion = None
    start = _EXP_START_RE.match(remaining)
    if start:
        expansion = start.group(1).strip()
        remaining = remaining[start.end():].strip()
    else:
        inline = _EXP_INLINE_RE.search(remaining)
        if inline:
            expansion = inline.group(1).strip()
            before = remaining[: inline.start()].strip()
            after = remaining[inline.end():].strip()
            remaining = " ".join(p for p in (before, after) if p)
    return {"raw": raw, "expression": expression, "expansion": expansion, "text": remaining}


def split_synonyms(text: str) -> list[str]:
    """רשימת מילים נרדפות בתוך פירוש: פיצול על פסיק/נקודה-פסיק/נקודה מחוץ לסוגריים."""
    parts: list[str] = []
    current: list[str] = []
    depth = 0
    for ch in text:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth = max(0, depth - 1)
        if depth == 0 and ch in ",;.":
            parts.append("".join(current))
            current = []
        else:
            current.append(ch)
    parts.append("".join(current))
    return [p.strip() for p in parts if p.strip()]
