import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:positioned_sliver_list/positioned_sliver_list.dart'
    show SuperListView;
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/utils/open_search_books.dart';
import 'package:otzaria/search/view/search_scope_menu.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';

import '../support/search_engine_test_init.dart';
import '../test_helpers/memory_cache_provider.dart';

class _MockLibraryBloc extends MockBloc<LibraryEvent, LibraryState>
    implements LibraryBloc {}

final _bereshit = TextBook(id: 1, title: 'בראשית', categoryPath: '/תורה');
final _shemot = TextBook(id: 2, title: 'שמות', categoryPath: '/תורה');
final _vayikra = TextBook(id: 3, title: 'ויקרא', categoryPath: '/תורה');
final _private = TextBook(
  id: 1,
  title: 'סיכום פרטי',
  categoryPath: '/תורה',
  source: BookSource.user,
);
final _pdf = PdfBook(id: 4, title: 'במדבר', path: 'bamidbar.pdf');

/// PDF מקומי ששואל את ה-id של ספר הטקסט המקביל (ראו BookIdentity), בתיקייה אחרת.
final _bereshitPdf = PdfBook(
  id: 1,
  title: 'בראשית',
  path: 'scans/bereshit.pdf',
  categoryPath: '/סרוקים',
);

Library _buildLibrary({List<Book> scans = const []}) {
  final torah = Category(
    title: 'תורה',
    description: '',
    shortDescription: '',
    order: 10,
    subCategories: [],
    books: [_bereshit, _shemot, _vayikra, _private, _pdf],
    parent: null,
  );
  final scanned = Category(
    title: 'סרוקים',
    description: '',
    shortDescription: '',
    order: 20,
    subCategories: [],
    books: scans,
    parent: null,
  );
  final library = Library(
    categories: [torah, if (scans.isNotEmpty) scanned],
  );
  torah.parent = library;
  scanned.parent = library;
  return library;
}

String _facetOf(Book book) =>
    FacetHelper.buildBookFacet(FacetHelper.resolveCategoryPath(book), book);

