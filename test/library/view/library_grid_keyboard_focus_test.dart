import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library_update/bloc/library_update_bloc.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/library/view/library_browser.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/widgets/layout/app_card.dart';
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

/// מספק CalendarState קבוע בלי להריץ את אתחול ה-cubit האמיתי.
class _StubCalendarCubit extends Cubit<CalendarState> implements CalendarCubit {
  _StubCalendarCubit(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  testWidgets('חיצים ו-Tab עוברים מהספר שנלחץ לשכנו ומציגים אותו בתצוגה '
      'המקדימה (issue #2010)', (tester) async {
    final library = Library(categories: []);
    final books = [
      for (var i = 0; i < 6; i++) TextBook(title: 'ספר $i', author: 'מחבר'),
    ];
    final libraryBloc = await _pumpBrowser(
      tester,
      LibraryState(
        library: library,
        currentCategory: library,
        searchResults: books,
        searchQuery: 'ספר',
      ),
    );

    await tester.tap(find.text('ספר 1'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_focusedBook(), 'ספר 1', reason: 'החיצים ממשיכים מהספר שנלחץ');

    // RTL: חץ שמאלה = הספר הבא בסדר הקריאה.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(_focusedBook(), 'ספר 2');
    verify(() => libraryBloc.add(SelectBookForPreview(books[2]))).called(1);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_focusedBook(), 'ספר 3');
    verify(() => libraryBloc.add(SelectBookForPreview(books[3]))).called(1);
  });

  testWidgets('Tab ו-Shift+Tab עוברים בכל 300 הכרטיסים בקטגוריה RTL', (
    tester,
  ) async {
    const categoryCount = 4;
    const bookCount = 296;
    final library = Library(categories: []);
    final category = Category(
      title: 'קטגוריה ארוכה',
      description: '',
      shortDescription: '',
      order: 1,
      subCategories: [
        for (var i = 0; i < categoryCount; i++)
          Category(
            title: 'תת-קטגוריה $i',
            description: '',
            shortDescription: '',
            order: i,
            subCategories: [],
            books: [TextBook(title: 'ספר בתיקייה $i', author: 'מחבר')],
            parent: null,
          ),
      ],
      books: [
        for (var i = 0; i < bookCount; i++)
          TextBook(title: 'ספר $i', author: 'מחבר', order: i),
      ],
      parent: library,
    );
    for (final subCategory in category.subCategories) {
      subCategory.parent = category;
    }
    final focusRepository = FocusRepository()
      ..librarySearchController.clear()
      ..librarySearchFocusNode.unfocus();
    await _pumpBrowser(
      tester,
      LibraryState(library: library, currentCategory: category),
      focusRepository: focusRepository,
    );

    final expected = [
      for (var i = 0; i < categoryCount; i++) 'category:תת-קטגוריה $i',
      for (var i = 0; i < bookCount; i++) 'book:ספר $i',
    ];
    focusRepository.librarySearchFocusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_focusedLibraryItem(), expected.first);

    for (var i = 1; i < expected.length; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focusedLibraryItem(), expected[i], reason: 'Tab item $i');
    }

    for (var i = expected.length - 2; i >= 0; i--) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(_focusedLibraryItem(), expected[i], reason: 'Shift+Tab item $i');
    }

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(_focusedLibraryItem(), isNull, reason: 'Shift+Tab יוצא מהרשת');
  });

  for (final scrollable in [false, true]) {
    for (final focusedIndex in [0, 150, 299]) {
      for (final interaction in [
        PointerDeviceKind.mouse,
        PointerDeviceKind.touch,
      ]) {
        testWidgets(
          'אחרי גלילה עם $interaction, ניווט ממוקד $focusedIndex פועל ב-${scrollable ? 'רשת עצלה' : 'רשת מלאה'}',
          (tester) async {
            tester.view.physicalSize = const Size(1400, 700);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final focusNodes = List.generate(300, (_) => FocusNode());
            addTearDown(() {
              for (final node in focusNodes) {
                node.dispose();
              }
            });
            final scrollController = ScrollController();
            addTearDown(scrollController.dispose);
            final grid = MyGridView(
              items: [
                for (var i = 0; i < focusNodes.length; i++)
                  AppCard(
                    onTap: () {},
                    focusNode: focusNodes[i],
                    requestFocusOnTap: true,
                    child: Center(child: Text('ספר $i')),
                  ),
              ],
              scrollable: scrollable,
            );
            await tester.pumpWidget(
              MaterialApp(
                home: Directionality(
                  textDirection: TextDirection.rtl,
                  child: SizedBox(
                    width: 1400,
                    height: 700,
                    child: scrollable
                        ? grid
                        : SingleChildScrollView(
                            controller: scrollController,
                            child: grid,
                          ),
                  ),
                ),
              ),
            );
            await tester.pump();
            final scrollPosition = scrollable
                ? tester
                      .state<ScrollableState>(
                        find.descendant(
                          of: find.byType(MyGridView),
                          matching: find.byType(Scrollable),
                        ),
                      )
                      .position
                : scrollController.position;
            expect(scrollPosition.pixels, 0);

            if (focusedIndex > 0) {
              scrollPosition.jumpTo((focusedIndex ~/ 5 * 137).toDouble());
              await tester.pumpAndSettle();
            }
            await tester.tap(
              find.text('ספר $focusedIndex'),
              kind: interaction,
            );
            await tester.pump();
            expect(focusNodes[focusedIndex].hasFocus, isTrue);

            if (interaction == PointerDeviceKind.mouse) {
              tester.binding.handlePointerEvent(
                PointerScrollEvent(
                  position: Offset(700, 350),
                  scrollDelta: Offset(0, focusedIndex == 299 ? -1000 : 1000),
                  kind: interaction,
                ),
              );
            } else {
              await tester.dragFrom(
                const Offset(700, 350),
                Offset(0, focusedIndex == 299 ? 500 : -500),
              );
            }
            await tester.pumpAndSettle();
            expect(scrollPosition.pixels, greaterThan(0));
            expect(focusNodes[focusedIndex].hasFocus, isTrue);

            final arrow = focusedIndex == 299
                ? LogicalKeyboardKey.arrowRight
                : LogicalKeyboardKey.arrowLeft;
            final nextIndex = focusedIndex == 299
                ? focusedIndex - 1
                : focusedIndex + 1;
            if (scrollable) {
              await tester.sendKeyDownEvent(arrow);
              await tester.sendKeyRepeatEvent(arrow);
              await tester.sendKeyUpEvent(arrow);
            } else {
              await tester.sendKeyEvent(arrow);
            }
            await tester.pumpAndSettle();
            final currentIndex = scrollable
                ? nextIndex + (focusedIndex == 299 ? -1 : 1)
                : nextIndex;
            expect(focusNodes[currentIndex].hasFocus, isTrue);

            if (focusedIndex == 299 || scrollable) {
              await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
            }
            if (scrollable) {
              await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
              await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
            } else {
              await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            }
            if (focusedIndex == 299 || scrollable) {
              await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
            }
            await tester.pumpAndSettle();
            final tabIndex = scrollable || focusedIndex == 299
                ? currentIndex - 1
                : currentIndex + 1;
            expect(focusNodes[tabIndex].hasFocus, isTrue);

            if (scrollable) {
              tester.binding.handlePointerEvent(
                PointerScrollEvent(
                  position: const Offset(700, 350),
                  scrollDelta: Offset(0, focusedIndex == 299 ? -1000 : 1000),
                  kind: PointerDeviceKind.mouse,
                ),
              );
              await tester.pumpAndSettle();
              expect(focusNodes[tabIndex].hasFocus, isTrue);
              expect(focusNodes[focusedIndex].context?.mounted, isFalse);
            }
          },
        );
      }
    }
  }

  testWidgets('קטגוריה ארוכה בונה רק את הכרטיסים שבתצוגה, וחץ-מטה מהחיפוש '
      'אחרי גלילה עמוקה חוזר לספר הראשון', (tester) async {
    const count = 300;
    final library = Library(categories: []);
    final category = Category(
      title: 'קטגוריה',
      description: '',
      shortDescription: '',
      order: 1,
      subCategories: [],
      books: [
        for (var i = 0; i < count; i++)
          TextBook(title: 'ספר $i', author: 'מחבר', order: i),
      ],
      parent: library,
    );
    final focusRepository = FocusRepository();
    await _pumpBrowser(
      tester,
      LibraryState(library: library, currentCategory: category),
      focusRepository: focusRepository,
    );

    final built = find.byType(BookGridItem).evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(count ~/ 5));

    final position = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(MyGridView),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(find.text('ספר 0'), findsNothing);

    focusRepository.requestLibrarySearchFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();
    expect(position.pixels, 0);
    expect(_focusedBook(), 'ספר 0');
  });

  testWidgets('בתצוגת רשימה החיצים עוברים שורה-שורה ולא חוזרים לשורה '
      'הראשונה (issue #3622)', (tester) async {
    final library = Library(categories: []);
    final books = [
      for (var i = 0; i < 5; i++) TextBook(title: 'ספר $i', author: 'מחבר'),
    ];
    final focusRepository = FocusRepository();
    await _pumpBrowser(
      tester,
      LibraryState(
        library: library,
        currentCategory: library,
        searchResults: books,
        searchQuery: 'ספר',
      ),
      focusRepository: focusRepository,
      settingsState: SettingsState.initial().copyWith(libraryViewMode: 'list'),
    );

    focusRepository.requestLibrarySearchFocus();
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_focusedListRow(books), 'ספר $i', reason: 'חץ-מטה מספר ${i + 1}');
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(_focusedListRow(books), 'ספר 2');
  });
}

