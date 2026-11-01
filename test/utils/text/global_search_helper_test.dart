import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:otzaria/semantic_search/repository/semantic_platform_support.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/semantic_search_tab.dart';
import 'package:otzaria/text_book/utils/reader_menu_entries.dart';
import 'package:otzaria/utils/text/global_search_helper.dart';

import '../../helpers/memory_settings_cache.dart';

class _MockHistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {
  final sent = <HistoryEvent>[];

  @override
  void add(HistoryEvent event) => sent.add(event);
}

class _RecordingTabsBloc extends MockBloc<TabsEvent, TabsState>
    implements TabsBloc {
  final sent = <TabsEvent>[];

  @override
  void add(TabsEvent event) => sent.add(event);
}

void main() {
  setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));

  tearDown(() {
    SearchDefaults.saveModeDefault(SearchMode.exact);
    SearchDefaults.saveDistanceDefault(0);
    SearchDefaults.saveExactDefaults(const {});
    SearchDefaults.saveSemanticIncludeLexicalDefault(true);
    SearchDefaults.saveSemanticGroupIdenticalDefault(true);
  });

  Future<BuildContext> pumpProviders(
    WidgetTester tester,
    _RecordingTabsBloc tabs, {
    _MockHistoryBloc? history,
  }) async {
    late BuildContext context;
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<HistoryBloc>.value(value: history ?? _MockHistoryBloc()),
          BlocProvider<TabsBloc>.value(value: tabs),
        ],
        child: Builder(
          builder: (ctx) {
            context = ctx;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return context;
  }

  testWidgets(
    'חיפוש בכל הספרים מטקסט מסומן מתחיל מברירות המחדל השמורות (issue #3690)',
    (tester) async {
      SearchDefaults.saveModeDefault(SearchMode.exact);
      SearchDefaults.saveDistanceDefault(3);
      SearchDefaults.saveExactDefaults(const {'קידומות דקדוקיות': true});
      final tabs = _RecordingTabsBloc();
      final context = await pumpProviders(tester, tabs);

      openGlobalSearch(context, 'תדע זרעך');

      final tab = tabs.sent.whereType<AddTab>().single.tab as SearchingTab;
      addTearDown(tab.dispose);
      final configuration = tab.searchBloc.state.configuration;
      expect(configuration.searchMode, SearchMode.exact);
      expect(configuration.distance, 3);
      expect(tab.globalSearchOptions['קידומות דקדוקיות'], isTrue);
    },
  );

  group('ברירת המחדל היא החיפוש החכם (issue #3527)', () {
    setUp(() {
      SearchDefaults.saveSemanticDefault();
      SearchDefaults.saveSemanticIncludeLexicalDefault(false);
      SearchDefaults.saveSemanticGroupIdenticalDefault(false);
    });

    void expectSemanticTab(_RecordingTabsBloc tabs, String query) {
      final add = tabs.sent.whereType<AddTab>().single;
      final tab = add.tab;
      addTearDown(tab.dispose);
      expect(tab, isA<SemanticSearchTab>());
      final options = (tab as SemanticSearchTab).options;
      expect(options.query, query);
      expect(options.facets, ['/'], reason: 'חיפוש בכל הספרים');
      expect(options.includeLexical, isFalse);
      expect(options.groupIdenticalText, isFalse);
      expect(tab.runOnFirstShow, isTrue);
      expect(add.insertAdjacent, isTrue);
    }

    testWidgets('חיפוש מטקסט מסומן נפתח כחיפוש חכם', (tester) async {
      final tabs = _RecordingTabsBloc();
      final history = _MockHistoryBloc();
      final context = await pumpProviders(tester, tabs, history: history);

      openGlobalSearch(context, 'תדע זרעך', platformSupported: true);

      expectSemanticTab(tabs, 'תדע זרעך');
      expect(history.sent, isEmpty);
    });

    testWidgets('"חיפוש" בתפריט הספר מכבד את ברירת המחדל ואת תמיכת הפלטפורמה', (
      tester,
    ) async {
      final tabs = _RecordingTabsBloc();
      final context = await pumpProviders(tester, tabs);
      final row = buildReaderIconRow(
        context: context,
        selection: ReaderMenuSelection('תֵּדַע\nזַרְעֲךָ'),
        book: TextBook(title: 'ספר בדיקה'),
        paragraphIndex: 0,
        selectedText: 'תֵּדַע\nזַרְעֲךָ',
        onCopy: () {},
        onAddNote: () {},
      );

      row.iconRowActions!.firstWhere((a) => a.label == 'חיפוש').onTap!();

      if (isSemanticSearchPlatformSupported()) {
        expectSemanticTab(tabs, 'תדע זרעך');
      } else {
        final tab = tabs.sent.whereType<AddTab>().single.tab as SearchingTab;
        addTearDown(tab.dispose);
        expect(tab, isNot(isA<SemanticSearchTab>()));
        expect(tab.queryController.text, 'תדע זרעך');
      }
    });

    testWidgets(
      'הגדרת חיפוש חכם ניידת חוזרת לחיפוש מילולי בפלטפורמה לא נתמכת',
      (
        tester,
      ) async {
        expect(
          BackupService.isPortableSettingKey(
            'key-search-default-semantic-mode',
          ),
          isTrue,
        );
        SearchDefaults.saveModeDefault(SearchMode.exact);
        SearchDefaults.saveDistanceDefault(3);
        SearchDefaults.saveExactDefaults(const {'קידומות דקדוקיות': true});
        SearchDefaults.saveSemanticDefault();
        final tabs = _RecordingTabsBloc();
        final history = _MockHistoryBloc();
        final context = await pumpProviders(tester, tabs, history: history);

        openGlobalSearch(
          context,
          '  תדע זרעך  ',
          insertAdjacent: false,
          platformSupported: false,
        );

        final add = tabs.sent.whereType<AddTab>().single;
        final tab = add.tab as SearchingTab;
        addTearDown(tab.dispose);
        expect(tab, isNot(isA<SemanticSearchTab>()));
        expect(tab.queryController.text, 'תדע זרעך');
        expect(tab.searchBloc.state.configuration.searchMode, SearchMode.exact);
        expect(tab.searchBloc.state.configuration.distance, 3);
        expect(tab.globalSearchOptions['קידומות דקדוקיות'], isTrue);
        expect(add.insertAdjacent, isFalse);
        expect(history.sent.whereType<AddHistory>().single.tab, same(tab));
        expect(SearchDefaults.initialSemanticForNewSearch(), isTrue);
        expect(SearchDefaults.loadSemanticDefault(), isTrue);
      },
    );
  });
}
