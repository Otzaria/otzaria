/// סגירת שורה מיושרת: רווחים עד התקרה, ואז מתיחת דהלת"ם — מעט ומסוף השורה.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/engine/stam_width_model.dart';
import 'package:otzaria/tools/tikkun_korim/export/tikkun_vector_ops.dart';
import 'package:otzaria/tools/tikkun_korim/models/tikkun_models.dart';
import 'package:otzaria/tools/tikkun_korim/view/stam_roof_metrics.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/reader_row.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/stam_word.dart';

import '../support/tikkun_fakes.dart';

/// מדדי גג מלאכותיים לגופן הבדיקה (בלי משפחה): רצועה של 20% מאמצע האות.
const _fakeRoof = StamRoofMetrics(sliceX: 0.5, sliceWidth: 0.2);

void main() {
  const style = TextStyle(fontSize: 20);
  final gap = tikkunWordWidth(
    String.fromCharCode(kTikkunSmallLetterCode),
    style,
  );
  final words = ['אבג', 'דהם', 'אבג'].map(word).toList();
  double used(TikkunLineFit fit) => tikkunLineItemWidths(
    words: words,
    style: style,
    contentWidth: 1000,
    isStam: true,
    maskDivineName: false,
    fit: fit,
  ).fold(0.0, (a, b) => a + b);
  final natural = used(TikkunLineFit.none);

  setUp(() {
    debugSetStamRoofMetrics('', {
      for (final letter in kTikkunStretchLetters) letter: _fakeRoof,
    });
  });
  tearDown(debugResetStamRoofMetrics);

  test('רק דהלת"ם נמתחות, ולא במילה שיש בה שם הוי"ה', () {
    expect(tikkunStretchableCount('דהלתם'), 5);
    expect(tikkunStretchableCount('אבגם'), 1);
    expect(tikkunStretchableCount('ליהוה'), 0);
    expect(tikkunStretchableCount('ליקוק'), 0);
    expect(tikkunStretchLetterWidths('אבג', style), isEmpty);
    expect(tikkunStretchLetterWidths('דהם', style), hasLength(3));
  });

  test('אות שגגה לא נמדד בגופן אינה נמתחת', () {
    debugResetStamRoofMetrics();
    expect(tikkunStretchLetterWidths('דהם', style), [0, 0, 0]);
    final fit = fitTikkunLine(
      words: words,
      style: style,
      contentWidth: natural + 500,
      maskDivineName: false,
    );
    expect(used(fit), closeTo(natural, 1e-9));
  });

  test('עודף שהרווחים מכילים אינו מותח אות', () {
    final fit = fitTikkunLine(
      words: words,
      style: style,
      contentWidth: natural + 2 * gap * kTikkunMaxWordGapFactor,
      maskDivineName: false,
    );
    expect(fit, TikkunLineFit.none);
  });

  test('מעבר לתקרת הרווחים נמתחת רק האות האחרונה, ואחריה הקודמת לה', () {
    final letters = tikkunStretchLetterWidths('דהם', style);
    final small = letters.last * 0.5;
    final fit = fitTikkunLine(
      words: words,
      style: style,
      contentWidth: natural + 2 * gap * kTikkunMaxWordGapFactor + small,
      maskDivineName: false,
    );
    expect(fit.letterExtras.keys, [1]);
    expect(fit.extrasOf(1), [0, 0, closeTo(small, 1e-9)]);
    expect(used(fit), closeTo(natural + small, 1e-9));

    final over = letters.last * kTikkunMaxLetterStretch + 1;
    final more = fitTikkunLine(
      words: words,
      style: style,
      contentWidth: natural + 2 * gap * kTikkunMaxWordGapFactor + over,
      maskDivineName: false,
    );
    expect(more.extrasOf(1)[2], closeTo(letters.last, 1e-9));
    expect(more.extrasOf(1)[1], closeTo(1, 1e-9));
    expect(more.extrasOf(1)[0], 0);
  });

  test('שורה צפופה מכווצת עד שהרווח המזערי נשמר', () {
    final target = natural - 2 * gap * kTikkunMinWordGapFactor;
    final fit = fitTikkunLine(
      words: words,
      style: style,
      contentWidth: target,
      maskDivineName: false,
    );
    expect(fit.condense, lessThan(1));
    expect(fit.letterExtras, isEmpty);
    expect(
      used(fit) + 2 * gap * kTikkunMinWordGapFactor,
      closeTo(target, 1e-9),
    );
  });

  testWidgets('האות נחתכת בגג, והפער מתמלא בעותקים של רצועת הגג', (
    tester,
  ) async {
    final width = tikkunWordWidth('ד', style);
    final slice = width * 0.2;
    final extra = slice * 2.5;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              tikkunWordText('ד', style, letterExtras: [extra]),
            ],
          ),
        ),
      ),
    );
    final slices = tester
        .widgetList<ClipRect>(find.byType(ClipRect))
        .map((c) => c.clipper)
        .whereType<TikkunLetterSliceClipper>()
        .toList();
    // חלק שמאלי, שלושה עותקי רצועה (2.5 מעוגל למעלה), וחלק ימני מוזז.
    expect(slices, hasLength(5));
    expect(slices.first.right, closeTo(width * 0.5, 1e-9));
    for (final copy in slices.sublist(1, 4)) {
      expect(copy.left, closeTo(width * 0.5, 1e-9));
      expect(copy.right, closeTo(width * 0.5 + slice, 1e-9));
    }
    expect(slices.last.left, closeTo(width * 0.5, 1e-9));
    expect(
      tester.getSize(find.byType(Row).first).width,
      closeTo(width + extra, 1e-9),
    );
    final shifts = tester
        .widgetList<Transform>(find.byType(Transform))
        .map((t) => t.transform.getTranslation().x)
        .toList();
    // העותק הראשון אינו מוזז; השאר צמודים, והאחרון נדחק לקצה ההארכה.
    expect(shifts, [
      closeTo(slice, 1e-9),
      closeTo(extra - slice, 1e-9),
      closeTo(extra, 1e-9),
    ]);

    // ב-PDF כל עותק הוא טקסט חתוך שמסומן כעותק, והאות עצמה נכתבת פעם אחת.
    final page = collectTikkunVectorPage(
      tester.renderObject<RenderBox>(find.byType(Row).first),
    );
    expect(page.rects, isEmpty);
    expect(page.texts, hasLength(5));
    expect(page.texts.where((op) => !op.artifact), hasLength(1));
  });

  testWidgets('מילה מכווצת תופסת את רוחבה המכווץ', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [tikkunWordText('אבג', style, condense: 0.9)],
          ),
        ),
      ),
    );
    final width = tikkunWordWidth('אבג', style);
    expect(tester.getSize(find.byType(Row)).width, closeTo(width * 0.9, 1e-6));

    // ייצוא ה-PDF קורא את הכיווץ מהטרנספורם — כמו את מתיחת הגג.
    final page = collectTikkunVectorPage(
      tester.renderObject<RenderBox>(find.byType(Row)),
    );
    expect(page.texts, hasLength(1));
    expect(page.texts.single.horizontalScale, closeTo(0.9, 1e-6));
    expect(page.texts.single.width, closeTo(width * 0.9, 1e-6));
    expect(page.texts.single.left, closeTo(0, 1e-6));
  });

  testWidgets('אות רבתי אינה מגביהה את המילה ואינה מזיזה את קו הבסיס', (
    tester,
  ) async {
    const lineStyle = TextStyle(fontSize: 20, height: 1.4);
    final big =
        '${String.fromCharCode(kRabatiStart)}ה${String.fromCharCode(kRabatiEnd)}לוא';
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            tikkunWordText('הלוא', lineStyle),
            tikkunWordText(big, lineStyle),
          ],
        ),
      ),
    );
    // מיושרות לקו הבסיס: אותו גובה ואותה עליונה = אותו קו בסיס בתוך המילה.
    final plain = tester.getRect(find.byType(RichText).at(0));
    final withBig = tester.getRect(find.byType(RichText).at(1));
    expect(withBig.height, plain.height);
    expect(withBig.top, plain.top);
  });

  test('ר נמתחת רק אחרי שדהלת"ם שבשורה מוצו', () {
    final line = ['דר', 'אב'].map(word).toList();
    final lineNatural = tikkunLineItemWidths(
      words: line,
      style: style,
      contentWidth: 1000,
      isStam: true,
      maskDivineName: false,
    ).fold(0.0, (a, b) => a + b);
    final dalet = tikkunWordWidth('ד', style);
    TikkunLineFit fitWith(double free) => fitTikkunLine(
      words: line,
      style: style,
      contentWidth: lineNatural + gap * kTikkunMaxWordGapFactor + free,
      maskDivineName: false,
    );

    final little = fitWith(dalet * 0.5).extrasOf(0);
    expect(little[0], closeTo(dalet * 0.5, 1e-6));
    expect(little[1], 0);

    final more = fitWith(dalet * kTikkunMaxLetterStretch + 2).extrasOf(0);
    expect(more[0], closeTo(dalet * kTikkunMaxLetterStretch, 1e-6));
    expect(more[1], closeTo(2, 1e-6));
  });
}
