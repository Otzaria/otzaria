"""שלבים 7-10: מיזוג דטרמיניסטי של החלטות (אוטומטיות + אנושיות) לתוך מודל הביניים.

קלט: baseline/existing_records.jsonl, merge/claims.jsonl, merge/auto_decisions.jsonl,
      merge/queue.jsonl, review/decisions.jsonl (החלטות הבודק; האחרונה לכל פריט גוברת).
פלט: merge/merged_entries.jsonl (רשומה לכל מפתח, עם רשימת משמעויות מובחנות ומקורותיהן),
     merge/merge_log.jsonl (כל שינוי ביחס למילון המקורי, עם הסיבה להכרעה).

ברירת מחדל: מיוצא רק מה שאושר — החלטות אוטומטיות טכניות וודאיות + החלטות בודק.
`--include-agent-suggestions` מוסיף גם הצעות הסוכן (לתצוגה מקדימה ובדיקות בלבד).
`--include-proposals` מוסיף את הצעת המערכת לכל פריט תלוי ועומד (לתצוגה מקדימה בלבד).
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path
from typing import Any

from classify_senses import group_claims, parens_covered, relation, richest
from common import (
    normalize_gloss,
    normalize_key,
    parse_sense,
    load_config,
    read_jsonl,
    stable_id,
    work_dir,
    write_jsonl,
)

BACKSLASH = chr(92)
CORRECTIONS_PATH = Path(__file__).resolve().parent / "manual_key_corrections.json"


def load_text_corrections() -> dict[tuple[str, str], dict[str, Any]]:
    """תיקוני טקסט ידניים מצומצמים (key, text מקורי) ← text מתוקן, עם סיבה; מתועדים ביומן המיזוג."""
    if not CORRECTIONS_PATH.exists():
        return {}
    rows = json.loads(CORRECTIONS_PATH.read_text(encoding="utf-8")).get("text_corrections", [])
    return {(normalize_key(row["key"]), row["from"]): row for row in rows}


def load_key_corrections() -> dict[str, dict[str, Any]]:
    """תיקוני מפתח ידניים (manual_key_corrections.json): מפתח כפי שחולץ ← המפתחות הנכונים, עם סיבה. מפתח הטבלה מנורמל."""
    if not CORRECTIONS_PATH.exists():
        return {}
    rows = json.loads(CORRECTIONS_PATH.read_text(encoding="utf-8"))["corrections"]
    return {normalize_key(row["extracted_key"]): row for row in rows}


def render_sense(text: str, expression: str | None) -> str:
    return f"{{{expression}}} {text}" if expression else text


def load_decisions(path) -> dict[str, dict[str, Any]]:
    """ההחלטה האחרונה לכל פריט. action=revert מבטל רק את ההחלטה האחרונה של הפריט (מחסנית) ומחזיר את הקודמת לה."""
    history: dict[str, list[dict[str, Any]]] = {}
    if not path.exists():
        return {}
    for row in read_jsonl(path, tolerate_truncated_tail=True):
        stack = history.setdefault(row["item_id"], [])
        if row["action"] == "revert":
            if stack:
                stack.pop()
        else:
            stack.append(row)
    return {item_id: stack[-1] for item_id, stack in history.items() if stack}


def proposal_sha(proposal: dict[str, Any]) -> str:
    """טביעת אצבע של הצעת המערכת; נשמרת בהחלטת accept_proposal כדי לזהות שהצעה השתנתה אחרי האישור."""
    return stable_id(json.dumps(proposal, ensure_ascii=False, sort_keys=True), length=16)


def _is_combining_mark(ch: str) -> bool:
    code = ord(ch)
    return 0x591 <= code <= 0x5C7 and code not in (0x5BE, 0x5C0, 0x5C3, 0x5C6)


def clean_new_text(text: str) -> str:
    """ניקוי ארטיפקטים של חילוץ בטקסט משמעות חדשה: מפריד "\\" ← "/", פסיק יתום בתחילה, וסימני ניקוד שאינם צמודים
    לאות (אחרי נקודה/מקף/גרש: ניקוד שאבד את מקומו בחילוץ). הטקסט המקורי נשמר ביומן ב-source_text."""
    text = text.replace(BACKSLASH, "/").lstrip(", ").strip()
    out: list[str] = []
    attached = False
    for ch in text:
        if _is_combining_mark(ch):
            if attached:
                out.append(ch)
            continue
        attached = "א" <= ch <= "ת"
        out.append(ch)
    return "".join(out)


def vocalized_expression(claim: dict[str, Any]) -> str | None:
    for occ in claim["occurrences"]:
        lemma = occ.get("vocalized_lemma")
        if lemma and "(" not in lemma and " או " not in lemma and any("ְ" <= ch <= "ׇ" for ch in lemma):
            return lemma.strip()
    return None


def build_model(
    existing_records: list[dict[str, Any]],
    claims: list[dict[str, Any]],
    auto: list[dict[str, Any]],
    queue: list[dict[str, Any]],
    decisions: dict[str, dict[str, Any]],
    agent: dict[str, dict[str, Any]],
    target_dictionary: str,
    include_proposals: bool,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    claims_by_id = {c["claim_id"]: c for c in claims}
    corrections = load_key_corrections()
    text_corrections = load_text_corrections()
    entries: dict[str, dict[str, Any]] = {}
    sense_index: dict[str, dict[str, Any]] = {}
    for rec in existing_records:
        if rec["dictionary"] != target_dictionary:
            continue
        entry = entries.setdefault(
            rec["normalized_key"],
            {"normalized_key": rec["normalized_key"], "display_key": rec["key"], "existing_records": [], "senses": [], "changed": False},
        )
        entry["existing_records"].append({"record_id": rec["record_id"], "key": rec["key"], "raw_value": rec["raw_value"], "position": rec["position"]})
        for sense in rec["senses"]:
            model = {
                "sense_id": sense["sense_id"],
                "text": sense["text"],
                "expression": sense["expression"],
                "raw": sense["raw"],
                "origin": "existing",
                "status": "existing",
                "support": [],
                "decisions": [],
            }
            entry["senses"].append(model)
            sense_index[sense["sense_id"]] = model

    log: list[dict[str, Any]] = []
    pending: list[dict[str, Any]] = []

    def support_of(claim_ids: list[str]) -> list[dict[str, Any]]:
        out = []
        for cid in claim_ids:
            claim = claims_by_id[cid]
            out.append(
                {
                    "claim_id": cid,
                    "origin": claim["origin"],
                    "sources": claim["sources"],
                    "attestations": claim["attestations"],
                    "occurrences": [{k: o.get(k) for k in ("source", "record_id", "pdf_page", "daf_label", "page_id", "revision_id", "permalink")} for o in claim["occurrences"][:20]],
                }
            )
        return out

    def add_sense(key: str, text: str, claim_ids: list[str], status: str, decision_id: str, cls: str, reason: str, display_key: str | None = None, split_key: bool = False) -> None:
        claim = claims_by_id[claim_ids[0]]
        entry = entries.setdefault(
            key, {"normalized_key": key, "display_key": display_key or claim["display_key"], "existing_records": [], "senses": [], "changed": False}
        )
        source_text = text
        text = clean_new_text(text)
        fix = text_corrections.get((key, text))
        if fix:
            log.append({"change": "manual_text_correction", "key": key, "from": text, "to": fix["to"], "reason": fix["reason"], "status": "manual_correction"})
            text = fix["to"]
        expression = vocalized_expression(claim) if claim["origin"] == "wiktionary" else None
        same_text = next((s for s in entry["senses"] if normalize_gloss(parse_sense(s["raw"])["text"]) == normalize_gloss(text)), None)
        if same_text is not None:
            # הוספה זהה בטקסט (אחרי נרמול) למשמעות שכבר בערך: כפילות — נרשמת כתמיכה בלבד
            support_sense(same_text["sense_id"], claim_ids, decision_id, "exact_duplicate", "הוספה שזהה בטקסט למשמעות קיימת בערך הוסבה לתמיכה", key)
            return
        if split_key:
            # מפתח שפוצל בתיקון ידני לא עבר סיווג מול ערכים קיימים: כמעט-כפילות נרשמת כתמיכה ולא כמשמעות חדשה
            near = next((s for s in entry["senses"] if relation(text, s["text"]) in ("identical", "same_core", "subset") and parens_covered(text, s["text"])), None)
            if near is not None:
                support_sense(near["sense_id"], claim_ids, decision_id, "semantic_duplicate", "מפתח מפוצל: הפירוש כלול במשמעות קיימת, נרשם כתמיכה", key)
                return
        sense_id = "ns-" + stable_id(key, text)
        if any(s["sense_id"] == sense_id for s in entry["senses"]):
            sense_index[sense_id]["support"].extend(support_of(claim_ids))
            return
        model = {
            "sense_id": sense_id,
            "text": text,
            "expression": expression,
            "raw": render_sense(text, expression),
            "origin": "wiktionary" if any(claims_by_id[c]["origin"] == "wiktionary" for c in claim_ids) else "siftey",
            "status": status,
            "support": support_of(claim_ids),
            "decisions": [decision_id],
        }
        entry["senses"].append(model)
        entry["changed"] = True
        sense_index[sense_id] = model
        log_row = {"change": "add_sense", "key": key, "sense_id": sense_id, "text": text, "class": cls, "reason": reason, "decision": decision_id, "status": status}
        if source_text != text:
            log_row["source_text"] = source_text
        log.append(log_row)

    def support_sense(target_id: str, claim_ids: list[str], decision_id: str, cls: str, reason: str, key: str) -> None:
        target = sense_index.get(target_id)
        if target is None:
            return
        target["support"].extend(support_of(claim_ids))
        target["decisions"].append(decision_id)
        log.append({"change": "support_existing", "key": key, "sense_id": target_id, "text": target["text"], "class": cls, "reason": reason, "decision": decision_id, "status": "supported"})

    logged_corrections: set[str] = set()
    modified_senses: set[str] = set()

    def add_with_corrections(key: str, text: str, claim_ids: list[str], status: str, decision_id: str, cls: str, reason: str, item_id: str) -> None:
        correction = corrections.get(key)
        if not correction:
            add_sense(key, text, claim_ids, status, decision_id, cls, reason)
            return
        if key not in logged_corrections:
            logged_corrections.add(key)
            log.append({"change": "manual_key_correction", "key": key, "item_id": item_id, "to_keys": correction["keys"], "reason": correction["reason"], "status": "manual_correction"})
        for target_key in correction["keys"]:
            add_sense(normalize_key(target_key), correction.get("gloss_prefix", "") + text, claim_ids, status, decision_id, cls, reason, display_key=target_key, split_key=True)

    # 1) החלטות אוטומטיות
    support_auto = [a for a in auto if a["action"] == "support_existing"]
    for dec in sorted(support_auto, key=lambda d: d["decision_id"]):
        support_sense(dec["target_sense_id"], [dec["claim_id"]], dec["decision_id"], dec["class"], dec["reason"], dec["normalized_key"])
    by_key: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for dec in auto:
        if dec["action"] == "add_entry":
            by_key[dec["normalized_key"]].append(dec)
    for key in sorted(by_key):
        key_claims = [claims_by_id[d["claim_id"]] for d in by_key[key]]
        for group in group_claims(key_claims):
            rep = richest(group)
            add_with_corrections(key, rep["gloss"], [c["claim_id"] for c in group], "auto_approved", by_key[key][0]["decision_id"], "new_entry", "מפתח חדש לגמרי, פירוש יחיד נקי בביטחון חילוץ גבוה", by_key[key][0]["decision_id"])

    # 2) תור הבקרה
    for item in sorted(queue, key=lambda it: it["item_id"]):
        decision = decisions.get(item["item_id"])
        status = "human_approved"
        if decision is None and item["item_id"] in agent:
            decision, status = agent[item["item_id"]], "agent_suggested"
        if decision is None and include_proposals:
            proposal = item["system_proposal"]
            decision = {"action": "accept_proposal", **{k: proposal[k] for k in ("add_senses", "support", "modify_existing")}}
            status = "system_proposed"
        if decision is None or decision["action"] in ("skip", "defer"):
            pending.append(item)
            continue
        key = item["normalized_key"]
        if decision["action"] == "accept_proposal" and decision.get("proposal_sha") not in (None, proposal_sha(item["system_proposal"])):
            # הצעת המערכת השתנתה אחרי שאושרה: האישור אינו חל על ההצעה החדשה
            log.append({"change": "proposal_changed_after_approval", "key": key, "item_id": item["item_id"], "status": status})
            pending.append(item)
            continue
        if decision["action"] == "reject":
            log.append({"change": "reject_item", "key": key, "item_id": item["item_id"], "reason": decision.get("notes", ""), "status": status})
            continue
        source = decision if decision["action"] == "custom" else decision
        if decision["action"] == "accept_proposal" and "add_senses" not in decision:
            proposal = item["system_proposal"]
            source = {k: proposal[k] for k in ("add_senses", "support", "modify_existing")}
        cls = (decision.get("class") or item["system_proposal"]["classes"][0]) if item["system_proposal"]["classes"] else "uncertain"
        dec_id = "hd-" + stable_id(item["item_id"], str(decision.get("ts", "")), decision["action"])
        for sup in source.get("support", []):
            support_sense(sup["target_sense_id"], sup["claim_ids"], dec_id, cls, decision.get("notes", ""), key)
        for mod in source.get("modify_existing", []):
            target = sense_index.get(mod["sense_id"])
            if target is None or target["text"] != mod.get("old_text", target["text"]):
                log.append({"change": "modification_skipped", "key": key, "item_id": item["item_id"], "sense_id": mod["sense_id"], "reason": "target_missing_or_text_changed", "decision": dec_id, "status": status})
                continue
            if not (decision.get("confirm_modify_existing") is True and status == "human_approved"):
                # שינוי פירוש קיים מחייב אישור מפורש וייעודי (confirm_modify_existing); אישור רגיל של פריט אינו מספיק
                log.append({"change": "modification_not_confirmed", "key": key, "item_id": item["item_id"], "sense_id": mod["sense_id"], "old": target["raw"], "proposed": mod["new_text"], "decision": dec_id, "status": status})
                continue
            if mod["sense_id"] in modified_senses:
                log.append({"change": "modification_skipped", "key": key, "item_id": item["item_id"], "sense_id": mod["sense_id"], "reason": "competing_modification_of_same_sense", "decision": dec_id, "status": status})
                continue
            old_raw = target["raw"]
            # new_raw: עריכה ידנית שמשנה גם את התחביר (למשל הסרת "(=...)"); אחרת מוחלף טקסט המשמעות (המופע האחרון, אחרי הביטוי וההרחבה)
            new_raw = mod.get("new_raw")
            if not new_raw:
                index = old_raw.rfind(target["text"])
                new_raw = old_raw[:index] + mod["new_text"] + old_raw[index + len(target["text"]):] if index >= 0 else ""
            if not new_raw or parse_sense(new_raw)["text"] != mod["new_text"]:
                log.append({"change": "modification_skipped", "key": key, "item_id": item["item_id"], "sense_id": mod["sense_id"], "reason": "could_not_rebuild_sense_text", "decision": dec_id, "status": status})
                continue
            modified_senses.add(mod["sense_id"])
            target["raw"] = new_raw
            target["text"] = mod["new_text"]
            target["status"] = "modified_" + status
            target["support"].extend(support_of(mod.get("claim_ids", [])))
            target["decisions"].append(dec_id)
            entries[key]["changed"] = True
            log.append({"change": "modify_existing_sense", "key": key, "sense_id": mod["sense_id"], "old": old_raw, "new": target["raw"], "class": cls, "decision": dec_id, "status": status})
        for add in source.get("add_senses", []):
            add_with_corrections(key, add["text"], add["claim_ids"], status, dec_id, cls, decision.get("notes", ""), item["item_id"])
    return list(entries.values()), log, pending


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--include-agent-suggestions", action="store_true")
    parser.add_argument("--include-proposals", action="store_true")
    parser.add_argument("--tag", default="merged", help="תחילית קובצי הפלט (למשל preview)")
    args = parser.parse_args()
    cfg = load_config()
    existing = read_jsonl(work_dir(cfg, "baseline", "existing_records.jsonl"))
    claims = read_jsonl(work_dir(cfg, "merge", "claims.jsonl"))
    auto = read_jsonl(work_dir(cfg, "merge", "auto_decisions.jsonl"))
    queue = read_jsonl(work_dir(cfg, "merge", "queue.jsonl"))
    decisions = load_decisions(work_dir(cfg, "review", "decisions.jsonl"))
    agent: dict[str, dict[str, Any]] = {}
    if args.include_agent_suggestions:
        agent = load_decisions(work_dir(cfg, "review", "agent_suggestions.jsonl"))
    entries, log, pending = build_model(existing, claims, auto, queue, decisions, agent, cfg["target_dictionary"], args.include_proposals)
    # ערכים: קודם הקיימים לפי מיקום מקורי, אחר כך החדשים — המיון הסופי נעשה ב-export
    entries.sort(key=lambda e: (e["existing_records"][0]["position"] if e["existing_records"] else 10**9, e["normalized_key"]))
    write_jsonl(work_dir(cfg, "merge", f"{args.tag}_entries.jsonl"), entries)
    write_jsonl(work_dir(cfg, "merge", f"{args.tag}_log.jsonl"), log)
    write_jsonl(work_dir(cfg, "merge", f"{args.tag}_pending.jsonl"), pending)
    added = sum(1 for e in entries if not e["existing_records"])
    print(f"entries: {len(entries)} (new keys {added}) | log {len(log)} | pending items {len(pending)} | human decisions {len(decisions)}")


if __name__ == "__main__":
    main()
