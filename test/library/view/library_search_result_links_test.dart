import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/hidden/hidden_library_filter.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
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
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/theme/theme_exports.dart';
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

/// החיפוש שרץ שוב בתיקיית היעד אחרי ניווט — בלי מנוע החיפוש האמיתי.
class _Repository extends Fake implements DataRepository {
  @override
  Future<BooksAndCategoriesSearch> findBooksAndCategories(
    String query,
    Category? category, {
    List<String>? topics,
    bool includeOtzar = false,
    bool includeHebrewBooks = false,
    bool includeLocalHebrewBooks = true,
    List<Book> extraBooks = const [],
    bool extraBooksOnly = false,
    bool sortByRatio = true,
    Object? supersedeKey,
    bool reuseCatalog = false,
  }) async => (
    books: const <Book>[],
    categories: const <Category>[],
    bookMatchKinds: const <Book, int>{},
  );
}

/// קישורי הקטגוריה והמחבר בתוצאות האיתור בספרייה (issue #4231).
({Library library, Category halacha, Category tur, List<Book> books})
_library() {
  Category cat(String title, List<Book> books, Category? parent) => Category(
    title: title,
    description: '',
    shortDescription: '',
    order: 1,
    subCategories: [],
    books: books,
    parent: parent,
  );
  final library = Library(categories: []);
  final halacha = cat('הלכה', [], library);
  final tur = cat('טור', [], halacha);
  final books = <Book>[
    TextBook(title: 'ארבעה טורים', author: 'רבי יעקב בן אשר', category: tur),
    TextBook(title: 'בית יוסף', author: 'רבי יוסף קארו', category: tur),
    TextBook(
      title: 'שולחן ערוך',
      author: 'רבי יוסף קארו',
      category: halacha,
    ),
    TextBook(title: 'ערוך השולחן', author: 'רבי יחיאל מיכל', category: halacha),
  ];
  tur.books.addAll(books.take(2));
  halacha.books.addAll(books.skip(2));
  halacha.subCategories.add(tur);
  library.subCategories.add(halacha);
  return (library: library, halacha: halacha, tur: tur, books: books);
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late LibraryBloc libraryBloc;

  Future<({Library library, Category halacha, Category tur, List<Book> books})>
  pump(WidgetTester tester, {bool hideBook = false}) async {
    final data = _library();
    final visibleLibrary = hideBook
        ? filterHiddenFromLibrary(
            data.library,
            HiddenLibrarySelection(
              bookKeys: {PerBookSettings.bookKey(data.books[0])},
            ),
          )
        : data.library;
    libraryBloc = LibraryBloc(repository: _Repository());
    final settingsBloc = _MockSettingsBloc();
    final navigationBloc = _MockNavigationBloc();
    final updateBloc = _MockLibraryUpdateBloc();
    final calendarCubit = _StubCalendarCubit(CalendarState.initial());
    // תוצאות איתור: "בית יוסף" ו"ערוך השולחן".
    libraryBloc.emit(
      LibraryState(
        library: visibleLibrary,
        currentCategory: visibleLibrary,
        searchQuery: 'יוסף',
        searchResults: [data.books[1], data.books[3]],
      ),
    );
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial().copyWith(libraryViewMode: 'list'),
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
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.reset();
      // אירוע שממתין לטיימר של הבדיקה לא יסתיים; לא מחכים לסגירה.
      unawaited(libraryBloc.close());
      await settingsBloc.close();
      await navigationBloc.close();
      await updateBloc.close();
      await calendarCubit.close();
    });

    final cs = AppThemeData.createColorScheme(
      AppSeedColors.defaultLight,
      Brightness.light,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.light(cs, compactMenuMode: false),
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: MultiProvider(
          providers: [
            Provider<FocusRepository>.value(value: FocusRepository()),
            BlocProvider<LibraryBloc>.value(value: libraryBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            BlocProvider<LibraryUpdateBloc>.value(value: updateBloc),
            BlocProvider<CalendarCubit>.value(value: calendarCubit),
            BlocProvider<CustomFoldersBloc>(
              create: (_) => CustomFoldersBloc(addLibraryEvent: (_) {}),
            ),
          ],
          child: const Material(child: LibraryBrowser()),
        ),
      ),
    );
    await tester.pump();
    // כפתור הדף היומי גולש עם CalendarState מדומה — לא נושא הבדיקה.
    tester.takeException();
    return data;
  }

  /// הקישור בשורת הנתיב או המחבר של [bookTitle].
  Finder link(String bookTitle, String text) => find.descendant(
    of: find.ancestor(
      of: find.text(bookTitle),
      matching: find.byType(InkWell),
    ),
    matching: find.text(text),
  );

  /// השורה מחכה ללחיצה כפולה (פתיחה בקורא) לפני שהקישור מקבל את הלחיצה.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pump();
    tester.takeException();
  }

  group(
    'category and author links in library search results (issue #4231)',
    () {
      testWidgets('לחיצה על "טור" בנתיב עוברת לקטגוריה ומסיימת את האיתור', (
        tester,
      ) async {
        final data = await pump(tester);

        await tester.tap(link('בית יוסף', 'טור'));
        await settle(tester);

        expect(libraryBloc.state.currentCategory, same(data.tur));
        expect(libraryBloc.state.searchResults, isNull);
      });

      testWidgets('קישור למדף משתמש בעץ המסונן ואינו מציג ספר מוסתר', (
        tester,
      ) async {
        final data = await pump(tester, hideBook: true);
        final visibleShelf = libraryBloc
            .state
            .library!
            .subCategories
            .single
            .subCategories
            .single;
        expect(visibleShelf.books, [data.books[1]]);

        await tester.tap(link('בית יוסף', 'טור'));
        await settle(tester);

        expect(libraryBloc.state.currentCategory, same(visibleShelf));
        expect(libraryBloc.state.searchQuery, isEmpty);
        expect(find.text(data.books[0].title), findsNothing);
      });

      testWidgets('לחיצה על "הלכה" בנתיב עוברת לקטגוריית האב', (tester) async {
        final data = await pump(tester);

        await tester.tap(link('בית יוסף', 'הלכה'));
        await settle(tester);

        expect(libraryBloc.state.currentCategory, same(data.halacha));
      });

      testWidgets('לחיצה על המחבר מציגה את כל ספריו, וצ\'יפ מנקה', (
        tester,
      ) async {
        final data = await pump(tester);

        expect(find.text('שולחן ערוך'), findsNothing);
        await tester.tap(link('בית יוסף', 'רבי יוסף קארו'));
        await settle(tester);

        expect(libraryBloc.state.authorFilter, 'רבי יוסף קארו');
        expect(
          libraryBloc.state.searchResults,
          unorderedEquals([data.books[1], data.books[2]]),
        );
        expect(find.text('מחבר: רבי יוסף קארו'), findsOneWidget);
        expect(find.text('שולחן ערוך'), findsOneWidget);
        expect(find.text('ערוך השולחן'), findsNothing);

        await tester.tap(find.byTooltip('נקה סינון'));
        await settle(tester);

        expect(libraryBloc.state.authorFilter, isNull);
        expect(libraryBloc.state.searchResults, isNull);
        expect(find.text('מחבר: רבי יוסף קארו'), findsNothing);
      });

      testWidgets('Enter על קישור ממוקד מפעיל אותו ולא את השורה', (
        tester,
      ) async {
        final data = await pump(tester);

        Focus.of(tester.element(link('בית יוסף', 'טור'))).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await settle(tester);

        expect(libraryBloc.state.currentCategory, same(data.tur));
      });

      testWidgets('Tab מהשורה מגיע לקישורי המחבר והקטגוריה, ו-Enter מפעיל', (
        tester,
      ) async {
        final data = await pump(tester);
        bool focusedOn(String text) =>
            FocusManager.instance.primaryFocus ==
            Focus.of(tester.element(link('בית יוסף', text)));

        Focus.of(tester.element(find.text('בית יוסף'))).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(focusedOn('רבי יוסף קארו'), isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(focusedOn('הלכה'), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(focusedOn('טור'), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await settle(tester);
        expect(libraryBloc.state.currentCategory, same(data.tur));
      });

      testWidgets('Enter על קישור המחבר שהגיעו אליו במקלדת מציג את ספריו', (
        tester,
      ) async {
        await pump(tester);

        Focus.of(tester.element(find.text('בית יוסף'))).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await settle(tester);

        expect(libraryBloc.state.authorFilter, 'רבי יוסף קארו');
      });

      testWidgets('לחיצה על השורה עצמה עדיין בוחרת את הספר', (tester) async {
        final data = await pump(tester);

        await tester.tap(find.text('ערוך השולחן'));
        await settle(tester);

        expect(libraryBloc.state.previewBook, same(data.books[3]));
        expect(libraryBloc.state.currentCategory, same(data.library));
        expect(libraryBloc.state.authorFilter, isNull);
        expect(libraryBloc.state.searchResults, isNotNull);
      });
    },
  );
}
