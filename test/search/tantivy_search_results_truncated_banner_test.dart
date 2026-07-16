import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/view/tantivy_search_results.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

class MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class RecordingSearchBloc extends SearchBloc {
  RecordingSearchBloc(SearchState initialSearchState) {
    emit(initialSearchState);
  }

  @override
  void add(SearchEvent event) {
    if (event is! LoadMoreResults) {
      super.add(event);
    }
  }
}

const _bannerNeedle = 'ייתכן שהתוצאות חלקיות';

SearchResult _result(int i) => SearchResult(
    id: BigInt.from(i),
    title: 'ספר $i',
    reference: 'סימן $i',
    text: 'טקסט בדיקה $i',
    segment: BigInt.from(i),
    isPdf: false,
    filePath: 'book_$i.txt',
    mergedCount: 1,
    merged: const []);

Future<void> _pumpResults(
  WidgetTester tester, {
  required bool truncated,
}) async {
  final searchBloc = RecordingSearchBloc(
    SearchState(
      searchQuery: 'ספר',
      totalResults: 2,
      results: [_result(1), _result(2)],
      resultsTruncated: truncated,
    ),
  );
  final settingsBloc = MockSettingsBloc();
  final tab = SearchingTab('חיפוש', 'ספר');

  whenListen(
    settingsBloc,
    const Stream<SettingsState>.empty(),
    initialState: SettingsState.initial(),
  );

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
        child: Scaffold(
          body: SizedBox(
            height: 500,
            child: TantivySearchResults(tab: tab),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('באנר "תוצאות חלקיות" מוצג כשהחיפוש חרג מתקציב האיסוף',
      (WidgetTester tester) async {
    await _pumpResults(tester, truncated: true);
    expect(find.textContaining(_bannerNeedle), findsOneWidget);
  });

  testWidgets('הבאנר אינו מוצג כשהתוצאות מלאות', (WidgetTester tester) async {
    await _pumpResults(tester, truncated: false);
    expect(find.textContaining(_bannerNeedle), findsNothing);
  });
}
