import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/view/reading_tab_strip.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/view/pane_drop_geometry.dart';
import 'package:otzaria/tabs/view/pane_drop_target.dart';

class _StubTab extends OpenedTab {
  _StubTab(super.title);

  /// stub חסר state — אין מה לשכפל.
  @override
  OpenedTab clone() => this;

  @override
  Map<String, dynamic> toJson() => {'type': '_StubTab', 'title': title};
}

/// תופס את פעולות הרצועה.
class _StripLog {
  OpenedTab? movedTab;
  int? newIndex;
  int moves = 0;
  int dragStarts = 0;
  final List<OpenedTab> springOpened = [];

  void reorder(OpenedTab tab, int index) {
    movedTab = tab;
    newIndex = index;
    moves++;
  }
}

void main() {
  const stripKey = Key('strip');
  const paneKey = Key('pane');
  const tabWidth = 100.0;

  /// רצועה עם שלוש כרטיסיות, ולצדה חלונית קריאה שמקבלת גרירות.
  Widget host({
    required _StripLog log,
    required List<OpenedTab> tabs,
    void Function(OpenedTab, PaneDropSide)? onPaneDrop,
    TextDirection textDirection = TextDirection.rtl,
    bool requireLongPress = false,
    // רוחב הרצועה. ברירת המחדל צמודה לכרטיסיות, אך במסך אמיתי היא רחבה
    // מהן — ואז מדידה מול גבולותיה במקום מול השורה מטה את מיקום ההכנסה.
    double? stripWidth,
    List<double>? tabWidths,
  }) {
    final widths = tabWidths ?? [for (final _ in tabs) tabWidth];
    return MaterialApp(
      home: Directionality(
        textDirection: textDirection,
        child: Scaffold(
          body: Column(
            children: [
              SizedBox(
                key: stripKey,
                height: 40,
                width:
                    stripWidth ??
                    widths.fold<double>(0, (sum, width) => sum + width),
                child: ReadingTabStrip(
                  stripColor: const Color(0xFFF2EBE0),
                  tabs: tabs,
                  widths: widths,
                  requireLongPressToDrag: requireLongPress,
                  onReorder: log.reorder,
                  onDragStarted: (_, _) => log.dragStarts++,
                  onSpringOpen: log.springOpened.add,
                  tabBuilder: (tab, index, width) => SizedBox(
                    width: width,
                    child: ColoredBox(
                      color: const Color(0xFFDDDDDD),
                      child: Center(child: Text(tab.title)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PaneDropTarget(
                  key: paneKey,
                  tab: _StubTab('מוצג'),
                  onDrop: onPaneDrop ?? (_, _) {},
                  child: const ColoredBox(
                    color: Color(0xFFEEEEEE),
                    child: SizedBox.expand(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// גוררת מכרטיסיה [from] אל [target] ומשחררת.
  Future<void> dragFrom(WidgetTester tester, String from, Offset target) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.text(from)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// השהיית גרירה מעל [over], בלי לשחרר. מחזירה את המחווה כדי להמשיך אותה.
  ///
  /// היעדים נמדדים לפני תחילת הגרירה: משעה שהיא רצה, טקסט הכרטיסיה מופיע
  /// פעמיים — במקומה המקורי ובמשוב הנגרר.
  Future<TestGesture> hoverDrag(
    WidgetTester tester,
    String from,
    String over, {
    required Duration dwell,
  }) async {
    final start = tester.getCenter(find.text(from));
    final target = tester.getCenter(find.text(over));
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(target);
    await tester.pump(dwell);
    return gesture;
  }

  group('פתיחת כרטיסיה בהשהיית גרירה', () {
    testWidgets('השהייה מעל כרטיסיה אחרת פותחת אותה', (tester) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      await tester.pumpWidget(host(log: log, tabs: tabs));

      final gesture = await hoverDrag(
        tester,
        'א',
        'ג',
        dwell: kTabSpringOpenDelay + const Duration(milliseconds: 20),
      );

      expect(log.springOpened, [same(tabs[2])]);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('מעבר חטוף מעל כרטיסיה אינו פותח אותה', (tester) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      await tester.pumpWidget(host(log: log, tabs: tabs));

      // חוצים את 'ב' בדרך אל 'ג' — פחות מזמן ההשהיה בכל אחת מהן.
      final thirdTabCenter = tester.getCenter(find.text('ג'));
      final gesture = await hoverDrag(
        tester,
        'א',
        'ב',
        dwell: const Duration(milliseconds: 80),
      );
      await gesture.moveTo(thirdTabCenter);
      await tester.pump(const Duration(milliseconds: 80));

      expect(log.springOpened, isEmpty);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('השהייה מעל הכרטיסיה הנגררת עצמה אינה פותחת דבר', (
      tester,
    ) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      await tester.pumpWidget(host(log: log, tabs: tabs));

      final gesture = await hoverDrag(
        tester,
        'ב',
        'ב',
        dwell: kTabSpringOpenDelay + const Duration(milliseconds: 20),
      );

      expect(log.springOpened, isEmpty);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('יציאה מהרצועה לפני תום ההשהיה מבטלת את הפתיחה', (
      tester,
    ) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      await tester.pumpWidget(host(log: log, tabs: tabs));

      final gesture = await hoverDrag(
        tester,
        'א',
        'ג',
        dwell: const Duration(milliseconds: 80),
      );
      await gesture.moveTo(tester.getCenter(find.byKey(paneKey)));
      await tester.pump(kTabSpringOpenDelay + const Duration(milliseconds: 20));

      expect(log.springOpened, isEmpty);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('השהייה ארוכה פותחת פעם אחת בלבד', (tester) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      await tester.pumpWidget(host(log: log, tabs: tabs));

      final gesture = await hoverDrag(
        tester,
        'א',
        'ג',
        dwell: kTabSpringOpenDelay * 4,
      );

      expect(log.springOpened, hasLength(1));

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('סידור מחדש', () {
    testWidgets('גרירה שמאלה ב-RTL מזיזה את הכרטיסיה קדימה ברשימה', (
      tester,
    ) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      await tester.pumpWidget(host(log: log, tabs: tabs));

      // ב-RTL הכרטיסיה הראשונה בימין; גרירת 'א' שמאלה מעבירה אותה אחרי 'ב'.
      await dragFrom(tester, 'א', tester.getCenter(find.text('ג')));

      expect(log.moves, 1);
      expect(log.movedTab, same(tabs[0]));
      expect(log.newIndex, greaterThan(0));
    });

    testWidgets('גרירה למקום שלא זז אינה שולחת סידור מחדש', (tester) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      await tester.pumpWidget(host(log: log, tabs: tabs));

      await dragFrom(tester, 'ב', tester.getCenter(find.text('ב')));

      expect(log.moves, 0);
    });

    testWidgets('היעד מדווח בקונבנציית הסרה-ואז-הכנסה', (tester) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      await tester.pumpWidget(host(log: log, tabs: tabs));

      // גרירת הכרטיסיה האחרונה אל תחילת הרצועה (הקצה הימני ב-RTL).
      final strip = tester.getRect(find.byKey(stripKey));
      await dragFrom(tester, 'ג', Offset(strip.right - 4, strip.center.dy));

      expect(log.moves, 1);
      expect(log.movedTab, same(tabs[2]));
      expect(log.newIndex, 0, reason: 'הכרטיסיה עוברת לראש הרשימה');
    });

    testWidgets('רצועה רחבה מהכרטיסיות: הגרירה מסדרת לפי מקום המצביע', (
      tester,
    ) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      // המצב הרגיל במסך רחב: 3 כרטיסיות של 100 בתוך רצועה של 700. ב-RTL הן
      // צמודות לימין, וכל השטח הריק שמשמאלן נכנס לחישוב אם מודדים אותו.
      await tester.pumpWidget(host(log: log, tabs: tabs, stripWidth: 700));

      await dragFrom(tester, 'א', tester.getCenter(find.text('ג')));

      expect(log.moves, 1, reason: 'גרירה על כרטיסיה אחרת מסדרת מחדש');
      expect(log.movedTab, same(tabs[0]));
      expect(log.newIndex, 2, reason: "'א' עוברת אל מקומה של 'ג'");
    });

    testWidgets('רצועה רחבה: גרירה על עצמה אינה מזיזה', (tester) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      await tester.pumpWidget(host(log: log, tabs: tabs, stripWidth: 700));

      await dragFrom(tester, 'ב', tester.getCenter(find.text('ב')));

      expect(log.moves, 0);
    });

    testWidgets('רצועה רחבה ב-LTR מסדרת לכיוון הנגדי', (tester) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      await tester.pumpWidget(
        host(
          log: log,
          tabs: tabs,
          stripWidth: 700,
          textDirection: TextDirection.ltr,
        ),
      );

      // תחילת הרשימה ב-LTR היא הקצה השמאלי; מרכז הכרטיסיה הראשונה הוא
      // בדיוק הגבול שבו מיקום ההכנסה מתחלף.
      final strip = tester.getRect(find.byKey(stripKey));
      await dragFrom(tester, 'ג', Offset(strip.left + 4, strip.center.dy));

      expect(log.moves, 1);
      expect(log.newIndex, 0);
    });

    testWidgets('ב-LTR הכיוון מתהפך', (tester) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      await tester.pumpWidget(
        host(log: log, tabs: tabs, textDirection: TextDirection.ltr),
      );

      final strip = tester.getRect(find.byKey(stripKey));
      await dragFrom(tester, 'ג', Offset(strip.left + 4, strip.center.dy));

      expect(log.moves, 1);
      expect(log.newIndex, 0);
    });

    testWidgets('רוחבים לא אחידים שומרים על יעד הגרירה ב-RTL', (tester) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      await tester.pumpWidget(
        host(log: log, tabs: tabs, tabWidths: const [60, 140, 80]),
      );

      await dragFrom(tester, 'א', tester.getCenter(find.text('ג')));

      expect(log.moves, 1);
      expect(log.movedTab, same(tabs[0]));
      expect(log.newIndex, 2);
    });

    testWidgets('רוחבים לא אחידים שומרים על יעד הגרירה ב-LTR', (tester) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      await tester.pumpWidget(
        host(
          log: log,
          tabs: tabs,
          tabWidths: const [60, 140, 80],
          textDirection: TextDirection.ltr,
        ),
      );

      final strip = tester.getRect(find.byKey(stripKey));
      await dragFrom(tester, 'ג', Offset(strip.left + 4, strip.center.dy));

      expect(log.moves, 1);
      expect(log.movedTab, same(tabs[2]));
      expect(log.newIndex, 0);
    });
  });

  group('חיווי מיקום ההכנסה', () {
    testWidgets('קו החיווי מופיע בגרירה מעל הרצועה ונעלם בשחרור', (
      tester,
    ) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב')];
      await tester.pumpWidget(host(log: log, tabs: tabs));

      Finder line() => find.descendant(
        of: find.byType(ReadingTabStrip),
        matching: find.byType(DecoratedBox),
      );
      final before = line().evaluate().length;

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('א')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.moveTo(tester.getCenter(find.text('ב')));
      await tester.pump();

      expect(line().evaluate().length, greaterThan(before));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(line().evaluate().length, before);
    });
  });

  group('גרירה אל חלונית קריאה', () {
    testWidgets('שחרור מעל אזור הקריאה מפצל ואינו מסדר מחדש', (tester) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב')];
      OpenedTab? dropped;
      PaneDropSide? side;

      await tester.pumpWidget(
        host(
          log: log,
          tabs: tabs,
          onPaneDrop: (tab, droppedSide) {
            dropped = tab;
            side = droppedSide;
          },
        ),
      );

      // ב-RTL החצי השמאלי הוא החלונית השנייה.
      final pane = tester.getRect(find.byKey(paneKey));
      await dragFrom(tester, 'א', Offset(pane.left + 8, pane.center.dy));

      expect(dropped, same(tabs[0]), reason: 'ההפלה הגיעה אל אזור הקריאה');
      expect(side, PaneDropSide.end);
      expect(log.moves, 0, reason: 'שחרור מחוץ לרצועה אינו מסדר מחדש');
    });

    testWidgets('תחילת גרירה מדווחת פעם אחת', (tester) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב')];
      await tester.pumpWidget(host(log: log, tabs: tabs));

      final pane = tester.getRect(find.byKey(paneKey));
      await dragFrom(tester, 'א', pane.center);

      expect(log.dragStarts, 1);
    });
  });

  group('פלטפורמה', () {
    testWidgets('בדסקטופ הגרירה מיידית', (tester) async {
      final log = _StripLog();
      await tester.pumpWidget(host(log: log, tabs: [_StubTab('א')]));

      expect(
        find.byWidgetPredicate((w) => w is Draggable<OpenedTab>),
        findsOneWidget,
      );
      expect(find.byType(LongPressDraggable<OpenedTab>), findsNothing);
    });

    testWidgets('במגע נדרשת לחיצה ארוכה', (tester) async {
      final log = _StripLog();
      await tester.pumpWidget(
        host(log: log, tabs: [_StubTab('א')], requireLongPress: true),
      );

      expect(find.byType(LongPressDraggable<OpenedTab>), findsOneWidget);
    });
  });

  group('ציר אנכי', () {
    /// רצועה אנכית של שלוש כרטיסיות בגובה קבוע.
    Widget verticalHost({
      required _StripLog log,
      required List<OpenedTab> tabs,
      TextDirection textDirection = TextDirection.rtl,
      // גובה הרצועה. ברירת המחדל מכילה את כל הכרטיסיות; גובה קטן ממנה הופך
      // אותה לנגללת.
      double? stripHeight,
    }) {
      const itemHeight = 40.0;
      return MaterialApp(
        home: Directionality(
          textDirection: textDirection,
          child: Scaffold(
            body: Row(
              children: [
                SizedBox(
                  key: stripKey,
                  width: 200,
                  height: stripHeight ?? tabs.length * itemHeight,
                  child: ReadingTabStrip(
                    stripColor: const Color(0xFFF2EBE0),
                    axis: Axis.vertical,
                    scrollable: true,
                    crossExtent: 200,
                    tabs: tabs,
                    widths: [for (final _ in tabs) itemHeight],
                    onReorder: log.reorder,
                    onDragStarted: (_, _) => log.dragStarts++,
                    onSpringOpen: log.springOpened.add,
                    tabBuilder: (tab, index, extent) => SizedBox(
                      height: extent,
                      child: ColoredBox(
                        color: const Color(0xFFDDDDDD),
                        child: Center(child: Text(tab.title)),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: PaneDropTarget(
                    key: paneKey,
                    tab: _StubTab('מוצג'),
                    onDrop: (_, _) {},
                    child: const ColoredBox(
                      color: Color(0xFFEEEEEE),
                      child: SizedBox.expand(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('גרירה מטה מעבירה את הכרטיסיה אחורה ברשימה', (tester) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      await tester.pumpWidget(verticalHost(log: log, tabs: tabs));

      await dragFrom(tester, 'א', tester.getCenter(find.text('ג')));

      expect(log.moves, 1);
      expect(log.movedTab, same(tabs[0]));
      expect(log.newIndex, 2);
    });

    testWidgets('גרירה מעלה מעבירה את הכרטיסיה לראש הרשימה', (tester) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      await tester.pumpWidget(verticalHost(log: log, tabs: tabs));

      final strip = tester.getRect(find.byKey(stripKey));
      await dragFrom(tester, 'ג', Offset(strip.center.dx, strip.top + 4));

      expect(log.moves, 1);
      expect(log.newIndex, 0);
    });

    testWidgets('הכיוון האנכי זהה ב-RTL וב-LTR — אין היפוך', (tester) async {
      final results = <TextDirection, int?>{};
      for (final direction in TextDirection.values) {
        final log = _StripLog();
        final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
        await tester.pumpWidget(
          verticalHost(log: log, tabs: tabs, textDirection: direction),
        );
        await dragFrom(tester, 'א', tester.getCenter(find.text('ג')));
        results[direction] = log.newIndex;
      }

      expect(results[TextDirection.rtl], 2);
      expect(
        results[TextDirection.ltr],
        results[TextDirection.rtl],
        reason: 'בציר אנכי הכיווניות אינה מהפכת את סדר הכרטיסיות',
      );
    });

    testWidgets('שחרור מעל אזור הקריאה מפצל ואינו מסדר מחדש', (tester) async {
      final log = _StripLog();
      final tabs = [_StubTab('א'), _StubTab('ב')];
      await tester.pumpWidget(verticalHost(log: log, tabs: tabs));

      await dragFrom(tester, 'א', tester.getCenter(find.byKey(paneKey)));

      expect(log.moves, 0);
      expect(log.dragStarts, 1);
    });

    group('גלילה אוטומטית בגרירה', () {
      /// 12 כרטיסיות בגובה 40 בתוך רצועה של 200 — רק חמש נראות.
      List<OpenedTab> manyTabs() => [
        for (var i = 0; i < 12; i++) _StubTab('כרטיסיה $i'),
      ];

      ScrollPosition stripPosition(WidgetTester tester) => tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(ReadingTabStrip),
              matching: find.byType(Scrollable),
            ),
          )
          .position;

      testWidgets('גרירה אל הקצה התחתון גוללת את הרשימה', (tester) async {
        final log = _StripLog();
        await tester.pumpWidget(
          verticalHost(log: log, tabs: manyTabs(), stripHeight: 200),
        );

        final strip = tester.getRect(find.byKey(stripKey));
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('כרטיסיה 0')),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 20));
        await gesture.moveTo(Offset(strip.center.dx, strip.bottom - 8));
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          stripPosition(tester).pixels,
          greaterThan(0),
          reason: 'הרשימה נגללת כשהסמן נכנס לאזור הקצה',
        );

        await gesture.up();
        await tester.pumpAndSettle();
      });

      testWidgets('הגלילה נעצרת בסוף הרשימה ואינה משאירה שעון פעיל', (
        tester,
      ) async {
        final log = _StripLog();
        await tester.pumpWidget(
          verticalHost(log: log, tabs: manyTabs(), stripHeight: 200),
        );

        final strip = tester.getRect(find.byKey(stripKey));
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('כרטיסיה 0')),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 20));
        await gesture.moveTo(Offset(strip.center.dx, strip.bottom - 8));
        // מספיק זמן כדי להגיע לקצה — משם הגלילה חייבת לעצור מעצמה.
        await tester.pumpAndSettle();

        final position = stripPosition(tester);
        expect(position.pixels, position.maxScrollExtent);

        await gesture.up();
        await tester.pumpAndSettle();
      });

      testWidgets('חזרה למרכז הרצועה עוצרת את הגלילה', (tester) async {
        final log = _StripLog();
        await tester.pumpWidget(
          verticalHost(log: log, tabs: manyTabs(), stripHeight: 200),
        );

        final strip = tester.getRect(find.byKey(stripKey));
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('כרטיסיה 0')),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 20));
        await gesture.moveTo(Offset(strip.center.dx, strip.bottom - 8));
        await tester.pump(const Duration(milliseconds: 100));
        await gesture.moveTo(strip.center);
        await tester.pump();

        final afterStop = stripPosition(tester).pixels;
        expect(afterStop, greaterThan(0));

        await tester.pump(const Duration(milliseconds: 300));
        expect(stripPosition(tester).pixels, afterStop);

        await gesture.up();
        await tester.pumpAndSettle();
      });

      testWidgets('גלילת הקצה מאפשרת להעביר כרטיסיה אל סוף רשימה ארוכה', (
        tester,
      ) async {
        final log = _StripLog();
        final tabs = manyTabs();
        await tester.pumpWidget(
          verticalHost(log: log, tabs: tabs, stripHeight: 200),
        );

        final strip = tester.getRect(find.byKey(stripKey));
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('כרטיסיה 0')),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 20));
        await gesture.moveTo(Offset(strip.center.dx, strip.bottom - 8));
        await tester.pumpAndSettle();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(log.moves, 1);
        expect(log.movedTab, same(tabs[0]));
        expect(
          log.newIndex,
          tabs.length - 1,
          reason: 'בלי גלילה היעד היה נעצר על הכרטיסיה האחרונה שנראתה',
        );
      });

      testWidgets(
        'בדסקטופ גרירת מגע גוללת את הרשימה ואינה גוררת כרטיסיה (issue #2307)',
        (tester) async {
          final log = _StripLog();
          await tester.pumpWidget(
            verticalHost(log: log, tabs: manyTabs(), stripHeight: 200),
          );

          await tester.timedDragFrom(
            tester.getCenter(find.text('כרטיסיה 3')),
            const Offset(0, -120),
            const Duration(milliseconds: 300),
          );
          await tester.pumpAndSettle();

          expect(log.dragStarts, 0);
          expect(stripPosition(tester).pixels, greaterThan(0));

          // לחיצה ארוכה במגע עדיין גוררת.
          final gesture = await tester.startGesture(
            tester.getCenter(find.text('כרטיסיה 5')),
          );
          await tester.pump(kLongPressTimeout);
          await gesture.moveBy(const Offset(0, 40));
          await tester.pump();
          expect(log.dragStarts, 1);
          await gesture.up();
          await tester.pumpAndSettle();
        },
      );
    });
  });

  group('מקרי קצה', () {
    testWidgets('כרטיסיה יחידה אינה מסדרת מחדש', (tester) async {
      final log = _StripLog();
      await tester.pumpWidget(host(log: log, tabs: [_StubTab('יחיד')]));

      final strip = tester.getRect(find.byKey(stripKey));
      await dragFrom(tester, 'יחיד', Offset(strip.left + 4, strip.center.dy));

      expect(log.moves, 0);
    });

    testWidgets('רצועה ריקה נבנית בלי שגיאה', (tester) async {
      final log = _StripLog();
      await tester.pumpWidget(host(log: log, tabs: const []));

      expect(find.byType(ReadingTabStrip), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
