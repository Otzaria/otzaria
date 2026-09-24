import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_tab_page.dart';

void main() {
  group('buildPluginTabWebViewSettings', () {
    test('זום חסום — צביטת מגע ו-Ctrl+גלגלת (issue #883)', () {
      final settings = buildPluginTabWebViewSettings(isDevelopment: false);
      expect(settings.supportZoom, isFalse);
      expect(settings.pinchZoomEnabled, isFalse);
    });

    test('הגדרות אבטחה ותצוגה נשמרות', () {
      final settings = buildPluginTabWebViewSettings(isDevelopment: false);
      expect(settings.allowFileAccessFromFileURLs, isFalse);
      expect(settings.allowUniversalAccessFromFileURLs, isFalse);
      expect(settings.useShouldOverrideUrlLoading, isTrue);
      expect(settings.useShouldInterceptRequest, isTrue);
      expect(settings.statusBarEnabled, isFalse);
      expect(settings.cacheEnabled, isTrue);
    });

    test('מצב פיתוח — ללא קאש ועם inspect', () {
      final settings = buildPluginTabWebViewSettings(isDevelopment: true);
      expect(settings.cacheEnabled, isFalse);
      expect(settings.isInspectable, isTrue);
      expect(settings.supportZoom, isFalse);
      expect(settings.pinchZoomEnabled, isFalse);
    });
  });

  group('pluginTabWebViewGestureRecognizers (פורום 2491)', () {
    // מדמה את המסך במובייל: WebView (platform view) בתוך PageView של
    // הטאבים, שיש בו שני דפים ולכן recognizer אופקי פעיל.
    Future<_RecordingPlatformViewController> pumpWebViewInTabs(
      WidgetTester tester,
      Set<Factory<OneSequenceGestureRecognizer>>? recognizers, {
      PageController? pageController,
    }) async {
      final controller = _RecordingPlatformViewController();
      await tester.pumpWidget(
        MaterialApp(
          home: PageView(
            controller: pageController,
            children: [
              PlatformViewSurface(
                controller: controller,
                hitTestBehavior: PlatformViewHitTestBehavior.opaque,
                gestureRecognizers:
                    recognizers ??
                    const <Factory<OneSequenceGestureRecognizer>>{},
              ),
              const SizedBox.expand(),
            ],
          ),
        ),
      );
      return controller;
    }

    Future<int> movesDeliveredBeforeRelease(
      WidgetTester tester,
      _RecordingPlatformViewController controller,
    ) async {
      final gesture = await tester.startGesture(
        const Offset(400, 400),
        kind: PointerDeviceKind.touch,
      );
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, -20));
      }
      final moves = controller.events.whereType<PointerMoveEvent>().length;
      await gesture.up();
      return moves;
    }

    testWidgets('בלי recognizer — המגע מעוכב עד השחרור (הבאג)', (
      tester,
    ) async {
      final controller = await pumpWebViewInTabs(tester, null);
      expect(await movesDeliveredBeforeRelease(tester, controller), 0);
    });

    testWidgets('במובייל — גרירה אנכית מגיעה לתוסף בזמן אמת', (tester) async {
      final controller = await pumpWebViewInTabs(
        tester,
        pluginTabWebViewGestureRecognizers(isTouchPlatform: true),
      );
      expect(await movesDeliveredBeforeRelease(tester, controller), 10);
    });

    testWidgets('במובייל — החלקה אופקית עדיין מחליפה טאב', (tester) async {
      final pageController = PageController();
      addTearDown(pageController.dispose);
      await pumpWebViewInTabs(
        tester,
        pluginTabWebViewGestureRecognizers(isTouchPlatform: true),
        pageController: pageController,
      );
      await tester.fling(
        find.byType(PageView),
        const Offset(-300, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(pageController.page, 1);
    });

    test('בדסקטופ — ללא שינוי', () {
      expect(
        pluginTabWebViewGestureRecognizers(isTouchPlatform: false),
        isNull,
      );
    });
  });
}

class _RecordingPlatformViewController extends PlatformViewController {
  final events = <PointerEvent>[];

  @override
  int get viewId => 0;

  @override
  Future<void> dispatchPointerEvent(PointerEvent event) async {
    events.add(event);
  }

  @override
  Future<void> clearFocus() async {}

  @override
  Future<void> dispose() async {}
}
