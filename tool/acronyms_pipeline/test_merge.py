"""Tests for merge.py.  Run: py tool/acronyms_pipeline/test_merge.py"""
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import merge  # noqa: E402

SOURCES = merge.load_sources()
BASE = {'א"א': ["אברהם אבינו", "אשת איש"], 'ב"ד': ["בית דין"], 'ג"ש': ["גזירה שווה"]}


def row(key, exp, status="approved", source="jastrow-sefaria", reviewer="מיכאל", date="2026-10-27", ref="Jastrow, שורה 9"):
    return {"key": key, "expansion": exp, "status": status, "source": source, "reference": ref, "notes": "",
            "reviewer": reviewer, "reviewed_at": date}


class Apply(unittest.TestCase):
    def test_new_meaning_is_appended_and_order_is_kept(self):
        merged, stats = merge.apply(BASE, [row('א"א', "אי אפשר")])
        self.assertEqual(merged['א"א'], ["אברהם אבינו", "אשת איש", "אי אפשר"])
        self.assertEqual(list(merged), list(BASE))
        self.assertEqual(stats["new_meanings"], 1)
        self.assertEqual(stats["new_keys"], 0)

    def test_new_key_goes_to_its_alphabetical_place(self):
        merged, stats = merge.apply(BASE, [row('ב"ה', "בית הלל")])
        self.assertEqual(list(merged), ['א"א', 'ב"ד', 'ב"ה', 'ג"ש'])
        self.assertEqual(stats["new_keys"], 1)

    def test_only_approved_rows_enter(self):
        merged, _ = merge.apply(BASE, [row('ב"ה', "בית הלל", status="pending"), row('ד"ה', "דיבור המתחיל", status="rejected"),
                                       row('ה"ה', "הרי הוא", status="needs_review")])
        self.assertEqual(merged, BASE)

    def test_existing_meaning_is_not_duplicated(self):
        merged, stats = merge.apply(BASE, [row('ב"ד', "בית  דין"), row('בד', "בית דין")])
        self.assertEqual(merged['ב"ד'], ["בית דין"])
        self.assertEqual(stats["already_present"], 2)

    def test_baseline_is_not_modified(self):
        before = json.dumps(BASE, ensure_ascii=False)
        merge.apply(BASE, [row('א"א', "אי אפשר")])
        self.assertEqual(json.dumps(BASE, ensure_ascii=False), before)

    def test_output_is_deterministic(self):
        rows = [row('ב"ה', "בית הלל"), row('א"א', "אי אפשר"), row('ג"ח', "גמילות חסדים")]
        a = merge.dump(merge.apply(BASE, rows)[0])
        b = merge.dump(merge.apply(BASE, list(reversed(rows)))[0])
        self.assertEqual(a, b)

    def test_layout_matches_the_shipped_file(self):
        root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "Acronyms.json")
        with open(root, "rb") as f:
            raw = f.read()
        self.assertEqual(merge.dump(json.loads(raw.decode("utf-8"))), raw)


