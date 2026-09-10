/// איסוף הפעולות הווקטוריות מהפריסה של הייצוא: כל מילה נאספת פעם אחת בלי
/// פסקת המשיחה, טור מוסתר נשמט, גבולות השורות נאספים, ונו"ן מנוזרת משתקפת.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/engine/tokenizer.dart';
import 'package:otzaria/tools/tikkun_korim/export/tikkun_pdf_exporter.dart';
import 'package:otzaria/tools/tikkun_korim/export/tikkun_vector_ops.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';

import '../support/tikkun_fakes.dart';

TikkunPdfExporter _exporter({
  TikkunExportMode mode = TikkunExportMode.flow,
  TikkunExportColumns columns = TikkunExportColumns.both,
  TikkunSettings settings = const TikkunSettings(),
  String? headerTitle,
}) => TikkunPdfExporter(
  settings: settings,
  options: TikkunExportOptions(
    scope: TikkunExportScope.all,
    mode: mode,
    columns: columns,
  ),
  headerTitle: headerTitle,
);

Iterable<TikkunTextOp> _withText(TikkunVectorPage page, String text) =>
    page.texts.where((op) => op.text == text);

void main() {
  testWidgets('כל מילה נאספת פעם אחת לכל טור, והכותרת בגופן מפורש', (
    tester,
  ) async {
    final exporter = _exporter(headerTitle: 'כותרת');
    late List<TikkunVectorPage> pages;
    await tester.runAsync(() async {
      pages = await exporter.layoutPages([
        [
          textLine(['אחת'], chapter: 1, verse: 1),
          textLine(['שתים'], chapter: 1, verse: 2),
        ],
      ]);
    });

    expect(pages, hasLength(1));
    final page = pages.single;
    // סת"ם ומנוקד — בלי פסקת המשיחה הכפולה של התצוגה.
    expect(_withText(page, 'אחת'), hasLength(2));
    expect(_withText(page, 'שתים'), hasLength(2));
    final header = _withText(page, 'כותרת').single;
    expect(header.style.fontFamily, isNotNull);
    expect(header.bold, isTrue);

    // סדר הכתיבה הוא סדר הקריאה של קורא ה-PDF: הכותרת, ואז כל טור בשלמותו
    // — אחרת גרירה על טור אחד מסמנת גם את חברו.
    expect(page.texts.first.text, 'כותרת');
    final first = page.texts.indexed
        .where((entry) => entry.$2.text == 'אחת')
        .map((entry) => entry.$1);
    final second = page.texts.indexed
        .where((entry) => entry.$2.text == 'שתים')
        .map((entry) => entry.$1);
    expect(first.first, lessThan(second.first));
    expect(second.first, lessThan(first.last));
    expect(first.last, lessThan(second.last));

    for (final op in page.texts) {
      expect(op.left, greaterThanOrEqualTo(0));
      expect(op.left, lessThan(page.width));
      expect(op.baseline, greaterThan(0));
      expect(op.baseline, lessThanOrEqualTo(page.height));
    }
    expect(page.rects, isNotEmpty, reason: 'קווי ההפרדה של השורות');
  });

  testWidgets('טור מוסתר נשמט מהאיסוף', (tester) async {
    final exporter = _exporter(columns: TikkunExportColumns.stamOnly);
    late List<TikkunVectorPage> pages;
    await tester.runAsync(() async {
      pages = await exporter.layoutPages([
        [
          textLine(['אחת'], chapter: 1, verse: 1),
        ],
      ]);
    });

    expect(_withText(pages.single, 'אחת'), hasLength(1));
  });

  testWidgets('נו"ן מנוזרת נאספת כקטע משתקף', (tester) async {
    final exporter = _exporter(
      settings: const TikkunSettings(hideRowBorders: true),
    );
    late List<TikkunVectorPage> pages;
    await tester.runAsync(() async {
      pages = await exporter.layoutPages([
        [
          textLine([kNunHafukha], chapter: 1, verse: 1),
        ],
      ]);
    });

    final page = pages.single;
    final mirrored = page.texts.where((op) => op.mirrorCenter != null);
    expect(mirrored, isNotEmpty);
    expect(mirrored.every((op) => op.text == kNunHafukhaGlyph), isTrue);
    expect(page.rects, isEmpty, reason: 'בלי גבולות אין מלבנים');
  });

  testWidgets('עמודים מקוריים — עמוד לכל טור, והאחרון קצר יותר', (
    tester,
  ) async {
    final exporter = _exporter(mode: TikkunExportMode.originalPages);
    late List<TikkunVectorPage> pages;
    await tester.runAsync(() async {
      pages = await exporter.layoutPages([
        [
          for (var i = 1; i <= 60; i++) textLine(['שורה'], verse: i),
        ],
        [
          textLine(['סוף'], verse: 1),
        ],
      ]);
    });

    expect(pages, hasLength(2));
    expect(pages[0].width, closeTo(pages[1].width, 0.01));
    expect(pages[1].height, lessThan(pages[0].height));
  });
}
