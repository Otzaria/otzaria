// לתחזוקת חיבור הסיור המודרך למסך הראשי ראו:
// docs/guided_tour_developer_guide.md

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:collection/collection.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/startup_indexing_decision.dart';
import 'package:otzaria/navigation/view/startup_work_gate.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/find_ref/bloc/find_ref_bloc.dart';
import 'package:otzaria/find_ref/view/find_ref_dialog.dart';
import 'package:otzaria/find_ref/bloc/find_ref_event.dart';
import 'package:otzaria/find_ref/bloc/find_ref_state.dart';
import 'package:otzaria/library/models/library.dart' as library_model;
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/library/view/library_browser.dart';
import 'package:otzaria/tabs/reading_screen.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/text_book/view/widgets/nav_panel_tour_target.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/pdf_book/view/pdf_book_screen.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tools/open_tool_tab.dart';
import 'package:otzaria/tools/tools_launcher_controller.dart';
import 'package:otzaria/tools/view/tools_launcher_panel.dart';
import 'package:otzaria/shortcuts/keyboard_shortcuts.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'dart:async';
import 'package:otzaria/update/my_update_widget.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/widgets/dialogs/ad_popup_dialog.dart';
import 'package:window_manager/window_manager.dart';
import 'package:otzaria/main.dart' show appWindowListener, presentMainWindow;
import 'package:otzaria/core/splash_screen.dart' show SplashIcon;
import 'package:otzaria/navigation/view/custom_title_bar.dart';
import 'package:otzaria/migration/sync/background_sync_initializer.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/workspaces/bloc/workspace_state.dart';
import 'package:otzaria/widgets/layout/context_overlay_panel.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/work_status/work_status_item.dart';
import 'package:otzaria/work_status/work_status_overlay.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/view/history_screen.dart';
import 'package:otzaria/bookmarks/view/bookmark_screen.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/library_update/library_update_work_status.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/utils/ui/fullscreen_helper.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/navigation/nav_rail_item.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/services/windows_jump_list_service.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/utils/fluent_icon_resolver.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart'
    show buildThemePayloadFromScheme;
import 'package:otzaria/theme/app_theme_data.dart' show AppThemeData;
import 'package:otzaria/core/external_activation_queue.dart';
import 'package:otzaria/core/external_activation_channel.dart';
import 'package:otzaria/core/external_uri_router.dart';
import 'package:otzaria/tools/built_in_tools_catalog.dart';
import 'package:otzaria/plugins/services/reader_location_tracker.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/tour/models/live_tip.dart';
import 'package:otzaria/tour/models/tour_step.dart';
import 'package:otzaria/tour/tour_target_keys.dart';
import 'package:otzaria/tour/view/tour_overlay_screen.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/plugins/view/plugin_background_host.dart';
import 'package:otzaria/plugins/view/plugin_install_screen.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/utils/navigation/external_action_dispatcher.dart';
import 'package:otzaria/utils/navigation/open_book.dart';
import 'package:kosher_dart/kosher_dart.dart' show Daf;
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart'
    show getDafYomi, formatAmud;
import 'package:otzaria/tools/calendar/helpers/daf_yomi_navigation.dart'
    show openDafYomiBook;

/// פריט מאוחד לסרגל הניווט הראשי — מייצג תוסף או כלי-מובנה שהוצמד לסרגל.
///
/// סרגל הניווט מטפל בשניהם באופן זהה (אותו אזור, אותה מסלול ניווט אל מסך
/// הכלים). ייצוג מאוחד חוסך כפילות בלוגיקת ה-`_buildBarDestinations` /
/// `_getBarSelectedIndex` / `_onBarNavTap`.
class _PinnedToolNavItem {
  final String toolId;
  final String label;

  /// אייקון Fluent. `null` רק אם הפריט משתמש ב-[imageAsset] במקום.
  final IconData? icon;

  /// נכס תמונה (PNG/SVG דרך AssetImage). מועדף אם קיים — תואם לכלים
  /// מובנים כמו "שמור וזכור" שמשתמשים בלוגו ייחודי במקום באייקון Fluent.
  final String? imageAsset;

  /// `true` עבור תוסף, `false` עבור כלי מובנה. שימושי כי בעת בחירה
  /// תוספים פותחים דרך `openPluginTransiently` בעוד שכלים מובנים פותחים
  /// דרך `requestOpenTool`.
  final bool isPlugin;
  final InstalledPlugin? plugin;

  const _PinnedToolNavItem({
    required this.toolId,
    required this.label,
    required this.isPlugin,
    this.icon,
    this.imageAsset,
    this.plugin,
  }) : assert(
         icon != null || imageAsset != null,
         'pinned nav item must have an icon or image asset',
       );

  factory _PinnedToolNavItem.fromBuiltIn(BuiltInToolMeta meta) {
    return _PinnedToolNavItem(
      toolId: meta.toolId,
      label: meta.label,
      icon: meta.icon,
      imageAsset: meta.imageIcon,
      isPlugin: false,
    );
  }

  factory _PinnedToolNavItem.fromPlugin(InstalledPlugin plugin) {
    return _PinnedToolNavItem(
      toolId: plugin.pluginId,
      label: plugin.manifest.toolTabTitle,
      icon:
          fluentIconFromName(plugin.manifest.toolTabIconName) ??
          FluentIcons.puzzle_piece_24_regular,
      isPlugin: true,
      plugin: plugin,
    );
  }

  /// ה-widget של האייקון לשימוש ב-Bar וב-NavRail.
  Widget buildIcon() {
    if (imageAsset != null) {
      return ImageIcon(AssetImage(imageAsset!), size: 24);
    }
    return RtlIcon(icon!);
  }
}

class MainWindowScreen extends StatefulWidget {
  const MainWindowScreen({super.key});

  @override
  MainWindowScreenState createState() => MainWindowScreenState();
}

enum LibraryPageBuildDecision {
  buildRealPage,
  usePlaceholder,
  keepExistingPage,
}

@visibleForTesting
LibraryPageBuildDecision resolveLibraryPageBuildDecision({
  required bool hasBuiltRealPage,
  required Screen currentScreen,
}) {
  // LibraryBrowser הוא תמיד עמוד הספרייה (גם כשאין ספרייה — הוא מציג את מסך
  // ההגדרה בתוך אזור התוכן), ולכן אין צורך לבנותו מחדש על שינוי מצב. בונים אותו
  // פעם אחת כשהמשתמש מבקש את הספרייה; עד אז placeholder זול.
  if (hasBuiltRealPage) {
    return LibraryPageBuildDecision.keepExistingPage;
  }
  return currentScreen == Screen.library
      ? LibraryPageBuildDecision.buildRealPage
      : LibraryPageBuildDecision.usePlaceholder;
}

final GlobalKey<State<LibraryBrowser>> libraryBrowserKey =
    GlobalKey<State<LibraryBrowser>>();
final GlobalKey<MainWindowScreenState> mainWindowScreenKey =
    GlobalKey<MainWindowScreenState>();

