import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/user_state_slot.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/multiview/multi_view_host.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/multiview/view_window_close_flow.dart';
import 'package:otzaria/core/windowing/multiview/view_window_opener.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';

import '../../../helpers/memory_settings_cache.dart';
import '../../../test_helpers/fake_view_window.dart';

/// חלון שנסגר חוזר ב-Ctrl+Shift+T גם אחרי הפעלה מחדש (issue #5495): סגירת
/// הראשי ואחריו החלון השני הותירה בהפעלה הבאה רק את כרטיסיות האחרון.
void main() {
  late Directory tmp;
  final store = WindowSessionStore.instance;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('closed_windows_restart_');
    AppPaths.debugProfileDataRootPath = tmp.path;
    UserStateDatabase.instance.overridePath('${tmp.path}/user_state.db');
    UserStateDatabase.debugWriteInline = true;
    MultiViewMode.debugOverride = true;
  });

  tearDown(() {
    MultiViewMode.debugOverride = false;
    AppPaths.debugProfileDataRootPath = null;
    AppWindowKeys.resetForTest();
    UserStateDatabase.instance.close();
    UserStateDatabase.debugWriteInline = false;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {
      // Windows עלול להחזיק את הקובץ עוד רגע; תיקיית temp בלבד.
    }
  });

  group('closed windows survive restart for Ctrl+Shift+T (issue #5495)', () {
    /// תהליך אחד של התוכנה: מארח חלונות ו-opener משלו, על אותו מסד.
    Future<(FakeViewWindows, ViewWindowOpener)> launch(
      WidgetTester tester,
    ) async {
      final windows = FakeViewWindows(tester);
      final opener = ViewWindowOpener(
        registry: windows.registry,
        native: windows.native,
        restoreMainWindow: () async => false,
      );
      await tester.pumpWidget(
        MultiViewHost(registry: windows.registry, child: const SizedBox()),
      );
      return (windows, opener);
    }

    Future<T> settle<T>(WidgetTester tester, Future<T> future) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      return future;
    }

    Future<void> closeView(
      WidgetTester tester,
      ViewWindowOpener opener,
      FakeViewWindows windows,
      String tabsJson,
    ) async {
      final entry = windows.registry.open(size: const Size(800, 600))!;
      await tester.pump();
      await store.save(entry.slot, tabsJson: tabsJson, currentIndex: 1);
      await store.saveBounds(entry.slot, '{"b":1}');
      final closed = await settle(
        tester,
        ViewWindowCloseFlow(
          entry: entry,
          flush: () async {},
          opener: opener,
        ).run(),
      );
      expect(closed, isTrue);
      await tester.pump();
    }

    testWidgets('חלון שנסגר חוזר אחרי הפעלה מחדש עם הכרטיסיות והמסגרת', (
      tester,
    ) async {
      final (first, opener) = await launch(tester);
      await closeView(tester, opener, first, '["a","b"]');
      expect(await store.load(2), isNull, reason: 'סגירה מכוונת מוחקת סשן');

      // הפעלה מחדש: opener חדש, בלי זיכרון של ההפעלה הקודמת.
      final (second, restarted) = await launch(tester);
      expect(await settle(tester, restarted.restoreLastClosedWindow()), isTrue);
      final slot = second.registry.windows.single.slot;
      final session = (await store.load(slot))!;
      expect(session.tabsJson, '["a","b"]');
      expect(session.currentIndex, 1);
      expect(session.boundsJson, '{"b":1}');

      // שוחזר פעם אחת: אינו חוזר שוב, גם לא בהפעלה הבאה.
      expect(
        await settle(tester, restarted.restoreLastClosedWindow()),
        isFalse,
      );
      final (_, third) = await launch(tester);
      expect(await settle(tester, third.restoreLastClosedWindow()), isFalse);
    });

    testWidgets('הראשי שנסגר לפני החלון השני חוזר אחרי הפעלה מחדש', (
      tester,
    ) async {
      final (_, opener) = await launch(tester);
      await store.save(
        UserStateSlot.main,
        tabsJson: '["main1","main2"]',
        currentIndex: 0,
      );
      expect(
        await opener.beforeMainWindowHides(slot: UserStateSlot.main),
        isTrue,
      );
      expect(await store.load(UserStateSlot.main), isNull);

      final (second, restarted) = await launch(tester);
      expect(await settle(tester, restarted.restoreLastClosedWindow()), isTrue);
      final slot = second.registry.windows.single.slot;
      expect((await store.load(slot))!.tabsJson, '["main1","main2"]');
    });

    testWidgets('הראשי שהוצג שוב אינו חוזר כחלון נוסף אחרי הפעלה מחדש', (
      tester,
    ) async {
      final (_, opener) = await launch(tester);
      await store.save(
        UserStateSlot.main,
        tabsJson: '["main"]',
        currentIndex: 0,
      );
      await opener.beforeMainWindowHides(slot: UserStateSlot.main);
      expect(await opener.mainWindowShown(), isTrue);
      expect((await store.load(UserStateSlot.main))?.tabsJson, '["main"]');

      final (_, restarted) = await launch(tester);
      expect(
        await settle(tester, restarted.restoreLastClosedWindow()),
        isFalse,
      );
    });

    testWidgets('כשל בשמירת רשימת השחזור אינו מוחק את סשן החלון', (
      tester,
    ) async {
      final windows = FakeViewWindows(tester);
      final opener = ViewWindowOpener(
        registry: windows.registry,
        native: windows.native,
        sessions: _FailingClosedStore(),
        restoreMainWindow: () async => false,
      );
      await tester.pumpWidget(
        MultiViewHost(registry: windows.registry, child: const SizedBox()),
      );
      await closeView(tester, opener, windows, '["lost"]');

      // אין רשימת שחזור, ולכן השורה נשארת ותשוחזר בהפעלה הבאה.
      expect((await store.load(2))?.tabsJson, '["lost"]');
    });

    testWidgets('כשל בשמירת רשימת השחזור אינו מוחק את סשן הראשי', (
      tester,
    ) async {
      final windows = FakeViewWindows(tester);
      final opener = ViewWindowOpener(
        registry: windows.registry,
        native: windows.native,
        sessions: _FailingClosedStore(),
        restoreMainWindow: () async => false,
      );
      await tester.pumpWidget(
        MultiViewHost(registry: windows.registry, child: const SizedBox()),
      );
      await store.save(
        UserStateSlot.main,
        tabsJson: '["main"]',
        currentIndex: 0,
      );
      expect(
        await opener.beforeMainWindowHides(slot: UserStateSlot.main),
        isFalse,
      );

      expect((await store.load(UserStateSlot.main))?.tabsJson, '["main"]');
    });

    testWidgets('נשמר סשן לאחר כשל כתיבה ופתיחת חלון חדש', (
      tester,
    ) async {
      final windows = FakeViewWindows(tester);
      final opener = ViewWindowOpener(
        registry: windows.registry,
        native: windows.native,
        sessions: _FailingClosedStore(),
      );
      await tester.pumpWidget(
        MultiViewHost(registry: windows.registry, child: const SizedBox()),
      );
      await closeView(tester, opener, windows, '["recover"]');
      expect((await store.load(2))?.tabsJson, '["recover"]');
      expect(
        await settle(tester, opener.openWindow(inheritPlacement: false)),
        isTrue,
      );
      final active = await store.load(2);
      final archived = await store.loadClosed();
      expect(
        [active?.tabsJson, ...archived.map((entry) => entry.tabsJson)],
        contains('["recover"]'),
      );
    });

    testWidgets('בקשת שחזור בזמן הסתרת הראשי משאירה את הסשן', (
      tester,
    ) async {
      final windows = FakeViewWindows(tester);
      final gated = _GatedClosedStore();
      final opener = ViewWindowOpener(
        registry: windows.registry,
        native: windows.native,
        sessions: gated,
        // The runner reports false while the main window is still visible.
        restoreMainWindow: () async => false,
      );
      await tester.pumpWidget(
        MultiViewHost(registry: windows.registry, child: const SizedBox()),
      );
      await store.save(1, tabsJson: '["recover"]', currentIndex: 0);
      final closing = opener.beforeMainWindowHides(slot: 1);
      await gated.firstCommit.future;

      final restoring = opener.restoreLastClosedWindow();
      await tester.pump();
      gated.closeMayProceed.complete();

      expect(await closing, isTrue);
      expect(await restoring, isFalse);
      final active = await store.load(1);
      final archived = await store.loadClosed();
      expect(
        [active?.tabsJson, ...archived.map((entry) => entry.tabsJson)],
        contains('["recover"]'),
      );
    });

    testWidgets('כשל SQL במחיקת השורה מבטל גם את הוספתה לרשימת השחזור', (
      tester,
    ) async {
      final (windows, opener) = await launch(tester);
      final db = await UserStateDatabase.instance.database;
      db.execute('''
        CREATE TRIGGER fail_close BEFORE DELETE ON window_sessions
        WHEN old.slot = 2 BEGIN SELECT RAISE(ABORT, 'delete failed'); END
      ''');
      await closeView(tester, opener, windows, '["kept"]');

      expect((await store.load(2))?.tabsJson, '["kept"]');
      expect(await store.loadClosed(), isEmpty);
      expect(opener.pendingRestoreForTest, {2});
      db.execute('DROP TRIGGER fail_close');
      expect(await settle(tester, opener.restoreLastClosedWindow()), isTrue);
      expect(windows.registry.windows.single.slot, 2);
      expect((await store.load(2))?.tabsJson, '["kept"]');
      expect(opener.pendingRestoreForTest, isEmpty);
    });

    testWidgets('כשל SQL בשחזור מחזיר את הרשומה לרשימה עד לניסיון חוזר', (
      tester,
    ) async {
      final (windows, opener) = await launch(tester);
      await closeView(tester, opener, windows, '["kept"]');
      final db = await UserStateDatabase.instance.database;
      db.execute('''
        CREATE TRIGGER fail_restore BEFORE INSERT ON window_sessions
        WHEN new.slot = 2 BEGIN SELECT RAISE(ABORT, 'restore failed'); END
      ''');
      expect(await settle(tester, opener.restoreLastClosedWindow()), isFalse);
      expect(await store.load(2), isNull);
      expect((await store.loadClosed()).single.tabsJson, '["kept"]');

      db.execute('DROP TRIGGER fail_restore');
      expect(await settle(tester, opener.restoreLastClosedWindow()), isTrue);
      expect((await store.load(2))?.tabsJson, '["kept"]');
      expect(await store.loadClosed(), isEmpty);
    });

    testWidgets('לפני חשיפת חלון ששוחזר קיים עותק עמיד יחיד של הסשן', (
      tester,
    ) async {
      final windows = FakeViewWindows(tester);
      final native = _FailingReveal();
      final opener = ViewWindowOpener(
        registry: windows.registry,
        native: native,
      );
      await tester.pumpWidget(
        MultiViewHost(registry: windows.registry, child: const SizedBox()),
      );
      await closeView(tester, opener, windows, '["kept"]');

      final restoring = opener.restoreLastClosedWindow();
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      expect(native.started.isCompleted, isTrue);
      expect((await store.load(2))?.tabsJson, '["kept"]');
      expect(await store.loadClosed(), isEmpty);

      native.finish.complete();
      expect(await restoring, isFalse);
      expect(await store.load(2), isNull);
      expect((await store.loadClosed()).single.tabsJson, '["kept"]');
    });

    testWidgets('כשל קריאה בסגירת הראשי משאיר את הסשן ואת אפשרות ההצגה', (
      tester,
    ) async {
      final windows = FakeViewWindows(tester);
      var activations = 0;
      final opener = ViewWindowOpener(
        registry: windows.registry,
        native: windows.native,
        sessions: _FailingMainRead(),
        restoreMainWindow: () async {
          activations++;
          return true;
        },
      );
      const slot = UserStateSlot.main;
      await store.save(slot, tabsJson: '["main"]', currentIndex: 0);

      expect(await opener.beforeMainWindowHides(slot: slot), isFalse);
      expect((await store.load(slot))?.tabsJson, '["main"]');
      expect(await opener.restoreLastClosedWindow(), isTrue);
      expect(activations, 1);
      expect((await store.load(slot))?.tabsJson, '["main"]');
      expect(await store.loadClosed(), isEmpty);
    });

    testWidgets('כשל SQL בהצגת הראשי מחדש משאיר את הארכיון עד שהכתיבה מצליחה', (
      tester,
    ) async {
      final (_, opener) = await launch(tester);
      const slot = UserStateSlot.main;
      await store.save(slot, tabsJson: '["main"]', currentIndex: 0);
      expect(await opener.beforeMainWindowHides(slot: slot), isTrue);
      final db = await UserStateDatabase.instance.database;
      db.execute('''
        CREATE TRIGGER fail_main_restore BEFORE INSERT ON window_sessions
        WHEN new.slot = 1 BEGIN SELECT RAISE(ABORT, 'restore failed'); END
      ''');

      expect(await opener.mainWindowShown(), isFalse);
      expect(await store.load(slot), isNull);
      expect((await store.loadClosed()).single.tabsJson, '["main"]');

      db.execute('DROP TRIGGER fail_main_restore');
      expect(await opener.mainWindowShown(), isTrue);
      expect((await store.load(slot))?.tabsJson, '["main"]');
      expect(await store.loadClosed(), isEmpty);
    });

    testWidgets('מספר החלונות שנזכרים מוגבל גם בין הפעלות', (tester) async {
      final (first, opener) = await launch(tester);
      for (var i = 0; i <= ViewWindowOpener.closedLimit; i++) {
        await closeView(tester, opener, first, '["w$i"]');
      }
      final (_, restarted) = await launch(tester);
      await settle(tester, restarted.restoreLastClosedWindow());
      expect(restarted.closedCountForTest, ViewWindowOpener.closedLimit - 1);
    });
  });
}

