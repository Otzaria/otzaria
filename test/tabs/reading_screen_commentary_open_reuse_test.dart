import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/reading_screen.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:provider/provider.dart';

import '../test_helpers/memory_cache_provider.dart';
import '../test_helpers/stub_settings_bloc.dart';

/// פתיחת מפרש מחלונית הצד (issue #2840): כשהמפרש כבר פתוח בטאב אחר, הטאב
/// הקיים מתמקד ומנווט ליעד — כמו באיתור — במקום טאב כפול.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'פתיחה מחלונית המפרשים ממקדת ומנווטת טאב פתוח של אותו ספר (issue #2840)',
    (tester) async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
      DataRepository.instance.library = Future.value(
        Library(categories: const []),
      );
      final focusRepository = FocusRepository()..resetForTesting();
      final bookmarkBloc = _TestBookmarkBloc();
      final personalNotesBloc = PersonalNotesBloc();
      final tourCubit = TourCubit();
      final historyBloc = _FakeHistoryBloc();
      final settingsBloc = StubSettingsBloc(SettingsState.initial());
      final source = TextBook(title: 'בראשית');
      final commentary = TextBook(title: 'רש"י על בראשית');
      final tabs = [
        for (final book in [source, commentary])
          TextBookTab(
            book: book,
            index: 0,
            blocOverride: _TestTextBookBloc(_loadedState(book)),
          ),
      ];
      final tabsBloc = _TestTabsBloc(TabsState(tabs: tabs, currentTabIndex: 0));

      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        for (final tab in tabs) {
          await tab.bloc.close();
          tab.dispose();
        }
        await tabsBloc.close();
        await settingsBloc.close();
        await historyBloc.close();
        await bookmarkBloc.close();
        await personalNotesBloc.close();
        await tourCubit.close();
        focusRepository.resetForTesting();
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<FocusRepository>.value(value: focusRepository),
            ChangeNotifierProvider<ShamorZachorDataProvider>.value(
              value: _FakeShamorZachorDataProvider(),
            ),
            ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
              value: _FakeShamorZachorProgressProvider(),
            ),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider<TabsBloc>.value(value: tabsBloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
              BlocProvider<BookmarkBloc>.value(value: bookmarkBloc),
              BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
              BlocProvider<TourCubit>.value(value: tourCubit),
              BlocProvider<HistoryBloc>.value(value: historyBloc),
            ],
            child: const MaterialApp(
              home: Directionality(
                textDirection: TextDirection.rtl,
                child: ReadingScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // מה שהחלונית מעבירה בלחיצה על מפרש: טאב חדש של המפרש בשורת היעד.
      final viewer = tester.widget<TextBookViewerBloc>(
        find.byType(TextBookViewerBloc).first,
      );
      final target = TextBookTab(book: commentary, index: 42);
      addTearDown(target.dispose);
      viewer.openBookCallback(target);

      final open = tabsBloc.events.whereType<OpenOrFocusTab>().single;
      expect(open.tab, same(target));
      expect(open.insertAdjacent, isTrue);
      expect(
        open.navigateToPositionIfReused,
        isTrue,
        reason:
            'בלי הדגל הטאב הפתוח של המפרש מותאם רק באותה כותרת, ובכותרת '
            'אחרת נפתח טאב כפול במקום גלילה בטאב הקיים',
      );
    },
  );
}

class _FakeHistoryBloc extends Bloc<HistoryEvent, HistoryState>
    implements HistoryBloc {
  _FakeHistoryBloc() : super(HistoryInitial()) {
    on<HistoryEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TextBookLoaded _loadedState(TextBook book) {
  return TextBookLoaded(
    book: book,
    showLeftPane: true,
    content: [for (var i = 0; i < 100; i++) 'שורה $i'],
    fontSize: 18,
    showSplitView: false,
    activeCommentators: const [],
    commentatorGroups: const [],
    availableCommentators: const [],
    links: const <Link>[],
    visibleLinks: const <Link>[],
    linksByLine: const {},
    tableOfContents: const [],
    removeNikud: false,
    removePunctuation: false,
    visibleIndices: const [0],
    selectedIndex: 0,
    searchText: '',
    currentTitle: 'סימן א',
    searchMode: SearchMode.exact,
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  @override
  final TextBookRepository repository = _FakeTextBookRepository();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTextBookRepository extends TextBookRepository {
  _FakeTextBookRepository() : super(fileSystem: FileSystemData.instance);

  @override
  Future<String> getBookContent(TextBook book) async => 'שורה א\nשורה ב';
}

class _TestTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState);

  final events = <TabsEvent>[];

  @override
  void add(TabsEvent event) => events.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestBookmarkBloc extends Cubit<BookmarkState> implements BookmarkBloc {
  _TestBookmarkBloc() : super(BookmarkState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeShamorZachorDataProvider extends ShamorZachorDataProvider {
  @override
  bool get hasData => false;

  @override
  Future<void> ensureLoaded() async {}
}

class _FakeShamorZachorProgressProvider extends ShamorZachorProgressProvider {
  @override
  Future<void> ensureLoaded() async {}
}
