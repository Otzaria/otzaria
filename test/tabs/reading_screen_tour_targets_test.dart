import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
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
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/reading_screen.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
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

/// מעבר טאב מזיז את יעדי הסיור בלי לבנות מחדש את מסכי הספר.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('מעבר טאב אינו בונה מחדש את מסכי הספר, ויעדי הסיור עוברים', (
    tester,
  ) async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    DataRepository.instance.library = Future.value(
      Library(categories: const []),
    );
    final tabs = <TextBookTab>[];
    for (final title in ['ספר א', 'ספר ב']) {
      final book = TextBook(title: title);
      final bloc = _TestTextBookBloc(_loadedState(book));
      tabs.add(TextBookTab(book: book, index: 0, blocOverride: bloc));
    }
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tabsBloc = TabsBloc(repository: _FakeTabsRepository());
    tabsBloc.emit(TabsState(tabs: tabs, currentTabIndex: 0));
    final tourCubit = TourCubit();
    final settingsBloc = StubSettingsBloc(SettingsState.initial());
    final bookmarkBloc = _TestBookmarkBloc();
    final notesBloc = PersonalNotesBloc();
    final historyBloc = _FakeHistoryBloc();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tabsBloc.close();
      await tourCubit.close();
      await settingsBloc.close();
      await bookmarkBloc.close();
      await notesBloc.close();
      await historyBloc.close();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<FocusRepository>.value(
            value: FocusRepository()..resetForTesting(),
          ),
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
            BlocProvider<PersonalNotesBloc>.value(value: notesBloc),
            BlocProvider<HistoryBloc>.value(value: historyBloc),
            BlocProvider<TourCubit>.value(value: tourCubit),
          ],
          child: const MaterialApp(home: ReadingScreen()),
        ),
      ),
    );
    Future<void> switchTo(int index) async {
      tabsBloc.add(SetCurrentTab(index));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.pump(const Duration(milliseconds: 100));
    await switchTo(1);
    await switchTo(0);

    Finder viewerOf(TextBookTab tab) => find.byWidgetPredicate(
      (w) => w is TextBookViewerBloc && identical(w.tab, tab),
      skipOffstage: false,
    );
    final before = [for (final tab in tabs) tester.widget(viewerOf(tab))];

    await switchTo(1);

    for (var i = 0; i < tabs.length; i++) {
      expect(
        identical(tester.widget(viewerOf(tabs[i])), before[i]),
        isTrue,
        reason: 'מעבר טאב בנה מחדש את מסך הספר "${tabs[i].title}"',
      );
    }
    expect(
      find.descendant(
        of: viewerOf(tabs[1]),
        matching: find.byKey(AppWindowKeys.current.tour.textBookNavigation),
        skipOffstage: false,
      ),
      findsOneWidget,
      reason: 'יעד הסיור חייב לעבור לטאב הפעיל',
    );
    expect(
      find.descendant(
        of: viewerOf(tabs[0]),
        matching: find.byKey(AppWindowKeys.current.tour.textBookNavigation),
        skipOffstage: false,
      ),
      findsNothing,
    );
  });
}

TextBookLoaded _loadedState(TextBook book) {
  return TextBookLoaded(
    book: book,
    showLeftPane: false,
    content: const ['שורה א', 'שורה ב', 'שורה ג'],
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
    pinLeftPane: false,
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
  final TextBookRepository repository = TextBookRepository(
    fileSystem: FileSystemData.instance,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestBookmarkBloc extends Cubit<BookmarkState> implements BookmarkBloc {
  _TestBookmarkBloc() : super(BookmarkState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHistoryBloc extends Bloc<HistoryEvent, HistoryState>
    implements HistoryBloc {
  _FakeHistoryBloc() : super(HistoryInitial()) {
    on<HistoryEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTabsRepository implements TabsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isMethod) {
      final name = invocation.memberName.toString();
      if (name.contains('save') ||
          name.contains('remap') ||
          name.contains('flush')) {
        return Future<void>.value();
      }
      if (name.contains('loadTabs')) return [];
      if (name.contains('loadCurrentTabIndex')) return 0;
    }
    return null;
  }
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
