import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/full_text_facet_filtering.dart';
import 'package:otzaria/search/view/search_navigation_tree.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _MockSearchBloc extends MockBloc<SearchEvent, SearchState>
    implements SearchBloc {}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

/// עץ הסינון נבנה מחדש רק כשמשתנה שדה שהוא מציג; פעימות חיפוש שאינן
/// נוגעות בו (chunk נוסף, ספירה כוללת, טעינת עוד) לא בונות אותו שוב.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Category makeCategory(String title, {List<Book> books = const []}) =>
      Category(
        title: title,
        description: '',
        shortDescription: '',
        order: 1,
        subCategories: const [],
        books: books,
        parent: null,
      );

  Library makeLibrary() {
    final tanach = makeCategory(
      'תנ"ך',
      books: [TextBook(id: 7, title: 'תהילים', categoryPath: '/תנ"ך')],
    );
    final library = Library(categories: [tanach, makeCategory('משנה')]);
    for (final cat in library.subCategories) {
      cat.parent = library;
    }
    return library;
  }

  SearchResult result(int id) => SearchResult(
    id: BigInt.from(id),
    title: 'תהילים',
    reference: 'תהילים א',
    text: 'טקסט',
    segment: BigInt.zero,
    isPdf: false,
    filePath: 'book.txt',
    mergedCount: 1,
    merged: const [],
    textStatus: TextStatus.ok,
    continuesToNextLine: false,
  );

  late _MockSearchBloc searchBloc;
  late StreamController<SearchState> searchStates;
  late SearchingTab tab;
  late List<Object> disposables;

  setUp(() {
    tab = SearchingTab('חיפוש', null);
    searchStates = StreamController<SearchState>.broadcast();
  });

  tearDown(() async {
    tab.dispose();
    await searchStates.close();
    for (final bloc in disposables) {
      await (bloc as BlocBase).close();
    }
  });

  Future<void> pumpPanel(WidgetTester tester, SearchState initial) async {
    searchBloc = _MockSearchBloc();
    whenListen(searchBloc, searchStates.stream, initialState: initial);
    final libraryBloc = _MockLibraryBloc();
    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: LibraryState(
        library: makeLibrary(),
        isLoading: false,
        currentCategory: null,
      ),
    );
    final settingsBloc = _MockSettingsBloc();
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial(),
    );
    disposables = [searchBloc, libraryBloc, settingsBloc];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<SearchBloc>.value(value: searchBloc),
              BlocProvider<LibraryBloc>.value(value: libraryBloc),
              BlocProvider<SettingsBloc>.value(value: settingsBloc),
            ],
            child: SizedBox(
              width: 320,
              height: 600,
              child: SearchFacetFiltering(tab: tab),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> emit(WidgetTester tester, SearchState state) async {
    searchStates.add(state);
    // whenListen מעביר את ה-state דרך stream נוסף — שתי פעימות עד ה-builder.
    await tester.pump();
    await tester.pump();
  }

  SearchNavigationTree tree(WidgetTester tester) =>
      tester.widget<SearchNavigationTree>(find.byType(SearchNavigationTree));

  const counts = {'/': 5, '/תנ"ך': 5, '/תנ"ך/id:7': 5};

  testWidgets('פעימות שאינן נוגעות בעץ אינן בונות אותו מחדש', (tester) async {
    final base = SearchState(
      searchQuery: 'ניגונים',
      facetCounts: counts,
      results: [result(1)],
      configuration: SearchConfiguration(currentFacets: const ['/']),
    );
    await pumpPanel(tester, base);
    final built = tree(tester);

    // chunk נוסף, ספירה כוללת, טעינת עוד (isLoading כשיש תוצאות), מיון.
    var state = base.copyWith(results: [result(1), result(2)]);
    await emit(tester, state);
    state = state.copyWith(totalResults: 900);
    await emit(tester, state);
    state = state.copyWith(isLoading: true);
    await emit(tester, state);
    state = state.copyWith(isLoading: false, results: [result(3)]);
    await emit(tester, state);
    state = state.copyWith(
      configuration: state.configuration.copyWith(numResults: 200),
    );
    await emit(tester, state);

    expect(identical(tree(tester), built), isTrue);
  });

  testWidgets('שינוי ספירות או בחירה עדיין מרענן את העץ', (tester) async {
    final base = SearchState(
      searchQuery: 'ניגונים',
      facetCounts: counts,
      configuration: SearchConfiguration(currentFacets: const ['/']),
    );
    await pumpPanel(tester, base);

    final recounted = base.copyWith(facetCounts: const {'/': 2, '/משנה': 2});
    await emit(tester, recounted);
    expect(tree(tester).facetCounts, recounted.facetCounts);

    final selected = recounted.copyWith(
      configuration: recounted.configuration.copyWith(
        currentFacets: const ['/משנה'],
      ),
    );
    await emit(tester, selected);
    expect(tree(tester).selectedFacets, const ['/משנה']);
  });

  testWidgets('טעינה בלי תוצאות מציגה ספינר ברשימה המסוננת', (tester) async {
    final base = SearchState(
      searchQuery: 'ניגונים',
      facetCounts: counts,
      results: [result(1)],
      configuration: SearchConfiguration(currentFacets: const ['/']),
    );
    await pumpPanel(tester, base);
    await tester.tap(find.byType(NavPanelSearchToggle));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(RtlTextField).first, 'תהילים');
    await emit(tester, base.copyWith(filterQuery: 'תהילים'));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await emit(tester, base.copyWith(isLoading: true, results: const []));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('ניקוי האיתור אחרי פעימה שאיפסה את filterQuery מחזיר את העץ', (
    tester,
  ) async {
    final base = SearchState(
      searchQuery: 'ניגונים',
      facetCounts: counts,
      configuration: SearchConfiguration(currentFacets: const ['/']),
    );
    await pumpPanel(tester, base);
    await tester.tap(find.byType(NavPanelSearchToggle));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(RtlTextField).first, 'תהילים');
    await emit(tester, base.copyWith(filterQuery: 'תהילים'));
    expect(tree(tester).filterQuery, 'תהילים');

    // copyWith מאפס את filterQuery; ClearFilter פולט אז null שוב.
    await emit(tester, base.copyWith(totalResults: 3));
    await tester.tap(find.byIcon(FluentIcons.dismiss_24_regular));
    await emit(tester, base.copyWith(totalResults: 3));
    await tester.pumpAndSettle();

    expect(tree(tester).filterQuery, isEmpty);
    expect(find.text('ספריית אוצריא'), findsOneWidget);
  });
}
