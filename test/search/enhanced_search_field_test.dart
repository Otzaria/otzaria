import 'package:bloc_test/bloc_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/view/enhanced_search_field.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

class MockSearchBloc extends MockBloc<SearchEvent, SearchState>
    implements SearchBloc {}

class _FakeSearchEvent extends Fake implements SearchEvent {}

void main() {
  testWidgets('שדה החיפוש מקבל רקע מלא מתוך ה-theme', (
    WidgetTester tester,
  ) async {
    final tab = SearchingTab('חיפוש', 'בדיקה');
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFB85C38),
      ),
    );

    addTearDown(tab.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: BlocProvider.value(
          value: tab.searchBloc,
          child: Scaffold(
            body: EnhancedSearchField(
              tab: tab,
              onSubmit: () {},
              showInlineSearchButton: false,
            ),
          ),
        ),
      ),
    );

    final textField = tester.widget<TextField>(find.byType(TextField));

    expect(textField.decoration?.filled, isTrue);
    expect(
      textField.decoration?.fillColor,
      theme.colorScheme.surfaceContainerHigh,
    );
    expect(textField.decoration?.labelText, 'חיפוש');
    expect(
      textField.decoration?.hintText,
      'הקלד מילות חיפוש · לצמצום: מצה@רשי/פסחים',
    );
  });

  // q12 Q8: בטלפון הרמז המלא נחתך ל"הקלד מילות חיפוש · ל...".
  testWidgets('בשדה צר הרמז קצר, ודרך הצמצום בשורת העזר', (tester) async {
    final tab = SearchingTab('חיפוש', 'בדיקה');
    addTearDown(tab.dispose);
    Future<InputDecoration?> decorationAt(double width) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider.value(
            value: tab.searchBloc,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: EnhancedSearchField(tab: tab, onSubmit: () {}),
                ),
              ),
            ),
          ),
        ),
      );
      return tester.widget<TextField>(find.byType(TextField)).decoration;
    }

    final narrow = await decorationAt(330);
    expect(narrow?.hintText, 'הקלד מילות חיפוש');
    expect(narrow?.helperText, 'לצמצום: מצה@רשי/פסחים');
    expect(tester.takeException(), isNull);

    final wide = await decorationAt(700);
    expect(wide?.hintText, 'הקלד מילות חיפוש · לצמצום: מצה@רשי/פסחים');
    expect(wide?.helperText, isNull);
  });

  testWidgets('כפתור הניקוי בשדה הראשי תמיד מוצג ומאפס גם כשהשדה ריק', (
    tester,
  ) async {
    registerFallbackValue(_FakeSearchEvent());
    final tab = SearchingTab('חיפוש', null);
    addTearDown(tab.dispose);
    tab.globalSearchOptions['קידומות דקדוקיות'] = true;
    tab.searchOptions['x'] = {'a': true};
    final searchBloc = MockSearchBloc();
    whenListen(
      searchBloc,
      const Stream<SearchState>.empty(),
      initialState: tab.searchBloc.state,
    );
    addTearDown(searchBloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SearchBloc>.value(
          value: searchBloc,
          child: Scaffold(
            body: EnhancedSearchField(
              tab: tab,
              onSubmit: () {},
              showInlineSearchButton: false,
            ),
          ),
        ),
      ),
    );

    final clear = find.byIcon(FluentIcons.dismiss_24_regular);
    expect(tab.queryController.text, isEmpty);
    expect(clear, findsOneWidget);

    await tester.tap(clear);
    await tester.pump();

    expect(tab.globalSearchOptions, isEmpty);
    expect(tab.searchOptions, isEmpty);
    verify(() => searchBloc.add(any(that: isA<UpdateSearchQuery>()))).called(1);
    verify(() => searchBloc.add(any(that: isA<UpdateFacetCounts>()))).called(1);
  });
}
