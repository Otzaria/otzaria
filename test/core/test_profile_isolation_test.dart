import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:path/path.dart' as p;

import '../helpers/memory_settings_cache.dart';

/// שורש הנתונים האמיתי של המשתמש לפי הפלטפורמה (APPDATA וכדומה).
String _realProfileDataRoot() {
  final env = Platform.environment;
  if (Platform.isWindows) return p.join(env['APPDATA'] ?? '', 'otzaria');
  final home = env['HOME'] ?? '';
  if (Platform.isMacOS) {
    return p.join(home, 'Library', 'Application Support', 'otzaria');
  }
  return p.join(home, '.local', 'share', 'otzaria');
}

bool _isUnder(String parent, String path) =>
    p.equals(parent, path) || p.isWithin(parent, path);

void main() {
  group('הרצת בדיקות אינה נוגעת בפרופיל המשתמש האמיתי (issue #1790)', () {
    setUp(() async {
      await Settings.init(cacheProvider: MemorySettingsCache());
      // המצב שבדיקות רבות משאירות אחריהן ב-tearDown.
      AppPaths.debugOverrideDataRootPath(null);
    });

    tearDown(Settings.clearCache);

    test('שורש הנתונים ונתיב האינדקס אינם תחת הפרופיל האמיתי', () async {
      final realRoot = _realProfileDataRoot();
      expect(_isUnder(realRoot, await AppPaths.getDataRootPath()), isFalse);
      expect(_isUnder(realRoot, await AppPaths.getIndexPath()), isFalse);
    });

    test('קובץ השגיאות אינו קובץ השגיאות האמיתי', () {
      final realLogPaths = {
        p.join(_realProfileDataRoot(), 'logs', ErrorLogFile.fileName),
        ErrorLogFile.resolvePath(environment: Platform.environment),
      };

      expect(realLogPaths, isNot(contains(ErrorLogFile.resolvePath())));
    });
  });
}