String? _focusedListRow(List<Book> books) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return null;
  for (final book in books) {
    final inFocused = find.descendant(
      of: find.byElementPredicate((e) => identical(e, focused)),
      matching: find.text(book.title, findRichText: true),
    );
    if (inFocused.evaluate().isNotEmpty) return book.title;
  }
  return null;
}

String? _focusedBook() => FocusManager.instance.primaryFocus?.context
    ?.findAncestorWidgetOfExactType<BookGridItem>()
    ?.book
    .title;

String? _focusedLibraryItem() {
  final context = FocusManager.instance.primaryFocus?.context;
  final category = context?.findAncestorWidgetOfExactType<CategoryGridItem>();
  if (category != null) return 'category:${category.category.title}';
  final book = context?.findAncestorWidgetOfExactType<BookGridItem>();
  if (book != null) return 'book:${book.book.title}';
  return null;
}

/// בונה LibraryBrowser מלא עם blocs מדומים במצב [initialState].
Future<LibraryBloc> _pumpBrowser(
  WidgetTester tester,
  LibraryState initialState, {
  FocusRepository? focusRepository,
  SettingsState? settingsState,
}) async {
  final libraryBloc = _MockLibraryBloc();
  final settingsBloc = _MockSettingsBloc();
  final navigationBloc = _MockNavigationBloc();
  final libraryUpdateBloc = _MockLibraryUpdateBloc();
  final calendarCubit = _StubCalendarCubit(CalendarState.initial());

  whenListen(
    libraryBloc,
    const Stream<LibraryState>.empty(),
    initialState: initialState,
  );
  whenListen(
    settingsBloc,
    const Stream<SettingsState>.empty(),
    initialState: settingsState ?? SettingsState.initial(),
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
  tester.view.physicalSize = const Size(1400, 900);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.reset();
    await libraryBloc.close();
    await settingsBloc.close();
    await navigationBloc.close();
    await libraryUpdateBloc.close();
    await calendarCubit.close();
  });

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('he', 'IL'),
      // כמו באפליקציה — בלי GlobalWidgetsLocalizations הכיוון היה LTR.
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: MultiProvider(
        providers: [
          Provider<FocusRepository>.value(
            value: focusRepository ?? FocusRepository(),
          ),
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
  return libraryBloc;
}
