import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/find_ref/find_ref_dialog.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/bookmarks/bookmarks_dialog.dart';
import 'package:otzaria/history/history_dialog.dart';
import 'package:otzaria/workspaces/view/workspace_switcher_dialog.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/library/view/library_panel_controller.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/utils/fullscreen_helper.dart';
import 'package:otzaria/settings/settings_exports.dart';

class KeyboardShortcuts extends StatefulWidget {
  final Widget child;

  const KeyboardShortcuts({super.key, required this.child});

  @override
  State<KeyboardShortcuts> createState() => _KeyboardShortcutsState();
}

class _KeyboardShortcutsState extends State<KeyboardShortcuts> {
  Map<String, String> _shortcutSettings = const {};

  /// בודק אם הפוקוס הנוכחי נמצא על שדה טקסט
  bool _isEditing() {
    final focusNode = FocusManager.instance.primaryFocus;
    if (focusNode == null || focusNode.context == null) return false;
    // בדיקה מעמיקה יותר - האם הוידג'ט שמחזיק את הפוקוס הוא צאצא של EditableText
    return focusNode.context!.widget is EditableText ||
        focusNode.context!.findAncestorWidgetOfExactType<EditableText>() !=
            null;
  }

  void _toggleDialog(WidgetBuilder builder) {
    final navigator = navigatorKey.currentState;
    final dialogContext = navigatorKey.currentContext;
    if (navigator == null || dialogContext == null) {
      return;
    }
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    showDialog(context: dialogContext, builder: builder);
  }

  /// מטפל באירועי מקלדת ברמה הגלובלית - עובד גם כשיש TextField עם focus
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // מניעת הפעלת קיצורי מקשים של תו בודד (ללא modifiers) בזמן עריכת טקסט
    if (_isEditing()) {
      final isModifierPressed = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isAltPressed ||
          HardwareKeyboard.instance.isMetaPressed;

      if (!isModifierPressed) {
        // מתיר רק מקשי F ומקש Escape
        final isAllowed = event.logicalKey == LogicalKeyboardKey.escape ||
            (event.logicalKey.keyId >= LogicalKeyboardKey.f1.keyId &&
                event.logicalKey.keyId <= LogicalKeyboardKey.f12.keyId);

        if (!isAllowed) {
          return KeyEventResult.ignored;
        }
      }
    }

    // קריאת ערכי הקיצורים מההגדרות
    final libraryShortcut =
        _shortcutSettings['key-shortcut-open-library-browser'] ?? 'ctrl+l';
    final findRefShortcut =
        _shortcutSettings['key-shortcut-open-find-ref'] ?? 'ctrl+o';
    final closeTabShortcut =
        _shortcutSettings['key-shortcut-close-tab'] ?? 'ctrl+w';
    final closeAllTabsShortcut =
        _shortcutSettings['key-shortcut-close-all-tabs'] ?? 'ctrl+shift+w';
    final readingScreenShortcut =
        _shortcutSettings['key-shortcut-open-reading-screen'] ?? 'ctrl+r';
    final newSearchShortcut =
        _shortcutSettings['key-shortcut-open-new-search'] ?? 'ctrl+q';
    final settingsShortcut =
        _shortcutSettings['key-shortcut-open-settings'] ?? 'ctrl+comma';
    final contextSettingsShortcut =
        _shortcutSettings['key-shortcut-open-context-settings'] ??
            'ctrl+shift+comma';
    final moreShortcut = _shortcutSettings['key-shortcut-open-more'] ?? 'ctrl+m';
    final bookmarksShortcut =
        _shortcutSettings['key-shortcut-open-bookmarks'] ?? 'ctrl+shift+b';
    final historyShortcut =
        _shortcutSettings['key-shortcut-open-history'] ?? 'ctrl+h';
    final workspaceShortcut =
        _shortcutSettings['key-shortcut-switch-workspace'] ?? 'ctrl+k';

    // ספרייה
    if (ShortcutHelper.matchesShortcut(event, libraryShortcut)) {
      context
          .read<NavigationBloc>()
          .add(const NavigateToScreen(Screen.library));
      context
          .read<FocusRepository>()
          .requestLibrarySearchFocus(selectAll: true);
      return KeyEventResult.handled;
    }

    // איתור
    if (ShortcutHelper.matchesShortcut(event, findRefShortcut)) {
      _toggleDialog((context) => FindRefDialog());
      return KeyEventResult.handled;
    }

