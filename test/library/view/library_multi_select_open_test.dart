import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library_navigation_history.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/library_browser.dart';
import 'package:otzaria/library/view/otzar_book_dialog.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
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

class _MockTabsBloc extends MockBloc<TabsEvent, TabsState>
    implements TabsBloc {}

class _MockHistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {}

class _StubCalendarCubit extends Cubit<CalendarState> implements CalendarCubit {
  _StubCalendarCubit(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  final libraryBloc = _MockLibraryBloc();
  final libraryStates = StreamController<LibraryState>.broadcast();
  final navigationBloc = _MockNavigationBloc();
  final tabsBloc = _MockTabsBloc();
  final historyBloc = _MockHistoryBloc();

  /// הספרים שנפתחו, לפי סדר האירועים שהגיעו ל-TabsBloc.
  List<String> openedTitles() => verify(
    () => tabsBloc.add(captureAny()),
  ).captured.whereType<OpenOrFocusTab>().map((e) => e.tab.title).toList();
}

Future<_Harness> _pumpBrowser(
  WidgetTester tester, {
  required List<Book> books,
  required String viewMode,
  List<OpenedTab> openTabs = const [],
  List<Book>? searchResults,
  bool previewEnabled = false,
}) async {
  final h = _Harness();
  final library = Library(categories: [])..books.addAll(books);
  final settingsBloc = _MockSettingsBloc();
  final libraryUpdateBloc = _MockLibraryUpdateBloc();
  final calendarCubit = _StubCalendarCubit(CalendarState.initial());

  whenListen(
    h.libraryBloc,
    h.libraryStates.stream,
    initialState: LibraryState(
      library: library,
      currentCategory: library,
      searchResults: searchResults,
    ),
  );
  whenListen(
    settingsBloc,
    const Stream<SettingsState>.empty(),
    initialState: SettingsState.initial().copyWith(
      libraryViewMode: viewMode,
      libraryShowPreview: previewEnabled,
    ),
  );
  whenListen(
    h.navigationBloc,
    const Stream<NavigationState>.empty(),
    initialState: const NavigationState(currentScreen: Screen.library),
  );
  whenListen(
    libraryUpdateBloc,
    const Stream<LibraryUpdateState>.empty(),
    initialState: const LibraryUpdateState(),
  );
  whenListen(
    h.tabsBloc,
    const Stream<TabsState>.empty(),
    initialState: TabsState(tabs: openTabs, currentTabIndex: 0),
  );
  whenListen(
    h.historyBloc,
    const Stream<HistoryState>.empty(),
    initialState: HistoryInitial(),
  );

  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 900);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.reset();
    await h.libraryStates.close();
    await settingsBloc.close();
    await h.navigationBloc.close();
    await libraryUpdateBloc.close();
    await h.tabsBloc.close();
    await h.historyBloc.close();
    await calendarCubit.close();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<FocusRepository>.value(value: FocusRepository()),
        BlocProvider<LibraryBloc>(create: (_) => h.libraryBloc),
        BlocProvider<SettingsBloc>.value(value: settingsBloc),
        BlocProvider<NavigationBloc>.value(value: h.navigationBloc),
        BlocProvider<LibraryUpdateBloc>.value(value: libraryUpdateBloc),
        BlocProvider<CalendarCubit>.value(value: calendarCubit),
        BlocProvider<TabsBloc>.value(value: h.tabsBloc),
        BlocProvider<HistoryBloc>.value(value: h.historyBloc),
        BlocProvider<CustomFoldersBloc>(
          create: (_) => CustomFoldersBloc(addLibraryEvent: (_) {}),
        ),
      ],
      child: MaterialApp(
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const LibraryBrowser(),
      ),
    ),
  );
  await tester.pump();
  // כפתור הדף היומי גולש עם CalendarState מדומה — לא נושא הבדיקה.
  tester.takeException();
  return h;
}

