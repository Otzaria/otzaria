import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserBooksDatabaseHolder', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria-uddh-');
      await Settings.init(cacheProvider: _MemoryCacheProvider());
      await UserBooksDatabaseHolder.instance.close();
      AppPaths.debugOverrideDataRootPath(tempDir.path);
    });

    tearDown(() async {
      await UserBooksDatabaseHolder.instance.close();
      AppPaths.debugOverrideDataRootPath(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('repository מאותחל פעם אחת ומוחזק במטמון (אותו instance)', () async {
      final first = await UserBooksDatabaseHolder.instance.repository;
      final second = await UserBooksDatabaseHolder.instance.repository;

      expect(
        identical(first, second),
        isTrue,
        reason: 'הקריאה השנייה חייבת להחזיר את אותו repository, בלי לאתחל מחדש',
      );
    });

    test('close() משחרר את ה-state — אתחול עוקב יוצר instance חדש', () async {
      final first = await UserBooksDatabaseHolder.instance.repository;

      await UserBooksDatabaseHolder.instance.close();

      final second = await UserBooksDatabaseHolder.instance.repository;

      expect(
        identical(first, second),
        isFalse,
        reason: 'אחרי close, האתחול הבא מייצר repository חדש',
      );
    });

    test(
      'resolveDbPath מחזיר נתיב legacy קיים תחת data_root/databases',
      () async {
        await Directory(
          path.join(tempDir.path, 'databases'),
        ).create(recursive: true);

        final dbPath = await UserBooksDatabaseHolder.resolveDbPath();

        expect(
          dbPath,
          path.join(tempDir.path, 'databases', 'user_books.db'),
        );
      },
    );

    test('resolveDbPath ממקם התקנה חדשה ליד תיקיית הספרייה', () async {
      final libraryRoot = await Directory.systemTemp.createTemp(
        'otzaria-uddh-library-',
      );
      addTearDown(() async {
        if (await libraryRoot.exists()) {
          await libraryRoot.delete(recursive: true);
        }
      });

      await Settings.setValue(
        SettingsRepository.keyLibraryPath,
        path.join(libraryRoot.path, 'books'),
      );

      final dbPath = await UserBooksDatabaseHolder.resolveDbPath();

      expect(
        dbPath,
        path.join(libraryRoot.path, 'databases', 'user_books.db'),
      );
    });

    test(
      'recovery: כישלון אתחול מאפס את _initFuture כדי לאפשר ניסיון חוזר',
      () async {
        // יוצרים _קובץ_ בשם "databases" במקום שאמורה להיות תיקייה — זה גורם
        // ל-`Directory.create` לזרוק כי הנתיב כבר תפוס. ה-DB לא מצליח להיפתח.
        final blocker = File(path.join(tempDir.path, 'databases'));
        await blocker.writeAsString('blocker');

        Object? firstError;
        try {
          await UserBooksDatabaseHolder.instance.repository;
        } catch (e) {
          firstError = e;
        }
        expect(
          firstError,
          isNotNull,
          reason: 'יצירת התיקייה אמורה להיכשל כי הנתיב הוא קובץ',
        );

        // מסירים את החסימה ויוצרים תיקייה תקינה במקום
        await blocker.delete();

        // ניסיון חוזר חייב להצליח, כי _initFuture אופס לאחר השגיאה.
        final repo = await UserBooksDatabaseHolder.instance.repository;
        expect(repo, isNotNull);

        // וידוא נוסף שה-DB אכן נפתח בקובץ הנכון
        final dbPath = await UserBooksDatabaseHolder.resolveDbPath();
        expect(await File(dbPath).exists(), isTrue);
      },
    );
  });
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) return value;
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }
}
