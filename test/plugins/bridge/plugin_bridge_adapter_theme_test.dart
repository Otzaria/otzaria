import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/theme/app_density.dart';
import 'package:otzaria/theme/app_surface_colors.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/theme/app_tokens.dart';

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
      expect(_payload(scheme, isDark: true)['mode'], 'dark');
      expect(
        _payload(scheme, isDark: false)['mode'],
        'light',
      );
    });

    test('הצבעים ב-payload משקפים את ה-scheme שהועבר', () {
      final scheme = AppThemeData.createColorScheme(
        Colors.blue,
        Brightness.dark,
      );
      final cs = _payload(scheme, isDark: true)['colorScheme'] as Map;
      expect(cs['surface'], hex(scheme.surface));
      expect(cs['primary'], hex(scheme.primary));
    });

    test('המשטחים נגזרים מ-AppSurfaceColors של אותו scheme', () {
      for (final brightness in Brightness.values) {
        final scheme = AppThemeData.createColorScheme(Colors.teal, brightness);
        final expected = AppSurfaceColors.fromScheme(scheme);
        final surfaces =
            _payload(scheme, isDark: brightness == Brightness.dark)['surfaces']
                as Map;
        expect(surfaces, {
          'reader': hex(expected.readerBackground),
          'panel': hex(expected.panelBackground),
          'card': hex(expected.card),
          'topBar': hex(expected.topBarBackground),
        });
      }
    });

    test('משטחים מפורשים גוברים על החישוב מה-scheme', () {
      final scheme = AppThemeData.createColorScheme(
        Colors.blue,
        Brightness.light,
      );
      final custom = AppSurfaceColors.fromScheme(
        scheme,
      ).copyWith(readerBackground: const Color(0xFF123456));
      final surfaces =
          buildThemePayloadFromScheme(
                scheme,
                isDark: false,
                density: AppDensity.regular,
                surfaces: custom,
              )['surfaces']
              as Map;
      expect(surfaces['reader'], '#123456');
    });

    test('רדיוס וסולם הריווח הם הטוקנים של AppTokens', () {
      final payload = _payload(
        AppThemeData.createColorScheme(Colors.blue, Brightness.light),
        isDark: false,
      );
      expect(payload['radius'], AppTokens.radius);
      expect(payload['spacing'], {
        '2xs': 2.0,
        'xs': 4.0,
        'sm': 8.0,
        'smd': 12.0,
        'md': 16.0,
        'lg': 24.0,
        'xl': 32.0,
      });
    });

    test('הצפיפות משקפת את AppDensity', () {
      final scheme = AppThemeData.createColorScheme(
        Colors.blue,
        Brightness.light,
      );
      Map density(AppDensity d) =>
          buildThemePayloadFromScheme(
                scheme,
                isDark: false,
                density: d,
              )['density']
              as Map;
      expect(density(AppDensity.regular), {
        'compact': false,
        'topBarHeight': 56.0,
        'fieldHeight': 48.0,
      });
      expect(density(AppDensity.compact), {
        'compact': true,
        'topBarHeight': 44.0,
        'fieldHeight': 36.0,
      });
    });

    test('השדות הקיימים נשארים: uiFontFamily הוא Rubik, uiFont נוסף לצדו', () {
      final typography =
          _payload(
                AppThemeData.createColorScheme(Colors.blue, Brightness.light),
                isDark: false,
              )['typography']
              as Map;
      expect(typography['uiFontFamily'], 'Rubik');
      expect(typography['uiFont'], pluginHostUiFontStack());
    });

    test('ה-payload עובר JSON כמו שהוא', () {
      final payload = _payload(
        AppThemeData.createColorScheme(Colors.blue, Brightness.dark),
        isDark: true,
      );
      expect(jsonDecode(jsonEncode(payload)), payload);
    });
  });

  group('pluginHostUiFontStack', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('ב-Windows: Segoe UI ראשון, בלי כפילות, וגופן המערכת בסוף', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(
        pluginHostUiFontStack(),
        "'Segoe UI', 'SF Pro Text', '.AppleSystemUIFont', "
        "'Noto Sans Hebrew', 'Arial', system-ui, sans-serif",
      );
    });

    test('המשפחה של הפלטפורמה מגיעה מ-AppThemeData', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final first = pluginHostUiFontStack().split(', ').first;
      expect(first, "'${AppThemeData.uiFontFamily}'");
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

Map<String, dynamic> _payload(ColorScheme scheme, {required bool isDark}) =>
    buildThemePayloadFromScheme(
      scheme,
      isDark: isDark,
      density: AppDensity.regular,
    );
