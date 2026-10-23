import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/app_scope/process_duties.dart';
import 'package:otzaria/attached_libraries/bloc/attached_libraries_bloc.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/startup_timeline.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/multiview/in_process_tab_drop.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/window_fullscreen_cubit.dart';
import 'package:otzaria/find_ref/bloc/find_ref_bloc.dart';
import 'package:otzaria/find_ref/repository/find_ref_factory.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/history_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/navigation_repository.dart';
import 'package:otzaria/personal_notes/bloc/personal_notes_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/declarative/services/declarative_library_book_access.dart';
import 'package:otzaria/plugins/declarative/services/declarative_plugin_host_service.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_reader_actions.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_client.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';
import 'package:otzaria/widgets/misc/link_preview_overlay.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_event.dart';
import 'package:otzaria/workspaces/workspace_repository.dart';

/// ספקים של חלון אחד: כל מה שמחזיק מצב של החלון. נשען על [AppScopeProviders]
/// שמעליו; הכיוון ההפוך (ספק תהליך שקורא ספק חלון) אסור.
class WindowScopeProviders extends StatelessWidget {
  const WindowScopeProviders({
    super.key,
    required this.historyRepository,
    this.initialTab,
    this.tabsSession,
    this.duties,
    this.initialFullscreen,
    required this.child,
  });

  final HistoryRepository historyRepository;

  /// כרטיסיה שהחלון נפתח איתה; נוספת פעם אחת, ביצירת `TabsBloc`.
  final OpenedTab? initialTab;

  /// סשן הכרטיסיות של החלון; `null` — [WindowTabsSession.current].
  final WindowTabsSession? tabsSession;

  /// `null` — [ProcessDuties.current], וה-`PluginSystemBloc` קורא אותו בכל אירוע.
  final ProcessDuties? duties;

  /// מצב החלון בפועל; null משמר את שחזור חלון ה־window_manager מההגדרות.
  final bool? initialFullscreen;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<_WindowUiLifetime>(
          lazy: false,
          create: (_) => _WindowUiLifetime(AppWindowKeys.of(context)),
          dispose: (lifetime) => lifetime.dispose(),
        ),
        // של החלון הזה ולא של החלון הפעיל, שבזמן היצירה עשוי להיות אחר.
        RepositoryProvider<FocusRepository>(
          create: (context) =>
              FocusRepository.forWindow(AppWindowKeys.of(context)),
        ),
        RepositoryProvider<ProcessDuties>.value(
          value: duties ?? ProcessDuties.current,
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<LibraryBloc>(
            // ה-LoadLibrary אינו נשלח כאן יותר: בניית הקטלוג (~300ms CPU על
            // ה-main thread) הייתה חונקת את שאילתת תוכן הספר הפעיל ומעכבת את
            // הופעתו. ההפעלה עברה ל-MainWindowScreen._revealMainWindowOnce,
            // שמעדיף את טעינת הספר הפעיל ורק אז מתחיל את בניית הקטלוג.
            create: (_) => LibraryBloc(),
          ),
          BlocProvider<CustomFoldersBloc>(
            create: (context) => CustomFoldersBloc(
              addLibraryEvent: (event) =>
                  context.read<LibraryBloc>().add(event),
            )..add(const LoadCustomFolders()),
          ),
          // לא עצל: הבלוק מאזין לשינויי המסדים המצורפים (גם מהסריקה בעלייה)
          // ומרענן את העץ, גם כשמסך ההגדרות לא נפתח.
          BlocProvider<AttachedLibrariesBloc>(
            lazy: false,
            create: (context) => AttachedLibrariesBloc(
              addLibraryEvent: (event) =>
                  context.read<LibraryBloc>().add(event),
            ),
          ),
          BlocProvider<TabsBloc>(
            create: (_) {
              final bloc = StartupTimeline.instance.phaseSync(
                'tabsBloc',
                () {
                  final repository = TabsRepository(window: tabsSession);
                  return TabsBloc(
                    repository: repository,
                    session: repository.window,
                  )..add(LoadTabs());
                },
              );
              // `LoadTabs` נשלח קודם כדי שסדר האירועים יהיה זהה לחלון רגיל —
              // הכרטיסיה המועברת נכנסת אחריו, ולכן היא זו שתהיה פעילה.
              final tab = initialTab;
              if (tab != null) bloc.add(AddTab(tab));
              return bloc;
            },
          ),
          // ⚠️ אחרי TabsBloc: ה-context של create רואה רק ספקים שמעליו.
          // נלכד כאן ולא ב-currentTab: ב-close() ה-context כבר מפורק.
          BlocProvider<HistoryBloc>(
            create: (context) {
              final tabsBloc = context.read<TabsBloc>();
              return HistoryBloc(
                historyRepository,
                currentTab: () => tabsBloc.state.currentTab,
              );
            },
          ),
          BlocProvider<NavigationBloc>(
            create: (context) {
              // הבנאי משחזר את כל הכרטיסיות השמורות סינכרונית (loadTabs) —
              // נמדד כי זה רץ בתוך build, לפני שהמסך הראשי קיים.
              final nav = StartupTimeline.instance.phaseSync(
                'navigationBloc',
                () =>
                    NavigationBloc(
                      repository: NavigationRepository(),
                      tabsRepository: TabsRepository(window: tabsSession),
                      // "חיפוש" ו"עיון" הם אותו עמוד טאבים; היישור לפי
                      // החלונית הפעילה שומר שהאייקון המודגש בסרגל יתאים
                      // למה שמוצג בפועל.
                      activePaneStream: context
                          .read<TabsBloc>()
                          .stream
                          .map((tabsState) => tabsState.activePane)
                          .distinct(),
                    )..add(
                      const CheckLibrary(),
                    ),
              );
              // ⚠️ אחרי `CheckLibrary` ולא במקומו. `CheckLibrary` מחליט
              // לאן לנווט לפי מצב הספרייה, ובחלון שנפתח עם כרטיסיה מועברת
              // ההחלטה שגויה: הוא היה נשאר במסך הספרייה בעוד הכרטיסיה
              // פתוחה מאחוריו — בדיוק מה שנצפה. הניווט נשלח אחריו ולכן
              // גובר עליו.
              if (AppWindowScope.roleOf(context).openedWithTab) {
                nav.add(const NavigateToScreen(Screen.reading));
              }
              return nav;
            },
          ),
          BlocProvider<FindRefBloc>(
            create: (_) => FindRefBloc(
              findRefRepository: buildFindRefRepository(),
            ),
          ),
          BlocProvider<PersonalNotesBloc>(
            create: (_) => PersonalNotesBloc(),
          ),
          BlocProvider<WorkspaceBloc>(
            create: (context) {
              final tabsBloc = context.read<TabsBloc>();
              final session = tabsSession;
              return WorkspaceBloc(
                repository: WorkspaceRepository(
                  slot: session == null ? null : () => session.slot,
                ),
                onWorkspaceTabsChanged:
                    (
                      List<OpenedTab> tabs,
                      int activeIndex,
                      String? activePane,
                    ) async {
                      // ⚠️ ההמתנה נרשמת **לפני** השליחה: `ReplaceAllTabs`
                      // מטופל סינכרונית, ורישום אחריו היה מפספס את המצב
                      // שהוא מחפש ומחכה לנצח.
                      final replaced = tabsBloc.stream.firstWhere(
                        (state) =>
                            identical(state.tabs, tabs) &&
                            state.currentTabIndex == activeIndex,
                      );
                      tabsBloc.add(
                        ReplaceAllTabs(
                          tabs,
                          activeIndex,
                          activePane: activePane,
                        ),
                      );
                      await replaced;
                    },
              )..add(LoadWorkspaces());
            },
          ),
          BlocProvider<WorkStatusCubit>(
            create: (_) => WorkStatusCubit(),
          ),
          BlocProvider<WindowFullscreenCubit>(
            create: (_) => WindowFullscreenCubit(initial: initialFullscreen),
          ),
          BlocProvider<PluginSystemBloc>(
            create: (context) => StartupTimeline.instance.phaseSync(
              'pluginSystemBloc',
              () => _createPluginSystemBloc(context, duties),
            ),
          ),
        ],
        // ריבוי תצוגות: יעד להעברת כרטיסיה ישירה מחלון אחר בתהליך.
        child: MultiViewMode.enabled
            ? InProcessTabDropReceiver(child: child)
            : child,
      ),
    );
  }
}

