// סעיף 17: פריטי AppTopBar עם עדיפות עוברים לתפריט "עוד" כשאין מקום.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';

const _moreTooltip = 'עוד פעולות';

/// כפתור דמה ברוחב ידוע, כדי שהחישוב לא יתלה בעיצוב כפתור אמיתי.
AppTopBarItem _item(
  String name,
  List<String> log, {
  AppTopBarPriority priority = AppTopBarPriority.critical,
  double width = 48,
  FocusNode? focusNode,
}) {
  return AppTopBarItem(
    priority: priority,
    menuAction: priority == AppTopBarPriority.critical
        ? null
        : AppTopBarMenuAction(
            label: 'פעולה $name',
            icon: Icons.add,
            onPressed: () => log.add(name),
          ),
    widget: Focus(
      focusNode: focusNode,
      child: Listener(
        key: Key(name),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(width: width, height: 40),
      ),
    ),
  );
}

Widget _app({
  required double width,
  List<AppTopBarItem> leading = const [],
  List<AppTopBarItem> trailing = const [],
  Widget? center,
  double? minCenterWidth,
  double textScale = 1.0,
  TextDirection direction = TextDirection.rtl,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: Directionality(textDirection: direction, child: child!),
    ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          child: AppTopBar(
            leadingItems: leading,
            trailingItems: trailing,
            center: center,
            minCenterWidth: minCenterWidth,
          ),
        ),
      ),
    ),
  );
}

bool _shown(WidgetTester tester, String name) =>
    tester.any(find.byKey(Key(name)).hitTestable());

bool _moreShown(WidgetTester tester) =>
    tester.any(find.byTooltip(_moreTooltip).hitTestable());

