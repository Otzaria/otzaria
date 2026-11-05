import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/sqlite_memory_release.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/data/data_providers/cache_database_holder.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SqliteMemoryPressureObserver', () {
    testWidgets('מעבר לרקע אינו דוחה לחץ שכבר ממתין', (tester) async {
      var calls = 0;
      final observer = SqliteMemoryPressureObserver(
        release: () async => calls++,
      );
      addTearDown(observer.dispose);
      observer.didHaveMemoryPressure();
      observer.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets('לחץ ראשון אחרי פינוי רקע אינו ממתין ל-cooldown', (
      tester,
    ) async {
      final background = Completer<void>();
      var calls = 0;
      final observer = SqliteMemoryPressureObserver(
        release: () {
          calls++;
          return calls == 1 ? background.future : Future<void>.value();
        },
        isBusy: () => false,
        windowCount: () => 1,
        now: tester.binding.clock.now,
      );
      addTearDown(observer.dispose);
      observer.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await tester.pump(const Duration(seconds: 5));
      expect(calls, 1);
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      observer.didHaveMemoryPressure();
      background.complete();
      await tester.pump();
      await tester.pump();
      expect(calls, 2);
    });

    testWidgets('לחץ זיכרון משחרר גם בזמן פעילות ועם כמה חלונות', (
      tester,
    ) async {
      var calls = 0;
      final observer = SqliteMemoryPressureObserver(
        release: () async => calls++,
        isBusy: () => true,
        windowCount: () => 3,
      );
      addTearDown(observer.dispose);
      observer.didHaveMemoryPressure();
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets('פינוי רקע ממתין לשקט ומאחד hidden ו-paused', (tester) async {
      var busy = true;
      var calls = 0;
      final observer = SqliteMemoryPressureObserver(
        release: () async => calls++,
        isBusy: () => busy,
        windowCount: () => 1,
      );
      addTearDown(observer.dispose);
      observer.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await tester.pump(const Duration(seconds: 10));
      expect(calls, 0);
      observer.didChangeAppLifecycleState(AppLifecycleState.hidden);
      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 5));
      expect(calls, 0);
      busy = false;
      await tester.pump(const Duration(seconds: 2));
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 20));
      expect(calls, 1);
    });

    testWidgets('חזרה לחזית מבטלת פינוי רקע שטרם החל', (tester) async {
      var calls = 0;
      final observer = SqliteMemoryPressureObserver(
        release: () async => calls++,
        isBusy: () => false,
        windowCount: () => 1,
      );
      addTearDown(observer.dispose);
      observer.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await tester.pump(const Duration(seconds: 2));
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 10));
      expect(calls, 0);
    });

    testWidgets('חלון נוסף מונע פינוי יזום של מטמונים משותפים', (tester) async {
      var calls = 0;
      final observer = SqliteMemoryPressureObserver(
        release: () async => calls++,
        isBusy: () => false,
        windowCount: () => 2,
      );
      addTearDown(observer.dispose);
      observer.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await tester.pump(const Duration(seconds: 5));
      expect(calls, 0);
      observer.didHaveMemoryPressure();
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets('לחץ חוזר מוגבל למעבר יחיד בכל מרווח', (tester) async {
      var calls = 0;
      final observer = SqliteMemoryPressureObserver(
        release: () async => calls++,
        now: tester.binding.clock.now,
      );
      addTearDown(observer.dispose);
      observer.didHaveMemoryPressure();
      await tester.pump();
      for (var i = 0; i < 50; i++) {
        observer.didHaveMemoryPressure();
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 2);
    });

    testWidgets('פינוי תקוע אינו משחרר slot; לחץ ממתין לסיום האמיתי', (
      tester,
    ) async {
      final gate = Completer<void>();
      var calls = 0;
      final observer = SqliteMemoryPressureObserver(
        release: () {
          calls++;
          return calls == 1 ? gate.future : Future<void>.value();
        },
        now: tester.binding.clock.now,
      );
      addTearDown(observer.dispose);
      observer.didHaveMemoryPressure();
      await tester.pump();
      observer.didHaveMemoryPressure();
      await tester.pump(const Duration(minutes: 2));
      expect(calls, 1);
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(calls, 2);
    });

    testWidgets('כשל סינכרוני אינו מרעיל ניסיון פינוי נוסף', (tester) async {
      var calls = 0;
      final observer = SqliteMemoryPressureObserver(
        release: () {
          calls++;
          if (calls == 1) throw StateError('injected');
          return Future<void>.value();
        },
        now: tester.binding.clock.now,
      );
      addTearDown(observer.dispose);
      observer.didHaveMemoryPressure();
      await tester.pump();
      observer.didHaveMemoryPressure();
      await tester.pump(const Duration(seconds: 2));
      expect(calls, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dispose מבטל תזמון ואירועים מאוחרים', (tester) async {
      var calls = 0;
      final observer = SqliteMemoryPressureObserver(
        release: () async => calls++,
      );
      observer.didHaveMemoryPressure();
      observer.dispose();
      observer.didHaveMemoryPressure();
      await tester.pump(const Duration(minutes: 1));
      expect(calls, 0);
    });
  });

  test('releaseSqliteMemory לא פותח חיבורים סגורים', () async {
    await releaseSqliteMemory();

    expect(SqliteDataProvider.instance.repository, isNull);
    expect(CacheDatabaseHolder.instance.repositoryIfInitialized, isNull);
    expect(UserBooksDatabaseHolder.instance.repositoryIfInitialized, isNull);
    expect(UserStateDatabase.instance.openDatabase, isNull);
    expect(PersonalNotesDatabase.instance.openDatabase, isNull);
    expect(PluginSystemDatabase.instance.openDatabase, isNull);
  });

  test('shrinkMemoryIfOpen רץ רק על חיבור פתוח ואינו פותח', () async {
    final dir = Directory.systemTemp.createTempSync('shrink_memory');
    addTearDown(() => dir.deleteSync(recursive: true));
    final database = MyDatabase.withPath(p.join(dir.path, 'cache.db'));

    expect(database.shrinkMemoryIfOpen(), isFalse);
    expect(database.isOpen, isFalse);

    await database.database;
    expect(database.shrinkMemoryIfOpen(), isTrue);

    database.close();
    expect(database.shrinkMemoryIfOpen(), isFalse);
    expect(database.isOpen, isFalse);
  });
}
