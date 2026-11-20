import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_sdk_scripts.dart';
import 'package:otzaria/plugins/view/plugin_tab_page.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/view/tab_swipe_detector.dart';

import '../../test_helpers/stub_tabs_bloc.dart';

/// מריץ את ה-stub ב-node עם DOM מזויף, משגר pointermove מעל כל נתיב ומחזיר
/// את הדיווחים שהגיעו ל-Flutter. `null` = אין node.
Future<List<Object?>?> runScrollReports(
  List<List<Map<String, Object>>> paths,
) async {
  ProcessResult? probe;
  try {
    probe = await Process.run('node', ['--version']);
  } on ProcessException {
    probe = null;
  }
  if (probe == null || probe.exitCode != 0) return null;
  final harness =
      '''
var reports = [];
var target = new EventTarget();
var document = { scrollingElement: null, body: null };
var window = {
  addEventListener: function (type, cb, options) {
    target.addEventListener(type, cb);
  },
  removeEventListener: function () {},
  dispatchEvent: function () {},
  flutter_inappwebview: {
    callHandler: function (name, arg) {
      if (name === 'otzaria_scrolls_x') reports.push(arg);
    }
  }
};
function getComputedStyle(el) { return { overflowX: el.overflowX }; }
var CustomEvent = function () {};
$pluginSdkStubScript
${jsonEncode(paths)}.forEach(function (path) {
  path.forEach(function (el) {
    if (el.root) document.scrollingElement = el;
  });
  var e = new Event('pointermove');
  e.composedPath = function () { return path; };
  target.dispatchEvent(e);
});
console.log(JSON.stringify(reports));
''';
  final result = await Process.run('node', ['-e', harness]);
  if (result.exitCode != 0) fail('node failed: ${result.stderr}');
  return jsonDecode(result.stdout.toString().trim()) as List<Object?>;
}

/// issue #3640: גלילה אופקית בתפריט של תוסף גררה גם את הכרטיסייה כולה.
///
/// ה-WebView בדסקטופ מעביר את הגלילה לדף דרך Listener ואינו מתחרה בזירת
/// המחוות, ולכן ה-[Listener] כאן מחליף אותו נאמנה. הדף מדווח מראש (בריחוף
/// ובלחיצה) אם מתחת לסמן יש אלמנט שנגלל לרוחב.
void main() {
  late PageController controller;
  late List<Offset> webViewPans;
  late int webViewTouchMoves;

  Future<void> pumpPluginTabs(
    WidgetTester tester, {
    required bool contentScrollsHorizontally,
  }) async {
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
                    contentScrollsHorizontally: () =>
                        contentScrollsHorizontally,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> trackpadSwipe(WidgetTester tester) async {
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
  }

  Future<void> touchSwipe(WidgetTester tester) async {
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
  }

  final desktop = TargetPlatformVariant({
    TargetPlatform.windows,
    TargetPlatform.linux,
  });

  testWidgets(
    'גלילה אופקית ב-trackpad בתוכן גולל של תוסף לא מעבירה כרטיסייה',
    (tester) async {
      await pumpPluginTabs(tester, contentScrollsHorizontally: true);
      await trackpadSwipe(tester);
      expect(controller.page, 1);
      expect(webViewPans, isNotEmpty);
    },
    variant: desktop,
  );

  testWidgets(
    'גרירה אופקית באצבע בתוכן גולל של תוסף לא מעבירה כרטיסייה',
    (tester) async {
      await pumpPluginTabs(tester, contentScrollsHorizontally: true);
      await touchSwipe(tester);
      expect(controller.page, 1);
      expect(webViewTouchMoves, greaterThan(0));
    },
    variant: desktop,
  );

  testWidgets(
    'החלקה מעל תוכן תוסף שאינו גולל לרוחב עדיין עוברת כרטיסייה',
    (tester) async {
      await pumpPluginTabs(tester, contentScrollsHorizontally: false);
      await trackpadSwipe(tester);
      expect(controller.page, 2);
    },
    variant: desktop,
  );

  test('הדף מדווח רק כשמתחת לסמן יש אלמנט שנגלל לרוחב', () async {
    Map<String, Object> el(
      int scrollWidth,
      int clientWidth,
      String overflowX, {
      bool root = false,
    }) => {
      'nodeType': 1,
      'scrollWidth': scrollWidth,
      'clientWidth': clientWidth,
      'overflowX': overflowX,
      'root': root,
    };
    final page = el(800, 800, 'visible', root: true);
    final reports = await runScrollReports([
      // תוכן סטטי.
      [el(100, 100, 'visible'), el(300, 300, 'auto'), page],
      // תפריט מקונן שנגלל לרוחב, מתחת לפריט שבו הסמן.
      [el(80, 80, 'visible'), el(900, 300, 'auto'), page],
      // אותו מצב — אין דיווח חוזר.
      [el(900, 300, 'scroll'), page],
      // תוכן שגולש אך חתוך (overflow-x: hidden) אינו נגלל.
      [el(900, 300, 'hidden'), page],
      // הדף כולו רחב מהחלון.
      [el(100, 100, 'visible'), el(1600, 800, 'visible', root: true)],
    ]);
    if (reports == null) {
      markTestSkipped('node אינו מותקן');
      return;
    }
    expect(reports, [true, false, true]);
  });
}
