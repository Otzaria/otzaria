import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/stub_settings_bloc.dart';

/// רגרסיה ל-issue #891: "Right overflowed by" בשורת הכפתורים במסך צר.
/// סורק רוחבי חלון ומוודא שאף רוחב לא זורק שגיאת RenderFlex overflow.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FocusRepository focusRepository;
  late _FakeShamorZachorDataProvider shamorZachorDataProvider;
  late _FakeShamorZachorProgressProvider shamorZachorProgressProvider;
  late _TestBookmarkBloc bookmarkBloc;
  late PersonalNotesBloc personalNotesBloc;
  late TourCubit tourCubit;

  setUp(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
    DataRepository.instance.library = Future.value(
      Library(categories: const []),
    );
    focusRepository = FocusRepository()..resetForTesting();
    shamorZachorDataProvider = _FakeShamorZachorDataProvider();
    shamorZachorProgressProvider = _FakeShamorZachorProgressProvider();
    bookmarkBloc = _TestBookmarkBloc();
    personalNotesBloc = PersonalNotesBloc();
    tourCubit = TourCubit();
  });

  tearDown(() async {
    await bookmarkBloc.close();
    await personalNotesBloc.close();
    await tourCubit.close();
    focusRepository.resetForTesting();
  });

  Future<void> sweepWidths(
    WidgetTester tester, {
    bool showPageShapeView = false,
  }) async {
    final book = TextBook(title: 'ספר בדיקה');
    final bloc = _TestTextBookBloc(
      _loadedState(book, showPageShapeView: showPageShapeView),
    );
    final tab = TextBookTab(book: book, index: 0, blocOverride: bloc);
    final tabsBloc = _TestTabsBloc(
      TabsState(tabs: [tab], currentTabIndex: 0),
    );
    final settingsBloc = StubSettingsBloc(SettingsState.initial());
    final navigationBloc = _TestNavigationBloc();

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await bloc.close();
      await tabsBloc.close();
      await settingsBloc.close();
      await navigationBloc.close();
      tab.dispose();
    });

    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // רוחב החלון המינימלי בדסקטופ הוא 420 (WindowPersistence.minSize).
    final overflowWidths = <double>[];
    for (double width = 420; width <= 1400; width += 10) {
      tester.view.physicalSize = Size(width, 900);
      await _pumpTextBookScreen(
        tester,
        tab: tab,
        textBookBloc: bloc,
        tabsBloc: tabsBloc,
        settingsBloc: settingsBloc,
        focusRepository: focusRepository,
        shamorZachorDataProvider: shamorZachorDataProvider,
        shamorZachorProgressProvider: shamorZachorProgressProvider,
        bookmarkBloc: bookmarkBloc,
        personalNotesBloc: personalNotesBloc,
        tourCubit: tourCubit,
        navigationBloc: navigationBloc,
      );
      final exception = tester.takeException();
      if (exception != null) {
        overflowWidths.add(width);
        debugPrint('overflow at width=$width: $exception');
      }
    }

    expect(
      overflowWidths,
      isEmpty,
      reason: 'רוחבים עם overflow בסרגל: $overflowWidths',
    );
  }

  final variant = TargetPlatformVariant({
    TargetPlatform.windows,
    TargetPlatform.android,
  });

  testWidgets(
    'סריקת רוחבים — אין overflow בסרגל העליון באף רוחב חלון',
    (tester) async => sweepWidths(tester),
    variant: variant,
  );

  testWidgets(
    'סריקת רוחבים בצורת הדף — כפתור ההגדרות המוביל לא גורם overflow',
    (tester) async => sweepWidths(tester, showPageShapeView: true),
    variant: variant,
  );
}

Future<void> _pumpTextBookScreen(
  WidgetTester tester, {
  required TextBookTab tab,
  required TextBookBloc textBookBloc,
  required TabsBloc tabsBloc,
  required SettingsBloc settingsBloc,
  required FocusRepository focusRepository,
  required ShamorZachorDataProvider shamorZachorDataProvider,
  required ShamorZachorProgressProvider shamorZachorProgressProvider,
  required BookmarkBloc bookmarkBloc,
  required PersonalNotesBloc personalNotesBloc,
  required TourCubit tourCubit,
  required NavigationBloc navigationBloc,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<FocusRepository>.value(value: focusRepository),
        ChangeNotifierProvider<ShamorZachorDataProvider>.value(
          value: shamorZachorDataProvider,
        ),
        ChangeNotifierProvider<ShamorZachorProgressProvider>.value(
          value: shamorZachorProgressProvider,
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<TextBookBloc>.value(value: textBookBloc),
          BlocProvider<TabsBloc>.value(value: tabsBloc),
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<BookmarkBloc>.value(value: bookmarkBloc),
          BlocProvider<PersonalNotesBloc>.value(value: personalNotesBloc),
          BlocProvider<TourCubit>.value(value: tourCubit),
          BlocProvider<NavigationBloc>.value(value: navigationBloc),
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

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

TextBookLoaded _loadedState(TextBook book, {bool showPageShapeView = false}) {
  return TextBookLoaded(
    book: book,
    showPageShapeView: showPageShapeView,
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestNavigationBloc extends Bloc<NavigationEvent, NavigationState>
    implements NavigationBloc {
  _TestNavigationBloc() : super(NavigationState.initial(true)) {
    on<NavigationEvent>((event, emit) {});
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
  bool addBookmark({
    required String ref,
    required Book book,
    required int index,
    List<String>? commentatorsToShow,
    BookmarkTargetKind targetKind = BookmarkTargetKind.book,
    String? label,
  }) {
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeShamorZachorDataProvider extends ShamorZachorDataProvider {
  _FakeShamorZachorDataProvider();

  @override
  bool get hasData => false;

  @override
  Future<void> ensureLoaded() async {}
}

class _FakeShamorZachorProgressProvider extends ShamorZachorProgressProvider {
  _FakeShamorZachorProgressProvider();

  @override
  Future<void> ensureLoaded() async {}
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      (_values[key] as bool?) ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      (_values[key] as double?) ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      (_values[key] as int?) ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      (_values[key] as String?) ?? defaultValue;

  @override
  Set<Object?> getKeys() => _values.keys.toSet();

  @override
  T? getValue<T>(String key, {T? defaultValue}) =>
      (_values[key] as T?) ?? defaultValue;

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> removeAll() async => _values.clear();

  @override
  Future<void> setBool(String key, bool? value) async => _values[key] = value;

  @override
  Future<void> setDouble(String key, double? value) async =>
      _values[key] = value;

  @override
  Future<void> setInt(String key, int? value) async => _values[key] = value;

  @override
  Future<void> setObject<T>(String key, T? value) async => _values[key] = value;

  @override
  Future<void> setString(String key, String? value) async =>
      _values[key] = value;
}
