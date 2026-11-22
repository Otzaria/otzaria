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
          discardSession: store.delete,
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
      // כמו AppWindowListener: הסשן נמחק, ואז הראשי מוסתר.
      final discarded = await store.load(UserStateSlot.main);
      await store.delete(UserStateSlot.main);
      await opener.beforeMainWindowHides(session: discarded);

      final (second, restarted) = await launch(tester);
      expect(await settle(tester, restarted.restoreLastClosedWindow()), isTrue);
      final slot = second.registry.windows.single.slot;
      expect((await store.load(slot))!.tabsJson, '["main1","main2"]');
    });

    testWidgets('הראשי שהוצג שוב אינו חוזר כחלון נוסף אחרי הפעלה מחדש', (
      tester,
    ) async {
      final (_, opener) = await launch(tester);
      await opener.beforeMainWindowHides(
        session: const WindowSession(
          slot: UserStateSlot.main,
          tabsJson: '["main"]',
          currentIndex: 0,
        ),
      );
      opener.mainWindowShown();
      await tester.pump();

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
      // כמו AppWindowListener בסגירת הראשי כשחלון אחר נשאר פתוח.
      final discarded = await store.load(UserStateSlot.main);
      await store.delete(UserStateSlot.main);
      await opener.beforeMainWindowHides(session: discarded);

      expect((await store.load(UserStateSlot.main))?.tabsJson, '["main"]');
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
  Future<void> saveClosed(List<WindowSession> sessions) async =>
      throw const FileSystemException('disk full');
}
