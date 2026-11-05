import 'dart:async';
import 'dart:convert';
import 'package:otzaria/indexing/utils/indexing_crash_canary.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/storage/plugin_correction_draft_store.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/utils/confirm_close_tabs.dart';

import '../test_helpers/controllable_correction_draft_repository.dart';
import '../test_helpers/memory_cache_provider.dart';
import 'package:otzaria/core/pre_close_registry.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/window_listener.dart';
import 'package:otzaria/plugins/services/plugin_crash_guard.dart';
import 'package:otzaria/core/windowing/app_quit.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:otzaria/core/windowing/multiview/view_focus_sync.dart';
import 'package:otzaria/core/windowing/multiview/view_window_opener.dart';
import 'package:otzaria/core/windowing/window_opener.dart';
import 'package:otzaria/core/windowing/multiview/view_window_close_flow.dart';
import 'package:otzaria/core/windowing/multiview/in_process_tab_drop.dart';
import '../test_helpers/fake_view_window.dart';
import 'package:otzaria/core/user_state/user_state_slot.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';

/// סגירה מנומסת שומרת סשן לעדכון ומוחקת סשן בסגירת X רגילה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late _FakeRunner runner;
  late UserStateDatabase database;
  late WindowSessionStore sessions;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() async {
    // ה-runner מדומה כדי לבדוק את מסלול ריבוי החלונות בכל פלטפורמה.
    RunnerWindowChannel.debugSupportedOverride = true;
    // onWindowFocus מתוך test() אחרי testWidgets פוגש FocusManager משוחרר.
    ViewFocusSync.debugEnabledOverride = false;
    ViewWindowOpener.instance.resetCloseQueueForTest();
    runner = _FakeRunner()..install();
    tmp = Directory.systemTemp.createTempSync('otzaria_secclose_');
    AppPaths.debugProfileDataRootPath = tmp.path;
    database = UserStateDatabase.openAt('${tmp.path}/user_state.db');
    await database.database;
    sessions = WindowSessionStore(database: database);
    TabsRepository.debugSessions = sessions;
  });

  tearDown(() async {
    WindowTabsSession.current.resume();
    InProcessTabDrops.instance.setMainShown(true);
    AppQuit.resetForTest();
    AppWindowListener.prepareUpdateForClose = null;
    AppPaths.debugProfileDataRootPath = null;
    TabsRepository.debugSessions = null;
    database.close();
    runner.uninstall();
    RunnerWindowChannel.debugSupportedOverride = null;
    ViewFocusSync.resetForTest();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// הכנת יציאה אחרת שעדיין פעילה מכשילה את אישור היציאה המלאה.
  void holdQuitPreparation() {
    final corrections = PluginCorrectionSessionService.instance;
    expect(corrections.beginProcessQuitPreparation('held'), isTrue);
    addTearDown(() => corrections.cancelProcessQuitPreparation('held'));
  }

  test('סגירת חלון בלי כיבוי התהליך משמרת canary', () async {
    IndexingCrashCanary.start('${tmp.path}/index');
    final canary = IndexingCrashCanary.current!;
    canary.begin('id:crashing');
    addTearDown(canary.finish);
    await AppWindowListener().handleWindowClose();
    expect(runner.closeSelfCalls, 1);
    expect(
      IndexingCrashCanary.current,
      same(canary),
      reason: 'האינדוקס ממשיך במנוע החי לאחר הסתרת החלון',
    );
  });

  test('הכנת העדכון מסתיימת לפני flush וסגירה, גם באירוע כפול', () async {
    final preparing = Completer<void>();
    final started = Completer<void>();
    final steps = <String>[];
    AppWindowListener.prepareUpdateForClose = () async {
      steps.add('prepare');
      started.complete();
      await preparing.future;
      steps.add('launched');
    };
    Future<void> flush() async => steps.add('flush');
    PreCloseRegistry.register(flush);
    addTearDown(() => PreCloseRegistry.unregister(flush));

    final listener = AppWindowListener();
    final close = listener.handleWindowClose();
    await started.future;
    await listener.handleWindowClose();
    expect(steps, ['prepare']);
    expect(runner.closeSelfCalls, 0);

    preparing.complete();
    await close;
    expect(steps, ['prepare', 'launched', 'flush']);
    expect(runner.closeSelfCalls, 1);
  });

  test('כתיבת canary של תוסף שנתקעה אינה עוצרת את הסגירה (#4008)', () async {
    AppPaths.debugOverrideDataRootPath(tmp.path);
    PluginCrashGuard.setInitialBlockedForTesting({});
    addTearDown(() {
      AppPaths.debugOverrideDataRootPath(null);
      PluginCrashGuard.resetForTesting();
    });
    await IOOverrides.runWithIOOverrides(() async {
      unawaited(PluginCrashGuard.markLoadAttempt('stuck.plugin', owner: 't'));
      await AppWindowListener().handleWindowClose().timeout(
        const Duration(seconds: 6),
      );
    }, _StuckCrashGuardWrites());
    expect(runner.closeSelfCalls, 1);
  });

  test('סגירה שבוטלה אינה מכינה או משגרת עדכון', () async {
    var launches = 0;
    AppWindowListener.prepareUpdateForClose = () async => launches++;

    await AppWindowListener().handleWindowClose(canClose: () => false);

    expect(launches, 0);
    expect(runner.closeSelfCalls, 0);
  });

  test('סגירת הראשי ממתינה למסלול סגירה של חלון Dart', () async {
    WindowOpener.debugOverride = _TwoWindowsOpener();
    addTearDown(() {
      WindowOpener.debugOverride = null;
      WindowTabsSession.current.resume();
    });
    final released = Completer<void>();
    final started = Completer<void>();
    final otherClose = ViewWindowOpener.instance.serializeClose(() async {
      started.complete();
      await released.future;
      return true;
    });
    await started.future;
    var prepared = false;
    AppWindowListener.prepareUpdateForClose = () async {
      prepared = true;
    };
    final mainClose = AppWindowListener().handleWindowClose();
    await Future<void>.delayed(Duration.zero);
    expect(prepared, isFalse);
    released.complete();
    await otherClose;
    await mainClose;
    expect(prepared, isTrue);
  });

  testWidgets(
    'יציאה מה-Dart האחרון מחליפה סגירת ראשי ממתינה גם כשהיציאה בוטלה',
    (tester) async {
      WindowOpener.debugOverride = _TwoWindowsOpener();
      addTearDown(() {
        WindowOpener.debugOverride = null;
        WindowTabsSession.current.resume();
      });
      holdQuitPreparation();
      await tester.pumpWidget(
        BlocProvider<TabsBloc>.value(
          value: _GuardTabs(
            ToolTab(toolId: 'p', title: 'טיוטה', instanceId: 'queued-quit'),
          ),
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const SizedBox(),
          ),
        ),
      );
      var prepared = 0;
      AppWindowListener.prepareUpdateForClose = () async {
        prepared++;
      };
      await tester.runAsync(() async {
        final released = Completer<void>();
        final started = Completer<void>();
        final dartClose = ViewWindowOpener.instance.serializeClose(() async {
          started.complete();
          await released.future;
          return true;
        });
        await started.future;
        final listener = AppWindowListener();
        final mainClose = listener.handleWindowClose();
        await listener.quitFromLastViewWindow();
        released.complete();
        await dartClose;
        await mainClose;
      });
      expect(
        prepared,
        0,
        reason: 'אישור יציאה נכשל; סגירה רגילה ישנה אינה רצה אחריו',
      );
      expect(runner.closeSelfCalls, 0);
      expect(WindowTabsSession.current.slot, isNotNull);
    },
  );

  test('יציאה מפורשת בזמן סגירה פעילה ממתינה ונבדקת אחריה', () async {
    WindowOpener.debugOverride = _TwoWindowsOpener();
    addTearDown(() {
      WindowOpener.debugOverride = null;
      WindowTabsSession.current.resume();
    });
    final prepared = Completer<void>();
    final released = Completer<void>();
    AppWindowListener.prepareUpdateForClose = () async {
      prepared.complete();
      await released.future;
    };
    final listener = AppWindowListener();
    final normal = listener.handleWindowClose();
    await prepared.future;
    var quitAttempts = 0;
    final quit = listener.handleWindowClose(
      quit: true,
      canClose: () {
        quitAttempts++;
        return false;
      },
    );
    expect(quitAttempts, 0);
    released.complete();
    await normal;
    await quit;
    expect(quitAttempts, 1);
    expect(runner.closeSelfCalls, 1);
  });

  testWidgets('עדכון בריבוי תצוגות מבקש יציאה מלאה ולא מסתיר רק את הראשי', (
    tester,
  ) async {
    holdQuitPreparation();
    final tab = ToolTab(toolId: 'p', title: 'תוסף', instanceId: 'update');
    await tester.pumpWidget(
      BlocProvider<TabsBloc>.value(
        value: _GuardTabs(tab),
        child: MaterialApp(navigatorKey: navigatorKey, home: const SizedBox()),
      ),
    );
    final window = _RecordingWindow();
    AppQuit.install(AppWindowListener(window: window).quitFromLastViewWindow);
    await tester.runAsync(
      () => AppQuit.quitAll(AppQuitReason.update, window: window),
    );
    expect(
      runner.closeSelfCalls,
      0,
      reason: 'יציאה שלא אושרה מונעת את הכיבוי; הראשי נשאר גלוי',
    );
    expect(window.closes, 0, reason: 'סגירה רגילה רק מסתירה את הראשי');
    expect(WindowTabsSession.current.slot, isNotNull);
  });

  test('כשל בהכנת העדכון אינו נועל את ניסיון הסגירה הבא', () async {
    final listener = AppWindowListener();
    AppWindowListener.prepareUpdateForClose = () async {
      throw StateError('preparation failed');
    };

    await expectLater(listener.handleWindowClose(), throwsStateError);
    expect(runner.closeSelfCalls, 0);

    AppWindowListener.prepareUpdateForClose = null;
    await listener.handleWindowClose();
    expect(runner.closeSelfCalls, 1);
  });

  testWidgets('חלון Dart שאינו האחרון: flush רץ, הסשן נמחק, ורק הוא נסגר', (
    tester,
  ) async {
    final windows = FakeViewWindows(tester);
    final entry = windows.registry.open(size: const Size(800, 600))!;
    final peer = windows.registry.open(size: const Size(800, 600))!;
    final opener = ViewWindowOpener(
      registry: windows.registry,
      native: windows.native,
      sessions: sessions,
    );
    final repository = TabsRepository(
      sessions: sessions,
      window: entry.tabsSession,
    );
    await tester.runAsync(() => repository.saveTabs(const [], 0));
    expect(await tester.runAsync(() => sessions.load(entry.slot)), isNotNull);
    var flushed = false;
    Future<void> flush() async => flushed = true;
    PreCloseRegistry.register(flush);
    addTearDown(() => PreCloseRegistry.unregister(flush));

    final flow = ViewWindowCloseFlow(
      entry: entry,
      opener: opener,
      discardSession: sessions.delete,
    );
    expect(await tester.runAsync(flow.run), isTrue);
    await tester.pump();

    expect(flushed, isTrue, reason: 'הכתיבות התלויות נשטפו');
    expect(
      windows.stubOf(entry).destroyed,
      isTrue,
      reason: 'רק החלון הזה נסגר',
    );
    expect(windows.stubOf(peer).destroyed, isFalse);
    expect(windows.registry.windows, [peer]);
    expect(
      await tester.runAsync(() => sessions.load(entry.slot)),
      isNull,
      reason: 'חלון שנסגר במכוון אינו חוזר באתחול הבא',
    );
    peer.handle.destroy();
    await tester.pump();
  });

  test('החלון הראשון שאינו האחרון: הסשן שלו נמחק כמו של כל חלון', () async {
    // ⚠️ ההצדקה זהה לזו של חלון משני — הוא נסגר במכוון בעוד אחרים
    // פתוחים — ולכן הכרטיסיות שלו אינן "פתוחות" יותר.
    const slot = UserStateSlot.main;
    await TabsRepository().saveTabs(const [], 0);

    await AppWindowListener().handleWindowClose();

    expect(runner.closeSelfCalls, 1);
    expect(await sessions.load(slot), isNull);
  });

  test(
    'ריבוי תצוגות: הראשי מוסתר כשחלונות Dart פתוחים, והסשן שלו מושהה',
    () async {
      WindowOpener.debugOverride = _TwoWindowsOpener();
      addTearDown(() {
        WindowOpener.debugOverride = null;
        WindowTabsSession.current.resume();
      });
      const slot = UserStateSlot.main;
      await TabsRepository().saveTabs(const [], 0);
      final closedBefore = ViewWindowOpener.instance.closedCountForTest;

      final listener = AppWindowListener();
      await listener.handleWindowClose();

      expect(runner.closeSelfCalls, 1, reason: 'הסתרה, לא יציאה (D1a)');
      expect(await sessions.load(slot), isNull);
      // ה-flush של החלון האחרון אינו כותב את הסשן שנמחק.
      expect(WindowTabsSession.current.slot, isNull);
      await TabsRepository().saveTabs(const [], 0);
      expect(await sessions.load(slot), isNull);
      expect(ViewWindowOpener.instance.closedCountForTest, closedBefore + 1);

      // הוצג שוב (Ctrl+Shift+T): שומר שוב.
      listener.onWindowFocus();
      expect(WindowTabsSession.current.slot, slot);
    },
  );

  group('דיאלוג עם שינויים שלא נשמרו בזמן סגירת החלון (q11 Q3, DD-08)', () {
    late ValueNotifier<bool> dirty;
    late Future<void> closing;
    var closeDone = false;

    setUp(() => dirty = ValueNotifier(true));
    tearDown(() => dirty.dispose());

    Future<void> openDialog(WidgetTester tester) async {
      ViewWindowOpener.instance.resetCloseQueueForTest();
      await tester.pumpWidget(
        BlocProvider<TabsBloc>.value(
          value: _GuardTabs(
            ToolTab(toolId: 'p', title: 'נקי', instanceId: 'dirty-dialog'),
          ),
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const SizedBox(),
          ),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      unawaited(
        showTwoActionsDialog(
          context: navigatorKey.currentContext!,
          title: 'עריכה',
          content: 'תוכן',
          isDirty: dirty,
        ),
      );
      await tester.pumpAndSettle();
    }

    /// מקדם את הסגירה עד שהסתיימה, או עד שאלת הדיאלוג כש-[untilQuestion].
    Future<void> advance(
      WidgetTester tester, {
      bool untilQuestion = false,
    }) async {
      bool reached() =>
          closeDone ||
          (untilQuestion &&
              find.text('לסגור בלי לשמור?').evaluate().isNotEmpty);
      final elapsed = Stopwatch()..start();
      while (!reached() && elapsed.elapsed < const Duration(seconds: 5)) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(reached(), isTrue);
      await tester.pumpAndSettle();
    }

    Future<void> startClose(WidgetTester tester) async {
      closeDone = false;
      closing = AppWindowListener().handleWindowClose().whenComplete(
        () => closeDone = true,
      );
      await advance(tester, untilQuestion: true);
    }

    Future<void> answer(WidgetTester tester, String button) async {
      expect(find.text('לסגור בלי לשמור?'), findsOneWidget);
      expect(runner.closeSelfCalls, 0, reason: 'החלון מחכה לתשובה');
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      await advance(tester);
      await closing;
    }

    testWidgets('"המשך לערוך": החלון והדיאלוג נשארים, עם מה שהוקלד', (
      tester,
    ) async {
      await openDialog(tester);
      await startClose(tester);
      await answer(tester, 'המשך לערוך');
      expect(runner.closeSelfCalls, 0);
      expect(find.text('עריכה'), findsOneWidget);
      expect(WindowTabsSession.current.slot, isNotNull);
    });

    testWidgets('"סגור בלי לשמור": הדיאלוג נסגר, ואחריו החלון', (
      tester,
    ) async {
      await openDialog(tester);
      await startClose(tester);
      await answer(tester, 'סגור בלי לשמור');
      expect(runner.closeSelfCalls, 1);
      expect(find.text('עריכה'), findsNothing);
    });

    testWidgets('דיאלוג בלי שינויים: החלון נסגר ישר, בלי שאלה', (
      tester,
    ) async {
      dirty.value = false;
      await openDialog(tester);
      await startClose(tester);
      expect(closeDone, isTrue);
      expect(find.text('לסגור בלי לשמור?'), findsNothing);
      await closing;
      expect(runner.closeSelfCalls, 1);
    });
  });

  group('סשן תיקון בלשונית קורא', () {
    final service = PluginCorrectionSessionService.instance;
    final ended = <String>[];
    late Database draftDb;
    late ControllableCorrectionDraftRepository drafts;
    late TextBookTab tab;
    late String tabId;

    setUp(() {
      PluginCorrectionSessionService.flushTimeout = const Duration(
        milliseconds: 100,
      );
      draftDb = sqlite3.openInMemory();
      drafts = ControllableCorrectionDraftRepository(
        PluginCorrectionDraftRepository.direct(draftDb),
      );
      service.draftRepository = drafts;
      tab = TextBookTab(book: TextBook(title: 'ספר'), index: 0);
      tabId = PluginCorrectionSessionService.tabIdFor(tab);
      ended.clear();
    });

    tearDown(() async {
      drafts.failWrites = false;
      await service.purgeOwner('p');
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      draftDb.close();
      PluginCorrectionSessionService.flushTimeout = const Duration(seconds: 3);
    });

    Future<void> openWindow(WidgetTester tester, {bool failing = false}) async {
      // הסגירה עוברת בתור של התהליך; הוא חייב להיווצר ב-FakeAsync של הבדיקה.
      ViewWindowOpener.instance.resetCloseQueueForTest();
      await tester.runAsync(
        () => service.begin(
          owner: 'p',
          tabId: tabId,
          bookId: 'ספר',
          bookUid: 'id:1',
          libraryVersion: 'v1',
          loadSource: (_) async => 'מקור',
          onEvent: (topic, payload) {
            if (topic == 'reader.correctionSessionEnded') {
              ended.add(payload['reason'] as String);
            }
          },
        ),
      );
      drafts.failWrites = failing;
      service.editParagraph(tabId, 0, 'מקור', 'תיקון');
      await tester.pumpWidget(
        BlocProvider<TabsBloc>.value(
          value: _GuardTabs(tab),
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const SizedBox(),
          ),
        ),
      );
      addTearDown(() => tester.pumpWidget(const SizedBox()));
    }

    late Future<void> closing;
    var closeDone = false;

    Future<void> advanceClose(
      WidgetTester tester, {
      bool allowDialog = false,
    }) async {
      bool reachedBoundary() =>
          closeDone ||
          (allowDialog &&
              find.text(unsavedChangesDialogTitle).evaluate().isNotEmpty);
      final elapsed = Stopwatch()..start();
      while (!reachedBoundary() &&
          elapsed.elapsed < const Duration(seconds: 5)) {
        await tester.pump(const Duration(milliseconds: 50));
        // גם I/O אמיתי וגם טיימרים מדומים משתתפים בסגירה.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(
        reachedBoundary(),
        isTrue,
        reason: 'הסגירה חייבת להסתיים או להציג את שומר הסגירה',
      );
      await tester.pumpAndSettle();
    }

    Future<void> startClose(
      WidgetTester tester,
      AppWindowListener listener,
    ) async {
      closeDone = false;
      closing = listener.handleWindowClose().whenComplete(
        () => closeDone = true,
      );
      await advanceClose(tester, allowDialog: true);
    }

    Future<void> finishClose(WidgetTester tester) async {
      await advanceClose(tester);
      await closing;
    }

    Future<Map<String, Object?>?> stored(WidgetTester tester) => tester
        .runAsync(() => drafts.get('p', correctionDraftId('p', 'id:1')))
        .then((draft) => draft);

    testWidgets('טיוטה שנשמרה: בלי אזהרה, והסתרת הראשי אינה מסיימת את הסשן', (
      tester,
    ) async {
      await openWindow(tester);
      await startClose(tester, AppWindowListener());
      expect(find.text(unsavedChangesDialogTitle), findsNothing);
      await finishClose(tester);
      await tester.runAsync(() async {
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      expect(runner.closeSelfCalls, 1);
      // הטיוטות שייכות לכל החלונות, והחלון המוסתר חוזר עם הכרטיסיות שלו.
      expect(service.hasSessionForTab(tabId), isTrue);
      expect(ended, isEmpty);
      expect(
        ((await stored(tester))!['changes'] as List).single['proposedText'],
        'תיקון',
      );
    });

    testWidgets(
      'כתיבה שנכשלת: ביטול משאיר חלון, סשן ושינוי; אישור סוגר והמצב נשמר '
      'אחרי התאוששות',
      (tester) async {
        await openWindow(tester, failing: true);
        final listener = AppWindowListener();

        await startClose(tester, listener);
        expect(find.text(unsavedChangesDialogTitle), findsOneWidget);
        await tester.tap(find.text('ביטול'));
        await tester.pumpAndSettle();
        await finishClose(tester);
        expect(runner.closeSelfCalls, 0);
        expect(service.hasSessionForTab(tabId), isTrue);
        expect(service.displayText(tabId, 0, 'מקור'), 'תיקון');

        await startClose(tester, listener);
        await tester.tap(find.text(unsavedChangesCloseAnyway));
        await tester.pumpAndSettle();
        await finishClose(tester);
        expect(runner.closeSelfCalls, 1);
        expect(service.hasSessionForTab(tabId), isTrue);
        expect(
          await tester.runAsync(() => service.unsavedStates()),
          hasLength(1),
          reason: 'המצב נשאר באזהרת היציאה עד שיישמר',
        );

        drafts.failWrites = false;
        await tester.runAsync(() async {
          service.retryDraftWrites();
          for (var i = 0; i < 20; i++) {
            await Future<void>.delayed(Duration.zero);
          }
        });
        expect(
          ((await stored(tester))!['changes'] as List).single['proposedText'],
          'תיקון',
        );
        expect(ended, isEmpty);
        // שחרור ה-lease שאחרי ההתאוששות רץ בשעון המדומה.
        await tester.pump(const Duration(milliseconds: 50));
      },
    );
  });

  test('macOS, החלון האחרון: מוסתר, הסשן נשמר, והתהליך אינו מסתיים', () async {
    AppWindowListener.debugKeepsProcessAfterLastWindowOverride = true;
    addTearDown(
      () => AppWindowListener.debugKeepsProcessAfterLastWindowOverride = null,
    );
    runner.windowCount = 1;
    IndexingCrashCanary.start('${tmp.path}/index');
    final canary = IndexingCrashCanary.current!;
    canary.begin('id:active');
    addTearDown(canary.finish);

    var flushed = false;
    Future<void> flush() async => flushed = true;
    PreCloseRegistry.register(flush);
    addTearDown(() => PreCloseRegistry.unregister(flush));

    const slot = UserStateSlot.main;
    await TabsRepository().saveTabs(const [], 0);

    await AppWindowListener().handleWindowClose();

    expect(flushed, isTrue);
    expect(runner.closeSelfCalls, 1, reason: 'הוסתר במקום כיבוי');
    expect(IndexingCrashCanary.current, same(canary));
    expect(
      await sessions.load(slot),
      isNotNull,
      reason: 'הכרטיסיות של החלון האחרון הן הסשן של הפתיחה הבאה',
    );
  });
}

/// `windowCount` מחזיר שניים כברירת מחדל — "אינך האחרון".
class _TwoWindowsOpener extends Fake implements WindowOpener {
  _TwoWindowsOpener([this.count]);
  final int Function()? count;

  @override
  Future<({int count, int max})?> windowCount() async =>
      (count: count?.call() ?? 2, max: 8);
}

class _FakeRunner {
  int closeSelfCalls = 0;
  int windowCount = 2;

  void install() {
    WindowOpener.debugOverride = _TwoWindowsOpener(() => windowCount);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(RunnerWindowChannel.channel, (call) async {
          switch (call.method) {
            case 'closeSelf':
              closeSelfCalls++;
              return null;
            case 'restoreLastClosedWindow':
              return true;
            default:
              return null;
          }
        });
  }

  void uninstall() {
    WindowOpener.debugOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(RunnerWindowChannel.channel, null);
  }
}

class _GuardTabs extends Fake implements TabsBloc {
  _GuardTabs(this.tab);
  final OpenedTab tab;

  @override
  Stream<TabsState> get stream => const Stream.empty();

  @override
  TabsState get state => TabsState(tabs: [tab], currentTabIndex: 0);
}

class _RecordingWindow extends Fake implements AppWindowController {
  int closes = 0;
  @override
  Future<void> close() async => closes++;
}

/// כתיבה לקובץ ה-canary של התוספים לעולם אינה מסתיימת.
final class _StuckCrashGuardWrites extends IOOverrides {
  @override
  File createFile(String path) {
    final real = super.createFile(path);
    return path.contains('plugin_crash_guard') ? _StuckFile(real) : real;
  }
}

class _StuckFile implements File {
  _StuckFile(this._real);
  final File _real;

  @override
  String get path => _real.path;

  @override
  Directory get parent => _real.parent;

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => Completer<File>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
