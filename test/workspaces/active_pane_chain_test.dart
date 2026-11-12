import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/workspaces/workspace.dart';
import 'package:otzaria/workspaces/workspace_repository.dart';

import '../helpers/memory_settings_cache.dart';

/// שרשרת ה-`activePane` עוברת שישה גבולות: `TabsState.activePaneSide` →
/// `SwitchToWorkspace` → `WorkspaceBloc` → `onWorkspaceTabsChanged` →
/// `ReplaceAllTabs` → `paneForSide` → `ActivePaneUpdate`.
///
/// כל חוליה נבדקת בנפרד במקום אחר, אבל **החיווט ביניהן** לא היה מכוסה —
/// ודווקא שם מסתתרות התקלות: מספיק שצד אחד יתרגם "ימין" הפוך, או ששלב
/// אחד ישמיט את הערך, כדי שהתכונה כולה תשתוק בלי שאף בדיקה תיפול.
///
/// ההצלבה קריטית במיוחד כאן משום ש-`WorkspaceBloc._cloneTabs` **משכפל**
/// את הטאבים: אובייקט החלונית שיוצא אינו זה שנכנס, ולכן הזהות אובדת בדרך
/// והצד הוא הדבר היחיד ששורד.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  PdfBookTab leaf(String title) => PdfBookTab(
    book: PdfBook(title: title, path: '/nonexistent/$title.pdf'),
    pageNumber: 1,
  );

  /// מריץ את השרשרת המלאה: קובע חלונית פעילה בשולחן א', עובר לשולחן ב'
  /// וחוזר — ומחזיר את ה-TabsBloc אחרי החזרה.
  Future<({TabsBloc tabs, OpenedTab restoredActive, String? sideSent})>
  roundTrip({required bool activateLeft}) async {
    final right = leaf('ימין');
    final left = leaf('שמאל');
    final split = CombinedTab(rightTab: right, leftTab: left);

    final tabsBloc = TabsBloc(repository: _FakeTabsRepository());
    addTearDown(tabsBloc.close);
    tabsBloc.add(ReplaceAllTabs([split], 0));
    await tabsBloc.stream.firstWhere((s) => s.tabs.isNotEmpty);

    // המשתמש בוחר חלונית. `_onSetActivePane` יוצא מוקדם כשהחלונית כבר
    // הפעילה, ו-`rightTab` הוא ברירת המחדל של `_resolveActivePane` — ולכן
    // בחירתו אינה פולטת state ואין אירוע להמתין לו.
    final target = activateLeft ? left : right;
    if (!identical(tabsBloc.state.activePane, target)) {
      tabsBloc.add(SetActivePane(target));
      await tabsBloc.stream.firstWhere(
        (s) => identical(s.activePane, target),
      );
    }
    expect(identical(tabsBloc.state.activePane, target), isTrue);

    final workspaceA = Workspace(name: 'א', tabs: const []);
    final workspaceB = Workspace(name: 'ב', tabs: const []);
    final repository = _FakeWorkspaceRepository(
      workspaces: [workspaceA, workspaceB],
      activeWorkspaceId: workspaceA.id,
    );

    String? sideSent;
    final workspaceBloc = WorkspaceBloc(
      repository: repository,
      // בדיוק החיווט שב-main.dart.
      onWorkspaceTabsChanged: (tabs, activeIndex, activePane) {
        sideSent = activePane;
        tabsBloc.add(
          ReplaceAllTabs(tabs, activeIndex, activePane: activePane),
        );
      },
    )..add(LoadWorkspaces());
    addTearDown(workspaceBloc.close);
    await workspaceBloc.stream.firstWhere((s) => !s.isLoading);

    // בדיוק החיווט שב-workspace_switcher_dialog.
    final emptiedTabs = tabsBloc.stream.firstWhere((s) => s.tabs.isEmpty);
    workspaceBloc.add(
      SwitchToWorkspace(
        sourceWorkspaceId: workspaceBloc.state.activeWorkspaceId,
        targetWorkspaceId: workspaceB.id,
        readCurrentTabs: () => (
          tabs: tabsBloc.state.tabs,
          activeTabIndex: tabsBloc.state.currentTabIndex,
          activePane: tabsBloc.state.activePaneSide,
        ),
      ),
    );
    await workspaceBloc.stream.firstWhere(
      (s) => s.activeWorkspaceId == workspaceB.id,
    );
    await emptiedTabs;

    // חזרה לשולחן א' — כאן הצד השמור אמור לחזור לחיים.
    final restoredTabs = tabsBloc.stream.firstWhere((s) => s.tabs.isNotEmpty);
    workspaceBloc.add(
      SwitchToWorkspace(
        sourceWorkspaceId: workspaceBloc.state.activeWorkspaceId,
        targetWorkspaceId: workspaceA.id,
        readCurrentTabs: () => (
          tabs: tabsBloc.state.tabs,
          activeTabIndex: tabsBloc.state.currentTabIndex,
          activePane: tabsBloc.state.activePaneSide,
        ),
      ),
    );
    await workspaceBloc.stream.firstWhere(
      (s) => s.activeWorkspaceId == workspaceA.id,
    );
    await restoredTabs;

    return (
      tabs: tabsBloc,
      restoredActive: tabsBloc.state.activePane!,
      sideSent: sideSent,
    );
  }

  test('החלונית השמאלית שנבחרה חוזרת אחרי מעבר הלוך-ושוב', () async {
    final result = await roundTrip(activateLeft: true);

    final restoredSplit = result.tabs.state.tabs.single as CombinedTab;
    expect(result.sideSent, kLeftPaneSide);
    // ⚠️ הזהות חייבת להיות מול החלונית **המשוחזרת**, לא המקורית: הטאבים
    // שוכפלו בדרך, ולכן השוואה למקור הייתה עוברת גם אילו נשמר הצד הלא נכון.
    expect(identical(result.restoredActive, restoredSplit.leftTab), isTrue);
    expect(result.restoredActive.title, 'שמאל');
  });

  test('החלונית הימנית שנבחרה חוזרת — והיא גם panes.first', () async {
    // המקרה שנראה "עובד תמיד": rightTab הוא גם ברירת המחדל של
    // `_resolveActivePane`, ולכן הוא היחיד שהיה עובר גם בלי התכונה כולה.
    // נבדק כדי שהבדיקה הראשונה לא תישאר לבד.
    final result = await roundTrip(activateLeft: false);

    final restoredSplit = result.tabs.state.tabs.single as CombinedTab;
    expect(result.sideSent, kRightPaneSide);
    expect(identical(result.restoredActive, restoredSplit.rightTab), isTrue);
    expect(result.restoredActive.title, 'ימין');
  });

  test('טאב שאינו מפוצל — אין צד לשמור, ואין קריסה בשחזור', () async {
    final single = leaf('בודד');
    final tabsBloc = TabsBloc(repository: _FakeTabsRepository());
    addTearDown(tabsBloc.close);
    tabsBloc.add(ReplaceAllTabs([single], 0));
    await tabsBloc.stream.firstWhere((s) => s.tabs.isNotEmpty);

    expect(tabsBloc.state.activePaneSide, isNull);

    // צד שנשמר בטעות על טאב שאינו מפוצל נפתר ל-null ונופל ל-panes.first.
    tabsBloc.add(
      ReplaceAllTabs([leaf('אחר')], 0, activePane: kLeftPaneSide),
    );
    await tabsBloc.stream.firstWhere(
      (s) => s.tabs.isNotEmpty && s.tabs.single.title == 'אחר',
    );

    expect(tabsBloc.state.rawActivePane, isNull);
    expect(tabsBloc.state.activePane!.title, 'אחר');
  });

  test('מעבר בין שני שולחנות ריקים מסתיים ואינו תוקע מעברים הבאים', () async {
    final tabsBloc = TabsBloc(repository: _FakeTabsRepository());
    addTearDown(tabsBloc.close);
    // אחרי פליטה ראשונה Bloc מדלג על state זהה, ובלעדיה הבאג לא משתחזר.
    final tab = leaf('זמני');
    tabsBloc.add(AddTab(tab));
    tabsBloc.add(RemoveTab(tab));
    await tabsBloc.stream.firstWhere((s) => s.tabs.isEmpty);

    final workspaceA = Workspace(name: 'א', tabs: const []);
    final workspaceB = Workspace(name: 'ב', tabs: const []);
    final workspaceBloc = WorkspaceBloc(
      repository: _FakeWorkspaceRepository(
        workspaces: [workspaceA, workspaceB],
        activeWorkspaceId: workspaceA.id,
      ),
      // בדיוק ההמתנה שב-main.dart.
      onWorkspaceTabsChanged: (tabs, activeIndex, activePane) async {
        final replaced = tabsBloc.stream.firstWhere(
          (state) =>
              identical(state.tabs, tabs) &&
              state.currentTabIndex == activeIndex,
        );
        tabsBloc.add(
          ReplaceAllTabs(tabs, activeIndex, activePane: activePane),
        );
        await replaced;
      },
    )..add(LoadWorkspaces());
    addTearDown(workspaceBloc.close);
    await workspaceBloc.stream.firstWhere((s) => !s.isLoading);

    for (final target in [workspaceB, workspaceA]) {
      workspaceBloc.add(
        SwitchToWorkspace(
          sourceWorkspaceId: workspaceBloc.state.activeWorkspaceId,
          targetWorkspaceId: target.id,
          readCurrentTabs: () => (
            tabs: tabsBloc.state.tabs,
            activeTabIndex: tabsBloc.state.currentTabIndex,
            activePane: null,
          ),
        ),
      );
      await workspaceBloc.stream
          .firstWhere((s) => s.activeWorkspaceId == target.id)
          .timeout(const Duration(seconds: 5));
    }
  });
}

