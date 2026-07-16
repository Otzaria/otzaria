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
import 'package:otzaria/search/view/search_dimension_filters.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _StubSearchBloc extends SearchBloc {
  _StubSearchBloc(SearchState initialState) {
    emit(initialState);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Category makeCategory(String title) => Category(
        title: title,
        description: '',
        shortDescription: '',
        order: 10,
        subCategories: const [],
        books: const [],
        parent: null,
      );

  group('SearchDimensionFilters - רגרסיית תקיעה', () {
    late _StubSearchBloc searchBloc;
    late _MockLibraryBloc libraryBloc;
    late SearchingTab tab;

    setUp(() {
      tab = SearchingTab('חיפוש', null);

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

      searchBloc = _StubSearchBloc(const SearchState());
    });

    tearDown(() async {
      tab.dispose();
      await searchBloc.close();
      await libraryBloc.close();
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

    testWidgets('פתיחת הפאנל ולחיצה על מתג ספרי היסוד לא תוקעת ולא זורקת',
        (tester) async {
      await pumpSidebar(tester);

      // פתיחת הפאנל — כאן דווחה התקיעה בשטח.
      await tester.tap(find.text('תקופה, מחבר וספרי יסוד'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('חיפוש בספרי היסוד בלבד'), findsOneWidget);

      // הפעלת המתג (שאילתה ריקה — לא מגיע למנוע).
      await tester.tap(find.text('חיפוש בספרי היסוד בלבד'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(tester.takeException(), isNull);

      // המתג אמור להידלק דרך ה-state (facet /base נכנס ל-currentFacets).
      expect(
        searchBloc.state.currentFacets.contains('/base'),
        isTrue,
        reason: 'הקלקה על המתג חייבת להוסיף את /base ל-currentFacets',
      );

      // צ'יפ תקופה.
      await tester.tap(find.text('ראשונים'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(tester.takeException(), isNull);
      expect(
        searchBloc.state.currentFacets.contains('/era/ראשונים'),
        isTrue,
      );
    });
  });

  group('SearchDimensionControls - רכיב נשלט (הדיאלוג)', () {
    testWidgets('מתג וצ׳יפ מדווחים בחירה דרך onChanged בלי bloc',
        (tester) async {
      Set<String>? reported;
      var selected = <String>{};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: SearchDimensionControls(
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

      await tester.tap(find.text('חיפוש בספרי היסוד בלבד'));
      await tester.pump();
      expect(reported, contains('/base'));

      await tester.tap(find.text('אחרונים'));
      await tester.pump();
      expect(reported, containsAll(['/base', '/era/אחרונים']));

      // כיבוי המתג מסיר את /base ומשאיר את התקופה.
      await tester.tap(find.text('חיפוש בספרי היסוד בלבד'));
      await tester.pump();
      expect(reported, equals({'/era/אחרונים'}));
      expect(tester.takeException(), isNull);
    });
  });
}
