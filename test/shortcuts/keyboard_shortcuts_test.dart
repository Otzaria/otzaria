import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/shortcuts/keyboard_shortcuts.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/tabs_repository.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:provider/provider.dart';
import '../helpers/memory_settings_cache.dart';

class MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class MockIndexingBloc extends MockBloc<IndexingEvent, IndexingState>
    implements IndexingBloc {}

class MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _StubTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _StubTabsBloc(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubHistoryBloc extends Bloc<HistoryEvent, HistoryState>
    implements HistoryBloc {
  _StubHistoryBloc() : super(HistoryInitial()) {
    on<HistoryEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubNavigationBloc extends Bloc<NavigationEvent, NavigationState>
    implements NavigationBloc {
  _StubNavigationBloc([Screen screen = Screen.reading])
    : super(NavigationState(currentScreen: screen)) {
    on<NavigationEvent>((event, _) => events.add(event));
  }

  final List<NavigationEvent> events = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubTextBookBloc extends Bloc<TextBookEvent, TextBookState>
    implements TextBookBloc {
  _StubTextBookBloc()
    : super(
        TextBookInitial.named(
          TextBook(title: 'ספר בדיקה'),
          0,
          false,
          const [],
        ),
      ) {
    on<TextBookEvent>((_, _) {});
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeTabsRepository extends TabsRepository {
  @override
  List<OpenedTab> loadTabs() => const [];

  @override
  int loadCurrentTabIndex() => 0;

  @override
  Future<void> saveCurrentTabIndex(
    List<OpenedTab> tabs,
    int currentTabIndex,
  ) async {}

  @override
  Future<void> saveTabs(List<OpenedTab> tabs, int currentTabIndex) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // הטסטים שולחים Control פיזי. ב-macOS `ctrl` מתורגם ל-Meta, ולכן בלי קיבוע
  // זה הקיצורים (Ctrl+Shift+L/C/T) לא היו מזוהים והטסטים נכשלים על Mac/CI.
  setUp(() {
    ShortcutHelper.isMacForTesting = false;
    ShortcutHelper.isWindowsForTesting = false;
  });
  tearDown(() {
    ShortcutHelper.isMacForTesting = null;
    ShortcutHelper.isWindowsForTesting = null;
  });

  group('KeyboardShortcuts', () {
    late MockSettingsBloc settingsBloc;
    late StreamController<SettingsState> settingsController;

    setUp(() {
      settingsBloc = MockSettingsBloc();
      settingsController = StreamController<SettingsState>.broadcast();

      whenListen(
        settingsBloc,
        settingsController.stream,
        initialState: SettingsState.initial(),
      );
    });

    tearDown(() async {
      await settingsController.close();
    });

    testWidgets(
      'לא זורק שגיאה בזמן rebuild של קיצורים כששדה טקסט מחזיק focus',
      (tester) async {
        await tester.pumpWidget(
          BlocProvider<SettingsBloc>.value(
            value: settingsBloc,
            child: MaterialApp(
              home: Scaffold(
                body: KeyboardShortcuts(
                  onFindRefRequested: () {},
                  child: const TextField(),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byType(TextField));
        await tester.pump();

        expect(FocusManager.instance.primaryFocus, isNotNull);

        // עדכון shortcuts מטריגר rebuild של ה-FocusScope; לפני התיקון
        // FocusScopeNode חדש בכל rebuild היה זורק שגיאה כששדה טקסט מחזיק focus.
        settingsController.add(
          SettingsState.initial().copyWith(
            shortcuts: const {
              'key-shortcut-open-library-browser': 'ctrl+shift+l',
            },
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('KeyboardShortcuts - קיצורי חלוניות ותצוגה (Ctrl+Shift+L/C/P)', () {
    late MockSettingsBloc settingsBlocLocal;
    late StreamController<SettingsState> settingsControllerLocal;

    setUpAll(() async {
      await Settings.init(cacheProvider: MemorySettingsCache());
    });

    setUp(() {
      FocusRepository().resetForTesting();
      settingsBlocLocal = MockSettingsBloc();
      settingsControllerLocal = StreamController<SettingsState>.broadcast();
      whenListen(
        settingsBlocLocal,
        settingsControllerLocal.stream,
        initialState: SettingsState.initial().copyWith(
          shortcuts: const {
            'key-shortcut-toggle-nav-pane': 'ctrl+shift+l',
            'key-shortcut-toggle-commentators-pane': 'ctrl+shift+c',
          },
        ),
      );
    });

    tearDown(() async {
      await settingsControllerLocal.close();
      FocusRepository().resetForTesting();
    });

    Future<void> pumpWithTab(WidgetTester tester, OpenedTab tab) async {
      final tabsBloc = _StubTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );
      final historyBloc = _StubHistoryBloc();
      final navigationBloc = _StubNavigationBloc();
      addTearDown(() async {
        await tabsBloc.close();
        await historyBloc.close();
        await navigationBloc.close();
      });

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settingsBlocLocal),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<HistoryBloc>.value(value: historyBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            Provider<FocusRepository>.value(value: FocusRepository()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: KeyboardShortcuts(
                onFindRefRequested: () {},
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> sendCtrlShift(
      WidgetTester tester,
      LogicalKeyboardKey key,
    ) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyUpEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    testWidgets('Ctrl+Shift+L ב-PdfBookTab מטוגל את toggleNavPaneNotifier', (
      tester,
    ) async {
      final tab = PdfBookTab(
        book: PdfBook(title: 'ספר PDF', path: '/x.pdf'),
        pageNumber: 1,
      );
      addTearDown(tab.dispose);

      await pumpWithTab(tester, tab);

      expect(tab.toggleNavPaneNotifier.value, 0);
      await sendCtrlShift(tester, LogicalKeyboardKey.keyL);
      expect(tab.toggleNavPaneNotifier.value, 1);

      await sendCtrlShift(tester, LogicalKeyboardKey.keyL);
      expect(tab.toggleNavPaneNotifier.value, 2);
    });

    testWidgets(
      'Ctrl+Shift+C ב-PdfBookTab מטוגל את toggleCommentatorsPaneNotifier '
      '(תיקון הבאג: PR המקורי בלע את האירוע ב-PDF)',
      (tester) async {
        final tab = PdfBookTab(
          book: PdfBook(title: 'ספר PDF', path: '/x.pdf'),
          pageNumber: 1,
        );
        addTearDown(tab.dispose);

        await pumpWithTab(tester, tab);

        expect(tab.toggleCommentatorsPaneNotifier.value, 0);
        await sendCtrlShift(tester, LogicalKeyboardKey.keyC);
        expect(tab.toggleCommentatorsPaneNotifier.value, 1);
      },
    );

    testWidgets(
      'Ctrl+Shift+P ב-PdfBookTab מגלגל את toggleTextViewNotifier '
      '(הקיצור פעל רק בכיוון טקסט→PDF)',
      (tester) async {
        final tab = PdfBookTab(
          book: PdfBook(title: 'ספר PDF', path: '/x.pdf'),
          pageNumber: 1,
        );
        addTearDown(tab.dispose);

        await pumpWithTab(tester, tab);

        expect(tab.toggleTextViewNotifier.value, 0);
        await sendCtrlShift(tester, LogicalKeyboardKey.keyP);
        expect(tab.toggleTextViewNotifier.value, 1);
      },
    );
  });

  group('KeyboardShortcuts - חיפוש מתקדם אופציונלי', () {
    late MockSettingsBloc settingsBlocLocal;
    late MockIndexingBloc indexingBloc;
    late MockLibraryBloc libraryBloc;
    late StreamController<SettingsState> settingsControllerLocal;

    setUpAll(() async {
      await Settings.init(cacheProvider: MemorySettingsCache());
    });

    setUp(() {
      FocusRepository().resetForTesting();
      settingsBlocLocal = MockSettingsBloc();
      indexingBloc = MockIndexingBloc();
      libraryBloc = MockLibraryBloc();
      settingsControllerLocal = StreamController<SettingsState>.broadcast();

      whenListen(
        settingsBlocLocal,
        settingsControllerLocal.stream,
        initialState: SettingsState.initial().copyWith(
          shortcuts: const {
            'key-shortcut-open-advanced-search': 'ctrl+shift+g',
          },
        ),
      );
      whenListen(
        indexingBloc,
        const Stream<IndexingState>.empty(),
        initialState: IndexingInitial(),
      );
      whenListen(
        libraryBloc,
        const Stream<LibraryState>.empty(),
        initialState: const LibraryState(),
      );
    });

    tearDown(() async {
      await settingsControllerLocal.close();
      await indexingBloc.close();
      await libraryBloc.close();
      FocusRepository().resetForTesting();
    });

    testWidgets('פותח את דיאלוג החיפוש במצב מתקדם', (tester) async {
      final tabsBloc = _StubTabsBloc(
        const TabsState(tabs: [], currentTabIndex: 0),
      );
      final historyBloc = _StubHistoryBloc();
      final navigationBloc = _StubNavigationBloc();
      addTearDown(() async {
        await tabsBloc.close();
        await historyBloc.close();
        await navigationBloc.close();
      });

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settingsBlocLocal),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<HistoryBloc>.value(value: historyBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            BlocProvider<IndexingBloc>.value(value: indexingBloc),
            BlocProvider<LibraryBloc>.value(value: libraryBloc),
            Provider<FocusRepository>.value(value: FocusRepository()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: KeyboardShortcuts(
                onFindRefRequested: () {},
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      final dialog = tester.widget<SearchDialog>(find.byType(SearchDialog));
      expect(dialog.initialSearchMode, SearchMode.advanced);
    });
  });

  group('KeyboardShortcuts - חיפוש חדש', () {
    late MockSettingsBloc settingsBlocLocal;
    late MockIndexingBloc indexingBloc;
    late MockLibraryBloc libraryBloc;
    late StreamController<SettingsState> settingsControllerLocal;

    setUpAll(() async {
      await Settings.init(cacheProvider: MemorySettingsCache());
    });

    void useShortcut(String shortcut) {
      whenListen(
        settingsBlocLocal,
        settingsControllerLocal.stream,
        initialState: SettingsState.initial().copyWith(
          shortcuts: {'key-shortcut-open-new-search': shortcut},
        ),
      );
    }

    setUp(() {
      FocusRepository().resetForTesting();
      settingsBlocLocal = MockSettingsBloc();
      indexingBloc = MockIndexingBloc();
      libraryBloc = MockLibraryBloc();
      settingsControllerLocal = StreamController<SettingsState>.broadcast();

      whenListen(
        indexingBloc,
        const Stream<IndexingState>.empty(),
        initialState: IndexingInitial(),
      );
      whenListen(
        libraryBloc,
        const Stream<LibraryState>.empty(),
        initialState: const LibraryState(),
      );
    });

    tearDown(() async {
      await settingsControllerLocal.close();
      await indexingBloc.close();
      await libraryBloc.close();
      FocusRepository().resetForTesting();
    });

    /// מרים את עץ הקיצורים ומחזיר מונה חי של הפעלות "חיפוש חדש".
    /// `withCallback: false` משאיר את ה-callback null כדי לבדוק את מסלול הדיאלוג.
    Future<ValueNotifier<int>> pumpShortcuts(
      WidgetTester tester, {
      bool withCallback = true,
    }) async {
      final tabsBloc = _StubTabsBloc(
        const TabsState(tabs: [], currentTabIndex: 0),
      );
      final historyBloc = _StubHistoryBloc();
      final navigationBloc = _StubNavigationBloc();
      final calls = ValueNotifier<int>(0);
      addTearDown(() async {
        await tabsBloc.close();
        await historyBloc.close();
        await navigationBloc.close();
        calls.dispose();
      });

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settingsBlocLocal),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<HistoryBloc>.value(value: historyBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            BlocProvider<IndexingBloc>.value(value: indexingBloc),
            BlocProvider<LibraryBloc>.value(value: libraryBloc),
            Provider<FocusRepository>.value(value: FocusRepository()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: KeyboardShortcuts(
                onFindRefRequested: () {},
                onNewSearchRequested: withCallback ? () => calls.value++ : null,
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return calls;
    }

    Future<void> sendKeys(
      WidgetTester tester,
      List<LogicalKeyboardKey> modifiers,
      LogicalKeyboardKey key,
    ) async {
      for (final modifier in modifiers) {
        await tester.sendKeyDownEvent(modifier);
      }
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyUpEvent(key);
      for (final modifier in modifiers.reversed) {
        await tester.sendKeyUpEvent(modifier);
      }
      await tester.pump();
    }

    testWidgets('קיצור ברירת המחדל Ctrl+Shift+F מפעיל את החיפוש החדש', (
      tester,
    ) async {
      useShortcut('ctrl+shift+f');
      final calls = await pumpShortcuts(tester);

      await sendKeys(
        tester,
        [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft],
        LogicalKeyboardKey.keyF,
      );

      expect(calls.value, 1);
    });

    // רגרסיה: קיצור מותאם אישית שהוקלט בפריסה עברית נשמר בעבר עם התו העברי
    // ולכן לא נתפס. כעת הוא נשמר קנוני, ואותה לחיצה פיזית מפעילה את הפעולה.
    testWidgets('קיצור מותאם אישית Ctrl+Shift+D מפעיל את החיפוש החדש', (
      tester,
    ) async {
      useShortcut('ctrl+shift+d');
      final calls = await pumpShortcuts(tester);

      await sendKeys(
        tester,
        [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft],
        LogicalKeyboardKey.keyD,
      );
      expect(calls.value, 1);

      // מקש אחר עם אותם modifiers אינו מפעיל את הפעולה
      await sendKeys(
        tester,
        [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft],
        LogicalKeyboardKey.keyF,
      );
      expect(calls.value, 1);
    });

    testWidgets('קיצור מותאם אישית שאינו אות (F8) מפעיל את החיפוש החדש', (
      tester,
    ) async {
      useShortcut('f8');
      final calls = await pumpShortcuts(tester);

      await sendKeys(tester, const [], LogicalKeyboardKey.f8);
      expect(calls.value, 1);
    });

    testWidgets('קיצור מותאם אישית Alt+חץ למעלה מפעיל את החיפוש החדש', (
      tester,
    ) async {
      useShortcut('alt+arrowup');
      final calls = await pumpShortcuts(tester);

      await sendKeys(
        tester,
        [LogicalKeyboardKey.altLeft],
        LogicalKeyboardKey.arrowUp,
      );
      expect(calls.value, 1);
    });

    testWidgets('קיצור ריק אינו מפעיל את החיפוש החדש', (tester) async {
      useShortcut('');
      final calls = await pumpShortcuts(tester);

      await sendKeys(
        tester,
        [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft],
        LogicalKeyboardKey.keyF,
      );
      expect(calls.value, 0);
    });

    testWidgets('ללא callback הקיצור פותח את דיאלוג החיפוש', (tester) async {
      useShortcut('ctrl+shift+d');
      await pumpShortcuts(tester, withCallback: false);

      await sendKeys(
        tester,
        [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft],
        LogicalKeyboardKey.keyD,
      );
      await tester.pumpAndSettle();

      expect(find.byType(SearchDialog), findsOneWidget);
    });
  });

  group('KeyboardShortcuts - Ctrl+Shift+T', () {
    late MockSettingsBloc settingsBlocLocal;
    late StreamController<SettingsState> settingsControllerLocal;

    setUpAll(() async {
      await Settings.init(cacheProvider: MemorySettingsCache());
    });

    setUp(() {
      settingsBlocLocal = MockSettingsBloc();
      settingsControllerLocal = StreamController<SettingsState>.broadcast();
      whenListen(
        settingsBlocLocal,
        settingsControllerLocal.stream,
        initialState: SettingsState.initial().copyWith(
          shortcuts: const {
            'key-shortcut-restore-closed-tab': 'ctrl+shift+t',
          },
        ),
      );
    });

    tearDown(() async {
      await settingsControllerLocal.close();
    });

    testWidgets('Ctrl+Shift+T משחזר את הטאב האחרון שנסגר', (tester) async {
      final tabsBloc = TabsBloc(repository: _FakeTabsRepository());
      final first = SearchingTab('חיפוש א', 'א');
      final second = SearchingTab('חיפוש ב', 'ב');
      final historyBloc = _StubHistoryBloc();
      final navigationBloc = _StubNavigationBloc();

      addTearDown(() async {
        final openTabs = List<OpenedTab>.from(tabsBloc.state.tabs);
        await tabsBloc.close();
        for (final tab in openTabs) {
          tab.dispose();
        }
        await historyBloc.close();
        await navigationBloc.close();
      });

      tabsBloc.add(AddTab(first));
      await tester.pump();
      tabsBloc.add(AddTab(second));
      await tester.pump();
      tabsBloc.add(RemoveTab(second));
      await tester.pump();

      expect(tabsBloc.state.tabs, hasLength(1));

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settingsBlocLocal),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<HistoryBloc>.value(value: historyBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            Provider<FocusRepository>.value(value: FocusRepository()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: KeyboardShortcuts(
                onFindRefRequested: () {},
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(tabsBloc.state.tabs, hasLength(2));
      expect(tabsBloc.state.currentTabIndex, 1);
      expect(tabsBloc.state.tabs[1].title, 'חיפוש ב');

      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('KeyboardShortcuts - Ctrl+1..9 מעבר לטאב', () {
    late MockSettingsBloc settingsBlocLocal;
    late StreamController<SettingsState> settingsControllerLocal;

    setUpAll(() async {
      await Settings.init(cacheProvider: MemorySettingsCache());
    });

    setUp(() {
      FocusRepository().resetForTesting();
      settingsBlocLocal = MockSettingsBloc();
      settingsControllerLocal = StreamController<SettingsState>.broadcast();
      whenListen(
        settingsBlocLocal,
        settingsControllerLocal.stream,
        initialState: SettingsState.initial(),
      );
    });

    tearDown(() async {
      await settingsControllerLocal.close();
      FocusRepository().resetForTesting();
    });

    Future<TabsBloc> pumpWithTabs(WidgetTester tester, int tabCount) async {
      final tabsBloc = TabsBloc(repository: _FakeTabsRepository());
      final historyBloc = _StubHistoryBloc();
      final navigationBloc = _StubNavigationBloc();
      addTearDown(() async {
        final openTabs = List<OpenedTab>.from(tabsBloc.state.tabs);
        await tabsBloc.close();
        for (final tab in openTabs) {
          tab.dispose();
        }
        await historyBloc.close();
        await navigationBloc.close();
      });

      for (var i = 1; i <= tabCount; i++) {
        tabsBloc.add(AddTab(SearchingTab('חיפוש $i', '$i')));
        await tester.pump();
      }

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settingsBlocLocal),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<HistoryBloc>.value(value: historyBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            Provider<FocusRepository>.value(value: FocusRepository()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: KeyboardShortcuts(
                onFindRefRequested: () {},
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return tabsBloc;
    }

    Future<void> sendCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyUpEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    testWidgets('Ctrl+3 עובר לטאב השלישי', (tester) async {
      final tabsBloc = await pumpWithTabs(tester, 5);

      await sendCtrl(tester, LogicalKeyboardKey.digit3);
      expect(tabsBloc.state.currentTabIndex, 2);
    });

    testWidgets('Ctrl+9 עובר תמיד לטאב האחרון', (tester) async {
      final tabsBloc = await pumpWithTabs(tester, 5);

      await sendCtrl(tester, LogicalKeyboardKey.digit9);
      expect(tabsBloc.state.currentTabIndex, 4);
    });

    testWidgets('Ctrl+ספרה מעבר למספר הטאבים אינו משנה את הטאב הפעיל', (
      tester,
    ) async {
      final tabsBloc = await pumpWithTabs(tester, 3);
      tabsBloc.add(const SetCurrentTab(1));
      await tester.pump();

      // Ctrl+8 ואין טאב 8 — נשאר על הטאב הנוכחי.
      await sendCtrl(tester, LogicalKeyboardKey.digit8);
      expect(tabsBloc.state.currentTabIndex, 1);
    });
  });

  group('KeyboardShortcuts - ניווט קטע/דף-פרק (Alt+חיצים, Alt+Page)', () {
    late MockSettingsBloc settingsBlocLocal;
    late StreamController<SettingsState> settingsControllerLocal;

    setUpAll(() async {
      await Settings.init(cacheProvider: MemorySettingsCache());
    });

    setUp(() {
      FocusRepository().resetForTesting();
      settingsBlocLocal = MockSettingsBloc();
      settingsControllerLocal = StreamController<SettingsState>.broadcast();
      whenListen(
        settingsBlocLocal,
        settingsControllerLocal.stream,
        initialState: SettingsState.initial().copyWith(
          shortcuts: const {
            'key-shortcut-prev-segment': 'alt+arrowup',
            'key-shortcut-next-segment': 'alt+arrowdown',
            'key-shortcut-prev-toc': 'alt+pageup',
            'key-shortcut-next-toc': 'alt+pagedown',
          },
        ),
      );
    });

    tearDown(() async {
      await settingsControllerLocal.close();
      FocusRepository().resetForTesting();
    });

    Future<void> pumpWithTab(
      WidgetTester tester,
      OpenedTab tab, {
      Widget child = const SizedBox(width: 100, height: 100),
    }) async {
      final tabsBloc = _StubTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );
      final historyBloc = _StubHistoryBloc();
      final navigationBloc = _StubNavigationBloc();
      addTearDown(() async {
        await tabsBloc.close();
        await historyBloc.close();
        await navigationBloc.close();
      });

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settingsBlocLocal),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<HistoryBloc>.value(value: historyBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            Provider<FocusRepository>.value(value: FocusRepository()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: KeyboardShortcuts(
                onFindRefRequested: () {},
                child: child,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> sendAlt(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyUpEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pump();
    }

    Future<void> sendAltGr(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.altRight,
        physicalKey: PhysicalKeyboardKey.altRight,
      );
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyUpEvent(key);
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.altRight,
        physicalKey: PhysicalKeyboardKey.altRight,
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    Future<void> sendCtrlAlt(
      WidgetTester tester,
      LogicalKeyboardKey key,
    ) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyUpEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    testWidgets('כל אחד מהקיצורים מגלגל את ה-notifier התואם ב-TextBookTab', (
      tester,
    ) async {
      final tab = TextBookTab(
        book: TextBook(title: 'ספר בדיקה'),
        index: 0,
        blocOverride: _StubTextBookBloc(),
      );
      addTearDown(tab.dispose);

      await pumpWithTab(tester, tab);

      await sendAlt(tester, LogicalKeyboardKey.arrowUp);
      expect(tab.navPreviousSegmentNotifier.value, 1);

      await sendAlt(tester, LogicalKeyboardKey.arrowDown);
      expect(tab.navNextSegmentNotifier.value, 1);

      await sendAlt(tester, LogicalKeyboardKey.pageUp);
      expect(tab.navPreviousTocNotifier.value, 1);

      await sendAlt(tester, LogicalKeyboardKey.pageDown);
      expect(tab.navNextTocNotifier.value, 1);
    });

    testWidgets('AltGr של Windows מפעיל קיצור alt דרך מצב HardwareKeyboard', (
      tester,
    ) async {
      ShortcutHelper.isWindowsForTesting = true;
      final tab = TextBookTab(
        book: TextBook(title: 'ספר בדיקה'),
        index: 0,
        blocOverride: _StubTextBookBloc(),
      );
      addTearDown(tab.dispose);

      await pumpWithTab(tester, tab);
      await sendAltGr(tester, LogicalKeyboardKey.arrowUp);

      expect(tab.navPreviousSegmentNotifier.value, 1);
    });

    testWidgets('AltGr אינו מסונן כששדה RTL מחזיק פוקוס', (tester) async {
      ShortcutHelper.isWindowsForTesting = true;
      final focusNode = FocusNode();
      final tab = TextBookTab(
        book: TextBook(title: 'ספר בדיקה'),
        index: 0,
        blocOverride: _StubTextBookBloc(),
      );
      addTearDown(() {
        focusNode.dispose();
        tab.dispose();
      });

      await pumpWithTab(
        tester,
        tab,
        child: RtlTextField(focusNode: focusNode, autofocus: true),
      );
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      await sendAltGr(tester, LogicalKeyboardKey.arrowUp);

      expect(tab.navPreviousSegmentNotifier.value, 1);
    });

    testWidgets('Ctrl+Alt שמאלי אינו מפעיל קיצור alt בלבד', (tester) async {
      final tab = TextBookTab(
        book: TextBook(title: 'ספר בדיקה'),
        index: 0,
        blocOverride: _StubTextBookBloc(),
      );
      addTearDown(tab.dispose);

      await pumpWithTab(tester, tab);
      await sendCtrlAlt(tester, LogicalKeyboardKey.arrowUp);

      expect(tab.navPreviousSegmentNotifier.value, 0);
    });

    testWidgets(
      'קיצור ניווט ב-PdfBookTab אינו מגלגל notifier (TextBook בלבד)',
      (tester) async {
        final tab = PdfBookTab(
          book: PdfBook(title: 'ספר PDF', path: '/x.pdf'),
          pageNumber: 1,
        );
        addTearDown(tab.dispose);

        await pumpWithTab(tester, tab);

        // לא אמור לזרוק ולא להשפיע — מאומת דרך היעדר חריגה.
        await sendAlt(tester, LogicalKeyboardKey.arrowUp);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('KeyboardShortcuts - Ctrl+W מוגבל למסך עיון', () {
    late MockSettingsBloc settingsBlocLocal;
    late StreamController<SettingsState> settingsControllerLocal;

    setUpAll(() async {
      await Settings.init(cacheProvider: MemorySettingsCache());
    });

    setUp(() {
      FocusRepository().resetForTesting();
      settingsBlocLocal = MockSettingsBloc();
      settingsControllerLocal = StreamController<SettingsState>.broadcast();
      whenListen(
        settingsBlocLocal,
        settingsControllerLocal.stream,
        initialState: SettingsState.initial().copyWith(
          shortcuts: const {'key-shortcut-close-tab': 'ctrl+w'},
        ),
      );
    });

    tearDown(() async {
      await settingsControllerLocal.close();
      FocusRepository().resetForTesting();
    });

    Future<TabsBloc> pumpOnScreen(WidgetTester tester, Screen screen) async {
      final tabsBloc = TabsBloc(repository: _FakeTabsRepository());
      final historyBloc = _StubHistoryBloc();
      final navigationBloc = _StubNavigationBloc(screen);
      addTearDown(() async {
        final openTabs = List<OpenedTab>.from(tabsBloc.state.tabs);
        await tabsBloc.close();
        for (final tab in openTabs) {
          tab.dispose();
        }
        await historyBloc.close();
        await navigationBloc.close();
      });

      tabsBloc.add(AddTab(SearchingTab('חיפוש א', 'א')));
      await tester.pump();
      tabsBloc.add(AddTab(SearchingTab('חיפוש ב', 'ב')));
      await tester.pump();

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settingsBlocLocal),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<HistoryBloc>.value(value: historyBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            Provider<FocusRepository>.value(value: FocusRepository()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: KeyboardShortcuts(
                onFindRefRequested: () {},
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return tabsBloc;
    }

    Future<void> sendCtrlW(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    testWidgets('Ctrl+W במסך עיון סוגר את הטאב הנוכחי', (tester) async {
      final tabsBloc = await pumpOnScreen(tester, Screen.reading);
      expect(tabsBloc.state.tabs, hasLength(2));

      await sendCtrlW(tester);
      expect(tabsBloc.state.tabs, hasLength(1));

      // ניקוז טיימר ההשהיה של שחרור הטאב (_disposeTabLater).
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('Ctrl+W במסך חיפוש סוגר את הטאב הנוכחי (issue #539)', (
      tester,
    ) async {
      final tabsBloc = await pumpOnScreen(tester, Screen.search);
      expect(tabsBloc.state.tabs, hasLength(2));

      await sendCtrlW(tester);
      expect(tabsBloc.state.tabs, hasLength(1));

      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('Ctrl+W מחוץ למסך עיון אינו סוגר טאב', (tester) async {
      final tabsBloc = await pumpOnScreen(tester, Screen.library);
      expect(tabsBloc.state.tabs, hasLength(2));

      await sendCtrlW(tester);
      expect(tabsBloc.state.tabs, hasLength(2));
    });

    testWidgets('Ctrl+W בטאב מפוצל סוגר רק את החלונית הפעילה', (tester) async {
      final tabsBloc = await pumpOnScreen(tester, Screen.reading);
      final right = tabsBloc.state.tabs[0];
      final left = tabsBloc.state.tabs[1];
      tabsBloc.add(CreateCombinedTab(rightTab: right, leftTab: left));
      await tester.pump();
      expect(tabsBloc.state.tabs, hasLength(1));
      expect(tabsBloc.state.tabs.single, isA<CombinedTab>());

      // החלונית הפעילה (ברירת המחדל: הימנית) נסגרת; אחותה נשארת ככרטיסייה.
      await sendCtrlW(tester);
      expect(tabsBloc.state.tabs, hasLength(1));
      expect(identical(tabsBloc.state.tabs.single, left), isTrue);

      // כשהטאב כבר אינו מפוצל — הקיצור סוגר את הכרטיסייה עצמה.
      await sendCtrlW(tester);
      expect(tabsBloc.state.tabs, isEmpty);

      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('KeyboardShortcuts - קיצורים כשדיאלוג פתוח', () {
    late MockSettingsBloc settingsBlocLocal;
    late StreamController<SettingsState> settingsControllerLocal;

    setUpAll(() async {
      await Settings.init(cacheProvider: MemorySettingsCache());
    });

    setUp(() {
      FocusRepository().resetForTesting();
      settingsBlocLocal = MockSettingsBloc();
      settingsControllerLocal = StreamController<SettingsState>.broadcast();
      whenListen(
        settingsBlocLocal,
        settingsControllerLocal.stream,
        initialState: SettingsState.initial().copyWith(
          shortcuts: const {
            'key-shortcut-open-library-browser': 'ctrl+l',
            'key-shortcut-close-tab': 'ctrl+w',
          },
        ),
      );
    });

    tearDown(() async {
      await settingsControllerLocal.close();
      FocusRepository().resetForTesting();
    });

    Future<
      ({
        TabsBloc tabsBloc,
        _StubNavigationBloc navigationBloc,
      })
    >
    pumpWithDialog(WidgetTester tester) async {
      final tabsBloc = TabsBloc(repository: _FakeTabsRepository());
      final historyBloc = _StubHistoryBloc();
      final navigationBloc = _StubNavigationBloc();
      addTearDown(() async {
        final openTabs = List<OpenedTab>.from(tabsBloc.state.tabs);
        await tabsBloc.close();
        for (final tab in openTabs) {
          tab.dispose();
        }
        await historyBloc.close();
        await navigationBloc.close();
      });

      tabsBloc.add(AddTab(SearchingTab('חיפוש א', 'א')));
      await tester.pump();
      tabsBloc.add(AddTab(SearchingTab('חיפוש ב', 'ב')));
      await tester.pump();

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settingsBlocLocal),
            BlocProvider<TabsBloc>.value(value: tabsBloc),
            BlocProvider<HistoryBloc>.value(value: historyBloc),
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            Provider<FocusRepository>.value(value: FocusRepository()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: KeyboardShortcuts(
                onFindRefRequested: () {},
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      showDialog(
        context: tester.element(find.byType(SizedBox)),
        builder: (_) => const AlertDialog(title: Text('דיאלוג בדיקה')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      return (tabsBloc: tabsBloc, navigationBloc: navigationBloc);
    }

    Future<void> sendCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(key);
      await tester.sendKeyUpEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    testWidgets('Ctrl+L פועל גם כשדיאלוג פתוח: סוגר אותו ועובר לספרייה', (
      tester,
    ) async {
      final blocs = await pumpWithDialog(tester);

      await sendCtrl(tester, LogicalKeyboardKey.keyL);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(
        blocs.navigationBloc.events,
        contains(const NavigateToScreen(Screen.library)),
      );

      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('Ctrl+W כשדיאלוג פתוח אינו סוגר טאב שברקע', (tester) async {
      final blocs = await pumpWithDialog(tester);
      expect(blocs.tabsBloc.state.tabs, hasLength(2));

      await sendCtrl(tester, LogicalKeyboardKey.keyW);
      await tester.pumpAndSettle();

      expect(blocs.tabsBloc.state.tabs, hasLength(2));
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });
}
