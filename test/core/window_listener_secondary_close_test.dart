import 'dart:async';
import 'package:otzaria/indexing/utils/indexing_crash_canary.dart';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui show IsolateNameServer;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/services/plugin_unsaved_changes_registry.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/utils/confirm_close_tabs.dart';

import '../test_helpers/memory_cache_provider.dart';
import 'package:otzaria/core/pre_close_registry.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/window_session_store.dart';
import 'package:otzaria/core/window_listener.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/tabs/tabs_repository.dart';

/// ⚠️ קידומת ייחודית לסוויטה — [ui.IsolateNameServer] גלובלי לתהליך.
const String _namespace = 'otzaria.test.secondaryclose';

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
    WindowBus.namespace = _namespace;
    WindowRole.isSecondary = false;
    // ה-runner מדומה כדי לבדוק את מסלול ריבוי החלונות בכל פלטפורמה.
    MultiWindowService.debugSupportedOverride = true;
    runner = _FakeRunner()..install();
    tmp = Directory.systemTemp.createTempSync('otzaria_secclose_');
    AppPaths.debugProfileDataRootPath = tmp.path;
    database = UserStateDatabase.openAt('${tmp.path}/user_state.db');
    await database.database;
    sessions = WindowSessionStore(database: database);
    TabsRepository.debugSessions = sessions;
  });

  tearDown(() async {
    AppWindowListener.prepareUpdateForClose = null;
    AppPaths.debugProfileDataRootPath = null;
    TabsRepository.debugSessions = null;
    MultiWindowService.closingAll = false;
    database.close();
    runner.uninstall();
    MultiWindowService.debugSupportedOverride = null;
    WindowRole.isSecondary = false;
    WindowBus.instance.onRequest = null;
    WindowBus.instance.unregister();
    for (var i = 1; i <= WindowBus.slotCount; i++) {
      ui.IsolateNameServer.removePortNameMapping('$_namespace.$i');
    }
    ui.IsolateNameServer.removePortNameMapping('$_namespace.owner');
    WindowBus.namespace = 'otzaria.window';
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('סגירת חלון בלי כיבוי התהליך משמרת canary', () async {
    WindowBus.instance.register();
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
    WindowBus.instance.register();
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

  test('סגירה שבוטלה אינה מכינה או משגרת עדכון', () async {
    var launches = 0;
    AppWindowListener.prepareUpdateForClose = () async => launches++;

    await AppWindowListener().handleWindowClose(canClose: () => false);

    expect(launches, 0);
    expect(runner.closeSelfCalls, 0);
  });

  test('כשל בהכנת העדכון אינו נועל את ניסיון הסגירה הבא', () async {
    WindowBus.instance.register();
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

  test('חלון משני שאינו האחרון: flush רץ, הסשן נמחק, ורק הוא נסגר', () async {
    final owner = _FakeOwner(1)..register();
    addTearDown(owner.dispose);

    var flushed = false;
    Future<void> flush() async => flushed = true;
    PreCloseRegistry.register(flush);
    addTearDown(() => PreCloseRegistry.unregister(flush));

    WindowRole.isSecondary = true;
    WindowBus.instance.register();
    // כרטיסיות שמורות בסשן של החלון הזה.
    await TabsRepository().saveTabs(const [], 0);
    final slot = WindowBus.instance.slot!;
    expect(await sessions.load(slot), isNotNull);

    await AppWindowListener().handleWindowClose();

    expect(flushed, isTrue, reason: 'הכתיבות התלויות נשטפו');
    expect(runner.closeSelfCalls, 1, reason: 'רק החלון הזה נסגר');
    expect(
      await sessions.load(slot),
      isNull,
      reason:
          'הסשן נמחק — בלעדיו `adoptOrphanWindowSessions` היה מחזיר '
          'בהפעלה הבאה כרטיסיות שהמשתמש סגר במכוון',
    );
  });

  test('החלון הראשון שאינו האחרון: הסשן שלו נמחק כמו של כל חלון', () async {
    // ⚠️ ההצדקה זהה לזו של חלון משני — הוא נסגר במכוון בעוד אחרים
    // פתוחים — ולכן הכרטיסיות שלו אינן "פתוחות" יותר.
    WindowBus.instance.register();
    final slot = WindowBus.instance.slot!;
    await TabsRepository().saveTabs(const [], 0);

    await AppWindowListener().handleWindowClose();

    expect(runner.closeSelfCalls, 1);
    expect(await sessions.load(slot), isNull);
  });

  test('סגירה לעדכון כשחלון אחר עוד פתוח: הסשן נשמר (issue #2095)', () async {
    // `closePeers` אינו ממתין, ולכן החלון שמתקין רואה עוד חלון פתוח.
    WindowBus.instance.register();
    final slot = WindowBus.instance.slot!;
    await TabsRepository().saveTabs(const [], 0);

    MultiWindowService.closePeers();
    await AppWindowListener().handleWindowClose();

    expect(runner.closeSelfCalls, 1);
    expect(await sessions.load(slot), isNotNull);
  });

  test('X אחרי החזרת חלון שנסגר לעדכון מוחק את הסשן', () async {
    WindowBus.instance.register();
    final slot = WindowBus.instance.slot!;
    final repository = TabsRepository();
    final listener = AppWindowListener();
    final tab = ToolTab(
      toolId: 'p.editor',
      title: 'עורך',
      instanceId: 'revived',
    );
    await repository.saveTabs([tab], 0);

    MultiWindowService.closePeers();
    await listener.handleWindowClose();
    expect(await sessions.load(slot), isNotNull);
    expect(await const MultiWindowService().restoreLastClosedWindow(), isTrue);
    await repository.saveTabs([tab], 0);
    await listener.handleWindowClose();

    expect(runner.closeSelfCalls, 2);
    expect(await sessions.adoptInto(slot == 1 ? 2 : 1), 0);
  });

  for (final cancellationCheck in [1, 2]) {
    test(
      'ביטול canClose בבדיקה $cancellationCheck אינו שומר כוונת עדכון',
      () async {
        WindowBus.instance.register();
        final slot = WindowBus.instance.slot!;
        await TabsRepository().saveTabs(const [], 0);
        final listener = AppWindowListener();
        var checks = 0;

        MultiWindowService.closePeers();
        await listener.handleWindowClose(
          canClose: () => ++checks < cancellationCheck,
        );
        expect(runner.closeSelfCalls, 0);
        expect(await sessions.load(slot), isNotNull);
        await listener.handleWindowClose();

        expect(runner.closeSelfCalls, 1);
        expect(await sessions.load(slot), isNull);
      },
    );
  }

  for (final beforeGuard in [false, true]) {
    for (final confirm in [false, true]) {
      testWidgets(
        'עדכון ${beforeGuard ? 'לפני' : 'בזמן'} שומר X ואז ${confirm ? 'אישור' : 'ביטול'}',
        (
          tester,
        ) async {
          WindowBus.instance.register();
          final slot = WindowBus.instance.slot!;
          final tab = ToolTab(
            toolId: 'p.editor',
            title: 'עורך',
            instanceId: 'guard',
          );
          final key = (pluginId: tab.toolId, instanceId: tab.instanceId);
          await tester.runAsync(() => TabsRepository().saveTabs([tab], 0));
          PluginUnsavedChangesRegistry.instance.set(key, hasChanges: true);
          addTearDown(
            () => PluginUnsavedChangesRegistry.instance.removeInstance(key),
          );
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
          final listener = AppWindowListener();
          if (beforeGuard) MultiWindowService.closePeers();
          final closing = listener.handleWindowClose();
          await tester.pumpAndSettle();
          expect(find.text(unsavedChangesDialogTitle), findsOneWidget);

          MultiWindowService.closePeers();
          final duplicate = listener.handleWindowClose();
          await tester.pump();
          expect(runner.closeSelfCalls, 0);
          expect(MultiWindowService.closingAll, isTrue);
          await tester.tap(
            find.text(confirm ? unsavedChangesCloseAnyway : 'ביטול'),
          );
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            await closing;
            await duplicate;
          });
          expect(runner.closeSelfCalls, confirm ? 1 : 0);
          expect(await tester.runAsync(() => sessions.load(slot)), isNotNull);
          expect(MultiWindowService.closingAll, isFalse);

          PluginUnsavedChangesRegistry.instance.removeInstance(key);
          if (confirm) {
            expect(
              await const MultiWindowService().restoreLastClosedWindow(),
              isTrue,
            );
          }
          await tester.runAsync(() => listener.handleWindowClose());
          expect(await tester.runAsync(() => sessions.load(slot)), isNull);
        },
      );
    }
  }

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

    WindowBus.instance.register();
    final slot = WindowBus.instance.slot!;
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

/// ה-runner המדומה. `windowCount` מחזיר שניים כברירת מחדל — "אינך האחרון".
class _FakeRunner {
  int closeSelfCalls = 0;
  int windowCount = 2;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MultiWindowService.channel, (call) async {
          switch (call.method) {
            case 'windowCount':
              return {'count': windowCount, 'max': 4, 'engines': 2};
            case 'closeSelf':
              closeSelfCalls++;
              return null;
            case 'restoreLastClosedWindow':
              return true;
            case 'setBusSlot':
              return null;
            default:
              return null;
          }
        });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MultiWindowService.channel, null);
  }
}

/// החלון הראשון של התהליך — תופס משבצת ואת כינוי המארח, ועונה לכל בקשה.
class _FakeOwner {
  _FakeOwner(this.slot);

  final int slot;
  late final ReceivePort _port;

  void register() {
    _port = ReceivePort();
    ui.IsolateNameServer.registerPortWithName(
      _port.sendPort,
      '$_namespace.$slot',
    );
    ui.IsolateNameServer.registerPortWithName(
      _port.sendPort,
      '$_namespace.owner',
    );
    _port.listen((message) {
      final map = message as Map;
      (map['reply'] as SendPort).send({'ok': true, 'result': null});
    });
  }

  void dispose() {
    ui.IsolateNameServer.removePortNameMapping('$_namespace.$slot');
    ui.IsolateNameServer.removePortNameMapping('$_namespace.owner');
    _port.close();
  }
}

class _GuardTabs extends Fake implements TabsBloc {
  _GuardTabs(this.tab);
  final ToolTab tab;

  @override
  Stream<TabsState> get stream => const Stream.empty();

  @override
  TabsState get state => TabsState(tabs: [tab], currentTabIndex: 0);
}
