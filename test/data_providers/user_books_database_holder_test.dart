import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';

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

    test('close מודיע למאזינים פעם אחת לכל מאזין', () async {
      var calls = 0;
      void listener() => calls++;
      UserBooksDatabaseHolder.instance
        ..addCloseListener(listener)
        ..addCloseListener(listener);

      await UserBooksDatabaseHolder.instance.close();
      expect(calls, 1);
    });

    test('close ממתין גם לקריאה שטרם פתחה את המסד', () async {
      final holder = UserBooksDatabaseHolder.instance;
      final ready = Completer<void>();
      final finish = Completer<void>();
      final read = holder.trackRead(() async {
        await ready.future;
        await holder.repository;
        await finish.future;
      });
      var closed = false;
      final closing = holder.close().then((_) => closed = true);
      ready.complete();
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      finish.complete();
      await Future.wait([read, closing]);
      expect(holder.openDbPath, isNull);
    });

    test('קריאה שמתחילה במהלך close אינה פותחת חיבור נוסף', () async {
      final holder = UserBooksDatabaseHolder.instance;
      final finish = Completer<void>();
      final read = holder.trackRead(() => finish.future);
      final closing = holder.close();
      var started = false;
      await holder.trackRead(() async {
        started = true;
        await holder.repository;
      });
      expect(started, isFalse);
      expect(holder.openDbPath, isNull);
      finish.complete();
      await Future.wait([read, closing]);
      await holder.trackRead(() async {
        started = true;
        await holder.repository;
      });
      expect(started, isTrue);
      expect(holder.openDbPath, isNotNull);
    });

    test('כשל בקריאה מדווח לקורא ומשחרר את ההמתנה לסגירה', () async {
      final holder = UserBooksDatabaseHolder.instance;
      final finish = Completer<void>();
      final read = holder.trackRead(() => finish.future);
      final failed = expectLater(read, throwsStateError);
      final closing = holder.close();
      finish.completeError(StateError('read failed'));
      await Future.wait([failed, closing]);
      expect(holder.openDbPath, isNull);
    });

    test('close ממתין לאתחול שכבר התחיל ולא משאיר חיבור פתוח', () async {
      final holder = UserBooksDatabaseHolder.instance;
      final initializing = holder.repository;
      final closing = holder.close();
      await Future.wait([initializing, closing]);
      expect(holder.openDbPath, isNull);
      expect(holder.repositoryIfInitialized, isNull);
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

    test('close() ממזג את ה-WAL גם כשחיבור אחר עדיין פתוח', () async {
      final repo = await UserBooksDatabaseHolder.instance.repository;
      final db = await repo.database.database;
      db.execute('CREATE TABLE wal_probe(x INTEGER)');
      db.execute('INSERT INTO wal_probe VALUES (1)');

      final dbPath = await UserBooksDatabaseHolder.resolveDbPath();
      // חיבור של חלון מוסתר: בזכותו הסגירה אינה האחרונה.
      final other = sqlite3.open(dbPath);
      addTearDown(other.close);
      other.select('SELECT 1');

      await UserBooksDatabaseHolder.instance.close();

      final wal = File('$dbPath-wal');
      expect(
        !wal.existsSync() || wal.lengthSync() == 0,
        isTrue,
        reason: 'השינויים חייבים להיכנס לקובץ הראשי בסגירה',
      );
    });

    test('close() אינו חוסם את ה-isolate כשכותב אחר מחזיק את המסד', () async {
      final repo = await UserBooksDatabaseHolder.instance.repository;
      final db = await repo.database.database;
      db.execute('CREATE TABLE wal_probe(x INTEGER)');
      db.execute('INSERT INTO wal_probe VALUES (1)');

      final dbPath = await UserBooksDatabaseHolder.resolveDbPath();
      // כותב מקביל (סנכרון התיקיות ב-isolate) מחזיק את נעילת הכתיבה.
      final writer = sqlite3.open(dbPath)..execute('BEGIN IMMEDIATE');
      addTearDown(writer.close);

      final stopwatch = Stopwatch()..start();
      final closing = UserBooksDatabaseHolder.instance.close();
      final timerDelay = await Future<Duration>.delayed(
        const Duration(milliseconds: 100),
        () => stopwatch.elapsed,
      );
      // בקשה בזמן הסגירה ממתינה לסופה ולא פותחת את הקובץ מחדש באמצע.
      final reopening = UserBooksDatabaseHolder.instance.repository;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      writer.execute('ROLLBACK');
      await closing;
      expect(UserBooksDatabaseHolder.instance.openDbPath, isNull);
      final wal = File('$dbPath-wal');
      expect(!wal.existsSync() || wal.lengthSync() == 0, isTrue);
      expect(timerDelay, lessThan(const Duration(seconds: 2)));
      await reopening;
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
