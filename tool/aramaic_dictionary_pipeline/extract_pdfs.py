"""שלב 3: חילוץ ערכי "שפתי גיטין" ו"שפתי ברכות" מה-PDF (שכבת הטקסט הקיימת).

מבנה העמוד בשני הספרים: טבלה בשני טורים; בכל שורה מילה/ביטוי ארמי (גופן PFT_Vilna)
מימין ותרגומו העברי (גופן FrankRuehl-XP) משמאלו. כותרת "דף ד." / "דף ד:" (גופן
EFT_Tefilot,Bold) מציינת דף ועמוד. טקסט ה-PDF שמור בסדר לוגי, למעט סוגריים
שמגיעים הפוכים (")לקצרו(") ומתוקנים כאן.

כל span בעמוד מסווג לקטגוריה — כותרת עמוד, מספר עמוד, כותרת דף, ערך, המשך תרגום,
הערת שוליים, הערות-עברית וכו' — כך שאין טקסט ש"נעלם" בלי תיעוד, ונספרים הכול לפי
עמוד (בקרת שלמות). OCR אינו מופעל כאן: אם בעמוד אין שכבת טקסט הוא מסומן ב-pages.csv.

פלט (work/extract/): <source>_entries.jsonl, <source>_nonentries.jsonl, <source>_pages.csv
"""

from __future__ import annotations

import argparse
import csv
import re
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import pymupdf

from common import (
    HEBREW_LETTER_RE,
    MARKS_RE,
    strip_marks,
    clean_text,
    load_config,
    normalize_key,
    work_dir,
    write_jsonl,
)

# ───────────────────────── קבועים ─────────────────────────

FONT_ARAMAIC = "PFT_Vilna"
FONT_HEBREW = "FrankRuehl-XP"
FONT_HEADING = "EFT_Tefilot"
FONT_SYMBOL = ("GLogo1", "GTaam")  # גליפים דקורטיביים/סימני ניקוד בתווי PUA

HEADER_Y_MAX = 100.0  # כותרת העמוד (שם הספר + "מסכת דף X")
FOOTER_Y_MIN = 650.0  # מספר עמוד
ROW_BASELINE_TOL = 3.0
PUA_RE = re.compile("[-]")
DAF_MARK_RE = re.compile(r"^דף\s+([א-ת\"'׳״]{1,7})\s*([.:])$")
HEADER_DAF_RE = re.compile(r"דף\s+([א-ת\"'׳״]{1,7})\s*([.:])")
_GEMATRIA = {c: v for c, v in zip("אבגדהוזחטיכלמנסעפצקרשת", [1,2,3,4,5,6,7,8,9,10,20,30,40,50,60,70,80,90,100,200,300,400])}
_GEMATRIA.update({"ך": 20, "ם": 40, "ן": 50, "ף": 80, "ץ": 90})
# גליפים מורכבים בגופן FrankRuehl-XP (PUA) שמייצגים ך סופית עם ניקוד: U+E802 = ךְ, U+E803 = ךָ
_COMPOSED_FINAL_KAF = ("\ue802", "\ue803")
_BRACKET_SWAP = str.maketrans("()[]{}", ")(][}{")

# ───────────────────────── מבני נתונים ─────────────────────────


@dataclass
class Piece:
    """span בודד אחרי סינון."""

    font: str
    size: float
    flags: int
    text: str
    x0: float
    y0: float
    x1: float
    y1: float
    baseline: float
    kind: str = ""  # aramaic / hebrew / heading / other
    chars: list[tuple[str, float, float]] = field(default_factory=list)  # (תו, x0, x1)
    dropped_marks: int = 0  # סימני ניקוד שלא ניתן לשייך לאות (רוחב אפס, span נפרד)


@dataclass
class VisualRow:
    col: str
    baseline: float
    pieces: list[Piece] = field(default_factory=list)

    @property
    def y0(self) -> float:
        return min(p.y0 for p in self.pieces)

    @property
    def y1(self) -> float:
        return max(p.y1 for p in self.pieces)

    @property
    def x0(self) -> float:
        return min(p.x0 for p in self.pieces)

    @property
    def x1(self) -> float:
        return max(p.x1 for p in self.pieces)