void main() {
  group('AppTopBar: פריטים בעדיפות עוברים ל"עוד"', () {
    for (final direction in TextDirection.values) {
      testWidgets('יש מקום לכולם: הכל גלוי ואין "עוד" ($direction)', (
        tester,
      ) async {
        final log = <String>[];
        await tester.pumpWidget(
          _app(
            width: 400,
            direction: direction,
            leading: [
              _item('c', log),
              _item('n', log, priority: AppTopBarPriority.normal),
              _item('l', log, priority: AppTopBarPriority.low),
            ],
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        for (final name in ['c', 'n', 'l']) {
          expect(_shown(tester, name), isTrue, reason: name);
        }
        expect(_moreShown(tester), isFalse);
      });
    }

    testWidgets('אין מקום: נמוך ואחריו רגיל עוברים, הקריטי נשאר', (
      tester,
    ) async {
      final log = <String>[];
      // 16 ריפוד + 108: קריטי (48) + רווח (8) + "עוד" (52, מגע כברירת מחדל) בדיוק.
      await tester.pumpWidget(
        _app(
          width: 124,
          leading: [
            _item('c', log),
            _item('n', log, priority: AppTopBarPriority.normal),
            _item('l', log, priority: AppTopBarPriority.low),
            _item('l2', log, priority: AppTopBarPriority.low),
          ],
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_shown(tester, 'c'), isTrue);
      for (final name in ['n', 'l', 'l2']) {
        expect(_shown(tester, name), isFalse, reason: name);
      }
      expect(_moreShown(tester), isTrue);
      // הכל בתוך הסרגל.
      final bar = tester.getRect(find.byType(AppTopBar));
      expect(
        bar.contains(tester.getRect(find.byTooltip(_moreTooltip)).center),
        isTrue,
      );
    });

    testWidgets('עדיפות קודמת למיקום: נמוך מוקדם עובר לפני רגיל מאוחר', (
      tester,
    ) async {
      final log = <String>[];
      // פריטים ברוחב 64: שניים לא נכנסים (136 > 108), אחד ו"עוד" כן (124 <= 130).
      await tester.pumpWidget(
        _app(
          width: 146,
          leading: [
            _item('l', log, priority: AppTopBarPriority.low, width: 64),
            _item('n', log, priority: AppTopBarPriority.normal, width: 64),
          ],
        ),
      );
      await tester.pump();
      expect(_shown(tester, 'n'), isTrue);
      expect(_shown(tester, 'l'), isFalse);
      expect(_moreShown(tester), isTrue);
    });

    testWidgets('באותה עדיפות עובר קודם המאוחר', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(
        _app(
          width: 146,
          leading: [
            _item('a', log, priority: AppTopBarPriority.normal, width: 64),
            _item('b', log, priority: AppTopBarPriority.normal, width: 64),
          ],
        ),
      );
      await tester.pump();
      expect(_shown(tester, 'a'), isTrue);
      expect(_shown(tester, 'b'), isFalse);
    });

    testWidgets('בחירה בתפריט מפעילה את הפעולה, ורק הפעולות שעברו מופיעות', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(
        _app(
          width: 124,
          leading: [
            _item('c', log),
            _item('n', log, priority: AppTopBarPriority.normal),
            _item('l', log, priority: AppTopBarPriority.low),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(); // עדכון המצב אחרי ה-frame
      await tester.tap(find.byTooltip(_moreTooltip));
      await tester.pumpAndSettle();
      expect(find.text('פעולה n'), findsOneWidget);
      expect(find.text('פעולה l'), findsOneWidget);
      // סדר הפריטים בתפריט כסדרם בסרגל.
      expect(
        tester.getTopLeft(find.text('פעולה n')).dy,
        lessThan(tester.getTopLeft(find.text('פעולה l')).dy),
      );
      await tester.tap(find.text('פעולה l'));
      await tester.pumpAndSettle();
      expect(log, ['l']);
    });

    testWidgets('הגדלת הרוחב מחזירה את הפריטים והתפריט נעלם', (tester) async {
      final log = <String>[];
      final leading = [
        _item('c', log),
        _item('l', log, priority: AppTopBarPriority.low),
      ];
      await tester.pumpWidget(_app(width: 112, leading: leading));
      await tester.pump();
      expect(_shown(tester, 'l'), isFalse);
      expect(_moreShown(tester), isTrue);

      await tester.pumpWidget(_app(width: 300, leading: leading));
      await tester.pump();
      await tester.pump();
      expect(_shown(tester, 'l'), isTrue);
      expect(_moreShown(tester), isFalse);
    });

    testWidgets('פריט שעבר ל"עוד" לא מקבל פוקוס מקלדת', (tester) async {
      final log = <String>[];
      final keep = FocusNode();
      final folded = FocusNode();
      addTearDown(keep.dispose);
      addTearDown(folded.dispose);
      await tester.pumpWidget(
        _app(
          width: 112,
          leading: [
            _item('c', log, focusNode: keep),
            _item(
              'l',
              log,
              priority: AppTopBarPriority.low,
              focusNode: folded,
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(keep.canRequestFocus, isTrue);
      expect(folded.canRequestFocus, isFalse);
    });

    testWidgets('פריטי סיום ופריטי התחלה מקפלים כל צד בנפרד', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(
        _app(
          width: 260,
          leading: [
            _item('lc', log),
            _item('ll', log, priority: AppTopBarPriority.low),
          ],
          trailing: [
            _item('tc', log),
            _item('tl', log, priority: AppTopBarPriority.low),
            _item('tl2', log, priority: AppTopBarPriority.low),
          ],
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_shown(tester, 'lc'), isTrue);
      expect(_shown(tester, 'tc'), isTrue);
      // רוחב הפריטים הגלויים לא חורג מהסרגל.
      final bar = tester.getRect(find.byType(AppTopBar));
      for (final name in ['lc', 'tc']) {
        final r = tester.getRect(find.byKey(Key(name)));
        expect(
          r.left >= bar.left && r.right <= bar.right,
          isTrue,
          reason: name,
        );
      }
    });

    testWidgets('פריט גמיש מקבל רוחב חסום (לא אינסוף) לצד פריטים מתקפלים', (
      tester,
    ) async {
      final log = <String>[];
      double? seen;
      await tester.pumpWidget(
        _app(
          width: 300,
          leading: [_item('n', log, priority: AppTopBarPriority.normal)],
          trailing: [
            AppTopBarItem(
              flexible: true,
              widget: LayoutBuilder(
                builder: (context, c) {
                  seen = c.maxWidth;
                  return const SizedBox(width: 20, height: 40);
                },
              ),
            ),
          ],
        ),
      );
      await tester.pump();
      expect(seen, isNotNull);
      expect(seen!.isFinite, isTrue);
    });

    test('פריט בעדיפות בלי פעולת תפריט נפסל', () {
      expect(
        () => AppTopBarItem(
          widget: const SizedBox(),
          priority: AppTopBarPriority.low,
        ),
        throwsAssertionError,
      );
    });
  });
}