class _FakeTabsRepository extends TabsRepository {
  @override
  List<OpenedTab> loadTabs({bool newRuntime = false}) => const [];

  @override
  int loadCurrentTabIndex() => 0;

  @override
  Future<void> saveTabs(List<OpenedTab> tabs, int currentTabIndex) async {}

  @override
  Future<void> saveCurrentTabIndex(
    List<OpenedTab> tabs,
    int currentTabIndex,
  ) async {}
}

class _FakeWorkspaceRepository extends WorkspaceRepository {
  _FakeWorkspaceRepository({
    required List<Workspace> workspaces,
    required String this._activeWorkspaceId,
  }) : _workspaces = List<Workspace>.from(workspaces);

  List<Workspace> _workspaces;
  String? _activeWorkspaceId;

  @override
  Future<(List<Workspace>, String?)> loadWorkspaces() async =>
      (List<Workspace>.from(_workspaces), _activeWorkspaceId);

  @override
  Future<List<Workspace>> mutateWorkspaces(
    List<Workspace> Function(List<Workspace> current) apply,
  ) async {
    _workspaces = List<Workspace>.from(
      apply(List<Workspace>.from(_workspaces)),
    );
    return List<Workspace>.from(_workspaces);
  }

  @override
  Future<void> saveActiveWorkspaceId(String? id) async {
    _activeWorkspaceId = id;
  }
}
