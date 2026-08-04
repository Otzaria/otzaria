import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/view/reading_tab_strip.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/view/pane_drop_geometry.dart';
import 'package:otzaria/tabs/view/pane_drop_target.dart';

class _StubTab extends OpenedTab {
  _StubTab(super.title);

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
                  tabs: tabs,
                  widths: widths,
                  requireLongPressToDrag: requireLongPress,
                  onReorder: log.reorder,
                  onDragStarted: () => log.dragStarts++,
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
    final gesture = await tester.startGesture(start);
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
        find.byWidgetPredicate((w) => w.runtimeType == Draggable<OpenedTab>),
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
