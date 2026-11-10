import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_spinbox/flutter_spinbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/view/full_text_settings_widgets.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

class _RecordingSearchBloc extends SearchBloc {
  final recorded = <SearchEvent>[];

  @override
  void add(SearchEvent event) {
    recorded.add(event);
    // Observe search requests without launching the real search engine.
    if (event is UpdateDistance || event is UpdateWordMatchMode) return;
    super.add(event);
  }
}

void main() {
  Widget harness(SearchBloc bloc, SearchingTab tab, {bool triggerSearch = true}) {
    return MaterialApp(
      home: BlocProvider<SearchBloc>.value(
        value: bloc,
        child: Scaffold(
          body: FuzzyDistance(tab: tab, triggerSearch: triggerSearch),
        ),
      ),
    );
  }

  testWidgets('rapid distance changes schedule just the last search',
      (tester) async {
    final tab = SearchingTab('חיפוש', null);
    final bloc = _RecordingSearchBloc();
    addTearDown(bloc.close);
    addTearDown(tab.searchBloc.close);
    await tester.pumpWidget(harness(bloc, tab));

    final field = tester.widget<SpinBox>(find.byType(SpinBox));
    field.onChanged!(1);
    await tester.pump(const Duration(milliseconds: 90));
    field.onChanged!(2);
    await tester.pump(const Duration(milliseconds: 90));
    field.onChanged!(3);
    await tester.pump(const Duration(milliseconds: 249));

    expect(bloc.recorded.whereType<UpdateDistance>(), isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    final searches = bloc.recorded.whereType<UpdateDistance>().toList();
    expect(searches, hasLength(1));
    expect(searches.single.distance, 3);
  });

  testWidgets('a canceled or disposed input does not launch a stale search',
      (tester) async {
    final tab = SearchingTab('חיפוש', null);
    final bloc = _RecordingSearchBloc();
    addTearDown(bloc.close);
    addTearDown(tab.searchBloc.close);
    await tester.pumpWidget(harness(bloc, tab));

    tester.widget<SpinBox>(find.byType(SpinBox)).onChanged!(
      (bloc.state.distance + 1).toDouble(),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));

    expect(bloc.recorded.whereType<UpdateDistance>(), isEmpty);
    final saved = bloc.recorded.whereType<UpdateDistanceWithoutSearch>().toList();
    expect(saved, hasLength(1));
    expect(saved.single.distance, 1);
  });

  testWidgets('actual rapid plus taps coalesce into one search',
      (tester) async {
    final tab = SearchingTab('חיפוש', null);
    final bloc = _RecordingSearchBloc();
    addTearDown(bloc.close);
    addTearDown(tab.searchBloc.close);
    await tester.pumpWidget(harness(bloc, tab));

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(bloc.recorded.whereType<UpdateDistance>(), isEmpty);
    await tester.pump(const Duration(milliseconds: 250));

    final searches = bloc.recorded.whereType<UpdateDistance>().toList();
    expect(searches, hasLength(1));
    expect(searches.single.distance, 3);
  });

  testWidgets('changing tabs retains the edit without a search',
      (tester) async {
    final firstTab = SearchingTab('חיפוש ראשון', null);
    final secondTab = SearchingTab('חיפוש שני', null);
    final bloc = _RecordingSearchBloc();
    addTearDown(bloc.close);
    addTearDown(firstTab.searchBloc.close);
    addTearDown(secondTab.searchBloc.close);
    await tester.pumpWidget(harness(bloc, firstTab));

    tester.widget<SpinBox>(find.byType(SpinBox)).onChanged!(4);
    await tester.pumpWidget(harness(bloc, secondTab));
    await tester.pump(const Duration(milliseconds: 500));

    expect(bloc.recorded.whereType<UpdateDistance>(), isEmpty);
    final silent = bloc.recorded.whereType<UpdateDistanceWithoutSearch>();
    expect(silent, hasLength(1));
    expect(silent.single.distance, 4);
  });

  testWidgets('silent mode keeps immediate state-only updates',
      (tester) async {
    final tab = SearchingTab('חיפוש', null);
    final bloc = _RecordingSearchBloc();
    addTearDown(bloc.close);
    addTearDown(tab.searchBloc.close);
    await tester.pumpWidget(
      harness(bloc, tab, triggerSearch: false),
    );

    tester.widget<SpinBox>(find.byType(SpinBox)).onChanged!(2);
    expect(bloc.recorded.whereType<UpdateDistanceWithoutSearch>(),
        hasLength(1));
    expect(bloc.recorded.whereType<UpdateDistance>(), isEmpty);
  });

  testWidgets('returning to the current value cancels a scheduled search',
      (tester) async {
    final tab = SearchingTab('חיפוש', null);
    final bloc = _RecordingSearchBloc();
    addTearDown(bloc.close);
    addTearDown(tab.searchBloc.close);
    await tester.pumpWidget(harness(bloc, tab));

    final field = tester.widget<SpinBox>(find.byType(SpinBox));
    final initialValue = bloc.state.distance;
    field.onChanged!((initialValue + 1).toDouble());
    field.onChanged!(initialValue.toDouble());
    await tester.pump(const Duration(milliseconds: 500));
    expect(bloc.recorded.whereType<UpdateDistance>(), isEmpty);
  });
  testWidgets('unrelated search state updates do not rebuild the spinbox',
      (tester) async {
    final tab = SearchingTab('חיפוש', null);
    final bloc = _RecordingSearchBloc();
    addTearDown(bloc.close);
    addTearDown(tab.searchBloc.close);
    await tester.pumpWidget(harness(bloc, tab));

    final spinBox = tester.widget<SpinBox>(find.byType(SpinBox));
    bloc.add(UpdateFilterQuery('test'));
    await tester.pumpAndSettle();

    expect(tester.widget<SpinBox>(find.byType(SpinBox)), same(spinBox));
    bloc.add(UpdateDistanceWithoutSearch(7));
    await tester.pumpAndSettle();
    expect(tester.widget<SpinBox>(find.byType(SpinBox)).value, 7);
  });

}