class MainWindowScreenState extends State<MainWindowScreen>
    with TickerProviderStateMixin {
  // לא final: ה-controller נוצר מחדש בעת שינוי אוריינטציה
  // (ראה _handleOrientationChange) כדי למנוע מצב שבו pixel offset מהציר
  // הישן (vertical) מתפרש כעמוד שגוי בציר החדש (horizontal).
  late PageController pageController;

  // --- מצב מעבר slide בין מסכים לא-סמוכים ---
  // כדי לקבל החלקה (slide) ישירה מ"ספריה" ל"כלים" בלי שעמוד הביניים ("עיון")
  // ייראה, מציבים זמנית את מסך היעד בעמוד-השכן בכיוון התנועה, מחליקים מרחק 1,
  // ובסיום קופצים למיקום האמיתי של היעד (ה-GlobalKey מעביר את ה-Element בלי
  // בנייה מחדש, כך שה-WebView של הכלים אינו נטען מחדש).

  /// אינדקס היעד האמיתי במהלך slide חוצה (null כשאין מעבר פעיל).
  int? _transitionTargetIndex;

  /// העמוד-השכן הזמני שאליו מחליקים בפועל (current ± 1).
  int? _transitionSlotIndex;

  /// שמירה מפני מעברים חופפים (לחיצות ניווט מהירות).
  bool _isCrossSliding = false;

  late final CalendarCubit _calendarCubit;
  late final SettingsScreenController _settingsScreenController;
  final ExternalActivationQueue _externalActivationQueue =
      const ExternalActivationQueue();
  late final TourCubit _tourCubit;
  final ExternalActivationChannel _externalActivationChannel =
      ExternalActivationChannel();
  ReaderLocationTracker? _readerLocationTracker;
  Orientation? _previousOrientation;
  int _currentPageIndex = 0;

  // עמוד הספרייה נבנה דינמית ב-build(); LibraryBrowser הוא תמיד עמוד הספרייה
  // ומציג בעצמו את מסך ההגדרה כשאין ספרייה.
  List<Widget> _pages = [];

  // שמירת הדפים כדי שלא ייבנו מחדש
  Widget? _cachedLibraryPage;
  Widget? _cachedReadingPage;
  Widget? _cachedSettingsPage;

  // GlobalKeys יציבים למסכי עיון והגדרות. במהלך slide חוצה (buildTransitionPages)
  // המסכים זזים בעץ דרך swap; ה-keys מאפשרים ל-Flutter לזהות שמדובר באותם מסכים
  // ולהעביר (reparent) את ה-State במקום לפרק ולבנות מחדש. (מסך הכלים כבר מותג
  // ב-moreScreenKey; מסך הספרייה ב-libraryBrowserKey.)
  final GlobalKey _readingScreenKey = GlobalKey();
  final GlobalKey _settingsScreenKey = GlobalKey();

  // האם LibraryBrowser האמיתי כבר נבנה (אחרי שהמשתמש ביקש את הספרייה); עד אז
  // מוצג placeholder זול.
  bool _hasBuiltRealLibraryPage = false;

  final StartupWorkGate _startupWorkGate = StartupWorkGate();
  final IndexingRepository _indexingRepository = IndexingRepository(
    TantivyDataProvider.instance,
  );
  bool _hasCheckedAutoIndex = false;
  // מסך הפתיחה (סמל צף) מוצג עד שתוכן הטאב הפעיל נטען, ואז החלון הקטן/השקוף
  // מתרחב לחלון המלא. ראה _scheduleSplashReveal / _revealNow.
  bool _initialContentReady = false;
  // אוברליי הסמל הצף מוסר רק *אחרי* שהתוכן צויר בפועל — כך הסמל גלוי ברצף
  // (בלי רגע ריק) וגם "מגשר" על זמן הציור הקר של ה-UI. נפרד מ-_initialContentReady
  // (שמפעיל את ה-Opacity של התוכן). ראה _revealMainWindowOnce.
  bool _splashOverlayVisible = true;
  // משמש כשומר re-entry: החשיפה מתבצעת אסינכרונית (presentMainWindow עם
  // await), כך ש-_initialContentReady נקבע מאוחר; הדגל הזה מונע כניסה כפולה
  // בזמן ה-await (failsafe timer + stream listener).
  bool _revealStarted = false;
  bool _hasScheduledSplashReveal = false;
  Timer? _splashFailsafeTimer;
  bool _isShowingStartupManualReindexDialog = false;
  // מסומן כשעדכון ספרייה הוחל, כדי להפעיל אינדוקס אחרי הטעינה מחדש הבאה
  // (ה-_checkAndStartIndexing הרגיל רץ פעם אחת בעלייה ולא מכסה עדכון חי).
  bool _indexAfterLibraryReload = false;
  // מסומן אחרי הורדה מלאה: אין דיווח אילו ספרים השתנו, ולכן אחרי הטעינה
  // מחדש מריצים reconcile — השוואת טביעות-אצבע ואינדוקס מחדש של השונים.
  bool _reconcileAfterLibraryReload = false;
  // אחרי עדכון DB, StartIndexing מכסה את כל הספרייה; ה-gate מונע מ-listener
  // ה-newBooksToIndex להריץ מסלול אינדוקס שני על אותו refresh.
  bool _dbUpdateTriggeredFullIndex = false;
  bool _isShowingFullDownloadDialog = false;
  bool _isSearchOpen = false;
  bool _isFindRefOpen = false;
  bool _isReadingSettingsPanelOpen = false;
  bool _isToolsLauncherOpen = false;
  bool _openGenesisForTour = false;
  bool _tourStartedAutomaticallyThisLaunch = false;
  OverlayEntry? _tourOverlayEntry;
  bool _tourOverlayInsertScheduled = false;
  bool _tourOpenedOverflowMenu = false;
  late Screen _lastScreen;
  // עוקב אחר מצב ההגדרות הקודם לצורך dispatch ספציפי
  SettingsState? _prevSettingsState;
  // עוקב אחר מצב הלוח הקודם לצורך dispatch ספציפי
  CalendarState? _prevCalendarState;

  bool _hasInitializedPageController = false;
  bool _isProcessingExternalActivations = false;
  StreamSubscription<FileSystemEvent>? _externalActivationWatchSub;
  StreamSubscription<String>? _externalActivationChannelSub;
  final WindowsJumpListService _jumpListService = WindowsJumpListService();

  static const List<
    ({
      Screen? screen,
      IconData icon,
      IconData iconFilled,
      String label,
      String shortcutKey,
    })
  >
  _navData = [
    (
      screen: Screen.library,
      icon: FluentIcons.library_24_regular,
      iconFilled: FluentIcons.library_24_filled,
      label: 'ספרייה',
      shortcutKey: 'key-shortcut-open-library-browser',
    ),
    (
      screen: Screen.find,
      icon: OtzariaIcons.book_search_24_regular,
      iconFilled: OtzariaIcons.book_search_24_filled,
      label: 'איתור',
      shortcutKey: 'key-shortcut-open-find-ref',
    ),
    (
      screen: Screen.reading,
      icon: OtzariaIcons.book_open_large_24_regular,
      iconFilled: OtzariaIcons.book_open_large_24_filled,
      label: 'עיון',
      shortcutKey: 'key-shortcut-open-reading-screen',
    ),
    (
      screen: Screen.search,
      icon: OtzariaIcons.search_24_regular,
      iconFilled: OtzariaIcons.search_24_filled,
      label: 'חיפוש',
      shortcutKey: 'key-shortcut-open-new-search',
    ),
    // screen: null — "כלים" אינו מסך אלא פותח את פאנל המשגר.
    (
      screen: null,
      icon: FluentIcons.apps_24_regular,
      iconFilled: FluentIcons.apps_24_filled,
      label: 'כלים',
      shortcutKey: 'key-shortcut-open-more',
    ),
    (
      screen: Screen.settings,
      icon: FluentIcons.settings_24_regular,
      iconFilled: FluentIcons.settings_24_filled,
      label: 'הגדרות',
      shortcutKey: 'key-shortcut-open-settings',
    ),
  ];

  /// אינדקס "כלים" בתוך `_navData` — הפריט היחיד שאינו מסך. משמש כנקודת הקצה
  /// התחתונה של ה-"top items" בסרגל/בבר.
  static final int _toolsNavIndex = _navData.indexWhere(
    (d) => d.screen == null,
  );

  /// אינדקס "הגדרות" בתוך `_navData`. תוספים מוצמדים-לסרגל מוזרקים
  /// _אחרי_ פריט הכלים ו_לפני_ פריט ההגדרות.
  static final int _settingsNavIndex = _navData.indexWhere(
    (d) => d.screen == Screen.settings,
  );

  /// `buildWhen` עבור `BlocBuilder<PluginSystemBloc, PluginSystemState>` —
  /// בנוי מחדש רק כשרשימת מזהי התוספים המוצמדים-לסרגל משתנה (סינון יציב).
  static bool _pinnedNavRailIdsChanged(
    PluginSystemState prev,
    PluginSystemState curr,
  ) {
    final prevPlugins = prev is PluginSystemLoaded
        ? prev.pluginsPinnedToNavRail
        : const <InstalledPlugin>[];
    final currPlugins = curr is PluginSystemLoaded
        ? curr.pluginsPinnedToNavRail
        : const <InstalledPlugin>[];
    if (prevPlugins.length != currPlugins.length) return true;
    for (var i = 0; i < prevPlugins.length; i++) {
      final p = prevPlugins[i];
      final c = currPlugins[i];
      if (p.pluginId != c.pluginId ||
          p.manifest.toolTabTitle != c.manifest.toolTabTitle ||
          p.manifest.toolTabIconName != c.manifest.toolTabIconName) {
        return true;
      }
    }
    // גם rebuild כשמשתנה מספר הפלאגינים הגלויים בכלים (לטובת _isAllToolsHidden)
    final prevVisible = prev is PluginSystemLoaded
        ? prev.plugins
              .where((p) => p.enabled && p.showInTools && !p.pinnedToNavRail)
              .length
        : -1;
    final currVisible = curr is PluginSystemLoaded
        ? curr.plugins
              .where((p) => p.enabled && p.showInTools && !p.pinnedToNavRail)
              .length
        : -1;
    return prevVisible != currVisible;
  }

  /// מחזיר את רשימת התוספים המוצמדים-לסרגל מתוך ה-state, או רשימה ריקה כשאין.
  /// במצב 'מנותק' תוספים שדורשים אינטרנט מסוננים החוצה.
  static List<InstalledPlugin> _pinnedNavRailFromState(
    PluginSystemState state,
    bool isOfflineMode,
  ) {
    if (state is! PluginSystemLoaded) return const <InstalledPlugin>[];
    return state.pluginsPinnedToNavRail.filterForOfflineMode(isOfflineMode);
  }

  /// מחזיר `true` כאשר כל הכלים המובנים מוסתרים וגם אין תוסף מותקן ומופעל
  /// המוצג במסך הכלים. במצב זה אין טעם להציג את פריט "כלים" בסרגל הניווט.
  static bool _isAllToolsHidden(
    SettingsState settingsState,
    PluginSystemState pluginState,
  ) {
    final allBuiltInsHidden = kBuiltInToolsCatalog.every(
      (m) => settingsState.hiddenBuiltInToolIds.contains(m.toolId),
    );
    if (!allBuiltInsHidden) return false;
    if (pluginState is! PluginSystemLoaded) return true;
    return pluginState.plugins
        .where((p) => p.enabled && p.showInTools && !p.pinnedToNavRail)
        .isEmpty;
  }

  /// מזהה הכלי שהכרטיסיה הפעילה מציגה, או `null` אם אינה כרטיסיית כלי.
  /// מזין את הדגשת הפריטים המוצמדים בסרגל הניווט.
  static String? _activeToolIdOf(TabsState state) {
    final pane = state.activePane;
    return pane is ToolTab ? pane.toolId : null;
  }

  /// אינדקס "הגדרות" בפועל בתוך ה-bar destinations, בהתחשב בהסתרת כלים.
  static int _effectiveSettingsNavIndex(bool hideTools) =>
      hideTools ? _toolsNavIndex : _settingsNavIndex;

  /// מאחד כלים מובנים מוצמדים לסרגל ותוספים מוצמדים לסרגל לרשימה אחת
  /// לפי הסדר: כלים מובנים תחילה, אחריהם תוספים. כלים מובנים מסוננים
  /// לפי [SettingsState.hiddenBuiltInToolIds] כדי לוודא שכלי מוסתר לא
  /// יופיע בסרגל גם אם הוצמד בעבר.
  static List<_PinnedToolNavItem> _resolvePinnedItems({
    required PluginSystemState pluginState,
    required Set<String> pinnedBuiltInIds,
    required Set<String> hiddenBuiltInIds,
    required bool isOfflineMode,
  }) {
    final builtIns = kBuiltInToolsCatalog
        .where(
          (m) =>
              pinnedBuiltInIds.contains(m.toolId) &&
              !hiddenBuiltInIds.contains(m.toolId),
        )
        .map(_PinnedToolNavItem.fromBuiltIn);
    final plugins = _pinnedNavRailFromState(
      pluginState,
      isOfflineMode,
    ).map(_PinnedToolNavItem.fromPlugin);
    return [...builtIns, ...plugins];
  }

  @override
  void initState() {
    super.initState();
    _calendarCubit = CalendarCubit();
    _settingsScreenController = SettingsScreenController();
    _tourCubit = TourCubit();
    _lastScreen = context.read<NavigationBloc>().state.currentScreen;

    // כשהמסך ההתחלתי אינו קריאה (אין טאבים שמורים) אין ספר להמתין לו, ולכן
    // אין סיבה להסתיר את התוכן: הוא נצבע כבר מהפריים הראשון — בעוד החלון
    // מוסתר וה-splash הנייטיבי מוצג — כך שהציור הקר (קומפילציית shaders,
    // אטלס גופנים) מתרחש מאחורי הסמל. בלי זה התוכן עטוף Opacity(0) שמדלג
    // על הציור כליל, הציור הקר מתחיל רק ברגע החשיפה, והסמל (fade-out קבוע
    // של ~90ms על thread נייטיבי חסין-עומס) נעלם לפני שהפריים הראשון הספיק
    // להתרסטר — והמשתמש רואה פער ריק בין היעלמות הסמל להופעת החלון.
    // LoadLibrary משוגר כאן מאותה סיבה: אין שאילתת תוכן ספר שהוא עלול לעכב,
    // ועדיף שמסך הספרייה ייחשף כשהקטלוג כבר בבנייה.
    if (_lastScreen != Screen.reading) {
      _initialContentReady = true;
      _splashOverlayVisible = false;
      context.read<LibraryBloc>().add(LoadLibrary());
    }

    PluginPageLauncher.instance.navigator = (pluginId) {
      if (!mounted) return;
      openToolTabById(context, pluginId);
    };
    ToolsLauncherController.instance.opener = () {
      if (!mounted || _isToolsLauncherOpen) return;
      setState(() => _isToolsLauncherOpen = true);
    };

    // הצגת פופאפ פרסומת אחרי 5 שניות
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // אתחול tracker למעקב אחרי מיקום הקריאה
      if (mounted) {
        _readerLocationTracker = ReaderLocationTracker(
          tabsBloc: context.read<TabsBloc>(),
        );
      }

      unawaited(_initializeExternalActivationMonitoring());

      _tourCubit.registerSession();

      AdPopupDialog.showIfNeeded(
        context,
        shouldSkip: () => _tourStartedAutomaticallyThisLaunch,
      );

      // רענון plugin calendar events עם scope אמיתי לאחר שה-context מוכן.
      // הטעינה הראשונית ב-_initializeCalendar נקראה בלי workspace/book IDs —
      // כאן אנחנו מתקנים זאת עם ה-state שמזומן כעת.
      if (!mounted) return;
      try {
        final workspaceId = context
            .read<WorkspaceBloc>()
            .state
            .activeWorkspaceId;
        final bookId = context.read<TabsBloc>().state.currentTab?.title;
        _calendarCubit.refreshPluginEvents(
          currentWorkspaceId: workspaceId,
          currentBookId: bookId,
        );
      } catch (e) {
        debugPrint('⚠️ refreshPluginEvents failed after init: $e');
      }
    });

    // Setup fullscreen sync with window manager
    _setupFullscreenSync();

    // Listen to calendar changes for plugin dispatch
    _calendarCubit.stream.listen((state) {
      PluginRuntimeDispatcher.instance.dispatchEvent('calendar.date_changed', {
        'date': state.selectedGregorianDate.toIso8601String(),
      });
    });

    // NOTE: Background sync is now triggered by LibraryBloc listener
    // (see MultiBlocListener) to avoid DB lock contention during library loading.

    // מתזמן את חשיפת החלון המלא (במקום ה-splash הקטן/השקוף) אחרי שהטאב הפעיל
    // נטען. נדחה לפוסט-פריים כדי שהטאב הפעיל יספיק לשלוח את LoadContent שלו.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleSplashReveal();
    });

    // רשת ביטחון: אם תוכן הספר לא ייטען (bloc תקוע) — לא נשאיר את המשתמש
    // תקוע במסך הפתיחה. failsafe בלבד; מבוטל בזרימה תקינה וב-dispose.
    _splashFailsafeTimer = Timer(
      const Duration(seconds: 8),
      _revealMainWindowOnce,
    );
  }

  /// מתזמן את חשיפת החלון המלא, תוך מתן עדיפות לטעינת הספר הפעיל: אם נפתח ספר
  /// טקסט שעדיין נטען — ממתינים שה-[TextBookBloc] שלו יגיע ל-[TextBookLoaded]/
  /// [TextBookError] (או ייסגר) לפני שחושפים. בכל מקרה אחר (מסך שאינו קריאה /
  /// PDF / ספר שכבר נטען) — חושפים מיד. אין timeout שרירותי בנתיב הזה.
  void _scheduleSplashReveal() {
    // _revealStarted (ולא _initialContentReady) כשומר: במסך שאינו קריאה
    // התוכן כבר נצבע מהפריים הראשון (_initialContentReady=true מ-initState),
    // אבל החלון עצמו עדיין מוסתר וממתין ל-presentMainWindow שכאן.
    if (_hasScheduledSplashReveal || _revealStarted) return;
    if (!mounted) return;

    final navigationState = context.read<NavigationBloc>().state;
    final currentTab = context.read<TabsBloc>().state.currentTab;

    // במסך קריאה הטאבים מאוכלסים אסינכרונית (TabsBloc.LoadTabs /
    // WorkspaceBloc.ReplaceAllTabs), כך שב-post-frame הראשון currentTab עדיין
    // null. לא חושפים עדיין — ה-listener של TabsBloc יקרא לנו שוב.
    if (navigationState.currentScreen == Screen.reading && currentTab == null) {
      return;
    }

    _hasScheduledSplashReveal = true;

    // בטאב מפוצל ממתינים לחלונית הפעילה: הצומת העוטף אינו ספר, ובלי זה החלון
    // נחשף לפני שהספר שבחלונית נטען.
    final pendingPane = context.read<TabsBloc>().state.activePane;
    final shouldWaitForBook =
        navigationState.currentScreen == Screen.reading &&
        pendingPane is TextBookTab &&
        pendingPane.bloc.state is! TextBookLoaded &&
        pendingPane.bloc.state is! TextBookError;

    if (!shouldWaitForBook) {
      _revealMainWindowOnce();
      return;
    }

    final bloc = pendingPane.bloc;
    late final StreamSubscription<TextBookState> sub;
    var done = false;
    void finish() {
      if (done) return;
      done = true;
      sub.cancel();
      _revealMainWindowOnce();
    }

    sub = bloc.stream.listen(
      (state) {
        if (state is TextBookLoaded || state is TextBookError) {
          finish();
        }
      },
      onDone: finish,
      onError: (_) => finish(),
      cancelOnError: false,
    );
  }

  /// מרחיב את החלון לגודל המלא ואז חושף את התוכן. idempotent.
  void _revealMainWindowOnce() {
    if (_revealStarted) return;
    _revealStarted = true;
    _splashFailsafeTimer?.cancel();
    _splashFailsafeTimer = null;

    if (!mounted) {
      _initialContentReady = true;
      return;
    }

    // נתיב קצה (failsafe): אם הגענו לכאן דרך הטיימר בעוד אנחנו במסך קריאה ללא
    // טאב (שחזור הטאבים נתקע/נכשל >8 שניות), אסור לחשוף מסך עיון ריק. מנווטים
    // למסך הספרייה — מסך שימושי. במסלול הרגיל currentTab כבר קיים, ולכן זה
    // לא יקרה.
    final navState = context.read<NavigationBloc>().state;
    final hasActiveTab = context.read<TabsBloc>().state.currentTab != null;
    if (navState.currentScreen == Screen.reading && !hasActiveTab) {
      context.read<NavigationBloc>().add(
        const NavigateToScreen(Screen.library),
      );
    }

    // חשיפה (הגבולות והמסגרת הסופיים כבר הוחלו מוקדם, בעוד החלון מוסתר —
    // ראה _initializeProcessSingletons):
    //   1. חושפים את התוכן (Opacity 0→1) ומסירים את אוברליי ה-splash של Flutter
    //      *באותו setState* — כך הפריים שמצויר נקי מהסמל הישן (אחרת, בעומס
    //      האתחול, הסרה ב-setState נפרד מתעכבת והסמל הישן מהבהב במרכז החלון).
    //   2. ממתינים שהפריים יצויר, ואז מציגים את החלון (presentMainWindow). ב-
    //      Windows הסמל הנייטיב מתחיל fade-out כשהפריים בגודל הסופי מוצג בפועל.
    //   3. רק אז משגרים את LoadLibrary: בניית הקטלוג (~300ms CPU על ה-main
    //      isolate) נדחתה לכאן כדי שלא תתחרה בשאילתת תוכן הספר הפעיל ולא
    //      בציור פריים החשיפה. ה-endOfFrame הנוסף לפני השיגור נותן לפריים
    //      ה-relayout של המיקסום (שעשוי להימשך יותר מפריים אחד) להסתיים לפני
    //      שהקטלוג תופס את ה-main isolate. ה-bloc חי ברמת AppBootstrap, ולכן
    //      בטוח לשגר אליו גם אם המסך כבר לא mounted.
    final libraryBloc = context.read<LibraryBloc>();
    unawaited(() async {
      if (!mounted) {
        _initialContentReady = true;
        _splashOverlayVisible = false;
        await presentMainWindow();
        await WidgetsBinding.instance.endOfFrame;
        libraryBloc.add(LoadLibrary());
        return;
      }
      // במסך שאינו קריאה התוכן כבר נצבע מהפריים הראשון (ראה initState) ואין
      // צורך ב-setState; ה-endOfFrame עדיין נותן לפריים תלוי-ועומד להסתיים.
      if (!_initialContentReady || _splashOverlayVisible) {
        setState(() {
          _initialContentReady = true;
          _splashOverlayVisible = false;
        });
      }
      await WidgetsBinding.instance.endOfFrame;
      await presentMainWindow();
      await WidgetsBinding.instance.endOfFrame;
      libraryBloc.add(LoadLibrary());
    }());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // אתחול PageController פעם אחת עם initialPage הנכון
    if (!_hasInitializedPageController) {
      _hasInitializedPageController = true;
      final initialScreen = context.read<NavigationBloc>().state.currentScreen;
      _currentPageIndex = _pageIndexForScreen(initialScreen) ?? 0;
      pageController = PageController(initialPage: _currentPageIndex);
    }
  }

  /// Initialize background file sync AFTER library is loaded.
  /// This avoids DB lock contention that caused 17s delays.
  void _initializeBackgroundSync() {
    BackgroundSyncInitializer.initializeAfterDelay(
      delaySeconds: 2, // Small delay to let UI settle after library load
      onComplete: (result) {
        if (!mounted) return;
        if (result.addedBooks > 0 || result.updatedBooks > 0) {
          debugPrint(
            '📚 סנכרון קבצים הושלם: ${result.addedBooks} ספרים חדשים, '
            '${result.updatedBooks} עודכנו',
          );

          // Refresh the library browser to show new books
          try {
            context.read<LibraryBloc>().add(
              RefreshLibrary(
                changedBookKeys: {
                  for (final id in result.updatedBookIds)
                    IndexingRepository.userBookKey(id),
                },
              ),
            );
          } catch (e) {
            debugPrint('Could not refresh library: $e');
          }
        }
      },
    );
  }

  void _tryStartDeferredStartupWork() {
    tryStartDeferredStartupWork(
      gate: _startupWorkGate,
      startBackgroundSync: _initializeBackgroundSync,
      isAutoSyncEnabled: () =>
          Settings.getValue<bool>(SettingsRepository.keyAutoSync) ?? true,
      canUseSoftwareAndBookUpdates: () =>
          context.read<SettingsBloc>().state.canUseSoftwareAndBookUpdates,
      libraryUpdateBloc: context.read<LibraryUpdateBloc>,
    );
  }

  /// Setup synchronization between window fullscreen state and settings
  void _setupFullscreenSync() {
    if (kIsWeb ||
        (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS)) {
      return;
    }

    // Listen for fullscreen changes from the window manager (e.g., user presses F11 in OS)
    appWindowListener?.onFullscreenChanged = (isFullscreen) {
      if (!mounted) return;
      final settingsBloc = context.read<SettingsBloc>();
      // Only update if the state is different to avoid loops
      if (settingsBloc.state.isFullscreen != isFullscreen) {
        settingsBloc.add(UpdateIsFullscreen(isFullscreen));
      }
    };

    // שחזור פוקוס לאחר אירועי מצב חלון דיסקרטיים (maximize/unmaximize/fullscreen/restore)
    appWindowListener?.onWindowStateChanged = () {
      if (!mounted) return;
      FocusRepository().scheduleRestore();
    };

    // שחזור פוקוס בזמן resize רציף — עם debounce כדי למנוע הצפת קריאות
    appWindowListener?.onWindowResizeOccurred = () {
      if (!mounted) return;
      FocusRepository().scheduleRestoreDebounced();
    };
  }

  void _checkAndStartIndexing(
    BuildContext context,
    library_model.Library library,
  ) {
    // Only check once. מופעל מ-listener טעינת הספרייה כך שהוא צורך את ה-library
    // שכבר נבנה (ולא מפעיל בנייה עצמאית נוספת שתתחרה בטעינת הספר הפעיל).
    if (_hasCheckedAutoIndex) return;
    _hasCheckedAutoIndex = true;

    unawaited(_resolveStartupIndexing(context, library));
  }

  /// מציג דיאלוג אישור לפני הורדה מלאה (~ג'יגות). המשתמש יכול לבחור להישאר
  /// עם הגרסה הנוכחית — אסור להוריד ספרייה מלאה ללא אישור מפורש.
  Future<void> _promptFullDownload(
    BuildContext context,
    LibraryUpdateState state,
  ) async {
    if (_isShowingFullDownloadDialog) return;
    _isShowingFullDownloadDialog = true;
    final bloc = context.read<LibraryUpdateBloc>();
    final sizeMb = ((state.plan?.totalDownloadSize ?? 0) / (1 << 20)).round();
    final sizeText = sizeMb >= 1024
        ? '${(sizeMb / 1024).toStringAsFixed(1)} GB'
        : '$sizeMb MB';
    try {
      final confirmed = await showTwoActionsDialog(
        context: context,
        title: 'נדרשת הורדה מלאה של הספרייה',
        content:
            'לא נמצא מסלול עדכון מצומצם למצב הנוכחי. כדי לעדכן יש להוריד '
            'את הספרייה המלאה (כ-$sizeText). אפשר גם להמשיך עם הגרסה הנוכחית '
            'ללא עדכון.',
        cancelText: 'המשך עם הנוכחי',
        confirmText: 'הורד עדכון מלא',
      );
      if (!context.mounted) return;
      bloc.add(
        confirmed == true
            ? const ConfirmFullDownload()
            : const DeclineFullDownload(),
      );
    } finally {
      _isShowingFullDownloadDialog = false;
    }
  }

  /// מפעיל אינדוקס אחרי עדכון DB חי — בנפרד מ-_checkAndStartIndexing שרץ פעם
  /// אחת בעלייה. מבקש אינדוקס רק אם המשתמש הפעיל עדכון אינדקס אוטומטי.
  void _indexAfterDbUpdateIfNeeded(
    BuildContext context,
    library_model.Library library,
  ) {
    if (!_indexAfterLibraryReload) {
      _dbUpdateTriggeredFullIndex = false;
      _reconcileAfterLibraryReload = false;
      return;
    }
    _indexAfterLibraryReload = false;
    final reconcile = _reconcileAfterLibraryReload;
    _reconcileAfterLibraryReload = false;
    final autoUpdateIndex = context.read<SettingsBloc>().state.autoUpdateIndex;
    // StartIndexing מאנדקס את כל הספרייה — מסמן ל-newBooksToIndex listener לדלג.
    _dbUpdateTriggeredFullIndex = autoUpdateIndex;
    if (autoUpdateIndex) {
      final indexingBloc = context.read<IndexingBloc>();
      // StartIndexing מוסיף ספרים חדשים (מדלג על קיימים); אחרי הורדה מלאה
      // אין דיווח מי השתנה, אז ReconcileIndex משווה טביעות-אצבע ומאנדקס
      // מחדש רק את הספרים ששונים. האירועים רצים סדרתית (sequential).
      indexingBloc.add(StartIndexing(library));
      if (reconcile) {
        indexingBloc.add(ReconcileIndex(library));
      }
    }
  }

  Future<void> _resolveStartupIndexing(
    BuildContext context,
    library_model.Library library,
  ) async {
    final autoUpdateIndex = context.read<SettingsBloc>().state.autoUpdateIndex;

    final requiresManualReindex = await _indexingRepository
        .requiresManualReindex(library);
    if (!mounted || !context.mounted) {
      return;
    }

    final decision = decideStartupIndexing(
      requiresManualReindex: requiresManualReindex,
      autoUpdateIndex: autoUpdateIndex,
    );

    switch (decision) {
      case StartupIndexingDecision.autoReindexThenStart:
        await _indexingRepository.clearIndex();
        if (!mounted || !context.mounted) {
          return;
        }
        _startupWorkGate.markIndexingDecisionResolved(expectIndexing: true);
        _tryStartDeferredStartupWork();
        context.read<IndexingBloc>().add(StartIndexing(library));
        return;
      case StartupIndexingDecision.promptManualReindex:
        _startupWorkGate.markIndexingDecisionResolved(expectIndexing: false);
        _tryStartDeferredStartupWork();
        await _showStartupManualReindexDialog(context, library);
        return;
      case StartupIndexingDecision.startIndexing:
        _startupWorkGate.markIndexingDecisionResolved(expectIndexing: true);
        _tryStartDeferredStartupWork();
        context.read<IndexingBloc>().add(StartIndexing(library));
        return;
      case StartupIndexingDecision.checkIndexStatus:
        _startupWorkGate.markIndexingDecisionResolved(expectIndexing: false);
        _tryStartDeferredStartupWork();
        context.read<IndexingBloc>().add(CheckIndexStatus(library));
        return;
    }
  }

  Future<void> _showStartupManualReindexDialog(
    BuildContext context,
    library_model.Library library,
  ) async {
    if (_isShowingStartupManualReindexDialog) {
      return;
    }

    _isShowingStartupManualReindexDialog = true;
    final indexingBloc = context.read<IndexingBloc>();
    try {
      final result = await showTwoActionsDialog(
        context: context,
        title: 'נדרש איפוס אינדקס',
        content:
            'האינדקס הקיים אינו מעודכן ביחס לשינויים האחרונים בחיפוש. עד שתבצע איפוס ואינדוקס מחדש, ייתכן שחלק מיכולות החיפוש לא יעבדו כראוי.',
        cancelText: 'אחר כך',
        confirmText: 'אפס ועדכן',
      );
      if (!mounted || !context.mounted || result != true) {
        return;
      }

      await _indexingRepository.clearIndex();
      if (!mounted || !context.mounted) {
        return;
      }

      _startupWorkGate.markIndexingDecisionResolved(expectIndexing: true);
      indexingBloc.add(StartIndexing(library));
    } finally {
      _isShowingStartupManualReindexDialog = false;
    }
  }

  void _startIndexing(BuildContext context) {
    DataRepository.instance.library.then((library) {
      if (!mounted || !context.mounted) return;
      context.read<IndexingBloc>().add(StartIndexing(library));
    });
  }

  Future<void> _processPendingExternalActivations() async {
    if (!mounted || _isProcessingExternalActivations) {
      return;
    }

    _isProcessingExternalActivations = true;
    try {
      final pendingUris = await _externalActivationQueue.drainUriStrings();
      for (final uriString in pendingUris) {
        await _handleExternalActivationUriString(uriString);
      }
    } catch (e, stackTrace) {
      debugPrint('External activation polling failed: $e\n$stackTrace');
    } finally {
      _isProcessingExternalActivations = false;
    }
  }

  Future<void> _initializeExternalActivationMonitoring() async {
    await _externalActivationChannel.initialize();
    await _externalActivationChannelSub?.cancel();
    _externalActivationChannelSub = _externalActivationChannel.uriStrings
        .listen((uriString) {
          unawaited(_handleExternalActivationUriString(uriString));
        });

    final pendingPlatformUris = await _externalActivationChannel
        .takePendingUriStrings();
    for (final uriString in pendingPlatformUris) {
      await _handleExternalActivationUriString(uriString);
    }

    final queuePath = await _externalActivationQueue.resolveQueueFilePath();
    final queueFile = File(queuePath);
    await queueFile.parent.create(recursive: true);

    await _externalActivationWatchSub?.cancel();
    _externalActivationWatchSub = queueFile.parent.watch().listen(
      (event) {
        final normalizedPath = event.path.replaceAll('\\', '/');
        final normalizedQueuePath = queuePath.replaceAll('\\', '/');
        if (normalizedPath != normalizedQueuePath) {
          return;
        }

        unawaited(_processPendingExternalActivations());
      },
      onError: (error, stackTrace) {
        debugPrint('External activation watch failed: $error\n$stackTrace');
      },
    );

    await _processPendingExternalActivations();
  }

  Future<bool> _handleExternalActivationUriString(String uriString) async {
    if (!mounted) {
      return false;
    }

    try {
      final uri = Uri.tryParse(uriString);
      if (uri == null) return false;

      final action = ExternalUriRouter.parseUri(uri);
      if (action == null) return false;

      await _bringWindowToFront();
      if (!mounted) return false;
      return await _dispatchExternalUriAction(action);
    } catch (e, stackTrace) {
      debugPrint(
        'Failed to process external activation "$uriString": $e\n$stackTrace',
      );
      return false;
    }
  }

  /// מטפל בקישור otzaria:// שהגיע ממקור פנימי (למשל שדה חיפוש בספרייה).
  /// ניתן לקרוא לפונקציה זו דרך [mainWindowScreenKey]. מחזיר `true` אם הקישור
  /// טופל בהצלחה — שדה החיפוש בספרייה משתמש בערך הזה כדי להחליט אם לנקות.
  Future<bool> handleInternalDeepLink(String uriString) =>
      _handleExternalActivationUriString(uriString);

  Future<void> _bringWindowToFront() async {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await windowManager.show();
      await windowManager.focus();
    }
  }

  /// מחזיר `true` כאשר הפעולה בוצעה במלואה (לדוגמה: ספר אומת ונפתח). חשוב
  /// במיוחד עבור book/pdf — אם ה-id לא קיים בספרייה, מחזיר `false` כדי ששדה
  /// החיפוש בספרייה לא ינקה את הקישור שהמשתמש הדביק.
  Future<bool> _dispatchExternalUriAction(ExternalUriAction action) async {
    switch (action) {
      case OpenScreenAction(:final screen):
        context.read<NavigationBloc>().add(NavigateToScreen(screen));
        return true;
      case OpenToolAction(:final toolId):
        openToolTabById(context, toolId);
        return true;
      case OpenPluginAction(:final pluginId):
        openToolTabById(context, pluginId);
        return true;
      case OpenToolsLauncherAction():
        ToolsLauncherController.instance.open();
        return true;
      case SwitchToTabAction(:final index):
        final tabsBloc = context.read<TabsBloc>();
        if (index < 0 || index >= tabsBloc.state.tabs.length) {
          return false;
        }
        tabsBloc.add(SetCurrentTab(index));
        context.read<NavigationBloc>().add(
          const NavigateToScreen(Screen.reading),
        );
        return true;
      case OpenBookAction():
        return await _openBookByExternalId(action);
      case OpenPdfBookAction():
        return await _openPdfBookByExternalId(action);
      case InstallPluginAction(:final request):
        context.read<PluginSystemBloc>().add(
          InstallRemotePluginRequested(
            request.downloadUri.toString(),
            forceOverwrite: request.forceOverwrite,
            reportContext: request.reportContext,
          ),
        );
        return true;
      case InstallLocalPluginAction(:final archivePath):
        context.read<PluginSystemBloc>().add(
          InstallPluginRequested(archivePath),
        );
        return true;
      case RunSearchAction(:final query, :final mode):
        _runExternalSearch(query, mode: mode);
        return true;
      case RunDetectionAction(:final query):
        final focusRepository = context.read<FocusRepository>();
        focusRepository.findRefSearchController.text = query;
        focusRepository.findRefSearchController.selection =
            TextSelection.collapsed(offset: query.length);
        if (query.isNotEmpty) {
          context.read<FindRefBloc>().add(SearchRefRequested(query));
        }
        _handleFindRefOpen(context);
        return true;
      case OpenInspectionAction():
        context.read<NavigationBloc>().add(
          const NavigateToScreen(Screen.reading),
        );
        return true;
      case OpenSdkAction():
        // ניהול התוספים עבר להגדרות ← כלים; המשגר משמש רק לפתיחה.
        context.read<NavigationBloc>().add(
          const NavigateToScreen(Screen.settings),
        );
        _settingsScreenController.openTab(SettingsTab.tools);
        return true;
      case OpenDailyPageAction():
        final Daf daf = getDafYomi(DateTime.now());
        openDafYomiBook(
          context,
          daf.getMasechta(),
          ' ${formatAmud(daf.getDaf())}.',
        );
        return true;
      case OpenHistoryAction():
        showDialog(context: context, builder: (_) => const HistoryDialog());
        return true;
      case OpenBookmarksAction():
        showDialog(context: context, builder: (_) => const BookmarksDialog());
        return true;
      case OpenSettingsTabAction(:final tab):
        context.read<NavigationBloc>().add(
          const NavigateToScreen(Screen.settings),
        );
        if (tab != null) {
          // ה-controller נוצר ב-initState ומועבר ל-MySettingsScreen דרך ה-build.
          // קריאה ישירה לאחר ה-NavigateToScreen מספיקה כי ה-controller מאזין
          // ל-ChangeNotifier — והמסך מגיב בקריאה הבאה ל-build.
          _settingsScreenController.openTab(tab);
        }
        return true;
    }
  }

  void _runExternalSearch(String query, {SearchMode? mode}) {
    // ה-configuration מועברת בבנייה ולא ב-event — מניעת race עם
    // ה-UpdateSearchQuery ש-TantivyFullTextSearch שולח ב-initState.
    final tab = SearchingTab(
      SearchingTab.titleForQuery(query),
      query,
      initialConfiguration: mode == null
          ? null
          : SearchConfiguration(
              searchMode: mode,
              distance: mode == SearchMode.fuzzy ? 2 : 0,
            ),
    );
    context.read<HistoryBloc>().add(AddHistory(tab));
    context.read<TabsBloc>().add(AddTab(tab));
    context.read<NavigationBloc>().add(const NavigateToScreen(Screen.search));
    // ה-UpdateSearchQuery נשלח אוטומטית מ-TantivyFullTextSearch.initState
    // ברגע שהלשונית מוצגת לראשונה. ראה tantivy_full_text_search.dart:130-134.
  }

  Future<bool> _openBookByExternalId(OpenBookAction action) async {
    final library = await DataRepository.instance.library;
    if (!mounted) return false;
    final book = library.getAllBooks().firstWhereOrNull(
      (b) => b.id == action.bookId,
    );
    if (book == null) {
      UiSnack.showError(LibraryMessages.bookNotFoundById(action.bookId));
      return false;
    }
    dispatchOpenBookAction(
      action: action,
      book: book,
      coordinator: BookOpenCoordinator(
        tabsBloc: context.read<TabsBloc>(),
        historyBloc: context.read<HistoryBloc>(),
        navigationBloc: context.read<NavigationBloc>(),
      ),
    );
    return true;
  }

  Future<bool> _openPdfBookByExternalId(OpenPdfBookAction action) async {
    final library = await DataRepository.instance.library;
    if (!mounted) return false;
    final book = library.getAllBooks().firstWhereOrNull(
      (b) => b is PdfBook && b.id == action.bookId,
    );
    if (book == null) {
      UiSnack.showError(LibraryMessages.pdfBookNotFoundById(action.bookId));
      return false;
    }
    dispatchOpenPdfBookAction(
      action: action,
      book: book,
      coordinator: BookOpenCoordinator(
        tabsBloc: context.read<TabsBloc>(),
        historyBloc: context.read<HistoryBloc>(),
        navigationBloc: context.read<NavigationBloc>(),
      ),
    );
    return true;
  }

  @override
  void dispose() {
    PluginPageLauncher.instance.navigator = null;
    ToolsLauncherController.instance.opener = null;
    // Clean up fullscreen callback
    appWindowListener?.onFullscreenChanged = null;
    appWindowListener?.onWindowStateChanged = null;
    appWindowListener?.onWindowResizeOccurred = null;
    _splashFailsafeTimer?.cancel();
    _externalActivationWatchSub?.cancel();
    _externalActivationChannelSub?.cancel();
    _externalActivationChannel.dispose();
    _calendarCubit.close();
    _removeTourOverlay();
    _tourCubit.close();
    _readerLocationTracker?.dispose();
    pageController.dispose();
    super.dispose();
  }

  void _handleOrientationChange(BuildContext context, Orientation orientation) {
    if (_previousOrientation == orientation) return;

    final isFirstDetection = _previousOrientation == null;
    _previousOrientation = orientation;
    if (isFirstDetection) return;

    // החלפת ציר ב-PageView (vertical↔horizontal) משבשת את חישוב העמוד
    // הפנימי של PageController: ה-pixel offset נשמר אבל ה-viewport
    // dimension משתנה (height→width), ולכן הנוסחה offset/viewport
    // מקפיצה את העמוד הפעיל. התוצאה: עמוד 1 (מסך עיון) מוצג רגעית מעל
    // המסך הנוכחי, ושאר המסכים נכפים ל-dispose ואז init מחדש (ראה למשל
    // ShamorZachorWidget בלוגים).
    //
    // הפתרון: יוצרים PageController חדש *סינכרונית* לפני בניית ה-PageView
    // החדש (בציר החדש). ה-PageView שייבנה מיד אחרי הקריאה הזו ישתמש
    // ב-controller החדש עם initialPage תקין, בלי offset יורש מהציר הקודם.
    final currentScreen = context.read<NavigationBloc>().state.currentScreen;
    final targetPage = _pageIndexForScreen(currentScreen) ?? _currentPageIndex;
    _currentPageIndex = targetPage;

    // אם מתבצע slide חוצה בזמן שינוי אוריינטציה — מבטלים אותו ונוחתים על היעד
    // האמיתי. איפוס _isCrossSliding גורם ל-slide הישן להפסיק בסיום ה-await שלו;
    // ה-setState הנדחה כופה rebuild עם הסידור הקנוני (ה-controller החדש כבר ביעד).
    if (_isCrossSliding || _transitionTargetIndex != null) {
      _transitionTargetIndex = null;
      _transitionSlotIndex = null;
      _isCrossSliding = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }

    final oldController = pageController;
    pageController = PageController(initialPage: targetPage);

    // dispose נדחה לפוסט-פריים: ה-PageView הישן עדיין מחובר ל-oldController
    // עד שתסתיים הרקונסיליאציה של עץ הווידג'טים בפריים הזה.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldController.dispose();
    });
  }

  void _toggleToolsLauncher() {
    setState(() => _isToolsLauncherOpen = !_isToolsLauncherOpen);
  }

  void _closeToolsLauncher() {
    if (!_isToolsLauncherOpen) return;
    setState(() => _isToolsLauncherOpen = false);
  }

  void _toggleReadingSettingsPanel() {
    setState(() {
      _isReadingSettingsPanelOpen = !_isReadingSettingsPanelOpen;
    });
  }

  /// ודאו שה-PageView מסונכרן למצב הניווט הנוכחי גם אם בחרו שוב באותו יעד.
  Future<void> _syncPageWithState() async {
    if (!mounted || !pageController.hasClients) return;
    // לא לגעת ב-controller בזמן slide חוצה פעיל — הוא יסתיים על היעד הנכון.
    if (_isCrossSliding) return;
    final currentScreen = context.read<NavigationBloc>().state.currentScreen;
    final targetPage = _pageIndexForScreen(currentScreen);
    if (targetPage == null) return;
    if (_currentPageIndex == targetPage) return;

    setState(() {
      _currentPageIndex = targetPage;
    });
    pageController.jumpToPage(targetPage);
  }

  List<NavigationDestination> _buildBarDestinations(
    List<_PinnedToolNavItem> pinnedItems, {
    required bool hideTools,
  }) {
    NavigationDestination buildNavDataDestination(int i) {
      final item = _navData[i];
      return NavigationDestination(
        tooltip: '',
        icon: Tooltip(
          preferBelow: false,
          message: (ShortcutValidator.getShortcutValue(item.shortcutKey) ?? '')
              .toUpperCase(),
          child: _navigationIcon(item.icon),
        ),
        selectedIcon: _navigationIcon(item.iconFilled),
        label: context.settingsText(item.label),
      );
    }

    NavigationDestination buildPinnedItemDestination(_PinnedToolNavItem item) {
      return NavigationDestination(
        tooltip: '',
        icon: item.buildIcon(),
        label: item.label,
      );
    }

    return [
      for (int i = 0; i < _settingsNavIndex; i++)
        if (i != _toolsNavIndex || !hideTools) buildNavDataDestination(i),
      for (final item in pinnedItems) buildPinnedItemDestination(item),
      buildNavDataDestination(_settingsNavIndex),
    ];
  }

  Widget _navigationIcon(IconData icon) {
    return icon.fontPackage == OtzariaIcons.fontPackage
        ? Icon(icon)
        : RtlIcon(icon);
  }

  /// סדר העמודים במהלך slide חוצה: מחליף (swap) בין מסך היעד ([targetIndex])
  /// למסך שיושב בעמוד-השכן ([slotIndex]), כך שמסך היעד מוצג בשכן לצורך ההחלקה.
  ///
  /// כל ארבעת המסכים נשארים בעץ (התוצאה היא תמורה של [canonical]) — כך אף מסך
  /// עם keep-alive כמו `ToolsScreen` אינו נדחק מהעץ ונבנה מחדש, וה-WebView שלו
  /// אינו נטען מחדש. מסך שכן מעורב ב-swap (עם GlobalKey) רק *זז* בעץ ולכן ה-State
  /// שלו נשמר דרך reparenting. כל GlobalKey יושב בעמוד אחד בלבד.
  ///
  /// במנוחה ([targetIndex] או [slotIndex] הם null) — מוחזר הסדר הקנוני כמות שהוא.
  @visibleForTesting
  static List<Widget> buildTransitionPages(
    List<Widget> canonical, {
    required int? targetIndex,
    required int? slotIndex,
  }) {
    if (targetIndex == null || slotIndex == null) {
      return canonical;
    }
    final pages = List<Widget>.of(canonical);
    pages[slotIndex] = canonical[targetIndex];
    pages[targetIndex] = canonical[slotIndex];
    return pages;
  }

  /// בונה את רשימת עמודי ה-PageView לפי מצב המעבר הנוכחי (ראה
  /// [buildTransitionPages]).
  List<Widget> _buildPagesList() {
    final canonical = <Widget>[
      _cachedLibraryPage!,
      _cachedReadingPage!,
      _cachedSettingsPage!,
    ];
    return buildTransitionPages(
      canonical,
      targetIndex: _transitionTargetIndex,
      slotIndex: _transitionSlotIndex,
    );
  }

  /// החלקה (slide) ישירה בין מסכים לא-סמוכים בלי שעמודי הביניים ייראו.
  ///
  /// הטכניקה: מציבים זמנית את מסך היעד בעמוד-השכן בכיוון התנועה ([slot]),
  /// מחליקים מרחק עמוד אחד בלבד (כך נראים רק המסך היוצא והיעד — לא הביניים),
  /// ובסיום קופצים למיקום האמיתי של היעד. ה-GlobalKey של מסך היעד גורם ל-Flutter
  /// להעביר (reparent) את ה-Element החי מ-[slot] ל-[to] בלי בנייה מחדש, כך
  /// שה-WebView של מסך הכלים אינו נטען מחדש ואין הבהוב.
  Future<void> _slideToDistantPage(int from, int to) async {
    final slot = from + (to > from ? 1 : -1);
    setState(() {
      _isCrossSliding = true;
      _transitionTargetIndex = to;
      _transitionSlotIndex = slot;
    });

    // המתנה לסוף ה-frame כדי שהסידור הזמני (מסך היעד בעמוד-השכן) יעבור layout
    // לפני תחילת האנימציה.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !pageController.hasClients || !_isCrossSliding) return;

    await pageController.animateToPage(
      slot,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    if (!mounted || !pageController.hasClients || !_isCrossSliding) return;

    // סיום: שחזור הסידור הקנוני וקפיצה ליעד האמיתי — שתי הפעולות סינכרוניות
    // באותו tick, כך שה-build הבא רואה את שתיהן יחד (ללא frame ביניים מהבהב).
    setState(() {
      _currentPageIndex = to;
      _transitionTargetIndex = null;
      _transitionSlotIndex = null;
      _isCrossSliding = false;
    });
    pageController.jumpToPage(to);
  }

  void _handleNavigationChange(
    BuildContext context,
    NavigationState state,
  ) async {
    if (!mounted || !context.mounted) return;

    final shouldExitFullscreen =
        FullscreenHelper.shouldExitFullscreenOnNavigation(
          platform: defaultTargetPlatform,
          isFullscreen: context.read<SettingsBloc>().state.isFullscreen,
          screen: state.currentScreen,
          hasOpenTabs: context.read<TabsBloc>().state.hasOpenTabs,
        );
    if (shouldExitFullscreen) {
      FullscreenHelper.toggleFullscreen(context, false);
    }

    if (state.currentScreen != _lastScreen) {
      if (_lastScreen == Screen.library) {
        final libraryState = libraryBrowserKey.currentState;
        if (libraryState != null) {
          (libraryState as dynamic).closeTransientPanels();
        }
      }
      // יציאה ממסך העיון משהה את התוספים שבטאב הפעיל (חוסך CPU/RAM ברקע);
      // חזרה מחדשת אותם.
      PluginRuntimeDispatcher.instance.setReaderScreenVisible(
        state.currentScreen == Screen.reading ||
            state.currentScreen == Screen.search,
      );
      // בקשת מיקוד אזור הקריאה שייכת למסך העיון בלבד; בעזיבתו היא מתבטלת כדי
      // שלא תירה מאוחר יותר, כשהתוכן נרשם, ותחטוף פוקוס משדה במסך הנוכחי.
      if (state.currentScreen != Screen.reading) {
        context.read<FocusRepository>().cancelPendingTabContentFocus();
      }
      _lastScreen = state.currentScreen;
    }

    final targetPage = _pageIndexForScreen(state.currentScreen);
    if (targetPage != null && _currentPageIndex != targetPage) {
      if (_isCrossSliding) {
        // הגיע מעבר חדש באמצע slide פעיל — מסיימים אותו מיד ונוחתים על היעד
        // החדש בקפיצה. איפוס _isCrossSliding גורם ל-slide הקודם להפסיק בסיום
        // ה-await שלו (ההגנה !_isCrossSliding).
        setState(() {
          _currentPageIndex = targetPage;
          _transitionTargetIndex = null;
          _transitionSlotIndex = null;
          _isCrossSliding = false;
        });
        if (pageController.hasClients) {
          pageController.jumpToPage(targetPage);
        }
      } else if (pageController.hasClients) {
        // עמודים סמוכים — החלקה (slide) רגילה. עמודים לא-סמוכים
        // (למשל "ספריה" → "כלים") — החלקה ישירה דרך _slideToDistantPage, כך
        // שעמוד הביניים ("עיון") אינו נראה ומערכת התוספים/WebView אינה נטענת לחינם.
        final currentPage = pageController.page?.round() ?? _currentPageIndex;
        final isAdjacent = (currentPage - targetPage).abs() == 1;
        if (isAdjacent) {
          setState(() {
            _currentPageIndex = targetPage;
          });
          pageController.animateToPage(
            targetPage,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        } else {
          unawaited(_slideToDistantPage(currentPage, targetPage));
        }
      } else {
        setState(() {
          _currentPageIndex = targetPage;
        });
      }
    }

    if (state.currentScreen == Screen.library) {
      context.read<FocusRepository>().requestLibrarySearchFocus(
        selectAll: true,
      );
    } else if (state.currentScreen == Screen.reading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // טאב כלי אינו ספר: requestBookContentFocus היה ממקד את ה-viewer של
        // ספר אחר, ובתוסף זה מתורגם ל-blur() בתוך ה-WebView.
        final pane = context.read<TabsBloc>().state.activePane;
        if (pane is ToolTab) {
          context.read<FocusRepository>().requestTabContentFocus(pane);
        } else {
          context.read<FocusRepository>().requestBookContentFocus();
        }
      });
    } else if (state.currentScreen == Screen.settings) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<FocusRepository>().requestSettingsFocus();
        }
      });
    } else if (state.currentScreen == Screen.find) {
      // find_ref_dialog registers its own restorer on open
      context.read<FocusRepository>().requestFindRefSearchFocus();
    } else if (state.currentScreen == Screen.search) {
      // TantivyFullTextSearch listens to NavigationBloc and registers
      // itself via setScreenRestorer in _requestSearchFieldFocus.
      // No extra action needed here.
    }
  }

  void _handleTourStepChanged(TourStep step) {
    // סגירת חלוניות איתור/חיפוש בכל מעבר שלב, למעט כאשר השלב החדש דורש פתיחה
    final shouldOpenFindRef = step.action == TourStepAction.openFindRef;
    final shouldOpenSearch = step.action == TourStepAction.openSearch;
    if (!shouldOpenFindRef && _isFindRefOpen) {
      Navigator.of(context, rootNavigator: true).maybePop();
    }
    if (!shouldOpenSearch && _isSearchOpen) {
      Navigator.of(context, rootNavigator: true).maybePop();
    }
    // פאנל המשגר אינו route ולכן maybePop לא נוגע בו; בלי הסגירה המפורשת הוא
    // היה נשאר פרוש מעל שאר שלבי הסיור.
    if (step.action != TourStepAction.openTools) _closeToolsLauncher();

    switch (step.action) {
      case TourStepAction.openLibrary:
        context.read<NavigationBloc>().add(
          const NavigateToScreen(Screen.library),
        );
      case TourStepAction.openLibraryHome:
        context.read<NavigationBloc>().add(
          const NavigateToScreen(Screen.library),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          (libraryBrowserKey.currentState as dynamic).navigateHome();
        });
      case TourStepAction.openLibraryBookPreview:
        context.read<NavigationBloc>().add(
          const NavigateToScreen(Screen.library),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final libraryState = libraryBrowserKey.currentState;
          if (libraryState != null) {
            (libraryState as dynamic).prepareTourBookPreview();
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _tourOverlayEntry?.markNeedsBuild();
            _scheduleTourTargetRebuilds(remainingFrames: 6);
          });
        });
      case TourStepAction.openReading:
        context.read<NavigationBloc>().add(
          const NavigateToScreen(Screen.reading),
        );
        if (_openGenesisForTour) {
          _openGenesisForTour = false;
          _openTourGenesisInReader();
        }
        if (step.id == 'toc') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final tocContext = textBookNavigationTourTargetKey.currentContext;
            if (tocContext != null && tocContext.mounted) {
              tocContext.read<TextBookBloc>().add(const ToggleLeftPane(true));
            }
          });
        }
      case TourStepAction.openTools:
        ToolsLauncherController.instance.open();
      case TourStepAction.openSettings:
        context.read<NavigationBloc>().add(
          const NavigateToScreen(Screen.settings),
        );
      case TourStepAction.openDesignSettings:
        _settingsScreenController.openTab(SettingsTab.design);
        context.read<NavigationBloc>().add(
          const NavigateToScreen(Screen.settings),
        );
      case TourStepAction.openFindRef:
        _openGenesisForTour = true;
        _openTourFindRef();
      case TourStepAction.openSearch:
        _handleSearchTabOpen(context, closeIfOpen: false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _bringTourOverlayToFront();
        });
      case TourStepAction.none:
        break;
    }
    _scheduleTourOverflowMenuForStep(step);
    _scheduleTourTargetRebuilds(remainingFrames: 4);
  }

  void _scheduleTourOverlayInsert() {
    if (_tourOverlayInsertScheduled) {
      return;
    }
    _tourOverlayInsertScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tourOverlayInsertScheduled = false;
      if (!mounted) {
        return;
      }
      _ensureTourOverlay();
    });
  }

  void _ensureTourOverlay() {
    if (_tourOverlayEntry != null) {
      return;
    }
    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    if (overlay == null) {
      return;
    }
    _tourOverlayEntry = OverlayEntry(
      builder: (context) => BlocProvider.value(
        value: _tourCubit,
        child: TourOverlayScreen(
          onStepChanged: _handleTourStepChanged,
          onNext: _handleTourNext,
          targetRectResolver: _resolveTourTargetRect,
          targetRectsResolver: _resolveTourTargetRects,
        ),
      ),
    );
    overlay.insert(_tourOverlayEntry!);
  }

  void _bringTourOverlayToFront() {
    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    final entry = _tourOverlayEntry;
    if (overlay == null || entry == null) {
      return;
    }
    entry.remove();
    overlay.insert(entry);
  }

  void _scheduleBringTourOverlayToFront({required int remainingFrames}) {
    if (remainingFrames <= 0) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _bringTourOverlayToFront();
      _tourOverlayEntry?.markNeedsBuild();
      _scheduleBringTourOverlayToFront(remainingFrames: remainingFrames - 1);
    });
  }

  void _removeTourOverlay() {
    _tourOverlayEntry?.remove();
    _tourOverlayEntry?.dispose();
    _tourOverlayEntry = null;
  }

  void _handleTourNext(TourStep step) {
    if (step.id == 'find_ref') {
      _openFirstTourFindRefResult();
      return;
    }
    if (step.id == 'advanced_search' && _isSearchOpen) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    _closeTourOverflowMenuIfNeeded();
    _tourCubit.next();
  }

  void _scheduleTourOverflowMenuForStep(TourStep step) {
    if (!_usesReadingOverflowMenu(step.area)) {
      _closeTourOverflowMenuIfNeeded();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _directReadingTourTargetRect(step.area) != null) {
        _closeTourOverflowMenuIfNeeded();
        return;
      }
      _openReadingOverflowMenuForTour();
    });
  }

  bool _usesReadingOverflowMenu(TourSpotlightArea area) {
    return area == TourSpotlightArea.commentators ||
        area == TourSpotlightArea.bookmark ||
        area == TourSpotlightArea.bookSearch ||
        area == TourSpotlightArea.print;
  }

  void _openReadingOverflowMenuForTour() {
    final state =
        (textBookOverflowTourTargetKey.currentState ??
                pdfBookOverflowTourTargetKey.currentState)
            as dynamic;
    if (state == null) {
      return;
    }
    state?.showMenu();
    _tourOpenedOverflowMenu = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _bringTourOverlayToFront();
      _scheduleTourTargetRebuilds(remainingFrames: 3);
    });
  }

  void _closeTourOverflowMenuIfNeeded() {
    if (!_tourOpenedOverflowMenu) {
      return;
    }
    _tourOpenedOverflowMenu = false;
    Navigator.of(context, rootNavigator: true).maybePop();
  }

  void _openTourFindRef() {
    final focusRepository = context.read<FocusRepository>();
    focusRepository.findRefSearchController.text = 'בראשית';
    focusRepository.findRefSearchController.selection =
        const TextSelection.collapsed(offset: 'בראשית'.length);
    context.read<FindRefBloc>().add(const SearchRefRequested('בראשית'));
    _handleFindRefOpen(context, closeIfOpen: false);
    _scheduleBringTourOverlayToFront(remainingFrames: 6);
  }

  Future<void> _openFirstTourFindRefResult() async {
    final findRefState = context.read<FindRefBloc>().state;
    if (findRefState is! FindRefSuccess || findRefState.refs.isEmpty) {
      return;
    }

    final ref = findRefState.refs.first;
    Book? book;
    try {
      final library = await DataRepository.instance.library;
      book = _findBookByTitle(library, ref.title);
    } catch (e) {
      debugPrint('Error searching library: $e');
    }

    if (!mounted) {
      return;
    }

    book ??= ref.isPdf
        ? PdfBook(title: ref.title, path: ref.filePath)
        : TextBook(title: ref.title);

    _openGenesisForTour = false;
    if (_isFindRefOpen) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    // לא סוגרים טאבים פתוחים: התוצאה נפתחת בסוף רשימת הטאבים (ללא
    // insertAdjacent), כך שטאבי טקסט קיימים מעובדים לפניה ומשחררים את מפתחות
    // הסיור לפני שהיא מקבלת אותם — בלי כפילות GlobalKeys.
    final frameCompleter = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => frameCompleter.complete(),
    );
    await frameCompleter.future;
    if (!mounted) return;
    openBook(
      context,
      book,
      ref.segment.toInt(),
      '',
      ignoreHistory: true,
      requiresStableLayout: ref.isPdf,
    );
    if (_tourCubit.state.currentStep?.id == 'find_ref') {
      await _tourCubit.next();
    }
  }

  Rect? _resolveTourTargetRect(TourStep step) {
    final exactRect = _exactTourTargetRect(step);
    if (exactRect != null) {
      return exactRect;
    }
    if (_usesReadingOverflowMenu(step.area)) {
      return _readingTourTargetRect(step.area);
    }
    if (step.area != TourSpotlightArea.bookCard) {
      return null;
    }
    final libraryState = libraryBrowserKey.currentState;
    if (libraryState == null) {
      return null;
    }
    return (libraryState as dynamic).tourBookCardRect() as Rect?;
  }

  Rect? _exactTourTargetRect(TourStep step) {
    switch (step.id) {
      case 'navigation':
        return _combinedRectForKeys(tourMainNavigationTargetKeys);
      case 'library':
        return _libraryTourRect('tourLibraryRect');
      case 'library_search':
        return _libraryTourRect('tourLibrarySearchRect');
      case 'categories':
        return _libraryTourRect('tourLibraryCategoriesRect');
      case 'advanced_search':
        return _rectForGlobalKey(tourSearchDialogTargetKey);
      case 'find_ref':
        return _findRefDialogTourRect();
      case 'reading':
        return _rectForGlobalKey(tourReadingScreenTargetKey);
      case 'tabs':
        return _tabsTourTargetRect();
      case 'reading_settings':
        return _rectForGlobalKey(tourReadingSettingsButtonTargetKey);
      case 'tools':
        return _navItemTourRect(_toolsNavIndex);
      case 'settings':
        return _navItemTourRectForScreen(Screen.settings);
      case 'appearance':
        return _rectForGlobalKey(tourSettingsTabTargetKeys[0]!);
    }

    if (step.id == 'toc') {
      return _rectForGlobalKey(textBookNavigationTourTargetKey) ??
          _rectForGlobalKey(pdfBookNavigationTourTargetKey);
    }

    return switch (step.area) {
      TourSpotlightArea.tableOfContents =>
        _rectForGlobalKey(textBookNavigationTourTargetKey) ??
            _rectForGlobalKey(pdfBookNavigationTourTargetKey),
      // טיפים חיים באזור ההגדרות נצמדים לפריט הניווט של ההגדרות
      TourSpotlightArea.settings => _navItemTourRectForScreen(Screen.settings),
      _ => null,
    };
  }

  List<Rect> _resolveTourTargetRects(TourStep step) {
    if (step.id == 'advanced_search') {
      final dialogRect = _rectForGlobalKey(tourSearchDialogTargetKey);
      final navSearchRect = _navItemTourRectForScreen(Screen.search);
      return [?dialogRect, ?navSearchRect];
    }

    if (step.id == 'find_ref') {
      final dialogRect = _findRefDialogTourRect();
      final navFindRefRect = _navItemTourRectForScreen(Screen.find);
      return [?dialogRect, ?navFindRefRect];
    }

    if (step.id == 'toc') {
      final buttonRect =
          _rectForGlobalKey(textBookNavigationTourTargetKey) ??
          _rectForGlobalKey(pdfBookNavigationTourTargetKey);
      final panelRect = _rectForGlobalKey(activeTextBookNavPanelTourTargetKey);
      return [?buttonRect, ?panelRect];
    }

    if (step.id == 'bookmark') {
      final titleBarHistoryRect = _rectForGlobalKey(
        tourTitleBarHistoryButtonTargetKey,
      );
      final titleBarBookmarkRect = _rectForGlobalKey(
        tourTitleBarBookmarkButtonTargetKey,
      );
      final directRect = _directReadingTourTargetRect(step.area);
      if (directRect != null) {
        return [directRect, ?titleBarHistoryRect, ?titleBarBookmarkRect];
      }
      final overflowRect =
          _rectForGlobalKey(textBookOverflowTourTargetKey) ??
          _rectForGlobalKey(pdfBookOverflowTourTargetKey);
      final menuItemRect = _readingOverflowMenuItemRect(step.area);
      return [
        ?overflowRect,
        ?menuItemRect,
        ?titleBarHistoryRect,
        ?titleBarBookmarkRect,
      ];
    }

    if (!_usesReadingOverflowMenu(step.area)) {
      final rect = _resolveTourTargetRect(step);
      return rect == null ? const [] : [rect];
    }

    final directRect = _directReadingTourTargetRect(step.area);
    if (directRect != null) {
      return [directRect];
    }

    final overflowRect =
        _rectForGlobalKey(textBookOverflowTourTargetKey) ??
        _rectForGlobalKey(pdfBookOverflowTourTargetKey);
    final menuItemRect = _readingOverflowMenuItemRect(step.area);
    return [?overflowRect, ?menuItemRect];
  }

  Rect? _readingTourTargetRect(TourSpotlightArea area) {
    final directRect = _directReadingTourTargetRect(area);
    if (directRect != null) {
      return directRect;
    }

    final overflowRect =
        _rectForGlobalKey(textBookOverflowTourTargetKey) ??
        _rectForGlobalKey(pdfBookOverflowTourTargetKey);
    final menuItemRect = _readingOverflowMenuItemRect(area);

    if (overflowRect != null && menuItemRect != null) {
      return overflowRect.expandToInclude(menuItemRect);
    }
    return menuItemRect ?? overflowRect;
  }

  Rect? _directReadingTourTargetRect(TourSpotlightArea area) {
    return switch (area) {
      TourSpotlightArea.commentators => _rectForGlobalKey(
        textBookCommentatorsTourTargetKey,
      ),
      TourSpotlightArea.bookmark =>
        _rectForGlobalKey(textBookBookmarkTourTargetKey) ??
            _rectForGlobalKey(pdfBookBookmarkTourTargetKey),
      TourSpotlightArea.bookSearch =>
        _rectForGlobalKey(textBookSearchTourTargetKey) ??
            _rectForGlobalKey(pdfBookSearchTourTargetKey),
      TourSpotlightArea.print =>
        _rectForGlobalKey(textBookPrintTourTargetKey) ??
            _rectForGlobalKey(pdfBookPrintTourTargetKey),
      _ => null,
    };
  }

  Rect? _readingOverflowMenuItemRect(TourSpotlightArea area) {
    return switch (area) {
      TourSpotlightArea.commentators => _rectForGlobalKey(
        textBookOverflowCommentatorsTourTargetKey,
      ),
      TourSpotlightArea.bookmark =>
        _rectForGlobalKey(textBookOverflowBookmarkTourTargetKey) ??
            _rectForGlobalKey(pdfBookOverflowBookmarkTourTargetKey),
      TourSpotlightArea.bookSearch =>
        _rectForGlobalKey(textBookOverflowSearchTourTargetKey) ??
            _rectForGlobalKey(pdfBookOverflowSearchTourTargetKey),
      TourSpotlightArea.print =>
        _rectForGlobalKey(textBookOverflowPrintTourTargetKey) ??
            _rectForGlobalKey(pdfBookOverflowPrintTourTargetKey),
      _ => null,
    };
  }

  Rect? _libraryTourRect(String methodName) {
    final libraryState = libraryBrowserKey.currentState;
    if (libraryState == null) {
      return null;
    }
    final dynamic state = libraryState;
    return switch (methodName) {
      'tourLibraryRect' => state.tourLibraryRect() as Rect?,
      'tourLibrarySearchRect' => state.tourLibrarySearchRect() as Rect?,
      'tourLibraryCategoriesRect' => state.tourLibraryCategoriesRect() as Rect?,
      _ => null,
    };
  }

  Rect? _combinedRectForKeys(Iterable<GlobalKey> keys) {
    Rect? combined;
    for (final key in keys) {
      final rect = _rectForGlobalKey(key);
      if (rect == null) continue;
      combined = combined == null ? rect : combined.expandToInclude(rect);
    }
    return combined;
  }

  Rect? _tabsTourTargetRect() {
    final rect = _rectForGlobalKey(tourReadingTabsTargetKey, inflate: 0);
    if (rect == null) {
      return null;
    }
    return Rect.fromLTRB(
      rect.left - 36,
      rect.top - 4,
      rect.right,
      rect.bottom + 4,
    );
  }

  Rect? _findRefDialogTourRect() {
    final contentRect = _rectForGlobalKey(
      tourFindRefDialogTargetKey,
      inflate: 0,
    );
    if (contentRect == null) {
      return null;
    }
    return Rect.fromLTRB(
      contentRect.left - 24,
      contentRect.top - 80,
      contentRect.right + 24,
      contentRect.bottom + 88,
    );
  }

  Rect? _navItemTourRect(int index) {
    if (index < 0 || index >= tourMainNavigationItemTargetKeys.length) {
      return null;
    }
    return _rectForGlobalKey(
      tourMainNavigationItemTargetKeys[index],
      inflate: 2,
    );
  }

  Rect? _navItemTourRectForScreen(Screen screen) {
    return _navItemTourRect(_navIndexForScreen(screen));
  }

  int _navIndexForScreen(Screen screen) {
    return _navData.indexWhere((item) => item.screen == screen);
  }

  Rect? _rectForGlobalKey(GlobalKey? key, {double inflate = 4}) {
    final context = key?.currentContext;
    if (context == null || !context.mounted) {
      return null;
    }
    // findRenderObject() can throw in debug mode if the element deactivates
    // between the mounted check and the layout callback — a Flutter-internal
    // race that context.mounted alone cannot prevent.
    RenderObject? renderObject;
    try {
      renderObject = context.findRenderObject();
    } catch (_) {
      return null;
    }
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }
    // ילד keep-alive שנגלל מחוץ ל-viewport עובר את בדיקות attached/hasSize,
    // אבל layoutOffset שלו ב-sliver הוא null ו-localToGlobal זורק.
    try {
      final topLeft = renderObject.localToGlobal(Offset.zero);
      return (topLeft & renderObject.size).inflate(inflate);
    } catch (_) {
      return null;
    }
  }

  void _scheduleTourTargetRebuilds({required int remainingFrames}) {
    if (remainingFrames <= 0) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _tourOverlayEntry?.markNeedsBuild();
      _scheduleTourTargetRebuilds(remainingFrames: remainingFrames - 1);
    });
  }

  Future<void> _openTourGenesisInReader() async {
    // לא סוגרים טאבים פתוחים: הסיור פותח את בראשית בסוף רשימת הטאבים (ללא
    // insertAdjacent), כך שכל טאב טקסט קיים מעובד לפניו ב-PageView ומשחרר את
    // מפתחות הסיור לפני שבראשית מקבל אותם — בלי כפילות GlobalKeys.
    // אם בראשית כבר פתוח, openBook יתמקד בו במקום לפתוח טאב כפול.
    final frameCompleter = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => frameCompleter.complete(),
    );
    await frameCompleter.future;
    if (!mounted) return;
    try {
      final library = await DataRepository.instance.library;
      final book =
          _findBookByTitle(library, 'בראשית') ??
          TextBook(title: 'בראשית', fileType: 'txt');
      if (!mounted) return;
      openBook(context, book, 0, '', ignoreHistory: true);
    } catch (_) {
      if (!mounted) return;
      openBook(
        context,
        TextBook(title: 'בראשית', fileType: 'txt'),
        0,
        '',
        ignoreHistory: true,
      );
    }
  }

  Book? _findBookByTitle(library_model.Category category, String title) {
    for (final book in category.books) {
      if (book.title == title) {
        return book;
      }
    }
    for (final subCategory in category.subCategories) {
      final book = _findBookByTitle(subCategory, title);
      if (book != null) {
        return book;
      }
    }
    return null;
  }

  void _scheduleTourStartIfNeeded({required bool libraryLoaded}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_tourCubit.startIfNeeded(libraryLoaded: libraryLoaded)) {
        _tourStartedAutomaticallyThisLaunch = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _calendarCubit),
        BlocProvider.value(value: _tourCubit),
      ],
      child: MultiBlocListener(
        listeners: [
          BlocListener<NavigationBloc, NavigationState>(
            listenWhen: (previous, current) =>
                previous.currentScreen != current.currentScreen,
            listener: (context, state) {
              PluginRuntimeDispatcher.instance.dispatchEvent(
                'navigation.changed',
                {'screen': state.currentScreen.name},
              );
              _handleNavigationChange(context, state);
            },
          ),
          BlocListener<WorkspaceBloc, WorkspaceState>(
            listenWhen: (previous, current) =>
                previous.activeWorkspaceId != current.activeWorkspaceId ||
                (previous.isLoading && !current.isLoading),
            listener: (context, state) {
              PluginRuntimeDispatcher.instance.dispatchEvent(
                'workspace.changed',
                {'workspaceId': state.activeWorkspaceId},
              );
              // עדכון שם שולחן העבודה הנוכחי ב-HistoryBloc
              final currentId = state.activeWorkspaceId;
              if (currentId != null) {
                final workspace = state.workspaces.firstWhere(
                  (w) => w.id == currentId,
                );
                context.read<HistoryBloc>().add(
                  SetCurrentWorkspaceName(workspace.name),
                );
              }
            },
          ),
          // ריענון הספרייה אחרי עדכון, ואישור הורדה מלאה. מוגדר כאן (לא
          // ב-LibraryBrowser) כדי שיהיה mounted גם כשנפתחים למסך אחר.
          BlocListener<LibraryUpdateBloc, LibraryUpdateState>(
            listenWhen: LibraryUpdateState.hasRefreshRelevantChange,
            listener: (context, state) {
              if (state.status == LibraryUpdateStatus.completed &&
                  state.hasUpdate) {
                _indexAfterLibraryReload = true;
                _reconcileAfterLibraryReload = state.isFullDownloadPlan;
                context.read<LibraryBloc>().add(
                  RefreshLibrary(
                    changedBookKeys: {
                      for (final id in state.changedBookIds)
                        IndexingRepository.officialBookKey(id),
                    },
                  ),
                );
              } else if (state.status ==
                  LibraryUpdateStatus.needsFullConfirmation) {
                _promptFullDownload(context, state);
              }
            },
          ),
          BlocListener<LibraryBloc, LibraryState>(
            listenWhen: (previous, current) =>
                previous.isLoading &&
                !current.isLoading &&
                current.library != null,
            listener: (context, state) {
              _startupWorkGate.markLibraryLoaded();
              _tryStartDeferredStartupWork();
              // החלטת האינדוקס צורכת את הקטלוג שזה עתה נטען — כך אין קריאה
              // עצמאית ל-getLibrary שתתחרה בטעינת הספר הפעיל בעלייה.
              if (state.library != null) {
                _checkAndStartIndexing(context, state.library!);
                _indexAfterDbUpdateIfNeeded(context, state.library!);
                // ניקוי רשומות אינדקס של ספרים שכבר אינם בספרייה (ספר אישי
                // שנמחק, תיקייה שהוסרה). רץ על כל טעינת/רענון ספרייה, בתור
                // העבודה הסדרתי — אחרי מסלולי האינדוקס של אותו רענון.
                context.read<IndexingBloc>().add(
                  DropOrphanedIndexEntries(state.library!),
                );
              }
              final navigationState = context.read<NavigationBloc>().state;
              if (navigationState.hasCheckedLibrary &&
                  !navigationState.isLibraryEmpty) {
                if (_tourCubit.startIfNeeded(libraryLoaded: true)) {
                  _tourStartedAutomaticallyThisLaunch = true;
                }
              }
            },
          ),
          BlocListener<LibraryBloc, LibraryState>(
            listenWhen: (previous, current) =>
                current.changedBooksToIndex != null &&
                current.changedBooksToIndex!.isNotEmpty,
            listener: (context, state) {
              // ספרים שתוכנם השתנה — רשומותיהם הישנות מוסרות ומאונדקסות מחדש.
              if (context.read<SettingsBloc>().state.autoUpdateIndex) {
                context.read<IndexingBloc>().add(
                  ReindexChangedBooks(
                    state.changedBooksToIndex!,
                    state.library!,
                  ),
                );
              }
            },
          ),
          BlocListener<LibraryBloc, LibraryState>(
            listenWhen: (previous, current) =>
                current.newBooksToIndex != null &&
                current.newBooksToIndex!.isNotEmpty,
            listener: (context, state) {
              // אחרי עדכון DB, StartIndexing כבר אינדקס את כל הספרייה — מדלגים
              // על מסלול האינדוקס השני (חד-פעמי לאותו refresh).
              if (_dbUpdateTriggeredFullIndex) {
                _dbUpdateTriggeredFullIndex = false;
                return;
              }
              if (context.read<SettingsBloc>().state.autoUpdateIndex) {
                context.read<IndexingBloc>().add(
                  IndexSpecificBooks(state.newBooksToIndex!, state.library!),
                );
              } else {
                context.read<IndexingBloc>().add(
                  CheckIndexStatus(state.library!),
                );
              }
            },
          ),
          BlocListener<IndexingBloc, IndexingState>(
            listenWhen: (previous, current) =>
                (previous is IndexingInProgress) !=
                (current is IndexingInProgress),
            listener: (context, state) {
              _startupWorkGate.markIndexingRunning(state is IndexingInProgress);
              _tryStartDeferredStartupWork();
            },
          ),
          BlocListener<IndexingBloc, IndexingState>(
            listener: (context, state) {
              final cubit = context.read<WorkStatusCubit>();
              if (state is IndexingInProgress && state.isCreatingIndex) {
                final total = state.totalBooks ?? 0;
                final processed = state.booksProcessed ?? 0;
                final progress = total > 0
                    ? (processed / total).clamp(0.0, 1.0)
                    : null;
                cubit.upsert(
                  WorkStatusItem(
                    id: 'indexing',
                    title: 'אינדוקס ספרים',
                    message: 'התוכנה בתהליך אינדוקס',
                    detail: 'התקדמות: $processed/$total',
                    progress: progress,
                    onTap: _openIndexingSettings,
                  ),
                );
              } else {
                cubit.remove('indexing');
              }
            },
          ),
          BlocListener<LibraryUpdateBloc, LibraryUpdateState>(
            listenWhen: (previous, current) =>
                previous.status != current.status ||
                previous.message != current.message ||
                previous.bytesDownloaded != current.bytesDownloaded ||
                previous.applyProgress != current.applyProgress,
            listener: (context, state) {
              final cubit = context.read<WorkStatusCubit>();
              final item = libraryUpdateWorkStatusItem(
                state,
                onRetry: () => context.read<LibraryUpdateBloc>().add(
                  const StartLibraryUpdate(),
                ),
              );
              if (item == null) {
                cubit.remove(kLibraryUpdateWorkStatusId);
              } else {
                cubit.upsert(item);
              }
            },
          ),
          BlocListener<SettingsBloc, SettingsState>(
            listenWhen: (previous, current) {
              // fire on first load or any change to plugin-visible settings
              if (previous == SettingsState.initial() &&
                  current != SettingsState.initial()) {
                return true;
              }
              return previous.isDarkMode != current.isDarkMode ||
                  previous.followSystemTheme != current.followSystemTheme ||
                  previous.seedColor != current.seedColor ||
                  previous.darkSeedColor != current.darkSeedColor ||
                  previous.fontSize != current.fontSize ||
                  previous.fontFamily != current.fontFamily ||
                  previous.commentatorsFontFamily !=
                      current.commentatorsFontFamily ||
                  previous.fontBold != current.fontBold ||
                  previous.commentatorsFontBold !=
                      current.commentatorsFontBold ||
                  previous.commentatorsFontSize !=
                      current.commentatorsFontSize ||
                  previous.lineHeight != current.lineHeight ||
                  previous.autoUpdateIndex != current.autoUpdateIndex ||
                  previous.showTeamim != current.showTeamim ||
                  previous.defaultRemoveNikud != current.defaultRemoveNikud ||
                  previous.removeNikudFromTanach !=
                      current.removeNikudFromTanach ||
                  previous.replaceHolyNames != current.replaceHolyNames ||
                  previous.libraryViewMode != current.libraryViewMode ||
                  previous.copyWithHeaders != current.copyWithHeaders ||
                  previous.copyHeaderFormat != current.copyHeaderFormat;
            },
            listener: (context, current) {
              final previous = _prevSettingsState ?? SettingsState.initial();
              _prevSettingsState = current;

              // --- settings.changed: one event per changed key (allowlist only) ---
              void dispatch(String key, dynamic value) {
                PluginRuntimeDispatcher.instance.dispatchEvent(
                  'settings.changed',
                  {'key': key, 'newValue': value},
                );
              }

              if (previous.isDarkMode != current.isDarkMode) {
                dispatch(SettingsRepository.keyDarkMode, current.isDarkMode);
              }
              if (previous.followSystemTheme != current.followSystemTheme) {
                dispatch(
                  SettingsRepository.keyFollowSystemTheme,
                  current.followSystemTheme,
                );
              }
              if (previous.seedColor != current.seedColor) {
                dispatch(
                  SettingsRepository.keySwatchColor,
                  current.seedColor.toARGB32().toRadixString(16),
                );
              }
              if (previous.darkSeedColor != current.darkSeedColor) {
                dispatch(
                  SettingsRepository.keyDarkSwatchColor,
                  current.darkSeedColor.toARGB32().toRadixString(16),
                );
              }
              if (previous.fontSize != current.fontSize) {
                dispatch(SettingsRepository.keyFontSize, current.fontSize);
              }
              if (previous.fontFamily != current.fontFamily) {
                dispatch(SettingsRepository.keyFontFamily, current.fontFamily);
              }
              if (previous.commentatorsFontFamily !=
                  current.commentatorsFontFamily) {
                dispatch(
                  SettingsRepository.keyCommentatorsFontFamily,
                  current.commentatorsFontFamily,
                );
              }
              if (previous.commentatorsFontSize !=
                  current.commentatorsFontSize) {
                dispatch(
                  SettingsRepository.keyCommentatorsFontSize,
                  current.commentatorsFontSize,
                );
              }
              if (previous.lineHeight != current.lineHeight) {
                dispatch(SettingsRepository.keyLineHeight, current.lineHeight);
              }
              if (previous.showTeamim != current.showTeamim) {
                dispatch(SettingsRepository.keyShowTeamim, current.showTeamim);
              }
              if (previous.defaultRemoveNikud != current.defaultRemoveNikud) {
                dispatch(
                  SettingsRepository.keyDefaultNikud,
                  current.defaultRemoveNikud,
                );
              }
              if (previous.removeNikudFromTanach !=
                  current.removeNikudFromTanach) {
                dispatch(
                  SettingsRepository.keyRemoveNikudFromTanach,
                  current.removeNikudFromTanach,
                );
              }
              if (previous.replaceHolyNames != current.replaceHolyNames) {
                dispatch(
                  SettingsRepository.keyReplaceHolyNames,
                  current.replaceHolyNames,
                );
              }
              if (previous.libraryViewMode != current.libraryViewMode) {
                dispatch(
                  SettingsRepository.keyLibraryViewMode,
                  current.libraryViewMode,
                );
              }
              if (previous.copyWithHeaders != current.copyWithHeaders) {
                dispatch(
                  SettingsRepository.keyCopyWithHeaders,
                  current.copyWithHeaders,
                );
              }
              if (previous.copyHeaderFormat != current.copyHeaderFormat) {
                dispatch(
                  SettingsRepository.keyCopyHeaderFormat,
                  current.copyHeaderFormat,
                );
              }

              // --- theme.changed: only when visual theme changes ---
              final isThemeChange =
                  previous.isDarkMode != current.isDarkMode ||
                  previous.followSystemTheme != current.followSystemTheme ||
                  previous.seedColor != current.seedColor ||
                  previous.darkSeedColor != current.darkSeedColor ||
                  previous.fontSize != current.fontSize ||
                  previous.fontFamily != current.fontFamily ||
                  previous.lineHeight != current.lineHeight ||
                  previous.commentatorsFontFamily !=
                      current.commentatorsFontFamily ||
                  previous.commentatorsFontSize != current.commentatorsFontSize;
              if (isThemeChange) {
                // ה-MaterialApp מתעדכן רק ב-frame הבא, כך ש-Theme.of(context)
                // כאן עדיין מחזיר את הצבעים הישנים. לכן בונים את ה-payload
                // דטרמיניסטית מתוך ה-state (שכבר עדכני) ולא מ-Theme.
                final brightness = current.followSystemTheme
                    ? WidgetsBinding
                          .instance
                          .platformDispatcher
                          .platformBrightness
                    : (current.isDarkMode ? Brightness.dark : Brightness.light);
                final isDark = brightness == Brightness.dark;
                final seed = isDark ? current.darkSeedColor : current.seedColor;
                final colorScheme = AppThemeData.createColorScheme(
                  seed,
                  brightness,
                );
                final themePayload = buildThemePayloadFromScheme(
                  colorScheme,
                  isDark: isDark,
                );
                PluginRuntimeDispatcher.instance.dispatchEvent(
                  'theme.changed',
                  themePayload,
                );
              }

              // --- internal app logic ---
              // הערה: החלטת האינדוקס בעלייה (_checkAndStartIndexing) הועברה
              // ל-listener של טעינת הספרייה, כדי שתצרוך את הקטלוג הקיים ולא
              // תפעיל בנייה עצמאית שתתחרה בטעינת הספר הפעיל.
              if (!previous.autoUpdateIndex && current.autoUpdateIndex) {
                _startIndexing(context);
              }
            },
          ),
          BlocListener<TabsBloc, TabsState>(
            // גם החלפת חלונית פעילה היא החלפת הספר הפתוח מבחינת התוספים.
            listenWhen: (previous, current) =>
                previous.currentTab != current.currentTab ||
                previous.readingPane != current.readingPane,
            listener: (context, state) {
              final currentTab = state.currentTab;
              // הטאב הפעיל אוכלס (אסינכרונית בעלייה) — כעת אפשר לתזמן את חשיפת
              // החלון המלא תוך מתן עדיפות לספר הפעיל. no-op אם כבר תוזמן/נחשף.
              _scheduleSplashReveal();
              if (currentTab != null) {
                int tabIndex = 0;
                if (currentTab is TextBookTab) tabIndex = currentTab.index;
                if (currentTab is PdfBookTab) tabIndex = currentTab.pageNumber;
                _tourCubit.recordInteraction(
                  TourInteraction(
                    type: TourInteractionType.currentTabChanged,
                    primaryValue: currentTab.title,
                  ),
                );
                if (currentTab is TextBookTab) {
                  _tourCubit.recordInteraction(
                    TourInteraction(
                      type: TourInteractionType.openedTextBook,
                      primaryValue: currentTab.title,
                    ),
                  );
                }
                if (currentTab is CombinedTab) {
                  _tourCubit.recordInteraction(
                    TourInteraction(
                      type: TourInteractionType.sideBySideEnabled,
                      primaryValue: currentTab.title,
                    ),
                  );
                }
                // החלונית הקוראת ולא הטאב: טאב כלי אינו ספר כלל.
                final pane = state.readingPane;
                if (pane != null) {
                  final paneBook = pane is TextBookTab
                      ? pane.book
                      : (pane is PdfBookTab ? pane.book : null);
                  PluginRuntimeDispatcher.instance.dispatchEvent(
                    'reader.current_book_changed',
                    {
                      'book': pane.title,
                      'bookId': pane.title,
                      'id': paneBook?.id,
                      'type': paneBook != null
                          ? PluginBookIdentity.typeOf(paneBook)
                          : null,
                      'source': paneBook != null
                          ? PluginBookIdentity.sourceOf(paneBook)
                          : null,
                      'index': pane is TextBookTab
                          ? pane.index
                          : (pane is PdfBookTab ? pane.pageNumber : tabIndex),
                    },
                  );
                }
              }
            },
          ),
          // סנכרון רשימת הטאבים הפתוחים ל-Jump List של שורת המשימות (Windows).
          // נדלק כשהכותרות או סדרן משתנים; השירות עצמו no-op מחוץ ל-Windows.
          BlocListener<TabsBloc, TabsState>(
            listenWhen: (previous, current) => !listEquals(
              previous.tabs.map((tab) => tab.title).toList(),
              current.tabs.map((tab) => tab.title).toList(),
            ),
            listener: (context, state) => _jumpListService.sync(state.tabs),
          ),
          // settings.changed עבור selectedCity ו-calendarType —
          // שדות אלה נמצאים ב-CalendarState ולא ב-SettingsState
          BlocListener<CalendarCubit, CalendarState>(
            listenWhen: (previous, current) =>
                previous.selectedCity != current.selectedCity ||
                previous.calendarType != current.calendarType,
            listener: (context, current) {
              final previous = _prevCalendarState;
              _prevCalendarState = current;
              if (previous == null) return;
              if (previous.selectedCity != current.selectedCity) {
                PluginRuntimeDispatcher.instance.dispatchEvent(
                  'settings.changed',
                  {
                    'key': SettingsRepository.keySelectedCity,
                    'newValue': current.selectedCity,
                  },
                );
              }
              if (previous.calendarType != current.calendarType) {
                PluginRuntimeDispatcher.instance.dispatchEvent(
                  'settings.changed',
                  {
                    'key': SettingsRepository.keyCalendarType,
                    'newValue': current.calendarType.toString(),
                  },
                );
              }
            },
          ),
          // רענון לוח כשמשתנה הספר הפתוח (book-scope events)
          BlocListener<TabsBloc, TabsState>(
            listenWhen: (previous, current) =>
                previous.readingPane?.title != current.readingPane?.title,
            listener: (context, state) {
              final bookId = state.readingPane?.title;
              final workspaceId = context
                  .read<WorkspaceBloc>()
                  .state
                  .activeWorkspaceId;
              _calendarCubit.refreshPluginEvents(
                currentBookId: bookId,
                currentWorkspaceId: workspaceId,
              );
            },
          ),
          // רענון לוח כשמשתנה ה-workspace (workspace-scope events)
          BlocListener<WorkspaceBloc, WorkspaceState>(
            listenWhen: (previous, current) =>
                previous.activeWorkspaceId != current.activeWorkspaceId,
            listener: (context, state) {
              final workspaceId = state.activeWorkspaceId;
              final bookId = context.read<TabsBloc>().state.readingPane?.title;
              _calendarCubit.refreshPluginEvents(
                currentWorkspaceId: workspaceId,
                currentBookId: bookId,
              );
            },
          ),
          BlocListener<PluginSystemBloc, PluginSystemState>(
            listenWhen: (_, current) =>
                current is PluginSystemInstallRequiresPermissions ||
                current is PluginSystemDevInstallRequiresPermissions ||
                current is PluginSystemOverwriteRequired,
            listener: (context, state) {
              final isOfflineMode = context
                  .read<SettingsBloc>()
                  .state
                  .isOfflineMode;
              if (state is PluginSystemInstallRequiresPermissions) {
                showDialog(
                  context: context,
                  builder: (_) => BlocProvider.value(
                    value: context.read<PluginSystemBloc>(),
                    child: PluginInstallScreen(
                      manifest: state.manifest,
                      tempDirPath: state.tempDirPath,
                      previousVersion: state.previousVersion,
                      previousAllowOrderBeforeBuiltInsGranted:
                          state.previousAllowOrderBeforeBuiltInsGranted,
                      reportContext: state.reportContext,
                      isOfflineMode: isOfflineMode,
                    ),
                  ),
                );
              } else if (state is PluginSystemDevInstallRequiresPermissions) {
                final bloc = context.read<PluginSystemBloc>();
                showDialog(
                  context: context,
                  builder: (_) => PluginInstallScreen(
                    manifest: state.manifest,
                    tempDirPath: '',
                    previousVersion: state.previousVersion,
                    previousAllowOrderBeforeBuiltInsGranted:
                        state.previousAllowOrderBeforeBuiltInsGranted,
                    isOfflineMode: isOfflineMode,
                    onConfirm: (perms, allowOrder) => bloc.add(
                      ConfirmDevPluginInstall(
                        manifest: state.manifest,
                        sourcePath: state.sourcePath,
                        sourceType: state.sourceType,
                        grantedPermissions: perms,
                        allowOrderBeforeBuiltInsGranted: allowOrder,
                      ),
                    ),
                    onCancel: () => bloc.add(LoadPlugins()),
                  ),
                );
              } else if (state is PluginSystemOverwriteRequired) {
                final bloc = context.read<PluginSystemBloc>();
                showWarningDialog(
                  context: context,
                  title: 'התוסף כבר קיים',
                  content:
                      'התוסף "${state.pluginName}" בגרסה ${state.version} כבר מותקן.',
                  subtitle: 'האם ברצונך להתקין מחדש ולדרוס אותו?',
                  cancelText: 'ביטול',
                  confirmText: 'התקן מחדש',
                ).then((value) {
                  if (value == true) {
                    bloc.add(
                      InstallPluginRequested(
                        state.archivePath,
                        forceOverwrite: true,
                      ),
                    );
                  } else {
                    bloc.add(LoadPlugins());
                  }
                });
              }
            },
          ),
        ],
        child: BlocBuilder<NavigationBloc, NavigationState>(
          builder: (context, state) {
            // נבנה את הדפים רק פעם אחת ונשמור אותם.
            //
            // אופטימיזציית bootstrap: LibraryBrowser הוא widget כבד עם BlocBuilder<LibraryBloc>
            // ו-context גלובלי. כש-PageView (ב-index 1=Reading) דורש את שכניו (index 0=Library),
            // הקונסטרקטור והקריאות הראשוניות חוסמות את ה-UI thread. עד שהמשתמש לא ביקש לפתוח
            // את הספרייה, מציגים placeholder ריק; כשהוא יבחר 'ספרייה', ה-BlocBuilder ירוץ שוב
            // ויחליף ל-LibraryBrowser האמיתי. כשאין ספרייה, LibraryBrowser עצמו מציג את
            // מסך ההגדרה בתוך אזור התוכן — אין מסך נפרד.
            final libraryBuildDecision = resolveLibraryPageBuildDecision(
              hasBuiltRealPage: _hasBuiltRealLibraryPage,
              currentScreen: state.currentScreen,
            );

            if (libraryBuildDecision ==
                LibraryPageBuildDecision.buildRealPage) {
              _cachedLibraryPage = LibraryBrowser(key: libraryBrowserKey);
              _hasBuiltRealLibraryPage = true;
            } else if (libraryBuildDecision ==
                LibraryPageBuildDecision.usePlaceholder) {
              // המשתמש עדיין ב-Reading/Tools/Settings ולא ביקש את הספרייה —
              // מציגים placeholder זול. הוא יוחלף ל-LibraryBrowser בפעם הראשונה
              // שהמשתמש ינווט ל-Screen.library.
              _cachedLibraryPage = const SizedBox.shrink();
            }

            _cachedReadingPage ??= ReadingScreen(key: _readingScreenKey);
            _cachedSettingsPage ??= MySettingsScreen(
              key: _settingsScreenKey,
              controller: _settingsScreenController,
            );

            _pages = _buildPagesList();

            if (state.hasCheckedLibrary) {
              _scheduleTourStartIfNeeded(libraryLoaded: !state.isLibraryEmpty);
            }
            _scheduleTourOverlayInsert();

            // ב-Android 15+ (targetSdk 35+) edge-to-edge נכפה: שורת הסטטוס
            // והניווט שקופות תמיד, וה-SafeArea דוחף את התוכן מתחתן — כך שללא
            // צביעה מפורשת מתגלה מאחוריהן רקע החלון הנייטיב (שחור ב-night
            // theme). _EdgeToEdgeShell צובע כל אזור inset בצבע הסרגל הצמוד
            // אליו וקובע את ניגודיות אייקוני המערכת. שורת הסטטוס נצבעת כצבע
            // ה-CustomTitleBar (reader/panel לפי המסך — ראה custom_title_bar)
            // ואזור הניווט התחתון כצבע ה-NavigationBar, כדי שלא ייווצר תפר.
            final hasOpenTabs = context.select(
              (TabsBloc bloc) => bloc.state.hasOpenTabs,
            );
            final useReaderStyle =
                state.currentScreen == Screen.search ||
                (state.currentScreen == Screen.reading && hasOpenTabs);
            final isImmersive = FullscreenHelper.shouldUseImmersiveLayout(
              platform: defaultTargetPlatform,
              isFullscreen: context.select(
                (SettingsBloc b) => b.state.isFullscreen,
              ),
              screen: state.currentScreen,
              hasOpenTabs: hasOpenTabs,
            );
            return _EdgeToEdgeShell(
              topColor: useReaderStyle
                  ? AppSurfaces.readerBackground(context)
                  : AppSurfaces.solidPanelBackground(context),
              bottomColor: AppSurfaces.panelBackground(context),
              child: KeyboardShortcuts(
                onFindRefRequested: () => _handleFindRefOpen(context),
                onNewSearchRequested: () => _handleSearchTabOpen(context),
                child: MyUpdatWidget(
                  child: Scaffold(
                    resizeToAvoidBottomInset: false,
                    body: Stack(
                      children: [
                        Column(
                          children: [
                            if (!isImmersive)
                              CustomTitleBar(
                                onReadingSettingsPressed:
                                    _toggleReadingSettingsPanel,
                                isReadingSettingsPanelOpen:
                                    _isReadingSettingsPanelOpen,
                              ),
                            Expanded(
                              child: OrientationBuilder(
                                builder: (context, orientation) {
                                  _handleOrientationChange(
                                    context,
                                    orientation,
                                  );

                                  final pageView = Stack(
                                    children: [
                                      PageView(
                                        controller: pageController,
                                        scrollDirection:
                                            orientation == Orientation.landscape
                                            ? Axis.vertical
                                            : Axis.horizontal,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        children: _pages,
                                      ),
                                      // צמוד לסרגל הניווט (ימין ב-RTL) ובתוך
                                      // אזור התוכן בלבד — כך ה-scrim אינו בולע
                                      // לחיצות בסרגל וכפתור "כלים" נשאר לחיץ
                                      // לסגירה.
                                      ContextOverlayPanel(
                                        isOpen: _isToolsLauncherOpen,
                                        onClose: _closeToolsLauncher,
                                        alignment:
                                            AlignmentDirectional.centerStart,
                                        width: 400,
                                        deferChildBuildOnOpen: true,
                                        child: ToolsLauncherPanel(
                                          onClose: _closeToolsLauncher,
                                          onToolSelected: (entry) {
                                            _closeToolsLauncher();
                                            openToolTab(context, entry);
                                          },
                                        ),
                                      ),
                                    ],
                                  );

                                  if (orientation == Orientation.landscape) {
                                    final isCompactRail = context
                                        .select<SettingsBloc, bool>(
                                          (b) => b.state.compactMenuMode,
                                        );
                                    final railWidth = isCompactRail
                                        ? NavRailItem.compactWidth
                                        : NavRailItem.width;
                                    return Row(
                                      children: [
                                        if (!isImmersive)
                                          ColoredBox(
                                            color: AppSurfaces.panelBackground(
                                              context,
                                            ),
                                            child: SizedBox.fromSize(
                                              size: Size.fromWidth(railWidth),
                                              child: Column(
                                                children: [
                                                  Expanded(
                                                    child: Material(
                                                      color:
                                                          AppSurfaces.panelBackground(
                                                            context,
                                                          ),
                                                      surfaceTintColor:
                                                          Colors.transparent,
                                                      child:
                                                          BlocBuilder<
                                                            PluginSystemBloc,
                                                            PluginSystemState
                                                          >(
                                                            buildWhen:
                                                                _pinnedNavRailIdsChanged,
                                                            builder:
                                                                (
                                                                  context,
                                                                  pluginState,
                                                                ) {
                                                                  final settingsState =
                                                                      context.select<
                                                                        SettingsBloc,
                                                                        SettingsState
                                                                      >(
                                                                        (b) => b
                                                                            .state,
                                                                      );
                                                                  final pinnedItems = _resolvePinnedItems(
                                                                    pluginState:
                                                                        pluginState,
                                                                    pinnedBuiltInIds:
                                                                        settingsState
                                                                            .builtInToolsPinnedToNavRail,
                                                                    hiddenBuiltInIds:
                                                                        settingsState
                                                                            .hiddenBuiltInToolIds,
                                                                    isOfflineMode:
                                                                        settingsState
                                                                            .isOfflineMode,
                                                                  );
                                                                  return BlocBuilder<
                                                                    TabsBloc,
                                                                    TabsState
                                                                  >(
                                                                    buildWhen: (p, c) =>
                                                                        _activeToolIdOf(
                                                                          p,
                                                                        ) !=
                                                                        _activeToolIdOf(
                                                                          c,
                                                                        ),
                                                                    builder:
                                                                        (
                                                                          context,
                                                                          tabsState,
                                                                        ) {
                                                                          final activeToolId = _activeToolIdOf(
                                                                            tabsState,
                                                                          );
                                                                          final hideTools = _isAllToolsHidden(
                                                                            settingsState,
                                                                            pluginState,
                                                                          );
                                                                          final isReaderScreen =
                                                                              state.currentScreen ==
                                                                                  Screen.reading ||
                                                                              state.currentScreen ==
                                                                                  Screen.search;
                                                                          final activePinnedIndex =
                                                                              isReaderScreen &&
                                                                                  activeToolId !=
                                                                                      null
                                                                              ? pinnedItems.indexWhere(
                                                                                  (
                                                                                    it,
                                                                                  ) =>
                                                                                      it.toolId ==
                                                                                      activeToolId,
                                                                                )
                                                                              : -1;
                                                                          // "כלים" מודגש כל עוד פאנל המשגר פתוח
                                                                          final isToolsSelected =
                                                                              !hideTools &&
                                                                              _isToolsLauncherOpen;
                                                                          return LayoutBuilder(
                                                                            builder:
                                                                                (
                                                                                  context,
                                                                                  constraints,
                                                                                ) {
                                                                                  const buttonHeight = 60.0;
                                                                                  const minSpacerHeight = 20.0;
                                                                                  final totalItems =
                                                                                      (_navData.length -
                                                                                          (hideTools
                                                                                              ? 1
                                                                                              : 0)) +
                                                                                      pinnedItems.length;
                                                                                  final needsScroll =
                                                                                      totalItems *
                                                                                              buttonHeight +
                                                                                          minSpacerHeight >
                                                                                      constraints.maxHeight;

                                                                                  final topItems =
                                                                                      <
                                                                                        Widget
                                                                                      >[
                                                                                        for (
                                                                                          int i = 0;
                                                                                          i <
                                                                                              _toolsNavIndex;
                                                                                          i++
                                                                                        )
                                                                                          _buildNavRailItem(
                                                                                            context,
                                                                                            i,
                                                                                            state.currentScreen,
                                                                                            compact: isCompactRail,
                                                                                          ),
                                                                                        if (!hideTools)
                                                                                          _buildNavRailItem(
                                                                                            context,
                                                                                            _toolsNavIndex,
                                                                                            state.currentScreen,
                                                                                            selectedOverride: isToolsSelected,
                                                                                            compact: isCompactRail,
                                                                                          ),
                                                                                        for (
                                                                                          int i = 0;
                                                                                          i <
                                                                                              pinnedItems.length;
                                                                                          i++
                                                                                        )
                                                                                          _buildPinnedItemNavRailItem(
                                                                                            context,
                                                                                            pinnedItems[i],
                                                                                            isSelected:
                                                                                                activePinnedIndex ==
                                                                                                i,
                                                                                            compact: isCompactRail,
                                                                                          ),
                                                                                      ];
                                                                                  final settingsItem = _buildNavRailItem(
                                                                                    context,
                                                                                    _settingsNavIndex,
                                                                                    state.currentScreen,
                                                                                    compact: isCompactRail,
                                                                                  );

                                                                                  if (needsScroll) {
                                                                                    return SingleChildScrollView(
                                                                                      child: Column(
                                                                                        children: [
                                                                                          ...topItems,
                                                                                          settingsItem,
                                                                                        ],
                                                                                      ),
                                                                                    );
                                                                                  }

                                                                                  return Column(
                                                                                    children: [
                                                                                      ...topItems,
                                                                                      const Spacer(),
                                                                                      settingsItem,
                                                                                    ],
                                                                                  );
                                                                                },
                                                                          );
                                                                        },
                                                                  );
                                                                },
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        if (!isImmersive)
                                          const VerticalDivider(
                                            thickness: 1,
                                            width: 1,
                                          ),
                                        Expanded(child: pageView),
                                      ],
                                    );
                                  } else {
                                    return Column(
                                      children: [
                                        Expanded(child: pageView),
                                        if (!isImmersive)
                                          BlocBuilder<
                                            PluginSystemBloc,
                                            PluginSystemState
                                          >(
                                            buildWhen: _pinnedNavRailIdsChanged,
                                            builder: (context, pluginState) {
                                              final settingsState = context
                                                  .select<
                                                    SettingsBloc,
                                                    SettingsState
                                                  >((b) => b.state);
                                              final pinnedItems = _resolvePinnedItems(
                                                pluginState: pluginState,
                                                pinnedBuiltInIds: settingsState
                                                    .builtInToolsPinnedToNavRail,
                                                hiddenBuiltInIds: settingsState
                                                    .hiddenBuiltInToolIds,
                                                isOfflineMode:
                                                    settingsState.isOfflineMode,
                                              );
                                              final hideTools =
                                                  _isAllToolsHidden(
                                                    settingsState,
                                                    pluginState,
                                                  );
                                              return BlocBuilder<
                                                TabsBloc,
                                                TabsState
                                              >(
                                                buildWhen: (p, c) =>
                                                    _activeToolIdOf(p) !=
                                                    _activeToolIdOf(c),
                                                builder: (context, tabsState) {
                                                  final activeToolId =
                                                      _activeToolIdOf(
                                                        tabsState,
                                                      );
                                                  return NavigationBar(
                                                    backgroundColor:
                                                        AppSurfaces.panelBackground(
                                                          context,
                                                        ),
                                                    surfaceTintColor:
                                                        Colors.transparent,
                                                    destinations:
                                                        _buildBarDestinations(
                                                          pinnedItems,
                                                          hideTools: hideTools,
                                                        ),
                                                    selectedIndex:
                                                        _getBarSelectedIndex(
                                                          state.currentScreen,
                                                          pinnedItems,
                                                          activeToolId,
                                                          hideTools: hideTools,
                                                        ),
                                                    onDestinationSelected:
                                                        (index) async {
                                                          await _onBarNavTap(
                                                            context,
                                                            index,
                                                            state.currentScreen,
                                                            pinnedItems,
                                                            hideTools:
                                                                hideTools,
                                                          );
                                                        },
                                                  );
                                                },
                                              );
                                            },
                                          ),
                                      ],
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const WorkStatusOverlay(),
                        // host נסתר לתוספים שביקשו לרוץ ברקע עם עליית
                        // האפליקציה. הוא חי כל זמן שה-MainWindowScreen קיים,
                        // ולא תלוי במסך "כלים".
                        const PluginBackgroundHost(),
                        ContextOverlayPanel(
                          isOpen:
                              _isReadingSettingsPanelOpen &&
                              (state.currentScreen == Screen.reading ||
                                  state.currentScreen == Screen.search),
                          onClose: _toggleReadingSettingsPanel,
                          deferChildBuildOnOpen: true,
                          preserveChildStateOnClose: true,
                          width: 400,
                          title: 'הגדרות תצוגת הספרים',
                          child: const Expanded(child: ReadingSettingsPanel()),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    // עוטפים את התוכן ב-Opacity: כל עוד הספר הפעיל לא נטען, התוכן נבנה ונטען
    // ברקע אך אינו נראה (opacity 0). כשהתוכן מוכן — _revealMainWindowOnce מסיר
    // את האוברליי וחושף את החלון.
    return Stack(
      children: [
        Opacity(
          opacity: _initialContentReady ? 1.0 : 0.0,
          child: IgnorePointer(ignoring: !_initialContentReady, child: content),
        ),
        if (_splashOverlayVisible)
          const Positioned.fill(child: _StartupSplashOverlay()),
      ],
    );
  }

  void _openIndexingSettings() {
    _settingsScreenController.openTab(SettingsTab.library);
    context.read<NavigationBloc>().add(const NavigateToScreen(Screen.settings));
  }

  int? _pageIndexForScreen(Screen screen) {
    switch (screen) {
      case Screen.library:
        return 0;
      case Screen.reading:
      case Screen.search:
        return 1;
      case Screen.settings:
        return 2;
      case Screen.find:
        return null;
    }
  }

  /// סוגר כל דיאלוג/תפריט פתוח מעל מסך הבית, כדי שחלוניות לא ייערמו זו על זו.
  void _closeRootOverlayRoutes(BuildContext context) {
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
  }

  void _handleSearchTabOpen(BuildContext context, {bool closeIfOpen = true}) {
    if (_isSearchOpen) {
      if (closeIfOpen) {
        Navigator.of(context).pop();
      }
      return;
    }

    _closeRootOverlayRoutes(context);
    final navigationBloc = context.read<NavigationBloc>();
    setState(() => _isSearchOpen = true);

    showDialog(
      context: context,
      builder: (context) => const SearchDialog(existingTab: null),
    ).then((_) {
      if (!mounted) return;
      setState(() => _isSearchOpen = false);
      // Restore focus to the screen below (dialog restorer was already removed
      // by SearchDialog.dispose → unregisterActiveRestorer)
      FocusRepository().scheduleRestore();
      final currentScreen = navigationBloc.state.currentScreen;
      if (currentScreen == Screen.reading || currentScreen == Screen.search) {
        _syncPageWithState();
      }
    });
  }

  void _handleFindRefOpen(BuildContext context, {bool closeIfOpen = true}) {
    if (_isFindRefOpen) {
      if (closeIfOpen) {
        Navigator.of(context).pop();
      }
      return;
    }

    _closeRootOverlayRoutes(context);
    final navigationBloc = context.read<NavigationBloc>();
    setState(() => _isFindRefOpen = true);

    showDialog(
      context: context,
      useRootNavigator: true,
      barrierColor: Colors.transparent,
      builder: (context) => FindRefDialog(),
    ).then((_) {
      if (!mounted) return;
      setState(() => _isFindRefOpen = false);
      // Restore focus to the screen below (dialog restorer was already removed
      // by FindRefDialog.dispose → unregisterActiveRestorer)
      FocusRepository().scheduleRestore();
      final currentScreen = navigationBloc.state.currentScreen;
      if (currentScreen == Screen.reading || currentScreen == Screen.search) {
        _syncPageWithState();
      }
    });
  }

  int _getSelectedIndex(Screen currentScreen) {
    // מיפוי מחדש של האינדקסים כיון שהסרנו את דף האיתור
    switch (currentScreen) {
      case Screen.library:
        return 0;
      case Screen.find:
        return -1; // לא נבחר
      case Screen.reading:
        return 2;
      case Screen.search:
        return 3;
      case Screen.settings:
        return 5;
    }
  }

  int _getActiveNavigationIndex(Screen currentScreen) {
    if (_isFindRefOpen) {
      return 1;
    }
    if (_isSearchOpen) {
      return 3;
    }
    // "כלים" אינו מסך; הוא מודגש כל עוד פאנל המשגר פתוח.
    if (_isToolsLauncherOpen) {
      return _toolsNavIndex;
    }
    return _getSelectedIndex(currentScreen);
  }

  /// אינדקס נבחר ב-NavigationBar בפורטרט. תוספים מוצמדים-לסרגל מוזרקים
  /// בין "כלים" ל"הגדרות", ולכן אינדקס "הגדרות" זז ל-`_settingsNavIndex + N`.
  /// אם המשתמש על מסך הכלים ובחר לשונית של תוסף-מוצמד-לסרגל, מודגש
  /// פריט התוסף ולא "כלים".
  int _getBarSelectedIndex(
    Screen currentScreen,
    List<_PinnedToolNavItem> pinnedItems,
    String? activeToolId, {
    required bool hideTools,
  }) {
    final effectiveSettingsIdx = _effectiveSettingsNavIndex(hideTools);
    if (_isFindRefOpen) return 1;
    if (_isSearchOpen) return 3;
    if (_isToolsLauncherOpen && !hideTools) return _toolsNavIndex;
    switch (currentScreen) {
      case Screen.library:
        return 0;
      case Screen.find:
        return -1;
      case Screen.reading:
      case Screen.search:
        // כלי פעיל בעיון מדגיש את הפריט המוצמד שלו, אם הוצמד לסרגל.
        if (activeToolId != null) {
          final idx = pinnedItems.indexWhere(
            (item) => item.toolId == activeToolId,
          );
          // הפריטים יושבים ישירות אחרי "כלים", ולכן position = settingsIndex + idx
          if (idx >= 0) return _effectiveSettingsNavIndex(hideTools) + idx;
        }
        return currentScreen == Screen.search ? 3 : 2;
      case Screen.settings:
        return effectiveSettingsIdx + pinnedItems.length;
    }
  }

  Future<void> _onBarNavTap(
    BuildContext context,
    int index,
    Screen currentScreen,
    List<_PinnedToolNavItem> pinnedItems, {
    required bool hideTools,
  }) async {
    final effectiveSettingsIdx = _effectiveSettingsNavIndex(hideTools);
    if (index < effectiveSettingsIdx) {
      await _onNavTap(context, index, currentScreen);
      return;
    }
    final pinnedEnd = effectiveSettingsIdx + pinnedItems.length;
    if (index < pinnedEnd) {
      openToolTabById(
        context,
        pinnedItems[index - effectiveSettingsIdx].toolId,
      );
      return;
    }
    // האחרון — "הגדרות" שמופה ל-_navData[_settingsNavIndex]
    await _onNavTap(context, _settingsNavIndex, currentScreen);
  }

  Future<void> _onNavTap(
    BuildContext context,
    int index,
    Screen currentScreen,
  ) async {
    final item = _navData[index];
    // "כלים" אינו מסך אלא טוגל של פאנל; הבדיקה קודמת ל-currentIndex, שלעולם
    // אינו שווה לאינדקס שלו.
    final screen = item.screen;
    if (screen == null) {
      _toggleToolsLauncher();
      return;
    }

    final currentIndex = _getSelectedIndex(currentScreen);
    if (index == currentIndex &&
        screen != Screen.search &&
        screen != Screen.find) {
      await _syncPageWithState();
      return;
    }

    if (screen == Screen.search) {
      _handleSearchTabOpen(context);
    } else if (screen == Screen.find) {
      _handleFindRefOpen(context);
    } else {
      context.read<NavigationBloc>().add(
        NavigateToScreen(screen),
      );
    }

    if (screen == Screen.library) {
      context.read<FocusRepository>().requestLibrarySearchFocus(
        selectAll: true,
      );
    }
  }

  Widget _buildNavRailItem(
    BuildContext context,
    int index,
    Screen currentScreen, {
    bool? selectedOverride,
    bool compact = false,
  }) {
    final item = _navData[index];
    final isSelected =
        selectedOverride ?? (_getActiveNavigationIndex(currentScreen) == index);
    final tooltip = (ShortcutValidator.getShortcutValue(item.shortcutKey) ?? '')
        .toUpperCase();

    final step = _tourCubit.state.currentStep;
    final isTourHighlighted = _isTourNavigationItemHighlighted(
      step,
      index,
      currentScreen,
    );
    return NavRailItem(
      icon: item.icon,
      iconFilled: item.iconFilled,
      label: context.settingsText(item.label),
      isSelected: isSelected,
      onTap: () => _onNavTap(context, index, currentScreen),
      tooltip: tooltip,
      tourTargetKey: tourMainNavigationTargetKeys[index],
      tourItemKey: tourMainNavigationItemTargetKeys[index],
      isTourHighlighted: isTourHighlighted,
      compact: compact,
    );
  }

  Widget _buildPinnedItemNavRailItem(
    BuildContext context,
    _PinnedToolNavItem item, {
    bool isSelected = false,
    bool compact = false,
  }) {
    return NavRailItem(
      icon: item.icon,
      iconFilled: item.icon,
      imageAsset: item.imageAsset,
      label: item.label,
      isSelected: isSelected,
      onTap: () => openToolTabById(context, item.toolId),
      compact: compact,
    );
  }

  bool _isTourNavigationItemHighlighted(
    TourStep? step,
    int index,
    Screen currentScreen,
  ) {
    if (step == null) {
      return false;
    }
    if (step.area == TourSpotlightArea.navigation &&
        index == _getActiveNavigationIndex(currentScreen)) {
      return true;
    }

    if (step.id == 'tools') return index == _toolsNavIndex;
    final targetScreen = _tourNavigationScreenForStep(step);
    return targetScreen != null && _navData[index].screen == targetScreen;
  }

  Screen? _tourNavigationScreenForStep(TourStep step) {
    return switch (step.id) {
      'find_ref' => Screen.find,
      'advanced_search' => Screen.search,
      'settings' => Screen.settings,
      'library' => Screen.library,
      _ => null,
    };
  }
}

/// מסך הפתיחה בזמן עליית התוכנה (החלון מוסתר עד החשיפה): מוצג עד שתוכן הטאב
/// הפעיל נטען. הרקע אטום בכוונה — סצנה שקופה מייצרת פריימים ריקים, ופריים ריק
/// בזמן resize משכלף את ה-surface בגלל באג מנוע (flutter#187922).
class _StartupSplashOverlay extends StatelessWidget {
  const _StartupSplashOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: const SplashIcon(),
    );
  }
}

class KeepAlivePage extends StatefulWidget {
  final Widget child;

  const KeepAlivePage({super.key, required this.child});

  @override
  State<KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// עוטף את ה-UI הראשי לטיפול ב-edge-to-edge שנכפה ב-Android 15+ (targetSdk 35+):
/// קובע את ניגודיות אייקוני המערכת לפי בהירות ערכת הנושא, וצובע את האזורים
/// שמאחורי פסי המערכת (שורת הסטטוס למעלה, סרגל הניווט למטה/בצדדים) בצבע הסרגל
/// הצמוד אליהם — [topColor] לשורת הסטטוס ו-[bottomColor] לשאר — כדי שלא ייחשף
/// רקע החלון הנייטיב ולא ייווצר תפר ויזואלי עם הסרגלים שבתוך האפליקציה.
class _EdgeToEdgeShell extends StatelessWidget {
  const _EdgeToEdgeShell({
    required this.topColor,
    required this.bottomColor,
    required this.child,
  });

  final Color topColor;
  final Color bottomColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconBrightness = isDark ? Brightness.light : Brightness.dark;
    final topInset = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: iconBrightness,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: iconBrightness,
      ),
      child: ColoredBox(
        color: bottomColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // אזור שורת הסטטוס נצבע ידנית (SafeArea למטה מבטל את ה-top שלו) כדי
            // שצבעו יוכל להתאים ל-CustomTitleBar שמתחתיו ולא ל-bottomColor.
            SizedBox(
              height: topInset,
              child: ColoredBox(color: topColor),
            ),
            Expanded(child: SafeArea(top: false, child: child)),
          ],
        ),
      ),
    );
  }
}