def hebrew_numeral(text: str) -> int | None:
    letters = re.sub(r"[\"'׳״]", "", text)
    if not letters or any(c not in _GEMATRIA for c in letters):
        return None
    return sum(_GEMATRIA[c] for c in letters)


def parse_daf(num_text: str, mark: str) -> dict[str, Any] | None:
    value = hebrew_numeral(num_text)
    if value is None:
        return None
    return {"daf": value, "amud": "a" if mark == "." else "b", "label": f"{num_text}{mark}"}


def font_kind(font: str) -> str:
    base = font.split("+")[-1]
    if base.startswith(FONT_ARAMAIC):
        return "aramaic"
    if base.startswith(FONT_HEBREW):
        return "hebrew"
    if base.startswith(FONT_HEADING):
        return "heading"
    if any(base.startswith(f) for f in FONT_SYMBOL):
        return "symbol"
    return "other"


def join_pieces(pieces: list[Piece]) -> str:
    """איחוד תווי שורה חזותית אחת לפי מיקום (ימין→שמאל).

    הסדר הלוגי בתוך span אינו אמין כשיש סוגריים/מקפים, לכן ממיינים לפי x של כל תו.
    סימני ניקוד כבר מחוברים לאות שלפניהם (ראו collect_pieces). רווח נקבע לפי פער בין
    תווים סמוכים. רצפי ספרות (LTR) מוחזרים לכיוונם.
    """
    chars = [
        (c, x0, x1, piece.size)
        for piece in pieces
        for c, x0, x1 in piece.chars
        if c.strip() != ""
    ]
    chars.sort(key=lambda t: -(t[1] + t[2]) / 2)
    out: list[str] = []
    prev = None
    for c, x0, x1, size in chars:
        if prev is not None and prev[1] - x1 > 0.14 * min(prev[3], size):
            out.append(" ")
        out.append(c)
        prev = (c, x0, x1, size)
    text = "".join(out)
    return re.sub(r"[0-9]+", lambda m: m.group(0)[::-1], text)


def fix_brackets(text: str) -> str:
    """הסוגריים ב-PDF שמורים כגליף חזותי; בעברית (RTL) יש להפוך אותם."""
    return text.translate(_BRACKET_SWAP) if HEBREW_LETTER_RE.search(text) else text


def clean_gloss(text: str) -> str:
    """ניקוי תרגום עברי מחילוץ: רווחים, רווח לפני פיסוק, נקודה סופית של סוף שורה."""
    text = clean_text(fix_brackets(text))
    text = re.sub(r"\s+([,.;:?!)\]])", r"\1", text)
    text = re.sub(r"([(\[])\s+", r"\1", text)
    text = re.sub(r"([,.;:?!])(?=[א-ת(])", r"\1 ", text)
    text = text.strip()
    if text.endswith(".") and not text.endswith(".."):
        text = text[:-1].rstrip()
    return text


def clean_aramaic(text: str) -> str:
    text = clean_text(fix_brackets(text))
    text = re.sub(r"\s+([,.;:?!)\]])", r"\1", text)
    return text.strip()


# ───────────────────────── חילוץ עמוד ─────────────────────────


def page_geometry(page: pymupdf.Page) -> dict[str, float]:
    """x של מפריד הטורים וגובה קו הערות-השוליים (אם קיימים), מתוך הציורים בעמוד."""
    divider_x = page.rect.width / 2
    footnote_y = float("inf")
    for drawing in page.get_drawings():
        rect = drawing["rect"]
        if drawing.get("type") != "f" or not drawing.get("fill"):
            continue
        r, g, b = drawing["fill"][:3]
        grayish = abs(r - g) < 0.02 and abs(g - b) < 0.02 and 0.3 < r < 0.8
        if not grayish:
            continue
        if rect.width <= 3 and rect.height > 150 and 100 < rect.y0 < 300:
            divider_x = (rect.x0 + rect.x1) / 2
        elif rect.height <= 3 and rect.width > 250 and 300 < rect.y0 < 640 and rect.x0 > 40:
            footnote_y = min(footnote_y, rect.y0)
    return {"divider_x": divider_x, "footnote_y": footnote_y}


