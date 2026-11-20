// "צפיפות ממשק" אוטומטית: במחשב מצומצמת כשהחלון צר (מתחת ל-600) או נמוך
// (מתחת ל-480), ובכל חלון לפי הגודל שלו בלבד, גם כשכמה חלונות פתוחים.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/device_chrome.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/theme/app_density.dart';
import 'package:otzaria/theme/app_theme_data.dart';

import '../test_helpers/second_test_view.dart';

void main() {
  setUp(() => DeviceChrome.debugMobileOverride = false);
  tearDown(() => DeviceChrome.debugMobileOverride = null);

  group('במחשב: חלון צר או נמוך קטן', () {
    test('צר וגבוה (חלון מוצמד לחצי מסך, מסך אנכי) קטן', () {
      for (final size in const [
        Size(500, 900),
        Size(512, 600),
        Size(599, 1000),
      ]) {
        expect(AppDensity.isSmallWindow(size), isTrue, reason: '$size');
      }
    });

    test('רחב מספיק וגבוה מספיק אינו קטן', () {
      for (final size in const [
        Size(1000, 700),
        Size(600, 480),
        Size(1093, 566),
        Size(960, 1080),
      ]) {
        expect(AppDensity.isSmallWindow(size), isFalse, reason: '$size');
      }
    });

    test('נמוך מ-480 קטן גם כשהוא רחב', () {
      for (final size in const [Size(1200, 450), Size(1920, 479)]) {
        expect(AppDensity.isSmallWindow(size), isTrue, reason: '$size');
      }
    });
  });

  /// ערכת נושא של חלון אחד, כמו ב-App: הצפיפות לפי גודל אותו חלון בלבד.
  Widget window(void Function(AppDensity) onDensity) => SmallWindowBuilder(
    builder: (isSmall) => Theme(
      data: AppThemeData.light(
        AppThemeData.createColorScheme(Colors.brown, Brightness.light),
        compactMenuMode: SettingsState.initial().compactMenuModeFor(
          isSmallWindow: isSmall,
        ),
      ),
      child: Builder(
        builder: (context) {
          onDensity(AppDensity.of(context));
          return const SizedBox();
        },
      ),
    ),
  );

  testWidgets('שני חלונות: גדול רגיל וקטן מצומצם בו-זמנית', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    final second = SecondTestView(tester.view)
      ..physicalSize = const Size(450, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    AppDensity? big;
    AppDensity? small;
    await tester.pumpWidget(
      wrapWithView: false,
      ViewCollection(
        views: [
          View(view: tester.view, child: window((d) => big = d)),
          View(view: second, child: window((d) => small = d)),
        ],
      ),
    );
    expect(big, AppDensity.regular);
    expect(small, AppDensity.compact);

    // הקטנת החלון הגדול לא משנה את הקטן, וההפך.
    tester.view.physicalSize = const Size(500, 900);
    await tester.pump();
    expect(big, AppDensity.compact);
    expect(small, AppDensity.compact);
    second.physicalSize = const Size(1000, 700);
    await tester.pump();
    expect(big, AppDensity.compact);
    expect(small, AppDensity.regular);
  });
}
