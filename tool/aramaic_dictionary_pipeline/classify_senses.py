"""שלבים 5-6: סיווג פירושים, קיבוץ טענות, החלטות אוטומטיות ותור בקרה ידנית.

עקרונות (ראו README, "מדיניות הכרעה"):
  * החלטה אוטומטית רק כשהיא טכנית וודאית: זהות טקסטואלית אחרי נרמול בטוח, אותה קבוצת
    מילים נרדפות בסדר/פיסוק שונה, הכלה מלאה בפירוש קיים בלי מידע נוסף, או מפתח חדש לגמרי
    עם פירוש יחיד, נקי ובביטחון חילוץ גבוה ממקור מותר (שפתי גיטין/ברכות).
  * כל מקרה אחר — משמעות שונה, חפיפה חלקית, מידע נוסף בסוגריים, סתירה, חילוץ חשוד,
    וכל ערך שמקורו בוויקימילון — נכנס לתור הבקרה עם *הצעה* בלבד. אין מיזוג טרנזיטיבי:
    קבוצות נוצרות רק מקשרי זהות ישירים (אותה קבוצת מילים נרדפות).
  * אף פירוש קיים אינו נמחק או נדרס; הצעות לשינוי פירוש קיים מסומנות במפורש.

פלט (work/merge/): auto_decisions.jsonl, queue.jsonl, classification_stats.json
"""

from __future__ import annotations

import argparse
import re
from collections import Counter, defaultdict
from typing import Any

from common import (
    load_config,
    normalize_gloss,
    read_jsonl,
    split_synonyms,
    stable_id,
    work_dir,
    write_json,
    write_jsonl,
)

PAREN_RE = re.compile(r"\(([^()]*)\)")
MIN_AUTO_CONFIDENCE = 0.9
# סיומות נטייה נפוצות — משמשות רק לרמז "הבדל דקדוקי" בתור הבקרה, לעולם לא למיזוג.
_INFLECTION_SUFFIXES = ("ים", "ות", "ו", "ה", "ת", "י", "נ", "כ", "מ")

# ───────────────────────── השוואת פירושים ─────────────────────────


def pieces_of(gloss: str) -> list[dict[str, Any]]:
    """מילים נרדפות בפירוש: טקסט תצוגה, ליבה מנורמלת (בלי סוגריים), והערות-סוגריים."""
    out = []
    for piece in split_synonyms(gloss.replace("/", ",")):
        parens = [normalize_gloss(p) for p in PAREN_RE.findall(piece)]
        core = normalize_gloss(PAREN_RE.sub(" ", piece))
        if core:
            out.append({"display": piece.strip(), "core": core, "parens": [p for p in parens if p]})
    return out


def core_set(gloss: str) -> frozenset[str]:
    return frozenset(p["core"] for p in pieces_of(gloss))


def stem_tokens(core: str) -> tuple[str, ...]:
    """גזע גס להשוואת רמזים בלבד: אותיות סופיות רגילות, עד שתי סיומות נטייה."""
    finals = str.maketrans("ךםןףץ", "כמנפצ")
    stems = []
    for token in core.translate(finals).split():
        for _ in range(2):
            for suffix in _INFLECTION_SUFFIXES:
                if len(token) > len(suffix) + 2 and token.endswith(suffix):
                    token = token[: -len(suffix)]
                    break
        stems.append(token)
    return tuple(stems)


def grammatical_hint(a: str, b: str) -> bool:
    """אותם גזעי-מילים אבל שונה בסיומת נטייה (יחיד/רבים, זכר/נקבה...): רמז לבודק בלבד."""
    sa = {stem_tokens(c) for c in core_set(a)}
    sb = {stem_tokens(c) for c in core_set(b)}
    return bool(sa & sb) and core_set(a) != core_set(b)


def relation(claim_gloss: str, sense_text: str) -> str:
    """identical | same_core | subset | superset | overlap | disjoint — מהטענה אל הפירוש."""
    if normalize_gloss(claim_gloss) == normalize_gloss(sense_text):
        return "identical"
    cc, cs = core_set(claim_gloss), core_set(sense_text)
    if not cc or not cs:
        return "disjoint"
    if cc == cs:
        return "same_core"
    if cc < cs:
        return "subset"
    if cc > cs:
        return "superset"
    if cc & cs:
        return "overlap"
    return "disjoint"


