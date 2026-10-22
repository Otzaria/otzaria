import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/personal_notes_system.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart'
    hide UpdateFontSize;
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/text_book/view/combined_view/combined_book_screen.dart';
import 'package:otzaria/text_book/view/text_book_screen.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:provider/provider.dart';

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

  testWidgets('שינוי גודל גופן ב-SettingsBloc שולח מיד UpdateFontSize', (
    tester,
  ) async {
    final book = TextBook(title: 'ספר בדיקה');
    final bloc = _MockTextBookBloc();
    whenListen(
      bloc,
      const Stream<TextBookState>.empty(),
      initialState: _loadedState(book, fontSize: 18),
    );
    final tab = TextBookTab(book: book, index: 0, blocOverride: bloc);
    final tabsBloc = _TestTabsBloc(TabsState(tabs: [tab], currentTabIndex: 0));
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await bloc.close();
      await tabsBloc.close();
      await settingsBloc.close();
      tab.dispose();
    });

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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      tester.widget<CombinedView>(find.byType(CombinedView).first).textSize,
      18,
    );

    settingsBloc.emitStateForTest(
      SettingsState.initial().copyWith(fontSize: 30),
    );
    await tester.pump();
    await tester.pump();

    verify(() => bloc.add(const UpdateFontSize(30))).called(1);
  });

  /// The book screen at [fontSize], with a mock bloc that records events.
  Future<_MockTextBookBloc> pumpViewer(
    WidgetTester tester, {
    required double fontSize,
    List<String>? content,
  }) async {
    final book = TextBook(title: 'ספר בדיקה');
    final bloc = _MockTextBookBloc();
    whenListen(
      bloc,
      const Stream<TextBookState>.empty(),
      initialState: content == null
          ? _loadedState(book, fontSize: fontSize)
          : _loadedState(book, fontSize: fontSize, content: content),
    );
    final tab = TextBookTab(book: book, index: 0, blocOverride: bloc);
    final tabsBloc = _TestTabsBloc(TabsState(tabs: [tab], currentTabIndex: 0));
    final settingsBloc = _TestSettingsBloc(SettingsState.initial());
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await bloc.close();
      await tabsBloc.close();
      await settingsBloc.close();
      tab.dispose();
    });

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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return bloc;
  }

  testWidgets('Ctrl + wheel over the text steps the font size (#2705)', (
    tester,
  ) async {
    final bloc = await pumpViewer(tester, fontSize: 18);
    final text = tester.getCenter(find.byType(CombinedView).first);
    final mouse = TestPointer(1, PointerDeviceKind.mouse)..hover(text);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -100)));
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    verify(() => bloc.add(const UpdateFontSize(21))).called(1);
  });

  testWidgets('a precision touchpad pinch scales the font size (#2705)', (
    tester,
  ) async {
    final bloc = await pumpViewer(tester, fontSize: 20);
    final text = tester.getCenter(find.byType(CombinedView).first);
    final pad = TestPointer(2, PointerDeviceKind.trackpad);

    await tester.sendEventToBinding(pad.panZoomStart(text));
    for (final scale in [1.1, 1.2, 1.3, 1.4, 1.5]) {
      await tester.sendEventToBinding(pad.panZoomUpdate(text, scale: scale));
      await tester.pump();
    }
    await tester.sendEventToBinding(pad.panZoomEnd());
    await tester.pump();

    verify(() => bloc.add(const UpdateFontSize(30))).called(1);
  });

  testWidgets('a precision touchpad pinch over a long book keeps its start', (
    tester,
  ) async {
    final bloc = await pumpViewer(
      tester,
      fontSize: 20,
      content: List.generate(200, (i) => 'שורה $i'),
    );
    final text = tester.getCenter(find.byType(CombinedView).first);
    final pad = TestPointer(2, PointerDeviceKind.trackpad);

    await tester.sendEventToBinding(pad.panZoomStart(text));
    for (final scale in [1.1, 1.2, 1.3, 1.4, 1.5]) {
      await tester.sendEventToBinding(pad.panZoomUpdate(text, scale: scale));
      await tester.pump();
    }
    await tester.sendEventToBinding(pad.panZoomEnd());
    await tester.pump();

    verify(() => bloc.add(const UpdateFontSize(22))).called(1);
    verify(() => bloc.add(const UpdateFontSize(30))).called(1);
  });

  testWidgets('a small one-sided touch pinch zooms instead of scrolling', (
    tester,
  ) async {
    // Enough lines for the text list to scroll, so its drag joins the arena.
    final bloc = await pumpViewer(
      tester,
      fontSize: 20,
      content: List.generate(200, (i) => 'שורה $i'),
    );
    final text = tester.getCenter(find.byType(CombinedView).first);
    final still = await tester.startGesture(text, pointer: 1);
    final moving = await tester.startGesture(
      text + const Offset(0, 100),
      pointer: 2,
    );
    for (var step = 0; step < 5; step++) {
      await moving.moveBy(const Offset(0, 5));
      await tester.pump();
    }
    await moving.up();
    await still.up();
    await tester.pump();

    verify(() => bloc.add(const UpdateFontSize(25))).called(1);
  });

  testWidgets('a parallel two-finger vertical drag does not zoom', (
    tester,
  ) async {
    registerFallbackValue(const UpdateFontSize(0));
    final bloc = await pumpViewer(
      tester,
      fontSize: 20,
      content: List.generate(200, (i) => 'שורה $i'),
    );
    final text = tester.getCenter(find.byType(CombinedView).first);
    final first = await tester.startGesture(text, pointer: 1);
    final second = await tester.startGesture(
      text + const Offset(0, 100),
      pointer: 2,
    );
    for (var step = 0; step < 6; step++) {
      await first.moveBy(const Offset(0, -5));
      await second.moveBy(const Offset(0, -5));
      await tester.pump();
    }
    await first.up();
    await second.up();
    await tester.pump();

    verifyNever(() => bloc.add(any(that: isA<UpdateFontSize>())));
  });

  test('TextBookBloc מחיל UpdateFontSize על מצב טעון', () async {
    final book = TextBook(title: 'ספר בדיקה');
    final bloc = TextBookBloc(
      repository: _FontSizeRepository(),
      quickPreviewLoader:
          (
            String title,
            int currentLine, {
            int? categoryId,
            String? fileType,
            BookSource preferSource = BookSource.official,
          }) async => null,
      initialState: TextBookInitial.named(
        book,
        0,
        false,
        const [],
        searchMode: SearchMode.exact,
        showPageShapeView: false,
      ),
    );
    addTearDown(bloc.close);

    final loaded = bloc.stream
        .where((state) => state is TextBookLoaded)
        .cast<TextBookLoaded>()
        .first;
    bloc.add(
      const LoadContent(
        fontSize: 18,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: false,
      ),
    );
    await loaded.timeout(const Duration(seconds: 5));

    final updated = bloc.stream
        .where((state) => state is TextBookLoaded)
        .cast<TextBookLoaded>()
        .firstWhere((state) => state.fontSize == 30);
    bloc.add(const UpdateFontSize(30));

    expect(
      (await updated.timeout(const Duration(seconds: 5))).fontSize,
      30,
    );
  });
}

