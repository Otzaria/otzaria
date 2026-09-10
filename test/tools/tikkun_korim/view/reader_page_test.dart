import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/settings/tikkun_settings.dart';
import 'package:otzaria/tools/tikkun_korim/view/tikkun_render_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/markers_column.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_row.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_page.dart';

import '../support/tikkun_fakes.dart';

void main() {
  group('computeTikkunLineMarkers', () {
    test('מספר הפרק מוצג רק בשורה הראשונה שלו', () {
      final markers = computeTikkunLineMarkers([
        textLine(['א'], chapter: 1, verse: 1),
        textLine(['ב'], chapter: 1, verse: 2),
        textLine(['ג'], chapter: 2, verse: 1),
      ]);

      expect(markers[0].chapterNum, 1);
      expect(markers[1].chapterNum, isNull);
      expect(markers[1].verseNum, 2);
      expect(markers[2].chapterNum, 2);
    });

    test('שורה בלי פרק שומרת על הפרק הקודם', () {
      final markers = computeTikkunLineMarkers([
        textLine(['א'], chapter: 3, verse: 1),
        textLine(['ב']),
        textLine(['ג'], chapter: 3, verse: 2),
      ]);

      expect(markers[1].chapterNum, isNull);
      expect(markers[2].chapterNum, isNull);
    });
  });

  testWidgets('העמוד מציג כותרת ושורות', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he', 'IL'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ReaderPage(
              lines: [
                textLine(['אחת'], chapter: 1, verse: 1),
                textLine(['שתים'], chapter: 1, verse: 2),
              ],
              settings: const TikkunSettings(),
              hideStam: false,
              hideNikud: false,
              headerTitle: 'הפטרת בראשית',
              headerSubtitle: 'הפטרה: שופטים',
            ),
          ),
        ),
      ),
    );

    expect(find.text('הפטרת בראשית'), findsOneWidget);
    expect(find.text('הפטרה: שופטים'), findsOneWidget);
    expect(find.byType(MarkersColumn), findsNWidgets(2));
  });

  testWidgets('טור יחיד ממורכז — העמוד צר יותר והטור ממלא אותו', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const settings = TikkunSettings(hideStam: true, centerSingleColumn: true);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('he', 'IL'),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ReaderPage(
              lines: [
                textLine(['אחת'], chapter: 1, verse: 1),
              ],
              settings: settings,
              hideStam: true,
              hideNikud: false,
            ),
          ),
        ),
      ),
    );

    final row = tester.getSize(find.byType(ReaderRow));
    expect(row.width, lessThan(kTikkunSingleColumnReferenceWidth));
    expect(row.width, greaterThan(kTikkunSingleColumnReferenceWidth - 40));
    // הטור עצמו רחב מחצי השורה — לא נשאר במקומו כטור אחד מתוך שניים.
    final column = tester.getSize(find.byType(ClipRect).first);
    expect(column.width, greaterThan(row.width * 0.7));
  });
}
