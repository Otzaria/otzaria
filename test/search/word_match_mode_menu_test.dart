import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_spinbox/flutter_spinbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/full_text_settings_widgets.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

void main() {
  Widget harness(SearchBloc bloc, SearchingTab tab) {
    return MaterialApp(
      home: BlocProvider<SearchBloc>.value(
        value: bloc,
        child: Scaffold(
          body: Center(
            child: FuzzyDistance(tab: tab, triggerSearch: false),
          ),
        ),
      ),
    );
  }

  group('תפריט מצב התאמת המילים', () {
    testWidgets('בחירת "מילה אחת לפחות" מעדכנת את ה-state ומשביתה את המרווח',
        (tester) async {
      final tab = SearchingTab('חיפוש', null);
      final bloc = tab.searchBloc;
      addTearDown(bloc.close);

      await tester.pumpWidget(harness(bloc, tab));
      expect(bloc.state.wordMatchMode, WordMatchMode.all);

      await tester.tap(find.byIcon(FluentIcons.multiselect_rtl_24_regular));
      await tester.pumpAndSettle();
      // כל ארבע האפשרויות מוצגות בתפריט.
      for (final mode in WordMatchMode.values) {
        expect(find.text(mode.label), findsOneWidget);
      }

      await tester.tap(find.text(WordMatchMode.anyWord.label));
      await tester.pumpAndSettle();

      expect(bloc.state.wordMatchMode, WordMatchMode.anyWord);
      // שדה המרווח מושבת ומציג את שם המצב במקומו.
      final spinBox = tester.widget<SpinBox>(find.byType(SpinBox));
      expect(spinBox.enabled, isFalse);
      expect(find.text(WordMatchMode.anyWord.label), findsOneWidget);
    });

    testWidgets('בחירת "לפחות X מילים" מציגה שדה מספר שמעדכן את ה-state',
        (tester) async {
      final tab = SearchingTab('חיפוש', null);
      final bloc = tab.searchBloc;
      addTearDown(bloc.close);

      await tester.pumpWidget(harness(bloc, tab));
      await tester.tap(find.byIcon(FluentIcons.multiselect_rtl_24_regular));
      await tester.pumpAndSettle();
      await tester.tap(find.text(WordMatchMode.atLeast.label));
      await tester.pumpAndSettle();

      expect(bloc.state.wordMatchMode, WordMatchMode.atLeast);
      expect(find.text('מספר מילים'), findsOneWidget);
      // ברירת המחדל 2; לחיצה על פלוס מעלה ל-3 ומעדכנת את ה-state.
      expect(bloc.state.wordMatchCount, 2);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(bloc.state.wordMatchCount, 3);
    });

    testWidgets('במצב שאינו מתקדם התפריט אינו מוצג', (tester) async {
      final tab = SearchingTab('חיפוש', null);
      final bloc = tab.searchBloc;
      addTearDown(bloc.close);
      bloc.add(SetSearchModeWithoutSearch(SearchMode.exact));

      await tester.pumpWidget(harness(bloc, tab));
      await tester.pumpAndSettle();
      expect(
        find.byIcon(FluentIcons.multiselect_rtl_24_regular),
        findsNothing,
      );
    });
  });

  group('SearchConfiguration — wordMatchMode', () {
    test('toMap/fromMap משמרים מצב וספירה', () {
      const config = SearchConfiguration(
        wordMatchMode: WordMatchMode.atLeast,
        wordMatchCount: 4,
      );
      final restored = SearchConfiguration.fromMap(config.toMap());
      expect(restored.wordMatchMode, WordMatchMode.atLeast);
      expect(restored.wordMatchCount, 4);
      expect(restored, config);
    });

    test('ערך אינדקס לא מוכר במפה נופל לברירת המחדל', () {
      final restored = SearchConfiguration.fromMap({'wordMatchMode': 99});
      expect(restored.wordMatchMode, WordMatchMode.all);
    });

    test('אינדקסים שליליים או לא-מספריים אינם זורקים RangeError', () {
      final restored = SearchConfiguration.fromMap({
        'wordMatchMode': -1,
        'sortBy': -1,
        'searchMode': -5,
        'proximityScope': 'זבל',
        'resultGrouping': -2,
      });
      expect(restored.wordMatchMode, WordMatchMode.all);
      expect(restored.sortBy, ResultsOrder.catalogue);
      expect(restored.searchMode, SearchMode.advanced);
      expect(restored.proximityScope, SearchScope.wordDistance);
      expect(restored.resultGrouping, ResultGroupingMode.none);
    });

    test('wordMatchCount שאינו int חיובי נופל לברירת המחדל', () {
      expect(
        SearchConfiguration.fromMap({'wordMatchCount': 'זבל'}).wordMatchCount,
        2,
      );
      expect(
        SearchConfiguration.fromMap({'wordMatchCount': 0}).wordMatchCount,
        2,
      );
      expect(
        SearchConfiguration.fromMap({'wordMatchCount': -3}).wordMatchCount,
        2,
      );
      expect(
        SearchConfiguration.fromMap({'wordMatchCount': 5}).wordMatchCount,
        5,
      );
    });

    test('SearchingTab toJson/fromJson משמרים מצב וספירה', () {
      final source = SearchingTab(
        'חיפוש',
        null,
        initialConfiguration: const SearchConfiguration(
          wordMatchMode: WordMatchMode.atLeast,
          wordMatchCount: 3,
        ),
      );
      addTearDown(source.searchBloc.close);

      final restored = SearchingTab.fromJson(source.toJson());
      addTearDown(restored.searchBloc.close);
      expect(
        restored.searchBloc.state.wordMatchMode,
        WordMatchMode.atLeast,
      );
      expect(restored.searchBloc.state.wordMatchCount, 3);

      // JSON ישן (בלי המפתחות) נופל לברירת המחדל בלי לזרוק.
      final json = source.toJson()
        ..remove('wordMatchMode')
        ..remove('wordMatchCount');
      final legacy = SearchingTab.fromJson(json);
      addTearDown(legacy.searchBloc.close);
      expect(legacy.searchBloc.state.wordMatchMode, WordMatchMode.all);
    });
  });
}
