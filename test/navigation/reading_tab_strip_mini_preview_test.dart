import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/tab_drag_preview.dart';
import 'package:otzaria/navigation/view/reading_tab_strip.dart';
import 'package:otzaria/tabs/models/tab.dart';

/// התצוגה המוקטנת שנגררת *בתוך* החלון: אסור לה לחכות לצילום בגודל החלון,
/// אחרת גרירה קצרה מסתיימת לפניו ורואים רק את ראש הכרטיסיה.
class _StubTab extends OpenedTab {
  _StubTab(super.title);

  @override
  OpenedTab clone() => this;

  @override
  Map<String, dynamic> toJson() => {'type': '_StubTab', 'title': title};
}

class _TabPage extends StatefulWidget {
  const _TabPage({required this.tab, required this.color});

  final OpenedTab tab;
  final Color color;

  @override
  State<_TabPage> createState() => _TabPageState();
}

class _TabPageState extends State<_TabPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RepaintBoundary(
      key: TabContentBoundaries.instance.keyFor(widget.tab),
      child: ColoredBox(color: widget.color),
    );
  }
}

void main() {
  const tabWidth = 100.0;
  const stripColor = Color(0xFFF2EBE0);
  const colors = [Color(0xFFFF0000), Color(0xFF00FF00), Color(0xFF0000FF)];

  setUp(TabContentBoundaries.instance.debugClear);

  Widget host({
    required List<OpenedTab> tabs,
    required PageController controller,
  }) => MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Column(
          children: [
            SizedBox(
              height: 40,
              width: tabs.length * tabWidth,
              child: ReadingTabStrip(
                stripColor: stripColor,
                tabs: tabs,
                widths: [for (final _ in tabs) tabWidth],
                onReorder: (_, _) {},
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
              child: RepaintBoundary(
                key: windowContentBoundaryKey,
                child: PageView(
                  controller: controller,
                  children: [
                    for (var i = 0; i < tabs.length; i++)
                      KeyedSubtree(
                        key: ObjectKey(tabs[i]),
                        child: _TabPage(tab: tabs[i], color: colors[i]),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// מתחילה גרירה וממתינה [frames] פעימות — בלי [runAsync], כדי שהבדיקה
  /// תמדוד בדיוק את מה שהמשתמש רואה בשניות הראשונות של הגרירה.
  Future<TestGesture> startDrag(
    WidgetTester tester,
    String from, {
    int frames = 3,
  }) async {
    final start = tester.getCenter(find.text(from));
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(start + const Offset(tabWidth * 1.5, 0));
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return gesture;
  }

  /// האם התצוגה הנגררת מציגה את תוכן הכרטיסיה ולא רק את ראשה.
  bool showsContent(WidgetTester tester) =>
      tester.widgetList<RawImage>(find.byType(RawImage)).isNotEmpty;

  testWidgets('התצוגה הנגררת מציגה תוכן כבר בפעימות הראשונות', (tester) async {
    final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
    final controller = PageController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(tabs: tabs, controller: controller));

    final gesture = await startDrag(tester, 'א');
    expect(
      showsContent(tester),
      isTrue,
      reason: 'התצוגה נשארה ראש-כרטיסיה בלבד בתחילת הגרירה',
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('גם כרטיסיה שאינה הפעילה מקבלת תוכן מיד', (tester) async {
    final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
    final controller = PageController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(tabs: tabs, controller: controller));

    controller.jumpToPage(1);
    await tester.pumpAndSettle();
    controller.jumpToPage(0);
    await tester.pumpAndSettle();

    final gesture = await startDrag(tester, 'ב');
    expect(showsContent(tester), isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('כרטיסיה שלא נפתחה מעולם מקבלת מוק ולא ראש כרטיסיה', (
    tester,
  ) async {
    final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
    final controller = PageController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(tabs: tabs, controller: controller));

    expect(
      TabContentBoundaries.instance.maybeKeyFor(tabs[2])?.currentContext,
      isNull,
    );

    final gesture = await startDrag(tester, 'ג');
    expect(showsContent(tester), isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
