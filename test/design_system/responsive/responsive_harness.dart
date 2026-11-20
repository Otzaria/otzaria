// תשתית בדיקות Responsive: מריצה מסך או רכיב מול מטריצת חלונות (רוחב, גובה,
// בהירות, הגדלת טקסט, צפיפות, מגע), ובודקת בכל אחד מהם:
//
//  - שגיאות layout: RenderFlex overflow ושאר שגיאות הציור (כולן, לא רק הראשונה);
//  - פעולות חיוניות: נמצאות, בתוך החלון ונגישות לנגיעה ([expectVisible],
//    [expectReachable]);
//  - טקסט שנחתך ([expectNoClippedText]) וגלילה אופקית שלא נתבקשה;
//  - דיאלוגים בתוך גבולות החלון ([expectInsideViewport]).
//
// כשמוגדר משתנה הסביבה RESPONSIVE_REPORT הכשלים נכתבים אליו כשורות JSON, ואם
// מוגדר RESPONSIVE_SHOTS נשמר גם צילום של הכשל. סקריפט הסיכום של ה-CI קורא
// אותם (CI_ENFORCEMENT.md).
//
// שתי שכבות: [ResponsiveTier.quick] חוסמת בכל PR (שישה חלונות מייצגים),
// [ResponsiveTier.full] מרחיבה לכל הרוחבים והגבהים בבהיר ובכהה, בהגדלות
// 1.3 ו-2.0 ובצפיפות מצומצמת, ורצה בשינויי UI ובלוח זמנים.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/device_chrome.dart';
import 'package:otzaria/theme/app_seed_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';

import '../../support/golden_fonts.dart';

/// הרוחבים הלוגיים שנבדקים (משימת "השלמת סבב עיצוב", שלב 1). אלו גדלי בדיקה,
/// לא נקודות שבירה.
const List<double> responsiveWidths = [
  320,
  360,
  390,
  480,
  600,
  720,
  800,
  1024,
  1280,
  1920,
];

/// הגבהים הלוגיים שנבדקים.
const List<double> responsiveHeights = [400, 500, 600, 768, 1080];

/// שכבת ההרצה: ה-CI החוסם מריץ [quick], ושינויי UI ולוח זמנים מריצים [full].
enum ResponsiveTier { quick, full }

/// הרצה מורחבת, למשל בלוח זמנים: `--dart-define=RESPONSIVE_TIER=full`.
const String _tierName = String.fromEnvironment(
  'RESPONSIVE_TIER',
  defaultValue: 'quick',
);

ResponsiveTier get activeTier =>
    _tierName == 'full' ? ResponsiveTier.full : ResponsiveTier.quick;

/// חלון אחד במטריצה.
@immutable
class ResponsiveViewport {
  const ResponsiveViewport(
    this.width,
    this.height, {
    this.brightness = Brightness.light,
    this.textScale = 1.0,
    this.compact = false,
    this.touch = false,
  });

  final double width;
  final double height;
  final Brightness brightness;

  /// הגדלת הטקסט של מערכת ההפעלה (1.0, 1.3, 1.5, 2.0).
  final double textScale;

  /// צפיפות ממשק מצומצמת ([AppDensity.compact]).
  final bool compact;

  /// מכשיר מגע: [DeviceChrome.isMobile] דלוק (בלי כפתורי חלון).
  final bool touch;

  Size get size => Size(width, height);

  Rect get rect => Offset.zero & size;

  String get label {
    final parts = <String>[
      '${width.toInt()}x${height.toInt()}',
      brightness == Brightness.dark ? 'dark' : 'light',
      if (textScale != 1.0) 'text${textScale}x',
      if (compact) 'compact',
      if (touch) 'touch',
    ];
    return parts.join(' ');
  }

  @override
  String toString() => label;
}

