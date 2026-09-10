/// טקסטי מקרא אמיתיים לבדיקות הכלי, כפי שהם מגיעים מ-`seforim.db`.
/// מופקים מחדש ע"י `tool/tikkun_korim/extract_fixtures.mjs`.
library;

import 'dart:convert';
import 'dart:io';

const String fixturesDir = 'test/tools/tikkun_korim/fixtures';

/// שם הספר בעברית לפי מזהה ה-fixture — כפי שהמנוע מצפה לקבלו.
const Map<String, String> fixtureBookNames = {
  'bereshit': 'בראשית',
  'shemot': 'שמות',
  'vayikra': 'ויקרא',
  'bamidbar': 'במדבר',
  'devarim': 'דברים',
  'shoftim': 'שופטים',
  'shmuel_b': 'שמואל ב',
  'esther': 'אסתר',
  'yeshayahu': 'ישעיהו',
};

String readGzText(String path) =>
    utf8.decode(gzip.decode(File(path).readAsBytesSync()));

String readFixture(String id) => readGzText('$fixturesDir/$id.txt.gz');

/// מקודד כל תו שאינו ASCII ל-`\uXXXX`, כדי שדוח כישלון לא יכיל טקסט מקרא.
String escapeNonAscii(Object? value) {
  final text = value is String ? value : jsonEncode(value);
  final buf = StringBuffer();
  for (final unit in text.codeUnits) {
    if (unit >= 0x20 && unit < 0x7f) {
      buf.writeCharCode(unit);
    } else {
      buf.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
    }
  }
  return buf.toString();
}
