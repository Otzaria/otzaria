// מסך הקורא בבדיקה: בלוקים מזויפים, ספק הגדרות בזיכרון וספריית ספרים ריקה.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:provider/provider.dart';
import 'stub_navigation_bloc.dart';
import 'stub_settings_bloc.dart';
import 'stub_tabs_bloc.dart';
import 'stub_text_book_bloc.dart';

const readerRigLongBookTitle =
    'שולחן ערוך אורח חיים עם נושאי כלים ומפרשים רבים ושונים מאוד לבדיקת כותרת ארוכה';
const readerRigLongLocation =
    'סימן שא סעיף ג בהגה: ומילתא אגב אורחיה קמ"ל דמועד לאדם הוה מועד לבהמה, '
    'וצריך להבין את החילוק שבין הדברים';
const readerRigLongAuthor =
    'רבי יוסף קארו בן אפרים, מחבר הבית יוסף והשולחן ערוך, צפת תש"ה';

/// מצב מסך הקורא שהתרחיש מציג.
enum ReaderRigPhase { loaded, loading, error }

/// כל מה שמסך הקורא צריך כדי לעלות בבדיקה: בלוקים מזויפים, ספק הגדרות בזיכרון
/// וספריית ספרים ריקה. נבנה פעם אחת בתוך [wrapApp] ונסגר בסיום הבדיקה.
class ReaderRig {
  ReaderRig._(this.book, this.bloc, this.tab, this.tabsBloc);

  final TextBook book;
  final StubTextBookBloc bloc;
  final TextBookTab tab;
  final StubTabsBloc tabsBloc;
  final settingsBloc = StubSettingsBloc(SettingsState.initial());
  final navigationBloc = StubNavigationBloc();
  final bookmarkBloc = FakeBookmarkBloc();
  final personalNotesBloc = PersonalNotesBloc();
  final tourCubit = TourCubit();
  final focusRepository = FocusRepository()..resetForTesting();
  final shamorData = FakeShamorZachorData();
  final shamorProgress = FakeShamorZachorProgress();

  factory ReaderRig.create({
    String title = 'ספר בדיקה',
    String? author,
    String currentTitle = 'סימן א',
    bool showLeftPane = false,
    bool pinLeftPane = false,
    bool pageShape = false,
    List<String>? content,
    List<TocEntry> toc = const [],
    List<Link> links = const [],
    List<String> commentators = const [],
    bool showSplitView = false,
    ReaderRigPhase phase = ReaderRigPhase.loaded,
    double fontSize = 18,
  }) {
    final book = TextBook(title: title, author: author);
    final TextBookState state = switch (phase) {
      ReaderRigPhase.loading => TextBookLoading(book, 0, false, const []),
      ReaderRigPhase.error => TextBookError('שגיאה', book, 0, false, const []),
      ReaderRigPhase.loaded => TextBookLoaded(
        book: book,
        showPageShapeView: pageShape,
        showLeftPane: showLeftPane,
        content: content ?? const ['שורה א', 'שורה ב', 'שורה ג'],
        fontSize: fontSize,
        showSplitView: showSplitView,
        activeCommentators: commentators,
        commentatorGroups: const [],
        availableCommentators: commentators,
        links: links,
        visibleLinks: const <Link>[],
        linksByLine: {if (links.isNotEmpty) 1: links},
        tableOfContents: toc,
        removeNikud: false,
        removePunctuation: false,
        visibleIndices: const [0],
        selectedIndex: 0,
        pinLeftPane: pinLeftPane,
        searchText: '',
        currentTitle: currentTitle,
        searchMode: SearchMode.exact,
      ),
    };
    final bloc = StubTextBookBloc(state);
    final tab = TextBookTab(book: book, index: 0, blocOverride: bloc);
    final tabsBloc = StubTabsBloc(TabsState(tabs: [tab], currentTabIndex: 0));
    return ReaderRig._(book, bloc, tab, tabsBloc);
  }

  Future<void> dispose() async {
    await bloc.close();
    await tabsBloc.close();
    await settingsBloc.close();
    await navigationBloc.close();
    await bookmarkBloc.close();
    // close() ממתין לטעינת הערות אמיתית שהמסך הפעיל, ואין לה מה לסיים כאן.
    await personalNotesBloc.close().timeout(
      const Duration(seconds: 1),
      onTimeout: () {},
    );
    await tourCubit.close();
    focusRepository.resetForTesting();
    tab.dispose();
  }

  Widget wrap(Widget app) => MultiProvider(
    providers: [
      Provider<FocusRepository>.value(value: focusRepository),
      ChangeNotifierProvider<ShamorZachorDataProvider>.value(value: shamorData),
      ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
        value: shamorProgress,
      ),
    ],
    child: MultiBlocProvider(
      providers: [
        BlocProvider<TextBookBloc>.value(value: bloc),
        BlocProvider<TabsBloc>.value(value: tabsBloc),
        BlocProvider<SettingsBloc>.value(value: settingsBloc),
        BlocProvider<BookmarkBloc>.value(value: bookmarkBloc),
        BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
        BlocProvider<TourCubit>.value(value: tourCubit),
        BlocProvider<NavigationBloc>.value(value: navigationBloc),
      ],
      child: app,
    ),
  );
}

class FakeBookmarkBloc extends Cubit<BookmarkState> implements BookmarkBloc {
  FakeBookmarkBloc() : super(BookmarkState.initial());

  @override
  bool addBookmark({
    required String ref,
    required Book book,
    required int index,
    List<String>? commentatorsToShow,
    BookmarkTargetKind targetKind = BookmarkTargetKind.book,
    String? label,
  }) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeShamorZachorData extends ShamorZachorDataProvider {
  FakeShamorZachorData();

  @override
  bool get hasData => false;

  @override
  Future<void> ensureLoaded() async {}
}

class FakeShamorZachorProgress extends ShamorZachorProgressProvider {
  FakeShamorZachorProgress();

  @override
  Future<void> ensureLoaded() async {}
}
