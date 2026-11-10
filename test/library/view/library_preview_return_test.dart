import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
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
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/memory_cache_provider.dart';

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

Category _folder(String title, {List<Book> books = const []}) => Category(
  title: title,
  description: '',
  shortDescription: '',
  order: 1,
  subCategories: [],
  books: List.of(books),
  parent: null,
);

/// תצוגת רשת: לחיצה אחת על תיקייה בוחרת אותה לתצוגה המקדימה בלי לנווט,
/// ו-Esc או לחיצה על רקע ריק מחזירים את התצוגה המקדימה לתיקייה הנוכחית
/// (issue #4626).
void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late Library library;
  late Category halacha;
  late LibraryBloc bloc;
  late FocusRepository focusRepository;
  late int escapesAboveLibrary;

  Future<void> pump(WidgetTester tester, {LibraryState? state}) async {
    halacha = _folder('הלכה', books: [TextBook(title: 'שולחן ערוך')]);
    final tanach = _folder('תנ״ך', books: [TextBook(title: 'בראשית')]);
    library = Library(categories: [tanach, halacha]);
    for (final c in library.subCategories) {
      c.parent = library;
    }
    bloc = LibraryBloc()
      ..emit(state ?? LibraryState(library: library, currentCategory: library));
    focusRepository = FocusRepository();
    escapesAboveLibrary = 0;

    final settingsBloc = _MockSettingsBloc();
    final navigationBloc = _MockNavigationBloc();
    final updateBloc = _MockLibraryUpdateBloc();
    final calendarCubit = _StubCalendarCubit(CalendarState.initial());
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial(),
    );
    whenListen(
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.library),
    );
    whenListen(
      updateBloc,
      const Stream<LibraryUpdateState>.empty(),
      initialState: const LibraryUpdateState(),
    );

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.reset();
      await settingsBloc.close();
      await navigationBloc.close();
      await updateBloc.close();
      await calendarCubit.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: MultiProvider(
          providers: [
            Provider<FocusRepository>.value(value: focusRepository),
            BlocProvider<LibraryBloc>(create: (_) => bloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            BlocProvider<LibraryUpdateBloc>.value(value: updateBloc),
            BlocProvider<CalendarCubit>.value(value: calendarCubit),
            BlocProvider<CustomFoldersBloc>(
              create: (_) => CustomFoldersBloc(addLibraryEvent: (_) {}),
            ),
          ],
          // מטפל מעל הספרייה: סופר Esc שהספרייה לא צרכה.
          child: Focus(
            canRequestFocus: false,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                escapesAboveLibrary++;
              }
              return KeyEventResult.ignored;
            },
            child: const LibraryBrowser(),
          ),
        ),
      ),
    );
    await tester.pump();
    // כפתור הדף היומי גולש עם CalendarState מדומה — לא נושא הבדיקה.
    tester.takeException();
  }

  Future<void> clickFolder(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(CategoryGridItem),
        matching: find.text('הלכה'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(bloc.state.previewCategory, same(halacha));
    expect(bloc.state.currentCategory, same(library));
  }

  testWidgets('Esc אחרי לחיצה על תיקייה מחזיר את התצוגה המקדימה לתיקייה '
      'הנוכחית', (tester) async {
    await pump(tester);
    await clickFolder(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(bloc.state.previewCategory, same(library));
    expect(bloc.state.currentCategory, same(library));
    expect(escapesAboveLibrary, 0, reason: 'Esc נצרך');
  });

  testWidgets('לחיצה על רקע ריק ברשת מחזירה את התצוגה המקדימה לתיקייה '
      'הנוכחית', (tester) async {
    await pump(tester);
    await clickFolder(tester);

    final grid = tester.getRect(find.byType(MyGridView));
    await tester.tapAt(Offset(grid.center.dx, grid.bottom - 20));
    await tester.pump(const Duration(milliseconds: 500));

    expect(bloc.state.previewCategory, same(library));
  });

  testWidgets('לחיצה על תיקייה אחרת רק מחליפה את התצוגה המקדימה', (
    tester,
  ) async {
    await pump(tester);
    await clickFolder(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(CategoryGridItem),
        matching: find.text('תנ״ך'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(bloc.state.previewCategory?.title, 'תנ״ך');
  });

  testWidgets('Esc בשדה החיפוש אינו נוגע בתצוגה המקדימה', (tester) async {
    await pump(tester);
    await clickFolder(tester);

    focusRepository.librarySearchFocusNode.requestFocus();
    await tester.pump();
    expect(focusRepository.librarySearchFocusNode.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(bloc.state.previewCategory, same(halacha));
    expect(escapesAboveLibrary, 1, reason: 'Esc לא נצרך');
  });

  testWidgets('Esc כשהתצוגה המקדימה כבר על התיקייה הנוכחית לא נצרך', (
    tester,
  ) async {
    await pump(tester);
    await clickFolder(tester);
    // מצב הפתיחה של הספרייה: התצוגה המקדימה על התיקייה הנוכחית.
    bloc.emit(bloc.state.copyWith(previewCategory: library));
    await tester.pump();
    final before = bloc.state;

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(bloc.state, before);
    expect(escapesAboveLibrary, 1, reason: 'אין מה להחזיר — Esc עובר הלאה');
  });

  testWidgets('Esc בתוצאות חיפוש משאיר את הספר שנבחר', (tester) async {
    final book = TextBook(title: 'תוצאה');
    final lib = Library(categories: []);
    await pump(
      tester,
      state: LibraryState(
        library: lib,
        currentCategory: lib,
        searchResults: [book],
        searchQuery: 'תוצאה',
        previewBook: book,
      ),
    );

    await tester.tap(find.text('תוצאה').first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(bloc.state.previewBook, same(book));
    expect(bloc.state.previewCategory, isNull);
  });
}
