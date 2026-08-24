import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/plugins/services/plugin_reader_actions.dart';
import 'package:otzaria/plugins/services/plugin_ref_line_resolver.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';

import '../../test_helpers/memory_cache_provider.dart';
import '../../support/search_engine_test_init.dart';

class _MockNavigationBloc extends Mock implements NavigationBloc {}

class _CapturingTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _CapturingTabsBloc([TabsState? initial])
    : super(initial ?? const TabsState(tabs: [], currentTabIndex: 0));

  final List<TabsEvent> captured = [];

  @override
  void add(TabsEvent event) => captured.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CapturingHistoryBloc extends Cubit<HistoryState> implements HistoryBloc {
  _CapturingHistoryBloc() : super(HistoryInitial());

  final List<HistoryEvent> captured = [];

  @override
  void add(HistoryEvent event) => captured.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TextBookTab _loadedTextTab() {
  final tab = TextBookTab(
    book: TextBook(title: 'ספר בדיקה לגלילה'),
    index: 0,
  );
  tab.bloc.emit(
    TextBookLoaded.initial(
      book: tab.book,
      index: 0,
      showLeftPane: false,
      splitView: false,
    ).copyWith(
      content: const ['א', 'ב', 'ג', 'ד'],
      permanentHighlightLine: 9,
    ),
  );
  return tab;
}

void main() {
  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('PluginReaderScrollService', () {
    test('גולל ספר טקסט פתוח דרך ה-bloc שלו', () async {
      final tab = _loadedTextTab();
      final tabsBloc = _CapturingTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );

      expect(PluginReaderScrollService(tabsBloc).scrollToSection(2), isTrue);
      await Future<void>.delayed(Duration.zero);
      // גלילה ללא highlight מנקה סימון קודם; עם highlight מסמנת את היעד.
      expect((tab.bloc.state as TextBookLoaded).permanentHighlightLine, isNull);
      expect(
        PluginReaderScrollService(tabsBloc).scrollToSection(2, highlight: true),
        isTrue,
      );
      await Future<void>.delayed(Duration.zero);
      expect((tab.bloc.state as TextBookLoaded).permanentHighlightLine, 2);
    });

    test('אינדקס שלילי וחלונית חסרה מוחזרים כ-false', () {
      final tab = _loadedTextTab();
      final withTab = _CapturingTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );
      expect(PluginReaderScrollService(withTab).scrollToSection(-1), isFalse);
      expect(
        PluginReaderScrollService(_CapturingTabsBloc()).scrollToSection(0),
        isFalse,
      );
    });
  });

  group('PluginDeclarativeReaderScroller', () {
    test('הפניה שנפתרת לשורה גוללת את הספר הפתוח', () async {
      final tab = _loadedTextTab();
      final tabsBloc = _CapturingTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );
      final scroller = PluginDeclarativeReaderScroller(
        tabsBloc: tabsBloc,
        refResolver: PluginRefLineResolver(
          fetchLineRefs: (book) async => [
            (lineIndex: 3, heRef: '${book.title} לג ה'),
          ],
        ),
      );

      expect(await scroller.scrollToRef('לג:ה', highlight: true), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect((tab.bloc.state as TextBookLoaded).permanentHighlightLine, 3);
    });

    test('הפניה שאינה נפתרת מחזירה false ואינה גוללת', () async {
      final tab = _loadedTextTab();
      final tabsBloc = _CapturingTabsBloc(
        TabsState(tabs: [tab], currentTabIndex: 0),
      );
      final scroller = PluginDeclarativeReaderScroller(
        tabsBloc: tabsBloc,
        refResolver: PluginRefLineResolver(
          fetchLineRefs: (_) async => const [],
        ),
      );

      expect(await scroller.scrollToRef('לג:ה', highlight: true), isFalse);
      expect((tab.bloc.state as TextBookLoaded).permanentHighlightLine, 9);
    });

    test('הפניה ריקה וללא ספר פתוח — false', () async {
      final scroller = PluginDeclarativeReaderScroller(
        tabsBloc: _CapturingTabsBloc(),
        refResolver: PluginRefLineResolver(
          fetchLineRefs: (_) async => const [],
        ),
      );
      expect(await scroller.scrollToRef('   '), isFalse);
      expect(await scroller.scrollToRef('לג:ה'), isFalse);
    });
  });

  group('PluginDeclarativeSearchOpener', () {
    test('פותח כרטיסיית חיפוש עם השאילתה', () async {
      if (!await tryInitSearchEngine()) {
        markTestSkipped(searchEngineSkipReason);
        return;
      }
      final tabsBloc = _CapturingTabsBloc();
      final historyBloc = _CapturingHistoryBloc();
      final opener = PluginDeclarativeSearchOpener(
        BookOpenCoordinator(
          tabsBloc: tabsBloc,
          historyBloc: historyBloc,
          navigationBloc: _MockNavigationBloc(),
        ),
      );

      expect(await opener.openSearch('בראשית ברא'), isTrue);
      final added = tabsBloc.captured.whereType<AddTab>().single;
      final tab = added.tab as SearchingTab;
      expect(tab.queryController.text, 'בראשית ברא');
      expect(historyBloc.captured, hasLength(1));
    });

    test('שאילתה ריקה אינה פותחת טאב', () async {
      final tabsBloc = _CapturingTabsBloc();
      final opener = PluginDeclarativeSearchOpener(
        BookOpenCoordinator(
          tabsBloc: tabsBloc,
          historyBloc: _CapturingHistoryBloc(),
          navigationBloc: _MockNavigationBloc(),
        ),
      );
      expect(await opener.openSearch('  '), isFalse);
      expect(tabsBloc.captured, isEmpty);
    });
  });

  // ההוספה למנוע הדקלרטיבי בלי חיווט ב-main.dart נכשלת בשקט
  // ב-declarative.service_unavailable, ולכן החיווט עצמו נשמר בבדיקה.
  group('חיווט המנוע הדקלרטיבי ב-main.dart', () {
    test(
      'readerScroller ו-searchOpener מועברים ל-DeclarativePluginHostService',
      () {
        final source = File('lib/main.dart').readAsStringSync();
        final start = source.indexOf('DeclarativePluginHostService(');
        expect(start, greaterThan(-1));
        final block = source.substring(start, start + 1200);
        expect(block, contains('readerScroller:'));
        expect(block, contains('searchOpener:'));
        expect(block, contains('PluginDeclarativeReaderScroller'));
        expect(block, contains('PluginDeclarativeSearchOpener'));
      },
    );
  });
}
