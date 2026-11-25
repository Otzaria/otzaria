import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/navigation/view/tab_visuals.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/semantic_search/bloc/semantic_results_bloc.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/semantic_search_tab.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// SearchBloc שהטסט פולט לו state ישירות (emit מוגן).
class _ControlledSearchBloc extends SearchBloc {
  void emitState(SearchState state) => emit(state);
}

/// SemanticResultsBloc שהטסט פולט לו state ישירות.
class _ControlledResultsBloc extends SemanticResultsBloc {
  void emitState(SemanticResultsState state) => emit(state);
}

void main() {
  /// [buildTabTypeIcon] הוא האייקון של העמודה האנכית ושל חלונית חיפוש
  /// הכרטיסיות.
  Future<void> pumpIcon(WidgetTester tester, SearchingTab tab) =>
      tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) =>
                Center(child: buildTabTypeIcon(context, tab, size: 16)),
          ),
        ),
      );

  Finder spinner() => find.byType(LoadingIndicator);
  Finder searchIcon() => find.byIcon(OtzariaIcons.search_24_regular);

  group('כרטיסיית חיפוש מציגה שהחיפוש רץ (issue #5766)', () {
    testWidgets('בזמן חיפוש ספינר במקום האייקון, ובסופו האייקון חוזר', (
      tester,
    ) async {
      final bloc = _ControlledSearchBloc();
      final tab = SearchingTab('חיפוש: קקק', 'קקק', searchBloc: bloc);
      addTearDown(tab.dispose);
      await pumpIcon(tester, tab);
      expect(searchIcon(), findsOneWidget);
      expect(spinner(), findsNothing);

      bloc.emitState(bloc.state.copyWith(isLoading: true, isCounting: true));
      await tester.pump();
      expect(spinner(), findsOneWidget);
      expect(searchIcon(), findsNothing);
      expect(tester.getSize(spinner()), const Size(16, 16));
      expect(find.byTooltip('מחפש…'), findsOneWidget);

      // התוצאות הראשונות כבר הגיעו, אבל הספירה הכוללת עוד רצה.
      bloc.emitState(bloc.state.copyWith(isLoading: false));
      await tester.pump();
      expect(spinner(), findsOneWidget);

      bloc.emitState(bloc.state.copyWith(isCounting: false));
      await tester.pump();
      expect(spinner(), findsNothing);
      expect(searchIcon(), findsOneWidget);
    });

    testWidgets('כרטיסיית חיפוש חכם: ספינר כל עוד התוצאות נטענות', (
      tester,
    ) async {
      final bloc = _ControlledResultsBloc();
      final tab = SemanticSearchTab(
        options: const SemanticQueryOptions(query: 'צדקה'),
        createResultsBloc: (_) => bloc,
      );
      addTearDown(tab.dispose);
      // הכרטיסיה הוצגה ויצרה את ה-BLoC שלה.
      expect(tab.resultsBloc, same(bloc));
      await pumpIcon(tester, tab);
      expect(searchIcon(), findsOneWidget);

      bloc.emitState(
        bloc.state.copyWith(status: SemanticResultsStatus.loading),
      );
      await tester.pump();
      expect(spinner(), findsOneWidget);
      expect(searchIcon(), findsNothing);

      bloc.emitState(bloc.state.copyWith(status: SemanticResultsStatus.loaded));
      await tester.pump();
      expect(spinner(), findsNothing);
      expect(searchIcon(), findsOneWidget);
    });

    testWidgets('כרטיסיית חיפוש חכם שטרם הוצגה אינה יוצרת BLoC', (
      tester,
    ) async {
      final tab = SemanticSearchTab(
        options: const SemanticQueryOptions(query: 'צדקה'),
      );
      addTearDown(tab.dispose);
      await pumpIcon(tester, tab);
      expect(searchIcon(), findsOneWidget);
      expect(tab.createdResultsBloc, isNull);
    });

    testWidgets(
      'כרטיסיית חיפוש חכם: הספינר מופיע כשהמסך יוצר את ה-BLoC, בלי בנייה מחדש',
      (tester) async {
        final bloc = _ControlledResultsBloc();
        final tab = SemanticSearchTab(
          options: const SemanticQueryOptions(query: 'צדקה'),
          createResultsBloc: (_) => bloc,
        );
        addTearDown(tab.dispose);
        final showScreen = ValueNotifier(false);
        addTearDown(showScreen.dispose);
        // הרצועה נבנית לפני מסך התוצאות, והמסך יוצר את ה-BLoC בבנייה.
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Column(
                children: [
                  buildTabTypeIcon(context, tab, size: 16)!,
                  ValueListenableBuilder<bool>(
                    valueListenable: showScreen,
                    builder: (context, show, _) {
                      if (show) tab.resultsBloc;
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
        expect(tab.createdResultsBloc, isNull);

        showScreen.value = true;
        await tester.pump();
        expect(tab.createdResultsBloc, same(bloc));
        bloc.emitState(
          bloc.state.copyWith(status: SemanticResultsStatus.loading),
        );
        await tester.pump();
        expect(spinner(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
