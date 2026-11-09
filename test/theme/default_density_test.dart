// q12 Q8, הערת בעל הפרויקט (4.11): במסך קטן "צפיפות ממשק" מצומצמת כברירת
// מחדל, ובחירה מפורשת של המשתמש נשמרת. "מסך קטן" הוא טלפון, או חצי מסך של
// 10" בטאבלט; במחשב רק חלון נמוך (סקירה r3).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/device_chrome.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/theme/app_density.dart';
import 'package:otzaria/theme/app_theme_data.dart';

/// הבדיקות של [body] בטלפון ([mobile]) או במחשב.
void onDevice(bool mobile, void Function() body) {
  setUp(() => DeviceChrome.debugMobileOverride = mobile);
  tearDown(() => DeviceChrome.debugMobileOverride = null);
  body();
}

/// כמה פעמים [SmallWindowBuilder] בנה, ועם איזו תשובה, לאורך [sizes].
Future<List<bool>> builds(WidgetTester tester, List<Size> sizes) async {
  addTearDown(tester.view.reset);
  tester.view.devicePixelRatio = 1;
  final result = <bool>[];
  final widget = SmallWindowBuilder(
    builder: (isSmall) {
      result.add(isSmall);
      return const SizedBox();
    },
  );
  for (final (i, size) in sizes.indexed) {
    tester.view.physicalSize = size;
    if (i == 0) {
      await tester.pumpWidget(widget);
    } else {
      await tester.pump();
    }
  }
  return result;
}

