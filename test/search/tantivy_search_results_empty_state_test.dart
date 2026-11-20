import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/external_search_status.dart';
import 'package:otzaria/search/view/external_search_results_section.dart';
import 'package:otzaria/search/view/tantivy_search_results.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/widgets/feedback/otzaria_error_state.dart';

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

  // כשל חיפוש מוצג כמצב שגיאה אחיד (אייקון, כותרת, דרך חזרה), לא כטקסט אדום.
  testWidgets(
    'כשל חיפוש בלי תוצאות מציג מצב שגיאה אחיד עם דרך לערוך את החיפוש',
    (
      WidgetTester tester,
    ) async {
      final searchBloc = RecordingSearchBloc(
        const SearchState(
          searchQuery: 'בדיקה',
          results: [],
          errorMessage: 'אירעה שגיאה בעת החיפוש',
        ),
      );
      final settingsBloc = MockSettingsBloc();
      final tab = SearchingTab('חיפוש', 'בדיקה');
      var edited = 0;

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
                child: TantivySearchResults(
                  tab: tab,
                  onEditSearch: () => edited++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(OtzariaErrorState), findsOneWidget);
      expect(find.text('אירעה שגיאה בעת החיפוש'), findsOneWidget);
      expect(find.text('אין תוצאות'), findsNothing);

      await tester.tap(find.text('ערוך חיפוש'));
      expect(edited, 1);
    },
  );

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

  testWidgets('הבלוק החיצוני יושב בתוך רשימת הגלילה המאוחדת', (
    WidgetTester tester,
  ) async {
    final searchBloc = RecordingSearchBloc(
      const SearchState(searchQuery: 'בדיקה', totalResults: 0, results: []),
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

    // מסך אחד: המדור החיצוני הוא sliver באותו CustomScrollView של תוצאות
    // המנוע — לא מדור נפרד עם גלילה משלו. (skipOffstage: בלי ספק פעיל
    // ה-sliver ריק ולכן נחשב offstage.)
    expect(
      find.descendant(
        of: find.byType(CustomScrollView, skipOffstage: false),
        matching: find.byType(
          ExternalSearchResultsSection,
          skipOffstage: false,
        ),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets('מצב-ריק של המנוע קומפקטי כשמקור חיצוני פעיל, וממלא-מסך בלעדיו', (
    WidgetTester tester,
  ) async {
    final searchBloc = RecordingSearchBloc(
      const SearchState(searchQuery: 'בדיקה', totalResults: 0, results: []),
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

    // בלי מקור חיצוני — מצב-הריק ממלא את שארית המסך (המראה המקורי).
    expect(find.byType(SliverFillRemaining), findsOneWidget);

    // מקור חיצוני פעיל — מצב-הריק מצטמצם כדי לא לדחוק את התוצאות
    // החיצוניות אל מחוץ למסך, אך ההודעה עצמה נשארת.
    tab.externalSearchStatus.value = const ExternalSearchStatus(
      sourceTitle: 'היברובוקס',
      loading: false,
      books: 3,
      hits: 7,
    );
    await tester.pump();

    expect(find.byType(SliverFillRemaining), findsNothing);
    expect(find.text('אין תוצאות'), findsOneWidget);
  });
}