    // סגור טאב
    if (ShortcutHelper.matchesShortcut(event, closeTabShortcut)) {
      final tabsBloc = context.read<TabsBloc>();
      final historyBloc = context.read<HistoryBloc>();
      if (tabsBloc.state.tabs.isNotEmpty) {
        final currentTab = tabsBloc.state.tabs[tabsBloc.state.currentTabIndex];
        historyBloc.add(AddHistory(currentTab));
      }
      tabsBloc.add(const CloseCurrentTab());
      return KeyEventResult.handled;
    }

    // סגור כל הטאבים
    if (ShortcutHelper.matchesShortcut(event, closeAllTabsShortcut)) {
      final tabsBloc = context.read<TabsBloc>();
      final historyBloc = context.read<HistoryBloc>();
      for (final tab in tabsBloc.state.tabs) {
        if (tab is! SearchingTab) {
          historyBloc.add(AddHistory(tab));
        }
      }
      tabsBloc.add(CloseAllTabs());
      return KeyEventResult.handled;
    }

    // עיון
    if (ShortcutHelper.matchesShortcut(event, readingScreenShortcut)) {
      context
          .read<NavigationBloc>()
          .add(const NavigateToScreen(Screen.reading));
      return KeyEventResult.handled;
    }

    // חיפוש חדש
    if (ShortcutHelper.matchesShortcut(event, newSearchShortcut)) {
      _toggleDialog((context) => const SearchDialog(existingTab: null));
      return KeyEventResult.handled;
    }

    // הגדרות
    if (ShortcutHelper.matchesShortcut(event, settingsShortcut)) {
      context
          .read<NavigationBloc>()
          .add(const NavigateToScreen(Screen.settings));
      return KeyEventResult.handled;
    }

    // הגדרות הקשר
    if (ShortcutHelper.matchesShortcut(event, contextSettingsShortcut)) {
      final currentScreen = context.read<NavigationBloc>().state.currentScreen;
      switch (currentScreen) {
        case Screen.library:
          LibraryPanelController.toggleSettingsPanel();
          break;
        case Screen.reading:
        case Screen.search:
          showReadingSettingsDialog(context);
          break;
        default:
          break;
      }
      return KeyEventResult.handled;
    }

    // כלים
    if (ShortcutHelper.matchesShortcut(event, moreShortcut)) {
      context.read<NavigationBloc>().add(const NavigateToScreen(Screen.more));
      return KeyEventResult.handled;
    }

    // סימניות
    if (ShortcutHelper.matchesShortcut(event, bookmarksShortcut)) {
      _toggleDialog((context) => const BookmarksDialog());
      return KeyEventResult.handled;
    }

    // היסטוריה
    if (ShortcutHelper.matchesShortcut(event, historyShortcut)) {
      _toggleDialog((context) => const HistoryDialog());
      return KeyEventResult.handled;
    }

    // החלף שולחן עבודה
    if (ShortcutHelper.matchesShortcut(event, workspaceShortcut)) {
      _toggleDialog((context) => const WorkspaceSwitcherDialog());
      return KeyEventResult.handled;
    }

    // Ctrl+Tab - טאב הבא
    if (ShortcutHelper.matchesShortcut(event, 'ctrl+tab')) {
      context.read<TabsBloc>().add(NavigateToNextTab());
      return KeyEventResult.handled;
    }

    // Ctrl+Shift+Tab - טאב קודם
    if (ShortcutHelper.matchesShortcut(event, 'ctrl+shift+tab')) {
      context.read<TabsBloc>().add(NavigateToPreviousTab());
      return KeyEventResult.handled;
    }

    // F11 - מסך מלא
    if (ShortcutHelper.matchesShortcut(event, 'f11')) {
      final settingsBloc = context.read<SettingsBloc>();
      final newFullscreenState = !settingsBloc.state.isFullscreen;
      FullscreenHelper.toggleFullscreen(context, newFullscreenState);
      return KeyEventResult.handled;
    }

    // ESC - יציאה ממסך מלא
    if (ShortcutHelper.matchesShortcut(event, 'escape')) {
      final settingsBloc = context.read<SettingsBloc>();
      if (settingsBloc.state.isFullscreen) {
        FullscreenHelper.toggleFullscreen(context, false);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (previous, current) => previous.shortcuts != current.shortcuts,
      builder: (context, state) {
        _shortcutSettings = state.shortcuts;
        return FocusScope(
          autofocus: true,
          onKeyEvent: _handleKeyEvent,
          child: widget.child,
        );
      },
    );
  }
}
