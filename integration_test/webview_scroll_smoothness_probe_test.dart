// בדיקת מדידה לחלקות גלילת טאצ'פד ב-WebView2 אמיתי.
//
// הדף מקליט את מיקום הגלילה שלו בכל פריים (requestAnimationFrame +
// performance.now()), כך שהמדידה אינה תלויה ב-roundtrip של evaluateJavascript.
// מחוות הטאצ'פד מוזרקות ב-fork כזרם אירועי wheel עם gain של 1.5
// (ראו _panToWheelUnits ב-custom_platform_view.dart), והבדיקה נכשלת על
// רגרסיה במדדים:
//
//   ratio     — מרחק עמוד / (מרחק אצבע × gain), קרוב ל-1
//   stallPct  — אחוז פריימים ללא תזוזה באמצע גרירה (גבוה = מקרטע)
//   stdStep   — סטיית תקן של הצעדים ביחס לממוצע (גבוה = קופצני)
//   latencyMs — זמן מתחילת הקלט עד התזוזה הראשונה
//   מחוות B-E — מחוות קצרות/איטיות חייבות לגלול גם הן (אסור אזור מת;
//               זו הסיבה שמסלול מגע סינתטי נפסל — סף ~34px לכל מחווה)
//
// הרצה: flutter test integration_test/webview_scroll_smoothness_probe_test.dart -d windows
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
  <div style="height:40000px;background:linear-gradient(red,blue)">tall</div>
  <script>
    window.__samples = [];
    (function loop() {
      window.__samples.push([performance.now(), window.scrollY]);
      if (window.__samples.length < 3000) requestAnimationFrame(loop);
    })();
  </script>
