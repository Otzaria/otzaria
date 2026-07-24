// טסט WebView2 אמיתי לגלילת טאצ'פד תת-פיקסלית, כי הבאג היה במסלול Windows.
// הרצה: flutter test integration_test/webview_touchpad_scroll_test.dart -d windows
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const String _tallPageHtml = '''
<!DOCTYPE html>
<html>
<head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
<body style="margin:0">
  <div style="height:20000px;background:linear-gradient(red,blue)">tall</div>
</body>
</html>
''';

Future<double> _scrollY(InAppWebViewController controller) async {
  final result = await controller.evaluateJavascript(
    source: 'window.scrollY',
  );
  return (result as num?)?.toDouble() ?? 0;
}

/// ממתין עד ש-scrollY עובר את [threshold], או שפג הזמן הקצוב.
Future<double> _waitForScroll(
  InAppWebViewController controller,
  double threshold, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  double value = 0;
  while (DateTime.now().isBefore(deadline)) {
    value = await _scrollY(controller);
    if (value > threshold) {
      return value;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return value;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'sub-pixel trackpad pan deltas scroll a real WebView2 page',
    (tester) async {
      final controllerCompleter = Completer<InAppWebViewController>();
      final loadedCompleter = Completer<void>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InAppWebView(
              initialData: InAppWebViewInitialData(data: _tallPageHtml),
              onWebViewCreated: (controller) {
                controllerCompleter.complete(controller);
              },
              onLoadStop: (controller, url) {
                if (!loadedCompleter.isCompleted) {
                  loadedCompleter.complete();
                }
              },
            ),
          ),
        ),
      );

      final controller = await controllerCompleter.future.timeout(
        const Duration(seconds: 30),
      );
      await loadedCompleter.future.timeout(const Duration(seconds: 30));
      // מאפשרים ל-compositor ולדף להתייצב.
      await Future<void>.delayed(const Duration(seconds: 2));
      await tester.pump();

      expect(await _scrollY(controller), 0);

      final center = tester.getCenter(find.byType(InAppWebView));

      // מציבים את הסמן הווירטואלי מעל הדף (כמו משתמש שמרחף עם העכבר
      // לפני שהוא גולל בטאצ'פד).
      final mouse = TestPointer(2, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(center));
      await tester.pump();

      // 240 עדכוני pan של 0.5px משחזרים גלילה איטית עם דלתות תת-פיקסליות.
      // חותמות זמן של 16ms משאירות את המחווה מתחת לסף fling.
      final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
      await tester.sendEventToBinding(
        trackpad.panZoomStart(center, timeStamp: Duration.zero),
      );
      for (var i = 1; i <= 240; i++) {
        await tester.sendEventToBinding(
          trackpad.panZoomUpdate(
            center,
            pan: Offset(0, -0.5 * i),
            timeStamp: Duration(milliseconds: 16 * i),
          ),
        );
        if (i % 40 == 0) {
          await tester.pump();
        }
      }
      await tester.sendEventToBinding(
        trackpad.panZoomEnd(timeStamp: const Duration(milliseconds: 3856)),
      );
      await tester.pump();

      final afterPan = await _waitForScroll(controller, 0);
      expect(
        afterPan,
        greaterThan(0),
        reason: 'גרירת טאצ\'פד תת-פיקסלית חייבת לגלול את הדף',
      );
      // מעקב: תנועת אצבע של 120px אמורה לגלול בערך 120 × gain (1.5) = 180px.
      await Future<void>.delayed(const Duration(seconds: 1));
      final dragDistance = await _scrollY(controller);
      // ignore: avoid_print
      print(
        'TOUCHPAD-TRACKING: finger=120px page=${dragDistance}px '
        'ratio=${(dragDistance / 120).toStringAsFixed(2)} (gain=1.5)',
      );
      expect(dragDistance, greaterThan(150));
      expect(dragDistance, lessThan(220));

      // מחווה מהירה אמורה להמשיך לגלול אחרי panZoomEnd —
      // האינרציה הסינתטית של ה-fork.
      final beforeFling = await _scrollY(controller);
      await tester.sendEventToBinding(
        trackpad.panZoomStart(center, timeStamp: const Duration(seconds: 10)),
      );
      for (var i = 1; i <= 8; i++) {
        await tester.sendEventToBinding(
          trackpad.panZoomUpdate(
            center,
            pan: Offset(0, -10.0 * i),
            timeStamp: Duration(milliseconds: 10000 + 8 * i),
          ),
        );
        await tester.pump();
      }
      await tester.sendEventToBinding(
        trackpad.panZoomEnd(timeStamp: const Duration(milliseconds: 10064)),
      );
      await tester.pump();
      // קוראים את המיקום מיד אחרי ההרמה, ואז נותנים לאינרציה לרוץ.
      final atRelease = await _scrollY(controller);
      expect(atRelease, greaterThan(beforeFling));
      final afterGlide = await _waitForScroll(
        controller,
        atRelease + 30,
        timeout: const Duration(seconds: 5),
      );
      // ignore: avoid_print
      print(
        'TOUCHPAD-INERTIA: atRelease=${atRelease}px '
        'afterGlide=${afterGlide}px',
      );
      expect(
        afterGlide,
        greaterThan(atRelease + 30),
        reason:
            'אחרי הרמת האצבעות במחווה מהירה הדף חייב להמשיך לגלוש '
            '(אינרציה) ולא לעצור במקום',
      );

      // וידוא שגלגלת עכבר רגילה עדיין עובדת (לא נשברה רגרסיה).
      await Future<void>.delayed(const Duration(seconds: 1));
      final beforeWheel = await _scrollY(controller);
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 240)));
      await tester.pump();
      final afterWheel = await _waitForScroll(controller, beforeWheel);
      expect(
        afterWheel,
        greaterThan(beforeWheel),
        reason: 'גלילת גלגלת עכבר חייבת להמשיך לעבוד אחרי התיקון',
      );
    },
    // טעינת WebView2 אמיתי עלולה להיות איטית בריצה ראשונה.
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
