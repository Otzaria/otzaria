import 'package:collection/collection.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';

class BookOpenCoordinator {
  final TabsBloc tabsBloc;
  final HistoryBloc historyBloc;
  final NavigationBloc navigationBloc;

  const BookOpenCoordinator({
    required this.tabsBloc,
    required this.historyBloc,
    required this.navigationBloc,
  });

  void openBook(
    Book book,
    int index,
    String searchQuery, {
    bool ignoreHistory = false,
    bool requiresStableLayout = false,
    String? pinpointHighlight,
  }) {
    final tabsState = tabsBloc.state;
    if (tabsState.hasOpenTabs) {
      historyBloc.add(CaptureStateForHistory(tabsState.currentTab!));
    }

    // deep link עם הדגשה ממוקדת מציין במפורש סעיף יעד; חייבים לכבד אותו במדויק
    // (גם כש‑index=0) ולא ליפול חזרה להיסטוריית קריאה — אחרת ההדגשה תופיע במקום
    // הלא נכון ביחס לסעיף שהמשתמש ביקש.
    final hasPinpoint =
        pinpointHighlight != null && pinpointHighlight.isNotEmpty;

    final historyState = historyBloc.state;
    final lastOpened = (ignoreHistory || hasPinpoint)
        ? null
        : historyState.history
            .firstWhereOrNull((b) => b.book.title == book.title);

    final initialIndex = (ignoreHistory || hasPinpoint || index != 0)
        ? index
        : (lastOpened?.index ?? 0);
    final initialCommentators = lastOpened?.commentatorsToShow;

    final shouldOpenLeftPane = shouldAutoOpenReadingLeftPane();

    final savedViewMode =
        PageShapeSettingsManager.getViewModePreference(book.title);

    final tab = OpenedTab.fromBook(
      book,
      initialIndex,
      searchText: searchQuery,
      commentators: initialCommentators,
      openLeftPane: shouldOpenLeftPane,
      showPageShapeView: savedViewMode,
      requiresStableLayout: requiresStableLayout,
      pinpointHighlight: pinpointHighlight,
      // שמירת הסעיף שהמשתמש ביקש בפירוש; משמש את מסלול ה‑reuse של TabsBloc
      // כדי לדעת על איזה סעיף להחיל את ההדגשה גם אם הטאב הקיים נפתח באינדקס
      // אחר.
      pinpointHighlightSectionIndex: hasPinpoint ? initialIndex : null,
    );
    tabsBloc.add(OpenOrFocusTab(tab));

    navigationBloc.add(const NavigateToScreen(Screen.reading));
  }
}
