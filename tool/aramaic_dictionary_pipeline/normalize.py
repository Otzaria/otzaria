"""שלב 4: איחוד כל המקורות לרשומות "טענה" (claim) אחידות, עם נרמול זהיר וביקורת איכות.

claim = טענה של מקור אחד (או כמה מקורות שזהים בטקסט) שלמילה ארמית מסוימת יש פירוש עברי.
הנרמול משמש להשוואה וזיהוי כפילויות בלבד; טקסט התצוגה נשמר כפי שחולץ.

פלט (work/merge/): claims.jsonl, existing_senses.jsonl, rejected.jsonl
"""

from __future__ import annotations

import argparse
import re
from collections import defaultdict
from typing import Any

from common import (
    HEBREW_LETTER_RE,
    load_config,
    normalize_gloss,
    normalize_key,
    parse_sense,
    read_jsonl,
    split_synonyms,
    stable_id,
    strip_marks,
    work_dir,
    write_jsonl,
)

# תווים מותרים במפתח ארמי "נקי": אותיות, ניקוד, רווח, מקף, גרש/גרשיים.
_CLEAN_KEY_RE = re.compile(r"^[א-ת֑-ׇ \-\"'׳״]+$")
_LATIN_RE = re.compile(r"[A-Za-z]")
_PAREN_RE = re.compile(r"\(([^()]*)\)")
# הערת גרסה בראש מפתח בשפתי גיטין: "[הג' הב"ח = באודנאי] באוזן שלי" / "[הג' הב"ח] בטסקא".
# המפתח האמיתי הוא רק מה שאחרי ההערה; ההערה עצמה ("הגהת הב"ח") אינה חלק מהמילה.
_VARIANT_READING_PREFIX_RE = re.compile(r"^\s*\[?\s*הג['׳]\s*הב[\"״]ח\s*\]?\s*=?\s*(?P<key>[^\[\]=]+?)\s*$")


def strip_variant_reading_prefix(key: str, gloss: str) -> tuple[str, str, bool]:
    """מסיר הערת גרסה "[הג' הב"ח ...]" ממפתח, ואת הסימנים העודפים ("=" בראש, "]" בסוף) מהפירוש."""
    match = _VARIANT_READING_PREFIX_RE.match(key)
    if not match:
        return key, gloss, False
    clean_gloss = gloss.strip()
    if clean_gloss.startswith("="):
        clean_gloss = clean_gloss[1:].strip()
    if clean_gloss.endswith("]") and clean_gloss.count("]") > clean_gloss.count("["):
        clean_gloss = clean_gloss[:-1].strip()
    return match.group("key").strip(), clean_gloss, True


def gloss_parts(gloss: str) -> tuple[list[str], list[str]]:
    """(מילים נרדפות ראשיות מנורמלות, הערות-סוגריים מנורמלות) של פירוש."""
    parens = [normalize_gloss(m) for m in _PAREN_RE.findall(gloss)]
    core_text = _PAREN_RE.sub(" ", gloss)
    core = [normalize_gloss(part) for part in split_synonyms(core_text.replace("/", ","))]
    return [c for c in core if c], [p for p in parens if p]


def key_issues(key: str) -> list[str]:
    issues: list[str] = []
    if not key.strip():
        issues.append("empty_key")
        return issues
    if not _CLEAN_KEY_RE.match(key):
        issues.append("key_has_unusual_characters")
    if not HEBREW_LETTER_RE.search(key):
        issues.append("key_without_letters")
    if len(key.split()) >= 4:
        # קטע משפט ולא ערך מילוני: ארבע מילים ומעלה — לבדיקה ידנית (ראו README, "היקף")
        issues.append("key_phrase_four_or_more_words")
    return issues


