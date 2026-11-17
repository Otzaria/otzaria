import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/view/tab_visuals.dart';

void main() {
  // בגופן הבדיקות כל תו רוחבו כגודל הגופן: 10 תווים × 10 = 100px.
  const title = 'אבגדהוזחטי';

  Future<void> pumpTitle(WidgetTester tester, double width) =>
      tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: DefaultTextStyle(
            style: const TextStyle(fontSize: 10),
            child: Center(
              child: SizedBox(
                width: width,
                child: Builder(
                  builder: (context) => buildFadedTabTitle(context, title),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('כותרת שנכנסת במלואה אינה נדהית גם כשהיא מגיעה לקצה (#1933)', (
    tester,
  ) async {
    await pumpTitle(tester, 100);
    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('כותרת שנחתכת נדהית בקצה הסוף', (tester) async {
    await pumpTitle(tester, 60);
    expect(find.byType(ShaderMask), findsOneWidget);
  });

  for (final direction in TextDirection.values) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('תחילת הכותרת והמיקום נשמרים ב־$direction ×$scale', (
        tester,
      ) async {
        const location = 'דף א';
        const bookTitle = 'אבגדהוזחטי אבגדהוזחטי';
        const fullTitle = '$bookTitle, $location';
        const titleBoxKey = ValueKey('title-box');
        for (final width in [0.0, 10.0, 35.0, 60.0, 100.0, 180.0, 360.0]) {
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Directionality(
                  textDirection: direction,
                  child: DefaultTextStyle(
                    style: const TextStyle(fontSize: 10),
                    child: Center(
                      child: SizedBox(
                        key: titleBoxKey,
                        width: width,
                        height: 30,
                        child: Builder(
                          builder: (context) => TabTitleTooltip(
                            title: fullTitle,
                            message: fullTitle,
                            child: buildFadedTabTitle(
                              context,
                              fullTitle,
                              location: location,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          if (width == 360) {
            expect(find.text(fullTitle), findsOneWidget);
            expect(find.byType(ShaderMask), findsNothing);
          } else {
            expect(find.byTooltip(fullTitle), findsOneWidget);
          }
          if (width == 180) {
            final book = tester.getRect(find.text(bookTitle));
            final suffix = tester.getRect(find.text(', $location'));
            final box = tester.getRect(find.byKey(titleBoxKey));
            expect(suffix.width, lessThan(box.width));
            expect(
              direction == TextDirection.rtl ? book.right : book.left,
              closeTo(
                direction == TextDirection.rtl ? box.right : box.left,
                0.01,
              ),
            );
            expect(
              direction == TextDirection.rtl ? suffix.left : suffix.right,
              closeTo(
                direction == TextDirection.rtl ? box.left : box.right,
                0.01,
              ),
            );
            final mask = tester.widget<ShaderMask>(find.byType(ShaderMask));
            final alphas = await tester.runAsync(() async {
              const rect = Rect.fromLTWH(0, 0, 100, 1);
              final recorder = ui.PictureRecorder();
              Canvas(
                recorder,
              ).drawRect(rect, Paint()..shader = mask.shaderCallback(rect));
              final picture = recorder.endRecording();
              final image = await picture.toImage(100, 1);
              final pixels = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              final result = [pixels.getUint8(3), pixels.getUint8(99 * 4 + 3)];
              image.dispose();
              picture.dispose();
              return result;
            });
            // ב־RTL נדהה הקצה השמאלי; ב־LTR הקצה הימני.
            expect(
              alphas![direction == TextDirection.rtl ? 0 : 1],
              lessThan(20),
            );
            expect(alphas[direction == TextDirection.rtl ? 1 : 0], 255);
          }
          if (width <= 35) {
            expect(find.text(location), findsOneWidget);
            expect(find.text(bookTitle), findsNothing);
          }
        }
      });
    }
  }
}
