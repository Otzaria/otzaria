import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';

/// ערכת הנושא של האפליקציה, בזרע ברירת המחדל של מצב הבהירות.
ThemeData appTheme(Brightness brightness) {
  final seed = brightness == Brightness.light
      ? AppSeedColors.defaultLight
      : AppSeedColors.defaultDark;
  final cs = AppThemeData.createColorScheme(seed, brightness);
  return brightness == Brightness.light
      ? AppThemeData.light(cs, compactMenuMode: false)
      : AppThemeData.dark(cs, compactMenuMode: false);
}

/// מציג את [child] בתוך אפליקציה RTL עם ערכת הנושא האמיתית, בגודל חלון קבוע.
Future<void> pumpInApp(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  Size size = const Size(1200, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: appTheme(brightness),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Scaffold(body: child),
    ),
  );
}

/// התוצאה של דיאלוג שנפתח ב-[openDialog].
class DialogOutcome<T> {
  bool closed = false;
  T? value;
}

/// פותח דיאלוג דרך [open] ומחזיר את התוצאה שלו, שמתמלאת כשהוא נסגר.
Future<DialogOutcome<T>> openDialog<T>(
  WidgetTester tester,
  Future<T?> Function(BuildContext context) open, {
  Brightness brightness = Brightness.light,
  Size size = const Size(1200, 800),
}) async {
  final outcome = DialogOutcome<T>();
  await pumpInApp(
    tester,
    Builder(
      builder: (context) => Center(
        child: GestureDetector(
          onTap: () async {
            outcome.value = await open(context);
            outcome.closed = true;
          },
          child: const Text('פתח'),
        ),
      ),
    ),
    brightness: brightness,
    size: size,
  );
  await tester.tap(find.text('פתח'));
  await tester.pumpAndSettle();
  return outcome;
}

/// פותח את [dialog] ב-[showDialog].
Future<DialogOutcome<T>> showInApp<T>(
  WidgetTester tester,
  Widget dialog, {
  Brightness brightness = Brightness.light,
  Size size = const Size(1200, 800),
}) => openDialog<T>(
  tester,
  (context) => showDialog<T>(context: context, builder: (_) => dialog),
  brightness: brightness,
  size: size,
);

/// ה-[ColorScheme] שבתוקף במקום של [finder].
ColorScheme schemeAt(WidgetTester tester, Finder finder) =>
    Theme.of(tester.element(finder)).colorScheme;

/// ה-[Material] הראשון בתוך [of]: המשטח שהרכיב מצייר בפועל.
Material firstMaterialIn(WidgetTester tester, Finder of) => tester.widget(
  find.descendant(of: of, matching: find.byType(Material)).first,
);
