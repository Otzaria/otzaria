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
import 'package:otzaria/utils/reading_left_pane_policy.dart';

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
  }) {
    final tabsState = tabsBloc.state;
    if (tabsState.hasOpenTabs) {
      historyBloc.add(CaptureStateForHistory(tabsState.currentTab!));
    }

    final historyState = historyBloc.state;
    final lastOpened = ignoreHistory
        ? null
        : historyState.history
            .firstWhereOrNull((b) => b.book.title == book.title);

    final resumeBookmark =
        !ignoreHistory && index == 0 && (lastOpened?.index ?? 0) > 0
            ? lastOpened
            : null;
    final initialIndex = book is PdfBook && index <= 0 ? 1 : index;
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
      resumeIndex: resumeBookmark?.index,
      resumeRef: resumeBookmark?.ref,
    );
    tabsBloc.add(OpenOrFocusTab(tab));

    navigationBloc.add(const NavigateToScreen(Screen.reading));
  }
}