</body>
</html>
''';

Future<num> _evalNum(InAppWebViewController c, String src) async =>
    (await c.evaluateJavascript(source: src)) as num? ?? 0;

/// ה-gain של מסלול הטאצ'פד ב-fork (ראו _panToWheelUnits): 120/80.
const double _kTrackpadGain = 1.5;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'trackpad scrolling tracks the fingers smoothly (touch-drag path)',
    (tester) async {
      final dataDir = await Directory.systemTemp.createTemp(
        'otzaria_scroll_probe',
      );
      final environment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(userDataFolder: dataDir.path),
      );

      final controllerCompleter = Completer<InAppWebViewController>();
      final loadedCompleter = Completer<void>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InAppWebView(
              webViewEnvironment: environment,
              initialData: InAppWebViewInitialData(data: _tallPageHtml),
              onWebViewCreated: controllerCompleter.complete,
              onLoadStop: (controller, url) {
                if (!loadedCompleter.isCompleted) loadedCompleter.complete();
              },
            ),
          ),
        ),
      );

      final controller = await controllerCompleter.future.timeout(
        const Duration(seconds: 30),
      );
      await loadedCompleter.future.timeout(const Duration(seconds: 30));
      await Future<void>.delayed(const Duration(seconds: 2));
      await tester.pump();

      final center = tester.getCenter(find.byType(InAppWebView));
      final mouse = TestPointer(2, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(center));
      await tester.pump();

      final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
      var fingerY = 0.0;
      var fakeT = 0;
      Future<void> sendPan(double step) async {
        fingerY -= step;
        fakeT += 16;
        await tester.sendEventToBinding(
          trackpad.panZoomUpdate(
            center,
            pan: Offset(0, fingerY),
            timeStamp: Duration(milliseconds: fakeT),
          ),
        );
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }

      // --- מחווה 1: גרירה יציבה (90×4px) עם האטה בסוף (ללא fling) ---
      final inputStartT = await _evalNum(
        controller,
        'performance.now()',
      );
      await tester.sendEventToBinding(
        trackpad.panZoomStart(center, timeStamp: Duration.zero),
      );
      for (var i = 0; i < 90; i++) {
        await sendPan(4);
      }
      for (final s in [3.0, 2.0, 1.5, 1.0, 0.5, 0.5, 0.25, 0.25]) {
        await sendPan(s);
      }
      await tester.sendEventToBinding(
        trackpad.panZoomEnd(timeStamp: Duration(milliseconds: fakeT + 16)),
      );
      await tester.pump();
      final releaseT = await _evalNum(controller, 'performance.now()');
      final firstFinger = -fingerY;

      // נותנים לכל זנב להסתיים.
      await Future<void>.delayed(const Duration(seconds: 3));
      final scrollAfterDrag = (await _evalNum(
        controller,
        'window.scrollY',
      )).toDouble();

      // --- מחוות אפיון: כמה נבלע לפי גודל/מהירות המחווה ---
      // לכל מחווה: שולחים, ממתינים להתייצבות, ומודדים כמה הדף זז בפועל.
      Future<double> runGesture(String name, double step, int count) async {
        final before = (await _evalNum(
          controller,
          'window.scrollY',
        )).toDouble();
        fingerY = 0;
        fakeT += 1000;
        await tester.sendEventToBinding(
          trackpad.panZoomStart(
            center,
            timeStamp: Duration(milliseconds: fakeT),
          ),
        );
        for (var i = 0; i < count; i++) {
          await sendPan(step);
        }
        await tester.sendEventToBinding(
          trackpad.panZoomEnd(timeStamp: Duration(milliseconds: fakeT + 16)),
        );
        await tester.pump();
        await Future<void>.delayed(const Duration(seconds: 2));
        final after = (await _evalNum(controller, 'window.scrollY')).toDouble();
        final moved = after - before;
        // ignore: avoid_print
        print(
          'PROBE gesture $name: finger=${(step * count).toStringAsFixed(0)}px '
          'page=${moved.toStringAsFixed(1)}px '
          'lost=${(step * count - moved).toStringAsFixed(1)}px',
        );
        return moved;
      }

      // B: בינונית-מהירה, C: איטית, D: מיקרו-מהירה, E: איטית מאוד וקצרה.
      final movedB = await runGesture('B(40px@250px/s)', 4, 10);
      final movedC = await runGesture('C(30px@62px/s)', 1, 30);
      final movedD = await runGesture('D(12px@190px/s)', 3, 4);
      final movedE = await runGesture('E(8px@31px/s)', 0.5, 16);

      // --- קריאת דגימות וניתוח המחווה הראשונה ---
      final raw = await controller.evaluateJavascript(
        source: 'JSON.stringify(window.__samples)',
      );
      final samples = (jsonDecode(raw as String) as List)
          .map((e) => [(e[0] as num).toDouble(), (e[1] as num).toDouble()])
          .toList();

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      try {
        await environment.dispose();
      } catch (_) {}
      // ניקוי תיקיית ה-temp; הדפדפן משחרר את הקבצים אסינכרונית.
      await Future<void>.delayed(const Duration(seconds: 1));
      try {
        await dataDir.delete(recursive: true);
      } catch (_) {}

      final moving = samples.where((s) => s[1] > 0).toList();
      expect(moving, isNotEmpty, reason: 'גרירת טאצ\'פד חייבת לגלול את הדף');
      final firstMoveT = moving.first[0];
      final dragEnd = releaseT.toDouble();
      final steadyStart = firstMoveT + (dragEnd - firstMoveT) * 0.2;
      final steadyEnd = firstMoveT + (dragEnd - firstMoveT) * 0.8;
      final steps = <double>[];
      for (var i = 1; i < samples.length; i++) {
        final t = samples[i][0];
        if (t >= steadyStart && t <= steadyEnd) {
          steps.add(samples[i][1] - samples[i - 1][1]);
        }
      }
      final meanStep = steps.reduce((a, b) => a + b) / steps.length;
      final variance =
          steps
              .map((s) => (s - meanStep) * (s - meanStep))
              .reduce(
                (a, b) => a + b,
              ) /
          steps.length;
      final stdStep = math.sqrt(variance);
      final stallPct = steps.where((s) => s == 0).length * 100.0 / steps.length;
      final latencyMs = firstMoveT - inputStartT.toDouble();
      // מנרמלים את היחס ל-gain: 1.0 = הדף זז בדיוק אצבע × gain.
      final ratio = scrollAfterDrag / (firstFinger * _kTrackpadGain);

      // ignore: avoid_print
      print(
        'PROBE wheel-path: ratio=${ratio.toStringAsFixed(2)} '
        '(finger=${firstFinger.toStringAsFixed(0)}px '
        'page=${scrollAfterDrag.toStringAsFixed(0)}px gain=$_kTrackpadGain) '
        'meanStep=${meanStep.toStringAsFixed(2)}px '
        'stdStep=${stdStep.toStringAsFixed(2)}px '
        'stallPct=${stallPct.toStringAsFixed(0)}% '
        'latency=${latencyMs.toStringAsFixed(0)}ms',
      );

      // ספי איכות — נכשלים על רגרסיה, לא רק על "זז בכלל".
      expect(
        ratio,
        greaterThan(0.85),
        reason: 'הדף חייב לעקוב אחרי האצבעות (כפול ה-gain)',
      );
      expect(
        ratio,
        lessThan(1.15),
        reason: 'הדף לא אמור לגלול מעבר לאצבעות (כפול ה-gain)',
      );
      expect(
        stallPct,
        lessThan(15),
        reason: 'גלילה מקרטעת — יותר מדי פריימים ללא תזוזה',
      );
      expect(
        stdStep / meanStep,
        lessThan(0.6),
        reason: 'גלילה קופצנית — פיזור צעדים גדול ביחס לממוצע',
      );
      expect(
        latencyMs,
        lessThan(150),
        reason: 'השהיה גדולה מדי מתחילת הקלט עד תזוזה',
      );
      // אסור אזור מת: גם מחוות קצרות ואיטיות חייבות לגלול את רוב דרכן.
      expect(
        movedB,
        greaterThan(40 * _kTrackpadGain * 0.7),
        reason: 'מחווה בינונית (40px) חייבת לגלול את רוב הדרך',
      );
      expect(
        movedC,
        greaterThan(30 * _kTrackpadGain * 0.7),
        reason: 'מחווה איטית (30px) חייבת לגלול את רוב הדרך',
      );
      expect(
        movedD,
        greaterThan(12 * _kTrackpadGain * 0.6),
        reason: 'מיקרו-מחווה מהירה (12px) חייבת לגלול',
      );
      expect(
        movedE,
        greaterThan(8 * _kTrackpadGain * 0.5),
        reason: 'מיקרו-מחווה איטית (8px) חייבת לגלול',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