def gloss_issues(gloss: str) -> list[str]:
    issues: list[str] = []
    if not gloss.strip():
        issues.append("empty_gloss")
        return issues
    if _LATIN_RE.search(gloss):
        issues.append("latin_in_gloss")
    if gloss.count("(") != gloss.count(")") or gloss.count("[") != gloss.count("]"):
        issues.append("unbalanced_brackets")
    if any(token in gloss for token in ("***", "{", "}", "(=")):
        issues.append("conflicts_with_otzaria_markup")
    parsed = parse_sense(gloss)
    if parsed["text"] != gloss.strip() or parsed["expression"] or parsed["expansion"]:
        issues.append("not_plain_after_parse")
    if len(gloss) > 160:
        issues.append("gloss_very_long")
    if re.search(r"[^א-ת֑-ׇ ,.;:?!()\[\]\"'׳״\-–/0-9%=]", gloss):
        issues.append("gloss_unusual_characters")
    return issues


def build_existing(records: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """כל פירוש קיים בכל המילונים, לפי מזהי הפירוש היציבים של baseline."""
    out: list[dict[str, Any]] = []
    for rec in records:
        for index, sense in enumerate(rec["senses"]):
            core, parens = gloss_parts(sense["text"])
            out.append(
                {
                    "sense_id": sense["sense_id"],
                    "record_id": rec["record_id"],
                    "dictionary": rec["dictionary"],
                    "key": rec["key"],
                    "normalized_key": rec["normalized_key"],
                    "sense_index": index,
                    "raw": sense["raw"],
                    "expression": sense["expression"],
                    "expansion": sense["expansion"],
                    "text": sense["text"],
                    "text_normalized": normalize_gloss(sense["text"]),
                    "core": core,
                    "parens": parens,
                }
            )
    return out


def source_occurrence(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "source": row["source"],
        "record_id": row["record_id"],
        "pdf_page": row["pdf_page"],
        "daf_label": row.get("daf_label"),
        "masechet": row.get("masechet"),
        "confidence": row["confidence"],
        "flags": row["flags"],
    }


def build_claims(
    siftey_rows: list[dict[str, Any]], wikt_rows: list[dict[str, Any]]
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    claims: dict[tuple[str, str, str], dict[str, Any]] = {}
    rejected: list[dict[str, Any]] = []

    def reject(source: str, record_id: str, key: str, gloss: str, reason: str, extra: dict[str, Any] | None = None) -> None:
        rejected.append({"source": source, "record_id": record_id, "key": key, "gloss": gloss, "reason": reason, **(extra or {})})

    for row in siftey_rows:
        key, gloss = row["aramaic"], row["hebrew_clean"]
        raw_key, raw_gloss = key, gloss
        key, gloss, variant_reading = strip_variant_reading_prefix(key, gloss)
        if row["region"] != "table":
            reject(row["source"], row["record_id"], key, gloss, "outside_scope_hebrew_word_explanation", {"pdf_page": row["pdf_page"]})
            continue
        if not key or not gloss:
            reject(row["source"], row["record_id"], key, gloss, "extraction_missing_side", {"pdf_page": row["pdf_page"]})
            continue
        norm_key = normalize_key(key)
        norm_gloss = normalize_gloss(gloss)
        bucket = claims.setdefault(
            ("siftey", norm_key, norm_gloss),
            {
                "claim_id": "cl-" + stable_id("siftey", norm_key, norm_gloss),
                "normalized_key": norm_key,
                "display_key": strip_marks(key),
                "gloss": gloss,
                "gloss_normalized": norm_gloss,
                "origin": "siftey",
                "occurrences": [],
                "issues": set(),
            },
        )
        occurrence = source_occurrence(row)
        if variant_reading:
            occurrence["raw_key"], occurrence["raw_gloss"] = raw_key, raw_gloss
            bucket["issues"].add("variant_reading_prefix_stripped")
        bucket["occurrences"].append(occurrence)
        bucket["issues"].update(key_issues(key) + gloss_issues(gloss))
        bucket["issues"].update(f"extraction:{flag}" for flag in row["flags"] if flag in {"wrapped_aramaic", "unbalanced_parens_in_hebrew", "odd_char_in_aramaic", "stacked_translation", "wrapped_translation"})

    for row in wikt_rows:
        if not row["gloss_clean"]:
            reject("wiktionary", row["record_id"], row["lemma"], "", "no_aramaic_tagged_definition", {"page_id": row["page_id"]})
            continue
        gloss = row["gloss_clean"].rstrip(".").strip()
        norm_gloss = normalize_gloss(gloss)
        # למה ראשית + כתיבים חלופיים/כתיב מלא כמפתחות נוספים (הגמרא מדפיסה בכתיב מלא)
        keys = [(row["lemma"], row["lemma_normalized"], None)] + [
            (variant, normalize_key(variant), row["record_id"]) for variant in row.get("key_variants", [])
        ]
        for display, norm_key, variant_of in keys:
            bucket = claims.setdefault(
                ("wiktionary", norm_key, norm_gloss),
                {
                    "claim_id": "cl-" + stable_id("wiktionary", norm_key, norm_gloss),
                    "normalized_key": norm_key,
                    "display_key": strip_marks(display),
                    "gloss": gloss,
                    "gloss_normalized": norm_gloss,
                    "origin": "wiktionary",
                    "occurrences": [],
                    "issues": set(),
                },
            )
            bucket["occurrences"].append(
                {
                    "source": "wiktionary",
                    "record_id": row["record_id"] + ("" if variant_of is None else f"~{norm_key}"),
                    "page_id": row["page_id"],
                    "revision_id": row["revision_id"],
                    "permalink": row["permalink"],
                    "vocalized_lemma": row["lemma"],
                    "layer_hint": row["layer_hint"],
                    "variant_of": variant_of,
                    "confidence": 1.0,
                    "flags": [],
                }
            )
            bucket["issues"].update(key_issues(display) + gloss_issues(gloss))
            bucket["issues"].add("wiktionary_requires_human_review")
            if variant_of:
                bucket["issues"].add("key_is_variant_form_of_wiktionary_lemma")

    out: list[dict[str, Any]] = []
    for claim in claims.values():
        occurrences = sorted(claim["occurrences"], key=lambda o: (o["source"], o["record_id"]))
        sources = sorted({o["source"] for o in occurrences})
        claim.update(
            occurrences=occurrences,
            sources=sources,
            attestations=len(occurrences),
            min_confidence=min(o["confidence"] for o in occurrences),
            issues=sorted(claim["issues"]),
        )
        core, parens = gloss_parts(claim["gloss"])
        claim["core"], claim["parens"] = core, parens
        out.append(claim)
    out.sort(key=lambda c: (c["normalized_key"], c["gloss_normalized"]))
    return out, rejected


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.parse_args()
    cfg = load_config()
    existing = read_jsonl(work_dir(cfg, "baseline", "existing_records.jsonl"))
    siftey = read_jsonl(work_dir(cfg, "extract", "siftey_gitin_entries.jsonl")) + read_jsonl(
        work_dir(cfg, "extract", "siftey_brachot_entries.jsonl")
    )
    wikt = read_jsonl(work_dir(cfg, "extract", "wiktionary_entries.jsonl"))
    existing_senses = build_existing(existing)
    claims, rejected = build_claims(siftey, wikt)
    write_jsonl(work_dir(cfg, "merge", "existing_senses.jsonl"), existing_senses)
    write_jsonl(work_dir(cfg, "merge", "claims.jsonl"), claims)
    write_jsonl(work_dir(cfg, "merge", "rejected.jsonl"), rejected)
    by_key: dict[str, int] = defaultdict(int)
    for claim in claims:
        by_key[claim["normalized_key"]] += 1
    print(
        f"existing senses: {len(existing_senses)} | claims: {len(claims)} over {len(by_key)} keys | rejected at normalize: {len(rejected)}"
    )


if __name__ == "__main__":
    main()