def collect_pieces(page: pymupdf.Page) -> tuple[list[Piece], int, int]:
    """כל ה-spans הלא ריקים של העמוד; מחזיר גם מספר תווי PUA שהוסרו (ניקוד/סימנים)."""
    pieces: list[Piece] = []
    pua_removed = 0
    marks_dropped = 0
    for block in page.get_text("rawdict")["blocks"]:
        if block.get("type") != 0:
            continue
        for line in block["lines"]:
            for span in line["spans"]:
                raw_chars = [(ch["c"], ch["bbox"][0], ch["bbox"][2]) for ch in span["chars"]]
                pua_removed += sum(1 for c, _, _ in raw_chars if PUA_RE.match(c))
                chars: list[tuple[str, float, float]] = []
                span_dropped = 0
                for c, cx0, cx1 in raw_chars:
                    if c in _COMPOSED_FINAL_KAF:
                        # גליף מורכב של ך סופית עם ניקוד (ךְ / ךָ): האות נשמרת, הניקוד אבד
                        chars.append(("ך", cx0, cx1))
                        span_dropped += 1
                        pua_removed -= 1
                        continue
                    if PUA_RE.match(c):
                        continue
                    if MARKS_RE.match(c):
                        # בקובץ אלה תווים ברוחב אפס; מיקומם אמין רק כשהם באותו span אחרי האות
                        if chars:
                            chars[-1] = (chars[-1][0] + c, chars[-1][1], chars[-1][2])
                        else:
                            span_dropped += 1
                        continue
                    chars.append((c, cx0, cx1))
                text = "".join(c for c, _, _ in chars)
                kind = font_kind(span["font"])
                if kind == "aramaic" and not HEBREW_LETTER_RE.search(text) and not re.fullmatch(r"\s*\d{1,3}\s*", text):
                    # פיסוק/סימן בגופן הארמי (למשל פסיק שמסיים את התרגום) שייך לעברית ולא פותח ערך חדש
                    kind = "hebrew"
                marks_dropped += span_dropped
                if not text.strip() and not span_dropped:
                    continue
                x0, y0, x1, y1 = span["bbox"]
                pieces.append(
                    Piece(
                        font=span["font"].split("+")[-1],
                        size=round(span["size"], 1),
                        flags=span["flags"],
                        text=text,
                        x0=x0,
                        y0=y0,
                        x1=x1,
                        y1=y1,
                        baseline=span["origin"][1],
                        kind=kind,
                        chars=chars,
                        dropped_marks=span_dropped,
                    )
                )
    return pieces, pua_removed, marks_dropped


def group_rows(pieces: list[Piece], divider_x: float, footnote_y: float) -> dict[str, list[VisualRow]]:
    """מחלק לטורים (R/L) ולשורות חזותיות לפי קו-בסיס; מדלג על רווחים בלבד."""
    columns: dict[str, list[Piece]] = {"R": [], "L": []}
    for piece in pieces:
        if piece.text.strip() == "" and not piece.dropped_marks:
            continue
        center = (piece.x0 + piece.x1) / 2
        columns["R" if center > divider_x else "L"].append(piece)
    rows: dict[str, list[VisualRow]] = {"R": [], "L": []}
    for col, items in columns.items():
        items.sort(key=lambda p: (p.baseline, -p.x1))
        for piece in items:
            if rows[col] and abs(rows[col][-1].baseline - piece.baseline) <= ROW_BASELINE_TOL:
                rows[col][-1].pieces.append(piece)
            else:
                rows[col].append(VisualRow(col=col, baseline=piece.baseline, pieces=[piece]))
    return rows


