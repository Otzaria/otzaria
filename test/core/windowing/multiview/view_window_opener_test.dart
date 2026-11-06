import 'dart:async';
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/material.dart';
import 'package:otzaria/core/windowing/multiview/cocoa_view_window_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/user_state/window_bounds.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/window_persistence.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/multiview/multi_view_host.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/multiview/view_focus_sync.dart';
import 'package:otzaria/core/windowing/multiview/view_window_close_flow.dart';
import 'package:otzaria/core/windowing/multiview/view_window_opener.dart';
import 'package:otzaria/core/windowing/multiview/view_window_registry.dart';
import 'package:otzaria/core/windowing/window_opener.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';

import '../../../test_helpers/fake_view_window.dart';
import '../../../test_helpers/memory_cache_provider.dart';

/// סשנים בזיכרון: בלי קובץ אמיתי בתוך FakeAsync.
class _MemorySessions extends WindowSessionStore {
  final Map<int, WindowSession> rows = {};
  final List<int> boundsWrites = [];

  @override
  Future<void> save(
    int slot, {
    required String tabsJson,
    required int currentIndex,
  }) async {
    final old = rows[slot];
    rows[slot] = WindowSession(
      slot: slot,
      tabsJson: tabsJson,
      currentIndex: currentIndex,
      activeWorkspaceId: old?.activeWorkspaceId,
      boundsJson: old?.boundsJson,
    );
  }

  WindowSession _row(int slot) =>
      rows[slot] ?? WindowSession(slot: slot, tabsJson: '[]', currentIndex: 0);

  @override
  Future<void> saveActiveWorkspace(int slot, String? workspaceId) async {
    final old = _row(slot);
    rows[slot] = WindowSession(
      slot: slot,
      tabsJson: old.tabsJson,
      currentIndex: old.currentIndex,
      activeWorkspaceId: workspaceId,
      boundsJson: old.boundsJson,
    );
  }

  @override
  Future<void> saveBounds(int slot, String? boundsJson) async {
    boundsWrites.add(slot);
    final old = _row(slot);
    rows[slot] = WindowSession(
      slot: slot,
      tabsJson: old.tabsJson,
      currentIndex: old.currentIndex,
      activeWorkspaceId: old.activeWorkspaceId,
      boundsJson: boundsJson,
    );
  }

  @override
  Future<String?> loadBoundsJson(int slot) async => rows[slot]?.boundsJson;

  @override
  Future<WindowSession?> load(int slot) async => rows[slot];

  @override
  Future<void> delete(int slot) async => rows.remove(slot);
}

/// מסך עם DPI אחר: ההזזה הראשונה מגדילה את החלון, כמו WM_DPICHANGED.
class _DpiChangeNative extends FakeViewWindowNative {
  final Set<int> _moved = {};

  @override
  void setWindowRect(int hwnd, Rect rect) => super.setWindowRect(
    hwnd,
    _moved.add(hwnd)
        ? Rect.fromLTWH(rect.left, rect.top, rect.width * 1.5, rect.height)
        : rect,
  );
}

class _GatedRevealNative extends FakeViewWindowNative {
  final revealStarted = Completer<void>();
  final allowReveal = Completer<void>();

  @override
  Future<void> reveal(int hwnd) async {
    revealStarted.complete();
    await allowReveal.future;
    await super.reveal(hwnd);
  }
}

/// מסד שהמחיקה בו נכשלת (נעול, למשל).
class _FailingDeleteSessions extends _MemorySessions {
  @override
  Future<void> delete(int slot) async => throw StateError('locked');
}

