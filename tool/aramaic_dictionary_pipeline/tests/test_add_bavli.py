"""בדיקות ל-add_bavli.py:  py -m unittest discover -s tests"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from add_bavli import add_bavli, app_key, drop_placeholders, is_placeholder, read_bavli  # noqa: E402
from common import hebrew_sort_key  # noqa: E402

TARGET = "מילון פשיטא"


def sample() -> dict[str, list]:
    return {
        TARGET: [{"אב": "אבא"}, {"גמל": "בעל חיים"}],
        "מילון שיח ישראל": [{"ב''ר": "*"}, {"דגל": "(סימן)"}, {"הלכתא": "דין"}, {"זזז": ""}],
    }


class PlaceholderTests(unittest.TestCase):
    def test_same_rule_as_the_app(self) -> None:
        self.assertTrue(is_placeholder("אל''ף", "*"))
        self.assertTrue(is_placeholder("ביט''ל", "(סימן)"))
        self.assertTrue(is_placeholder("זזז", ""))
        self.assertTrue(is_placeholder("abc", "פירוש"))  # מפתח בלי אות עברית
        self.assertTrue(is_placeholder("אב", "* *** (סימן)"))
        self.assertFalse(is_placeholder("אב", "אבא"))
        self.assertFalse(is_placeholder("אב", "* *** אבא"))  # פירוש אחד אמיתי מספיק

    def test_drop_keeps_order_and_real_entries(self) -> None:
        data = sample()
        removed = drop_placeholders(data)
        self.assertEqual(removed, {"מילון שיח ישראל": 3})
        self.assertEqual(data["מילון שיח ישראל"], [{"הלכתא": "דין"}])
        self.assertEqual(data[TARGET], sample()[TARGET])
        self.assertEqual(drop_placeholders(data), {})


class AddBavliTests(unittest.TestCase):
    def test_adds_sorted_and_is_idempotent(self) -> None:
        data = sample()
        rows = [("בקר", "בוקר"), ("אבא", "אב")]
        self.assertEqual(add_bavli(data, TARGET, rows), (2, 0))
        keys = [next(iter(e)) for e in data[TARGET]]
        self.assertEqual(keys, sorted(keys, key=hebrew_sort_key))
        self.assertEqual(add_bavli(data, TARGET, rows), (0, 2))
        self.assertEqual(len(data[TARGET]), 4)

    def test_other_dictionaries_untouched(self) -> None:
        data = sample()
        add_bavli(data, TARGET, [("בקר", "בוקר")])
        self.assertEqual(data["מילון שיח ישראל"], sample()["מילון שיח ישראל"])

    def test_placeholder_key_is_not_a_collision(self) -> None:
        data = sample()
        self.assertEqual(add_bavli(data, TARGET, [("בר", "בן")]), (1, 0))  # ב''ר הוא ערך מילוי

    def test_real_collision_stops(self) -> None:
        data = sample()
        with self.assertRaises(SystemExit):
            add_bavli(data, TARGET, [("הלכתא", "הלכה")])  # קיים במילון אחר
        with self.assertRaises(SystemExit):
            add_bavli(data, TARGET, [("אב", "אבא אחר")])  # קיים באותו מילון בפירוש אחר

    def test_app_key_matches_app_normalisation(self) -> None:
        self.assertEqual(app_key("אַבָּרָא"), "אברא")
        self.assertEqual(app_key("א\"ל  ב'"), "אל ב")


class SourceFileTests(unittest.TestCase):
    def test_bavli_source_file_is_valid(self) -> None:
        rows = read_bavli()
        self.assertGreater(len(rows), 500)
        for key, meaning in rows:
            self.assertFalse(is_placeholder(key, meaning), key)


if __name__ == "__main__":
    unittest.main()