void main() {
  group('AppDensity.isSmallWindow בטלפון ובטאבלט', () {
    onDevice(true, () {
      test('הצד הקצר מתחת ל-600: טלפון לאורך ולרוחב, חצי מסך של 10"', () {
        for (final size in const [
          Size(360, 640),
          Size(390, 844),
          Size(844, 390),
          Size(512, 600),
        ]) {
          expect(AppDensity.isSmallWindow(size), isTrue, reason: '$size');
        }
      });

      test('טאבלט 10" (1024×600 ומעלה) אינו קטן', () {
        for (final size in const [
          Size(1024, 600),
          Size(800, 1280),
          Size(1280, 800),
        ]) {
          expect(AppDensity.isSmallWindow(size), isFalse, reason: '$size');
        }
      });
    });
  });

  group('AppDensity.isSmallWindow במחשב: רק חלון נמוך', () {
    onDevice(false, () {
      test('מחשב נייד 1366×768 ב-125%, מוגדל (1093×566), אינו קטן', () {
        for (final size in const [
          Size(1093, 566),
          Size(1024, 600),
          Size(512, 600),
          Size(500, 900),
          Size(1280, 800),
        ]) {
          expect(AppDensity.isSmallWindow(size), isFalse, reason: '$size');
        }
      });

      test('חלון נמוך מ-480 קטן', () {
        for (final size in const [Size(1200, 450), Size(640, 360)]) {
          expect(AppDensity.isSmallWindow(size), isTrue, reason: '$size');
        }
      });

      test('בלי בחירה 1093×566 נשאר רגיל', () {
        expect(
          SettingsState.initial().compactMenuModeFor(
            isSmallWindow: AppDensity.isSmallWindow(const Size(1093, 566)),
          ),
          isFalse,
        );
      });
    });
  });

  group('SettingsState.compactMenuModeFor', () {
    final unset = SettingsState.initial();

    test('בלי בחירה: מצומצם רק בחלון קטן', () {
      expect(unset.compactMenuModeIsSet, isFalse);
      expect(unset.compactMenuModeFor(isSmallWindow: true), isTrue);
      expect(unset.compactMenuModeFor(isSmallWindow: false), isFalse);
    });

    test('בחירה מפורשת ב"רגיל" נשמרת גם בחלון קטן', () {
      final regular = unset.copyWith(
        compactMenuMode: false,
        compactMenuModeIsSet: true,
      );
      expect(regular.compactMenuModeFor(isSmallWindow: true), isFalse);
      expect(regular.compactMenuModeFor(isSmallWindow: false), isFalse);
    });

    test('בחירה מפורשת ב"מצומצם" נשמרת גם בחלון גדול', () {
      final compact = unset.copyWith(
        compactMenuMode: true,
        compactMenuModeIsSet: true,
      );
      expect(compact.compactMenuModeFor(isSmallWindow: false), isTrue);
    });

    test('"לא נבחר" ו"רגיל" אינם אותו מצב', () {
      expect(
        unset,
        isNot(
          unset.copyWith(compactMenuMode: false, compactMenuModeIsSet: true),
        ),
      );
    });
  });

  for (final mobile in [true, false]) {
    group('חלון נמוך (גובה מתחת ל-480), ${mobile ? 'טלפון' : 'מחשב'}', () {
      onDevice(mobile, () {
        const shortWindows = [Size(640, 360), Size(568, 320), Size(1200, 450)];

        test('בלי בחירה: מצומצם', () {
          for (final size in shortWindows) {
            final isSmall = AppDensity.isSmallWindow(size);
            expect(isSmall, isTrue, reason: '$size');
            expect(
              SettingsState.initial().compactMenuModeFor(
                isSmallWindow: isSmall,
              ),
              isTrue,
              reason: '$size',
            );
          }
        });

        test('בחירה מפורשת ב"רגיל" נשמרת', () {
          final regular = SettingsState.initial().copyWith(
            compactMenuMode: false,
            compactMenuModeIsSet: true,
          );
          for (final size in shortWindows) {
            expect(
              regular.compactMenuModeFor(
                isSmallWindow: AppDensity.isSmallWindow(size),
              ),
              isFalse,
              reason: '$size',
            );
          }
        });
      });
    });
  }

  group('SmallWindowBuilder בטלפון', () {
    onDevice(true, () {
      testWidgets('נבנה מחדש רק כשהתשובה מתהפכת, לא בכל שינוי גודל', (
        tester,
      ) async {
        expect(
          await builds(tester, const [
            Size(1280, 800),
            Size(1100, 760),
            Size(1024, 600),
            Size(360, 640),
            Size(640, 360),
            Size(1280, 800),
          ]),
          [false, true, false],
        );
      });
    });
  });

  group('SmallWindowBuilder במחשב', () {
    onDevice(false, () {
      testWidgets('במחשב 1093×566 אינו מתהפך; חלון נמוך מ-480 כן', (
        tester,
      ) async {
        expect(
          await builds(tester, const [
            Size(1366, 705),
            Size(1093, 566),
            Size(1200, 450),
          ]),
          [false, true],
        );
      });
    });
  });

  // theme.changed לתוספים (MainWindowScreen) נשלח מ-AppDensityListener כשהצפיפות
  // שבפועל מתהפכת עם גודל החלון.
  group('AppDensityListener מתחת לערכת הנושא של App', () {
    onDevice(false, () {
      testWidgets('פעם אחת לכל היפוך, ולא בכל שינוי גודל', (tester) async {
        addTearDown(tester.view.reset);
        tester.view.devicePixelRatio = 1;
        final cs = AppThemeData.createColorScheme(
          Colors.brown,
          Brightness.light,
        );
        final calls = <bool>[];
        // כמו App: ערכת הנושא נבנית ב-SmallWindowBuilder, בלי בחירה.
        final app = SmallWindowBuilder(
          builder: (isSmall) => MaterialApp(
            theme: AppThemeData.light(
              cs,
              compactMenuMode: SettingsState.initial().compactMenuModeFor(
                isSmallWindow: isSmall,
              ),
            ),
            home: AppDensityListener(
              onChanged: (density) => calls.add(density.isCompact),
              child: const SizedBox(),
            ),
          ),
        );

        Future<void> resize(Size size) async {
          tester.view.physicalSize = size;
          // כל המעבר המונפש בין ערכות הנושא.
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 60));
          }
        }

        tester.view.physicalSize = const Size(1280, 800);
        await tester.pumpWidget(app);
        await resize(const Size(1100, 760));
        await resize(const Size(1093, 566));
        expect(calls, isEmpty, reason: 'בבנייה הראשונה ובלי היפוך אין קריאה');

        await resize(const Size(1200, 450));
        await resize(const Size(1180, 440));
        await resize(const Size(1000, 400));
        expect(calls, [true]);

        await resize(const Size(1280, 800));
        await resize(const Size(1300, 820));
        expect(calls, [true, false]);
      });
    });
  });
}
