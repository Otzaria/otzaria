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

class MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class RecordingSearchBloc extends SearchBloc {
  RecordingSearchBloc(this.initialSearchState) {
    emit(initialSearchState);
  }

  final SearchState initialSearchState;

  @override
  void add(SearchEvent event) {
    if (event is! LoadMoreResults) {
      super.add(event);
    }
  }
}

void main() {
  testWidgets('מצב אין תוצאות מציג הנחיה מועילה למשתמש', (
    WidgetTester tester,
  ) async {
    final searchBloc = RecordingSearchBloc(
      const SearchState(
        searchQuery: 'בדיקה',
        totalResults: 0,
        results: [],
      ),
    );
    final settingsBloc = MockSettingsBloc();
    final tab = SearchingTab('חיפוש', 'בדיקה');

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

    expect(find.text('אין תוצאות'), findsOneWidget);
    expect(
      find.text(
        'נסה להרחיב קטגוריות, לשנות מצב חיפוש או לעדכן את מילות החיפוש.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'חיפוש שנחתך לאפס תוצאות מציג הודעת מגבלת חיפוש ולא "אין תוצאות"',
    (WidgetTester tester) async {
      final searchBloc = RecordingSearchBloc(
        const SearchState(
          searchQuery: 'בדיקה',
          totalResults: 0,
          results: [],
          resultsTruncated: true,
        ),
      );
      final settingsBloc = MockSettingsBloc();
      final tab = SearchingTab('חיפוש', 'בדיקה');

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

      expect(find.text('הגעת למגבלת אפשרויות החיפוש'), findsOneWidget);
      expect(find.text('אין תוצאות'), findsNothing);
    },
  );
}