/// עותק של ספר כפי שהוא משוחזר בכרטיסייה: אותו id, בלי קטגוריה.
TextBook _restored(TextBook book) =>
    TextBook(id: book.id, title: book.title, source: book.source);

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Set<String> selection;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  List<OpenedTab> tabsOf(List<OpenedTab> tabs) {
    for (final tab in tabs) {
      addTearDown(tab.dispose);
    }
    return tabs;
  }

  Future<void> pumpMenu(
    WidgetTester tester, {
    required Set<String> selected,
    required List<Book> openBooks,
    bool excludeUserBooks = false,
    List<Book> scans = const [],
  }) async {
    final libraryBloc = _MockLibraryBloc();
    whenListen(
      libraryBloc,
      const Stream<LibraryState>.empty(),
      initialState: LibraryState(library: _buildLibrary(scans: scans)),
    );
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      await libraryBloc.close();
    });

    selection = selected;
    await tester.binding.setSurfaceSize(const Size(600, 900));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: BlocProvider<LibraryBloc>.value(
          value: libraryBloc,
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SearchScopeMenuButton(
                selected: selection,
                onChanged: (next) => setState(() => selection = next),
                openBooks: () => openBooks,
                excludeUserBooks: excludeUserBooks,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Finder rowOf(String label) => find
      .ancestor(
        of: find.descendant(
          of: find.byType(SuperListView),
          matching: find.text(label),
        ),
        matching: find.byType(InkWell),
      )
      .first;

  group('scope: open books (issue #2543)', () {
    test('כל החלוניות, כולל מפוצלות, בלי כפילויות', () {
      final tabs = tabsOf([
        TextBookTab(book: _restored(_bereshit), index: 0),
        TextBookTab(book: _restored(_shemot), index: 0),
        CombinedTab(
          rightTab: TextBookTab(book: _restored(_vayikra), index: 0),
          leftTab: TextBookTab(book: _restored(_bereshit), index: 0),
        ),
      ]);

      final books = openSearchableBooks(
        tabs,
        includePdfBooks: true,
        includeUserBooks: true,
      );

      expect([for (final b in books) b.title], ['בראשית', 'שמות', 'ויקרא']);
    });

    test('ספר אישי מוחרג כשספרים אישיים אינם באינדקס', () {
      final tabs = tabsOf([
        TextBookTab(book: _restored(_bereshit), index: 0),
        TextBookTab(book: _restored(_private), index: 0),
      ]);

      final books = openSearchableBooks(
        tabs,
        includePdfBooks: true,
        includeUserBooks: false,
      );

      expect([for (final b in books) b.title], ['בראשית']);
    });

    test('PDF מוחרג כשאינדוקס PDF כבוי', () {
      final tabs = tabsOf([
        TextBookTab(book: _restored(_bereshit), index: 0),
        PdfBookTab(book: _pdf, pageNumber: 1),
      ]);

      expect(
        [
          for (final b in openSearchableBooks(
            tabs,
            includePdfBooks: false,
            includeUserBooks: true,
          ))
            b.title,
        ],
        ['בראשית'],
      );
      expect(
        [
          for (final b in openSearchableBooks(
            tabs,
            includePdfBooks: true,
            includeUserBooks: true,
          ))
            b.title,
        ],
        ['בראשית', 'במדבר'],
      );
    });

    testWidgets('בחירת "ספרים פתוחים" בוחרת את שלושת הספרים ושומרת ממדים', (
      tester,
    ) async {
      final tabs = tabsOf([
        TextBookTab(book: _restored(_bereshit), index: 0),
        TextBookTab(book: _restored(_shemot), index: 0),
        CombinedTab(
          rightTab: TextBookTab(book: _restored(_vayikra), index: 0),
          leftTab: TextBookTab(book: _restored(_bereshit), index: 0),
        ),
      ]);
      await pumpMenu(
        tester,
        selected: {'/', '/era/ראשונים'},
        openBooks: openSearchableBooks(
          tabs,
          includePdfBooks: true,
          includeUserBooks: true,
        ),
      );

      await tester.tap(rowOf('ספרים פתוחים'));
      await tester.pumpAndSettle();

      expect(selection, {
        _facetOf(_bereshit),
        _facetOf(_shemot),
        _facetOf(_vayikra),
        '/era/ראשונים',
      });
    });

    testWidgets('בלי ספרים פתוחים — השורה מושבתת עם הסבר', (tester) async {
      await pumpMenu(tester, selected: {'/'}, openBooks: const []);

      expect(find.text('ספרים פתוחים'), findsOneWidget);
      expect(find.byTooltip('אין ספרים פתוחים'), findsOneWidget);

      await tester.tap(rowOf('ספרים פתוחים'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(selection, {'/'});
    });

    testWidgets('ספר פתוח שאינו בר חיפוש אינו הופך לחיפוש בכל הספרייה', (
      tester,
    ) async {
      await pumpMenu(
        tester,
        selected: {'/era/ראשונים'},
        openBooks: [_restored(_private)],
        excludeUserBooks: true,
      );

      await tester.tap(rowOf('ספרים פתוחים'));
      await tester.pumpAndSettle();

      expect(selection, {'/era/ראשונים'});
    });

    test('טקסט ו-PDF ששואל את ה-id שלו — שני מסמכי חיפוש, שניהם נשמרים', () {
      final tabs = tabsOf([
        TextBookTab(book: _restored(_bereshit), index: 0),
        PdfBookTab(book: _bereshitPdf, pageNumber: 1),
        TextBookTab(book: _restored(_bereshit), index: 0),
      ]);

      final books = openSearchableBooks(
        tabs,
        includePdfBooks: true,
        includeUserBooks: true,
      );

      expect(books, hasLength(2));
      expect(books.whereType<PdfBook>().single.path, 'scans/bereshit.pdf');
    });

    testWidgets('טקסט ו-PDF פתוחים עם אותו id — שני ה-facets בבחירה', (
      tester,
    ) async {
      final tabs = tabsOf([
        TextBookTab(book: _restored(_bereshit), index: 0),
        PdfBookTab(book: _bereshitPdf, pageNumber: 1),
      ]);
      await pumpMenu(
        tester,
        selected: {'/'},
        scans: [_bereshitPdf],
        openBooks: openSearchableBooks(
          tabs,
          includePdfBooks: true,
          includeUserBooks: true,
        ),
      );

      await tester.tap(rowOf('ספרים פתוחים'));
      await tester.pumpAndSettle();

      expect(selection, {_facetOf(_bereshit), _facetOf(_bereshitPdf)});
    });

    testWidgets('רק הטקסט פתוח — ה-PDF ששואל את ה-id שלו אינו נבחר', (
      tester,
    ) async {
      await pumpMenu(
        tester,
        selected: {'/'},
        scans: [_bereshitPdf],
        openBooks: [_restored(_bereshit)],
      );

      await tester.tap(rowOf('ספרים פתוחים'));
      await tester.pumpAndSettle();

      expect(selection, {_facetOf(_bereshit)});
    });

    testWidgets('השורה נראית כמו השורות שמעליה — בלי כותרת משנה', (
      tester,
    ) async {
      await pumpMenu(
        tester,
        selected: {'/'},
        openBooks: [_restored(_bereshit)],
      );

      final row = rowOf('ספרים פתוחים');
      final texts = find.descendant(of: row, matching: find.byType(Text));
      expect(texts, findsOneWidget);
      expect(
        tester.getSize(row).height,
        tester.getSize(rowOf('ספרי יסוד')).height,
      );
      Color? iconColor(Finder row) => tester
          .widget<Icon>(
            find.descendant(of: row, matching: find.byType(Icon)).first,
          )
          .color;
      expect(iconColor(row), iconColor(rowOf('כל הספרים')));
      expect(
        find.byTooltip('הבחירה נלקחת מהספרים הפתוחים ברגע הלחיצה'),
        findsOneWidget,
      );
    });
  }, skip: engineReady ? false : searchEngineSkipReason);
}
