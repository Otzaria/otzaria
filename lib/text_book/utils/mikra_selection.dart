/// בחירה והעתקה בספר מקרא: חלון הבחירה חייב לראות את השורות כפי שהן מוצגות
/// (בלי מספר הפסוק, כותרת פרק ריקה), אחרת בחירה שחוצה פסוק או פרק לא תימצא.
/// הצרכנים (הערות, תוספים, דיווח טעות) מקבלים עמודות בשורה הרגילה, ולכן
/// עמודה בטקסט המוצג מוסטת בחזרה באורך מספר הפסוק שהוסר.
///
/// ההעתקה כמו התצוגה, בלי מספר הפסוק, ובלי סימוני הפרשיות {פ} ו-{ס}.
library;

import 'dart:math' as math;

import 'package:otzaria/book_common/selection/selected_text_restore.dart';
import 'package:otzaria/text_book/utils/mikra_structure.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';

/// השורה [line] כפי שהיא מוצגת במקרא, להתאמת הבחירה. [html] — השורה אחרי
/// הזרקת הסימונים של המסך.
String mikraSelectionHtml(MikraStructure mikra, int line, String html) =>
    mikra.isHiddenLine(line) ? '' : mikraDisplayHtml(html);

/// כמה תווים בתחילת השורה הרגילה המרונדרת (מספר הפסוק) אינם בשורה המוצגת
/// במקרא. 0 כשאין הסטה או כשאין התאמה ודאית.
int mikraColumnShift({
  required String rawLine,
  required int line,
  required MikraStructure mikra,
  required RenderSettings settings,
}) {
  if (mikra.isHiddenLine(line)) return 0;
  final standard = renderSelectionLine(rawText: rawLine, settings: settings);
  final shown = renderSelectionLine(
    rawText: mikraDisplayHtml(rawLine),
    settings: settings,
  );
  if (shown.isEmpty) return 0;
  // ראש הטקסט המוצג מופיע בשורה הרגילה מיד אחרי מספר הפסוק; סוף השורה
  // (סימוני הפרשיות) עשוי להיות שונה ברווחים, ולכן אין משווים אותו.
  final head = shown.substring(0, math.min(shown.length, 16));
  final at = standard.indexOf(head);
  return at > 0 ? at : 0;
}

final RegExp _copyMarkHtml = RegExp(
  r'(?:&nbsp;|\s|\u00A0)*<span class="mam-spi-(?:pe|samekh)">.*?</span>'
  r'(?:\s*<br\s*/?>)?',
  dotAll: true,
);
final RegExp _copyMarkText = RegExp(
  '[ \t\u00A0\u2003]*\\{[\u05E4\u05E1]\\}[ \t\u00A0\u2003]*',
);
final RegExp _spacesBeforeBreak = RegExp(r' +\n');
final RegExp _spacesAfterBreak = RegExp(r'\n +');

/// שורת מקור להעתקה במקרא ("העתק את כל הפסקה"): בלי מספר הפסוק ובלי סימוני
/// הפרשיות. סתומה באמצע השורה נשארת רווח אחד; פתוחה באמצע פסוק — שבירת שורה,
/// כמו בתצוגה.
String mikraCopyHtml(String html) => stripMikraVersePrefix(html)
    .replaceAllMapped(
      _copyMarkHtml,
      (m) =>
          m[0]!.contains('mam-spi-pe') && !mikraBlankAfter(m)
          ? '<br>'
          : ' ',
    )
    .trimRight();

/// טקסט נבחר להעתקה במקרא: בלי {פ} ו-{ס} ובלי ריווח הסתומה.
String mikraCopyText(String text) => text
    .replaceAll(_copyMarkText, ' ')
    .replaceAll(_spacesBeforeBreak, '\n')
    .replaceAll(_spacesAfterBreak, '\n')
    .trim();

/// שורות המקור להעתקת בחירה במקרא: השורה [index] כמו בהעתקה, כדי שה-HTML
/// המעוצב שנגזר ממנה יתאים לטקסט שהועתק. שאר השורות כמות שהן.
List<String> mikraCopyContent(List<String> content, int? index) {
  if (index == null || index < 0 || index >= content.length) return content;
  return List<String>.of(content)..[index] = mikraCopyHtml(content[index]);
}
