import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_search_dialog_registry.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/tantivy_full_text_search.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

import '../support/search_engine_test_init.dart';

class _StaticSearchBloc extends SearchBloc {
  _StaticSearchBloc(SearchState initialState) {
    emit(initialState);
  }

  void set(SearchState state) => emit(state);

  @override
  void add(SearchEvent event) {}
}

/// כפתור `resultsAction` בטאב החיפוש: מוצג רק אחרי שהחיפוש הסתיים, ולחיצה
/// מעבירה לתוסף את אותו חיפוש באותו חוזה של שליחת הדיאלוג.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  late _StaticSearchBloc searchBloc;
  late SearchingTab tab;
  late PluginSearchDialogRegistry registry;
  late List<(String, Map<String, dynamic>)> launches;

  const finished = SearchState(
    searchQuery: 'שבת',
    negativeQuery: 'גוי',
    configuration: SearchConfiguration(
      searchMode: SearchMode.advanced,
      distance: 2,
      currentFacets: ['/הלכה'],
      searchScopeFacets: ['/הלכה'],
    ),
  );

  setUp(() {
    searchBloc = _StaticSearchBloc(finished);
    tab = SearchingTab('חיפוש', 'שבת', searchBloc: searchBloc);
    tab.negativeQueryController.text = 'גוי';
    registry = PluginSearchDialogRegistry.forTesting();
    registry.registerPayload('test.plugin', {
      'id': 'external',
      'type': 'checkbox',
      'title': 'חפש במקור חיצוני',
      'openPluginOnSubmit': true,
      'resultsAction': 'המשך במקור החיצוני',
      'visibleInModes': ['advanced'],
    });
    launches = [];
  });

  tearDown(() async {
    registry.dispose();
    tab.dispose();
    await searchBloc.close();
  });

  Future<void> pump(WidgetTester tester, {bool iconOnly = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PluginSearchResultsActions(
            tab: tab,
            iconOnly: iconOnly,
            registry: registry,
            launcher: (pluginId, payload) => launches.add((pluginId, payload)),
          ),
        ),
      ),
    );
  }

  testWidgets('מוצג רק אחרי שהחיפוש הסתיים, גם בלי תוצאות', (tester) async {
    final button = find.text('המשך במקור החיצוני');
    Future<void> emit(SearchState state) async {
      searchBloc.set(state);
      await tester.pumpAndSettle();
    }

    await pump(tester);
    expect(button, findsOneWidget);

    await emit(finished.copyWith(isLoading: true));
    expect(button, findsNothing);

    await emit(finished.copyWith(errorMessage: 'נכשל'));
    expect(button, findsNothing);

    await emit(finished.copyWith(searchQuery: ''));
    expect(button, findsNothing);

    await emit(finished);
    expect(button, findsOneWidget);
  });

  testWidgets('שורה בלי resultsAction או מחוץ למצב החיפוש אינה מציגה כפתור', (
    tester,
  ) async {
    registry.registerPayload('other.plugin', {
      'id': 'no-action',
      'type': 'checkbox',
      'title': 'בלי כפתור',
      'openPluginOnSubmit': true,
    });
    searchBloc.set(
      finished.copyWith(
        configuration: finished.configuration.copyWith(
          searchMode: SearchMode.exact,
        ),
      ),
    );
    await pump(tester);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byTooltip('המשך במקור החיצוני'), findsNothing);
  });

  testWidgets('בסרגל צר מוצג אייקון בלבד, והכותרת ב-tooltip', (tester) async {
    await pump(tester, iconOnly: true);
    expect(find.text('המשך במקור החיצוני'), findsNothing);
    expect(find.byTooltip('המשך במקור החיצוני'), findsOneWidget);
  });

  testWidgets(
    'לחיצה שולחת search.requested עם השאילתה, ההיקף והשלילה של הטאב',
    (tester) async {
      await pump(tester);
      await tester.tap(find.text('המשך במקור החיצוני'));
      await tester.pump();

      expect(launches, hasLength(1));
      expect(launches.single.$1, 'test.plugin');
      expect(launches.single.$2['itemId'], 'external');
      final request = launches.single.$2['request'] as Map<String, dynamic>;
      expect(request['query'], 'שבת');
      expect(request['mode'], 'advanced');
      expect(request['distance'], 2);
      expect(request['facets'], ['/הלכה']);
      expect(request['negativeQuery'], 'גוי');
    },
    skip: !engineReady,
  );
}
