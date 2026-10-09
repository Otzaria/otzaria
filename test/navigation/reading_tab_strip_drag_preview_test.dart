import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/tab_drag_preview.dart';
import 'package:otzaria/navigation/view/reading_tab_strip.dart';
import 'package:otzaria/tabs/models/tab.dart';

class _StubTab extends OpenedTab {
  _StubTab(super.title);

  @override
  OpenedTab clone() => this;

  @override
  Map<String, dynamic> toJson() => {'type': '_StubTab', 'title': title};
}

/// עמוד תוכן של כרטיסיה, בצבע משלו ומאחורי הגבול שהרצועה מצלמת.
///
/// ⚠️ `wantKeepAlive` הוא **תנאי הבדיקה** ולא נוחות: הוא מה שמשאיר כרטיסיה
/// שאינה על המסך בעץ עם שכבת הציור שלה, וזה כל מה שמאפשר לצלם אותה. כך זה
/// באמת ב-`reading_screen`, שם כל מסכי הכרטיסיות מסמנים אותו.
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

  /// רצועה מעל `PageView` של כרטיסיות — אותו מבנה שיש ב-`reading_screen`.
  Widget host({
    required List<OpenedTab> tabs,
    required PageController controller,
    required void Function(OpenedTab tab, TabWindowPreview preview) onSnapshot,
  }) {
    return MaterialApp(
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
                  onTabSnapshot: (tab, preview, _) => onSnapshot(tab, preview),
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
  }

  /// גוררת כרטיסיה הצדה ומחזירה את המוק שנוצר, או `null`.
  ///
  /// ⚠️ שרשרת הצילום עוברת במנוע שלוש פעמים (תוכן, ראש הכרטיסיה, הרכבה),
  /// ולכן `runAsync` בלולאה ולא פעם אחת: תחת `FakeAsync` ה-`Future`-ים של
  /// `toImage` אינם מתקדמים בלי חלון זמן אמיתי.
  Future<TabWindowPreview?> dragAside(
    WidgetTester tester,
    String from,
    List<TabWindowPreview> snapshots,
  ) async {
    final start = tester.getCenter(find.text(from));
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(start + const Offset(tabWidth * 1.5, 0));
    await tester.pump();
    for (var i = 0; i < 30 && snapshots.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    return snapshots.isEmpty ? null : snapshots.first;
  }

  /// הצבע במרכז **אזור התוכן** של המוק.
  ///
  /// המוק מורכב מראש הכרטיסיה מעל והתוכן מתחתיו, ולכן הדגימה מתחת לגובה
  /// הרצועה — אחרת היא הייתה קוראת את הכרטיסיה ולא את הספר.
  Future<Color> contentColour(WidgetTester tester, ui.Image image) async {
    // גובה רצועת הכרטיסיות במוק הוא ההפרש בין המוק לאזור התוכן שמתחתיו,
    // ואת יחסו לגובה הכולל אפשר לגזור רק מהמידות: הרצועה 40 מתוך 600
    // לוגיים, כלומר הדגימה בשני שלישים למטה נמצאת בבטחה בתוך התוכן.
    late Color colour;
    await tester.runAsync(() async {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final x = image.width ~/ 2;
      final y = (image.height * 2) ~/ 3;
      final offset = (y * image.width + x) * 4;
      colour = Color.fromARGB(
        data!.getUint8(offset + 3),
        data.getUint8(offset),
        data.getUint8(offset + 1),
        data.getUint8(offset + 2),
      );
    });
    return colour;
  }

  group('מוק הגרירה מציג את תוכן הכרטיסיה הנגררת', () {
    testWidgets('כרטיסיה שאינה מוצגת מצטלמת בתוכן שלה, לא של הפעילה', (
      tester,
    ) async {
      final snapshots = <TabWindowPreview>[];
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      final controller = PageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          tabs: tabs,
          controller: controller,
          onSnapshot: (tab, preview) => snapshots.add(preview),
        ),
      );

      // 'ב' מוצגת ואז נעזבת — מכאן היא בדלי ה-keep-alive, בלי להיות פעילה.
      controller.jumpToPage(1);
      await tester.pumpAndSettle();
      controller.jumpToPage(0);
      await tester.pumpAndSettle();

      final preview = await dragAside(tester, 'ב', snapshots);
      expect(preview, isNotNull, reason: 'גרירת כרטיסיה שאינה פעילה לא צילמה');
      addTearDown(preview!.image.dispose);

      // ⚠️ זה הליבה: ירוק = התוכן של 'ב'. אדום היה התוכן של 'א' הפעילה,
      // כלומר בדיוק הבאג — "גררתי כרטיסיה וראיתי מתחתיה ספר אחר".
      expect(await contentColour(tester, preview.image), colors[1]);
    });

    testWidgets('הכרטיסיה הפעילה מצטלמת בתוכן שלה', (tester) async {
      final snapshots = <TabWindowPreview>[];
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      final controller = PageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          tabs: tabs,
          controller: controller,
          onSnapshot: (tab, preview) => snapshots.add(preview),
        ),
      );

      final preview = await dragAside(tester, 'א', snapshots);
      expect(preview, isNotNull);
      addTearDown(preview!.image.dispose);
      expect(await contentColour(tester, preview.image), colors[0]);
    });

    testWidgets('כרטיסיה שלא נפתחה מעולם מקבלת מוק חלון ולא ראש כרטיסיה', (
      tester,
    ) async {
      final snapshots = <TabWindowPreview>[];
      final tabs = [_StubTab('א'), _StubTab('ב'), _StubTab('ג')];
      final controller = PageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          tabs: tabs,
          controller: controller,
          onSnapshot: (tab, preview) => snapshots.add(preview),
        ),
      );

      // 'ג' לא הוצגה מעולם, ולכן אין לה תת-עץ בכלל — אין מה לצלם.
      expect(
        TabContentBoundaries.instance.maybeKeyFor(tabs[2])?.currentContext,
        isNull,
      );

      final preview = await dragAside(tester, 'ג', snapshots);
      expect(
        preview,
        isNotNull,
        reason: 'כרטיסיה בלי צילום נשארה בלי מוק במקום לקבל חלון ריק',
      );
      addTearDown(preview!.image.dispose);

      // רקע הרצועה, ולא תוכן של כרטיסיה אחרת: זה המוק שנבנה מחדש.
      expect(await contentColour(tester, preview.image), stripColor);
    });
  });
}
