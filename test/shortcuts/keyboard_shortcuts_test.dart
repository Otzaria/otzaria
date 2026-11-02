import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:otzaria/app_report/bloc/app_report_bloc.dart';
import 'package:otzaria/app_report/bloc/app_report_event.dart';
import 'package:otzaria/app_report/view/app_report_dialog.dart';
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
import 'package:otzaria/navigation/view/tab_search_menu.dart';
import 'package:otzaria/personal_notes/widgets/personal_note_editor_dialog.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut.dart';
import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut_registry.dart';
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
import 'package:otzaria/widgets/text/selection_copy_shortcuts.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/widgets_exports.dart' show ActionButton;
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:provider/provider.dart';
import '../app_report/app_report_test_fakes.dart';
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
  _StubTextBookBloc([TextBookState? state])
    : super(
        state ??
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
  List<OpenedTab> loadTabs({bool newRuntime = false}) => const [];

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

  // issue #1302 — קיצור של אות בודדת ("פ" לחלונית המפרשים) נורה בזמן הקלדה
  // בעורך ההערות האישיות: הזיהוי של "שדה טקסט בפוקוס" הכיר רק ב-EditableText,
  // ועורך Quill מטפל בקלט בעצמו.
  group('KeyboardShortcuts - קיצור של מקש בודד בעורך Quill (issue #1302)', () {
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
          shortcuts: const {'key-shortcut-toggle-commentators-pane': 'p'},
        ),
      );
    });

    tearDown(() async {
      await settingsControllerLocal.close();
      FocusRepository().resetForTesting();
    });

    Future<TextBookTab> pumpEditor(
      WidgetTester tester, {
      required Widget child,
    }) async {
      final tab = TextBookTab(
        book: TextBook(title: 'ספר בדיקה'),
        index: 0,
        blocOverride: _StubTextBookBloc(),
      );
      addTearDown(tab.dispose);
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
      return tab;
    }

    testWidgets('בלי שדה טקסט — המקש הבודד מגלגל את החלונית', (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      final tab = await pumpEditor(
        tester,
        child: Focus(
          focusNode: focusNode,
          child: const SizedBox(width: 100, height: 100),
        ),
      );
      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.pump();

      expect(tab.toggleCommentatorsPaneNotifier.value, 1);
    });

    testWidgets('בעורך Quill בפוקוס — המקש הבודד נשאר הקלדה', (tester) async {
      final controller = quill.QuillController.basic();
      final focusNode = FocusNode();
      final scrollController = ScrollController();
      addTearDown(() {
        controller.dispose();
        focusNode.dispose();
        scrollController.dispose();
      });
      final tab = await pumpEditor(
        tester,
        child: quill.QuillEditor(
          controller: controller,
          focusNode: focusNode,
          scrollController: scrollController,
          config: const quill.QuillEditorConfig(autoFocus: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(focusNode.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.pump();

      expect(tab.toggleCommentatorsPaneNotifier.value, 0);
    });
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
        await tabsBloc.close();
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
        await tabsBloc.close();
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

    testWidgets(
      'Ctrl+C שהוגדר כקיצור דינמי גובר על ההעתקה המובנית (issue #2380)',
      (tester) async {
        final tab = TextBookTab(
          book: TextBook(title: 'ספר בדיקה'),
          index: 0,
          blocOverride: _StubTextBookBloc(
            TextBookLoaded.initial(
              book: TextBook(title: 'ספר בדיקה'),
              index: 0,
              showLeftPane: false,
              splitView: false,
            ),
          ),
        );
        addTearDown(tab.dispose);
        var builtInCopies = 0;
        final selectionFocus = FocusNode();
        addTearDown(selectionFocus.dispose);
        // אותו מיירט Ctrl+C שעוטף את הבחירה בגוף הספר ובחלונית המפרשים.
        await pumpWithTab(
          tester,
          tab,
          child: SelectionCopyShortcuts(
            onCopy: () => builtInCopies++,
            child: SelectionArea(
              focusNode: selectionFocus,
              child: const Text('טקסט'),
            ),
          ),
        );
        selectionFocus.requestFocus();
        await tester.pump();
        Future<void> pressCtrlC({bool hold = false}) async {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
          if (hold) await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyC);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pump();
        }

        await pressCtrlC();
        expect(builtInCopies, 1, reason: 'בלי קיצור דינמי נשארת ההעתקה הרגילה');

        DynamicShortcutRegistry.instance.put(
          const DynamicShortcut(
            id: 'issue2380',
            key: 'ctrl+c',
            kind: DynamicShortcutKind.copySelectionWith,
            change: DynamicDisplayChange(nikud: DynamicMarkChange.hide),
            plainTextOnly: true,
          ),
        );
        addTearDown(() => DynamicShortcutRegistry.instance.remove('issue2380'));
        // גם החזרות של מקש מוחזק אינן מגיעות להעתקה המובנית.
        await pressCtrlC(hold: true);

        expect(builtInCopies, 1);
        final request = tab.dynamicCopyRequestNotifier.value;
        expect(request?.profile.removeNikud, isTrue);
        expect(request?.plainTextOnly, isTrue);
      },
    );
    for (final editing in [true, false]) {
      testWidgets(
        'Ctrl+C דינמי מכבד ${editing ? 'שדה טקסט' : 'דיאלוג שלא ניתן לסגור'}',
        (tester) async {
          final tab = TextBookTab(
            book: TextBook(title: 'ספר בדיקה'),
            index: 0,
            blocOverride: _StubTextBookBloc(
              TextBookLoaded.initial(
                book: TextBook(title: 'ספר בדיקה'),
                index: 0,
                showLeftPane: false,
                splitView: false,
              ),
            ),
          );
          addTearDown(tab.dispose);
          final clipboardWrites = <String>[];
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                clipboardWrites.add(call.arguments['text'] as String);
              }
              if (call.method == 'Clipboard.getData') return {'text': ''};
              return null;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          final controller = TextEditingController(text: 'טקסט בשדה');
          addTearDown(controller.dispose);
          DynamicShortcutRegistry.instance.put(
            const DynamicShortcut(
              id: 'editing-dialog-copy',
              key: 'ctrl+c',
              kind: DynamicShortcutKind.copySelectionWith,
              change: DynamicDisplayChange(nikud: DynamicMarkChange.hide),
            ),
          );
          addTearDown(
            () =>
                DynamicShortcutRegistry.instance.remove('editing-dialog-copy'),
          );
          await pumpWithTab(
            tester,
            tab,
            child: editing
                ? RtlTextField(controller: controller, autofocus: true)
                : const SizedBox(),
          );
          await tester.pumpAndSettle();
          if (editing) {
            controller.selection = TextSelection(
              baseOffset: 0,
              extentOffset: controller.text.length,
            );
          } else {
            unawaited(
              showDialog<void>(
                context: tester.element(find.byType(KeyboardShortcuts)),
                barrierDismissible: false,
                builder: (_) => const PopScope(
                  canPop: false,
                  child: Dialog(child: Text('פעולה בתהליך')),
                ),
              ),
            );
            await tester.pumpAndSettle();
          }
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pump();
          expect(tab.dynamicCopyRequestNotifier.value, isNull);
          if (editing) {
            expect(clipboardWrites, ['טקסט בשדה']);
          } else {
            expect(find.text('פעולה בתהליך'), findsOneWidget);
          }
        },
      );
    }
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
        await tabsBloc.close();
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
    pumpWithDialog(
      WidgetTester tester, {
      bool blocked = false,
      VoidCallback? onCancel,
    }) async {
      final tabsBloc = TabsBloc(repository: _FakeTabsRepository());
      final historyBloc = _StubHistoryBloc();
      final navigationBloc = _StubNavigationBloc();
      addTearDown(() async {
        await tabsBloc.close();
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
            home: PopScope(
              canPop: false,
              child: Scaffold(
                body: KeyboardShortcuts(
                  onFindRefRequested: () => navigationBloc.add(
                    const NavigateToScreen(Screen.find),
                  ),
                  onNewSearchRequested: () => navigationBloc.add(
                    const NavigateToScreen(Screen.search),
                  ),
                  child: const SizedBox(width: 100, height: 100),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      showDialog(
        context: tester.element(find.byType(KeyboardShortcuts)),
        builder: (_) => blocked
            ? AppDialogFrame(
                title: 'התקנה פעילה',
                icon: Icons.extension,
                closeEnabled: false,
                actions: [
                  if (onCancel != null)
                    ActionButton.ghost(
                      text: 'ביטול פריסה',
                      onPressed: onCancel,
                    ),
                ],
                child: const SizedBox.shrink(),
              )
            : const AlertDialog(title: Text('דיאלוג בדיקה')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(blocked ? AppDialogFrame : AlertDialog),
        findsOneWidget,
      );

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

    for (final extraRoute in [false, true]) {
      testWidgets('Ctrl+L מכבד התקנה חסומה, שכבה נוספת: $extraRoute', (
        tester,
      ) async {
        final blocs = await pumpWithDialog(tester, blocked: true);
        if (extraRoute) {
          showDialog<void>(
            context: tester.element(find.byType(AppDialogFrame)),
            builder: (_) => const AlertDialog(title: Text('שכבה נוספת')),
          );
          await tester.pumpAndSettle();
        }
        await sendCtrl(tester, LogicalKeyboardKey.keyL);
        await tester.pumpAndSettle();
        expect(find.text('שכבה נוספת'), findsNothing);
        expect(find.text('התקנה פעילה'), findsOneWidget);
        expect(blocs.navigationBloc.events, isEmpty);
      });
    }

    for (final cancellable in [false, true]) {
      testWidgets(
        'דיאלוג עסוק חוסם callbacks ושומר ביטול מקומי: $cancellable',
        (
          tester,
        ) async {
          var cancelled = 0;
          final blocs = await pumpWithDialog(
            tester,
            blocked: true,
            onCancel: cancellable ? () => cancelled++ : null,
          );
          await sendCtrl(tester, LogicalKeyboardKey.keyF);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pump();
          expect(blocs.navigationBloc.events, isEmpty);
          expect(find.text('התקנה פעילה'), findsOneWidget);
          if (cancellable) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.sendKeyEvent(LogicalKeyboardKey.space);
            await tester.pumpAndSettle();
            expect(cancelled, 1);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(cancelled, 2);
          }
        },
      );
    }

    testWidgets('קיצור ניווט אינו סוגר טופס דיווח שהוקלד בו (issue #2323)', (
      tester,
    ) async {
      whenListen(
        settingsBlocLocal,
        settingsControllerLocal.stream,
        initialState: SettingsState.initial().copyWith(
          shortcuts: const {'key-shortcut-open-reading-screen': 'ctrl+8'},
        ),
      );
      final blocs = await pumpWithDialog(tester);
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      final reportBloc = AppReportBloc(
        trigger: AppReportTrigger.manual,
        service: FakeAppReportService(),
        collector: FakeAppReportCollector(),
        redactor: AppReportRedactor(environment: const {}),
      );
      showAppReportDialog(
        tester.element(find.byType(SizedBox)),
        createBloc: () => reportBloc,
      );
      await tester.pumpAndSettle();
      final description = find.byKey(const ValueKey('app-report-description'));
      await tester.enterText(description, 'דיווח ארוך');
      await tester.pump();

      await sendCtrl(tester, LogicalKeyboardKey.digit8);
      await tester.pumpAndSettle();

      expect(find.text('דיווח ארוך'), findsOneWidget);

      // גם צילום שצורף, בלי טקסט, הוא דיווח שאסור לאבד.
      await tester.enterText(description, '');
      reportBloc.add(
        AppReportImagesChanged([
          AppReportImage(
            bytes: Uint8List(1),
            fileName: 'a.png',
            mimeType: 'image/png',
          ),
        ]),
      );
      await tester.pump();

      await sendCtrl(tester, LogicalKeyboardKey.digit8);
      await tester.pumpAndSettle();

      expect(find.byType(AppReportDialog), findsOneWidget);
      expect(blocs.navigationBloc.events, isEmpty);
    });

    Future<_StubNavigationBloc> pumpReportWithText(WidgetTester tester) async {
      final blocs = await pumpWithDialog(tester);
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      showAppReportDialog(
        tester.element(find.byType(KeyboardShortcuts)),
        createBloc: () => AppReportBloc(
          trigger: AppReportTrigger.manual,
          service: FakeAppReportService(),
          collector: FakeAppReportCollector(),
          redactor: AppReportRedactor(environment: const {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('app-report-description')),
        'דיווח',
      );
      await tester.pump();
      return blocs.navigationBloc;
    }

    /// שולח [key] כש-[modifiers] לחוצים ומחזיר אם האירוע סומן handled.
    Future<bool> sendWith(
      WidgetTester tester,
      List<LogicalKeyboardKey> modifiers,
      LogicalKeyboardKey key, {
      String? character,
    }) async {
      for (final modifier in modifiers) {
        await tester.sendKeyDownEvent(modifier);
      }
      final handled = await tester.sendKeyDownEvent(key, character: character);
      await tester.sendKeyUpEvent(key);
      for (final modifier in modifiers.reversed) {
        await tester.sendKeyUpEvent(modifier);
      }
      await tester.pump();
      return handled;
    }

    testWidgets('תווים מגיעים לשדה בדיאלוג שחוסם סגירה (#2323, #2599)', (
      tester,
    ) async {
      final navigationBloc = await pumpReportWithText(tester);

      // handled חוסם ב-Windows את התו מלהיכנס לשדה.
      for (final key in [
        LogicalKeyboardKey.keyA,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.digit8,
      ]) {
        expect(await tester.sendKeyEvent(key), isFalse, reason: '$key');
      }
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyB), isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      await sendCtrl(tester, LogicalKeyboardKey.keyL);
      await sendCtrl(tester, LogicalKeyboardKey.keyO);
      await tester.pumpAndSettle();
      expect(find.byType(AppReportDialog), findsOneWidget);
      expect(navigationBloc.events, isEmpty);
    });

    testWidgets('AltGr של Windows מקליד ₪ בדיאלוג שחוסם סגירה', (tester) async {
      ShortcutHelper.isWindowsForTesting = true;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final navigationBloc = await pumpReportWithText(tester);
        const altGr = [
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.altRight,
        ];
        const ctrl = [LogicalKeyboardKey.controlLeft];

        expect(
          await sendWith(
            tester,
            altGr,
            LogicalKeyboardKey.digit4,
            character: '₪',
          ),
          isFalse,
        );
        // בלי תו זה קיצור, לא הקלדה.
        expect(
          await sendWith(tester, altGr, LogicalKeyboardKey.pageUp),
          isTrue,
        );
        expect(
          await sendWith(tester, const [
            LogicalKeyboardKey.altLeft,
          ], LogicalKeyboardKey.pageUp),
          isTrue,
        );
        expect(
          await sendWith(tester, ctrl, LogicalKeyboardKey.keyW, character: 'w'),
          isTrue,
        );
        expect(
          await sendWith(tester, ctrl, LogicalKeyboardKey.keyO, character: 'o'),
          isTrue,
        );
        expect(
          await sendWith(
            tester,
            const [],
            LogicalKeyboardKey.escape,
            character: '',
          ),
          isTrue,
        );
        await tester.pumpAndSettle();
        expect(find.byType(AppReportDialog), findsOneWidget);
        expect(navigationBloc.events, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Option במק מקליד תו בדיאלוג שחוסם סגירה', (tester) async {
      ShortcutHelper.isMacForTesting = true;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final navigationBloc = await pumpReportWithText(tester);
        const option = [LogicalKeyboardKey.altLeft];
        const cmd = [LogicalKeyboardKey.metaLeft];

        expect(
          await sendWith(
            tester,
            option,
            LogicalKeyboardKey.keyE,
            character: '´',
          ),
          isFalse,
        );
        expect(
          await sendWith(tester, cmd, LogicalKeyboardKey.keyW, character: 'w'),
          isTrue,
        );
        expect(
          await sendWith(tester, cmd, LogicalKeyboardKey.keyO, character: 'o'),
          isTrue,
        );
        expect(
          await sendWith(
            tester,
            [...cmd, ...option],
            LogicalKeyboardKey.keyX,
            character: '≈',
          ),
          isTrue,
        );
        await tester.pumpAndSettle();
        expect(find.byType(AppReportDialog), findsOneWidget);
        expect(navigationBloc.events, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Ctrl+D/H של Cocoa מגיעים לשדה בדיאלוג שחוסם סגירה', (
      tester,
    ) async {
      ShortcutHelper.isMacForTesting = true;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final navigationBloc = await pumpReportWithText(tester);
        for (final key in [LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyH]) {
          expect(
            await sendWith(tester, const [LogicalKeyboardKey.controlLeft], key),
            isFalse,
            reason: '$key must reach Cocoa text editing',
          );
          for (final modifier in [
            LogicalKeyboardKey.shiftLeft,
            LogicalKeyboardKey.metaLeft,
          ]) {
            expect(
              await sendWith(tester, [
                LogicalKeyboardKey.controlLeft,
                modifier,
              ], key),
              isTrue,
            );
          }
        }
        for (final key in [LogicalKeyboardKey.keyO, LogicalKeyboardKey.keyW]) {
          expect(
            await sendWith(tester, const [LogicalKeyboardKey.controlLeft], key),
            isTrue,
          );
        }
        expect(find.byType(AppReportDialog), findsOneWidget);
        expect(navigationBloc.events, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
      'Ctrl+D/H נשארים חסומים בשדה מחוץ למק',
      (tester) async {
        final navigationBloc = await pumpReportWithText(tester);
        for (final key in [LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyH]) {
          expect(
            await sendWith(tester, const [LogicalKeyboardKey.controlLeft], key),
            isTrue,
          );
        }
        expect(navigationBloc.events, isEmpty);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.windows,
        TargetPlatform.linux,
      }),
    );

    testWidgets('Ctrl+D/H נשארים חסומים במק כשהפוקוס אינו בשדה', (
      tester,
    ) async {
      ShortcutHelper.isMacForTesting = true;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final blocs = await pumpWithDialog(tester, blocked: true);
        expect(ShortcutHelper.isEditingText, isFalse);
        for (final key in [LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyH]) {
          expect(
            await sendWith(tester, const [LogicalKeyboardKey.controlLeft], key),
            isTrue,
          );
        }
        expect(find.byType(AppDialogFrame), findsOneWidget);
        expect(blocs.navigationBloc.events, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('תווים מגיעים לעורך ההערות, שחוסם סגירה תמיד', (tester) async {
      final blocs = await pumpWithDialog(tester);
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      showDialog<void>(
        context: tester.element(find.byType(SizedBox)),
        builder: (_) => const PersonalNoteEditorDialog(),
      );
      await tester.pumpAndSettle();
      expect(find.byType(quill.QuillEditor), findsOneWidget);
      expect(ShortcutHelper.isEditingText, isTrue);

      for (final key in [LogicalKeyboardKey.keyA, LogicalKeyboardKey.space]) {
        expect(await tester.sendKeyEvent(key), isFalse, reason: '$key');
      }

      await sendCtrl(tester, LogicalKeyboardKey.keyL);
      await tester.pumpAndSettle();
      expect(find.byType(PersonalNoteEditorDialog), findsOneWidget);
      expect(blocs.navigationBloc.events, isEmpty);
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

  group('KeyboardShortcuts - קיצור חיפוש הכרטיסיות פותח וסוגר', () {
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
          shortcuts: const {'key-shortcut-search-tabs': 'ctrl+shift+a'},
        ),
      );
    });

    tearDown(() async {
      await settingsControllerLocal.close();
      FocusRepository().resetForTesting();
    });

    Future<void> pumpReadingScreen(WidgetTester tester) async {
      final tabsBloc = TabsBloc(repository: _FakeTabsRepository());
      final historyBloc = _StubHistoryBloc();
      final navigationBloc = _StubNavigationBloc();
      addTearDown(() async {
        await tabsBloc.close();
        await historyBloc.close();
        await navigationBloc.close();
      });

      tabsBloc.add(AddTab(SearchingTab('חיפוש א', 'א')));
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
    }

    Future<void> sendCtrlShiftA(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('לחיצה שנייה על הקיצור סוגרת את החלונית הפתוחה', (
      tester,
    ) async {
      await pumpReadingScreen(tester);

      await sendCtrlShiftA(tester);
      expect(find.byType(TabSearchPanel), findsOneWidget);

      await sendCtrlShiftA(tester);
      expect(find.byType(TabSearchPanel), findsNothing);
    });

    testWidgets('הקיצור אינו פותח את החלונית מעל דיאלוג אחר', (tester) async {
      await pumpReadingScreen(tester);
      showDialog(
        context: tester.element(find.byType(SizedBox)),
        builder: (_) => const AlertDialog(title: Text('דיאלוג בדיקה')),
      );
      await tester.pumpAndSettle();

      await sendCtrlShiftA(tester);

      expect(find.byType(TabSearchPanel), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });
}
