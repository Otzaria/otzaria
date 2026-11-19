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

/// issue #3640: גלילה אופקית בתפריט של תוסף גררה גם את הכרטיסייה כולה.
///
/// ה-WebView בדסקטופ מעביר את הגלילה לדף דרך Listener ואינו מתחרה בזירת
/// המחוות, ולכן ה-[Listener] כאן מחליף אותו נאמנה.
void main() {
  late PageController controller;
  late List<Offset> webViewPans;
  late int webViewTouchMoves;

  Future<void> pumpPluginTabs(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    webViewPans = [];
    webViewTouchMoves = 0;
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
                      onPointerPanZoomUpdate: (e) => webViewPans.add(e.pan),
                      onPointerMove: (_) => webViewTouchMoves++,
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

  testWidgets(
    'גלילה אופקית ב-trackpad מעל תוסף גוללת את התוסף ולא את הכרטיסייה',
    (tester) async {
      await pumpPluginTabs(tester);
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
        expect(controller.page, 1);
      }
      await gesture.panZoomEnd(timeStamp: const Duration(milliseconds: 180));
      await tester.pumpAndSettle();
      expect(controller.page, 1);
      expect(webViewPans, isNotEmpty);
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    'גרירה אופקית באצבע מעל תוסף גוללת את התוסף ולא את הכרטיסייה',
    (tester) async {
      await pumpPluginTabs(tester);
      final gesture = await tester.startGesture(
        const Offset(600, 400),
        kind: PointerDeviceKind.touch,
      );
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(-30, 0));
        await tester.pump();
        expect(controller.page, 1);
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.page, 1);
      expect(webViewTouchMoves, greaterThan(0));
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    'במובייל ה-PageView מחליק בעצמו, ועטיפת התוסף לא נוספת',
    (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: buildPluginTabBody(webView: const SizedBox(), loading: false),
        ),
      );
      expect(find.byType(RawGestureDetector), findsNothing);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}
