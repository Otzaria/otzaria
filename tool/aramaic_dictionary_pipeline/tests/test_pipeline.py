"""בדיקות יחידה לצינור (unittest, בלי תלות חיצונית):  py -m unittest discover -s tests"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from classify_senses import decide, grammatical_hint, group_claims, parens_covered, relation  # noqa: E402  (parens_covered נבדק גם להלן)
from common import hebrew_sort_key, normalize_gloss, normalize_key, parse_sense, split_senses, split_synonyms  # noqa: E402
from export import SEP, build_target_list  # noqa: E402
from extract_pdfs import Piece, clean_gloss, fix_brackets, hebrew_numeral, join_pieces, parse_daf  # noqa: E402
from extract_wiktionary import split_lemma, strip_markup  # noqa: E402
from merge import build_model  # noqa: E402
from normalize import gloss_issues, key_issues, strip_variant_reading_prefix  # noqa: E402


def claim(key: str, gloss: str, origin: str = "siftey", conf: float = 1.0, attest: int = 1, issues=None) -> dict:
    from normalize import gloss_parts

    core, parens = gloss_parts(gloss)
    return {
        "claim_id": "cl-" + key + "-" + gloss, "normalized_key": key, "display_key": key, "gloss": gloss,
        "gloss_normalized": normalize_gloss(gloss), "origin": origin, "occurrences": [{"source": "siftey_gitin", "record_id": "r", "confidence": conf, "flags": []}],
        "sources": ["siftey_gitin"], "attestations": attest, "min_confidence": conf, "issues": issues or [], "core": core, "parens": parens,
    }


def esense(key: str, text: str, n: int = 1) -> dict:
    return {"sense_id": f"ex-d-{key}-s{n}", "record_id": f"ex-d-{key}", "dictionary": "מילון פשיטא", "key": key, "normalized_key": key,
            "raw": text, "text": text, "expression": None, "expansion": None}


class NormalizationTests(unittest.TestCase):
    def test_key_keeps_letters_and_quotes_distinct(self) -> None:
        self.assertEqual(normalize_key("אַבָּרָא"), "אברא")
        self.assertNotEqual(normalize_key('א"ל'), normalize_key("אל"))
        self.assertEqual(normalize_key("א''ל"), 'א"ל')
        self.assertNotEqual(normalize_key("מלכה"), normalize_key("מלכא"))  # אין איחוד ה/א
        self.assertNotEqual(normalize_key("חכמים"), normalize_key("חכמין"))  # אין איחוד ם/ן

    def test_gloss_normalization_ignores_punctuation_only(self) -> None:
        self.assertEqual(normalize_gloss("כלום?, משום."), normalize_gloss("כלום משום"))
        self.assertNotEqual(normalize_gloss("נצרך לו"), normalize_gloss("נצרכו לו"))

    def test_otzaria_syntax_roundtrip(self) -> None:
        raw = "{אַהֲנֵי} הועיל *** {אַהָנֵי} (=א הני) על אלה"
        senses = split_senses(raw)
        self.assertEqual(len(senses), 2)
        second = parse_sense(senses[1])
        self.assertEqual((second["expression"], second["expansion"], second["text"]), ("אַהָנֵי", "א הני", "על אלה"))

    def test_synonym_split_ignores_commas_inside_parentheses(self) -> None:
        self.assertEqual(split_synonyms("חותך (מקצר, גוזז), חותך"), ["חותך (מקצר, גוזז)", "חותך"])

    def test_sort_key_is_stable_and_final_letters_do_not_break_order(self) -> None:
        keys = ["מאי חזית", "מאי", "מאיכא", "אך", "אכא"]
        self.assertEqual(sorted(keys, key=hebrew_sort_key), ["אך", "אכא", "מאי", "מאי חזית", "מאיכא"])


class RelationTests(unittest.TestCase):
    def test_relations(self) -> None:
        self.assertEqual(relation("יש", "יש"), "identical")
        self.assertEqual(relation("למדים, מלומדים", "מלומדים, למדים"), "same_core")
        self.assertEqual(relation("למדים", "למדים, מלומדים"), "subset")
        self.assertEqual(relation("למדים, מלומדים, ידועים", "למדים, מלומדים"), "superset")
        self.assertEqual(relation("אמת", "אבר, עופרת"), "disjoint")

    def test_no_transitive_grouping(self) -> None:
        a, b, c = claim("k", "א, ב"), claim("k", "ב, ג"), claim("k", "ג, ד")
        groups = group_claims([a, b, c])
        self.assertEqual(len(groups), 3)  # א~ב וב~ג חופפים, אך אינם מקובצים אוטומטית

    def test_parens_coverage(self) -> None:
        self.assertTrue(parens_covered("חותך", "חותך, גוזז"))
        self.assertFalse(parens_covered("חותך (מקצר)", "חותך, גוזז"))
        self.assertTrue(parens_covered("חותך (מקצר)", "חותך (מקצר), גוזז"))

    def test_grammatical_hint(self) -> None:
        self.assertTrue(grammatical_hint("נצרך לו", "נצרכו לו"))
        self.assertFalse(grammatical_hint("אמת", "עופרת"))


class DecisionTests(unittest.TestCase):
    def run_decide(self, existing, claims):
        by_key = {}
        for s in existing:
            by_key.setdefault(s["normalized_key"], []).append(s)
        cl = {}
        for c in claims:
            cl.setdefault(c["normalized_key"], []).append(c)
        return decide(by_key, {}, cl)

    def test_exact_and_contained_duplicates_are_automatic(self) -> None:
        existing = [esense("גמירי", "למדים, מלומדים")]
        auto, queue = self.run_decide(existing, [claim("גמירי", "למדים"), claim("גמירי", "מלומדים, למדים")])
        self.assertEqual([d["action"] for d in auto], ["support_existing", "support_existing"])
        self.assertEqual(queue, [])

    def test_distinct_meaning_goes_to_review_and_is_never_automatic(self) -> None:
        existing = [esense("אברא", "אמת")]
        auto, queue = self.run_decide(existing, [claim("אברא", "אבר, עופרת")])
        self.assertEqual(auto, [])
        self.assertEqual(len(queue), 1)
        self.assertEqual(queue[0]["system_proposal"]["classes"], ["distinct_sense"])

    def test_new_key_single_clean_claim_is_automatic(self) -> None:
        auto, queue = self.run_decide([], [claim("חדש", "חדשה")])
        self.assertEqual((len(auto), len(queue)), (1, 0))
        self.assertEqual(auto[0]["action"], "add_entry")

    def test_new_key_conflicting_claims_need_review(self) -> None:
        _, queue = self.run_decide([], [claim("אטו", "כלום"), claim("אטו", "משום")])
        self.assertEqual(len(queue), 1)

    def test_low_confidence_or_issue_blocks_auto(self) -> None:
        auto, queue = self.run_decide([], [claim("חדש", "חדשה", conf=0.8, issues=["extraction:wrapped_translation"])])
        self.assertEqual((len(auto), len(queue)), (0, 1))

    def test_wiktionary_always_queued_even_when_duplicate(self) -> None:
        existing = [esense("אסיא", "רופא")]
        auto, queue = self.run_decide(existing, [claim("אסיא", "רופא", origin="wiktionary", issues=["wiktionary_requires_human_review"])])
        self.assertEqual(auto, [])
        self.assertEqual(queue[0]["kind"], "wiktionary_candidate")


class MergeExportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.record = {
            "record_id": "ex-d-אברא", "dictionary": "מילון פשיטא", "position": 0, "key": "אברא", "normalized_key": "אברא",
            "raw_value": "{אַבָּרָא} אמת. *** {אֲבָרָא } אבר, עופרת.",
            "senses": [
                {"sense_id": "ex-d-אברא-s1", "raw": "{אַבָּרָא} אמת.", "text": "אמת.", "expression": "אַבָּרָא", "expansion": None},
                {"sense_id": "ex-d-אברא-s2", "raw": "{אֲבָרָא } אבר, עופרת.", "text": "אבר, עופרת.", "expression": "אֲבָרָא ", "expansion": None},
            ],
        }

    def test_existing_value_is_byte_identical_when_unchanged_and_additions_append(self) -> None:
        cl = claim("חדש", "חדשה")
        entries, log, pending = build_model(
            [self.record], [cl],
            [{"decision_id": "ad-1", "claim_id": cl["claim_id"], "normalized_key": "חדש", "action": "add_entry", "class": "new_entry", "target_sense_id": None, "reason": "", "gloss": "חדשה", "display_key": "חדש", "sources": ["siftey_gitin"], "attestations": 1, "auto": True}],
            [], {}, {}, "מילון פשיטא", False,
        )
        items = build_target_list(entries)
        self.assertEqual(items, [{"אברא": self.record["raw_value"]}, {"חדש": "חדשה"}])
        self.assertEqual(pending, [])

    def test_added_sense_is_appended_with_separator_and_existing_untouched(self) -> None:
        cl = claim("אברא", "כוס")
        queue = [{"item_id": "it-1", "normalized_key": "אברא", "system_proposal": {"classes": ["distinct_sense"], "add_senses": [{"text": "כוס", "claim_ids": [cl["claim_id"]]}], "support": [], "modify_existing": []}}]
        entries, _, _ = build_model([self.record], [cl], [], queue, {"it-1": {"item_id": "it-1", "action": "accept_proposal", "ts": "t"}}, {}, "מילון פשיטא", False)
        value = list(build_target_list(entries)[0].values())[0]
        self.assertEqual(value, self.record["raw_value"] + SEP + "כוס")

    def test_existing_sense_modification_needs_explicit_confirmation(self) -> None:
        cl = claim("אברא", "אמת, נכון")
        mod = {"sense_id": "ex-d-אברא-s1", "old_text": "אמת.", "new_text": "אמת, נכון", "claim_ids": [cl["claim_id"]]}
        queue = [{"item_id": "it-1", "normalized_key": "אברא", "system_proposal": {"classes": ["semantic_duplicate"], "add_senses": [], "support": [], "modify_existing": [mod]}}]
        plain = {"it-1": {"item_id": "it-1", "action": "accept_proposal", "ts": "t"}}
        entries, log, _ = build_model([self.record], [cl], [], queue, plain, {}, "מילון פשיטא", False)
        self.assertEqual(list(build_target_list(entries)[0].values())[0], self.record["raw_value"])
        self.assertIn("modification_not_confirmed", [row["change"] for row in log])
        confirmed = {"it-1": {**plain["it-1"], "confirm_modify_existing": True}}
        entries, _, _ = build_model([self.record], [cl], [], queue, confirmed, {}, "מילון פשיטא", False)
        self.assertIn("אמת, נכון", list(build_target_list(entries)[0].values())[0])

    def test_backslash_separator_becomes_slash_in_new_senses(self) -> None:
        cl = claim("חדש", "בן מחוז" + chr(92) + "כרך")
        queue = [{"item_id": "it-1", "normalized_key": "חדש", "system_proposal": {"classes": ["distinct_sense"], "add_senses": [{"text": cl["gloss"], "claim_ids": [cl["claim_id"]]}], "support": [], "modify_existing": []}}]
        entries, _, _ = build_model([self.record], [cl], [], queue, {"it-1": {"item_id": "it-1", "action": "accept_proposal", "ts": "t"}}, {}, "מילון פשיטא", False)
        self.assertEqual({k: v for e in build_target_list(entries) for k, v in e.items()}["חדש"], "בן מחוז/כרך")

    def test_pending_items_are_not_exported_by_default(self) -> None:
        cl = claim("אברא", "כוס")
        queue = [{"item_id": "it-1", "normalized_key": "אברא", "system_proposal": {"classes": ["distinct_sense"], "add_senses": [{"text": "כוס", "claim_ids": [cl["claim_id"]]}], "support": [], "modify_existing": []}}]
        entries, _, pending = build_model([self.record], [cl], [], queue, {}, {}, "מילון פשיטא", False)
        self.assertEqual(list(build_target_list(entries)[0].values())[0], self.record["raw_value"])
        self.assertEqual(len(pending), 1)


class ExtractionTests(unittest.TestCase):
    @staticmethod
    def piece(text: str, x0: float, width: float = 6.0) -> Piece:
        chars = []
        x = x0 + width * len(text)  # טקסט לוגי: התו הראשון הכי ימני
        for ch in text:
            x -= width
            chars.append((ch, x, x + width))
        return Piece("FrankRuehl-XP", 12.8, 4, text, x0, 0, x0 + width * len(text), 10, 9, "hebrew", chars)

    def test_brackets_are_mirrored_for_rtl_text(self) -> None:
        self.assertEqual(fix_brackets(")לקצרו("), "(לקצרו)")
        self.assertEqual(clean_gloss(")לקצרו( כלום ?,"), "(לקצרו) כלום?,")

    def test_join_orders_right_to_left_with_spaces(self) -> None:
        right = self.piece("אב", 100)
        left = self.piece("גד", 70)
        self.assertEqual(join_pieces([left, right]), "אב גד")

    def test_daf_markers(self) -> None:
        self.assertEqual(parse_daf("ל\"ב", ".")["daf"], 32)
        self.assertEqual(parse_daf("ד", ":"), {"daf": 4, "amud": "b", "label": "ד:"})
        self.assertEqual(hebrew_numeral("קכ"), 120)
        self.assertIsNone(hebrew_numeral("abc"))


class WiktionaryParsingTests(unittest.TestCase):
    def test_markup_stripping(self) -> None:
        self.assertEqual(strip_markup("{{ארמית}} [[שכר]], [[תשלום|תשלום]]"), "שכר, תשלום")

    def test_lemma_variants(self) -> None:
        self.assertEqual(split_lemma("חַבְרוּתָא (וגם: חַבְרוּתָה)"), ("חַבְרוּתָא", ["חַבְרוּתָה"]))
        self.assertEqual(split_lemma("נַרְדְּשִׁיר או נַדְרְשִׁיר"), ("נַרְדְּשִׁיר", ["נַדְרְשִׁיר"]))


class QualityChecksTests(unittest.TestCase):
    def test_variant_reading_prefix_is_stripped_from_key_only(self) -> None:
        self.assertEqual(strip_variant_reading_prefix("[הג' הב\"ח באודנאי", "= באוזן שלי]"), ("באודנאי", "באוזן שלי", True))
        self.assertEqual(strip_variant_reading_prefix("[הג' הב\"ח] בטסקא", "במס"), ("בטסקא", "במס", True))
        self.assertEqual(strip_variant_reading_prefix("אברא", "אמת"), ("אברא", "אמת", False))

    def test_gloss_issues(self) -> None:
        self.assertEqual(gloss_issues("אמת"), [])
        self.assertIn("latin_in_gloss", gloss_issues("אמת abc"))
        self.assertIn("unbalanced_brackets", gloss_issues("יפה (מובן"))
        self.assertIn("conflicts_with_otzaria_markup", gloss_issues("א *** ב"))
        self.assertIn("conflicts_with_otzaria_markup", gloss_issues("(=א) ב"))
        self.assertIn("empty_gloss", gloss_issues("  "))

    def test_key_issues(self) -> None:
        self.assertEqual(key_issues("מאי חזית"), [])
        self.assertIn("key_without_letters", key_issues(","))
        self.assertIn("key_has_unusual_characters", key_issues("אגידא [אגודא] דנהר"))


class DecisionAndCleanupTests(unittest.TestCase):
    def _write(self, rows: list[str]) -> Path:
        import tempfile

        path = Path(tempfile.mkdtemp()) / "decisions.jsonl"
        path.write_text("\n".join(rows) + "\n", encoding="utf-8")
        return path

    def test_revert_removes_only_the_last_decision(self) -> None:
        from merge import load_decisions

        path = self._write([
            '{"item_id": "a", "action": "accept_proposal", "ts": "1"}',
            '{"item_id": "a", "action": "reject", "ts": "2"}',
            '{"item_id": "a", "action": "revert", "ts": "3"}',
            '{"item_id": "b", "action": "reject", "ts": "1"}',
            '{"item_id": "b", "action": "revert", "ts": "2"}',
        ])
        decisions = load_decisions(path)
        self.assertEqual(decisions["a"]["action"], "accept_proposal")
        self.assertNotIn("b", decisions)

    def test_truncated_last_line_is_skipped_not_fatal(self) -> None:
        from merge import load_decisions

        path = self._write(['{"item_id": "a", "action": "reject", "ts": "1"}', '{"item_id": "b", "act'])
        self.assertEqual(list(load_decisions(path)), ["a"])

    def test_clean_new_text(self) -> None:
        from merge import clean_new_text

        self.assertEqual(clean_new_text(", כמו, כש-"), "כמו, כש-")
        self.assertEqual(clean_new_text("בן מחוז" + chr(92) + "כרך"), "בן מחוז/כרך")
        self.assertEqual(clean_new_text("הרבית (בלימוד תורה).ְִ"), "הרבית (בלימוד תורה).")
        self.assertEqual(clean_new_text("שָׁנָה"), "שָׁנָה")  # ניקוד צמוד לאות נשמר

    def test_manual_key_correction_splits_key_into_entries(self) -> None:
        cl = claim("חמשא/ה", "חמשה")
        queue = [{"item_id": "it-1", "normalized_key": "חמשא/ה", "system_proposal": {"classes": ["distinct_sense"], "add_senses": [{"text": "חמשה", "claim_ids": [cl["claim_id"]]}], "support": [], "modify_existing": []}}]
        entries, log, _ = build_model([], [cl], [], queue, {"it-1": {"item_id": "it-1", "action": "accept_proposal", "ts": "t"}}, {}, "מילון פשיטא", False)
        self.assertEqual(sorted(e["normalized_key"] for e in entries), ["חמשא", "חמשה"])
        self.assertIn("manual_key_correction", [row["change"] for row in log])

    def test_changed_proposal_invalidates_old_accept_proposal(self) -> None:
        from merge import proposal_sha

        cl = claim("חדש", "חדשה")
        proposal = {"classes": ["distinct_sense"], "add_senses": [{"text": "חדשה", "claim_ids": [cl["claim_id"]]}], "support": [], "modify_existing": []}
        queue = [{"item_id": "it-1", "normalized_key": "חדש", "system_proposal": proposal}]
        stale = {"it-1": {"item_id": "it-1", "action": "accept_proposal", "ts": "t", "proposal_sha": "stale"}}
        _, _, pending = build_model([], [cl], [], queue, stale, {}, "מילון פשיטא", False)
        self.assertEqual(len(pending), 1)
        fresh = {"it-1": {**stale["it-1"], "proposal_sha": proposal_sha(proposal)}}
        entries, _, pending = build_model([], [cl], [], queue, fresh, {}, "מילון פשיטא", False)
        self.assertEqual((len(entries), len(pending)), (1, 0))

    def test_parens_covered_uses_whole_words(self) -> None:
        self.assertFalse(parens_covered("שנה (לא)", "שנה, אלא"))
        self.assertTrue(parens_covered("שנה (לא)", "שנה לא"))

    def test_normalize_key_keeps_maqaf_words_apart(self) -> None:
        self.assertEqual(normalize_key("מאי־טעמא"), "מאי-טעמא")

    def test_server_rejects_decisions_with_foreign_ids(self) -> None:
        sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "review"))
        from server import validate_decision

        item = {"groups": [[{"claim_id": "c1"}]], "existing_senses": [{"sense_id": "s1"}]}
        validate_decision(item, {"action": "custom", "add_senses": [{"text": "א", "claim_ids": ["c1"]}]})
        for bad in (
            {"action": "custom", "add_senses": [{"text": "א", "claim_ids": []}]},
            {"action": "custom", "add_senses": [{"text": "א", "claim_ids": ["other"]}]},
            {"action": "custom", "add_senses": "text"},
            {"action": "custom", "modify_existing": [{"sense_id": "nope", "old_text": "א", "new_text": "ב"}]},
            {"action": "reject", "confirm_modify_existing": "yes"},
        ):
            with self.assertRaises(ValueError):
                validate_decision(item, bad)


if __name__ == "__main__":
    unittest.main()
