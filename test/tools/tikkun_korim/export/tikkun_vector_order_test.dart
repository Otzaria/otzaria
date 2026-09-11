/// סדר הפעולות שנאספות מהעמוד: טור אחר טור, כדי שסימון טקסט ב-PDF המיוצא
/// יסמן כל טור בפני עצמו. בעץ הרינדור כל שורה מחזיקה את שני הטורים, ולכן
/// הסדר הנאסף מזגזג ביניהם.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/export/tikkun_vector_ops.dart';

/// גאומטריית העמוד הסינתטי: שני טורים של 130, רווח 10 ומסמנים של 20.
const double _columnWidth = 130;
const double _gap = 10;
const double _markers = 20;
const double _pageWidth = 2 * _columnWidth + 2 * _gap + _markers;

const TikkunPageColumns _columns = TikkunPageColumns(
  cuts: [_columnWidth + _gap / 2, _pageWidth - _columnWidth - _gap / 2],
  leadingFullWidthChildren: 1,
);

final GlobalKey _pageKey = GlobalKey();

/// שורה אחת בעמוד — הילד הראשון יושב מימין, כמו בשורת התיקון.
Widget _row(List<String> stam, String marker, String nikud) => Row(
  textDirection: TextDirection.rtl,
  children: [
    SizedBox(
      width: _columnWidth,
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          for (final word in stam) ...[
            Text(word),
            const SizedBox(width: 6),
          ],
        ],
      ),
    ),
    const SizedBox(width: _gap),
    SizedBox(width: _markers, child: Text(marker)),
    const SizedBox(width: _gap),
    SizedBox(width: _columnWidth, child: Text(nikud)),
  ],
);

Future<TikkunVectorPage> _collect(
  WidgetTester tester, {
  required TikkunPageColumns columns,
  List<Widget>? rows,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.rtl,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: _pageWidth,
          child: Column(
            key: _pageKey,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('H'),
              ...rows ??
                  [
                    _row(const ['S1'], 'x', 'N1'),
                    _row(const ['S2'], 'y', 'N2'),
                  ],
            ],
          ),
        ),
      ),
    ),
  );
  return collectTikkunVectorPage(
    tester.renderObject<RenderBox>(find.byKey(_pageKey)),
    columns: columns,
  );
}

void main() {
  testWidgets('בלי גאומטריית טורים הסדר מזגזג בין הטורים', (tester) async {
    final page = await _collect(tester, columns: TikkunPageColumns.none);

    expect(page.texts.map((op) => op.text).toList(), [
      'H',
      'S1',
      'x',
      'N1',
      'S2',
      'y',
      'N2',
    ]);
  });

  testWidgets('עם גאומטריית טורים כל טור נכתב בשלמותו, מימין לשמאל', (
    tester,
  ) async {
    final page = await _collect(tester, columns: _columns);

    // הכותרת ראשונה — היא אינה שורה ולכן אינה משויכת לטור, גם כשהיא
    // ממורכזת ונופלת בחריץ המסמנים.
    expect(page.texts.map((op) => op.text).toList(), [
      'H',
      'S1',
      'S2',
      'x',
      'y',
      'N1',
      'N2',
    ]);
  });

  testWidgets('בתוך שורה הסדר חזותי — משמאל לימין', (tester) async {
    // המילה הראשונה בשורה עברית יושבת מימין, ולכן היא נכתבת אחרונה: קורא
    // ה-PDF מחלץ רצף חזותי ומריץ עליו ניתוח דו-כיווני.
    final page = await _collect(
      tester,
      columns: _columns,
      rows: [
        _row(const ['P1', 'P2'], 'x', 'N1'),
      ],
    );

    expect(page.texts.map((op) => op.text).toList(), [
      'H',
      'P2',
      'P1',
      'x',
      'N1',
    ]);
  });

  testWidgets('רוחב התיבה נאסף, ומיקום הטור נגזר ממרכזה', (tester) async {
    final page = await _collect(tester, columns: _columns);
    final stam = page.texts.firstWhere((op) => op.text == 'S1');
    final nikud = page.texts.firstWhere((op) => op.text == 'N1');

    expect(stam.width, greaterThan(0));
    expect(_columns.slotOf(stam.left + stam.width / 2), 0);
    expect(_columns.slotOf(nikud.left + nikud.width / 2), 2);
    expect(stam.right, stam.left + stam.width);
  });
}