Future<void> _tapWith(
  WidgetTester tester,
  Finder finder, {
  LogicalKeyboardKey? holding,
}) async {
  if (holding != null) await tester.sendKeyDownEvent(holding);
  await tester.tap(finder);
  // המקש משתחרר מיד אחרי הלחיצה, כמו ביד אנושית — לפני שחלון הלחיצה הכפולה
  // (שמעכב לחיצה בודדת) נסגר.
  if (holding != null) await tester.sendKeyUpEvent(holding);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    registerFallbackValue(const NavigateToScreen(Screen.reading));
    registerFallbackValue(const SelectTopics([]));
    registerFallbackValue(const ClearTabSelection());
    registerFallbackValue(CloseAllTabs());
    registerFallbackValue(
      CaptureStateForHistory(
        TextBookTab(book: TextBook(title: 'fallback'), index: 0),
      ),
    );
  });

  for (final mode in ['list', 'grid']) {
    group('פתיחת ספרים מרובים, תצוגת $mode (issue #2034)', () {
      late List<Book> books;

      setUp(() {
        books = [
          TextBook(title: 'ספר א'),
          TextBook(title: 'ספר ב'),
          TextBook(title: 'ספר ג'),
          TextBook(title: 'ספר ד'),
        ];
      });

      testWidgets(
        'Ctrl+לחיצה בוחרת בלי לפתוח, ו"פתח נבחרים" פותח לפי סדר הבחירה '
        'ועובר למסך הקריאה פעם אחת',
        (tester) async {
          final h = await _pumpBrowser(tester, books: books, viewMode: mode);

          await _tapWith(
            tester,
            find.text('ספר ג'),
            holding: LogicalKeyboardKey.controlLeft,
          );
          await _tapWith(
            tester,
            find.text('ספר א'),
            holding: LogicalKeyboardKey.controlLeft,
          );

          expect(find.text('2 ספרים נבחרו'), findsOneWidget);
          verifyNever(() => h.tabsBloc.add(any()));

          await tester.tap(find.text('פתח נבחרים'));
          await tester.pumpAndSettle();

          expect(h.openedTitles(), ['ספר ג', 'ספר א']);
          verify(
            () => h.navigationBloc.add(const NavigateToScreen(Screen.reading)),
          ).called(1);
          expect(find.text('פתח נבחרים'), findsNothing);
        },
      );

      testWidgets('regression: deselection keeps the existing preview', (
        tester,
      ) async {
        final h = await _pumpBrowser(
          tester,
          books: books,
          viewMode: mode,
          previewEnabled: true,
        );
        h.libraryStates.add(
          h.libraryBloc.state.copyWith(previewBook: books.first),
        );
        await tester.pump();
        await _tapWith(
          tester,
          find.text('ספר ב'),
          holding: LogicalKeyboardKey.controlLeft,
        );
        final focusRepository = tester
            .element(find.byType(LibraryBrowser))
            .read<FocusRepository>();
        focusRepository.librarySearchFocusNode.requestFocus();
        await tester.pump();
        clearInteractions(h.libraryBloc);
        await _tapWith(
          tester,
          find.text('ספר ב'),
          holding: LogicalKeyboardKey.controlLeft,
        );
        expect(find.text('פתח נבחרים'), findsNothing);
        verifyNever(
          () => h.libraryBloc.add(any(that: isA<SelectBookForPreview>())),
        );
        verifyNever(() => h.tabsBloc.add(any()));
      });

      if (mode == 'grid') {
        for (final refocusBeforeDeselect in [false, true]) {
          testWidgets(
            'regression: keyboard focus after deselection still previews '
            '(refocus=$refocusBeforeDeselect)',
            (tester) async {
              final h = await _pumpBrowser(
                tester,
                books: books,
                viewMode: mode,
                previewEnabled: true,
              );
              await _tapWith(
                tester,
                find.text('ספר ב'),
                holding: LogicalKeyboardKey.controlLeft,
              );
              final searchFocus = tester
                  .element(find.byType(LibraryBrowser))
                  .read<FocusRepository>()
                  .librarySearchFocusNode;
              if (refocusBeforeDeselect) {
                searchFocus.requestFocus();
                await tester.pump();
              }
              await _tapWith(
                tester,
                find.text('ספר ב'),
                holding: LogicalKeyboardKey.controlLeft,
              );
              expect(find.text('פתח נבחרים'), findsNothing);
              searchFocus.requestFocus();
              await tester.pump();
              clearInteractions(h.libraryBloc);
              Focus.of(tester.element(find.text('ספר ב'))).requestFocus();
              await tester.pump();
              verify(
                () => h.libraryBloc.add(any(that: isA<SelectBookForPreview>())),
              ).called(1);
            },
          );
        }
      }

      for (final previewEnabled in [false, true]) {
        testWidgets('regression: Enter opens Ctrl/Shift selection, '
            'preview=$previewEnabled', (tester) async {
          final h = await _pumpBrowser(
            tester,
            books: books,
            viewMode: mode,
            previewEnabled: previewEnabled,
            openTabs: [TextBookTab(book: TextBook(title: 'פתוח'), index: 0)],
          );
          await _tapWith(
            tester,
            find.text('ספר ב'),
            holding: LogicalKeyboardKey.controlLeft,
          );
          await _tapWith(
            tester,
            find.text('ספר ד'),
            holding: LogicalKeyboardKey.shiftLeft,
          );
          // Focus a book outside the selection: Enter acts on the selection.
          Focus.of(tester.element(find.text('ספר א'))).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(h.openedTitles(), ['ספר ב', 'ספר ג', 'ספר ד']);
          expect(find.text('פתח נבחרים'), findsNothing);
          verify(
            () => h.historyBloc.add(any(that: isA<CaptureStateForHistory>())),
          ).called(1);
          verify(
            () => h.navigationBloc.add(const NavigateToScreen(Screen.reading)),
          ).called(1);
        });

        testWidgets('regression: Enter with search focus opens selection, '
            'preview=$previewEnabled', (tester) async {
          final h = await _pumpBrowser(
            tester,
            books: books,
            viewMode: mode,
            previewEnabled: previewEnabled,
          );
          await _tapWith(
            tester,
            find.text('ספר א'),
            holding: LogicalKeyboardKey.controlLeft,
          );
          await _tapWith(
            tester,
            find.text('ספר ב'),
            holding: LogicalKeyboardKey.controlLeft,
          );
          tester
              .element(find.byType(LibraryBrowser))
              .read<FocusRepository>()
              .librarySearchFocusNode
              .requestFocus();
          await tester.pump();
          await tester.testTextInput.receiveAction(TextInputAction.search);
          await tester.pumpAndSettle();
          expect(h.openedTitles(), ['ספר א', 'ספר ב']);
          expect(find.text('פתח נבחרים'), findsNothing);
        });

        testWidgets('regression: single click keeps preview/open behavior, '
            'preview=$previewEnabled', (tester) async {
          final h = await _pumpBrowser(
            tester,
            books: books,
            viewMode: mode,
            previewEnabled: previewEnabled,
          );
          await _tapWith(tester, find.text('ספר ב'));
          expect(find.text('פתח נבחרים'), findsNothing);
          if (previewEnabled) {
            verify(
              () => h.libraryBloc.add(any(that: isA<SelectBookForPreview>())),
            ).called(greaterThanOrEqualTo(1));
            verifyNever(() => h.tabsBloc.add(any()));
          } else {
            expect(h.openedTitles(), ['ספר ב']);
          }
        });

        testWidgets('regression: double click opens one book, '
            'preview=$previewEnabled', (tester) async {
          final h = await _pumpBrowser(
            tester,
            books: books,
            viewMode: mode,
            previewEnabled: previewEnabled,
          );
          await tester.tap(find.text('ספר ב'));
          await tester.pump(const Duration(milliseconds: 50));
          await tester.tap(find.text('ספר ב'));
          await tester.pumpAndSettle();
          expect(find.text('פתח נבחרים'), findsNothing);
          expect(h.openedTitles(), ['ספר ב']);
        });

        testWidgets('regression: canceled/dragged selection does not affect '
            'the next click, preview=$previewEnabled', (tester) async {
          final h = await _pumpBrowser(
            tester,
            books: books,
            viewMode: mode,
            previewEnabled: previewEnabled,
          );
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          final canceled = await tester.startGesture(
            tester.getCenter(find.text('ספר ב')),
          );
          await canceled.cancel();
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pump();
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          final dragged = await tester.startGesture(
            tester.getCenter(find.text('ספר ב')),
          );
          await dragged.moveBy(const Offset(0, -80));
          await dragged.up();
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.pumpAndSettle();
          expect(find.text('פתח נבחרים'), findsNothing);
          await _tapWith(tester, find.text('ספר ב'));
          expect(find.text('פתח נבחרים'), findsNothing);
          if (previewEnabled) {
            verifyNever(() => h.tabsBloc.add(any()));
          } else {
            expect(h.openedTitles(), ['ספר ב']);
          }
        });

        testWidgets('regression: rapid modifier clicks keep their own gesture, '
            'preview=$previewEnabled', (tester) async {
          final h = await _pumpBrowser(
            tester,
            books: books,
            viewMode: mode,
            previewEnabled: previewEnabled,
          );
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.tap(find.text('ספר א'));
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pump(const Duration(milliseconds: 50));
          await tester.tap(find.text('ספר ב'));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump();
          expect(find.text('2 ספרים נבחרו'), findsOneWidget);
          verifyNever(() => h.tabsBloc.add(any()));
          await tester.tap(find.text('פתח נבחרים'));
          await tester.pumpAndSettle();
          expect(h.openedTitles(), ['ספר א', 'ספר ב']);
        });
      }

      testWidgets(
        'כשיש טאב פתוח, ההיסטוריה נלכדת פעם אחת בלבד לכל הפתיחה המרובה',
        (tester) async {
          final h = await _pumpBrowser(
            tester,
            books: books,
            viewMode: mode,
            openTabs: [TextBookTab(book: TextBook(title: 'פתוח'), index: 0)],
          );

          for (final title in ['ספר א', 'ספר ב', 'ספר ג']) {
            await _tapWith(
              tester,
              find.text(title),
              holding: LogicalKeyboardKey.controlLeft,
            );
          }
          await tester.tap(find.text('פתח נבחרים'));
          await tester.pumpAndSettle();

          verify(
            () => h.historyBloc.add(any(that: isA<CaptureStateForHistory>())),
          ).called(1);
          expect(h.openedTitles(), ['ספר א', 'ספר ב', 'ספר ג']);
        },
      );

      testWidgets(
        'כשיש בחירה, לחיצה רגילה מחליפה את מצב הספר ולא פותחת אותו',
        (tester) async {
          final h = await _pumpBrowser(tester, books: books, viewMode: mode);

          await _tapWith(
            tester,
            find.text('ספר ב'),
            holding: LogicalKeyboardKey.controlLeft,
          );
          await _tapWith(tester, find.text('ספר ג'));
          expect(find.text('2 ספרים נבחרו'), findsOneWidget);

          await _tapWith(tester, find.text('ספר ב'));
          expect(find.text('ספר אחד נבחר'), findsOneWidget);
          verifyNever(() => h.tabsBloc.add(any()));
        },
      );

      testWidgets(
        'Ctrl משוחרר מיד אחרי הלחיצה, לפני סגירת חלון הלחיצה הכפולה: '
        'הספר נבחר ולא נפתח',
        (tester) async {
          final h = await _pumpBrowser(tester, books: books, viewMode: mode);

          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.tap(find.text('ספר ב'));
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump();

          expect(find.text('ספר אחד נבחר'), findsOneWidget);
          verifyNever(() => h.tabsBloc.add(any()));
        },
      );

      for (final modifier in [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.metaLeft,
      ]) {
        for (final key in [
          LogicalKeyboardKey.enter,
          LogicalKeyboardKey.numpadEnter,
          LogicalKeyboardKey.space,
        ]) {
          testWidgets(
            '${modifier.keyLabel}+לחיצה, שחרור, Esc ואז ${key.keyLabel} '
            'פותח מיד בלי להשתמש במקשי העכבר',
            (tester) async {
              final h = await _pumpBrowser(
                tester,
                books: books,
                viewMode: mode,
              );
              await _tapWith(tester, find.text('ספר ב'), holding: modifier);
              expect(find.text('ספר אחד נבחר'), findsOneWidget);
              Focus.of(tester.element(find.text('ספר ב'))).requestFocus();
              await tester.pump();
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
              await tester.pump();
              expect(find.text('ספר אחד נבחר'), findsNothing);

              await tester.sendKeyEvent(key);
              await tester.pump();
              expect(find.text('ספר אחד נבחר'), findsNothing);
              expect(h.openedTitles(), ['ספר ב']);
            },
          );
        }
      }

      testWidgets('רענון עץ משמר PDF מקומי מתוצאות חיפוש ומחליף מופעי ספרים', (
        tester,
      ) async {
        final local = PdfBook(
          title: 'היברובוקס מקומי',
          path: '/books/hb.pdf',
          externalLibraryId: 'hb:77',
        );
        final replacement = PdfBook(
          title: local.title,
          path: local.path,
          externalLibraryId: local.externalLibraryId,
        );
        DataRepository.instance.localHebrewBooks = Future.value([replacement]);
        addTearDown(DataRepository.instance.invalidateHebrewBooksCache);
        final h = await _pumpBrowser(
          tester,
          books: books,
          viewMode: mode,
          searchResults: [local, books.first],
        );
        await _tapWith(
          tester,
          find.text(local.title),
          holding: LogicalKeyboardKey.controlLeft,
        );
        await _tapWith(
          tester,
          find.text(books.first.title),
          holding: LogicalKeyboardKey.controlLeft,
        );
        final updated = TextBook(title: books.first.title);
        final library = Library(categories: [])..books.add(updated);
        h.libraryStates.add(
          h.libraryBloc.state.copyWith(
            library: library,
            currentCategory: library,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('2 ספרים נבחרו'), findsOneWidget);
        await tester.tap(find.text('פתח נבחרים'));
        await tester.pumpAndSettle();
        final tabs = verify(() => h.tabsBloc.add(captureAny())).captured
            .whereType<OpenOrFocusTab>()
            .map((event) => event.tab)
            .toList();
        expect(tabs.map((tab) => tab.title), [local.title, updated.title]);
        expect((tabs.first as PdfBookTab).book, same(replacement));
        expect((tabs.last as TextBookTab).book, same(updated));
      });

      testWidgets('Enter רגיל אחרי ביטול בחירה במקלדת פותח את הספר', (
        tester,
      ) async {
        final h = await _pumpBrowser(tester, books: books, viewMode: mode);
        await _tapWith(
          tester,
          find.text('ספר ב'),
          holding: LogicalKeyboardKey.controlLeft,
        );
        Focus.of(tester.element(find.text('ספר ב'))).requestFocus();
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(find.text('ספר אחד נבחר'), findsNothing);
        verifyNever(() => h.tabsBloc.add(any()));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(find.text('ספר אחד נבחר'), findsNothing);
        expect(h.openedTitles(), ['ספר ב']);
      });

      for (final previewEnabled in [false, true]) {
        testWidgets('Enter בזמן בחירה פותח את הנבחרים '
            '(תצוגה מקדימה: $previewEnabled)', (tester) async {
          final h = await _pumpBrowser(
            tester,
            books: books,
            viewMode: mode,
            previewEnabled: previewEnabled,
          );
          await _tapWith(
            tester,
            find.text('ספר ב'),
            holding: LogicalKeyboardKey.controlLeft,
          );
          Focus.of(tester.element(find.text('ספר ב'))).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(find.text('ספר אחד נבחר'), findsNothing);
          expect(h.openedTitles(), ['ספר ב']);
        });
      }

      group('השלמת בחירה אחרי רענון אסינכרוני', () {
        late PdfBook local;
        setUp(() {
          local = PdfBook(
            title: 'היברובוקס מקומי',
            id: 77,
            path: '/books/hb.pdf',
            externalLibraryId: 'hb:77',
          );
        });
        tearDown(() => DataRepository.instance.invalidateHebrewBooksCache());
        LibraryState refreshed(_Harness h, List<Book> currentBooks) {
          final library = Library(categories: [])..books.addAll(currentBooks);
          return h.libraryBloc.state.copyWith(
            library: library,
            currentCategory: library,
            searchResults: [local, ...currentBooks],
          );
        }

        testWidgets('כשל טעינת המטא־דאטה אינו מוחק בחירה או מדליף שגיאה', (
          tester,
        ) async {
          final h = await _pumpBrowser(
            tester,
            books: books,
            viewMode: mode,
            searchResults: [local],
          );
          await _tapWith(
            tester,
            find.text(local.title),
            holding: LogicalKeyboardKey.controlLeft,
          );
          final scan = Completer<List<Book>>();
          DataRepository.instance.localHebrewBooks = scan.future;
          h.libraryStates.add(refreshed(h, books));
          await tester.pump();
          scan.completeError(StateError('catalog unavailable'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('ספר אחד נבחר'), findsOneWidget);
          await tester.tap(find.text('פתח נבחרים'));
          await tester.pumpAndSettle();
          expect(h.openedTitles(), [local.title]);
        });

        testWidgets('PDF שנמחק מוסר בלי להחליף PDF ספרייה בעל אותו id', (
          tester,
        ) async {
          final pdf = PdfBook(
            title: 'PDF ספרייה',
            id: local.id,
            path: '/books/library.pdf',
          );
          final h = await _pumpBrowser(
            tester,
            books: [pdf],
            viewMode: mode,
            searchResults: [local, pdf],
          );
          for (final title in [local.title, pdf.title]) {
            await _tapWith(
              tester,
              find.text(title),
              holding: LogicalKeyboardKey.controlLeft,
            );
          }
          final updated = PdfBook(title: pdf.title, id: pdf.id, path: pdf.path);
          DataRepository.instance.localHebrewBooks = Future.value([]);
          h.libraryStates.add(refreshed(h, [updated]));
          await tester.pumpAndSettle();
          expect(find.text('ספר אחד נבחר'), findsOneWidget);
          await tester.tap(find.text('פתח נבחרים'));
          await tester.pumpAndSettle();
          final event = verify(
            () => h.tabsBloc.add(captureAny()),
          ).captured.whereType<OpenOrFocusTab>().single;
          expect((event.tab as PdfBookTab).book, same(updated));
        });
        testWidgets('רענון ישן שמסתיים מאוחר לא מחזיר ספר שנמחק', (
          tester,
        ) async {
          final h = await _pumpBrowser(
            tester,
            books: books,
            viewMode: mode,
            searchResults: [local, books.first],
          );
          for (final title in [local.title, books.first.title]) {
            await _tapWith(
              tester,
              find.text(title),
              holding: LogicalKeyboardKey.controlLeft,
            );
          }
          final oldScan = Completer<List<Book>>();
          DataRepository.instance.localHebrewBooks = oldScan.future;
          h.libraryStates.add(
            refreshed(h, [TextBook(title: books.first.title)]),
          );
          await tester.pump();
          final latest = TextBook(title: books.first.title);
          DataRepository.instance.localHebrewBooks = Future.value([]);
          h.libraryStates.add(refreshed(h, [latest]));
          await tester.pumpAndSettle();
          expect(find.text('ספר אחד נבחר'), findsOneWidget);
          oldScan.complete([local]);
          await tester.pumpAndSettle();
          expect(find.text('ספר אחד נבחר'), findsOneWidget);
          await tester.tap(find.text('פתח נבחרים'));
          await tester.pumpAndSettle();
          final event = verify(
            () => h.tabsBloc.add(captureAny()),
          ).captured.whereType<OpenOrFocusTab>().single;
          expect((event.tab as TextBookTab).book, same(latest));
        });
        for (final selectAgain in [false, true]) {
          testWidgets('Esc בזמן המתנה אינו מחזיר בחירה ישנה '
              '(בחירה חדשה: $selectAgain)', (tester) async {
            final h = await _pumpBrowser(
              tester,
              books: books,
              viewMode: mode,
              searchResults: [local, ...books],
            );
            await _tapWith(
              tester,
              find.text(local.title),
              holding: LogicalKeyboardKey.controlLeft,
            );
            final scan = Completer<List<Book>>();
            DataRepository.instance.localHebrewBooks = scan.future;
            final updated = TextBook(title: books.first.title);
            h.libraryStates.add(refreshed(h, [updated]));
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pump();
            if (selectAgain) {
              await _tapWith(
                tester,
                find.text(updated.title),
                holding: LogicalKeyboardKey.controlLeft,
              );
            }
            scan.complete([local]);
            await tester.pumpAndSettle();
            if (selectAgain) {
              expect(find.text('ספר אחד נבחר'), findsOneWidget);
              await tester.tap(find.text('פתח נבחרים'));
              await tester.pumpAndSettle();
              expect(h.openedTitles(), [updated.title]);
            } else {
              expect(find.text('פתח נבחרים'), findsNothing);
              verifyNever(() => h.tabsBloc.add(any()));
            }
          });
        }
        testWidgets('סגירת הספרייה בזמן המתנה אינה משתמשת ב־context שנסגר', (
          tester,
        ) async {
          final h = await _pumpBrowser(
            tester,
            books: books,
            viewMode: mode,
            searchResults: [local],
          );
          await _tapWith(
            tester,
            find.text(local.title),
            holding: LogicalKeyboardKey.controlLeft,
          );
          final scan = Completer<List<Book>>();
          DataRepository.instance.localHebrewBooks = scan.future;
          h.libraryStates.add(refreshed(h, books));
          await tester.pump();
          await tester.pumpWidget(const SizedBox.shrink());
          scan.complete([local]);
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      });

      // בשורת רשימה לחיצה לא מעבירה פוקוס; גולש המקלדת מגיע אליה ב-Tab.
      testWidgets(
        'Ctrl+Enter על כרטיס ממוקד מחליף את מצבו בלי עכבר, ו-Enter רגיל לא',
        (tester) async {
          final h = await _pumpBrowser(tester, books: books, viewMode: mode);

          await _tapWith(
            tester,
            find.text('ספר ב'),
            holding: LogicalKeyboardKey.controlLeft,
          );
          expect(find.text('ספר אחד נבחר'), findsOneWidget);

          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('ספר אחד נבחר'), findsNothing);

          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('ספר אחד נבחר'), findsOneWidget);
          verifyNever(() => h.tabsBloc.add(any()));
        },
        skip: mode != 'grid',
      );

      for (final previewEnabled in [false, true]) {
        testWidgets('Ctrl/Meta+Enter/Space ו־Shift+Enter שומרים על בחירה וטווח '
            '(תצוגה מקדימה: $previewEnabled)', (tester) async {
          final h = await _pumpBrowser(
            tester,
            books: books,
            viewMode: mode,
            previewEnabled: previewEnabled,
          );
          Future<void> activate(
            String title,
            LogicalKeyboardKey modifier,
            LogicalKeyboardKey key,
          ) async {
            Focus.of(tester.element(find.text(title))).requestFocus();
            await tester.pump();
            await tester.sendKeyDownEvent(modifier);
            await tester.sendKeyEvent(key);
            await tester.sendKeyUpEvent(modifier);
            await tester.pump();
          }

          await activate(
            'ספר ב',
            LogicalKeyboardKey.controlLeft,
            LogicalKeyboardKey.enter,
          );
          expect(find.text('ספר אחד נבחר'), findsOneWidget);
          await activate(
            'ספר ד',
            LogicalKeyboardKey.shiftLeft,
            LogicalKeyboardKey.enter,
          );
          expect(find.text('3 ספרים נבחרו'), findsOneWidget);
          await activate(
            'ספר ג',
            LogicalKeyboardKey.metaLeft,
            LogicalKeyboardKey.space,
          );
          expect(find.text('2 ספרים נבחרו'), findsOneWidget);
          await activate(
            'ספר א',
            LogicalKeyboardKey.controlLeft,
            LogicalKeyboardKey.space,
          );
          expect(find.text('3 ספרים נבחרו'), findsOneWidget);
          await activate(
            'ספר ב',
            LogicalKeyboardKey.metaLeft,
            LogicalKeyboardKey.enter,
          );
          expect(find.text('2 ספרים נבחרו'), findsOneWidget);
          verifyNever(() => h.tabsBloc.add(any()));
        });
      }

      testWidgets('Shift+לחיצה בוחרת טווח לפי סדר התצוגה', (tester) async {
        await _pumpBrowser(tester, books: books, viewMode: mode);

        await _tapWith(
          tester,
          find.text('ספר ב'),
          holding: LogicalKeyboardKey.controlLeft,
        );
        await _tapWith(
          tester,
          find.text('ספר ד'),
          holding: LogicalKeyboardKey.shiftLeft,
        );

        expect(find.text('3 ספרים נבחרו'), findsOneWidget);
      });

      testWidgets('Esc ו"ביטול בחירה" מנקים את הבחירה', (tester) async {
        await _pumpBrowser(tester, books: books, viewMode: mode);

        await _tapWith(
          tester,
          find.text('ספר א'),
          holding: LogicalKeyboardKey.controlLeft,
        );
        expect(find.text('ספר אחד נבחר'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(find.text('ספר אחד נבחר'), findsNothing);

        await _tapWith(
          tester,
          find.text('ספר א'),
          holding: LogicalKeyboardKey.controlLeft,
        );
        await tester.tap(find.text('ביטול בחירה'));
        await tester.pump();
        expect(find.text('ספר אחד נבחר'), findsNothing);
      });
    });

    // PDF, היברובוקס מקומי (PDF שהורד), ואוצר החכמה / היברובוקס מקוון / ספק
    // מתוסף כמו בר-אילן, שנפתחים בדיאלוג או בפעולת תוסף ולא כטאב.
    group('סוגי ספרים שונים, תצוגת $mode (issue #2034)', () {
      late Book text;
      late Book pdf;
      late Book localHebrewBook;
      late ExternalLibraryBook otzar;
      late ExternalLibraryBook onlineHebrewBook;
      late ExternalLibraryBook pluginBook;

      setUp(() {
        text = TextBook(title: 'טקסט');
        pdf = PdfBook(title: 'פי-די-אף', path: r'C:\books\a.pdf');
        localHebrewBook = PdfBook(
          title: 'היברובוקס מקומי',
          path: r'C:\books\hb.pdf',
          externalLibraryId: 'hb:77',
        );
        otzar = ExternalLibraryBook(
          title: 'אוצר החכמה',
          id: 5,
          link: 'https://tablet.otzar.org/book/book.php?book=5',
          externalLibraryId: 'oh:5',
        );
        onlineHebrewBook = ExternalLibraryBook(
          title: 'היברובוקס מקוון',
          id: 6,
          link: 'https://hebrewbooks.org/6',
          externalLibraryId: 'hb:6',
        );
        pluginBook = ExternalLibraryBook(
          title: 'בר-אילן',
          id: 7,
          link: '',
          externalLibraryId: 'bar-ilan:7',
        );
      });

      testWidgets('טקסט, PDF והיברובוקס מקומי נפתחים יחד לפי סדר הבחירה, '
          'כל אחד בטאב מהסוג שלו', (tester) async {
        final h = await _pumpBrowser(
          tester,
          books: [text, pdf, localHebrewBook],
          viewMode: mode,
        );

        for (final title in ['היברובוקס מקומי', 'טקסט', 'פי-די-אף']) {
          await _tapWith(
            tester,
            find.text(title),
            holding: LogicalKeyboardKey.controlLeft,
          );
        }
        await tester.tap(find.text('פתח נבחרים'));
        await tester.pumpAndSettle();

        final tabs = verify(
          () => h.tabsBloc.add(captureAny()),
        ).captured.whereType<OpenOrFocusTab>().map((e) => e.tab).toList();
        expect(tabs.map((t) => t.title), [
          'היברובוקס מקומי',
          'טקסט',
          'פי-די-אף',
        ]);
        expect(tabs[0], isA<PdfBookTab>());
        expect(tabs[1], isA<TextBookTab>());
        expect(tabs[2], isA<PdfBookTab>());
        verify(
          () => h.navigationBloc.add(const NavigateToScreen(Screen.reading)),
        ).called(1);
      });

      testWidgets('ספרים חיצוניים אינם נבחרים ואינם פותחים דיאלוג בזמן בחירה', (
        tester,
      ) async {
        final h = await _pumpBrowser(
          tester,
          books: [text, otzar, onlineHebrewBook, pluginBook],
          viewMode: mode,
        );

        for (final title in ['אוצר החכמה', 'היברובוקס מקוון', 'בר-אילן']) {
          await _tapWith(
            tester,
            find.text(title),
            holding: LogicalKeyboardKey.controlLeft,
          );
          await _tapWith(
            tester,
            find.text(title),
            holding: LogicalKeyboardKey.shiftLeft,
          );
        }
        expect(find.text('פתח נבחרים'), findsNothing);
        expect(find.byType(OtzarBookDialog), findsNothing);

        // עם בחירה פעילה גם לחיצה רגילה על ספר חיצוני לא עושה כלום.
        await _tapWith(
          tester,
          find.text('טקסט'),
          holding: LogicalKeyboardKey.controlLeft,
        );
        await _tapWith(tester, find.text('היברובוקס מקוון'));
        expect(find.byType(OtzarBookDialog), findsNothing);
        expect(find.text('ספר אחד נבחר'), findsOneWidget);
        verifyNever(() => h.tabsBloc.add(any()));
      });

      testWidgets('ספר חיצוני בלחיצה רגילה בלי בחירה נפתח כמו קודם', (
        tester,
      ) async {
        await _pumpBrowser(
          tester,
          books: [text, onlineHebrewBook],
          viewMode: mode,
        );

        await _tapWith(tester, find.text('היברובוקס מקוון'));
        await tester.pumpAndSettle();

        expect(find.byType(OtzarBookDialog), findsOneWidget);
        expect(find.text('פתח נבחרים'), findsNothing);
      });

      for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
        testWidgets(
          '${key.keyLabel} בספר חיצוני אינו משתמש במקשי לחיצת העכבר',
          (tester) async {
            await _pumpBrowser(
              tester,
              books: [onlineHebrewBook],
              viewMode: mode,
            );
            await _tapWith(
              tester,
              find.text(onlineHebrewBook.title),
              holding: LogicalKeyboardKey.controlLeft,
            );
            expect(find.byType(OtzarBookDialog), findsNothing);
            Focus.of(
              tester.element(find.text(onlineHebrewBook.title)),
            ).requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(key);
            await tester.pumpAndSettle();
            expect(find.byType(OtzarBookDialog), findsOneWidget);
            expect(find.text('פתח נבחרים'), findsNothing);
          },
        );
      }

      testWidgets('טווח Shift שעובר על ספר חיצוני מדלג עליו, והפתיחה כוללת '
          'רק ספרי קריאה', (tester) async {
        final h = await _pumpBrowser(
          tester,
          books: [text, otzar, pdf],
          viewMode: mode,
        );

        await _tapWith(
          tester,
          find.text('טקסט'),
          holding: LogicalKeyboardKey.controlLeft,
        );
        await _tapWith(
          tester,
          find.text('פי-די-אף'),
          holding: LogicalKeyboardKey.shiftLeft,
        );
        expect(find.text('2 ספרים נבחרו'), findsOneWidget);

        await tester.tap(find.text('פתח נבחרים'));
        await tester.pumpAndSettle();
        expect(h.openedTitles(), ['טקסט', 'פי-די-אף']);
      });
    });
  }

  group('חזרה לעיון מהספרייה (issue #4229)', () {
    final book = TextBook(title: 'ספר בספרייה');
    List<OpenedTab> tabs() => [
      TextBookTab(book: TextBook(title: 'בראשית'), index: 0),
      TextBookTab(book: TextBook(title: 'שמות'), index: 0),
    ];
    final returnButton = find.byTooltip('חזרה לעיון: בראשית');

    void expectReturnedToReading(_Harness h) {
      verify(
        () => h.navigationBloc.add(const NavigateToScreen(Screen.reading)),
      ).called(1);
      verifyNever(() => h.tabsBloc.add(any()));
    }

    testWidgets('יש כרטיסיות פתוחות: הכפתור מציג את הכרטיסייה הנוכחית '
        'ומחזיר אליה', (tester) async {
      final h = await _pumpBrowser(
        tester,
        books: [book],
        viewMode: 'grid',
        openTabs: tabs(),
      );
      expect(returnButton, findsOneWidget);

      await tester.tap(returnButton);
      await tester.pump();
      expectReturnedToReading(h);
    });

    testWidgets('Esc מחוץ לשדה טקסט מחזיר לעיון', (tester) async {
      final h = await _pumpBrowser(
        tester,
        books: [book],
        viewMode: 'grid',
        openTabs: tabs(),
      );
      // Tab משדה החיפוש מעביר את הפוקוס לרשת הספרים.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expectReturnedToReading(h);
    });

    testWidgets('אין כרטיסיות פתוחות: אין כפתור ו-Esc לא עובר לעיון', (
      tester,
    ) async {
      final h = await _pumpBrowser(tester, books: [book], viewMode: 'grid');
      expect(find.byTooltip(RegExp('^חזרה לעיון')), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      verifyNever(() => h.navigationBloc.add(any()));
    });
  });
}
