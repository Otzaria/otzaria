import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/window_messages.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';
import 'package:otzaria/workspaces/workspace.dart';
import 'package:otzaria/workspaces/workspace_repository.dart';

import '../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('אזהרת שולחן נשארת בחלון המקור אחרי מעבר פוקוס', (tester) async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    final a = AppWindowKeys(id: const AppWindowId('a'));
    final b = AppWindowKeys(id: const AppWindowId('b'));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          children: [
            Expanded(
              child: MaterialApp(
                navigatorKey: a.navigator,
                home: const SizedBox(),
              ),
            ),
            Expanded(
              child: MaterialApp(
                navigatorKey: b.navigator,
                home: const SizedBox(),
              ),
            ),
          ],
        ),
      ),
    );
    AppWindowKeys.activate(a);
    final first = Workspace(name: 'א', tabs: []);
    final second = Workspace(name: 'ב', tabs: []);
    final switched = Completer<void>();
    final bloc = WorkspaceBloc(
      repository: _FakeWorkspaceRepository(
        workspaces: [first, second],
        activeWorkspaceId: first.id,
      ),
      isOpenInOtherWindow: (_) => true,
      onWorkspaceTabsChanged: (_, _, _) => switched.future,
    )..add(LoadWorkspaces());
    await tester.pump();
    bloc.add(
      SwitchToWorkspace(
        targetWorkspaceId: second.id,
        currentTabsToSave: [],
        currentTabIndexToSave: 0,
      ),
    );
    await tester.pump();
    AppWindowKeys.activate(b);
    switched.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final warning = find.text(WindowMessages.workspaceOpenInOtherWindow);
    expect(
      find.descendant(of: find.byKey(a.navigator), matching: warning),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(b.navigator), matching: warning),
      findsNothing,
    );
    UiSnack.hide(window: a);
    UiSnack.hide(window: b);
    await tester.pump(const Duration(seconds: 1));
    unawaited(bloc.close());
    await tester.pump();
    AppWindowKeys.resetForTest();
    await tester.pumpWidget(const SizedBox());
  });

  group('WorkspaceBloc tab isolation', () {
    setUp(() async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
    });

    test('שומר snapshot נפרד של הטאבים בעת החלפת שולחן עבודה', () async {
      final firstWorkspace = Workspace(name: 'א', tabs: const []);
      final secondWorkspace = Workspace(name: 'ב', tabs: const []);
      final repository = _FakeWorkspaceRepository(
        workspaces: [firstWorkspace, secondWorkspace],
        activeWorkspaceId: firstWorkspace.id,
      );

      List<OpenedTab>? callbackTabs;
      final bloc = WorkspaceBloc(
        repository: repository,
        onWorkspaceTabsChanged: (tabs, _, _) {
          callbackTabs = tabs;
        },
      )..add(LoadWorkspaces());

      // Wait for LoadWorkspaces to complete (isLoading transitions false→true→false)
      await bloc.stream.firstWhere((s) => !s.isLoading);

      final liveTab = _createTextTab('ספר חי');
      bloc.add(
        SwitchToWorkspace(
          targetWorkspaceId: secondWorkspace.id,
          currentTabsToSave: [liveTab],
          currentTabIndexToSave: 0,
        ),
      );

      // Wait for workspace switch to complete (activeWorkspaceId changes)
      await bloc.stream.firstWhere(
        (s) => s.activeWorkspaceId == secondWorkspace.id,
      );

      final savedWorkspace = bloc.state.workspaces.firstWhere(
        (w) => w.id == firstWorkspace.id,
      );
      expect(savedWorkspace.tabs, hasLength(1));
      expect(savedWorkspace.tabs.first, isNot(same(liveTab)));
      expect(callbackTabs, isNotNull);
      expect(callbackTabs, isEmpty);

      await bloc.close();
      liveTab.dispose();
    });

    test('מעביר ל-UI עותקים נפרדים של טאבי שולחן העבודה היעד', () async {
      final targetTab = _createTextTab('ספר יעד');
      final sourceWorkspace = Workspace(name: 'א', tabs: const []);
      final targetWorkspace = Workspace(name: 'ב', tabs: [targetTab]);
      final repository = _FakeWorkspaceRepository(
        workspaces: [sourceWorkspace, targetWorkspace],
        activeWorkspaceId: sourceWorkspace.id,
      );

      List<OpenedTab>? callbackTabs;
      final bloc = WorkspaceBloc(
        repository: repository,
        onWorkspaceTabsChanged: (tabs, _, _) {
          callbackTabs = tabs;
        },
      )..add(LoadWorkspaces());

      await bloc.stream.firstWhere((s) => !s.isLoading);

      bloc.add(
        SwitchToWorkspace(
          targetWorkspaceId: targetWorkspace.id,
          currentTabsToSave: const [],
          currentTabIndexToSave: 0,
        ),
      );

      await bloc.stream.firstWhere(
        (s) => s.activeWorkspaceId == targetWorkspace.id,
      );

      expect(callbackTabs, isNotNull);
      expect(callbackTabs, hasLength(1));
      expect(callbackTabs!.first, isNot(same(targetWorkspace.tabs.first)));

      await bloc.close();
      targetTab.dispose();
    });

    test('מחליף מצב פעיל רק אחרי שה-UI החליף את הטאבים', () async {
      final sourceWorkspace = Workspace(name: 'א', tabs: const []);
      final targetWorkspace = Workspace(name: 'ב', tabs: const []);
      final repository = _FakeWorkspaceRepository(
        workspaces: [sourceWorkspace, targetWorkspace],
        activeWorkspaceId: sourceWorkspace.id,
      );
      final callbackStarted = Completer<void>();
      final allowTabReplacement = Completer<void>();
      final bloc = WorkspaceBloc(
        repository: repository,
        onWorkspaceTabsChanged: (_, _, _) {
          callbackStarted.complete();
          return allowTabReplacement.future;
        },
      )..add(LoadWorkspaces());

      await bloc.stream.firstWhere((state) => !state.isLoading);
      final switched = bloc.stream.firstWhere(
        (state) => state.activeWorkspaceId == targetWorkspace.id,
      );
      bloc.add(
        SwitchToWorkspace(
          targetWorkspaceId: targetWorkspace.id,
          currentTabsToSave: const [],
          currentTabIndexToSave: 0,
        ),
      );

      await callbackStarted.future;
      expect(bloc.state.activeWorkspaceId, sourceWorkspace.id);

      allowTabReplacement.complete();
      await switched;
      await bloc.close();
    });

    test('כשל שמירה משאיר את הכרטיסיות במקומן ואינו מחליף שולחן', () async {
      final firstWorkspace = Workspace(name: 'א', tabs: const []);
      final secondWorkspace = Workspace(name: 'ב', tabs: const []);
      final repository = _FakeWorkspaceRepository(
        workspaces: [firstWorkspace, secondWorkspace],
        activeWorkspaceId: firstWorkspace.id,
      )..failMutate = false;

      var callbackCalls = 0;
      final bloc = WorkspaceBloc(
        repository: repository,
        onWorkspaceTabsChanged: (_, _, _) => callbackCalls++,
      )..add(LoadWorkspaces());
      await bloc.stream.firstWhere((s) => !s.isLoading);

      repository.failMutate = true;
      final liveTab = _createTextTab('ספר חי');
      bloc.add(
        SwitchToWorkspace(
          targetWorkspaceId: secondWorkspace.id,
          currentTabsToSave: [liveTab],
          currentTabIndexToSave: 0,
        ),
      );

      await bloc.stream.firstWhere((s) => s.error != null);

      // ⚠️ זה הלב: ההחלפה משחררת את הכרטיסיות של השולחן הנעזב, ולכן היא
      // אסורה כשהשמירה נכשלה — אחרת הן אינן בשום box ובשום state.
      expect(callbackCalls, 0);
      expect(bloc.state.activeWorkspaceId, firstWorkspace.id);

      await bloc.close();
      liveTab.dispose();
    });

    test('שולחן מקובע שומר את התמונה הקבועה כשעוזבים אותו (#1619)', () async {
      final pinnedTab = _createTextTab('ספר קבוע');
      final pinned = Workspace(
        name: 'כולל',
        tabs: [pinnedTab],
        isPinned: true,
      );
      final other = Workspace(name: 'ב', tabs: const []);
      final repository = _FakeWorkspaceRepository(
        workspaces: [pinned, other],
        activeWorkspaceId: pinned.id,
      );
      final bloc = WorkspaceBloc(repository: repository)..add(LoadWorkspaces());
      await bloc.stream.firstWhere((s) => !s.isLoading);

      final extraTab = _createTextTab('ספר שנפתח בדרך אגב');
      bloc.add(
        SwitchToWorkspace(
          targetWorkspaceId: other.id,
          currentTabsToSave: [pinnedTab, extraTab],
          currentTabIndexToSave: 1,
        ),
      );
      await bloc.stream.firstWhere((s) => s.activeWorkspaceId == other.id);

      List<OpenedTab>? restored;
      final reopen = WorkspaceBloc(
        repository: repository,
        onWorkspaceTabsChanged: (tabs, _, _) => restored = tabs,
      )..add(LoadWorkspaces());
      await reopen.stream.firstWhere((s) => !s.isLoading);
      reopen.add(
        SwitchToWorkspace(
          targetWorkspaceId: pinned.id,
          currentTabsToSave: const [],
          currentTabIndexToSave: 0,
        ),
      );
      await reopen.stream.firstWhere((s) => s.activeWorkspaceId == pinned.id);

      expect(restored!.map((t) => t.title), ['ספר קבוע']);

      await bloc.close();
      await reopen.close();
      pinnedTab.dispose();
      extraTab.dispose();
    });

    test(
      'אזהרת "פתוח בחלון אחר" שואלת את המקור שהוזרק (ריבוי תצוגות)',
      () async {
        final first = Workspace(name: 'א', tabs: const []);
        final second = Workspace(name: 'ב', tabs: const []);
        final repository = _FakeWorkspaceRepository(
          workspaces: [first, second],
          activeWorkspaceId: first.id,
        );
        final asked = <String>[];
        final bloc = WorkspaceBloc(
          repository: repository,
          isOpenInOtherWindow: (id) {
            asked.add(id);
            return true;
          },
        )..add(LoadWorkspaces());
        await bloc.stream.firstWhere((s) => !s.isLoading);

        bloc.add(
          SwitchToWorkspace(
            targetWorkspaceId: second.id,
            currentTabsToSave: const [],
            currentTabIndexToSave: 0,
          ),
        );
        await bloc.stream.firstWhere((s) => s.activeWorkspaceId == second.id);

        expect(asked, [second.id]);
        await bloc.close();
      },
    );

    test('קיבוע השולחן הפעיל שומר את הכרטיסיות החיות כתמונה הקבועה', () async {
      final workspace = Workspace(name: 'א', tabs: const []);
      final repository = _FakeWorkspaceRepository(
        workspaces: [workspace],
        activeWorkspaceId: workspace.id,
      );
      final bloc = WorkspaceBloc(repository: repository)..add(LoadWorkspaces());
      await bloc.stream.firstWhere((s) => !s.isLoading);

      final liveTab = _createTextTab('ספר חי');
      bloc.add(
        SetWorkspacePinned(
          workspaceId: workspace.id,
          isPinned: true,
          tabsToSave: [liveTab],
        ),
      );
      final pinned = await bloc.stream
          .map((s) => s.workspaces.single)
          .firstWhere((w) => w.isPinned);

      expect(pinned.tabs.map((t) => t.title), ['ספר חי']);

      bloc.add(
        SetWorkspacePinned(workspaceId: workspace.id, isPinned: false),
      );
      final unpinned = await bloc.stream
          .map((s) => s.workspaces.single)
          .firstWhere((w) => !w.isPinned);
      expect(unpinned.tabs, hasLength(1));

      await bloc.close();
      liveTab.dispose();
    });

    test('isPinned נשמר ב-JSON ונעדר ממנו כשהשולחן אינו מקובע', () {
      final plain = Workspace(name: 'א', tabs: const []);
      final pinned = plain.copyWith(isPinned: true);

      expect(plain.toJson().containsKey('isPinned'), isFalse);
      expect(Workspace.fromJson(plain.toJson()).isPinned, isFalse);
      expect(Workspace.fromJson(pinned.toJson()).isPinned, isTrue);
    });

    test('שגיאה אינה נמחקת ב-emit הבא, ו-clearError מאפס אותה', () {
      final state = WorkspaceState(workspaces: const [], error: 'boom');

      expect(state.copyWith(isLoading: true).error, 'boom');
      expect(state.copyWith(clearError: true).error, isNull);
    });

    test('copyWith יכול לאפס את השולחן הפעיל ל-null', () {
      final state = WorkspaceState(
        workspaces: const [],
        activeWorkspaceId: 'w1',
      );

      expect(state.copyWith(activeWorkspaceId: null).activeWorkspaceId, 'w1');
      expect(
        state.copyWith(clearActiveWorkspaceId: true).activeWorkspaceId,
        isNull,
      );
    });
  });

  group('WorkspaceBloc כשהרשימה מתמלאת בזמן הטעינה', () {
    setUp(() async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
    });

    test('אינו ננעל על השולחן של הבעלים כשהרשימה חוזרת לא ריקה', () async {
      // המרוץ: `load` מחזיר רשימה ריקה כי הבעלים עוד טוען, אבל עד ה-`mutate`
      // הרשימה שלו כבר קיימת — וה-`apply` מחזיר את השולחנות שלו.
      final ownerWorkspace = Workspace(name: 'של הבעלים', tabs: const []);
      final repository = _FakeWorkspaceRepository.empty()
        ..workspacesOnMutate = [ownerWorkspace];

      final bloc = WorkspaceBloc(repository: repository)..add(LoadWorkspaces());
      await bloc.stream.firstWhere((s) => !s.isLoading);

      expect(bloc.state.workspaces, hasLength(1));
      expect(bloc.state.activeWorkspaceId, isNull);

      await bloc.close();
    });
  });
}