@dataclass
class Entry:
    page: int
    col: str
    index_in_col: int
    daf: dict[str, Any] | None
    aramaic_groups: list[list[Piece]]  # קבוצה לכל שורה חזותית (ביטוי ארמי שנשבר לשתי שורות)
    hebrew_groups: list[list[Piece]] = field(default_factory=list)  # קבוצה לכל שורה חזותית
    flags: list[str] = field(default_factory=list)
    bbox: list[float] = field(default_factory=list)
    last_row_y0: float = 0.0
    region: str = "table"
    chapter: str | None = None
    footnote_refs: list[str] = field(default_factory=list)


def is_superscript_ref(piece: Piece, row: VisualRow) -> bool:
    main_size = max((p.size for p in row.pieces if p.kind == "aramaic"), default=piece.size)
    return bool(re.fullmatch(r"\s*\d{1,3}\s*", piece.text)) and (piece.flags & 1 or piece.size < main_size - 1.5)


def process_page(page: pymupdf.Page, page_no: int, state: dict[str, Any]) -> tuple[list[Entry], list[dict], dict[str, Any]]:
    """מחזיר (ערכים, שורות שאינן ערכים, סטטיסטיקות עמוד). state מחזיק דף נוכחי בין עמודים."""
    geo = page_geometry(page)
    pieces, pua_removed, marks_dropped = collect_pieces(page)
    stats: Counter = Counter()
    stats["pua_removed"] = pua_removed
    stats["marks_dropped"] = marks_dropped
    stats["text_chars"] = sum(len(p.text.strip()) for p in pieces) + marks_dropped
    nonentries: list[dict] = []
    entries: list[Entry] = []

    def record_non(kind: str, row_or_text: Any, *, col: str = "", bbox: list[float] | None = None) -> None:
        if isinstance(row_or_text, VisualRow):
            text = clean_text(fix_brackets(join_pieces(row_or_text.pieces)))
            bbox = [round(row_or_text.x0, 1), round(row_or_text.y0, 1), round(row_or_text.x1, 1), round(row_or_text.y1, 1)]
            col = row_or_text.col
            fonts = sorted({p.font for p in row_or_text.pieces})
            chars = sum(len(p.text.strip()) + p.dropped_marks for p in row_or_text.pieces)
        else:
            text, fonts, chars = row_or_text, [], len(row_or_text)
        stats[f"non_{kind}"] += 1
        stats["chars_non"] += chars
        nonentries.append(
            {"page": page_no, "kind": kind, "col": col, "text": text, "bbox": bbox or [], "fonts": fonts, "daf": state.get("daf")}
        )

    # כותרת/כותרת תחתונה לפי גובה
    body: list[Piece] = []
    header_rows: list[VisualRow] = []
    footer_rows: list[VisualRow] = []
    top: list[Piece] = []
    bottom: list[Piece] = []
    for p in pieces:
        if p.baseline < HEADER_Y_MAX:
            top.append(p)
        elif p.baseline > FOOTER_Y_MIN:
            bottom.append(p)
        else:
            body.append(p)
    for group, sink in ((top, header_rows), (bottom, footer_rows)):
        for p in sorted([q for q in group if q.text.strip()], key=lambda q: q.baseline):
            if sink and abs(sink[-1].baseline - p.baseline) <= ROW_BASELINE_TOL:
                sink[-1].pieces.append(p)
            else:
                sink.append(VisualRow(col="", baseline=p.baseline, pieces=[p]))
    header_daf = None
    for row in header_rows:
        text = clean_text(join_pieces(row.pieces))
        match = HEADER_DAF_RE.search(text)
        if match and any(p.kind == "heading" for p in row.pieces):
            header_daf = parse_daf(match.group(1), match.group(2))
        record_non("page_header", row)
    for row in footer_rows:
        record_non("page_footer", row)
    stats["header_daf"] = header_daf["label"] if header_daf else ""

    if state.get("daf") is None and header_daf:
        state["daf"] = dict(header_daf)
        state["daf_seeded_from_header"] = page_no
    rows_by_col = group_rows(body, geo["divider_x"], geo["footnote_y"])
    for col in ("R", "L"):  # סדר קריאה: טור ימני ואז שמאלי
        current: Entry | None = None
        index_in_col = 0
        for row in rows_by_col[col]:
            kinds = {p.kind for p in row.pieces}
            text = clean_text(join_pieces(row.pieces))
            if row.y0 >= geo["footnote_y"] - 1:
                record_non("footnote", row)
                current = None
                continue
            heading_pieces = [p for p in row.pieces if p.kind == "heading"]
            if heading_pieces and kinds <= {"heading", "symbol"}:
                mark = DAF_MARK_RE.match(clean_text(join_pieces(heading_pieces)))
                if mark:
                    parsed = parse_daf(mark.group(1), mark.group(2))
                    if parsed:
                        state["daf"] = parsed
                        stats["daf_markers"] += 1
                        record_non("daf_marker", row)
                        current = None
                        continue
                state["chapter"] = text if max(p.size for p in heading_pieces) > 17 else state.get("chapter")
                record_non("heading", row)
                current = None
                continue
            if not any(p.kind in ("aramaic", "hebrew") for p in row.pieces):
                record_non("decoration", row)
                continue
            aramaic = [p for p in row.pieces if p.kind == "aramaic"]
            hebrew = [p for p in row.pieces if p.kind == "hebrew"]
            others = [p for p in row.pieces if p.kind not in ("aramaic", "hebrew")]
            if (
                aramaic
                and current is not None
                and not current.hebrew_groups
                and row.y0 - current.last_row_y0 < 18
            ):
                # ביטוי ארמי שנשבר לשתי שורות: השורה הנוכחית ממשיכה את הקודמת
                current.aramaic_groups.append([p for p in aramaic if not is_superscript_ref(p, row)])
                current.hebrew_groups = [list(hebrew)] if hebrew else []
                current.flags.append("wrapped_aramaic")
                current.last_row_y0 = row.y0
                current.bbox = [min(current.bbox[0], row.x0), current.bbox[1], max(current.bbox[2], row.x1), max(current.bbox[3], row.y1)]
                continue
            if aramaic:
                index_in_col += 1
                refs = [p.text.strip() for p in aramaic if is_superscript_ref(p, row)]
                aramaic = [p for p in aramaic if not is_superscript_ref(p, row)]
                current = Entry(
                    page=page_no,
                    col=col,
                    index_in_col=index_in_col,
                    daf=dict(state["daf"]) if state.get("daf") else None,
                    aramaic_groups=[aramaic],
                    hebrew_groups=[list(hebrew)] if hebrew else [],
                    chapter=state.get("chapter"),
                    footnote_refs=refs,
                )
                if any(p.size == 10.4 for p in hebrew):
                    current.region = "hebrew_notes"
                entries.append(current)
                current.last_row_y0 = row.y0
                current.bbox = [row.x0, row.y0, row.x1, row.y1]
                if others:
                    current.flags.append("unknown_font_in_row:" + ",".join(sorted({p.font for p in others})))
            else:
                # שורת עברית בלבד: המשך/תרגום מוערם לערך הקודם, אחרת "הערות עברית"
                if current is not None and row.y0 - current.bbox[3] < 22:
                    current.flags.append("wrapped_translation" if current.hebrew_groups else "stacked_translation")
                    current.last_row_y0 = row.y0
                    current.hebrew_groups.append(list(hebrew))
                    current.bbox = [min(current.bbox[0], row.x0), current.bbox[1], max(current.bbox[2], row.x1), max(current.bbox[3], row.y1)]
                    if any(p.size == 10.4 for p in hebrew):
                        current.region = "hebrew_notes"
                else:
                    record_non("hebrew_text", row)
                    current = None
    stats["entries"] = len(entries)
    stats["entries_chars"] = sum(
        len(p.text.strip()) + p.dropped_marks for e in entries for p in [q for g in e.aramaic_groups + e.hebrew_groups for q in g]
    )
    return entries, nonentries, {"stats": dict(stats), "header_daf": header_daf, "pieces": len(pieces)}


