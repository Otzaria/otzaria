import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/models/library_navigation_history.dart';
import 'package:otzaria/library/view/grid_items.dart';
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
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/memory_cache_provider.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {
  @override
  final navigationHistory = LibraryNavigationHistory();
}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _MockLibraryUpdateBloc
    extends MockBloc<LibraryUpdateEvent, LibraryUpdateState>
    implements LibraryUpdateBloc {}

class _StubCalendarCubit extends Cubit<CalendarState> implements CalendarCubit {
  _StubCalendarCubit(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Category _category(String title, Category parent) {
  final category = Category(
    title: title,
    description: '',
    shortDescription: '',
    order: 0,
    subCategories: [],
    books: [],
    parent: parent,
  );
  parent.subCategories.add(category);
  return category;
}

/// issue #2691 — מדף שנפתח מתוצאות החיפוש השאיר את השאילתה בתיבה, ולכן
/// Backspace מחק ממנה תו (וחץ החזרה הריץ את החיפוש שוב) במקום לעלות במדפים.
void main() {
  setUpAll(() async {
    registerFallbackValue(NavigateUp());
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('מדף שנפתח מתוצאות החיפוש מנקה את החיפוש, ו-Backspace עולה מדף', (
    tester,
  ) async {
    final searchController = FocusRepository().librarySearchController
      ..text = 'משנה';
    addTearDown(searchController.clear);

    final library = Library(categories: []);
    final mishna = _category('משנה', library);
    _category('ראשונים', mishna).books.add(TextBook(title: 'ספר'));

    final libraryBloc = _MockLibraryBloc();
    final settingsBloc = _MockSettingsBloc();
    final navigationBloc = _MockNavigationBloc();
    final libraryUpdateBloc = _MockLibraryUpdateBloc();
    final calendarCubit = _StubCalendarCubit(CalendarState.initial());
    final states = StreamController<LibraryState>.broadcast();

    whenListen(
      libraryBloc,
      states.stream,
      initialState: LibraryState(
        library: library,
        currentCategory: library,
        searchResults: const [],
        searchCategoryResults: [mishna],
        searchQuery: 'משנה',
      ),
    );
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial().copyWith(
        libraryShowPreview: false,
      ),
    );
    whenListen(
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.library),
    );
    whenListen(
      libraryUpdateBloc,
      const Stream<LibraryUpdateState>.empty(),
      initialState: const LibraryUpdateState(),
    );

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.reset();
      await states.close();
      await libraryBloc.close();
      await settingsBloc.close();
      await navigationBloc.close();
      await libraryUpdateBloc.close();
      await calendarCubit.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.light(
          ColorScheme.fromSeed(seedColor: Colors.blue),
          compactMenuMode: false,
        ),
        locale: const Locale('he', 'IL'),
        home: MultiProvider(
          providers: [
            Provider<FocusRepository>.value(value: FocusRepository()),
            BlocProvider<LibraryBloc>.value(value: libraryBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            BlocProvider<LibraryUpdateBloc>.value(value: libraryUpdateBloc),
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

    await tester.tap(find.byType(CategoryGridItem));
    await tester.pump();

    expect(searchController.text, isEmpty);
    verifyInOrder([
      () => libraryBloc.add(const UpdateSearchQuery('')),
      () => libraryBloc.add(NavigateToCategory(mishna)),
    ]);

    states.add(
      LibraryState(
        library: library,
        currentCategory: mishna,
        searchQuery: '',
      ),
    );
    await tester.pump();
    await tester.pump();
    clearInteractions(libraryBloc);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    verify(() => libraryBloc.add(any(that: isA<NavigateUp>()))).called(1);
  });
}
