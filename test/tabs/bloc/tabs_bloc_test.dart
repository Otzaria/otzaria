import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
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
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TabsBloc side-by-side', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test('יוצר CombinedTab עם עותקים נפרדים של הטאבים', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final rightTab = _createTextTab('ספר ימין', categoryId: 1);
      final leftTab = _createTextTab('ספר שמאל', categoryId: 2);

      bloc.add(AddTab(rightTab));
      bloc.add(AddTab(leftTab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      bloc.add(EnableSideBySideMode(rightTab: rightTab, leftTab: leftTab));
      await bloc.stream
          .firstWhere((s) => s.tabs.length == 1 && s.currentTab is CombinedTab);

      final currentState = bloc.state;
      expect(currentState.tabs, hasLength(1));
      expect(currentState.currentTab, isA<CombinedTab>());

      final combinedTab = currentState.currentTab! as CombinedTab;
      expect(combinedTab.rightTab, isNot(same(rightTab)));
      expect(combinedTab.leftTab, isNot(same(leftTab)));

      final combinedRightTab = combinedTab.rightTab as TextBookTab;
      final combinedLeftTab = combinedTab.leftTab as TextBookTab;

      expect(combinedRightTab.scrollController,
          isNot(same(rightTab.scrollController)));
      expect(combinedLeftTab.scrollController,
          isNot(same(leftTab.scrollController)));

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('פירוק CombinedTab מחזיר טאבים חדשים ולא את מופעי המשנה הישנים',
        () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final rightTab = _createTextTab('ספר א', categoryId: 1);
      final leftTab = _createTextTab('ספר ב', categoryId: 2);

      bloc.add(AddTab(rightTab));
      bloc.add(AddTab(leftTab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      bloc.add(EnableSideBySideMode(rightTab: rightTab, leftTab: leftTab));
      await bloc.stream
          .firstWhere((s) => s.tabs.length == 1 && s.currentTab is CombinedTab);

      final combinedTab = bloc.state.currentTab! as CombinedTab;
      final combinedRightTab = combinedTab.rightTab;
      final combinedLeftTab = combinedTab.leftTab;

      bloc.add(const DisableSideBySideMode(0));
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      final restoredState = bloc.state;
      expect(restoredState.tabs, hasLength(2));
      expect(restoredState.tabs[0], isNot(same(combinedRightTab)));
      expect(restoredState.tabs[1], isNot(same(combinedLeftTab)));

      await _closeBlocAndAllowDeferredDispose(bloc);
    });
  });

  group('TabsBloc open or focus', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test('ממקד טאב טקסט קיים כשאותו ספר פתוח באותה כותרת', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final firstTab = _createTextTab('ספר א', index: 0, categoryId: 1)
        ..currentTitle.value = 'פרק א';
      final secondTab = _createTextTab('ספר ב', index: 0, categoryId: 2);

      bloc.add(AddTab(firstTab));
      bloc.add(AddTab(secondTab));
      // After both AddTabs: tabs=[first,second], currentTabIndex=1
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      final targetTab = _createTextTab('ספר א', index: 12, categoryId: 1);
      bloc.add(OpenOrFocusTab(targetTab, targetTitle: 'ספר א, פרק א'));
      // Focuses firstTab at index 0 — currentTabIndex changes from 1 to 0
      await bloc.stream
          .firstWhere((s) => s.tabs.length == 2 && s.currentTabIndex == 0);

      expect(bloc.state.tabs, hasLength(2));
      expect(bloc.state.currentTabIndex, 0);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('פותח טאב חדש כשאותו ספר נפתח בכותרת אחרת', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final existingTab = _createTextTab('ספר א', index: 0, categoryId: 1)
        ..currentTitle.value = 'פרק א';

      bloc.add(AddTab(existingTab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      final targetTab = _createTextTab('ספר א', index: 25, categoryId: 1);
      bloc.add(OpenOrFocusTab(targetTab, targetTitle: 'פרק ב'));
      // No existing tab matches 'פרק ב' — a new tab is added
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      expect(bloc.state.tabs, hasLength(2));
      expect(bloc.state.currentTabIndex, 1);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('ממקד טאב PDF קיים לפי כותרת גם אם העמוד שונה', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final existingTab = PdfBookTab(
        book: PdfBook(title: 'ספר PDF', path: 'a.pdf'),
        pageNumber: 10,
      )..currentTitle.value = 'שער ראשון';

      bloc.add(AddTab(existingTab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      final targetTab = PdfBookTab(
        book: PdfBook(title: 'ספר PDF', path: 'a.pdf'),
        pageNumber: 14,
      );
      bloc.add(OpenOrFocusTab(targetTab, targetTitle: 'ספר PDF, שער ראשון'));
      // Tab is already active at index 0 — state.currentTabIndex stays 0, no new emission.
      // pumpEventQueue drains all microtasks to guarantee the handler has completed.
      await pumpEventQueue();

      expect(bloc.state.tabs, hasLength(1));
      expect(bloc.state.currentTabIndex, 0);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('ממקד CombinedTab כשאחת החלוניות תואמת', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final combinedTab = CombinedTab(
        rightTab: _createTextTab('ספר ימין', index: 0, categoryId: 1)
          ..currentTitle.value = 'פרק א',
        leftTab: _createTextTab('ספר שמאל', index: 0, categoryId: 2)
          ..currentTitle.value = 'פרק ג',
      );

      bloc.add(AddTab(combinedTab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      final targetTab = _createTextTab('ספר שמאל', index: 99, categoryId: 2);
      bloc.add(OpenOrFocusTab(targetTab, targetTitle: 'ספר שמאל, פרק ג'));
      // CombinedTab is already active at index 0 — no state change.
      await pumpEventQueue();

      expect(bloc.state.tabs, hasLength(1));
      expect(bloc.state.currentTabIndex, 0);
      expect(bloc.state.currentTab, same(combinedTab));

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('ממקד טאב טקסט קיים גם בלי targetTitle לפי אינדקס', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final existingTab = _createTextTab('ספר א', index: 12, categoryId: 1);

      bloc.add(AddTab(existingTab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      final targetTab = _createTextTab('ספר א', index: 12, categoryId: 1);
      bloc.add(OpenOrFocusTab(targetTab));
      // Tab is already active at index 0 — no state change.
      await pumpEventQueue();

      expect(bloc.state.tabs, hasLength(1));
      expect(bloc.state.currentTabIndex, 0);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('לא ממקד ספר טקסט אחר כשיש רק התאמת כותרת ללא מזהה יציב', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final existingTab = TextBookTab(
        book: TextBook(title: 'ספר זהה', categoryId: 1),
        index: 12,
      )..currentTitle.value = 'פרק א';

      bloc.add(AddTab(existingTab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      final targetTab = TextBookTab(
        book: TextBook(title: 'ספר זהה'),
        index: 12,
      );
      bloc.add(OpenOrFocusTab(targetTab, targetTitle: 'ספר זהה, פרק א'));
      // No stable identity match — a new tab is added
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      expect(bloc.state.tabs, hasLength(2));
      expect(bloc.state.currentTabIndex, 1);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('לא ממקד ספר אחר רק כי הוא באותה קטגוריה', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final existingTab = TextBookTab(
        book: TextBook(
          id: 101,
          title: 'משנה ברכות',
          categoryId: 7,
        ),
        index: 0,
      );

      bloc.add(AddTab(existingTab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      final targetTab = TextBookTab(
        book: TextBook(
          id: 102,
          title: 'משנה פאה',
          categoryId: 7,
        ),
        index: 0,
      );
      bloc.add(OpenOrFocusTab(targetTab));
      // Different book IDs — a new tab is added
      await bloc.stream.firstWhere((s) => s.tabs.length == 2);

      expect(bloc.state.tabs, hasLength(2));
      expect(bloc.state.currentTabIndex, 1);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('ממקד טאב PDF קיים גם כשהכותרת עוד לא נטענה לפי מספר עמוד', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final existingTab = PdfBookTab(
        book: PdfBook(title: 'ספר PDF', path: 'a.pdf'),
        pageNumber: 10,
      );

      bloc.add(AddTab(existingTab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      final targetTab = PdfBookTab(
        book: PdfBook(title: 'ספר PDF', path: 'a.pdf'),
        pageNumber: 10,
      );
      bloc.add(OpenOrFocusTab(targetTab, targetTitle: 'ספר PDF, שער ראשון'));
      // Tab already active at index 0 — no state change.
      await pumpEventQueue();

      expect(bloc.state.tabs, hasLength(1));
      expect(bloc.state.currentTabIndex, 0);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });

    test('ממקד טאב חיפוש קיים לפי dedupeKey גם בלי מזהה ספר יציב', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final existingTab = TextBookTab(
        book: TextBook(title: 'ספר זהה'),
        index: 12,
        dedupeKey: 'search:text|ספר זהה|ספר זהה, פרק א|12',
      );

      bloc.add(AddTab(existingTab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      final targetTab = TextBookTab(
        book: TextBook(title: 'ספר זהה'),
        index: 12,
        dedupeKey: 'search:text|ספר זהה|ספר זהה, פרק א|12',
      );
      bloc.add(OpenOrFocusTab(targetTab, targetTitle: 'ספר זהה, פרק א'));
      // dedupeKey matches, tab already active at index 0 — no state change.
      await pumpEventQueue();

      expect(bloc.state.tabs, hasLength(1));
      expect(bloc.state.currentTabIndex, 0);

      await _closeBlocAndAllowDeferredDispose(bloc);
    });
  });

  group('TabsBloc deferred dispose', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test('סגירת טאב דוחה את dispose עד אחרי עדכון ה-state', () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final searchTab = SearchingTab('חיפוש', 'בדיקה');

      bloc.add(AddTab(searchTab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      bloc.add(RemoveTab(searchTab));
      await bloc.stream.firstWhere((s) => s.tabs.isEmpty);

      void titleListener() {}
      expect(
        () => searchTab.titleNotifier.addListener(titleListener),
        returnsNormally,
      );
      searchTab.titleNotifier.removeListener(titleListener);

      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(
        () => searchTab.titleNotifier.addListener(() {}),
        throwsA(isA<FlutterError>()),
      );

      await bloc.close();
    });

    test('ReplaceAllTabs לא משחרר את הטאבים הישנים לפני שה-UI מספיק להתנתק',
        () async {
      final bloc = TabsBloc(repository: _FakeTabsRepository());
      final oldTab = SearchingTab('חיפוש ישן', 'ישן');
      final newTab = SearchingTab('חיפוש חדש', 'חדש');

      bloc.add(AddTab(oldTab));
      await bloc.stream.firstWhere((s) => s.tabs.length == 1);

      bloc.add(ReplaceAllTabs([newTab], 0));
      await bloc.stream.firstWhere(
        (s) => s.tabs.length == 1 && identical(s.tabs.first, newTab),
      );

      void titleListener() {}
      expect(
        () => oldTab.titleNotifier.addListener(titleListener),
        returnsNormally,
      );
      oldTab.titleNotifier.removeListener(titleListener);

      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(
        () => oldTab.titleNotifier.addListener(() {}),
        throwsA(isA<FlutterError>()),
      );

      await _closeBlocAndAllowDeferredDispose(bloc);
    });
  });

  group('OpenedTab.from for search tabs', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test('משכפל SearchingTab למופע חדש עם controllers חדשים', () {
      final original = SearchingTab('חיפוש: שבת', 'שבת');
      original.searchOptions['שבת_0'] = {'קידומות': true};
      original.alternativeWords[0] = ['שבתות'];
      original.spacingValues['0-1'] = '2';

      final cloned = OpenedTab.from(original) as SearchingTab;

      expect(cloned, isNot(same(original)));
      expect(cloned.queryController, isNot(same(original.queryController)));
      expect(
        cloned.searchFieldFocusNode,
        isNot(same(original.searchFieldFocusNode)),
      );
      expect(cloned.queryController.text, original.queryController.text);
      expect(cloned.searchOptions, isNot(same(original.searchOptions)));
      expect(cloned.searchOptions['שבת_0']?['קידומות'], isTrue);
      expect(cloned.alternativeWords[0], ['שבתות']);
      expect(cloned.spacingValues['0-1'], '2');

      original.dispose();

      expect(
        () => cloned.queryController.addListener(() {}),
        returnsNormally,
      );

      cloned.dispose();
    });

    test('TextBookTab משמר pinpointHighlight ו-section index בעת clone', () {
      final original = TextBookTab(
        book: TextBook(title: 'בראשית'),
        index: 12,
        pinpointHighlight: 'אור',
        pinpointHighlightSectionIndex: 7,
      );

      final cloned = OpenedTab.from(original) as TextBookTab;

      expect(cloned.pinpointHighlight, 'אור');
      expect(
        cloned.pinpointHighlightSectionIndex,
        7,
        reason:
            'בעת clone או side-by-side חייבים לשמר את הסעיף שעליו הוחלה ההדגשה, אחרת ההדגשה תיעלם או תופיע בסעיף שגוי.',
      );

      original.dispose();
      cloned.dispose();
    });
  });

  group('OpenOrFocusTab עם pinpointHighlight על טאב קיים', () {
    setUp(() async {
      await Settings.init(cacheProvider: _MemoryCacheProvider());
    });

    test(
        'מחיל ApplyPinpointHighlight על ה-bloc של הטאב הקיים במקום לפתוח טאב חדש',
        () async {
      final tabsBloc = TabsBloc(repository: _FakeTabsRepository());

      // טאב קיים: bloc מוזרק עם repository מזויף שמביא ל‑Loaded מיידית.
      // האינדקס תואם ל‑incoming כי `_titlesMatch` נופל ל‑index כשאין TOC.
      final existingBloc = _createLoadedTextBookBloc(
        book: TextBook(id: 42, title: 'בראשית'),
        initialIndex: 5,
      );
      await existingBloc.stream.firstWhere((s) => s is TextBookLoaded);

      final existingTab = TextBookTab(
        book: TextBook(id: 42, title: 'בראשית'),
        index: 5,
        blocOverride: existingBloc,
      );

      tabsBloc.add(AddTab(existingTab));
      await tabsBloc.stream.firstWhere((s) => s.tabs.length == 1);

      // אותו ספר מגיע מ‑deep link עם הדגשה ממוקדת לסעיף 5.
      final incomingTab = TextBookTab(
        book: TextBook(id: 42, title: 'בראשית'),
        index: 5,
        pinpointHighlight: 'אור',
        pinpointHighlightSectionIndex: 5,
      );

      tabsBloc.add(OpenOrFocusTab(incomingTab));

      // ה-bloc של הטאב הקיים אמור לקבל ApplyPinpointHighlight ולעדכן state.
      final updated = await existingBloc.stream
          .firstWhere(
              (s) => s is TextBookLoaded && s.pinpointHighlightText == 'אור')
          .timeout(const Duration(seconds: 2)) as TextBookLoaded;

      expect(updated.pinpointHighlightIndex, 5);
      expect(updated.pinpointHighlightText, 'אור');
      expect(tabsBloc.state.tabs, hasLength(1),
          reason: 'אסור להוסיף טאב חדש; הטאב הקיים אמור להתעדכן.');
      expect(tabsBloc.state.currentTabIndex, 0);

      await _closeBlocAndAllowDeferredDispose(tabsBloc);
    });

    test(
        'מחיל ApplyPinpointHighlight כש‑bloc הקיים עדיין ב‑Initial וטוען רק אחרי כן',
        () async {
      final tabsBloc = TabsBloc(repository: _FakeTabsRepository());

      // bloc חדש שעדיין לא טען — נשאר ב‑TextBookInitial עד שנוסיף LoadContent.
      final repository = _PinpointFakeTextBookRepository();
      final existingBloc = TextBookBloc(
        repository: repository,
        initialState: TextBookInitial.named(
          TextBook(id: 99, title: 'שמות'),
          3,
          false,
          const [],
        ),
        scrollController: ItemScrollController(),
        positionsListener: ItemPositionsListener.create(),
      );

      final existingTab = TextBookTab(
        book: TextBook(id: 99, title: 'שמות'),
        index: 3,
        blocOverride: existingBloc,
      );
      tabsBloc.add(AddTab(existingTab));
      await tabsBloc.stream.firstWhere((s) => s.tabs.length == 1);

      // ההדגשה הממוקדת נשלחת לפני שה‑bloc הגיע ל‑Loaded — חייב להישאר ולהיות
      // מוחל ברגע שה‑Loaded מגיע.
      final incomingTab = TextBookTab(
        book: TextBook(id: 99, title: 'שמות'),
        index: 3,
        pinpointHighlight: 'משה',
        pinpointHighlightSectionIndex: 3,
      );
      tabsBloc.add(OpenOrFocusTab(incomingTab));

      // עכשיו טוענים את התוכן — ה‑bloc יעבור ל‑Loaded וה‑listener יזריק את
      // ApplyPinpointHighlight.
      existingBloc.add(const LoadContent(
        fontSize: 20,
        showSplitView: false,
        removeNikud: false,
        loadCommentators: false,
      ));

      final updated = await existingBloc.stream
          .firstWhere(
              (s) => s is TextBookLoaded && s.pinpointHighlightText == 'משה')
          .timeout(const Duration(seconds: 2)) as TextBookLoaded;

      expect(updated.pinpointHighlightIndex, 3);
      expect(updated.pinpointHighlightText, 'משה');
      expect(tabsBloc.state.tabs, hasLength(1));

      await _closeBlocAndAllowDeferredDispose(tabsBloc);
    });
  });
}

TextBookBloc _createLoadedTextBookBloc({
  required TextBook book,
  int initialIndex = 0,
}) {
  final bloc = TextBookBloc(
    repository: _PinpointFakeTextBookRepository(),
    initialState: TextBookInitial.named(book, initialIndex, false, const []),
    scrollController: ItemScrollController(),
    positionsListener: ItemPositionsListener.create(),
  );
  bloc.add(const LoadContent(
    fontSize: 20,
    showSplitView: false,
    removeNikud: false,
    loadCommentators: false,
  ));
  return bloc;
}

class _PinpointFakeTextBookRepository extends TextBookRepository {
  _PinpointFakeTextBookRepository() : super(fileSystem: FileSystemData.instance);

  @override
  Future<String> getBookContent(TextBook book) async {
    return List.generate(20, (index) => 'שורה $index').join('\n');
  }

  @override
  Future<List<TocEntry>> getTableOfContents(TextBook book) async => const [];

  @override
  Future<List<Link>> getBookLinksInRange(
    TextBook book, {
    required int startIndex,
    required int endIndex,
    Iterable<String>? targetBookTitles,
  }) async =>
      const [];

  @override
  Future<List<String>> getAvailableCommentators(TextBook book) async =>
      const [];
}

TextBookTab _createTextTab(String title, {int index = 0, int? categoryId}) {
  return TextBookTab(
    book: TextBook(title: title, categoryId: categoryId),
    index: index,
  );
}

/// Closes the bloc and waits for deferred tab disposal (350 ms timers) to settle.
Future<void> _closeBlocAndAllowDeferredDispose(TabsBloc bloc) async {
  await bloc.close();
  await Future<void>.delayed(const Duration(milliseconds: 400));
}

class _FakeTabsRepository extends TabsRepository {
  List<Map<String, dynamic>> _tabsJson = const [];
  int _currentTabIndex = 0;
  SideBySideMode? _sideBySideMode;

  @override
  List<OpenedTab> loadTabs() =>
      _tabsJson.map((tab) => TextBookTab.fromJson(tab)).toList();

  @override
  int loadCurrentTabIndex() => _currentTabIndex;

  @override
  SideBySideMode? loadSideBySideMode() => _sideBySideMode;

  @override
  Future<void> saveTabs(
    List<OpenedTab> tabs,
    int currentTabIndex, [
    SideBySideMode? sideBySideMode,
  ]) async {
    _tabsJson = tabs
        .map<Map<String, dynamic>>((tab) => tab.toJson())
        .toList(growable: false);
    _currentTabIndex = currentTabIndex;
    _sideBySideMode = sideBySideMode;
  }
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

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
