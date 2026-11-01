import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/utils/text/global_search_helper.dart';

import '../../helpers/memory_settings_cache.dart';

class _MockHistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {
  @override
  void add(HistoryEvent event) {}
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
  });

  testWidgets(
    'חיפוש בכל הספרים מטקסט מסומן מתחיל מברירות המחדל השמורות (issue #3690)',
    (tester) async {
      SearchDefaults.saveModeDefault(SearchMode.exact);
      SearchDefaults.saveDistanceDefault(3);
      SearchDefaults.saveExactDefaults(const {'קידומות דקדוקיות': true});
      final tabs = _RecordingTabsBloc();
      late BuildContext context;
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<HistoryBloc>.value(value: _MockHistoryBloc()),
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

      openGlobalSearch(context, 'תדע זרעך');

      final tab = tabs.sent.whereType<AddTab>().single.tab as SearchingTab;
      addTearDown(tab.dispose);
      final configuration = tab.searchBloc.state.configuration;
      expect(configuration.searchMode, SearchMode.exact);
      expect(configuration.distance, 3);
      expect(tab.globalSearchOptions['קידומות דקדוקיות'], isTrue);
    },
  );
}
