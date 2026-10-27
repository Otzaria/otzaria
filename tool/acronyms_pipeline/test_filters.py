"""Regression examples for filters.py.  Run: py tool/acronyms_pipeline/test_filters.py"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import filters as f  # noqa: E402


def reasons(key, exp):
    return f.check_expansion(key, exp)[0]


class RejectedExamples(unittest.TestCase):
    """Fixed examples of noise that must never reach the dictionary again."""

    def test_empty_values(self):
        for exp in ["", "   ", "...", "-", "־", "‏‎", "ְִֵ", "\n"]:
            self.assertIn("empty", reasons('א"ב', exp), repr(exp))

    def test_non_strings(self):
        self.assertEqual(reasons('א"ב', None), ["not_a_string"])

    def test_same_as_key(self):
        self.assertIn("same_as_key", reasons('רש"י', 'רש"י'))
        self.assertIn("same_as_key", reasons('רש"י', "רש״י"))

    def test_technical_and_errors(self):
        for exp in ["null", "undefined", "N/A", "Error 500", "Traceback"]:
            self.assertTrue(reasons('א"ב', exp), exp)

    def test_truncated(self):
        self.assertIn("truncated", reasons('א"ב', "אמר רבי ("))
        self.assertIn("truncated", reasons('א"ב', "אמר רבי (יוחנן"))

    def test_html_and_structure(self):
        self.assertIn("html", reasons('א"ב', "<b>אמר</b> בית"))
        self.assertIn("html", reasons('א"ב', "אמר &nbsp; בית"))
        self.assertIn("structure_chars", reasons('א"ב', '{"a": "אמר בית"}'))
        self.assertIn("control_chars", reasons('א"ב', "אמר\x07 בית"))

    def test_letter_names(self):
        # the examples from the PR #3202 review
        self.assertIn("letter_names", reasons('צמיער', "צדיק מם יוד עין ריש"))
        self.assertIn("letter_names", reasons('אב', "אלף בית"))
        self.assertIn("letter_names", reasons('קמ', "קוף מם"))
        self.assertIn("letter_names", reasons('אבג', "אלף בית גימל"))
        self.assertIn("letter_names", reasons('שמ"ר', "שין מם ריש"))
        self.assertIn("letter_names", reasons('צ"מ', "צדי״ק מ״ם"))

    def test_letter_names_only_on_the_whole_meaning(self):
        # one of the words is also a letter name; the meaning is genuine
        for key, exp in [('ב"ד', "בית דין"), ('ב"ה', "בית הלל"), ('ר"ת', "ראש תיבות"), ('ת"ת', "תלמוד תורה"),
                         ('ב"ש', "בית שמאי"), ('ע"ז', "עבודה זרה"), ('ש"ס', "ששה סדרים")]:
            self.assertNotIn("letter_names", reasons(key, exp), exp)

    def test_gematria_numbers(self):
        self.assertIn("gematria_number", reasons('קכ"ג', "מאה עשרים ושלוש"))
        self.assertIn("gematria_number", reasons('קכ"ג', "פרק מאה עשרים ושלושה"))
        self.assertIn("gematria_number", reasons('פ"א', "שמונים ואחד"))
        self.assertIn("gematria_number", reasons('תע"ו', "ארבע מאות שבעים ושש"))
        self.assertIn("gematria_number", reasons('ט"ו', "חמש עשרה"))
        self.assertIn("gematria_number", reasons('ק"ל', "מאה ושלושים"))
        self.assertIn("gematria_number", reasons('י"ג', "שלוש עשרה"))

    def test_real_chapter_and_page_abbreviations_survive(self):
        for key, exp in [('פ"א', "פרק א"), ('פ"א', "פרק ראשון"), ('פ"א', "פרק אחד"), ('ס"א', "סעיף א"),
                         ('ע"א', "עמוד א"), ('ע"ב', "עמוד ב"), ('ד"ה', "דיבור המתחיל"),
                         ('ר"ח', "ראש חודש"), ('ט"ו', "טו בשבט")]:
            self.assertNotIn("gematria_number", reasons(key, exp), (key, exp))

    def test_not_a_numeral_key_is_not_gematria(self):
        # 'רש"י' cannot be a numeral and "רבי" is no number word
        self.assertEqual(reasons('רש"י', "רבי שלמה יצחקי"), [])

    def test_unexpected_characters(self):
        self.assertIn("unexpected_characters", reasons('א"ב', "אמר abc"))
        self.assertIn("unexpected_characters", reasons('א"ב', "אמר 12"))

    def test_navigation_text_is_matched_on_whole_phrases(self):
        self.assertIn("navigation_text", reasons('א"ב', "חזרה לתפריט"))
        for exp in ["לעבור לעולם הבא", "מותר לעבור למקום אחר", "התחברות חברים", "הרשמה לאחר מכן"]:
            self.assertNotIn("navigation_text", reasons('א"ב', exp), exp)

    def test_gematria_with_double_yod_spellings(self):
        self.assertIn("gematria_number", reasons('כ"ב', "עשרים ושתיים"))
        self.assertIn("gematria_number", reasons('כ"ב', "עשרים ושניים"))

    def test_any_run_of_two_letter_names(self):
        self.assertIn("letter_names", reasons('פ"ד', "בית דלת"))

    def test_acronym_explained_by_another_acronym(self):
        self.assertIn("expansion_is_acronym", reasons('איב"א', 'אב"א'))
        self.assertNotIn("expansion_is_acronym", reasons('הב"ה', 'הקדוש ברוך הוא'))

    def test_too_long(self):
        self.assertIn("too_long", reasons('א"ב', "אמר " * 40))


class AcceptedExamples(unittest.TestCase):
    def test_normal_meanings_pass_clean(self):
        for key, exp in [('רש"י', "רבי שלמה יצחקי"), ('רמב"ם', "רבי משה בן מימון"), ('הגר"א', "הגאון רבי אליהו"),
                         ('חז"ל', "חכמינו זכרונם לברכה"), ('שו"ע', "שולחן ערוך"), ('אב"ד', "אב בית דין"),
                         ('מהר"ל', "מורנו הרב רבי ליווא"), ('תנ"ך', "תורה נביאים כתובים")]:
            r, flags, _ = f.check_expansion(key, exp)
            self.assertEqual(r, [], (key, exp))
            self.assertNotIn("letters_do_not_align", flags, (key, exp))

    def test_misaligned_meaning_is_flagged_not_dropped(self):
        r, flags, _ = f.check_expansion('אב"ד', "דין ברור")
        self.assertEqual(r, [])
        self.assertIn("letters_do_not_align", flags)


class Normalisation(unittest.TestCase):
    def test_normalize_key(self):
        self.assertEqual(f.normalize_key("רש״י"), 'רש"י')
        self.assertEqual(f.normalize_key("רַשִׁ״י"), 'רש"י')
        self.assertEqual(f.normalize_key("רשי"), 'רש"י')

    def test_signatures_ignore_quotes_and_nikud(self):
        self.assertEqual(f.key_signature("רש״י"), f.key_signature('רש"י'))
        self.assertEqual(f.meaning_signature("אל״ף־בית"), f.meaning_signature('אלף בית'))

    def test_normalize_expansion_keeps_letters(self):
        self.assertEqual(f.normalize_expansion("  רבי‏ שלמה  יצחקי. "), "רבי שלמה יצחקי")


class Numbers(unittest.TestCase):
    def test_gematria_value(self):
        self.assertEqual(f.gematria_value('קכ"ג'), 123)
        self.assertEqual(f.gematria_value('ט"ו'), 15)
        self.assertEqual(f.gematria_value('תתקע"ב'), 972)
        self.assertIsNone(f.gematria_value('רש"י'))

    def test_number_phrase_value(self):
        self.assertEqual(f.number_phrase_value("מאה עשרים ושלוש".split()), 123)
        self.assertEqual(f.number_phrase_value("שמונים ואחד".split()), 81)
        self.assertEqual(f.number_phrase_value("שלוש מאות".split()), 300)
        self.assertEqual(f.number_phrase_value("חמש עשרה".split()), 15)
        self.assertIsNone(f.number_phrase_value(["רבי"]))


if __name__ == "__main__":
    unittest.main()
