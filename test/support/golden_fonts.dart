import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// הפלטפורמה שבה ה-goldens מצוירים (DD-22): Windows, כמו האפליקציה אצל רוב
/// המשתמשים. קובעת את משפחת הגופן של ה-textTheme, את visualDensity ואת
/// התפריטים הצפופים.
const TargetPlatform goldenPlatform = TargetPlatform.windows;

/// המשפחה ש-ThemeData מבקש ב-[goldenPlatform] כשאין fontFamily ('Segoe UI').
String get goldenUiFontFamily => Typography.material2021(
  platform: goldenPlatform,
).black.bodyMedium!.fontFamily!;

/// גופן הבדיקה של הממשק: Rubik מהמאגר, כי Segoe UI אינו כלול (רישיון).
const String _uiTestFontAsset = 'fonts/Rubik-VariableFont_wght.ttf';

/// גופני האייקונים מתוך FontManifest של ה-bundle.
const Set<String> _iconFamilies = {
  'MaterialIcons',
  'FluentSystemIcons-Light',
  'packages/otzaria_icons/OtzariaIcons',
  'packages/fluentui_system_icons/FluentSystemIcons-Regular',
  'packages/fluentui_system_icons/FluentSystemIcons-Filled',
};

bool _loaded = false;

/// טוען את גופני ה-goldens פעם אחת לכל isolate.
///
/// Rubik נרשם בשם [goldenUiFontFamily], ולכן כל טקסט שיורש את ה-textTheme
/// (וגם רשימת ה-fallback, שמתחילה ב-Segoe UI) מצויר בו. טקסט בלי fontFamily
/// בכלל — `TextSpan`/`RichText` שלא יורשים סגנון, `TextPainter` בציור — מצויר
/// בגופן המובנה של flutter_tester (ריבועים), ואי אפשר לכנות אותו מ-Dart.
Future<void> loadGoldenFonts() async {
  if (_loaded) return;
  _loaded = true;

  final ui = FontLoader(goldenUiFontFamily)
    ..addFont(rootBundle.load(_uiTestFontAsset));
  await ui.load();

  final manifest =
      jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final family = entry['family'] as String;
    if (!_iconFamilies.contains(family)) continue;
    final loader = FontLoader(family);
    for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}
