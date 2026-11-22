import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/tantivy_search_results.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/widgets/feedback/app_info_banner.dart';
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
  merged: const [],
  textStatus: TextStatus.ok,
  continuesToNextLine: false,
);

Future<void> _pumpResults(
  WidgetTester tester, {
  required bool truncated,
  List<String> facets = const ['/'],
}) async {
  final searchBloc = RecordingSearchBloc(
    SearchState(
      searchQuery: 'ספר',
      totalResults: 2,
      results: [_result(1), _result(2)],
      resultsTruncated: truncated,
      configuration: SearchConfiguration(
        currentFacets: facets,
        searchScopeFacets: facets,
      ),
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
  testWidgets('באנר "תוצאות חלקיות" מוצג כשהחיפוש חרג מתקציב האיסוף', (
    WidgetTester tester,
  ) async {
    await _pumpResults(tester, truncated: true);
    expect(find.textContaining(_bannerNeedle), findsOneWidget);
    // UI-012: הבאנר הוא AppInfoBanner בטון אזהרה, לא Container ידני.
    final banner = tester.widget<AppInfoBanner>(find.byType(AppInfoBanner));
    expect(banner.tone, AppInfoBannerTone.warning);
  });

  testWidgets('הבאנר אינו מוצג כשהתוצאות מלאות', (WidgetTester tester) async {
    await _pumpResults(tester, truncated: false);
    expect(find.textContaining(_bannerNeedle), findsNothing);
  });

  group('באנר תוצאות חלקיות בחיפוש מסונן (issue #5759)', () {
    String bannerText(WidgetTester tester) =>
        tester.widget<AppInfoBanner>(find.byType(AppInfoBanner)).message;

    testWidgets('חיפוש בספרים נבחרים: הבאנר אומר שהקיצור חל גם בתוכם', (
      WidgetTester tester,
    ) async {
      await _pumpResults(
        tester,
        truncated: true,
        facets: const ['/תלמוד בבלי/סדר טהרות/נדה'],
      );
      final text = bannerText(tester);
      expect(text, contains(_bannerNeedle));
      expect(text, contains('גם בתוך הספרים שנבחרו'));
      expect(text, contains('קידומות'));
      // צמצום ההיקף אינו עוזר — אסור לרמוז שהחיפוש "רחב מדי".
      expect(text, isNot(contains('רחב מדי')));
    });

    testWidgets('סינון ממדי (תקופה) על כל הספרייה נחשב חיפוש מסונן', (
      WidgetTester tester,
    ) async {
      await _pumpResults(
        tester,
        truncated: true,
        facets: const ['/', '/era/ראשונים'],
      );
      expect(bannerText(tester), contains('גם בתוך הספרים שנבחרו'));
    });

    testWidgets('חיפוש בכל הספרייה: ניסוח כללי ואותה עצה', (
      WidgetTester tester,
    ) async {
      await _pumpResults(tester, truncated: true);
      final text = bannerText(tester);
      expect(text, contains(_bannerNeedle));
      expect(text, isNot(contains('גם בתוך הספרים שנבחרו')));
      expect(text, contains('קידומות'));
      expect(text, isNot(contains('רחב מדי')));
    });

    testWidgets('בלי חריגה מהתקציב אין באנר גם בחיפוש מסונן', (
      WidgetTester tester,
    ) async {
      await _pumpResults(
        tester,
        truncated: false,
        facets: const ['/תלמוד בבלי/סדר טהרות/נדה'],
      );
      expect(find.byType(AppInfoBanner), findsNothing);
    });
  });
}