# ───────────────────────── המרה לרשומות ─────────────────────────


def entry_to_record(entry: Entry, source: str, cfg: dict[str, Any]) -> dict[str, Any]:
    aramaic_raw = " ".join(join_pieces(group) for group in entry.aramaic_groups)
    hebrew_raw = " ".join(join_pieces(group) for group in entry.hebrew_groups)
    flags = sorted(set(entry.flags))
    dropped = sum(p.dropped_marks for g in entry.aramaic_groups + entry.hebrew_groups for p in g)
    aramaic = clean_aramaic(aramaic_raw)
    hebrew = clean_gloss(hebrew_raw)
    if dropped:
        # ניקוד שלא ניתן למקם (נשמר ב-PDF כ-span נפרד ברוחב אפס): התרגום מוצג ללא ניקוד
        flags.append("niqqud_lost")
        hebrew = strip_marks(hebrew)
    confidence = 1.0
    if "wrapped_aramaic" in flags:
        confidence -= 0.2
    if entry.region == "table" and (len(hebrew) > 150 or (len(entry.hebrew_groups) >= 4 and len(hebrew) > 100)):
        # פסקת הסבר למילה עברית (לא שורת טבלה): נשמרת ברשומות אך אינה מועמדת למילון
        entry.region = "hebrew_notes"
    if not aramaic or not hebrew:
        flags.append("missing_side")
        confidence -= 0.6
    if "wrapped_translation" in flags:
        confidence -= 0.2
    if "stacked_translation" in flags:
        confidence -= 0.1
    if re.search(r"[A-Za-z0-9]", aramaic):
        flags.append("latin_or_digit_in_aramaic")
        confidence -= 0.3
    if re.search(r"[^א-ת\s\"'׳״\-֑-ׇ(),.?]", aramaic):
        flags.append("odd_char_in_aramaic")
        confidence -= 0.2
    if len(aramaic.split()) > 6:
        flags.append("long_aramaic_phrase")
        confidence -= 0.1
    if hebrew.count("(") != hebrew.count(")"):
        flags.append("unbalanced_parens_in_hebrew")
        confidence -= 0.2
    if re.search(r"[A-Za-z]", hebrew):
        flags.append("latin_in_hebrew")
        confidence -= 0.2
    if entry.region != "table":
        flags.append(f"region:{entry.region}")
        confidence -= 0.5
    daf = entry.daf
    rec_id = f"{source}-p{entry.page:03d}-{entry.col}{entry.index_in_col:02d}"
    pdf = cfg["sources"][source].get("pdf", "")
    return {
        "record_id": rec_id,
        "source": source,
        "aramaic_original": aramaic_raw.strip(),
        "aramaic": aramaic,
        "aramaic_normalized": normalize_key(aramaic),
        "hebrew_original": hebrew_raw.strip(),
        "hebrew_clean": hebrew,
        "pdf_page": entry.page,
        "daf": daf["daf"] if daf else None,
        "amud": daf["amud"] if daf else None,
        "daf_label": daf["label"] if daf else None,
        "masechet": cfg["sources"][source]["masechet"],
        "chapter": entry.chapter,
        "column": entry.col,
        "row_in_column": entry.index_in_col,
        "bbox": [round(v, 1) for v in entry.bbox],
        "source_text": f"{aramaic_raw.strip()} ⟵ {hebrew_raw.strip()}",
        "footnote_refs": entry.footnote_refs,
        "niqqud_marks_lost": dropped,
        "confidence": round(max(confidence, 0.0), 2),
        "flags": sorted(set(flags)),
        "region": entry.region,
        "review_status": "extracted",
        "pdf_ref": f"{Path(pdf).name}#page={entry.page}" if pdf else f"page={entry.page}",
        "notes": "",
    }