/// מסד שבו כתיבת רשימת החלונות שנסגרו נכשלת (דיסק מלא, קובץ נעול).
class _FailingClosedStore extends WindowSessionStore {
  @override
  Future<void> saveClosed(
    List<WindowSession> sessions, {
    int? removeSlot,
    WindowSession? activate,
  }) async => throw const FileSystemException('disk full');
}

class _GatedClosedStore extends WindowSessionStore {
  final firstCommit = Completer<void>();
  final closeMayProceed = Completer<void>();

  @override
  Future<void> saveClosed(
    List<WindowSession> sessions, {
    int? removeSlot,
    WindowSession? activate,
  }) async {
    await super.saveClosed(
      sessions,
      removeSlot: removeSlot,
      activate: activate,
    );
    if (!firstCommit.isCompleted) {
      firstCommit.complete();
      await closeMayProceed.future;
    }
  }
}

class _FailingReveal extends FakeViewWindowNative {
  final started = Completer<void>();
  final finish = Completer<void>();

  @override
  Future<void> reveal(int hwnd) async {
    started.complete();
    await finish.future;
    throw StateError('reveal failed');
  }
}

class _FailingMainRead extends WindowSessionStore {
  @override
  Future<List<WindowSession>> loadClosed() async =>
      throw StateError('history read failed');

  @override
  Future<WindowSession?> load(int slot) async {
    if (slot == UserStateSlot.main) throw StateError('session read failed');
    return super.load(slot);
  }
}