TextBookLoaded _loadedState(
  TextBook book, {
  required double fontSize,
  List<String> content = const ['שורה א', 'שורה ב', 'שורה ג'],
}) {
  return TextBookLoaded(
    book: book,
    showLeftPane: false,
    content: content,
    fontSize: fontSize,
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

class _MockTextBookBloc extends MockBloc<TextBookEvent, TextBookState>
    implements TextBookBloc {}

class _MockFileSystemData extends Mock implements FileSystemData {}

class _FontSizeRepository extends TextBookRepository {
  _FontSizeRepository() : super(fileSystem: _MockFileSystemData());

  @override
  Future<String> getBookContent(TextBook book) async {
    return 'שורה א\nשורה ב\nשורה ג';
  }

  @override
  Future<BookContentRange?> getBookContentRange(
    TextBook book, {
    required int startLine,
    required int endLine,
  }) async {
    return const BookContentRange(
      startLine: 0,
      endLine: 2,
      totalLines: 3,
      lines: ['שורה א', 'שורה ב', 'שורה ג'],
    );
  }

  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async {
    return const [];
  }

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async {
    return const [];
  }

  @override
  Future<List<String>> getAvailableCommentators(TextBook book) async {
    return const [];
  }
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) {});
  }

  void emitStateForTest(SettingsState state) => emit(state);

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
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) {
      return value;
    }
    return defaultValue;
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }
}
