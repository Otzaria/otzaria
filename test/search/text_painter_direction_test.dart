import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/view/full_text_facet_filtering.dart';
import 'package:otzaria/search/view/full_text_settings_widgets.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';

import '../support/search_engine_test_init.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _StubSearchBloc extends SearchBloc {
  _StubSearchBloc(SearchState initialState) {
    emit(initialState);
  }

  void emitState(SearchState s) => emit(s);
}

Future<void> main() async {
  // הווידג'טים הנבדקים קוראים ל-sanitizeQuery/splitQueryWords שמאצילים למנוע
  // ה-Rust; הטסטים המסומנים מדולגים כשאין build נייטיבי זמין.
  final engineReady = await tryInitSearchEngine();

  TestWidgetsFlutterBinding.ensureInitialized();

  // עוזר לבניית Category בסיסית לטסטים
  Category makeCategory(String title, {List<Category> children = const []}) {
    final cat = Category(
      title: title,
      description: '',
      shortDescription: '',
      order: 10,
      subCategories: List<Category>.from(children),
      books: const [],
      parent: null,
    );
    for (final child in cat.subCategories) {
      child.parent = cat;
    }
    return cat;
  }

  group('TextPainter.textDirection - רגרסיה', () {
    // רגרסיה: TextPainter בלי textDirection זורק StateError בסביבת RTL
    // תוקן: הוספת textDirection: TextDirection.rtl לכל TextPainter שמשמש
    // למדידת רוחב/שורות בתוך full_text_settings_widgets.dart ו-full_text_facet_filtering.dart

    group('SearchTermsDisplay', () {
      late _StubSearchBloc searchBloc;
      late SearchingTab tab;

      setUp(() {
        tab = SearchingTab('חיפוש', null);
        searchBloc = _StubSearchBloc(
          const SearchState(searchQuery: 'מכשילן לעתיד'),
        );
      });

      tearDown(() async {
        tab.dispose();
        await searchBloc.close();
      });

      testWidgets('מרנדר ללא חריגה כשיש שאילתת חיפוש', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BlocProvider<SearchBloc>.value(
                value: searchBloc,
                child: SizedBox(
                  width: 400,
                  child: SearchTermsDisplay(tab: tab),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        expect(tester.takeException(), isNull);
      });

      testWidgets('מרנדר ללא חריגה עם טקסט ארוך שעולה על הרוחב',
          (tester) async {
        searchBloc.emitState(
          const SearchState(
              searchQuery: 'מכשילן לעתיד ומחייבן לדורות ומה שכתב'),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BlocProvider<SearchBloc>.value(
                value: searchBloc,
                child: SizedBox(
                  width: 200,
                  child: SearchTermsDisplay(tab: tab),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }, skip: engineReady ? false : searchEngineSkipReason);

    group('SearchFacetFiltering - category tile', () {
      late _StubSearchBloc searchBloc;
      late _MockLibraryBloc libraryBloc;
      late SearchingTab tab;

      setUp(() {
        tab = SearchingTab('חיפוש', null);

        final tanach = makeCategory('תנ"ך');
        final mishna = makeCategory('משנה');
        final library = Library(categories: [tanach, mishna]);
        for (final cat in library.subCategories) {
          cat.parent = library;
        }

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

        // count > 0 כדי שה-tile ייצור LayoutBuilder + TextPainter
        searchBloc = _StubSearchBloc(
          const SearchState(
            searchQuery: 'בדיקה',
            facetCounts: {'/': 10, '/תנ"ך': 5, '/משנה': 5},
          ),
        );
      });

      tearDown(() async {
        tab.dispose();
        await searchBloc.close();
        await libraryBloc.close();
      });

      testWidgets('tile של קטגוריה מרנדר ללא חריגת TextPainter',
          (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MultiBlocProvider(
                providers: [
                  BlocProvider<SearchBloc>.value(value: searchBloc),
                  BlocProvider<LibraryBloc>.value(value: libraryBloc),
                ],
                child: SizedBox(
                  height: 500,
                  child: SearchFacetFiltering(tab: tab),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    });

    group('SearchFacetFiltering - book tile', () {
      late _StubSearchBloc searchBloc;
      late _MockLibraryBloc libraryBloc;
      late SearchingTab tab;

      setUp(() {
        tab = SearchingTab('חיפוש', null);

        // ספר בדיקה עם id כדי שמפתח ה-facet יהיה פשוט ונקי
        final book = TextBook(id: 42, title: 'ספר הבדיקה');
        final tanach = Category(
          title: 'תנ"ך',
          description: '',
          shortDescription: '',
          order: 10,
          subCategories: const [],
          books: [book],
          parent: null,
        );

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

        // מפתח ה-facet לספר עם id: '/תנ"ך/id:42'
        searchBloc = _StubSearchBloc(
          const SearchState(
            searchQuery: 'בדיקה',
            facetCounts: {'/': 3, '/תנ"ך': 3, '/תנ"ך/id:42': 3},
          ),
        );
      });

      tearDown(() async {
        tab.dispose();
        await searchBloc.close();
        await libraryBloc.close();
      });

      testWidgets('tile של ספר מרנדר ללא חריגת TextPainter', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MultiBlocProvider(
                providers: [
                  BlocProvider<SearchBloc>.value(value: searchBloc),
                  BlocProvider<LibraryBloc>.value(value: libraryBloc),
                ],
                child: SizedBox(
                  height: 500,
                  child: SearchFacetFiltering(tab: tab),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    });
  });
}
