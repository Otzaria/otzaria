import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/library_browser.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _MockLibraryUpdateBloc
    extends MockBloc<LibraryUpdateEvent, LibraryUpdateState>
    implements LibraryUpdateBloc {}

class _MockTabsBloc extends MockBloc<TabsEvent, TabsState>
    implements TabsBloc {}

class _MockHistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {}

/// מספק CalendarState קבוע בלי להריץ את אתחול ה-cubit האמיתי.
class _StubCalendarCubit extends Cubit<CalendarState> implements CalendarCubit {
  _StubCalendarCubit(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// #4468: Enter בספרייה פותח את הספר המסומן, בשדה החיפוש ובשורה הממוקדת.
void main() {
  late _MockTabsBloc tabsBloc;
  late List<TabsEvent> tabEvents;

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  Future<void> pumpBrowser(
    WidgetTester tester, {
    required List<Book> books,
    Book? previewBook,
    bool previewEnabled = true,
    String viewMode = 'list',
  }) async {
    final library = Library(categories: []);
    final libraryBloc = _MockLibraryBloc();
    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: LibraryState(
        library: library,
        currentCategory: library,
        searchResults: books,
        previewBook: previewBook,
      ),
    );
    final settingsBloc = _MockSettingsBloc();
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial().copyWith(
        libraryViewMode: viewMode,
        libraryShowPreview: previewEnabled,
      ),
    );
    final navigationBloc = _MockNavigationBloc();
    whenListen(
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.library),
    );
    final libraryUpdateBloc = _MockLibraryUpdateBloc();
    whenListen(
      libraryUpdateBloc,
      const Stream<LibraryUpdateState>.empty(),
      initialState: const LibraryUpdateState(),
    );
    final historyBloc = _MockHistoryBloc();
    whenListen(
      historyBloc,
      const Stream<HistoryState>.empty(),
      initialState: HistoryInitial(),
    );
    tabsBloc = _MockTabsBloc();
    tabEvents = [];
    whenListen(
      tabsBloc,
      const Stream<TabsState>.empty(),
      initialState: const TabsState(tabs: [], currentTabIndex: 0),
    );
    when(() => tabsBloc.add(any())).thenAnswer((invocation) {
      tabEvents.add(invocation.positionalArguments.single as TabsEvent);
    });
    final calendarCubit = _StubCalendarCubit(CalendarState.initial());

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.reset();
      await settingsBloc.close();
      await navigationBloc.close();
      await libraryUpdateBloc.close();
      await historyBloc.close();
      await tabsBloc.close();
      await calendarCubit.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: MultiProvider(
          providers: [
            Provider<FocusRepository>.value(value: FocusRepository()),
            BlocProvider<LibraryBloc>(create: (_) => libraryBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            BlocProvider<LibraryUpdateBloc>.value(value: libraryUpdateBloc),
            BlocProvider<HistoryBloc>.value(value: historyBloc),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<CalendarCubit>.value(value: calendarCubit),
            BlocProvider<CustomFoldersBloc>(
              create: (_) => CustomFoldersBloc(addLibraryEvent: (_) {}),
            ),
          ],
          child: const LibraryBrowser(),
        ),
      ),
    );
    await tester.pump();
    // כפתור הדף היומי גולש עם CalendarState מדומה — לא נושא הבדיקה.
    tester.takeException();
  }

  Iterable<OpenOrFocusTab> opened() => tabEvents.whereType<OpenOrFocusTab>();

  setUpAll(() {
    registerFallbackValue(const SaveTabs());
  });

  for (final viewMode in ['list', 'grid']) {
    testWidgets('Enter על ספר ממוקד פותח אותו, בתצוגת $viewMode', (
      tester,
    ) async {
      final books = [
        TextBook(title: 'ספר ראשון'),
        TextBook(title: 'ספר שני'),
      ];
      await pumpBrowser(tester, books: books, viewMode: viewMode);

      Focus.of(tester.element(find.text('ספר שני'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(opened(), hasLength(1));
      expect(opened().single.tab.title, 'ספר שני');
    });
  }

  testWidgets('בלי תצוגה מקדימה Enter פותח ספר ממוקד פעם אחת', (tester) async {
    await pumpBrowser(
      tester,
      books: [TextBook(title: 'ספר ראשון')],
      previewEnabled: false,
    );

    Focus.of(tester.element(find.text('ספר ראשון'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(opened(), hasLength(1));
  });

  testWidgets('Enter בשדה החיפוש פותח את הספר המסומן בתוצאות', (tester) async {
    final books = [
      TextBook(title: 'ספר ראשון'),
      TextBook(title: 'ספר שני'),
    ];
    await pumpBrowser(tester, books: books, previewBook: books[1]);

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(opened(), hasLength(1));
    expect(opened().single.tab.title, 'ספר שני');
  });

  testWidgets('Enter בשדה החיפוש לא פותח ספר מסומן שאינו בתוצאות', (
    tester,
  ) async {
    final books = [TextBook(title: 'ספר ראשון')];
    await pumpBrowser(
      tester,
      books: books,
      previewBook: TextBook(title: 'ספר ישן'),
    );

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(opened(), isEmpty);
  });
}
