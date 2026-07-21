import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/view/full_text_facet_filtering.dart';
import 'package:otzaria/search/view/search_scope_menu.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

import '../support/search_engine_test_init.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _StubSearchBloc extends SearchBloc {
  _StubSearchBloc(SearchState initialState) {
    emit(initialState);
  }
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // בניית פאנל התפריט מאצילה ל-sanitizeQuery של מנוע ה-Rust; כשאין build
  // זמין הקבוצות מדולגות.
  final engineReady = await tryInitSearchEngine();

  Category makeCategory(String title) => Category(
    title: title,
    description: '',
    shortDescription: '',
    order: 10,
    subCategories: const [],
    books: const [],
    parent: null,
  );

  late _MockLibraryBloc libraryBloc;

  setUp(() {
    final tanach = makeCategory('תנ"ך');
    final library = Library(categories: [tanach]);
    tanach.parent = library;

    libraryBloc = _MockLibraryBloc();
    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: LibraryState(
        library: library,
        isLoading: false,
        currentCategory: library,
      ),
    );
  });

  tearDown(() async {
    await libraryBloc.close();
  });

  /// פותח את תפריט ההיקף (מתמקד בשדה) ומקליק על צ׳יפ/שורה לפי טקסט.
  /// pump מפורש (ולא pumpAndSettle) — טיימר ההבהוב המחזורי של השדה מונע
  /// התייצבות.
  Future<void> openMenuAndTap(WidgetTester tester, String label) async {
    final scopeField = find.descendant(
      of: find.byType(SearchScopeMenuButton),
      matching: find.byType(TextField),
    );
    await tester.tap(scopeField);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text(label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group(
    'SearchDimensionFilters - סרגל התוצאות',
    () {
      late _StubSearchBloc searchBloc;
      late SearchingTab tab;

      setUp(() {
        tab = SearchingTab('חיפוש', null);
        searchBloc = _StubSearchBloc(const SearchState());
      });

      tearDown(() async {
        tab.dispose();
        await searchBloc.close();
      });

      Future<void> pumpSidebar(WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MultiBlocProvider(
                providers: [
                  BlocProvider<SearchBloc>.value(value: searchBloc),
                  BlocProvider<LibraryBloc>.value(value: libraryBloc),
                ],
                child: SizedBox(
                  height: 700,
                  width: 350,
                  child: SearchFacetFiltering(tab: tab),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      testWidgets('בחירת תקופה מתפריט ההיקף מוסיפה /era ל-currentFacets', (
        tester,
      ) async {
        await pumpSidebar(tester);

        await openMenuAndTap(tester, 'ראשונים');

        expect(tester.takeException(), isNull);
        expect(
          searchBloc.state.currentFacets.contains('/era/ראשונים'),
          isTrue,
          reason: 'בחירת תקופה חייבת להוסיף את /era/ראשונים ל-currentFacets',
        );
      });
    },
    skip: engineReady ? false : searchEngineSkipReason,
  );

  group(
    'SearchScopeMenuButton - רכיב נשלט',
    () {
      testWidgets('בחירת תקופה מדווחת דרך onChanged', (tester) async {
        Set<String>? reported;
        var selected = <String>{};

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BlocProvider<LibraryBloc>.value(
                value: libraryBloc,
                child: StatefulBuilder(
                  builder: (context, setState) => SearchScopeMenuButton(
                    selected: selected,
                    onChanged: (next) {
                      reported = next;
                      setState(() => selected = next);
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        await openMenuAndTap(tester, 'אחרונים');

        expect(reported, contains('/era/אחרונים'));
        expect(tester.takeException(), isNull);
      });
    },
    skip: engineReady ? false : searchEngineSkipReason,
  );
}
