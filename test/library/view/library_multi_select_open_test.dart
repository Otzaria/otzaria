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

class _StubCalendarCubit extends Cubit<CalendarState> implements CalendarCubit {
  _StubCalendarCubit(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  final libraryBloc = _MockLibraryBloc();
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
}) async {
  final h = _Harness();
  final library = Library(categories: [])..books.addAll(books);
  final settingsBloc = _MockSettingsBloc();
  final libraryUpdateBloc = _MockLibraryUpdateBloc();
  final calendarCubit = _StubCalendarCubit(CalendarState.initial());

  whenListen(
    h.libraryBloc,
    const Stream<LibraryState>.empty(),
    initialState: LibraryState(library: library, currentCategory: library),
  );
  whenListen(
    settingsBloc,
    const Stream<SettingsState>.empty(),
    initialState: SettingsState.initial().copyWith(
      libraryViewMode: viewMode,
      libraryShowPreview: false,
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
    await settingsBloc.close();
    await h.navigationBloc.close();
    await libraryUpdateBloc.close();
    await h.tabsBloc.close();
    await h.historyBloc.close();
    await calendarCubit.close();
  });

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: MultiProvider(
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
        child: const LibraryBrowser(),
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
}
