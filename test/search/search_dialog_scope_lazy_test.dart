import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/utils/scope_tree.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/search/view/search_scope_menu.dart';

import '../support/search_engine_test_init.dart';
import '../test_helpers/memory_cache_provider.dart';

class _MockHistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {}

class _MockIndexingBloc extends MockBloc<IndexingEvent, IndexingState>
    implements IndexingBloc {}

class _MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

Category _mkCat(
  String title, {
  List<Category> children = const [],
  List<Book> books = const [],
}) {
  final cat = Category(
    title: title,
    description: '',
    shortDescription: '',
    order: 10,
    subCategories: List<Category>.from(children),
    books: List<Book>.from(books),
    parent: null,
  );
  for (final child in cat.subCategories) {
    child.parent = cat;
  }
  return cat;
}

/// ספרייה בעומק 4 עם [total] ספרים, בסדר גודל של ספרייה אמיתית.
Library _buildLibrary(int total) {
  final topCats = <Category>[];
  var made = 0;
  var t = 0;
  while (made < total) {
    final level3 = <Category>[];
    for (var c = 0; c < 10 && made < total; c++) {
      final level4 = <Category>[];
      for (var d = 0; d < 10 && made < total; d++) {
        final books = <Book>[];
        for (var b = 0; b < 20 && made < total; b++) {
          books.add(
            TextBook(
              title: 'ספר $made',
              author: 'מחבר ${made % 300}',
              categoryPath: '/ראש $t/תת $t-$c/תת-תת $t-$c-$d',
            ),
          );
          made++;
        }
        level4.add(_mkCat('תת-תת $t-$c-$d', books: books));
      }
      level3.add(_mkCat('תת $t-$c', children: level4));
    }
    topCats.add(_mkCat('ראש $t', children: level3));
    t++;
  }
  final library = Library(categories: topCats);
  for (final cat in library.subCategories) {
    cat.parent = library;
  }
  return library;
}

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  void rustTest(String description, WidgetTesterCallback callback) {
    testWidgets(description, callback, skip: !engineReady);
  }

  /// מקים את דיאלוג החיפוש מעל ספרייה בגודל [bookCount] ומחזיר את משך
  /// הפריים הראשון — הזמן שהמשתמש ממתין עד שהפופאפ מוצג.
  ///
  /// [savedScope] מדמה היקף חיפוש שנשמר מהעדפות המשתמש; `null` = ברירת
  /// המחדל (כל הספרייה).
  Future<Duration> measureDialogOpen(
    WidgetTester tester,
    int bookCount, {
    Set<String>? savedScope,
  }) async {
    final historyBloc = _MockHistoryBloc();
    final indexingBloc = _MockIndexingBloc();
    final navigationBloc = _MockNavigationBloc();
    final libraryBloc = _MockLibraryBloc();

    whenListen(
      historyBloc,
      const Stream<HistoryState>.empty(),
      initialState: HistoryLoaded(const []),
    );
    whenListen(
      indexingBloc,
      const Stream<IndexingState>.empty(),
      initialState: IndexingInitial(),
    );
    whenListen(
      navigationBloc,
      const Stream<NavigationState>.empty(),
      initialState: const NavigationState(currentScreen: Screen.search),
    );
    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: LibraryState(library: _buildLibrary(bookCount)),
    );

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      await historyBloc.close();
      await indexingBloc.close();
      await navigationBloc.close();
      await libraryBloc.close();
    });

    await tester.binding.setSurfaceSize(const Size(1400, 900));

    Widget harness(Widget body) => MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<HistoryBloc>.value(value: historyBloc),
          BlocProvider<IndexingBloc>.value(value: indexingBloc),
          BlocProvider<NavigationBloc>.value(value: navigationBloc),
          BlocProvider<LibraryBloc>.value(value: libraryBloc),
        ],
        child: Scaffold(body: body),
      ),
    );

    // חימום: הבנייה הראשונה של עץ הווידג'טים משלמת עלויות חד-פעמיות
    // שאינן קשורות לגודל הספרייה, ומעוותת את ההשוואה.
    Widget dialog() => savedScope == null
        ? const SearchDialog(existingTab: null)
        : _ScopeOnlyHarness(selected: savedScope);

    await tester.pumpWidget(harness(dialog()));
    await tester.pumpWidget(harness(const SizedBox.shrink()));

    // מדידת המינימום מכמה מעברים: תזמון של מעבר בודד רועש מספיק כדי
    // להטביע רגרסיה אמיתית או להמציא אחת.
    var fastest = const Duration(days: 1);
    for (var i = 0; i < 3; i++) {
      final stopwatch = Stopwatch()..start();
      await tester.pumpWidget(harness(dialog()));
      stopwatch.stop();
      if (stopwatch.elapsed < fastest) fastest = stopwatch.elapsed;
      await tester.pumpWidget(harness(const SizedBox.shrink()));
    }

    await tester.pumpWidget(harness(dialog()));
    expect(find.byType(SearchScopeMenuButton), findsOneWidget);
    return fastest;
  }

  /// הרף: הפרש קבוע קטן מעל המקרה הזעיר, בתוספת מרווח יחסי שגדל יחד עם
  /// רעש התזמון של המכונה. הרגרסיה שנמדדה הייתה ‎+500ms ומעלה.
  void expectScanFree(Duration small, Duration large, String scenario) {
    final limit = (small.inMilliseconds * 1.6 + 150).round();
    expect(
      large.inMilliseconds,
      lessThan(limit),
      reason:
          '$scenario: פתיחה עם 20,000 ספרים (${large.inMilliseconds}ms) חייבת '
          'להישאר קרובה לפתיחה עם 200 ספרים (${small.inMilliseconds}ms, רף '
          '${limit}ms) — אחרת משהו בעץ הווידג\'טים חזר לסרוק את הספרייה '
          'בזמן build.',
    );
  }

  group('פתיחת דיאלוג החיפוש אינה סורקת את הספרייה', () {
    testWidgets('זמן הפתיחה אינו גדל עם מספר הספרים בספרייה', (tester) async {
      // רגרסיה: תפריט היקף החיפוש בנה את עץ הספרייה כולו ומיין את ספרי
      // היסוד בכל build, כך שפתיחת הפופאפ ארכה שניות בספרייה גדולה.
      final small = await measureDialogOpen(tester, 200);
      final large = await measureDialogOpen(tester, 20000);
      expectScanFree(small, large, 'ברירת מחדל');
    });

    testWidgets('גם בחירת היקף ספציפית שמורה אינה מאטה את הפתיחה', (
      tester,
    ) async {
      // רגרסיה: תווית הצ׳יפ ("כל הספרים"/"ספרי יסוד") נבנתה מסיווג כל ספרי
      // הספרייה, ולכן משתמש עם היקף חיפוש שמור שילם את מלוא הסריקה.
      const scope = {'/ראש 0'};
      final small = await measureDialogOpen(tester, 200, savedScope: scope);
      final large = await measureDialogOpen(tester, 20000, savedScope: scope);
      expectScanFree(small, large, 'היקף שמור');
    });

    testWidgets('תווית הצ׳יפ מדויקת גם בבחירה שמורה, בלי לחסום את הפתיחה', (
      tester,
    ) async {
      // התווית נגזרת מה-facet עצמו ואינה תלויה בבניית העץ.
      final library = _buildLibrary(200);
      final libraryBloc = _MockLibraryBloc();
      whenListen(
        libraryBloc,
        const Stream<LibraryState>.empty(),
        initialState: LibraryState(library: library),
      );
      addTearDown(libraryBloc.close);

      final bookFacet = ScopeTree.fromLibrary(
        library,
      ).allBookNodes().first.facet;

      await tester.binding.setSurfaceSize(const Size(600, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: BlocProvider<LibraryBloc>.value(
            value: libraryBloc,
            child: Scaffold(
              body: SearchScopeMenuButton(
                selected: {bookFacet},
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // ספר בודד שאינו ספר יסוד → "כל הספרים", ולא תווית ריקה או קריסה.
      await tester.pump();
      expect(find.text('כל הספרים'), findsOneWidget);
      expect(find.text('ספרי יסוד'), findsNothing);
    });

    testWidgets('התווית "ספרי יסוד" מגיעה מה-facet הממדי, בלי ספרייה טעונה', (
      tester,
    ) async {
      // הכוונה "ספרי יסוד" מיוצגת ב-/base, ולכן התיוג שלה אינו תלוי בעץ
      // ואינו ממתין לטעינת הספרייה. זה מה שמאפשר לוותר על סיווג כל הספרייה.
      final libraryBloc = _MockLibraryBloc();
      whenListen(
        libraryBloc,
        const Stream<LibraryState>.empty(),
        initialState: const LibraryState(), // ספרייה שעדיין נטענת
      );
      addTearDown(libraryBloc.close);

      await tester.binding.setSurfaceSize(const Size(600, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: BlocProvider<LibraryBloc>.value(
            value: libraryBloc,
            child: Scaffold(
              body: SearchScopeMenuButton(
                selected: {FacetHelper.baseDimensionFacet},
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('ספרי יסוד'), findsOneWidget);
      expect(find.text('כל הספרים'), findsNothing);
    });

    testWidgets('הפתיחה הראשונה בסשן זולה גם עם היקף שמור מצומצם', (
      tester,
    ) async {
      // מה שהמתחזק ביקש: מדידה שאינה מסתמכת על מטמון מחומם. כל קריאה מקבלת
      // אובייקט ספרייה חדש, ונמדדים גם פריים הפתיחה וגם הפריים שאחריו — שם
      // היה מתבצע ה-postFrameCallback שבנה את העץ המלא.
      Future<Duration> measureFirstOpen(int bookCount) async {
        final libraryBloc = _MockLibraryBloc();
        whenListen(
          libraryBloc,
          const Stream<LibraryState>.empty(),
          initialState: LibraryState(library: _buildLibrary(bookCount)),
        );
        addTearDown(libraryBloc.close);

        final stopwatch = Stopwatch()..start();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: BlocProvider<LibraryBloc>.value(
              value: libraryBloc,
              child: Scaffold(
                body: SearchScopeMenuButton(
                  selected: const {'/ראש 0'},
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pump(); // תגובתיות ה-UI מיד אחרי שהחלון נצבע
        stopwatch.stop();
        return stopwatch.elapsed;
      }

      await tester.binding.setSurfaceSize(const Size(600, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // חימום עץ הווידג'טים בספרייה זעירה, כדי לא לחמם את המטמון של הגדולה.
      await measureFirstOpen(50);
      await tester.pumpWidget(const SizedBox.shrink());

      final small = await measureFirstOpen(200);
      await tester.pumpWidget(const SizedBox.shrink());
      final large = await measureFirstOpen(20000);

      expectScanFree(small, large, 'פתיחה ראשונה, היקף שמור');
    });

    rustTest('פתיחת תפריט ההיקף אינה בונה או מסווגת את כל הספרייה', (
      tester,
    ) async {
      Future<Duration> measureMenuOpen(int bookCount) async {
        final libraryBloc = _MockLibraryBloc();
        whenListen(
          libraryBloc,
          const Stream<LibraryState>.empty(),
          initialState: LibraryState(library: _buildLibrary(bookCount)),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: BlocProvider<LibraryBloc>.value(
              value: libraryBloc,
              child: Scaffold(
                body: SearchScopeMenuButton(
                  selected: const {'/'},
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        );

        final stopwatch = Stopwatch()..start();
        await tester.tap(find.byType(TextField));
        await tester.pump();
        stopwatch.stop();

        expect(find.text('כל הספרים'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await libraryBloc.close();
        return stopwatch.elapsed;
      }

      await tester.binding.setSurfaceSize(const Size(600, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await measureMenuOpen(50);
      final small = await measureMenuOpen(200);
      final large = await measureMenuOpen(20000);
      expectScanFree(small, large, 'פתיחת תפריט ההיקף');
    });

    rustTest('התפריט והחיפוש בו עובדים על העץ שנבנה בעצלתיים', (
      tester,
    ) async {
      // העץ נבנה רק כשחיפוש או drill באמת דורשים אותו.
      await measureDialogOpen(tester, 200);
      final scopeField = find.descendant(
        of: find.byType(SearchScopeMenuButton),
        matching: find.byType(TextField),
      );

      await tester.tap(scopeField);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('כל הספרים'), findsOneWidget);

      // הקלדה מסננת דרך ScopeTree.search. ה-finder ממוקד לתפריט עצמו כדי
      // שלא ייתפס טקסט השדה שהוקלד.
      await tester.enterText(scopeField, 'ראש 0');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('ראש 0'),
        ),
        findsWidgets,
      );
    });

    rustTest('כניסה לספרי יסוד מסווגת בעצלתיים ומציגה את הספרים', (
      tester,
    ) async {
      final torah = _mkCat(
        'תורה',
        books: [
          TextBook(title: 'בראשית', categoryPath: '/תנ״ך/תורה'),
        ],
      );
      final tanach = _mkCat('תנ״ך', children: [torah]);
      final library = Library(categories: [tanach]);
      tanach.parent = library;

      final libraryBloc = _MockLibraryBloc();
      whenListen(
        libraryBloc,
        const Stream<LibraryState>.empty(),
        initialState: LibraryState(library: library),
      );
      addTearDown(libraryBloc.close);

      await tester.binding.setSurfaceSize(const Size(600, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: BlocProvider<LibraryBloc>.value(
            value: libraryBloc,
            child: Scaffold(
              body: SearchScopeMenuButton(
                selected: const {'/'},
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.tap(find.text('ספרי יסוד'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('בראשית'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rebuild עם ספרייה חדשה אינו בונה את העץ מחדש', (tester) async {
      // שני טסטי התזמון שלמעלה עובדים על אותו אובייקט ספרייה, ולכן מטמון
      // ScopeTree מגן עליהם גם אם הבנייה תחזור לתוך build. כאן כל rebuild
      // מקבל אובייקט ספרייה חדש — המטמון אינו רלוונטי, ובנייה בזמן build
      // תתבטא ישירות בזמן.
      Future<Duration> measure(int bookCount) async {
        final libraryBloc = _MockLibraryBloc();
        final controller = StreamController<LibraryState>.broadcast();
        addTearDown(controller.close);
        whenListen(
          libraryBloc,
          controller.stream,
          initialState: LibraryState(library: _buildLibrary(bookCount)),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: BlocProvider<LibraryBloc>.value(
              value: libraryBloc,
              child: Scaffold(
                body: SearchScopeMenuButton(
                  selected: const {'/'},
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        );

        var fastest = const Duration(days: 1);
        for (var i = 0; i < 3; i++) {
          controller.add(LibraryState(library: _buildLibrary(bookCount)));
          // idle מוסר את ה-state ל-BlocBuilder ומסמן אותו dirty; רק ה-pump
          // שאחריו הוא הפריים שבונה, וזה מה שנמדד.
          await tester.idle();
          final stopwatch = Stopwatch()..start();
          await tester.pump();
          stopwatch.stop();
          if (stopwatch.elapsed < fastest) fastest = stopwatch.elapsed;
        }
        return fastest;
      }

      await measure(200); // חימום
      final small = await measure(200);
      final large = await measure(20000);
      expectScanFree(small, large, 'ספרייה חדשה בכל rebuild');
    });

    rustTest('החלפת ספרייה מרעננת את העץ בתפריט הפתוח', (tester) async {
      // המטמון של ScopeTree ממופתח בזהות אובייקט הספרייה; החלפה חייבת
      // להחליף גם את מה שהתפריט מציג.
      final libraryBloc = _MockLibraryBloc();
      final libraryA = _buildLibrary(200);
      final libraryB = Library(
        categories: [
          _mkCat('ספרייה חדשה', books: [TextBook(title: 'ספר ב')]),
        ],
      );
      for (final cat in libraryB.subCategories) {
        cat.parent = libraryB;
      }

      final controller = StreamController<LibraryState>.broadcast();
      addTearDown(controller.close);
      whenListen(
        libraryBloc,
        controller.stream,
        initialState: LibraryState(library: libraryA),
      );

      await tester.binding.setSurfaceSize(const Size(600, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: BlocProvider<LibraryBloc>.value(
            value: libraryBloc,
            child: Scaffold(
              body: SearchScopeMenuButton(
                selected: const {'/'},
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      // כל ה-finders מוגבלים לרשימת התפריט: הטקסט שהוקלד יושב גם ב-TextField,
      // ובלי ההגבלה כל ההשוואות כאן היו מתקיימות גם כשהתפריט ריק.
      Finder inMenu(String text) => find.descendant(
        of: find.byType(ListView),
        matching: find.text(text),
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(find.byType(TextField), 'ראש 0');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(inMenu('ראש 0'), findsWidgets);

      controller.add(LibraryState(library: libraryB));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // הקטגוריה של הספרייה הישנה נעלמת, ושל החדשה מופיעה — כך שהטסט
      // מבחין בין "העץ התרענן" לבין "העץ נעלם".
      expect(inMenu('ראש 0'), findsNothing);

      await tester.enterText(find.byType(TextField), 'ספרייה חדשה');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(inMenu('ספרייה חדשה'), findsWidgets);
    });
  });
}

/// עוטף את בורר ההיקף בלבד עם בחירה נתונה — מדמה היקף חיפוש שנשמר
/// מהעדפות המשתמש, בלי לעבור דרך אתחול ההעדפות של הדיאלוג.
class _ScopeOnlyHarness extends StatelessWidget {
  const _ScopeOnlyHarness({required this.selected});

  final Set<String> selected;

  @override
  Widget build(BuildContext context) => SearchScopeMenuButton(
    selected: selected,
    onChanged: (_) {},
  );
}
