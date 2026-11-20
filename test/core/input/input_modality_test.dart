import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/input/input_modality.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';

/// "מגע" באנדרואיד/iOS הוא ברירת המחדל, ועכבר שהופיע אחרון מחזיר את הממשק
/// למידות מחשב עד שמגיע אירוע מגע או עט. במחשב (Windows/Linux/macOS) אין שינוי.
void main() {
  bool? seenTouch;
  bool? seenMouse;

  Future<void> pumpApp(
    WidgetTester tester, {
    required bool inScope,
    bool adaptTheme = true,
  }) async {
    final cs = AppThemeData.createColorScheme(
      AppSeedColors.defaultLight,
      Brightness.light,
    );
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final probe = Builder(
      builder: (context) {
        seenTouch = BarButton.isTouch(context);
        seenMouse = InputModality.lastPointerIsMouseOf(context);
        return const SizedBox.expand();
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.light(cs, compactMenuMode: false),
        builder: (context, child) => inScope
            ? InputModalityScope(adaptTheme: adaptTheme, child: child!)
            : child!,
        home: probe,
      ),
    );
  }

  Future<void> mouseMove(WidgetTester tester, {bool trackpad = false}) async {
    if (trackpad) {
      final g = await tester.createGesture(kind: PointerDeviceKind.trackpad);
      await g.panZoomStart(const Offset(50, 50));
      await tester.pump();
      await g.panZoomEnd();
      await tester.pump();
      return;
    }
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: const Offset(5, 5));
    await g.moveTo(const Offset(50, 50));
    await tester.pump();
    await g.removePointer();
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, PointerDeviceKind kind) async {
    final g = await tester.startGesture(const Offset(100, 100), kind: kind);
    await g.up();
    await tester.pump();
  }

  /// בודק עם פלטפורמה מדומה; חייב להחזיר אותה בתוך גוף הבדיקה (בדיקת
  /// האינווריאנטים של flutter_test רצה לפני tearDown).
  Future<void> onPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('אנדרואיד: מגע, אחר כך עכבר, אחר כך מגע', (tester) async {
    await pumpApp(tester, inScope: true);
    expect(seenTouch, isTrue, reason: 'ברירת המחדל באנדרואיד: מגע');
    expect(seenMouse, isNull, reason: 'עוד לא הגיע אירוע מצביע');

    await mouseMove(tester);
    expect(seenMouse, isTrue);
    expect(seenTouch, isFalse, reason: 'עכבר אחרון: ממשק מחשב');

    await tap(tester, PointerDeviceKind.touch);
    expect(seenMouse, isFalse);
    expect(seenTouch, isTrue, reason: 'אירוע מגע מחזיר למגע');

    await mouseMove(tester, trackpad: true);
    expect(seenTouch, isFalse, reason: 'משטח מגע נחשב עכבר');

    await tap(tester, PointerDeviceKind.stylus);
    expect(seenTouch, isTrue, reason: 'עט מחזיר למגע');
  });

  testWidgets('בלי InputModalityScope עכבר לא משנה כלום (ברירת מחדל מגע)', (
    tester,
  ) async {
    await pumpApp(tester, inScope: false);
    await mouseMove(tester);
    expect(seenTouch, isTrue);
    expect(seenMouse, isNull);
  });

  testWidgets('בלי adaptTheme הערכה לא משתנה, אבל המצביע האחרון נקלט', (
    tester,
  ) async {
    await pumpApp(tester, inScope: true, adaptTheme: false);
    await mouseMove(tester);
    expect(seenMouse, isTrue);
    expect(seenTouch, isTrue);
  });

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ]) {
    testWidgets('$platform: נשאר מחשב גם עם מסך מגע', (tester) async {
      await onPlatform(platform, () async {
        await pumpApp(tester, inScope: true);
        expect(seenTouch, isFalse);
        await tap(tester, PointerDeviceKind.touch);
        expect(seenTouch, isFalse, reason: 'החלטת הבעלים: מחשב גם עם מגע');
        await mouseMove(tester);
        expect(seenTouch, isFalse);
      });
    });
  }

  testWidgets('iOS: אותו דבר כמו אנדרואיד', (tester) async {
    await onPlatform(TargetPlatform.iOS, () async {
      await pumpApp(tester, inScope: true);
      expect(seenTouch, isTrue);
      await mouseMove(tester);
      expect(seenTouch, isFalse);
      await tap(tester, PointerDeviceKind.touch);
      expect(seenTouch, isTrue);
    });
  });

  testWidgets('scope מקונן לא פותח מעקב שני ולא מחליף את הערך', (tester) async {
    await pumpApp(tester, inScope: true);
    await mouseMove(tester);
    late bool? inner;
    await tester.pumpWidget(
      MaterialApp(
        home: InputModalityScope(
          child: InputModalityScope(
            child: Builder(
              builder: (context) {
                inner = InputModality.lastPointerIsMouseOf(context);
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    expect(inner, isNull, reason: 'עץ חדש, מעקב חדש');
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: const Offset(1, 1));
    await g.moveTo(const Offset(9, 9));
    await tester.pump();
    expect(inner, isTrue);
    await g.removePointer();
  });
}
