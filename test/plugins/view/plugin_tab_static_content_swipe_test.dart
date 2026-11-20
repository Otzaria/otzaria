import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_tab_page.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/view/tab_swipe_detector.dart';

import '../../test_helpers/stub_tabs_bloc.dart';

/// החלקה אופקית מעל תוכן סטטי של תוסף בדסקטופ עוברת כרטיסייה, כמו מעל כל
/// תוכן אחר. התוסף אינו יכול לגלול כאן לרוחב, ולכן אין מי שיצרוך את המחווה.
///
/// ה-WebView ב-Windows וב-Linux מקבל את הקלט דרך [Listener] ואינו עונה
/// ל-Flutter אם הדף השתמש בו — ה-[Listener] כאן מחליף אותו נאמנה.
void main() {
  late PageController controller;
  late int webViewEvents;

  Future<void> pumpStaticPluginTabs(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    webViewEvents = 0;
    controller = PageController(initialPage: 1);
    addTearDown(controller.dispose);
    final tabs = [
      for (final id in ['a', 'b', 'c']) ToolTab(toolId: id, title: id),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<TabsBloc>.value(
          value: StubTabsBloc(TabsState(tabs: tabs, currentTabIndex: 1)),
          child: TabSwipeDetector(
            controller: controller,
            onActiveChanged: (_) {},
            child: PageView(
              controller: controller,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < 3; i++)
                  buildPluginTabBody(
                    webView: Listener(
                      onPointerPanZoomUpdate: (_) => webViewEvents++,
                      onPointerMove: (_) => webViewEvents++,
                      child: const ColoredBox(color: Colors.white),
                    ),
                    loading: false,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final desktop = TargetPlatformVariant({
    TargetPlatform.windows,
    TargetPlatform.linux,
  });

  testWidgets('החלקה ב-trackpad מעל תוכן סטטי של תוסף עוברת כרטיסייה', (
    tester,
  ) async {
    await pumpStaticPluginTabs(tester);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    const center = Offset(600, 400);
    await gesture.panZoomStart(center, timeStamp: Duration.zero);
    for (var i = 1; i <= 8; i++) {
      await gesture.panZoomUpdate(
        center,
        pan: Offset(-30.0 * i, 0),
        timeStamp: Duration(milliseconds: 20 * i),
      );
      await tester.pump();
    }
    await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 180));
    await tester.pumpAndSettle();
    expect(controller.page, 2);
    expect(webViewEvents, greaterThan(0));
  }, variant: desktop);

  testWidgets('החלקה באצבע מעל תוכן סטטי של תוסף עוברת כרטיסייה', (
    tester,
  ) async {
    await pumpStaticPluginTabs(tester);
    final gesture = await tester.startGesture(
      const Offset(600, 400),
      kind: PointerDeviceKind.touch,
    );
    for (var i = 1; i <= 8; i++) {
      await gesture.moveBy(
        const Offset(-30, 0),
        timeStamp: Duration(milliseconds: 20 * i),
      );
      await tester.pump();
    }
    await gesture.up(timeStamp: const Duration(milliseconds: 180));
    await tester.pumpAndSettle();
    expect(controller.page, 2);
    expect(webViewEvents, greaterThan(0));
  }, variant: desktop);
}