/// החלונות לפי שכבה.
///
/// quick: שישה חלונות שמכסים טלפון, טלפון לרוחב, חלון צר, חלון שטוח, מחשב
/// ומסך רחב. full: כל הרוחבים בגובה 800 בבהיר, כל הגבהים ברוחב 1280, צירופי
/// קצה (רוחב גדול עם גובה נמוך מאוד), כהה בכל רוחב מייצג, הגדלות טקסט 1.3 ו-2.0
/// בחלון צר ובחלון רגיל, וצפיפות מצומצמת.
List<ResponsiveViewport> viewportsFor(ResponsiveTier tier) {
  if (tier == ResponsiveTier.quick) {
    return const [
      ResponsiveViewport(320, 640, touch: true),
      ResponsiveViewport(390, 844, brightness: Brightness.dark, touch: true),
      ResponsiveViewport(600, 400),
      ResponsiveViewport(800, 500, textScale: 1.3),
      ResponsiveViewport(1280, 800),
      ResponsiveViewport(1920, 1080, brightness: Brightness.dark),
    ];
  }
  return [
    for (final w in responsiveWidths) ResponsiveViewport(w, 800),
    for (final h in responsiveHeights) ResponsiveViewport(1280, h),
    const ResponsiveViewport(1920, 400),
    const ResponsiveViewport(320, 400),
    const ResponsiveViewport(360, 600, touch: true),
    const ResponsiveViewport(390, 844, touch: true),
    for (final w in const [320.0, 360.0, 600.0, 1024.0, 1920.0])
      ResponsiveViewport(w, 800, brightness: Brightness.dark),
    for (final scale in const [1.3, 1.5, 2.0])
      for (final w in const [320.0, 600.0, 1280.0])
        ResponsiveViewport(w, 800, textScale: scale),
    for (final w in const [320.0, 800.0, 1280.0])
      ResponsiveViewport(w, 800, compact: true),
    const ResponsiveViewport(
      320,
      800,
      brightness: Brightness.dark,
      compact: true,
      textScale: 1.3,
    ),
  ];
}

/// כשל אחד שנמצא בהרצה.
@immutable
class ResponsiveIssue {
  const ResponsiveIssue(this.kind, this.detail);

  /// overflow | layout-error | not-visible | not-reachable | clipped-text |
  /// outside-viewport | horizontal-scroll | tap-target
  final String kind;
  final String detail;

  Map<String, String> toJson() => {'kind': kind, 'detail': detail};

  @override
  String toString() => '[$kind] $detail';
}

/// מה שהרצה אחת אוספת: שגיאות ה-framework והכשלים של הבדיקות.
class ResponsiveRun {
  ResponsiveRun(this.viewport);

  final ResponsiveViewport viewport;
  final List<ResponsiveIssue> issues = [];

  /// גובה המקלדת הווירטואלית שפתוחה בהרצה (0 = סגורה).
  double keyboardHeight = 0;

  /// השטח שהמשתמש רואה: החלון פחות המקלדת. פעולה חיונית חייבת להיות בתוכו.
  Rect get usableRect => Rect.fromLTWH(
    0,
    0,
    viewport.width,
    (viewport.height - keyboardHeight).clamp(0, viewport.height),
  );

  FlutterExceptionHandler? _previousHandler;

  /// מחזיר את מטפל השגיאות המקורי. חובה לפני `expect`/`fail`, אחרת flutter_test
  /// מתלונן שהמטפל לא הוחזר.
  void release() {
    if (_installed) FlutterError.onError = _previousHandler;
    _installed = false;
  }

  bool _installed = false;

  /// שגיאות ש-framework דיווח עליהן ושהבדיקה הצהירה עליהן כצפויות.
  final List<Pattern> _allowedErrors = [];

  /// מצהיר על שגיאת framework צפויה (למשל overflow ידוע שמחכה לתיקון, עם
  /// הנימוק בבדיקה עצמה). שימוש חריג, לא ברירת מחדל.
  void allowError(Pattern pattern) => _allowedErrors.add(pattern);

