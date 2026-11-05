// #2826: קטעי תוצאות החיפוש לוקחים את גודל התוצאות, ולא את גודל הספר.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/view/tantivy_search_results.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  setUp(() {
    DataRepository.instance.library = Future.value(
      Library(categories: const []),
    );
  });

  /// גודל הגופן של הקטע: הספאן שבו מופיעה המילה "כי".
  Future<double?> snippetFontSize(
    WidgetTester tester,
    SettingsState settings,
  ) async {
    final searchBloc = _StaticSearchBloc();
    final settingsBloc = _MockSettingsBloc();
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: settings,
    );
    final tab = SearchingTab('חיפוש', 'תדע זרעך', searchBloc: searchBloc);
    addTearDown(() async {
      tab.dispose();
      await searchBloc.close();
      await settingsBloc.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SearchBloc>.value(value: searchBloc),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: Scaffold(body: TantivySearchResults(tab: tab)),
        ),
      ),
    );
    await tester.pump();

    double? size;
    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      rich.text.visitChildren((span) {
        if (span is TextSpan && (span.text ?? '').contains('כי')) {
          size ??= span.style?.fontSize;
        }
        return true;
      });
    }
    return size;
  }

  testWidgets('הקטע בגודל התוצאות, גם כשגודל הספר אחר', (tester) async {
    final size = await snippetFontSize(
      tester,
      SettingsState.initial().copyWith(fontSize: 34, searchResultsFontSize: 20),
    );
    expect(size, 20);
  });

  testWidgets('הגדלת הספר אינה מגדילה את התוצאות', (tester) async {
    final initial = SettingsState.initial();
    final size = await snippetFontSize(tester, initial.copyWith(fontSize: 40));
    expect(size, initial.searchResultsFontSize);
  });
}

class _StaticSearchBloc extends SearchBloc {
  _StaticSearchBloc() {
    emit(
      SearchState(
        searchQuery: 'תדע זרעך',
        totalResults: 1,
        results: [
          SearchResult(
            id: BigInt.one,
            title: 'בראשית',
            reference: 'בראשית, פרק טו',
            text: 'ידע תדע כי־גר יהיה זרעך',
            segment: BigInt.from(389),
            isPdf: false,
            filePath: 'id:1',
            mergedCount: 1,
            merged: const [],
            textStatus: TextStatus.ok,
            continuesToNextLine: false,
          ),
        ],
      ),
    );
  }

  @override
  void add(SearchEvent event) {}
}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}