def parens_covered(claim_gloss: str, sense_text: str) -> bool:
    """האם כל הערות-הסוגריים של הטענה כבר מופיעות בפירוש (או שאין לה כאלה)."""
    # השוואה כמילים שלמות: "לא" אינה "מכוסה" בתוך "אלא"
    target = normalize_gloss(sense_text)
    return all(
        re.search(r"(?<![א-ת])" + re.escape(p) + r"(?![א-ת])", target)
        for p in (pp for piece in pieces_of(claim_gloss) for pp in piece["parens"])
    )


_RELATION_RANK = {"identical": 0, "same_core": 1, "subset": 2, "superset": 3, "overlap": 4, "disjoint": 5}


def best_relation(claim_gloss: str, senses: list[dict[str, Any]]) -> tuple[str, dict[str, Any] | None]:
    best: tuple[str, dict[str, Any] | None] = ("disjoint", None)
    for sense in senses:
        rel = relation(claim_gloss, sense["text"])
        if _RELATION_RANK[rel] < _RELATION_RANK[best[0]] or best[1] is None:
            best = (rel, sense)
    return best


# ───────────────────────── קיבוץ טענות ─────────────────────────


def richest(claims: list[dict[str, Any]]) -> dict[str, Any]:
    """הניסוח העשיר ביותר בקבוצה: יותר הערות-סוגריים, אחר כך נפוץ יותר, אחר כך ארוך, ואז לפי טקסט (יציב)."""
    return sorted(
        claims,
        key=lambda c: (-sum(len(p["parens"]) for p in pieces_of(c["gloss"])), -c["attestations"], -len(c["gloss"]), c["gloss"]),
    )[0]