  void _onFlutterError(FlutterErrorDetails details) {
    final text = details.exceptionAsString();
    if (_allowedErrors.any((p) => text.contains(p))) return;
    final overflow = text.contains('overflowed by');
    // בגלישה מצרפים את הווידג'ט שהאשים אותה (שורת המיקום בקוד), אחרת אי אפשר
    // לדעת איזה רכיב גלש.
    final culprit = overflow
        ? RegExp(
            r'error-causing widget was:\s*\n\s*(.+)',
          ).firstMatch(details.toString())?.group(1)
        : null;
    issues.add(
      ResponsiveIssue(
        overflow ? 'overflow' : 'layout-error',
        text.split('\n').first +
            (culprit == null ? '' : ' ($culprit)') +
            (overflow
                ? ''
                : '\n${details.stack.toString().split('\n').take(4).join('\n')}'),
      ),
    );
  }

  void add(ResponsiveIssue issue) => issues.add(issue);

  /// מכשיל אם נאספו כשלים.
  void expectClean() {
    if (issues.isEmpty) return;
    fail(
      'נמצאו ${issues.length} בעיות ב-${viewport.label}:\n'
      '${issues.map((i) => '  - $i').join('\n')}',
    );
  }
}

final GlobalKey _shotKey = GlobalKey(debugLabel: 'responsive-shot');

/// עוטף את [child] באפליקציה אחת עם ערכת הנושא האמיתית (זרע ברירת המחדל),
/// RTL, ובגודל הטקסט של ה-[viewport].
///
/// [wrapApp] עוטף את ה-MaterialApp מבחוץ (BlocProvider ושאר התלויות של מסך).
/// [scaffold] false כשהמסך מביא Scaffold משלו.
Widget buildResponsiveApp(
  ResponsiveViewport viewport,
  Widget Function(BuildContext context) build, {
  Widget Function(Widget app)? wrapApp,
  bool scaffold = true,
}) {
  final light = viewport.brightness == Brightness.light;
  final cs = AppThemeData.createColorScheme(
    light ? AppSeedColors.defaultLight : AppSeedColors.purple,
    viewport.brightness,
  );
  final theme = light
      ? AppThemeData.light(cs, compactMenuMode: viewport.compact)
      : AppThemeData.dark(cs, compactMenuMode: viewport.compact);
  final app = MaterialApp(
    debugShowCheckedModeBanner: false,
    // מגע = פלטפורמה נייד: פס גלילה, הזחות ותפריטים של Android. הטיפוגרפיה
    // כבר חושבה ב-[theme], ולכן המדידות אינן משתנות.
    theme: viewport.touch
        ? theme.copyWith(platform: TargetPlatform.android)
        : theme,
    builder: (context, child) => Directionality(
      textDirection: TextDirection.rtl,
      child: RepaintBoundary(key: _shotKey, child: child!),
    ),
    home: scaffold
        ? Scaffold(body: Builder(builder: build))
        : Builder(builder: build),
  );
  return wrapApp == null ? app : wrapApp(app);
}

