import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../test_helpers/memory_cache_provider.dart';

/// ספר שנפתח מתוצאת חיפוש מתחיל בלשונית 'חיפוש' דרך initialIndex — בלי אירוע
/// מעבר לשונית. סרגל החיפוש העליון חייב להסתנכרן גם אז, אחרת השדה מנוטרל
/// ("אין חיפוש בלשונית זו") ואי-אפשר לחפש בתוך הספר (issue #1080).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FocusRepository focusRepository;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    DataRepository.instance.library = Future.value(
      Library(categories: const []),
    );
    focusRepository = FocusRepository()..resetForTesting();
  });

  tearDown(() {
    focusRepository.resetForTesting();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required String searchText,
  }) async {
    final book = TextBook(title: 'ספר בדיקה');
    final bloc = _TestTextBookBloc(_loadedState(book, searchText));
    final tab = TextBookTab(
      book: book,
      index: 0,
      searchText: searchText,
      blocOverride: bloc,
    );
    final tabsBloc = _TestTabsBloc(TabsState(tabs: [tab], currentTabIndex: 0));
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    final bookmarkBloc = _TestBookmarkBloc();
    final personalNotesBloc = PersonalNotesBloc();
    final tourCubit = TourCubit();

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await bloc.close();
      await tabsBloc.close();
      await settingsBloc.close();
      await bookmarkBloc.close();
      await personalNotesBloc.close();
      await tourCubit.close();
      tab.dispose();
    });

    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<FocusRepository>.value(value: focusRepository),
          ChangeNotifierProvider<ShamorZachorDataProvider>(
            create: (_) => _FakeShamorZachorDataProvider(),
          ),
          ChangeNotifierProvider<ShamorZachorProgressProvider>(
            create: (_) => _FakeShamorZachorProgressProvider(),
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
          ],
          child: MaterialApp(
            home: TextBookViewerBloc(
              tab: tab,
              isInCombinedView: false,
              openBookCallback: (_) {},
            ),
          ),
        ),
      ),
    );

    // הפרסום לסרגל נדחה לסוף frame — נותנים לו להתעדכן.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Finder hoistedField() => find.descendant(
    of: find.byType(NavPanelSearchBar),
    matching: find.byType(OtzariaSearchField),
  );

  testWidgets('פתיחה מתוצאת חיפוש — סרגל החיפוש העליון פעיל', (tester) async {
    await pumpScreen(tester, searchText: 'הגעת זמן');

    final field = tester.widget<OtzariaSearchField>(hoistedField());
    expect(
      field.enabled,
      isTrue,
      reason: 'הסרגל נשאר על לשונית 0 בעוד הבקר התחיל בלשונית החיפוש',
    );
    expect(field.hintText, isNot('אין חיפוש בלשונית זו'));
  });
}

TextBookLoaded _loadedState(TextBook book, String searchText) {
  return TextBookLoaded(
    book: book,
    showLeftPane: true,
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
    pinLeftPane: true,
    searchText: searchText,
    currentTitle: 'סימן א',
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
    searchMode: SearchMode.exact,
  );
}

class _TestTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _TestTextBookBloc(super.initialState) {
    on<TextBookEvent>((event, emit) {});
  }

  // לשונית החיפוש טוענת את תוכן הספר דרך ה-repository — בלי הזיוף הבדיקה
  // נתקעת על IO אמיתי (LibraryProviderManager).
  @override
  TextBookRepository get repository => _FakeTextBookRepository();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTextBookRepository implements TextBookRepository {
  @override
  Future<String> getBookContent(TextBook book) async =>
      'שורה א\nשורה ב\nשורה ג';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState);

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