def extract_source(source: str, cfg: dict[str, Any], pages: range | None = None) -> dict[str, Any]:
    pdf_path = Path(cfg["sources"][source]["pdf"])
    if not pdf_path.exists():
        raise SystemExit(f"{source}: קובץ ה-PDF לא נמצא: {pdf_path} (קבעו ב-config.local.json)")
    doc = pymupdf.open(pdf_path)
    state: dict[str, Any] = {"daf": None, "chapter": None}
    all_records: list[dict] = []
    all_non: list[dict] = []
    page_rows: list[dict] = []
    for index in range(doc.page_count):
        page_no = index + 1
        if pages is not None and page_no not in pages:
            continue
        page = doc[page_no - 1]
        entries, non, info = process_page(page, page_no, state)
        records = [entry_to_record(e, source, cfg) for e in entries]
        all_records.extend(records)
        all_non.extend(non)
        stats = info["stats"]
        text_layer = stats["text_chars"]
        # בקרת שלמות עצמאית: ספירת אותיות עבריות בעמוד (get_text רגיל) מול כל מה שחולץ
        page_letters = Counter(ch for ch in page.get_text() if "א" <= ch <= "ת")
        out_letters = Counter(
            ch
            for text in [r["aramaic_original"] + r["hebrew_original"] for r in records] + [n["text"] for n in non]
            for ch in text
            if "א" <= ch <= "ת"
        )
        letter_diff = sum(((page_letters - out_letters) + (out_letters - page_letters)).values())
        page_rows.append(
            {
                "page": page_no,
                "text_chars": text_layer,
                "has_text_layer": int(text_layer >= 40),
                "images": len(page.get_images()),
                "entries": len(records),
                "table_entries": sum(1 for r in records if r["region"] == "table"),
                "low_confidence": sum(1 for r in records if r["confidence"] < 0.8),
                "non_entry_rows": len(non),
                "pua_removed": stats["pua_removed"],
                "header_daf": stats.get("header_daf", ""),
                "daf_at_start": records[0]["daf_label"] if records else "",
                "daf_at_end": state["daf"]["label"] if state.get("daf") else "",
                "letters_in_page": sum(page_letters.values()),
                "letter_diff": letter_diff,
                "chars_text": stats["text_chars"],
                "chars_accounted": stats["entries_chars"] + stats.get("chars_non", 0),
                "coverage": round((stats["entries_chars"] + stats.get("chars_non", 0)) / stats["text_chars"], 3) if stats["text_chars"] else "",
            }
        )
    return {"records": all_records, "non": all_non, "pages": page_rows, "page_count": doc.page_count}


