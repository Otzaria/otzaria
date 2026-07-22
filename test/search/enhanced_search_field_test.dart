import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/view/enhanced_search_field.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

class MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class MockHistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {}

class MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class MockSearchBloc extends MockBloc<SearchEvent, SearchState>
    implements SearchBloc {}

class _TestSearchDialogWrapper {
  final SearchingTab tab;

  _TestSearchDialogWrapper(this.tab);
}

void main() {
  testWidgets('שדה החיפוש מקבל רקע מלא מתוך ה-theme', (
    WidgetTester tester,
  ) async {
    final tab = SearchingTab('חיפוש', 'בדיקה');
    final navigationBloc = MockNavigationBloc();
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFB85C38),
      ),
    );

    whenListen(
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );

    addTearDown(() async {
      await navigationBloc.close();
      tab.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: MultiBlocProvider(
          providers: [
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            BlocProvider.value(value: tab.searchBloc),
          ],
          child: Scaffold(
            body: EnhancedSearchField(
              widget: _TestSearchDialogWrapper(tab),
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
    expect(textField.decoration?.hintText, 'הקלד מילות חיפוש');
  });

  testWidgets('שליחת חיפוש מעדכנת את כותרת הטאב', (tester) async {
    final tab = SearchingTab('חיפוש', null);
    final navigationBloc = MockNavigationBloc();
    final historyBloc = MockHistoryBloc();
    final libraryBloc = MockLibraryBloc();
    final searchBloc = MockSearchBloc();

    whenListen(
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );
    whenListen(
      historyBloc,
      const Stream<HistoryState>.empty(),
      initialState: HistoryInitial(),
    );
    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: const LibraryState(),
    );
    whenListen(
      searchBloc,
      const Stream<SearchState>.empty(),
      initialState: tab.searchBloc.state,
    );

    addTearDown(() async {
      await navigationBloc.close();
      await historyBloc.close();
      await libraryBloc.close();
      await searchBloc.close();
      tab.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<NavigationBloc>.value(value: navigationBloc),
            BlocProvider<HistoryBloc>.value(value: historyBloc),
            BlocProvider<LibraryBloc>.value(value: libraryBloc),
            BlocProvider<SearchBloc>.value(value: searchBloc),
          ],
          child: Scaffold(
            body: EnhancedSearchField(
              widget: _TestSearchDialogWrapper(tab),
              showInlineSearchButton: false,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'צדיק גאולה');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(tab.title, 'חיפוש: צדיק גאולה');
    expect(tab.titleNotifier.value, 'חיפוש: צדיק גאולה');
  });
}
