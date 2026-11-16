import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
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
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

class _MockSearchBloc extends MockBloc<SearchEvent, SearchState>
    implements SearchBloc {}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

/// חלונית סינון תוצאות החיפוש: שדה "איתור ספר" + עץ הניווט.
///
/// שני הבאגים שהטסטים כאן שומרים עליהם:
/// 1. רשימת הסינון השטוחה הציגה ספרים ללא תוצאות (רגרסיה מ-1c98decf).
/// 2. בחירת ספר נעלמה מהעץ אחרי ניקוי שדה האיתור, ולא הייתה דרך לבטלה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Category makeCategory(
    String title, {
    List<Category> subCategories = const [],
    List<Book> books = const [],
  }) => Category(
    title: title,
    description: '',
    shortDescription: '',
    order: 1,
    subCategories: subCategories,
    books: books,
    parent: null,
  );

  /// ספרייה: תנ"ך › כתובים › [תהילים(id:7), ויקרא(id:8)], ומשנה במקביל.
  Library makeLibrary() {
    final ketuvim = makeCategory(
      'כתובים',
      books: [
        TextBook(id: 7, title: 'תהילים', categoryPath: '/תנ"ך/כתובים'),
        TextBook(id: 8, title: 'ויקרא', categoryPath: '/תנ"ך/כתובים'),
      ],
    );
    final tanach = makeCategory('תנ"ך', subCategories: [ketuvim]);
    final mishna = makeCategory('משנה');
    final library = Library(categories: [tanach, mishna]);
    for (final cat in library.subCategories) {
      cat.parent = library;
    }
    ketuvim.parent = tanach;
    return library;
  }

  const counts = {
    '/': 9,
    '/תנ"ך': 5,
    '/תנ"ך/כתובים': 5,
    '/תנ"ך/כתובים/id:7': 5,
    '/משנה': 4,
  };

  late _MockSearchBloc searchBloc;
  late _MockLibraryBloc libraryBloc;
  late _MockSettingsBloc settingsBloc;
  late StreamController<SearchState> searchStates;
  late SearchingTab tab;

  SearchState stateWith({
    List<String> currentFacets = const ['/'],
    Map<String, int> facetCounts = counts,
  }) => SearchState(
    searchQuery: 'ניגונים',
    facetCounts: facetCounts,
    configuration: SearchConfiguration(currentFacets: currentFacets),
  );

  void setUpBlocs(SearchState initial) {
    searchStates = StreamController<SearchState>.broadcast();
    searchBloc = _MockSearchBloc();
    whenListen(searchBloc, searchStates.stream, initialState: initial);

    libraryBloc = _MockLibraryBloc();
    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: LibraryState(
        library: makeLibrary(),
        isLoading: false,
        currentCategory: null,
      ),
    );

    settingsBloc = _MockSettingsBloc();
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: SettingsState.initial(),
    );
  }

  setUp(() {
    tab = SearchingTab('חיפוש', null);
  });

  tearDown(() async {
    tab.dispose();
    await searchStates.close();
    await searchBloc.close();
    await libraryBloc.close();
    await settingsBloc.close();
  });

  Future<void> pumpPanel(WidgetTester tester) async {
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

  /// הקלדה בשדה "איתור ספר" הקבוע. העץ מתרענן דרך
  /// ה-BlocBuilder, לכן מדמים גם את ה-state שה-bloc פולט בתגובה ל-UpdateFilterQuery.
  Future<void> typeFilter(
    WidgetTester tester,
    String text,
    SearchState echo,
  ) async {
    await tester.enterText(find.byType(RtlTextField).first, text);
    searchStates.add(echo);
    await tester.pump();
  }

  /// שם ספר בתוך שורת העץ — ולא הטקסט שהוקלד בשדה האיתור עצמו.
  Finder tileText(String text) => find.descendant(
    of: find.byType(NavTreeTile),
    matching: find.text(text),
  );

  testWidgets('סינון "ויקרא": ספר ללא תוצאות אינו מוצג', (tester) async {
    setUpBlocs(stateWith());
    await pumpPanel(tester);

    await typeFilter(tester, 'ויקרא', stateWith());

    // לוויקרא (id:8) אין ספירה — הוא לא ניתן לבחירה.
    expect(tileText('ויקרא'), findsNothing);
    expect(find.text('לא נמצאו ספרים עם תוצאות'), findsOneWidget);
  });

  testWidgets('סינון "תהילים": ספר עם תוצאות מוצג ברשימה', (tester) async {
    setUpBlocs(stateWith());
    await pumpPanel(tester);

    await typeFilter(tester, 'תהילים', stateWith());

    expect(tileText('תהילים'), findsOneWidget);
    expect(find.text('לא נמצאו ספרים עם תוצאות'), findsNothing);
  });

  testWidgets('ניקוי שדה האיתור מחזיר את העץ עם הספר הנבחר גלוי בתוכו', (
    tester,
  ) async {
    final selected = stateWith(currentFacets: const ['/תנ"ך/כתובים/id:7']);
    setUpBlocs(selected);
    await pumpPanel(tester);

    await typeFilter(tester, 'תהילים', selected);
    expect(find.byType(NavTreeTile), findsOneWidget);

    await tester.tap(find.byIcon(FluentIcons.dismiss_24_regular));
    searchStates.add(selected);
    await tester.pump();

    // העץ חזר — והבחירה הפעילה נראית בו במקום להיעלם בענף מכווץ.
    expect(find.text('ספריית אוצריא'), findsOneWidget);
    expect(find.text('תנ"ך'), findsOneWidget);
    expect(find.text('כתובים'), findsOneWidget);
    expect(find.text('תהילים'), findsOneWidget);
    expect(find.text('נקה סינון'), findsOneWidget);
  });

  testWidgets('לחיצה על החץ מכווצת ענף שנפתח אוטומטית בגלל הבחירה', (
    tester,
  ) async {
    setUpBlocs(stateWith(currentFacets: const ['/תנ"ך/כתובים/id:7']));
    await pumpPanel(tester);

    expect(find.text('כתובים'), findsOneWidget);

    final chevron = find.descendant(
      of: find.ancestor(
        of: find.text('תנ"ך'),
        matching: find.byType(NavTreeTile),
      ),
      matching: find.byType(IconButton),
    );
    await tester.tap(chevron);
    await tester.pump();

    // רגרסיה: כשה-toggle התעלם מהפתיחה האוטומטית, הלחיצה הראשונה לא עשתה כלום.
    expect(find.text('כתובים'), findsNothing);
    expect(find.text('תהילים'), findsNothing);
  });

  testWidgets('ללא בחירה הענף נשאר מכווץ', (tester) async {
    setUpBlocs(stateWith());
    await pumpPanel(tester);

    expect(find.text('תנ"ך'), findsOneWidget);
    expect(find.text('כתובים'), findsNothing);
  });

  testWidgets('שדה "איתור ספר" מוצג תמיד, ו-X מנקה בלי להסתיר אותו', (
    tester,
  ) async {
    setUpBlocs(stateWith());
    await pumpPanel(tester);

    expect(find.byType(OtzariaSearchField), findsOneWidget);

    await typeFilter(tester, 'תהילים', stateWith());
    expect(find.byType(OtzariaSearchField), findsOneWidget);

    await tester.tap(find.byIcon(FluentIcons.dismiss_24_regular));
    searchStates.add(stateWith());
    await tester.pumpAndSettle();

    expect(find.byType(OtzariaSearchField), findsOneWidget);
    expect(find.text('ספריית אוצריא'), findsOneWidget);

    final field = tester.widget<RtlTextField>(find.byType(RtlTextField));
    expect(field.controller!.text, isEmpty, reason: 'X מנקה את הסינון');
  });
}