def write_outputs(source: str, result: dict[str, Any], cfg: dict[str, Any]) -> None:
    write_jsonl(work_dir(cfg, "extract", f"{source}_entries.jsonl"), result["records"])
    write_jsonl(work_dir(cfg, "extract", f"{source}_nonentries.jsonl"), result["non"])
    with open(work_dir(cfg, "extract", f"{source}_pages.csv"), "w", encoding="utf-8-sig", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(result["pages"][0].keys()))
        writer.writeheader()
        writer.writerows(result["pages"])


def parse_pages(spec: str | None) -> range | None:
    if not spec:
        return None
    a, _, b = spec.partition("-")
    return range(int(a), int(b or a) + 1)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", choices=["siftey_gitin", "siftey_brachot", "all"], default="all")
    parser.add_argument("--pages", help="טווח עמודי PDF לדיבוג, למשל 9-12 (לא נכתב לקבצי הפלט)")
    args = parser.parse_args()
    cfg = load_config()
    sources = ["siftey_gitin", "siftey_brachot"] if args.source == "all" else [args.source]
    for source in sources:
        pages = parse_pages(args.pages)
        result = extract_source(source, cfg, pages)
        if pages is None:
            write_outputs(source, result, cfg)
        recs = result["records"]
        print(f"{source}: {len(recs)} entries, {len(result['non'])} non-entry rows, {result['page_count']} pages")
        if pages is not None:
            for rec in recs:
                print(f"  p{rec['pdf_page']} {rec['daf_label']} {rec['column']}{rec['row_in_column']:02d} [{rec['confidence']}] {rec['aramaic']} ⟵ {rec['hebrew_clean']} {rec['flags'] or ''}")


if __name__ == "__main__":
    main()