class _ToggleDeleteSessions extends _MemorySessions {
  bool failDelete = false;
  @override
  Future<void> delete(int slot) async {
    if (failDelete) throw StateError('locked');
    await super.delete(slot);
  }
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() => MultiViewMode.debugOverride = true);

  tearDown(() {
    MultiViewMode.debugOverride = false;
    WindowOpener.debugOverride = null;
    AppWindowKeys.resetForTest();
  });

  late FakeViewWindows windows;
  late _MemorySessions sessions;
  late bool mainVisible;
  late int mainRestores;
  late bool mainRestoreResult;
  late int mainShows;

  ViewWindowOpener makeOpener(
    WidgetTester tester, {
    Duration? timeout,
    FakeViewWindowNative? native,
    _MemorySessions? store,
    int? mainHwnd,
    bool mainFullscreen = false,
    bool keepsProcess = false,
  }) {
    windows = FakeViewWindows(tester);
    sessions = store ?? _MemorySessions();
    mainVisible = true;
    mainRestores = 0;
    mainRestoreResult = true;
    mainShows = 0;
    return ViewWindowOpener(
      registry: windows.registry,
      native: native ?? windows.native,
      sessions: sessions,
      isMainWindowVisible: () async => mainVisible,
      restoreMainWindow: () async {
        mainRestores++;
        return mainRestoreResult;
      },
      showMainWindow: () async => mainShows++,
      keepsProcessAfterLastWindow: keepsProcess,
      defaultSize: () => const Size(1000, 700),
      mainWindowHwnd: () async => mainHwnd,
      isMainWindowFullscreen: () async => mainFullscreen,
      firstFrameTimeout: timeout ?? const Duration(seconds: 20),
    );
  }

  Future<void> pumpHost(WidgetTester tester) => tester.pumpWidget(
    MultiViewHost(registry: windows.registry, child: const SizedBox()),
  );

  /// מריץ פעולה עד שהחלון שלה מצייר פריים ראשון.
  Future<T> settle<T>(WidgetTester tester, Future<T> future) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    return future;
  }

  testWidgets('בלי בעלים נשארים בחלון יחיד, ולעולם לא פותחים מנוע נוסף', (
    tester,
  ) async {
    expect(WindowOpener.current, same(ViewWindowOpener.instance));
    MultiViewMode.debugOverride = false;
    expect(WindowOpener.current, same(ViewWindowOpener.instance));
    MultiViewMode.debugOverride = null;
    expect(WindowOpener.current, same(ViewWindowOpener.instance));
  });

  testWidgets('בלי בעלים לחלונות Dart לא נפתח שום חלון', (tester) async {
    final opener = makeOpener(tester);
    await pumpHost(tester);
    // תחת binding של בדיקות הבעלים אינו מותקן, כמו ב-integration_test.
    MultiViewMode.debugOverride = null;

    expect(await opener.canOpenAnotherWindow(), isFalse);
    expect(await opener.openWindow(), isFalse);
    // חלון יחיד: האפשרות מוסתרת, ולכן גם אין הודעה.
    expect(await opener.openEmptyWindow(), isFalse);
    expect(windows.registry.windows, isEmpty);
  });

  testWidgets('openWindow: חלון עם כרטיסיה, שארית במשבצת נמחקת', (
    tester,
  ) async {
    final opener = makeOpener(tester);
    await pumpHost(tester);
    sessions.rows[2] = const WindowSession(
      slot: 2,
      tabsJson: '[{"stale":true}]',
      currentIndex: 0,
    );
    final tab = ToolTab(toolId: 'calendar', title: 'לוח שנה');

    expect(await settle(tester, opener.openWindow(tab: tab)), isTrue);

    final entry = windows.registry.windows.single;
    expect(entry.slot, 2);
    expect(entry.openedWithTab, isTrue);
    expect(sessions.rows[2], isNull, reason: 'שארית מקריסה אינה נטענת');
    expect(windows.native.hooked, [windows.handleOf(entry).fakeHwnd]);
    expect(windows.native.frameless, [windows.handleOf(entry).fakeHwnd]);
    final count = (await opener.windowCount())!;
    expect((count.count, count.max), (2, 8));
  });

  testWidgets('openWindow: החלון מקבל עותק, ושחרור המקור אינו סוגר אותו', (
    tester,
  ) async {
    final opener = makeOpener(tester);
    await pumpHost(tester);
    final source = TextBookTab(book: TextBook(title: 'בראשית'), index: 12);

    expect(await settle(tester, opener.openWindow(tab: source)), isTrue);
    final moved = windows.registry.windows.single.takeInitialTab();

    // כמו `RemoveTab` במקור אחרי שהחלון נפתח.
    source.dispose();
    expect(moved, isA<TextBookTab>());
    expect(moved, isNot(same(source)));
    final text = moved! as TextBookTab;
    expect(text.index, 12);
    expect(text.bloc.isClosed, isFalse, reason: 'BUG-1: ספינר אינסופי');
    text.dispose();
  });

  testWidgets('מיקום לפני הפריים הראשון: מסגרת, מסגרת קטנה מדי, פינה', (
    tester,
  ) async {
    final opener = makeOpener(tester);
    await pumpHost(tester);
    windows.native.area = const Rect.fromLTWH(0, 0, 1920, 1040);

    expect(
      await settle(
        tester,
        opener.openWindow(
          bounds: (left: 960, top: 0, width: 960, height: 1040),
        ),
      ),
      isTrue,
    );
    expect(windows.native.rects[100], const Rect.fromLTWH(960, 0, 960, 1040));

    // תצוגת גרירה בגודל כרטיסיה אינה מסגרת חלון.
    expect(
      await settle(
        tester,
        opener.openWindow(bounds: (left: 5, top: 5, width: 176, height: 40)),
      ),
      isTrue,
    );
    expect(windows.native.rects[101], isNull);

    // פינה בקצה המסך: הגודל נשמר והחלון מהודק לאזור העבודה.
    windows.native.rects[102] = const Rect.fromLTWH(0, 0, 1000, 700);
    expect(
      await settle(tester, opener.openWindow(origin: (x: 1500, y: 900))),
      isTrue,
    );
    expect(windows.native.rects[102], const Rect.fromLTWH(920, 340, 1000, 700));
  });

  group('חלון חדש בלי מסגרת שמורה: לפי המסגרת החיצונית של המקור', () {
    const main = 1;

    testWidgets('גודל הראשי ומדרג של 30 לוגיים', (tester) async {
      final opener = makeOpener(tester, mainHwnd: main);
      await pumpHost(tester);
      windows.native.area = const Rect.fromLTWH(0, 0, 1920, 1040);
      windows.native.rects[main] = const Rect.fromLTWH(100, 50, 1200, 800);

      expect(await settle(tester, opener.openWindow()), isTrue);
      expect(
        windows.native.rects[100],
        const Rect.fromLTWH(130, 80, 1200, 800),
      );
      expect(windows.handles.single.stub.maximized, isFalse);
    });

    testWidgets('DPI 144: המדרג 45 פיזיים', (tester) async {
      final opener = makeOpener(tester, mainHwnd: main);
      await pumpHost(tester);
      windows.native.dpi = 144;
      windows.native.rects[main] = const Rect.fromLTWH(100, 50, 1200, 800);

      expect(await settle(tester, opener.openWindow()), isTrue);
      expect(
        windows.native.rects[100],
        const Rect.fromLTWH(145, 95, 1200, 800),
      );
    });

    testWidgets('ראשי במסך מלא פותח חלון ממוקסם', (tester) async {
      final opener = makeOpener(tester, mainHwnd: main, mainFullscreen: true);
      await pumpHost(tester);
      windows.native.rects[main] = const Rect.fromLTWH(0, 0, 1920, 1080);

      expect(await settle(tester, opener.openWindow()), isTrue);
      expect(windows.handles.single.stub.maximized, isTrue);
      expect(windows.handles.single.stub.fullscreen, isFalse);
    });

    testWidgets('ראשי בגובה מלא: חוזר לפינת אזור העבודה ואינו גולש', (
      tester,
    ) async {
      final opener = makeOpener(tester, mainHwnd: main);
      await pumpHost(tester);
      windows.native.area = const Rect.fromLTWH(0, 0, 1920, 1040);
      windows.native.rects[main] = const Rect.fromLTWH(200, 0, 1000, 1040);

      expect(await settle(tester, opener.openWindow()), isTrue);
      expect(windows.native.rects[100], const Rect.fromLTWH(0, 0, 1000, 1040));
    });

    testWidgets('מקור גדול מאזור העבודה: מוקטן אליו', (tester) async {
      final opener = makeOpener(tester, mainHwnd: main);
      await pumpHost(tester);
      windows.native.area = const Rect.fromLTWH(0, 0, 1920, 1040);
      windows.native.rects[main] = const Rect.fromLTWH(-8, -8, 1936, 1056);

      expect(await settle(tester, opener.openWindow()), isTrue);
      expect(windows.native.rects[100], const Rect.fromLTWH(0, 0, 1920, 1040));
    });

    testWidgets('ראשי ממוקסם: החדש ממוקסם, מסגרתו הרגילה מדורגת', (
      tester,
    ) async {
      final opener = makeOpener(tester, mainHwnd: main);
      await pumpHost(tester);
      windows.native.rects[main] = const Rect.fromLTWH(100, 50, 1200, 800);
      windows.native.maximizedWindows.add(main);

      expect(await settle(tester, opener.openWindow()), isTrue);
      expect(
        windows.native.rects[100],
        const Rect.fromLTWH(130, 80, 1200, 800),
      );
      expect(windows.handles.single.stub.maximized, isTrue);
    });

    testWidgets('חלון Dart בחזית הוא המקור', (tester) async {
      final opener = makeOpener(tester, mainHwnd: main);
      await pumpHost(tester);
      windows.native.rects[main] = const Rect.fromLTWH(100, 50, 1200, 800);
      expect(await settle(tester, opener.openWindow()), isTrue);
      windows.native.rects[100] = const Rect.fromLTWH(500, 300, 900, 600);
      windows.native.foreground = 100;

      expect(await settle(tester, opener.openWindow()), isTrue);
      expect(
        windows.native.rects[101],
        const Rect.fromLTWH(530, 330, 900, 600),
      );

      // חלון זר בחזית: חוזרים לראשי.
      windows.native.foreground = 999;
      expect(await settle(tester, opener.openWindow()), isTrue);
      expect(
        windows.native.rects[102],
        const Rect.fromLTWH(130, 80, 1200, 800),
      );
    });

    testWidgets('חלון Dart במסך מלא פותח חלון ממוקסם בלי להוריש מסך מלא', (
      tester,
    ) async {
      final opener = makeOpener(tester);
      await pumpHost(tester);
      expect(await settle(tester, opener.openWindow()), isTrue);
      final source = windows.handles.single;
      source.stub.fullscreen = true;
      windows.native.foreground = source.fakeHwnd;
      windows.native.rects[source.fakeHwnd!] = const Rect.fromLTWH(
        0,
        0,
        1920,
        1080,
      );

      expect(await settle(tester, opener.openWindow()), isTrue);
      expect(windows.handles.last.stub.maximized, isTrue);
      expect(windows.handles.last.stub.fullscreen, isFalse);
    });

    testWidgets('גרירה לנקודה: גודל המקור, מהודק ומוקטן לאזור העבודה', (
      tester,
    ) async {
      final opener = makeOpener(tester, mainHwnd: main);
      await pumpHost(tester);
      windows.native.area = const Rect.fromLTWH(0, 0, 1920, 1040);
      windows.native.rects[main] = const Rect.fromLTWH(0, 0, 1200, 1100);
      windows.native.maximizedWindows.add(main);

      expect(
        await settle(tester, opener.openWindow(origin: (x: 1500, y: 300))),
        isTrue,
      );
      expect(
        windows.native.rects[100],
        const Rect.fromLTWH(720, 0, 1200, 1040),
      );
      expect(windows.handles.single.stub.maximized, isFalse);
    });

    testWidgets('מסגרת שמורה: כפי שהיא, בלי מדרג ובלי לשאול את המקור', (
      tester,
    ) async {
      final opener = makeOpener(tester, mainHwnd: main);
      await pumpHost(tester);
      windows.native.rects[main] = const Rect.fromLTWH(100, 50, 1200, 800);
      windows.native.maximizedWindows.add(main);
      sessions.rows[2] = WindowSession(
        slot: 2,
        tabsJson: '[]',
        currentIndex: 0,
        boundsJson: const WindowBounds(
          left: 10,
          top: 20,
          width: 800,
          height: 600,
        ).encode(),
      );

      await settle(tester, opener.restoreAllWindows([2]));
      expect(windows.native.rects[100], const Rect.fromLTWH(10, 20, 800, 600));
      expect(windows.handles.single.stub.maximized, isFalse);

      expect(
        await settle(
          tester,
          opener.openWindow(
            bounds: (left: 960, top: 0, width: 960, height: 1040),
          ),
        ),
        isTrue,
      );
      expect(windows.native.rects[101], const Rect.fromLTWH(960, 0, 960, 1040));
      expect(windows.handles.last.stub.maximized, isFalse);
    });

    testWidgets('inheritPlacement: false — בלי מדרג ובלי מיקסום מהמקור', (
      tester,
    ) async {
      final opener = makeOpener(tester, mainHwnd: main);
      await pumpHost(tester);
      windows.native.rects[main] = const Rect.fromLTWH(100, 50, 1200, 800);
      windows.native.maximizedWindows.add(main);

      expect(
        await settle(tester, opener.openWindow(inheritPlacement: false)),
        isTrue,
      );
      expect(
        windows.native.rects[100],
        isNot(const Rect.fromLTWH(130, 80, 1200, 800)),
      );
      expect(windows.handles.single.stub.maximized, isFalse);
    });
  });

  testWidgets('clampToArea: מזיז פנימה, ומקטין רק מה שאינו נכנס', (
    tester,
  ) async {
    const area = Rect.fromLTWH(0, 0, 1920, 1040);
    expect(
      ViewWindowOpener.clampToArea(
        const Rect.fromLTWH(1500, 900, 1000, 700),
        area,
      ),
      const Rect.fromLTWH(920, 340, 1000, 700),
    );
    expect(
      ViewWindowOpener.clampToArea(
        const Rect.fromLTWH(100, 100, 2000, 1100),
        area,
      ),
      const Rect.fromLTWH(0, 0, 1920, 1040),
    );
  });

  testWidgets('תקרה: 8 כולל הראשי; משבצת שהתפנתה נלקחת שוב', (tester) async {
    final opener = makeOpener(tester);
    await pumpHost(tester);
    for (var i = 0; i < 7; i++) {
      expect(await settle(tester, opener.openWindow()), isTrue);
    }
    expect(await opener.canOpenAnotherWindow(), isFalse);
    expect(await settle(tester, opener.openWindow()), isFalse);
    final count = (await opener.windowCount())!;
    expect(count.count >= count.max, isTrue, reason: 'הודעת התקרה');

    final slot3 = windows.registry.windows.firstWhere((w) => w.slot == 3);
    windows.stubOf(slot3).destroy();
    await tester.pump();
    expect(await settle(tester, opener.openWindow()), isTrue);
    expect(windows.registry.windows.last.slot, 3);
  });

  testWidgets('פריים ראשון שלא הגיע: false, החלון נהרס והסשן נמחק', (
    tester,
  ) async {
    final opener = makeOpener(tester, timeout: const Duration(seconds: 1));
    // בלי MultiViewHost אין מי שיצייר את החלון.
    await tester.pumpWidget(const SizedBox());
    final future = opener.openWindow();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(await future, isFalse);
    expect(windows.handles.single.stub.destroyed, isTrue);
    expect(windows.registry.windows, isEmpty);
    expect(sessions.rows[2], isNull);
  });

  testWidgets('שחזור כל החלונות: משבצת וגבולות שמורים; פתיחה במקביל לא גונבת', (
    tester,
  ) async {
    final opener = makeOpener(tester);
    await pumpHost(tester);
    sessions.rows[2] = WindowSession(
      slot: 2,
      tabsJson: '[]',
      currentIndex: 0,
      boundsJson: const WindowBounds(
        left: 10,
        top: 20,
        width: 800,
        height: 600,
        dpr: 1.5,
      ).encode(),
    );
    sessions.rows[3] = WindowSession(
      slot: 3,
      tabsJson: '[]',
      currentIndex: 0,
      boundsJson: const WindowBounds(maximized: true).encode(),
    );

    final restore = opener.restoreAllWindows([2, 3]);
    final fresh = opener.openWindow();
    await settle(tester, restore);
    expect(await settle(tester, fresh), isTrue);

    final bySlot = {for (final w in windows.registry.windows) w.slot: w};
    expect(bySlot.keys.toSet(), {2, 3, 4});
    expect(sessions.rows[2], isNotNull, reason: 'הסשן שוחזר ולא נמחק');
    expect(sessions.rows[3], isNotNull);
    expect(
      windows.native.rects[windows.handleOf(bySlot[2]!).fakeHwnd],
      const Rect.fromLTWH(15, 30, 1200, 900),
    );
    expect(windows.stubOf(bySlot[3]!).maximized, isTrue);
    expect(opener.pendingRestoreForTest, isEmpty);
  });

  testWidgets(
    'מעבר ממודל A: סשני משבצות 2-4 נפתחים כחלונות Dart באותן משבצות',
    (
      tester,
    ) async {
      final opener = makeOpener(tester);
      await pumpHost(tester);
      for (final slot in [2, 3, 4]) {
        sessions.rows[slot] = WindowSession(
          slot: slot,
          tabsJson: '[]',
          currentIndex: 0,
          activeWorkspaceId: 'ws$slot',
        );
      }

      await settle(tester, opener.restoreAllWindows([2, 3, 4]));

      final entries = windows.registry.windows;
      expect(entries.map((w) => w.slot), [2, 3, 4]);
      for (final entry in entries) {
        // הסשן, השולחן והגבולות של החלון נקראים ונכתבים לפי אותה משבצת.
        expect(entry.tabsSession.slot, entry.slot);
        expect(entry.id.value, 'window-view-${entry.slot}');
        expect(sessions.rows[entry.slot]!.activeWorkspaceId, 'ws${entry.slot}');
      }
      expect(opener.pendingRestoreForTest, isEmpty);
    },
  );

  testWidgets('הסתרת הראשי ממתינה לחשיפה הנייטיבית, מעבר לפריים הראשון', (
    tester,
  ) async {
    final native = _GatedRevealNative();
    final opener = makeOpener(tester, native: native);
    await pumpHost(tester);
    final opened = opener.openWindow();
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(native.revealStarted.isCompleted, isTrue);
    var canHide = false;
    final hide = opener.beforeMainWindowHides().then((_) => canHide = true);
    await tester.pump();
    expect(canHide, isFalse);
    native.allowReveal.complete();
    await tester.pump();
    await hide;
    expect(await opened, isTrue);
    expect(native.revealed, hasLength(1));
    expect(canHide, isTrue);
  });

  testWidgets(
    'חלון שנהרס אחרי פריים ראשון ולפני אישור החשיפה אינו יעד שהצליח',
    (tester) async {
      final native = _GatedRevealNative();
      final opener = makeOpener(tester, native: native);
      await pumpHost(tester);
      final opened = opener.openWindow();
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      expect(native.revealStarted.isCompleted, isTrue);
      windows.registry.windows.single.handle.destroy();
      native.allowReveal.complete();
      await tester.pump();
      expect(await opened, isFalse);
      expect(windows.registry.windows, isEmpty);
    },
  );

  testWidgets('כשל פתיחה מסתיים לפני הסתרת הראשי ואינו משאיר חלון', (
    tester,
  ) async {
    final opener = makeOpener(tester, timeout: const Duration(seconds: 1));
    final opened = opener.openWindow();
    await tester.pump();
    final hide = opener.beforeMainWindowHides();
    await tester.pump(const Duration(seconds: 2));
    await hide;
    expect(await opened, isFalse);
    expect(windows.registry.windows, isEmpty);
  });

  for (final scenario in [
    (
      name: 'ראשי zoom',
      secondary: false,
      fullscreen: false,
      saved: true,
      legacy: false,
    ),
    (
      name: 'ראשי fullscreen',
      secondary: false,
      fullscreen: true,
      saved: true,
      legacy: false,
    ),
    (
      name: 'משני zoom',
      secondary: true,
      fullscreen: false,
      saved: true,
      legacy: false,
    ),
    (
      name: 'משני fullscreen',
      secondary: true,
      fullscreen: true,
      saved: true,
      legacy: false,
    ),
    (
      name: 'ראשי legacy',
      secondary: false,
      fullscreen: false,
      saved: false,
      legacy: true,
    ),
    (
      name: 'ראשי ללא normal שמור',
      secondary: false,
      fullscreen: true,
      saved: false,
      legacy: false,
    ),
  ]) {
    testWidgets('Cocoa expanded source: ${scenario.name}', (tester) async {
      makeOpener(tester);
      await pumpHost(tester);
      final source = scenario.secondary
          ? windows.registry.open(size: const Size(800, 600))
          : null;
      if (source != null) {
        windows.stubOf(source)
          ..maximized = !scenario.fullscreen
          ..fullscreen = scenario.fullscreen;
      }
      final sourceHandle = source?.handle.nativeHandle ?? 1;
      final slot = source?.slot ?? 1;
      const normal = WindowBounds(
        left: 100,
        top: 80,
        width: 800,
        height: 600,
        dpr: 2,
      );
      if (scenario.saved) {
        sessions.rows[slot] = WindowSession(
          slot: slot,
          tabsJson: '[]',
          currentIndex: 0,
          boundsJson: normal.encode(),
        );
      }
      if (scenario.legacy) {
        final values = {
          'window_bounds_left': 100.0,
          'window_bounds_top': 80.0,
          'window_bounds_width': 800.0,
          'window_bounds_height': 600.0,
          'window_bounds_dpr': 2.0,
        };
        for (final entry in values.entries) {
          await Settings.setValue(entry.key, entry.value);
        }
        addTearDown(() async {
          for (final key in values.keys) {
            await Settings.setValue<Object?>(key, null);
          }
        });
      }
      final frames = <int, Rect>{
        sourceHandle: const Rect.fromLTWH(0, 0, 1920, 1080),
      };
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(CocoaViewWindowNative.defaultChannel, (
        call,
      ) async {
        final args = call.arguments as Map?;
        final handle = args?['handle'] as int?;
        if (call.method == 'keyWindow') return sourceHandle;
        if (call.method == 'setFrame') {
          frames[handle!] = Rect.fromLTWH(
            args!['x'] as double,
            args['y'] as double,
            args['width'] as double,
            args['height'] as double,
          );
        }
        if (call.method == 'frame' || call.method == 'placement') {
          final rect = frames[handle] ?? const Rect.fromLTWH(0, 0, 1000, 700);
          return {
            'x': rect.left,
            'y': rect.top,
            'width': rect.width,
            'height': rect.height,
            'maximized': !scenario.fullscreen,
          };
        }
        if (call.method == 'visibleFrame') {
          return {
            'x': 0.0,
            'y': 25.0,
            'width': 1920.0,
            'height': 1015.0,
            'scale': 2.0,
          };
        }
        if (call.method == 'reveal') return true;
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          CocoaViewWindowNative.defaultChannel,
          null,
        ),
      );
      final opener = ViewWindowOpener(
        registry: windows.registry,
        native: const CocoaViewWindowNative(),
        sessions: sessions,
        mainWindowHwnd: () async => 1,
        isMainWindowFullscreen: () async => scenario.fullscreen,
      );
      expect(await settle(tester, opener.openWindow()), isTrue);
      final created = windows.handles.last;
      expect(created.stub.maximized, isTrue);
      expect(created.stub.fullscreen, isFalse);
      expect(
        frames[created.fakeHwnd],
        scenario.saved || scenario.legacy
            ? const Rect.fromLTWH(130, 110, 800, 600)
            : const Rect.fromLTWH(30, 30, 1280, 720),
      );
    });
  }

  testWidgets('שחזור Cocoa משתמש בנקודות הסשן הישן עם DPR 2', (tester) async {
    makeOpener(tester);
    const saved = WindowBounds(
      left: -1600,
      top: 100,
      width: 800,
      height: 600,
      dpr: 2,
    );
    sessions.rows[2] = WindowSession(
      slot: 2,
      tabsJson: '[]',
      currentIndex: 0,
      boundsJson: saved.encode(),
    );
    var actual = const Rect.fromLTWH(100, 100, 800, 600);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(CocoaViewWindowNative.defaultChannel, (
      call,
    ) async {
      if (call.method == 'setFrame') {
        final args = call.arguments as Map;
        actual = Rect.fromLTWH(
          args['x'] as double,
          args['y'] as double,
          args['width'] as double,
          args['height'] as double,
        );
      }
      if (call.method == 'frame') {
        return {
          'x': actual.left,
          'y': actual.top,
          'width': actual.width,
          'height': actual.height,
        };
      }
      if (call.method == 'reveal') return true;
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        CocoaViewWindowNative.defaultChannel,
        null,
      ),
    );
    final opener = ViewWindowOpener(
      registry: windows.registry,
      native: const CocoaViewWindowNative(),
      sessions: sessions,
    );
    await pumpHost(tester);
    await settle(tester, opener.restoreAllWindows([2]));
    expect(actual, const Rect.fromLTWH(-1600, 100, 800, 600));
    expect(windows.registry.windows.single.slot, 2);
  });

  testWidgets('Ctrl+Shift+T: חלון שנסגר חוזר עם הסשן שלו; אחריו הראשי', (
    tester,
  ) async {
    final opener = makeOpener(tester);
    await pumpHost(tester);
    expect(await settle(tester, opener.openWindow()), isTrue);
    final entry = windows.registry.windows.single;
    await sessions.save(2, tabsJson: '["a","b"]', currentIndex: 1);
    // הראשי הוסתר קודם, ולכן הוא השני בתור.
    await opener.beforeMainWindowHides();

    final flow = ViewWindowCloseFlow(
      entry: entry,
      flush: () async {},
      discardSession: sessions.delete,
      opener: opener,
    );
    expect(await settle(tester, flow.run()), isTrue);
    await tester.pump();
    expect(windows.registry.windows, isEmpty);
    expect(sessions.rows[2], isNull);

    expect(await settle(tester, opener.restoreLastClosedWindow()), isTrue);
    expect(windows.registry.windows.single.slot, 2);
    expect(sessions.rows[2]!.tabsJson, '["a","b"]');
    expect(sessions.rows[2]!.currentIndex, 1);
    expect(mainRestores, 0);

    expect(await settle(tester, opener.restoreLastClosedWindow()), isTrue);
    expect(mainRestores, 1);
    expect(await settle(tester, opener.restoreLastClosedWindow()), isFalse);
  });

  testWidgets('מאישור הסגירה החלון אינו יעד; כשל לפני ההריסה מחזיר אותו', (
    tester,
  ) async {
    final opener = makeOpener(tester);
    await pumpHost(tester);
    expect(await settle(tester, opener.openWindow()), isTrue);
    final entry = windows.registry.windows.single;
    expect(entry.isClosing, isFalse);
    bool? closingDuringFlush;
    final failing = ViewWindowCloseFlow(
      entry: entry,
      flush: () async {
        closingDuringFlush = entry.isClosing;
        throw StateError('flush');
      },
      discardSession: sessions.delete,
      opener: opener,
    );
    final outcome = failing.run().then<Object?>(
      (_) => null,
      onError: (Object e) => e,
    );
    expect(await settle(tester, outcome), isStateError);
    expect(closingDuringFlush, isTrue);
    expect(entry.isClosing, isFalse);
    expect(windows.stubOf(entry).destroyed, isFalse);
  });

  testWidgets('החלון האחרון על המסך (הראשי מוסתר): סגירה היא יציאה', (
    tester,
  ) async {
    final opener = makeOpener(tester);
    await pumpHost(tester);
    var exits = 0;
    opener.endProcess = () async => exits++;
    expect(await settle(tester, opener.openWindow()), isTrue);
    expect(await settle(tester, opener.openWindow()), isTrue);
    final [a, b] = windows.registry.windows;
    await sessions.save(a.slot, tabsJson: '[]', currentIndex: 0);
    await sessions.save(b.slot, tabsJson: '[]', currentIndex: 0);
    mainVisible = false;
    ViewWindowCloseFlow flowOf(ViewWindowEntry entry) => ViewWindowCloseFlow(
      entry: entry,
      flush: () async {},
      discardSession: sessions.delete,
      opener: opener,
    );

    // עוד חלון Dart פתוח: סגירה רגילה.
    expect(await opener.isLastVisibleWindow(a), isFalse);
    expect(await settle(tester, flowOf(a).run()), isTrue);
    await tester.pump();
    expect(exits, 0);
    expect(sessions.rows[a.slot], isNull);

    // האחרון: מסלול היציאה, בלי מחיקת הסשן ובלי הריסה (בוטל או יוצא).
    expect(await opener.isLastVisibleWindow(b), isTrue);
    expect(await settle(tester, flowOf(b).run()), isFalse);
    expect(exits, 1);
    expect(AppWindowKeys.current, same(b.keys));
    expect(sessions.rows[b.slot], isNotNull);
    expect(windows.stubOf(b).destroyed, isFalse);

    // הראשי גלוי: אינו האחרון.
    mainVisible = true;
    expect(await opener.isLastVisibleWindow(b), isFalse);
  });

  testWidgets('שמירת גבולות שהסשן הסתיים באמצעה אינה יוצרת אותו מחדש', (
    tester,
  ) async {
    final opener = makeOpener(tester);
    await pumpHost(tester);
    expect(await settle(tester, opener.openWindow()), isTrue);
    final entry = windows.registry.windows.single;
    windows.native.rects[windows.handleOf(entry).fakeHwnd!] =
        const Rect.fromLTWH(0, 0, 800, 600);
    var calls = 0;
    final binding = WindowPersistenceBinding(
      controller: entry.controller,
      geometry: entry.controller,
      sessions: sessions,
      devicePixelRatio: () => 1.0,
      // הקריאה הראשונה לפני ה-await-ים, השנייה ממש לפני הכתיבה.
      slot: () => calls++ == 0 ? entry.slot : null,
    );
    binding.scheduleSave();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(calls, 2);
    expect(sessions.boundsWrites, isEmpty);
    expect(sessions.rows[entry.slot], isNull);
    binding.dispose();
  });
  testWidgets('שחזור שפריים ראשון לא הגיע אליו: הסשן נשאר והמשבצת שמורה', (
    tester,
  ) async {
    final opener = makeOpener(tester, timeout: const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    sessions.rows[2] = const WindowSession(
      slot: 2,
      tabsJson: '["kept"]',
      currentIndex: 0,
    );
    final restore = opener.restoreAllWindows([2]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await restore;
    expect(windows.registry.windows, isEmpty);
    expect(sessions.rows[2]!.tabsJson, '["kept"]');
    expect(opener.pendingRestoreForTest, {2});
  });

  testWidgets('Ctrl+Shift+T שנכשל: השורה נמחקת והחלון נשאר לניסיון חוזר', (
    tester,
  ) async {
    final opener = makeOpener(tester, timeout: const Duration(seconds: 1));
    await pumpHost(tester);
    expect(await settle(tester, opener.openWindow()), isTrue);
    final entry = windows.registry.windows.single;
    await sessions.save(2, tabsJson: '["a"]', currentIndex: 0);
    final flow = ViewWindowCloseFlow(
      entry: entry,
      flush: () async {},
      discardSession: sessions.delete,
      opener: opener,
    );
    expect(await settle(tester, flow.run()), isTrue);
    await tester.pump();

    // בלי MultiViewHost החלון המשוחזר אינו מצייר.
    await tester.pumpWidget(const SizedBox());
    final restore = opener.restoreLastClosedWindow();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(await restore, isFalse);
    expect(sessions.rows[2], isNull);
    expect(opener.closedCountForTest, 1);
  });

  testWidgets('מסגרת במסך עם DPI אחר: הגודל מוחל שוב אחרי שינוי ה-DPI', (
    tester,
  ) async {
    final native = _DpiChangeNative();
    final opener = makeOpener(tester, native: native);
    await pumpHost(tester);
    expect(
      await settle(
        tester,
        opener.openWindow(bounds: (left: 0, top: 0, width: 800, height: 600)),
      ),
      isTrue,
    );
    expect(native.rects[100], const Rect.fromLTWH(0, 0, 800, 600));
  });

  testWidgets('כשל במסד: openWindow מחזיר false ולא זורק', (tester) async {
    final opener = makeOpener(tester, store: _FailingDeleteSessions());
    await pumpHost(tester);
    expect(await settle(tester, opener.openWindow()), isFalse);
    expect(windows.registry.windows, isEmpty);
    // התור לא נתקע אחרי הכשל.
    expect(await settle(tester, opener.restoreLastClosedWindow()), isFalse);
  });

  testWidgets('משבצת שמורה לשחזור לפני תחילתו אינה נמחקת בפתיחה חדשה', (
    tester,
  ) async {
    final opener = makeOpener(tester);
    await pumpHost(tester);
    sessions.rows[2] = const WindowSession(
      slot: 2,
      tabsJson: '["pending"]',
      currentIndex: 0,
    );
    opener.reserveForRestore([2]);
    expect(await settle(tester, opener.openWindow()), isTrue);
    expect(windows.registry.windows.single.slot, 3);
    expect(sessions.rows[2]!.tabsJson, '["pending"]');
  });

  testWidgets('מחיקת הסשן נכשלה: החלון נסגר בכל זאת', (tester) async {
    final opener = makeOpener(tester);
    await pumpHost(tester);
    expect(await settle(tester, opener.openWindow()), isTrue);
    final entry = windows.registry.windows.single;
    final flow = ViewWindowCloseFlow(
      entry: entry,
      flush: () async {},
      discardSession: (_) async => throw StateError('locked'),
      opener: opener,
    );
    expect(await settle(tester, flow.run()), isTrue);
    expect(windows.stubOf(entry).destroyed, isTrue);
  });

  testWidgets('סגירת שני החלונות האחרונים במקביל מבקשת יציאה אחת', (
    tester,
  ) async {
    final opener = makeOpener(tester);
    await pumpHost(tester);
    var exits = 0;
    opener.endProcess = () async {
      exits++;
    };
    expect(await settle(tester, opener.openWindow()), isTrue);
    expect(await settle(tester, opener.openWindow()), isTrue);
    mainVisible = false;
    final closing = [
      for (final entry in windows.registry.windows)
        ViewWindowCloseFlow(
          entry: entry,
          flush: () async {},
          discardSession: sessions.delete,
          opener: opener,
        ).run(),
    ];
    await settle(tester, Future.wait(closing));
    expect(exits, 1);
    expect(
      windows.registry.windows,
      hasLength(1),
      reason: 'ביטול יציאה משאיר חלון גלוי ולא תהליך ללא חלונות',
    );
  });

  testWidgets('כשל מסד בשחזור שומר את החלון לניסיון חוזר', (tester) async {
    final store = _ToggleDeleteSessions();
    final opener = makeOpener(tester, store: store);
    await pumpHost(tester);
    expect(await settle(tester, opener.openWindow()), isTrue);
    final entry = windows.registry.windows.single;
    await sessions.save(2, tabsJson: '["draft"]', currentIndex: 0);
    expect(
      await settle(
        tester,
        ViewWindowCloseFlow(
          entry: entry,
          flush: () async {},
          discardSession: sessions.delete,
          opener: opener,
        ).run(),
      ),
      isTrue,
    );
    store.failDelete = true;
    expect(await settle(tester, opener.restoreLastClosedWindow()), isFalse);
    expect(opener.closedCountForTest, 1);
    store.failDelete = false;
    expect(await settle(tester, opener.restoreLastClosedWindow()), isTrue);
    expect(opener.closedCountForTest, 0);
    expect(sessions.rows[2]!.tabsJson, '["draft"]');
  });

  testWidgets('אחרי הפריים הראשון: reveal, ובמק אירוע פוקוס לתצוגה החדשה', (
    tester,
  ) async {
    ViewFocusSync.debugMacOSOverride = false;
    final focus = _FocusEvents();
    tester.binding.addObserver(focus);
    addTearDown(() {
      tester.binding.removeObserver(focus);
      ViewFocusSync.resetForTest();
    });
    final opener = makeOpener(tester);
    await pumpHost(tester);

    expect(await settle(tester, opener.openWindow()), isTrue);
    final a = windows.registry.windows.single;
    expect(windows.native.revealed, [windows.handleOf(a).fakeHwnd]);
    expect(focus.events, isEmpty, reason: 'Windows/Linux: המנוע שולח בעצמו');

    ViewFocusSync.debugMacOSOverride = true;
    expect(await settle(tester, opener.openWindow()), isTrue);
    final b = windows.registry.windows.last;
    expect(windows.native.revealed.last, windows.handleOf(b).fakeHwnd);
    expect(focus.events.single.viewId, b.handle.view.viewId);
    expect(focus.events.single.state, ViewFocusState.focused);
  });

  testWidgets('macOS: החלון האחרון נסגר — נשארים ב-Dock והסשן נשמר', (
    tester,
  ) async {
    final opener = makeOpener(tester, keepsProcess: true);
    await pumpHost(tester);
    var exits = 0;
    opener.endProcess = () async => exits++;
    expect(await settle(tester, opener.openWindow()), isTrue);
    expect(await settle(tester, opener.openWindow()), isTrue);
    final [a, b] = windows.registry.windows;
    await sessions.save(a.slot, tabsJson: '["a"]', currentIndex: 0);
    await sessions.save(b.slot, tabsJson: '["b"]', currentIndex: 0);
    mainVisible = false;
    ViewWindowCloseFlow flowOf(ViewWindowEntry entry) => ViewWindowCloseFlow(
      entry: entry,
      flush: () async {},
      discardSession: sessions.delete,
      opener: opener,
    );

    expect(await settle(tester, flowOf(a).run()), isTrue);
    await tester.pump();
    expect(sessions.rows[a.slot], isNull);

    expect(await settle(tester, flowOf(b).run()), isTrue);
    await tester.pump();
    expect(exits, 0);
    expect(windows.stubOf(b).destroyed, isTrue);
    expect(sessions.rows[b.slot]!.tabsJson, '["b"]');

    // ה-Dock מחזיר את האחרון למשבצת הפנויה, והשורה הישנה אינה נשארת כפולה.
    expect(await settle(tester, opener.reopenFromDock()), isTrue);
    final restored = windows.registry.windows.single;
    expect(restored.slot, a.slot);
    expect(sessions.rows[restored.slot]!.tabsJson, '["b"]');
    expect(sessions.rows[b.slot], isNull);
    expect(mainRestores, 0);
  });

  testWidgets('macOS: שחזור אינו מוחק שורה שמורה שחלון חדש כבר תפס', (
    tester,
  ) async {
    final opener = makeOpener(tester, keepsProcess: true);
    await pumpHost(tester);
    opener.endProcess = () async {};
    expect(await settle(tester, opener.openWindow()), isTrue);
    final a = windows.registry.windows.single;
    await sessions.save(a.slot, tabsJson: '["a"]', currentIndex: 0);
    mainVisible = false;
    expect(
      await settle(
        tester,
        ViewWindowCloseFlow(
          entry: a,
          flush: () async {},
          discardSession: sessions.delete,
          opener: opener,
        ).run(),
      ),
      isTrue,
    );
    await tester.pump();

    // חלון חדש תופס את המשבצת של השורה השמורה.
    mainVisible = true;
    expect(await settle(tester, opener.openWindow()), isTrue);
    final fresh = windows.registry.windows.single;
    expect(fresh.slot, a.slot);
    await sessions.save(fresh.slot, tabsJson: '["fresh"]', currentIndex: 0);

    expect(await settle(tester, opener.restoreLastClosedWindow()), isTrue);
    expect(sessions.rows[fresh.slot]!.tabsJson, '["fresh"]');
    final restored = windows.registry.windows.last;
    expect(sessions.rows[restored.slot]!.tabsJson, '["a"]');
  });

  testWidgets('Dock בלי חלון סגור: הראשי, ואם לא שוחזר — הצגה', (tester) async {
    final opener = makeOpener(tester);
    await pumpHost(tester);

    expect(await opener.reopenFromDock(), isTrue);
    expect((mainRestores, mainShows), (1, 0));

    mainRestoreResult = false;
    expect(await opener.reopenFromDock(), isTrue);
    expect((mainRestores, mainShows), (2, 1));
  });
}

class _FocusEvents with WidgetsBindingObserver {
  final List<ViewFocusEvent> events = [];

  @override
  void didChangeViewFocus(ViewFocusEvent event) => events.add(event);
}