TextBookTab _createTextTab(String title) {
  return TextBookTab(
    book: TextBook(title: title),
    index: 0,
  );
}

class _FakeWorkspaceRepository extends WorkspaceRepository {
  _FakeWorkspaceRepository({
    required List<Workspace> workspaces,
    required String this._activeWorkspaceId,
  }) : _workspaces = List<Workspace>.from(workspaces);

  /// רשימה ריקה בטעינה — כמו חלון משני שנפתח בזמן שהבעלים עוד טוען.
  _FakeWorkspaceRepository.empty()
    : _workspaces = <Workspace>[],
      _activeWorkspaceId = null;

  List<Workspace> _workspaces;
  String? _activeWorkspaceId;

  /// `mutateWorkspaces` זורק — כמו `SharedHiveUnavailable` בחלון משני.
  bool failMutate = false;

  /// מה שיהיה ברשימה ברגע ה-`mutate`, גם אם הטעינה החזירה ריק.
  List<Workspace>? workspacesOnMutate;

  @override
  Future<(List<Workspace>, String?)> loadWorkspaces() async =>
      (List<Workspace>.from(_workspaces), _activeWorkspaceId);

  @override
  Future<List<Workspace>> mutateWorkspaces(
    List<Workspace> Function(List<Workspace> current) apply,
  ) async {
    if (failMutate) throw StateError('shared store unavailable');
    final current = workspacesOnMutate ?? _workspaces;
    _workspaces = List<Workspace>.from(apply(List<Workspace>.from(current)));
    workspacesOnMutate = null;
    return List<Workspace>.from(_workspaces);
  }

  @override
  Future<void> saveActiveWorkspaceId(String? id) async {
    _activeWorkspaceId = id;
  }
}
