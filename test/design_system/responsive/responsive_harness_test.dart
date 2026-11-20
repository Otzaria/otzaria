// בדיקת עצמית של תשתית ה-Responsive: רכיבים שבורים בכוונה חייבים להיתפס,
// ורכיבים תקינים חייבים לעבור. בלי זה, "הכל ירוק" לא מוכיח שהתשתית מזהה.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'responsive_harness.dart';

const _narrow = ResponsiveViewport(320, 640);

Future<ResponsiveRun> _pump(WidgetTester tester, Widget child) =>
    pumpResponsive(tester, _narrow, (_) => child);

void main() {
  testWidgets('overflow של Row נתפס, וגם מסווג כ-overflow', (tester) async {
    final run = await _pump(
      tester,
      Row(
        children: [
          for (var i = 0; i < 4; i++)
            const SizedBox(width: 120, height: 40, child: Text('פעולה')),
        ],
      ),
    );
    run.release();
    expect(run.issues.map((i) => i.kind), contains('overflow'));
  });

  testWidgets('כפתור מחוץ לחלון נתפס כ-outside-viewport', (tester) async {
    final run = await _pump(
      tester,
      Stack(
        children: [
          PositionedDirectional(
            start: 400,
            top: 10,
            child: ElevatedButton(onPressed: () {}, child: const Text('שמור')),
          ),
        ],
      ),
    );
    expectVisible(tester, run, find.text('שמור'), name: 'שמור');
    run.release();
    expect(run.issues.map((i) => i.kind), contains('outside-viewport'));
  });

  testWidgets('כפתור שמוסתר מאחורי רכיב אחר נתפס כ-not-visible', (
    tester,
  ) async {
    final run = await _pump(
      tester,
      Stack(
        children: [
          Center(
            child: ElevatedButton(onPressed: () {}, child: const Text('מחק')),
          ),
          Positioned.fill(child: Container(color: Colors.white)),
        ],
      ),
    );
    expectVisible(tester, run, find.text('מחק'), name: 'מחק');
    run.release();
    expect(run.issues.map((i) => i.kind), contains('not-visible'));
  });

  testWidgets('expectReachable מקבל פקד בתוך גלילה ודוחה פקד שלא קיים', (
    tester,
  ) async {
    final run = await _pump(
      tester,
      ListView(
        children: [
          for (var i = 0; i < 40; i++)
            SizedBox(height: 60, child: Text('שורה $i')),
          ElevatedButton(onPressed: () {}, child: const Text('בתחתית')),
        ],
      ),
    );
    await expectReachable(
      tester,
      run,
      find.text('בתחתית'),
      name: 'בתחתית',
      scrollable: find.byType(Scrollable),
    );
    await expectReachable(
      tester,
      run,
      find.text('אין כזה'),
      name: 'אין כזה',
      scrollable: find.byType(Scrollable),
    );
    run.release();
    expect(run.issues, hasLength(1));
    expect(run.issues.single.kind, 'not-reachable');
  });

  testWidgets('טקסט שנחתך ב-maxLines נתפס', (tester) async {
    final run = await _pump(
      tester,
      const SizedBox(
        width: 100,
        child: Text(
          'טקסט ארוך מאוד שלא ייכנס בשורה אחת של מאה פיקסלים',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
    expectNoClippedText(tester, run);
    run.release();
    expect(run.issues.map((i) => i.kind), contains('clipped-text'));
  });

  testWidgets('גלילה אופקית נתפסת, ושדה טקסט חד־שורתי לא', (tester) async {
    final run = await _pump(
      tester,
      Column(
        children: [
          const TextField(),
          SizedBox(
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < 10; i++)
                  const SizedBox(width: 100, child: Text('פריט')),
              ],
            ),
          ),
        ],
      ),
    );
    expectNoHorizontalScroll(tester, run);
    run.release();
    expect(run.issues, hasLength(1));
    expect(run.issues.single.kind, 'horizontal-scroll');
  });

  testWidgets('שטח נגיעה קטן מ-48 נתפס', (tester) async {
    final run = await _pump(
      tester,
      const Center(
        child: SizedBox(width: 24, height: 24, child: Icon(Icons.close)),
      ),
    );
    expectTapTarget(tester, run, find.byType(Icon), name: 'סגור');
    run.release();
    expect(run.issues.single.kind, 'tap-target');
  });

  testWidgets('רכיב תקין לא מייצר כשלים', (tester) async {
    final run = await _pump(
      tester,
      Column(
        children: [
          const TextField(),
          Wrap(
            children: [
              for (var i = 0; i < 6; i++)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: ElevatedButton(
                    onPressed: () {},
                    child: const Text('פעולה'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
    expectVisible(tester, run, find.byType(TextField), name: 'שדה');
    expectNoHorizontalScroll(tester, run);
    expectNoClippedText(tester, run);
    run.release();
    expect(run.issues, isEmpty);
  });

  testWidgets('allowError מדלג על שגיאה מוצהרת', (tester) async {
    final run = ResponsiveRun(_narrow)..allowError('overflowed by');
    expect(run.issues, isEmpty);
  });
  testWidgets(
    'מקלדת וירטואלית: שדה שהמקלדת מסתירה נתפס, ושדה שה-Scaffold מרים לא',
    (
      tester,
    ) async {
      Widget field() => const Align(
        alignment: AlignmentDirectional.bottomCenter,
        child: TextField(key: Key('bottom-field')),
      );
      // Scaffold רגיל מקטין את הגוף בגובה המקלדת: השדה נשאר גלוי.
      final ok = await pumpResponsive(
        tester,
        _narrow,
        (_) => field(),
        keyboardHeight: 300,
      );
      expectVisible(
        tester,
        ok,
        find.byKey(const Key('bottom-field')),
        name: 'שדה',
      );
      ok.release();
      expect(ok.issues, isEmpty);

      // מסך שמבטל את ההתאמה למקלדת: השדה נשאר מתחתיה.
      final bad = await pumpResponsive(
        tester,
        _narrow,
        (_) => Scaffold(resizeToAvoidBottomInset: false, body: field()),
        scaffold: false,
        keyboardHeight: 300,
      );
      expectVisible(
        tester,
        bad,
        find.byKey(const Key('bottom-field')),
        name: 'שדה',
      );
      bad.release();
      expect(bad.issues.map((i) => i.kind), contains('outside-viewport'));
    },
  );
}