/// קובע את גודל החלון, את הגדלת הטקסט ואת סוג המכשיר, ומציג את [build]. הכל
/// מתאפס בסיום הבדיקה.
Future<ResponsiveRun> pumpResponsive(
  WidgetTester tester,
  ResponsiveViewport viewport,
  Widget Function(BuildContext context) build, {
  Widget Function(Widget app)? wrapApp,
  bool scaffold = true,
  bool settle = true,
  double keyboardHeight = 0,
}) async {
  final run = ResponsiveRun(viewport)..keyboardHeight = keyboardHeight;
  run._previousHandler = FlutterError.onError;
  FlutterError.onError = run._onFlutterError;
  run._installed = true;
  addTearDown(run.release);
  // בלי הבהוב סמן: אחרת pumpAndSettle לא מסתיים כשיש שדה ממוקד.
  EditableText.debugDeterministicCursor = true;
  addTearDown(() => EditableText.debugDeterministicCursor = false);

  tester.view.physicalSize = viewport.size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = viewport.textScale;
  DeviceChrome.debugMobileOverride = viewport.touch;
  // מקלדת וירטואלית פתוחה: ה-viewInsets התחתון מקטין את השטח הפנוי.
  if (keyboardHeight > 0) {
    tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
  }
  addTearDown(() {
    tester.view.resetViewInsets();
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    DeviceChrome.debugMobileOverride = null;
  });

  await tester.pumpWidget(
    buildResponsiveApp(viewport, build, wrapApp: wrapApp, scaffold: scaffold),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return run;
}

Rect _rectOf(WidgetTester tester, Finder finder) =>
    tester.getRect(finder.first);

/// [finder] קיים, בשלמותו בתוך החלון, ונגיעה במרכזו מגיעה אליו (לא מוסתר
/// בידי רכיב אחר). בלי גלילה: מתאים לפעולות שחייבות להיראות כל הזמן (כפתורי
/// אישור בדיאלוג, סרגל כלים).
void expectVisible(
  WidgetTester tester,
  ResponsiveRun run,
  Finder finder, {
  required String name,
}) {
  if (finder.evaluate().isEmpty) {
    run.add(ResponsiveIssue('not-visible', '$name: לא נמצא בעץ'));
    return;
  }
  final rect = _rectOf(tester, finder);
  if (!_contains(run.usableRect, rect)) {
    run.add(
      ResponsiveIssue(
        'outside-viewport',
        '$name: ${_fmt(rect)} חורג מהחלון ${_fmt(run.usableRect)}',
      ),
    );
    return;
  }
  if (finder.hitTestable().evaluate().isEmpty) {
    run.add(ResponsiveIssue('not-visible', '$name: מוסתר או לא נתפס בנגיעה'));
  }
}

/// כמו [expectVisible], אבל מותר שהפקד בתוך אזור גלילה: הוא נגלל אל החלון
/// ומגיע לנגיעה. מתאים לפעולות בתוך רשימה או טופס ארוך.
///
/// ברשימה עצלה (`ListView.builder`) הפקד לא קיים בעץ עד שמגיעים אליו, ולכן
/// [scrollable] מצביע על הגלילה שאליה מגללים עד שהוא נבנה.
Future<void> expectReachable(
  WidgetTester tester,
  ResponsiveRun run,
  Finder finder, {
  required String name,
  Finder? scrollable,
}) async {
  if (finder.evaluate().isEmpty && scrollable != null) {
    try {
      await tester.scrollUntilVisible(finder, 120, scrollable: scrollable);
    } on StateError {
      // לא נמצא גם אחרי גלילה: מדווחים למטה.
    }
  }
  if (finder.evaluate().isEmpty) {
    run.add(ResponsiveIssue('not-reachable', '$name: לא נמצא בעץ'));
    return;
  }
  // גם פקד שמרכזו נתפס בנגיעה אבל שוליו חורגים מהחלון (חתוך בקצה אזור גלילה)
  // צריך להגיע אליו בגלילה לפני שבודקים אותו.
  if (finder.hitTestable().evaluate().isEmpty ||
      !_contains(run.usableRect, _rectOf(tester, finder))) {
    try {
      await tester.ensureVisible(finder.first);
      await tester.pump();
    } on Object catch (e) {
      run.add(
        ResponsiveIssue('not-reachable', '$name: ensureVisible נכשל ($e)'),
      );
      return;
    }
  }
  final rect = _rectOf(tester, finder);
  if (!_contains(run.usableRect, rect) ||
      finder.hitTestable().evaluate().isEmpty) {
    run.add(
      ResponsiveIssue(
        'not-reachable',
        '$name: גם אחרי גלילה ${_fmt(rect)} לא נגיש בחלון ${_fmt(run.usableRect)}',
      ),
    );
  }
}

/// [finder] (דיאלוג, תפריט, חלונית) בתוך גבולות החלון.
void expectInsideViewport(
  WidgetTester tester,
  ResponsiveRun run,
  Finder finder, {
  required String name,
}) {
  if (finder.evaluate().isEmpty) {
    run.add(ResponsiveIssue('outside-viewport', '$name: לא נמצא בעץ'));
    return;
  }
  final rect = _rectOf(tester, finder);
  if (!_contains(run.usableRect.inflate(0.5), rect)) {
    run.add(
      ResponsiveIssue(
        'outside-viewport',
        '$name: ${_fmt(rect)} חורג מהחלון ${_fmt(run.usableRect)}',
      ),
    );
  }
}

/// אף אחד מהטקסטים שמתחת ל-[within] לא נחתך בגלל [Text.maxLines]. טקסט שנקטע
/// ב"..." מכוון (שם ספר ארוך עם רמז) צריך להישאר מחוץ ל-[within] או להצהיר על
/// עצמו ב-[ignoreLabels].
void expectNoClippedText(
  WidgetTester tester,
  ResponsiveRun run, {
  Finder? within,
  Set<String> ignoreLabels = const {},
}) {
  final scope = within ?? find.byType(Overlay);
  final paragraphs = find.descendant(
    of: scope,
    matching: find.byType(RichText),
  );
  for (final element in paragraphs.evaluate()) {
    final render = element.renderObject;
    if (render is! RenderParagraph) continue;
    final text = render.text.toPlainText();
    if (ignoreLabels.contains(text)) continue;
    if (render.didExceedMaxLines) {
      run.add(
        ResponsiveIssue(
          'clipped-text',
          'הטקסט נחתך: "${_short(text)}" (maxLines=${render.maxLines})',
        ),
      );
    }
  }
}

/// אין גלילה אופקית גלויה, אלא אם היא מותרת בשם ב-[allowed].
void expectNoHorizontalScroll(
  WidgetTester tester,
  ResponsiveRun run, {
  Set<Key> allowed = const {},
}) {
  for (final element in find.byType(Scrollable).evaluate()) {
    final scrollable = element.widget as Scrollable;
    if (scrollable.axis != Axis.horizontal) continue;
    // שדה טקסט חד־שורתי גולל את הטקסט שלו אופקית: זה לא פריסה שבורה.
    if (element.findAncestorWidgetOfExactType<EditableText>() != null) continue;
    if (allowed.contains(scrollable.key)) continue;
    final position =
        ((element as StatefulElement).state as ScrollableState).position;
    if (position.maxScrollExtent > 0.5) {
      run.add(
        ResponsiveIssue(
          'horizontal-scroll',
          'גלילה אופקית בלתי מכוונת (${position.maxScrollExtent.toStringAsFixed(1)}px)',
        ),
      );
    }
  }
}

/// שטח הנגיעה של [finder] לפחות [minSize] בשני הצירים (48 במגע).
void expectTapTarget(
  WidgetTester tester,
  ResponsiveRun run,
  Finder finder, {
  required String name,
  double minSize = 48,
}) {
  if (finder.evaluate().isEmpty) {
    run.add(ResponsiveIssue('tap-target', '$name: לא נמצא בעץ'));
    return;
  }
  final size = tester.getSize(finder.first);
  if (size.width + 0.5 < minSize || size.height + 0.5 < minSize) {
    run.add(
      ResponsiveIssue(
        'tap-target',
        '$name: ${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)} '
            'קטן מ-${minSize.toInt()}x${minSize.toInt()}',
      ),
    );
  }
}

bool _contains(Rect outer, Rect inner) =>
    inner.left >= outer.left - 0.5 &&
    inner.top >= outer.top - 0.5 &&
    inner.right <= outer.right + 0.5 &&
    inner.bottom <= outer.bottom + 0.5;

String _fmt(Rect r) =>
    '(${r.left.toStringAsFixed(0)},${r.top.toStringAsFixed(0)} '
    '${r.width.toStringAsFixed(0)}x${r.height.toStringAsFixed(0)})';

String _short(String s) => s.length <= 40 ? s : '${s.substring(0, 40)}…';

/// פעולה בתוך תרחיש: מחכה לדיאלוג, מקליד, פותח תפריט, וכד'.
typedef ResponsiveAct =
    Future<void> Function(WidgetTester tester, ResponsiveRun run);

/// רושם בדיקה אחת לכל חלון במטריצה של השכבה הפעילה.
///
/// [build] בונה את המסך או הרכיב. [act] מבצע פעולה אחרי הבנייה (פתיחת דיאלוג
/// למשל). [verify] מוסיף בדיקות ספציפיות (פעולות חיוניות). אחריהם נבדק תמיד
/// שלא נאספו שגיאות layout, ושאין גלילה אופקית בלתי מכוונת ([horizontalScroll]).
///
/// [viewports] מחליף את המטריצה כשיש סיבה (רכיב שרלוונטי לרוחב אחד).
void testResponsive(
  String description, {
  required Widget Function(BuildContext context) build,
  Widget Function(Widget app)? wrapApp,
  bool scaffold = true,
  ResponsiveAct? act,
  ResponsiveAct? verify,
  List<ResponsiveViewport>? viewports,
  bool horizontalScroll = false,
  Set<Key> allowedHorizontalScrolls = const {},
  bool settle = true,
  double keyboardHeight = 0,
}) {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadGoldenFonts();
    // ב-Android משפחת הממשק היא Roboto: טוענים בה את Rubik, אחרת המדידות
    // במצב מגע היו בגופן הבדיקה המרובע.
    final roboto = FontLoader('Roboto')
      ..addFont(rootBundle.load('fonts/Rubik-VariableFont_wght.ttf'));
    await roboto.load();
  });
  for (final viewport in viewports ?? viewportsFor(activeTier)) {
    testWidgets(
      '$description @ ${viewport.label}',
      (tester) async {
        final run = await pumpResponsive(
          tester,
          viewport,
          build,
          wrapApp: wrapApp,
          scaffold: scaffold,
          settle: settle,
          keyboardHeight: keyboardHeight,
        );
        try {
          if (act != null) await act(tester, run);
          if (verify != null) await verify(tester, run);
          if (!horizontalScroll) {
            expectNoHorizontalScroll(
              tester,
              run,
              allowed: allowedHorizontalScrolls,
            );
          }
          run.release();
          run.expectClean();
        } on Object catch (e) {
          run.release();
          await _recordFailure(tester, description, run, e);
          rethrow;
        }
      },
      variant: TargetPlatformVariant.only(
        viewport.touch ? TargetPlatform.android : goldenPlatform,
      ),
    );
  }
}