def group_claims(claims: list[dict[str, Any]]) -> list[list[dict[str, Any]]]:
    """קבוצות לפי קשר ישיר בלבד (אותה קבוצת מילים נרדפות). בלי סגור טרנזיטיבי של דמיון."""
    parent = list(range(len(claims)))

    def find(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i in range(len(claims)):
        for j in range(i + 1, len(claims)):
            if core_set(claims[i]["gloss"]) == core_set(claims[j]["gloss"]):
                parent[find(i)] = find(j)
    groups: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for index, claim in enumerate(claims):
        groups[find(index)].append(claim)
    return [sorted(g, key=lambda c: c["claim_id"]) for _, g in sorted(groups.items())]


def parens_variants(group: list[dict[str, Any]]) -> bool:
    """האם בקבוצה הערות-סוגריים שונות שאינן הכלה זו בזו (מידע שיאבד במיזוג)."""
    best = richest(group)
    return any(not parens_covered(c["gloss"], best["gloss"]) for c in group)


# ───────────────────────── הצעות לתור הבקרה ─────────────────────────


def union_text(base: str, extra: str) -> str:
    """איחוד מילים נרדפות: פירוש בסיס + מילים מהפירוש הנוסף שחסרות בו (סדר יציב)."""
    have = {p["core"] for p in pieces_of(base)}
    additions = [p["display"] for p in pieces_of(extra) if p["core"] not in have]
    return ", ".join([base.strip().rstrip(".,"), *additions]) if additions else base


def claim_view(claim: dict[str, Any]) -> dict[str, Any]:
    return {
        "claim_id": claim["claim_id"],
        "gloss": claim["gloss"],
        "display_key": claim["display_key"],
        "origin": claim["origin"],
        "sources": claim["sources"],
        "attestations": claim["attestations"],
        "min_confidence": claim["min_confidence"],
        "issues": claim["issues"],
        "occurrences": claim["occurrences"][:12],
    }


def sense_view(sense: dict[str, Any]) -> dict[str, Any]:
    return {k: sense[k] for k in ("sense_id", "dictionary", "key", "raw", "expression", "text")}


def build_proposal(
    groups: list[list[dict[str, Any]]], existing: list[dict[str, Any]], key_has_wikt: bool = False
) -> dict[str, Any]:
    """הצעת מערכת לקבוצות שנותרו: מה להוסיף, מה רק תמיכה, ומה לבדוק. תמיד *הצעה*."""
    add_senses: list[dict[str, Any]] = []
    support: list[dict[str, Any]] = []
    modify: list[dict[str, Any]] = []
    notes: list[str] = []
    classes: set[str] = set()
    confidence = 0.9
    pending_groups = []
    for group in groups:
        rep = richest(group)
        rel, target = best_relation(rep["gloss"], existing) if existing else ("disjoint", None)
        ids = [c["claim_id"] for c in group]
        if rel in ("identical", "same_core", "subset") and target is not None:
            support.append({"claim_ids": ids, "target_sense_id": target["sense_id"], "relation": rel})
            classes.add("semantic_duplicate" if rel != "identical" else "exact_duplicate")
            if not parens_covered(rep["gloss"], target["text"]):
                notes.append(f"לטענה «{rep['gloss']}» יש הערת-הקשר שאינה בפירוש הקיים «{target['text']}» — הוצע לא להוסיף אותה")
            confidence = min(confidence, 0.8)
        elif rel in ("superset", "overlap") and target is not None:
            new_text = union_text(target["text"], rep["gloss"])
            modify.append({"sense_id": target["sense_id"], "old_text": target["text"], "new_text": new_text, "claim_ids": ids})
            classes.add("semantic_duplicate")
            notes.append(f"חפיפה חלקית עם «{target['text']}» ({rel}) — הוצע להרחיב את הפירוש הקיים (שינוי בפירוש קיים!)")
            confidence = min(confidence, 0.5)
        else:
            pending_groups.append((group, rep))
    # קבוצות חדשות: זהו אותן ביניהן — חפיפה → איחוד מוצע, אחרת משמעויות נפרדות
    placed: list[dict[str, Any]] = []
    for group, rep in sorted(pending_groups, key=lambda gr: (-sum(c["attestations"] for c in gr[0]), gr[1]["gloss"])):
        ids = [c["claim_id"] for c in group]
        text = rep["gloss"]
        merged = False
        for slot in placed:
            rel = relation(text, slot["text"])
            if rel in ("subset", "superset", "overlap"):
                slot["text"] = union_text(slot["text"], text)
                slot["claim_ids"].extend(ids)
                notes.append(f"«{text}» חופף ל«{slot['text']}» — הוצע לאחד")
                classes.add("semantic_duplicate")
                confidence = min(confidence, 0.5)
                merged = True
                break
        if not merged:
            if placed or existing:
                classes.add("grammatical_variant" if any(grammatical_hint(text, s["text"]) for s in placed + existing) else "distinct_sense")
                confidence = min(confidence, 0.6)
            placed.append({"text": text, "claim_ids": list(ids)})
    add_senses.extend(placed)
    if not classes:
        classes.add("distinct_sense")
    return {
        "classes": sorted(classes),
        "add_senses": add_senses,
        "support": support,
        "modify_existing": modify,
        "notes": notes,
        "confidence": round(confidence, 2),
    }


# ───────────────────────── מנוע ההחלטות ─────────────────────────


def claim_is_clean(claim: dict[str, Any]) -> bool:
    return claim["min_confidence"] >= MIN_AUTO_CONFIDENCE and not [
        i for i in claim["issues"] if not i.startswith("extraction:stacked")
    ]


def decide(
    existing_by_key: dict[str, list[dict[str, Any]]],
    other_by_key: dict[str, list[dict[str, Any]]],
    claims_by_key: dict[str, list[dict[str, Any]]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    auto: list[dict[str, Any]] = []
    queue: list[dict[str, Any]] = []

    def auto_decision(claim: dict[str, Any], action: str, cls: str, reason: str, target: str | None = None) -> None:
        auto.append(
            {
                "decision_id": "ad-" + stable_id(claim["claim_id"], action, target or ""),
                "claim_id": claim["claim_id"],
                "normalized_key": claim["normalized_key"],
                "action": action,
                "class": cls,
                "target_sense_id": target,
                "reason": reason,
                "gloss": claim["gloss"],
                "display_key": claim["display_key"],
                "sources": claim["sources"],
                "attestations": claim["attestations"],
                "auto": True,
            }
        )

    for key in sorted(claims_by_key):
        existing = existing_by_key.get(key, [])
        evidence = other_by_key.get(key, [])
        claims = claims_by_key[key]
        siftey = [c for c in claims if c["origin"] == "siftey"]
        wikt = [c for c in claims if c["origin"] == "wiktionary"]

        remaining: list[dict[str, Any]] = []
        for claim in siftey:
            rel, target = best_relation(claim["gloss"], existing) if existing else ("disjoint", None)
            if target is not None and rel == "identical":
                auto_decision(claim, "support_existing", "exact_duplicate", "זהות טקסטואלית אחרי נרמול בטוח", target["sense_id"])
            elif target is not None and rel in ("same_core", "subset") and parens_covered(claim["gloss"], target["text"]):
                auto_decision(
                    claim,
                    "support_existing",
                    "exact_duplicate",
                    "אותן מילים נרדפות בסדר/פיסוק שונה, או הכלה מלאה בפירוש קיים — בלי מידע נוסף",
                    target["sense_id"],
                )
            else:
                remaining.append(claim)

        groups = group_claims(remaining) if remaining else []
        key_issue_present = any("key_" in i or i.startswith("extraction:") for c in remaining for i in c["issues"])

        # מפתח חדש לגמרי, קבוצה אחת, כל הטענות נקיות => הוספה אוטומטית
        if not existing and len(groups) == 1 and all(claim_is_clean(c) for c in groups[0]) and not parens_variants(groups[0]):
            rep = richest(groups[0])
            for claim in groups[0]:
                auto_decision(
                    claim,
                    "add_entry",
                    "exact_duplicate" if claim is not rep and core_set(claim["gloss"]) == core_set(rep["gloss"]) and claim["gloss_normalized"] != rep["gloss_normalized"] else "new_entry",
                    "מפתח חדש לגמרי, פירוש יחיד נקי בביטחון חילוץ גבוה" if claim is rep else "ניסוח שקול (אותה קבוצת מילים) לטענה העשירה בקבוצה — נתמך בלבד",
                    None,
                )
            groups = []
        elif groups:
            proposal = build_proposal(groups, existing)
            reasons = sorted({i for g in groups for c in g for i in c["issues"]})
            queue.append(
                {
                    "item_id": "it-" + stable_id("cluster", key, *sorted(c["claim_id"] for g in groups for c in g)),
                    "kind": "sense_cluster",
                    "normalized_key": key,
                    "display_key": groups[0][0]["display_key"] if not existing else existing[0]["key"],
                    "existing_senses": [sense_view(s) for s in existing],
                    "evidence_other_dictionaries": [sense_view(s) for s in evidence],
                    "groups": [[claim_view(c) for c in g] for g in groups],
                    "issues": reasons,
                    "key_issue": key_issue_present,
                    "system_proposal": proposal,
                    "review_status": "pending",
                }
            )

        for claim in wikt:
            rel, target = best_relation(claim["gloss"], existing) if existing else ("disjoint", None)
            sift_groups = group_claims([c for c in siftey])
            sift_rel = None
            for g in sift_groups:
                r = relation(claim["gloss"], richest(g)["gloss"])
                if r in ("identical", "same_core"):
                    sift_rel = (r, richest(g)["claim_id"])
                    break
            proposal = build_proposal([[claim]], existing)
            if sift_rel:
                proposal["notes"].append(f"תואם בטקסט לטענת שפתי גיטין/ברכות {sift_rel[1]} ({sift_rel[0]})")
            queue.append(
                {
                    "item_id": "it-" + stable_id("wiktionary", claim["claim_id"]),
                    "kind": "wiktionary_candidate",
                    "normalized_key": key,
                    "display_key": claim["display_key"],
                    "existing_senses": [sense_view(s) for s in existing],
                    "evidence_other_dictionaries": [sense_view(s) for s in evidence],
                    "groups": [[claim_view(claim)]],
                    "issues": claim["issues"],
                    "key_issue": False,
                    "system_proposal": proposal,
                    "review_status": "pending",
                    "relation_to_existing": rel,
                }
            )
    return auto, queue


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.parse_args()
    cfg = load_config()
    existing_senses = read_jsonl(work_dir(cfg, "merge", "existing_senses.jsonl"))
    claims = read_jsonl(work_dir(cfg, "merge", "claims.jsonl"))
    existing_by_key: dict[str, list[dict[str, Any]]] = defaultdict(list)
    other_by_key: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for sense in existing_senses:
        (existing_by_key if sense["dictionary"] == cfg["target_dictionary"] else other_by_key)[sense["normalized_key"]].append(sense)
    claims_by_key: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for claim in claims:
        claims_by_key[claim["normalized_key"]].append(claim)
    auto, queue = decide(existing_by_key, other_by_key, claims_by_key)
    write_jsonl(work_dir(cfg, "merge", "auto_decisions.jsonl"), auto)
    write_jsonl(work_dir(cfg, "merge", "queue.jsonl"), queue)
    stats = {
        "claims_total": len(claims),
        "keys_with_claims": len(claims_by_key),
        "auto_decisions": len(auto),
        "auto_by_action": Counter(a["action"] for a in auto),
        "auto_by_class": Counter(a["class"] for a in auto),
        "queue_items": len(queue),
        "queue_by_kind": Counter(q["kind"] for q in queue),
        "queue_by_proposal_class": Counter(c for q in queue for c in q["system_proposal"]["classes"]),
        "queue_with_modification_of_existing": sum(1 for q in queue if q["system_proposal"]["modify_existing"]),
    }
    write_json(work_dir(cfg, "merge", "classification_stats.json"), stats)
    for k, v in stats.items():
        print(k, dict(v) if isinstance(v, Counter) else v)


if __name__ == "__main__":
    main()
