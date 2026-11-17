import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:otzaria/core/windowing/window_opener.dart';
import 'package:otzaria/core/windowing/window_fullscreen_cubit.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/navigation/view/tab_search_menu.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/navigation/view/tab_context_menu.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tools/tools_launcher_controller.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/bookmarks/view/bookmark_screen.dart';
import 'package:otzaria/bookmarks/view/save_group_bookmark_dialog.dart';
import 'package:otzaria/history/view/history_screen.dart';
import 'package:otzaria/workspaces/view/workspace_switcher_dialog.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut_dispatcher.dart';
import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut_registry.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/utils/ui/fullscreen_helper.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';

class KeyboardShortcuts extends StatefulWidget {
  final Widget child;
  final VoidCallback onFindRefRequested;

  /// פתיחת/סגירת דיאלוג חיפוש חדש דרך MainWindowScreen (מעקב `_isSearchOpen`).
  final VoidCallback? onNewSearchRequested;

  const KeyboardShortcuts({
    super.key,
    required this.child,
    required this.onFindRefRequested,
    this.onNewSearchRequested,
  });

  @override
  State<KeyboardShortcuts> createState() => _KeyboardShortcutsState();
}

class _KeyboardShortcutsState extends State<KeyboardShortcuts> {
  late final FocusScopeNode _shortcutFocusScopeNode;

  /// המקש שהפעיל קיצור דינמי; החזרות שלו (מקש מוחזק) לא יגיעו לטיפול המובנה.
  PhysicalKeyboardKey? _dynamicKey;

  @override
  void initState() {
    super.initState();
    _shortcutFocusScopeNode = FocusScopeNode(
      debugLabel: 'global_keyboard_shortcuts',
      skipTraversal: true,
    );
    // late handler רץ אחרי עץ הפוקוס כולו ורק אם האירוע לא טופל, ולכן הקיצורים
    // פועלים גם כשדיאלוג (route נפרד ב-Overlay) מחזיק את הפוקוס.
    FocusManager.instance.addLateKeyEventHandler(_handleLateKeyEvent);
    // קיצור דינמי קודם לעץ: אחרת טיפול מובנה (Ctrl+C על בחירה) בולע אותו.
    FocusManager.instance.addEarlyKeyEventHandler(_handleEarlyKeyEvent);
  }

  @override
  void dispose() {
    FocusManager.instance.removeLateKeyEventHandler(_handleLateKeyEvent);
    FocusManager.instance.removeEarlyKeyEventHandler(_handleEarlyKeyEvent);
    _shortcutFocusScopeNode.dispose();
    super.dispose();
  }

  /// FocusManager אחד לכל החלונות ב-isolate: כל מקש מגיע ל-handlers של כולם,
  /// ולכן רק החלון הפעיל מבצע קיצורים.
  bool get _isActiveWindow => mounted && AppWindowKeys.isActiveWindow(context);

  KeyEventResult _handleLateKeyEvent(KeyEvent event) {
    if (!_isActiveWindow) return KeyEventResult.ignored;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final route = focusContext == null ? null : ModalRoute.of(focusContext);
    if (route != null &&
        !route.isFirst &&
        route.popDisposition == RoutePopDisposition.doNotPop) {
      // תו שמסומן handled לא נכנס לשדה ב-Windows; חוסמים רק קיצורים.
      return ShortcutHelper.shouldIgnoreWhileEditing(event) ||
              _typesCharacterWithModifiers(event) ||
              _isMacControlEditingEvent(event)
          ? KeyEventResult.ignored
          : KeyEventResult.handled;
    }
    return _handleKeyEvent(event, context.read<SettingsBloc>().state.shortcuts);
  }

  /// AltGr (Ctrl+Alt ב-Windows) או Option במק שמייצרים תו לשדה, כמו ₪ או ניקוד.
  static bool _typesCharacterWithModifiers(KeyEvent event) =>
      event.character != null &&
      ShortcutHelper.isEditingText &&
      !ShortcutHelper.isPlainCtrlOrCmdPressed &&
      !HardwareKeyboard.instance.isMetaPressed;