Future<void> _recordFailure(
  WidgetTester tester,
  String description,
  ResponsiveRun run,
  Object error,
) async {
  final reportPath = Platform.environment['RESPONSIVE_REPORT'];
  final shotsDir = Platform.environment['RESPONSIVE_SHOTS'];
  if (reportPath == null && shotsDir == null) return;

  String? shotFile;
  if (shotsDir != null) {
    final safe = '$description ${run.viewport.label}'.replaceAll(
      RegExp(r'[^\p{L}\p{N}]+', unicode: true),
      '_',
    );
    shotFile = '$shotsDir/$safe.png';
    await tester.runAsync(() async {
      try {
        final boundary =
            _shotKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
        if (boundary == null) return;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) return;
        Directory(shotsDir).createSync(recursive: true);
        File(shotFile!).writeAsBytesSync(bytes.buffer.asUint8List());
      } on Object {
        shotFile = null;
      }
    });
  }
  if (reportPath != null) {
    final line = jsonEncode({
      'scenario': description,
      'viewport': run.viewport.label,
      'issues': [for (final i in run.issues) i.toJson()],
      'error': run.issues.isEmpty ? error.toString().split('\n').first : null,
      'screenshot': shotFile,
    });
    File(reportPath).writeAsStringSync('$line\n', mode: FileMode.append);
  }
}