class _WindowUiLifetime {
  _WindowUiLifetime(this.keys);
  final AppWindowKeys keys;

  void dispose() {
    UiSnack.hide(window: keys);
    LinkPreviewOverlay.dismiss(window: keys);
  }
}

PluginSystemBloc _createPluginSystemBloc(
  BuildContext context,
  ProcessDuties? duties,
) {
  final repository = PluginRegistryRepository();
  final tabsBloc = context.read<TabsBloc>();
  final coordinator = BookOpenCoordinator(
    tabsBloc: tabsBloc,
    historyBloc: context.read<HistoryBloc>(),
    navigationBloc: context.read<NavigationBloc>(),
    layoutWidth: readingLayoutWidthResolverOf(context),
  );
  final bookAccess = DeclarativeLibraryBookAccess.otzaria(
    coordinator,
  );
  final toolbar = PluginToolbarRegistry.forWindow();
  final host = DeclarativePluginHostService(
    toolbarRegistry: toolbar,
    loadPlugin: repository.getPlugin,
    loadPermissions: (pluginId) async =>
        (await repository.getGrantedPermissionNames(
          pluginId,
        )).toSet(),
    bookResolver: bookAccess,
    bookOpener: bookAccess,
    parallelEditionsFinder: bookAccess.parallelEditionsForIdentity,
    readerScroller: PluginDeclarativeReaderScroller(
      tabsBloc: tabsBloc,
    ),
    searchOpener: PluginDeclarativeSearchOpener(coordinator),
    onError: (pluginId, error, stackTrace) => debugPrint(
      'Declarative plugin host [$pluginId]: $error\n$stackTrace',
    ),
  );
  return PluginSystemBloc(
      repository: repository,
      alertsClient: CalendarAlertsClient.forCurrentWindow(),
      declarativeHost: host,
      toolbarRegistry: toolbar,
      readerStates: tabsBloc.stream,
      initialReaderState: tabsBloc.state,
      processDuties: duties,
    )
    ..add(const SeedBundledPlugins())
    ..add(LoadPlugins());
}
