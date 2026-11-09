import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';

import '../support/golden_fonts.dart';

/// השבר המקסימלי של פיקסלים שונים שעדיין נחשב התאמה: 0.05% (DD-22).
const double goldenTolerance = 0.0005;

/// [LocalFileComparator] שמקבל הבדל של עד [tolerance] מהפיקסלים. את גודל
/// התמונה הוא לא סולח: תמונה בגודל אחר נכשלת תמיד.
class TolerantGoldenFileComparator extends LocalFileComparator {
  TolerantGoldenFileComparator(
    super.testFile, {
    this.tolerance = goldenTolerance,
  });

  final double tolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

/// בדיקת golden: רצה רק ב-Windows, פלטפורמת הייחוס, וב-[goldenPlatform].
void goldenTest(String description, WidgetTesterCallback body) => testWidgets(
  description,
  body,
  skip: !Platform.isWindows,
  variant: TargetPlatformVariant.only(goldenPlatform),
);

/// ערכת הנושא של האפליקציה בזרע ברירת המחדל. נבנית בתוך הבדיקה, כדי ש-
/// visualDensity והתפריטים יחושבו ל-[goldenPlatform].
ThemeData goldenTheme(Brightness brightness, {bool compact = false}) {
  final light = brightness == Brightness.light;
  final cs = AppThemeData.createColorScheme(
    light ? AppSeedColors.defaultLight : AppSeedColors.defaultDark,
    brightness,
  );
  return light
      ? AppThemeData.light(cs, compactMenuMode: compact)
      : AppThemeData.dark(cs, compactMenuMode: compact);
}

/// מפתח הגבול שה-golden מצלם.
const Key goldenBoundaryKey = ValueKey('golden-boundary');

/// מציג את [child] באפליקציה RTL בגודל חלון קבוע, ב-devicePixelRatio 1,
/// ועוטף אותו ב-RepaintBoundary בגודל הרכיב.
Future<void> pumpGolden(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  Size size = const Size(800, 600),
  double textScale = 1.0,
  TextDirection direction = TextDirection.rtl,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final theme = goldenTheme(brightness);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: Directionality(textDirection: direction, child: app!),
      ),
      home: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Center(
          child: RepaintBoundary(key: goldenBoundaryKey, child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// משווה את הגבול של [pumpGolden] ל-`goldens/<name>.png`.
Future<void> expectGolden(String name) => expectLater(
  find.byKey(goldenBoundaryKey),
  matchesGoldenFile('goldens/$name.png'),
);