class Validate(unittest.TestCase):
    def problems(self, *rows):
        return merge.validate(list(rows), SOURCES)

    def test_good_row(self):
        self.assertEqual(self.problems(row('ב"ה', "בית הלל")), [])

    def test_agent_cannot_approve(self):
        for who in ["agent", "claude", "auto-review", "GPT", "בדיקה אוטומטית", "", "claude_code", "auto_approve", "ChatGPT",
                    "Gemini", "Opus 5", "קלוד", "robot", "review-bot"]:
            self.assertTrue(self.problems(row('ב"ה', "בית הלל", reviewer=who)), who)

    def test_blocked_and_lead_sources_cannot_approve(self):
        self.assertTrue(self.problems(row('ב"ה', "בית הלל", source="jewishbooks")))
        self.assertTrue(self.problems(row('ב"ה', "בית הלל", source="dicta-lead")))
        self.assertTrue(self.problems(row('ב"ה', "בית הלל", source="unknown")))

    def test_real_names_are_fine(self):
        for who in ["מיכאל", "Michael Levi", "י. כהן", "palmoni5", "Maya"]:
            self.assertEqual(self.problems(row('ב"ה', "בית הלל", reviewer=who)), [], who)

    def test_reference_and_date_are_required(self):
        self.assertTrue(self.problems(row('ב"ה', "בית הלל", ref="")))
        self.assertTrue(self.problems(row('ב"ה', "בית הלל", date="")))
        for bad in ["2026-99-99", "2026-99-99xyz", "27/10/2026", "2026-10-27T10:00"]:
            self.assertTrue(self.problems(row('ב"ה', "בית הלל", date=bad)), bad)

    def test_key_must_be_in_dictionary_spelling(self):
        for key in ["abc", 'א"ב"ג', 'a"b', "אב", "", 'א ב"ג']:
            self.assertTrue(self.problems(row(key, "בית הלל")), key)

    def test_expansion_must_be_normalised(self):
        for exp in ["פרק\u200f א", "פרק  א", " פרק א.", "פרק א\u00ad", "פרק \u201cא\u201d", "פרַק א", "פרק־א"]:
            self.assertTrue(self.problems(row('פ"א', exp)), repr(exp))

    def test_noise_cannot_be_approved(self):
        self.assertTrue(self.problems(row('צמיער', "צדיק מם יוד עין ריש")))
        self.assertTrue(self.problems(row('קכ"ג', "מאה עשרים ושלוש")))

    def test_rejected_rows_need_no_reviewer(self):
        self.assertEqual(self.problems(row('ב"ה', "בית הלל", status="rejected", reviewer="", ref="", date="")), [])

    def test_duplicate_decisions(self):
        self.assertTrue(self.problems(row('ב"ה', "בית הלל"), row('ב"ה', "בית הלל", status="rejected")))


class AgentApproved(unittest.TestCase):
    def agent(self, **kw):
        return row('ב"ה', "בית הלל", status="agent_approved", source="agent-verified-reference", reviewer="agent:claude-sonnet-5-5", **kw)

    def test_valid_agent_row_enters_and_is_counted_separately(self):
        r = self.agent()
        self.assertEqual(merge.validate([r], SOURCES), [])
        merged, stats = merge.apply(BASE, [r, row('ג"ח', "גמילות חסדים")])
        self.assertIn('ב"ה', merged)
        self.assertEqual((stats["agent_approved_rows"], stats["human_approved_rows"]), (1, 1))

    def test_human_only_leaves_agent_rows_out(self):
        merged, _ = merge.apply(BASE, [self.agent()], human_only=True)
        self.assertEqual(merged, BASE)

    def test_agent_row_must_say_it_is_an_agent(self):
        for who in ["מיכאל", "", "claude", "agent:", "agent:x y"]:
            r = self.agent()
            r["reviewer"] = who
            self.assertTrue(merge.validate([r], SOURCES), who)

    def test_agent_row_still_needs_reference_date_and_clean_text(self):
        self.assertTrue(merge.validate([self.agent(ref="")], SOURCES))
        self.assertTrue(merge.validate([self.agent(date="soon")], SOURCES))
        r = self.agent()
        r["key"], r["expansion"] = 'קכ"ג', "מאה עשרים ושלוש"
        self.assertTrue(merge.validate([r], SOURCES))

    def test_a_human_row_cannot_use_an_agent_reviewer_id(self):
        self.assertTrue(merge.validate([row('ב"ה', "בית הלל", reviewer="agent:claude-sonnet-5-5")], SOURCES))


class Imports(unittest.TestCase):
    def test_short_csv_row_does_not_crash(self):
        import tempfile

        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "short.csv")
            with open(p, "w", encoding="utf-8", newline="") as f:
                f.write("key,expansion,status,source,reference,notes,reviewer,reviewed_at\n")
                f.write('ב"ה,בית הלל,approved\n')
            rows = merge.read_ledger(p)
        self.assertEqual(rows[0]["reviewer"], "")
        self.assertTrue(merge.validate(rows, SOURCES))

    def test_later_decision_replaces_earlier(self):
        import csv
        import tempfile

        ledger = [row('ב"ה', "בית הלל", status="needs_review")]
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "export.csv")
            with open(p, "w", encoding="utf-8-sig", newline="") as f:  # the review page writes a BOM
                w = csv.DictWriter(f, merge.COLUMNS)
                w.writeheader()
                w.writerow(row('ב"ה', "בית הלל"))
            out = merge.import_exports(ledger, [p])
        self.assertEqual([r["status"] for r in out], ["approved"])


if __name__ == "__main__":
    unittest.main()