  // Cocoa מממש Ctrl+D/H רק אחרי שה-framework מחזיר ignored.
  static bool _isMacControlEditingEvent(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    return ShortcutHelper.usesMacModifiers &&
        ShortcutHelper.isEditingText &&
        keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed &&
        (event.logicalKey == LogicalKeyboardKey.keyD ||
            event.logicalKey == LogicalKeyboardKey.keyH);
  }

  /// בעריכת טקסט השדה קודם, והקיצור הדינמי נבדק רק ב-late handler.
  KeyEventResult _handleEarlyKeyEvent(KeyEvent event) {
    if (!_isActiveWindow) return KeyEventResult.ignored;
    if (event is KeyRepeatEvent && event.physicalKey == _dynamicKey) {
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final result = ShortcutHelper.isEditingText
        ? null
        : _handleDynamicShortcut(event);
    _dynamicKey = result == KeyEventResult.handled ? event.physicalKey : null;
    return result ?? KeyEventResult.ignored;
  }

  /// קיצור דינמי של המשתמש על כרטיסיית טקסט במסך העיון; null — לא חל כאן.
  KeyEventResult? _handleDynamicShortcut(KeyEvent event) {
    final shortcut = DynamicShortcutRegistry.instance.match(event);
    if (shortcut == null || !_isReadingScreen) return null;
    final tab = context.read<TabsBloc>().state.currentTab;
    if (tab is! TextBookTab) return null;
    return DynamicShortcutDispatcher.run(shortcut, tab)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  /// מסך העיון או החיפוש (אותו עמוד טאבים), בלי דיאלוג/תפריט פתוח מעליו.
  bool get _isReadingScreen {
    final screen = context.read<NavigationBloc>().state.currentScreen;
    return !(Navigator.maybeOf(context, rootNavigator: true)?.canPop() ??
            false) &&
        (screen == Screen.reading || screen == Screen.search);
  }

  /// ממפה מקש ספרה (שורת המספרים או הספרון) ל-1..9. מחזיר null לכל מקש אחר.
  /// אפס לא נכלל בכוונה — Ctrl+0 שמור לאיפוס גודל טקסט.
  static int? _tabDigitForKey(LogicalKeyboardKey key) =>
      _tabDigitKeys[key.keyId];

  // ממופה לפי keyId (פרימיטיב) כי LogicalKeyboardKey דורס את == ולא יכול
  // לשמש מפתח במפת const.
  static final Map<int, int> _tabDigitKeys = {
    LogicalKeyboardKey.digit1.keyId: 1,
    LogicalKeyboardKey.digit2.keyId: 2,
    LogicalKeyboardKey.digit3.keyId: 3,
    LogicalKeyboardKey.digit4.keyId: 4,
    LogicalKeyboardKey.digit5.keyId: 5,
    LogicalKeyboardKey.digit6.keyId: 6,
    LogicalKeyboardKey.digit7.keyId: 7,
    LogicalKeyboardKey.digit8.keyId: 8,
    LogicalKeyboardKey.digit9.keyId: 9,
    LogicalKeyboardKey.numpad1.keyId: 1,
    LogicalKeyboardKey.numpad2.keyId: 2,
    LogicalKeyboardKey.numpad3.keyId: 3,
    LogicalKeyboardKey.numpad4.keyId: 4,
    LogicalKeyboardKey.numpad5.keyId: 5,
    LogicalKeyboardKey.numpad6.keyId: 6,
    LogicalKeyboardKey.numpad7.keyId: 7,
    LogicalKeyboardKey.numpad8.keyId: 8,
    LogicalKeyboardKey.numpad9.keyId: 9,
  };

  /// מטפל באירועי מקלדת ברמה הגלובלית - עובד גם כשיש TextField עם focus
  KeyEventResult _handleKeyEvent(
    KeyEvent event,
    Map<String, String> shortcutSettings,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (ShortcutHelper.shouldIgnoreWhileEditing(event)) {
      return KeyEventResult.ignored;
    }

    // קריאת ערכי הקיצורים מההגדרות. ברירת המחדל נלקחת מהמקור הקנוני היחיד
    // (`ShortcutValidator.defaultShortcuts`) ולא משוכפלת כאן.
    String shortcutOf(String key) =>
        shortcutSettings[key] ?? ShortcutValidator.defaultShortcuts[key] ?? '';

    final libraryShortcut = shortcutOf('key-shortcut-open-library-browser');
    final findRefShortcut = shortcutOf('key-shortcut-open-find-ref');
    final closeTabShortcut = shortcutOf('key-shortcut-close-tab');
    final closeAllTabsShortcut = shortcutOf('key-shortcut-close-all-tabs');
    final restoreClosedTabShortcut = shortcutOf(
      'key-shortcut-restore-closed-tab',
    );
    final searchTabsShortcut = shortcutOf('key-shortcut-search-tabs');
    final readingScreenShortcut = shortcutOf(
      'key-shortcut-open-reading-screen',
    );
    final newSearchShortcut = shortcutOf('key-shortcut-open-new-search');
    final advancedSearchShortcut = shortcutOf(
      ShortcutValidator.openAdvancedSearchKey,
    );
    final settingsShortcut = shortcutOf('key-shortcut-open-settings');
    final moreShortcut = shortcutOf('key-shortcut-open-more');
    final bookmarksShortcut = shortcutOf('key-shortcut-open-bookmarks');
    final historyShortcut = shortcutOf('key-shortcut-open-history');
    final workspaceShortcut = shortcutOf('key-shortcut-switch-workspace');
    final newWindowShortcut = shortcutOf(ShortcutValidator.openNewWindowKey);
    final toggleNavPaneShortcut = shortcutOf('key-shortcut-toggle-nav-pane');
    final toggleCommentatorsPaneShortcut = shortcutOf(
      'key-shortcut-toggle-commentators-pane',
    );
    final openCommentatorsTabShortcut = shortcutOf(
      'key-shortcut-open-commentators-tab',
    );
    final togglePdfViewShortcut = shortcutOf('key-shortcut-toggle-pdf-view');
    final prevSegmentShortcut = shortcutOf('key-shortcut-prev-segment');
    final nextSegmentShortcut = shortcutOf('key-shortcut-next-segment');
    final prevTocShortcut = shortcutOf('key-shortcut-prev-toc');
    final nextTocShortcut = shortcutOf('key-shortcut-next-toc');

    // דיאלוג/תפריט פתוח = route מעל מסך הבית ב-root Navigator. קיצורי ניווט
    // סוגרים אותו לפני המעבר; קיצורי טאבים מנוטרלים כדי לא לפעול על מסך שברקע.
    final rootNavigator = Navigator.maybeOf(context, rootNavigator: true);
    bool closeOverlayRoutes() {
      var blocked = false;
      if (rootNavigator?.canPop() ?? false) {
        rootNavigator!.popUntil((route) {
          blocked =
              !route.isFirst &&
              route.popDisposition == RoutePopDisposition.doNotPop;
          return route.isFirst || blocked;
        });
      }
      return !blocked;
    }

    final isReadingScreen = _isReadingScreen;

    if (isReadingScreen &&
        context.read<TabsBloc>().state.currentTab is PdfBookTab) {
      for (final entry in ShortcutValidator.pluginShortcuts.entries) {
        final target = entry.value;
        final shortcut = ShortcutValidator.getShortcutValue(entry.key) ?? '';
        if (target.contextMenuItemId == null &&
            target.command != null &&
            shortcut.isNotEmpty &&
            ShortcutHelper.matchesShortcut(event, shortcut)) {
          unawaited(
            PluginRuntimeDispatcher.instance.dispatchEventToPlugin(
              target.pluginId,
              'app.command',
              {'command': target.command, 'shortcutId': target.shortcutId},
              preferBackground: true,
              viewId: View.of(context).viewId,
              windowKeys: AppWindowKeys.of(context),
            ),
          );
          return KeyEventResult.handled;
        }
      }
    }

    // פתח/סגור חלונית ניווט. אם הטאב הפעיל אינו ספר — מחזירים `ignored`
    // כדי לא לבלוע את הקיצור (כך מנוע ה-shortcut יכול להמשיך הלאה במקום
    // להציג למשתמש "כלום קרה" שקטה).
    if (isReadingScreen &&
        ShortcutHelper.matchesShortcut(event, toggleNavPaneShortcut)) {
      final tab = context.read<TabsBloc>().state.currentTab;
      if (tab is TextBookTab) {
        final state = tab.bloc.state;
        if (state is TextBookLoaded) {
          tab.bloc.add(ToggleLeftPane(!state.showLeftPane));
        }
        return KeyEventResult.handled;
      }
      if (tab is PdfBookTab) {
        tab.toggleNavPaneNotifier.value++;
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // פתח/סגור חלונית מפרשים — פועל גם ב-TextBookTab וגם ב-PdfBookTab
    // (תיקון לבאג שב-PR המקורי שבלע את האירוע ב-PDF בלי השפעה).
    if (isReadingScreen &&
        ShortcutHelper.matchesShortcut(event, toggleCommentatorsPaneShortcut)) {
      final tab = context.read<TabsBloc>().state.currentTab;
      if (tab is TextBookTab) {
        tab.toggleCommentatorsPaneNotifier.value++;
        return KeyEventResult.handled;
      }
      if (tab is PdfBookTab) {
        tab.toggleCommentatorsPaneNotifier.value++;
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // החלפת מצב תצוגה PDF→טקסט. הכיוון ההפוך מטופל במסך ספר הטקסט עצמו,
    // שה-KeyboardListener שלו עוטף את כל המסך.
    if (isReadingScreen &&
        togglePdfViewShortcut.isNotEmpty &&
        ShortcutHelper.matchesShortcut(event, togglePdfViewShortcut)) {
      final tab = context.read<TabsBloc>().state.currentTab;
      if (tab is PdfBookTab) {
        tab.toggleTextViewNotifier.value++;
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // פתיחת כרטיסיית מפרשים נפרדת מהטאב הנוכחי
    if (isReadingScreen &&
        openCommentatorsTabShortcut.isNotEmpty &&
        ShortcutHelper.matchesShortcut(event, openCommentatorsTabShortcut)) {
      final tabsBloc = context.read<TabsBloc>();
      final tab = tabsBloc.state.currentTab;
      if (tab is TextBookTab) {
        tabsBloc.add(
          AddTab(CommentatorsTab(sourceTab: tab), insertAdjacent: true),
        );
        return KeyEventResult.handled;
      }
      if (tab is PdfBookTab) {
        tabsBloc.add(
          AddTab(PdfCommentatorsTab.of(tab), insertAdjacent: true),
        );
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // ניווט קטע/דף-פרק בספר טקסט — מגלגל את ה-notifier המתאים בטאב, שהמסך
    // מאזין לו ומבצע בדיוק את אותו ניווט כמו לחיצה על הכפתור. רלוונטי רק
    // ל-TextBookTab; במסכים אחרים מחזירים `ignored` כדי לא לבלוע את הקיצור.
    final navTab = context.read<TabsBloc>().state.currentTab;
    if (isReadingScreen && navTab is TextBookTab) {
      ValueNotifier<int>? navNotifier;
      if (ShortcutHelper.matchesShortcut(event, prevSegmentShortcut)) {
        navNotifier = navTab.navPreviousSegmentNotifier;
      } else if (ShortcutHelper.matchesShortcut(event, nextSegmentShortcut)) {
        navNotifier = navTab.navNextSegmentNotifier;
      } else if (ShortcutHelper.matchesShortcut(event, prevTocShortcut)) {
        navNotifier = navTab.navPreviousTocNotifier;
      } else if (ShortcutHelper.matchesShortcut(event, nextTocShortcut)) {
        navNotifier = navTab.navNextTocNotifier;
      }
      if (navNotifier != null) {
        navNotifier.value++;
        return KeyEventResult.handled;
      }
    }

    if (ShortcutHelper.matchesShortcut(event, libraryShortcut)) {
      if (!closeOverlayRoutes()) return KeyEventResult.handled;
      context.read<NavigationBloc>().add(
        const NavigateToScreen(Screen.library),
      );
      context.read<FocusRepository>().requestLibrarySearchFocus(
        selectAll: true,
      );
      return KeyEventResult.handled;
    }

    // בית הספרייה (אופציונלי, ללא ברירת מחדל) — מעבר לספרייה והפעלת פעולת
    // הבית שלה, כמו לחיצה על כפתור הבית.
    final libraryHomeShortcut = shortcutOf(
      ShortcutValidator.openLibraryHomeKey,
    );
    if (libraryHomeShortcut.isNotEmpty &&
        ShortcutHelper.matchesShortcut(event, libraryHomeShortcut)) {
      if (!closeOverlayRoutes()) return KeyEventResult.handled;
      context.read<NavigationBloc>().add(
        const NavigateToScreen(Screen.library),
      );
      context.read<FocusRepository>().requestLibraryHome();
      return KeyEventResult.handled;
    }

    // איתור
    if (ShortcutHelper.matchesShortcut(event, findRefShortcut)) {
      widget.onFindRefRequested();
      return KeyEventResult.handled;
    }

    // סגור טאב
    if (isReadingScreen &&
        ShortcutHelper.matchesShortcut(event, closeTabShortcut)) {
      final tabsBloc = context.read<TabsBloc>();
      // הקיצור סוגר את כל הבחירה המרובה כשהכרטיסיה הפעילה חלק ממנה.
      final closeGroup = tabsBloc.state.currentCloseGroup;
      // בטאב מפוצל (שאינו חלק מבחירה מרובה) נסגרת רק החלונית הפעילה.
      if (closeGroup.length <= 1 && tabsBloc.state.currentTab is CombinedTab) {
        final pane = tabsBloc.state.activePane;
        if (pane != null) {
          closePaneWithHistory(context, pane);
          return KeyEventResult.handled;
        }
      }
      if (closeGroup.length > 1) {
        closeSelectedTabsWithHistory(context);
      } else if (closeGroup.isNotEmpty) {
        closeTabWithHistory(context, closeGroup.first);
      }
      return KeyEventResult.handled;
    }

    // סגור כל הטאבים
    if (isReadingScreen &&
        ShortcutHelper.matchesShortcut(event, closeAllTabsShortcut)) {
      closeAllTabsWithHistory(context);
      return KeyEventResult.handled;
    }

    // שחזור כרטיסייה או חלון זמין מכל מסך ומחזיר למסך העיון.
    if (ShortcutHelper.matchesShortcut(event, restoreClosedTabShortcut)) {
      // כמו בדפדפן: קודם כרטיסיה שנסגרה, ורק אם אין כזו — חלון שנסגר.
      // הסדר חשוב, כי הכרטיסיה היא הפעולה השכיחה בהרבה.
      final tabsBloc = context.read<TabsBloc>();
      if (tabsBloc.hasRecentlyClosedTabs) {
        tabsBloc.add(const RestoreLastClosedTab());
        if (!isReadingScreen) {
          context.read<NavigationBloc>().add(
            const NavigateToScreen(Screen.reading),
          );
        }
      } else {
        unawaited(WindowOpener.current.restoreLastClosedWindow());
      }
      return KeyEventResult.handled;
    }

    // החלונית עצמה היא route פתוח ולכן isReadingScreen שקרי; הקיצור צריך לסגור אותה.
    if ((isReadingScreen || isTabSearchMenuOnTop(context)) &&
        ShortcutHelper.matchesShortcut(event, searchTabsShortcut)) {
      showTabSearchMenu(context);
      return KeyEventResult.handled;
    }

    // עיון
    if (ShortcutHelper.matchesShortcut(event, readingScreenShortcut)) {
      if (!closeOverlayRoutes()) return KeyEventResult.handled;
      context.read<NavigationBloc>().add(
        const NavigateToScreen(Screen.reading),
      );
      return KeyEventResult.handled;
    }

    // חיפוש חדש
    if (ShortcutHelper.matchesShortcut(event, newSearchShortcut)) {
      final onNewSearch = widget.onNewSearchRequested;
      if (onNewSearch != null) {
        onNewSearch();
      } else {
        if (!closeOverlayRoutes()) return KeyEventResult.handled;
        showDialog(
          context: context,
          builder: (context) => const SearchDialog(existingTab: null),
        );
      }
      return KeyEventResult.handled;
    }

    if (advancedSearchShortcut.isNotEmpty &&
        ShortcutHelper.matchesShortcut(event, advancedSearchShortcut)) {
      showDialog(
        context: context,
        builder: (context) => const SearchDialog(
          existingTab: null,
          initialSearchMode: SearchMode.advanced,
        ),
      );
      return KeyEventResult.handled;
    }

    // הגדרות
    if (ShortcutHelper.matchesShortcut(event, settingsShortcut)) {
      if (!closeOverlayRoutes()) return KeyEventResult.handled;
      context.read<NavigationBloc>().add(
        const NavigateToScreen(Screen.settings),
      );
      return KeyEventResult.handled;
    }

    // כלים
    if (ShortcutHelper.matchesShortcut(event, moreShortcut)) {
      if (!closeOverlayRoutes()) return KeyEventResult.handled;
      ToolsLauncherController.instance.open();
      return KeyEventResult.handled;
    }

    // סימניות
    if (ShortcutHelper.matchesShortcut(event, bookmarksShortcut)) {
      if (!closeOverlayRoutes()) return KeyEventResult.handled;
      showDialog(
        context: context,
        builder: (context) => const BookmarksDialog(),
      );
      return KeyEventResult.handled;
    }

    // סימניה מרוכזת לכל הספרים הפתוחים (אופציונלי, ללא ברירת מחדל)
    final saveGroupBookmarkShortcut = shortcutOf(
      'key-shortcut-save-group-bookmark',
    );
    if (saveGroupBookmarkShortcut.isNotEmpty &&
        ShortcutHelper.matchesShortcut(event, saveGroupBookmarkShortcut)) {
      if (!closeOverlayRoutes()) return KeyEventResult.handled;
      showSaveGroupBookmarkDialog(context);
      return KeyEventResult.handled;
    }

    // היסטוריה
    if (ShortcutHelper.matchesShortcut(event, historyShortcut)) {
      if (!closeOverlayRoutes()) return KeyEventResult.handled;
      showDialog(
        context: context,
        builder: (context) => const HistoryDialog(),
      );
      return KeyEventResult.handled;
    }

    // החלף שולחן עבודה
    if (ShortcutHelper.matchesShortcut(event, workspaceShortcut)) {
      if (!closeOverlayRoutes()) return KeyEventResult.handled;
      showDialog(
        context: context,
        builder: (context) => const WorkspaceSwitcherDialog(),
      );
      return KeyEventResult.handled;
    }

    // חלון אוצריא נוסף — רק בפלטפורמה תומכת, אחרת הקיצור ממשיך הלאה.
    if (RunnerWindowChannel.canOpenWindows &&
        newWindowShortcut.isNotEmpty &&
        ShortcutHelper.matchesShortcut(event, newWindowShortcut)) {
      unawaited(WindowOpener.current.openEmptyWindow());
      return KeyEventResult.handled;
    }

    // פתיחת כלי לפי קיצור אופציונלי (ללא ברירת מחדל) — דרך deep-link פנימי.
    for (final entry in ShortcutValidator.openToolShortcutKeys.entries) {
      final toolShortcut = shortcutOf(entry.key);
      if (toolShortcut.isNotEmpty &&
          ShortcutHelper.matchesShortcut(event, toolShortcut)) {
        if (!closeOverlayRoutes()) return KeyEventResult.handled;
        AppWindowKeys.of(
          context,
        ).mainWindowScreen.currentState?.handleInternalDeepLink(
          'otzaria://open/tool/${entry.value}',
        );
        return KeyEventResult.handled;
      }
    }

    // פתיחת תוסף פעיל לפי קיצור אופציונלי — דרך deep-link `otzaria://open/plugin/<id>`.
    // מסתמכים על המפתחות הרשומים (תוספים פעילים בלבד) ולא על PluginSystemBloc,
    // כדי לא לדרוש Provider בכל אירוע מקש.
    for (final pluginKey in ShortcutValidator.pluginShortcutKeys) {
      final pluginShortcut = shortcutOf(pluginKey);
      if (pluginShortcut.isNotEmpty &&
          ShortcutHelper.matchesShortcut(event, pluginShortcut)) {
        final pluginId = ShortcutValidator.pluginIdFromShortcutKey(pluginKey);
        if (!closeOverlayRoutes()) return KeyEventResult.handled;
        AppWindowKeys.of(
          context,
        ).mainWindowScreen.currentState?.handleInternalDeepLink(
          'otzaria://open/plugin/$pluginId',
        );
        return KeyEventResult.handled;
      }
    }

    // קיצור דינמי בעריכת טקסט (מחוץ לה הוא טופל כבר ב-early handler).
    final dynamicResult = _handleDynamicShortcut(event);
    if (dynamicResult != null) return dynamicResult;

    // Ctrl+Tab / Ctrl+Shift+Tab - מעבר בין טאבים.
    // לא משתמשים ב-matchesShortcut כדי לא להפוך ל-Cmd ב-Mac: Cmd+Tab
    // שמור למערכת ההפעלה, ולכן ב-Mac נשארים עם Ctrl פיזי (זמין שם).
    if (isReadingScreen &&
        event.logicalKey == LogicalKeyboardKey.tab &&
        HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isMetaPressed) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        context.read<TabsBloc>().add(NavigateToPreviousTab());
      } else {
        context.read<TabsBloc>().add(NavigateToNextTab());
      }
      return KeyEventResult.handled;
    }

    // Ctrl+1..9 - מעבר ישיר לטאב לפי מיקומו, כמו בדפדפן: 1-8 לטאבים הראשונים
    // ו-9 תמיד לטאב האחרון. נבדק אחרי כל קיצורי matchesShortcut כדי שקיצור
    // מותאם-אישית שהמשתמש שייך ל-Ctrl+ספרה יקבל קדימות. ללא matchesShortcut
    // (כמו Ctrl+Tab) כדי לא להפוך ל-Cmd ב-Mac.
    if (isReadingScreen &&
        HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isShiftPressed &&
        !HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isMetaPressed) {
      final digit = _tabDigitForKey(event.logicalKey);
      if (digit != null) {
        final tabsBloc = context.read<TabsBloc>();
        final tabCount = tabsBloc.state.tabs.length;
        if (tabCount > 0) {
          final targetIndex = digit == 9 ? tabCount - 1 : digit - 1;
          if (targetIndex < tabCount) {
            tabsBloc.add(SetCurrentTab(targetIndex));
          }
          return KeyEventResult.handled;
        }
      }
    }

    // F11 - מסך מלא (רק בעיון/כלים)
    if (ShortcutHelper.matchesShortcut(event, 'f11')) {
      if (!FullscreenHelper.isAllowedInContext(context)) {
        return KeyEventResult.ignored;
      }
      final newFullscreenState = !context.read<WindowFullscreenCubit>().state;
      FullscreenHelper.toggleFullscreen(context, newFullscreenState);
      return KeyEventResult.handled;
    }

    // ESC - יציאה ממסך מלא
    if (ShortcutHelper.matchesShortcut(event, 'escape')) {
      if (context.read<WindowFullscreenCubit>().state) {
        FullscreenHelper.toggleFullscreen(context, false);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // הטיפול בקיצורים רשום כ-late handler גלובלי (initState); ה-scope נשמר
    // כדי שתמיד יהיה יעד פוקוס שממנו אירועי מקלדת נכנסים לעץ.
    return FocusScope(
      node: _shortcutFocusScopeNode,
      autofocus: true,
      child: widget.child,
    );
  }
}
