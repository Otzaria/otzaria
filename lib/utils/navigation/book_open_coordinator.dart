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
    bool insertAdjacent = false,
  }) {
    final tabsState = tabsBloc.state;
    if (tabsState.hasOpenTabs) {
      historyBloc.add(CaptureStateForHistory(tabsState.currentTab!));
    }

    // deep link ╫ó╫¥ ╫פ╫ף╫ע╫⌐╫פ ╫₧╫₧╫ץ╫º╫ף╫¬ ╫₧╫ª╫ש╫ש╫ƒ ╫ס╫₧╫ñ╫ץ╫¿╫⌐ ╫í╫ó╫ש╫ú ╫ש╫ó╫ף; ╫ק╫ש╫ש╫ס╫ש╫¥ ╫£╫¢╫ס╫ף ╫נ╫ץ╫¬╫ץ ╫ס╫₧╫ף╫ץ╫ש╫º
    // (╫ע╫¥ ╫¢╫⌐Γאסindex=0) ╫ץ╫£╫נ ╫£╫ש╫ñ╫ץ╫£ ╫ק╫צ╫¿╫פ ╫£╫פ╫ש╫í╫ר╫ץ╫¿╫ש╫ש╫¬ ╫º╫¿╫ש╫נ╫פ Γאפ ╫נ╫ק╫¿╫¬ ╫פ╫פ╫ף╫ע╫⌐╫פ ╫¬╫ץ╫ñ╫ש╫ó ╫ס╫₧╫º╫ץ╫¥
    // ╫פ╫£╫נ ╫á╫¢╫ץ╫ƒ ╫ס╫ש╫ק╫í ╫£╫í╫ó╫ש╫ú ╫⌐╫פ╫₧╫⌐╫¬╫₧╫⌐ ╫ס╫ש╫º╫⌐.
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
      // ╫⌐╫₧╫ש╫¿╫¬ ╫פ╫í╫ó╫ש╫ú ╫⌐╫פ╫₧╫⌐╫¬╫₧╫⌐ ╫ס╫ש╫º╫⌐ ╫ס╫ñ╫ש╫¿╫ץ╫⌐; ╫₧╫⌐╫₧╫⌐ ╫נ╫¬ ╫₧╫í╫£╫ץ╫£ ╫פΓאסreuse ╫⌐╫£ TabsBloc
      // ╫¢╫ף╫ש ╫£╫ף╫ó╫¬ ╫ó╫£ ╫נ╫ש╫צ╫פ ╫í╫ó╫ש╫ú ╫£╫פ╫ק╫ש╫£ ╫נ╫¬ ╫פ╫פ╫ף╫ע╫⌐╫פ ╫ע╫¥ ╫נ╫¥ ╫פ╫ר╫נ╫ס ╫פ╫º╫ש╫ש╫¥ ╫á╫ñ╫¬╫ק ╫ס╫נ╫ש╫á╫ף╫º╫í
      // ╫נ╫ק╫¿.
      pinpointHighlightSectionIndex: hasPinpoint ? initialIndex : null,
    );
    tabsBloc.add(OpenOrFocusTab(tab, insertAdjacent: insertAdjacent));

    navigationBloc.add(const NavigateToScreen(Screen.reading));
  }
}
