// בדיקות widget למסך ההכוונה שמופיע כש-WebView2 Runtime אינו מותקן.
//
// המסך מציג למשתמש הסבר, כפתור להורדת WebView2, וכפתור "בדוק שוב"
// שמריץ מחדש את בדיקת הזמינות (callback onRetry).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/view/plugin_webview2_missing_view.dart';

void main() {
  group('PluginWebView2MissingView', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('לחיצה על "בדוק שוב" מפעילה את onRetry', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        wrap(PluginWebView2MissingView(onRetry: () => retried = true)),
      );

      await tester.tap(find.text('בדוק שוב'));
      await tester.pump();

      expect(retried, isTrue);
    });

    // המסך צורך ~460px; בחלון נמוך בלי גלילה כפתור ההורדה יוצא מחוץ למסך,
    // ומשתמש בלי WebView2 נתקע בלי דרך להתקין אותו.
    for (final size in const [Size(900, 400), Size(640, 360)]) {
      testWidgets(
        'כפתור ההורדה נגיש ב-${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          tester.view.devicePixelRatio = 1.0;
          tester.view.physicalSize = size;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await tester.pumpWidget(
            wrap(PluginWebView2MissingView(onRetry: () {})),
          );
          expect(tester.takeException(), isNull);

          await tester.ensureVisible(find.text('הורד WebView2'));
          expect(find.text('הורד WebView2').hitTestable(), findsOneWidget);
        },
      );
    }

    testWidgets('בחלון מרווח המסך אינו גליל', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(wrap(PluginWebView2MissingView(onRetry: () {})));

      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      expect(position.maxScrollExtent, 0);
    });
  });
}
