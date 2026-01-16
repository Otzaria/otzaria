import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/focus/focus_repository.dart';
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
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/utils/shortcut_helper.dart';
import 'package:otzaria/utils/fullscreen_helper.dart';

class KeyboardShortcuts extends StatefulWidget {
  final Widget child;

  const KeyboardShortcuts({super.key, required this.child});

  @override
  State<KeyboardShortcuts> createState() => _KeyboardShortcutsState();
}

class _KeyboardShortcutsState extends State<KeyboardShortcuts> {
  /// בודק אם הפוקוס הנוכחי נמצא על שדה טקסט
  bool _isEditing() {
    final focusNode = FocusManager.instance.primaryFocus;
    if (focusNode == null || focusNode.context == null) return false;
    // בדיקה מעמיקה יותר - האם הוידג'ט שמחזיק את הפוקוס הוא צאצא של EditableText
    return focusNode.context!.widget is EditableText ||
        focusNode.context!.findAncestorWidgetOfExactType<EditableText>() !=
            null;
  }

  /// מטפל באירועי מקלדת ברמה הגלובלית - עובד גם כשיש TextField עם focus
  KeyEventResult _handleKeyEvent(
      FocusNode node, KeyEvent event, Map<String, String> shortcutSettings) {
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
        shortcutSettings['key-shortcut-open-library-browser'] ?? 'ctrl+l';
    final findRefShortcut =
        shortcutSettings['key-shortcut-open-find-ref'] ?? 'ctrl+o';
    final closeTabShortcut =
        shortcutSettings['key-shortcut-close-tab'] ?? 'ctrl+w';
    final closeAllTabsShortcut =
        shortcutSettings['key-shortcut-close-all-tabs'] ?? 'ctrl+shift+w';
    final readingScreenShortcut =
        shortcutSettings['key-shortcut-open-reading-screen'] ?? 'ctrl+r';
    final newSearchShortcut =
        shortcutSettings['key-shortcut-open-new-search'] ?? 'ctrl+q';
    final settingsShortcut =
        shortcutSettings['key-shortcut-open-settings'] ?? 'ctrl+comma';
    final moreShortcut = shortcutSettings['key-shortcut-open-more'] ?? 'ctrl+m';
    final bookmarksShortcut =
        shortcutSettings['key-shortcut-open-bookmarks'] ?? 'ctrl+shift+b';
    final historyShortcut =
        shortcutSettings['key-shortcut-open-history'] ?? 'ctrl+h';
    final workspaceShortcut =
        shortcutSettings['key-shortcut-switch-workspace'] ?? 'ctrl+k';

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
      showDialog(context: context, builder: (context) => FindRefDialog());
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
      final useFastSearch = context.read<SettingsBloc>().state.useFastSearch;
      if (!useFastSearch) {
        _openLegacySearchTab(context);
      } else {
        showDialog(
          context: context,
          builder: (context) => const SearchDialog(existingTab: null),
        );
      }
      return KeyEventResult.handled;
    }

    // הגדרות
    if (ShortcutHelper.matchesShortcut(event, settingsShortcut)) {
      context
          .read<NavigationBloc>()
          .add(const NavigateToScreen(Screen.settings));
      return KeyEventResult.handled;
    }

    // כלים
    if (ShortcutHelper.matchesShortcut(event, moreShortcut)) {
      context.read<NavigationBloc>().add(const NavigateToScreen(Screen.more));
      return KeyEventResult.handled;
    }

    // סימניות
    if (ShortcutHelper.matchesShortcut(event, bookmarksShortcut)) {
      showDialog(
        context: context,
        builder: (context) => const BookmarksDialog(),
      );
      return KeyEventResult.handled;
    }

    // היסטוריה
    if (ShortcutHelper.matchesShortcut(event, historyShortcut)) {
      showDialog(
        context: context,
        builder: (context) => const HistoryDialog(),
      );
      return KeyEventResult.handled;
    }

    // החלף שולחן עבודה
    if (ShortcutHelper.matchesShortcut(event, workspaceShortcut)) {
      showDialog(
        context: context,
        builder: (context) => const WorkspaceSwitcherDialog(),
      );
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
        // משתמשים ב-FocusScope עם onKeyEvent כדי לתפוס קיצורים גם כשיש TextField עם focus
        return FocusScope(
          autofocus: true,
          onKeyEvent: (node, event) =>
              _handleKeyEvent(node, event, state.shortcuts),
          child: widget.child,
        );
      },
    );
  }

  void _openLegacySearchTab(BuildContext context) {
    final tabsBloc = context.read<TabsBloc>();
    final navigationBloc = context.read<NavigationBloc>();

    final tabsState = tabsBloc.state;
    final hasSearchTab = tabsState.tabs.any(
      (tab) => tab.runtimeType == SearchingTab,
    );

    if (!hasSearchTab) {
      tabsBloc.add(AddTab(SearchingTab("חיפוש", "")));
    } else {
      final currentScreen = navigationBloc.state.currentScreen;
      final isAlreadySearchTab = currentScreen == Screen.search &&
          tabsState.tabs[tabsState.currentTabIndex].runtimeType == SearchingTab;
      if (!isAlreadySearchTab) {
        final searchTabIndex = tabsState.tabs.indexWhere(
          (tab) => tab.runtimeType == SearchingTab,
        );
        if (searchTabIndex != -1) {
          tabsBloc.add(SetCurrentTab(searchTabIndex));
        }
      }
    }

    navigationBloc.add(const NavigateToScreen(Screen.search));
  }
}
