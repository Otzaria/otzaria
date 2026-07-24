import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/theme/app_theme_data.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  String hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

  group('buildThemePayloadFromScheme', () {
    test('mode נגזר מהפרמטר isDark ולא מהבהירות של ה-scheme', () {
      // התיקון: ה-payload נבנה מ-scheme מפורש כדי לעקוף את Theme.of(context)
      // שמפגר frame אחד. אותו scheme עם isDark שונה => mode שונה.
      final scheme = AppThemeData.createColorScheme(
        Colors.blue,
        Brightness.dark,
      );
      expect(buildThemePayloadFromScheme(scheme, isDark: true)['mode'], 'dark');
      expect(
        buildThemePayloadFromScheme(scheme, isDark: false)['mode'],
        'light',
      );
    });

    test('הצבעים ב-payload משקפים את ה-scheme שהועבר', () {
      final scheme = AppThemeData.createColorScheme(
        Colors.blue,
        Brightness.dark,
      );
      final cs =
          buildThemePayloadFromScheme(scheme, isDark: true)['colorScheme']
              as Map;
      expect(cs['surface'], hex(scheme.surface));
      expect(cs['primary'], hex(scheme.primary));
    });
  });

  group('AppThemeData.createColorScheme', () {
    test('מכבד את הבהירות המבוקשת', () {
      expect(
        AppThemeData.createColorScheme(Colors.blue, Brightness.dark).brightness,
        Brightness.dark,
      );
      expect(
        AppThemeData.createColorScheme(
          Colors.blue,
          Brightness.light,
        ).brightness,
        Brightness.light,
      );
    });
  });
}
