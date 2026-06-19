import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/bookmarks/view/bookmark_screen.dart';
import 'package:otzaria/history/view/history_screen.dart';
import 'package:otzaria/workspaces/view/workspace_switcher_dialog.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/utils/ui/fullscreen_helper.dart';
import 'package:otzaria/settings/settings_exports.dart';

class KeyboardShortcuts extends StatefulWidget {
  final Widget child;
  final VoidCallback onFindRefRequested;

  const KeyboardShortcuts({
    super.key,
    required this.child,
    required this.onFindRefRequested,
  });

  @override
  State<KeyboardShortcuts> createState() => _KeyboardShortcutsState();
}

class _KeyboardShortcutsState extends State<KeyboardShortcuts> {
  late final FocusScopeNode _shortcutFocusScopeNode;

  @override
  void initState() {
    super.initState();
    _shortcutFocusScopeNode = FocusScopeNode(
      debugLabel: 'global_keyboard_shortcuts',
      skipTraversal: true,
    );
  }

  @override
  void dispose() {
    _shortcutFocusScopeNode.dispose();
    super.dispose();
  }

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

    // קריאת ערכי הקיצורים מההגדרות. ברירת המחדל נלקחת מהמקור הקנוני היחיד
    // (`ShortcutValidator.defaultShortcuts`) ולא משוכפלת כאן.
    String shortcutOf(String key) =>
        shortcutSettings[key] ?? ShortcutValidator.defaultShortcuts[key] ?? '';

    final libraryShortcut = shortcutOf('key-shortcut-open-library-browser');
    final findRefShortcut = shortcutOf('key-shortcut-open-find-ref');
    final closeTabShortcut = shortcutOf('key-shortcut-close-tab');
    final closeAllTabsShortcut = shortcutOf('key-shortcut-close-all-tabs');
    final restoreClosedTabShortcut =
        shortcutOf('key-shortcut-restore-closed-tab');
    final readingScreenShortcut =
        shortcutOf('key-shortcut-open-reading-screen');
    final newSearchShortcut = shortcutOf('key-shortcut-open-new-search');
    final settingsShortcut = shortcutOf('key-shortcut-open-settings');
    final moreShortcut = shortcutOf('key-shortcut-open-more');
    final bookmarksShortcut = shortcutOf('key-shortcut-open-bookmarks');
    final historyShortcut = shortcutOf('key-shortcut-open-history');
    final workspaceShortcut = shortcutOf('key-shortcut-switch-workspace');
    final toggleNavPaneShortcut = shortcutOf('key-shortcut-toggle-nav-pane');
    final toggleCommentatorsPaneShortcut =
        shortcutOf('key-shortcut-toggle-commentators-pane');
    final openCommentatorsTabShortcut =
        shortcutOf('key-shortcut-open-commentators-tab');
    final prevSegmentShortcut = shortcutOf('key-shortcut-prev-segment');
    final nextSegmentShortcut = shortcutOf('key-shortcut-next-segment');
    final prevTocShortcut = shortcutOf('key-shortcut-prev-toc');
    final nextTocShortcut = shortcutOf('key-shortcut-next-toc');

    // פתח/סגור חלונית ניווט. אם הטאב הפעיל אינו ספר — מחזירים `ignored`
    // כדי לא לבלוע את הקיצור (כך מנוע ה-shortcut יכול להמשיך הלאה במקום
    // להציג למשתמש "כלום קרה" שקטה).
    if (ShortcutHelper.matchesShortcut(event, toggleNavPaneShortcut)) {
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
    if (ShortcutHelper.matchesShortcut(event, toggleCommentatorsPaneShortcut)) {
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

    // פתיחת כרטיסיית מפרשים נפרדת מהטאב הנוכחי
    if (openCommentatorsTabShortcut.isNotEmpty &&
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
          AddTab(PdfCommentatorsTab(sourceTab: tab), insertAdjacent: true),
        );
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // ניווט קטע/דף-פרק בספר טקסט — מגלגל את ה-notifier המתאים בטאב, שהמסך
    // מאזין לו ומבצע בדיוק את אותו ניווט כמו לחיצה על הכפתור. רלוונטי רק
    // ל-TextBookTab; במסכים אחרים מחזירים `ignored` כדי לא לבלוע את הקיצור.
    final navTab = context.read<TabsBloc>().state.currentTab;
    if (navTab is TextBookTab) {
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
      widget.onFindRefRequested();
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

    if (ShortcutHelper.matchesShortcut(event, restoreClosedTabShortcut)) {
      context.read<TabsBloc>().add(const RestoreLastClosedTab());
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
      showDialog(
        context: context,
        builder: (context) => const SearchDialog(existingTab: null),
      );
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

    // פתיחת כלי לפי קיצור אופציונלי (ללא ברירת מחדל) — דרך deep-link פנימי.
    for (final entry in ShortcutValidator.openToolShortcutKeys.entries) {
      final toolShortcut = shortcutOf(entry.key);
      if (toolShortcut.isNotEmpty &&
          ShortcutHelper.matchesShortcut(event, toolShortcut)) {
        mainWindowScreenKey.currentState
            ?.handleInternalDeepLink('otzaria://open/tool/${entry.value}');
        return KeyEventResult.handled;
      }
    }

    // Ctrl+Tab / Ctrl+Shift+Tab - מעבר בין טאבים.
    // לא משתמשים ב-matchesShortcut כדי לא להפוך ל-Cmd ב-Mac: Cmd+Tab
    // שמור למערכת ההפעלה, ולכן ב-Mac נשארים עם Ctrl פיזי (זמין שם).
    if (event.logicalKey == LogicalKeyboardKey.tab &&
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

    // F11 - מסך מלא (רק בעיון/כלים)
    if (ShortcutHelper.matchesShortcut(event, 'f11')) {
      if (!FullscreenHelper.isAllowedInContext(context)) {
        return KeyEventResult.ignored;
      }
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
        // Scope יציב שומר על קיצורים גלובליים גם כשאין child ממוקד, בלי
        // ליצור FocusScopeNode חדש בכל rebuild.
        return FocusScope(
          node: _shortcutFocusScopeNode,
          autofocus: true,
          onKeyEvent: (node, event) =>
              _handleKeyEvent(node, event, state.shortcuts),
          child: widget.child,
        );
      },
    );
  }
}
