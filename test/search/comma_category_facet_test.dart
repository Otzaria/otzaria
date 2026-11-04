import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/book_facet.dart';
import 'package:otzaria/search/search_engine_gateway.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/utils/category_query_parser.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/utils/scope_tree.dart';
import 'package:otzaria/search/view/search_navigation_tree.dart';
import 'package:otzaria/semantic_search/models/semantic_mode_gate.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../support/search_engine_test_init.dart';

/// תיקייה שבשמה פסיק, כמו "נתיבות המשפט, ביאורים" בקטלוג: האינדקס והספירות
/// מנרמלים את הפסיק למפריד, ולכן גם העץ, תחום החיפוש ו-@ חייבים לעשות כך.
Future<void> main() async {
  final ready = await tryInitSearchEngine();

  Category category(String title, {List<Category> sub = const []}) {
    final created = Category(
      title: title,
      description: '',
      shortDescription: '',
      order: 1,
      subCategories: sub,
      books: [],
      parent: null,
    );
    for (final child in sub) {
      child.parent = created;
    }
    return created;
  }

  TextBook bookIn(Category parent, int id, String title) {
    final book = TextBook(id: id, title: title, category: parent);
    parent.books.add(book);
    return book;
  }

  // המבנה מהקטלוג: הלכה > שולחן ערוך > מפרשים > שתי תיקיות עם פסיק.
  final simanim = category('סימנים');
  final biurimCategory = category('נתיבות המשפט, ביאורים', sub: [simanim]);
  final chidushimCategory = category('נתיבות המשפט, חידושים');
  final ketzotCategory = category('קצות החושן');
  final library = Library(
    categories: [
      category(
        'הלכה',
        sub: [
          category(
            'שולחן ערוך',
            sub: [
              category(
                'מפרשים',
                sub: [biurimCategory, chidushimCategory, ketzotCategory],
              ),
            ],
          ),
        ],
      ),
    ],
  );
  for (final top in library.subCategories) {
    top.parent = library;
  }
  final biurim = bookIn(
    biurimCategory,
    3831,
    'נתיבות המשפט, ביאורים על שולחן ערוך חושן משפט',
  );
  final chidushim = bookIn(
    chidushimCategory,
    3833,
    'נתיבות המשפט, חידושים על שולחן ערוך חושן משפט',
  );
  final ketzot = bookIn(ketzotCategory, 50, 'קצות החושן');
  final simanBook = bookIn(simanim, 60, 'ביאור');
  final books = [biurim, chidushim, ketzot, simanBook];
  String filePathOf(Book book) => 'id:${book.id}';

  /// ה-facet שהאינדוקס כותב לספר (IndexingRepository._bookTopics).
  String indexedFacetOf(Book book) => BookFacet.buildFacetPath(
    title: book.title,
    topics: book.topics,
    externalLibraryId: book.externalLibraryId,
    bookId: book.id,
    source: book.source,
    categoryPath: book.category?.path ?? book.categoryPath,
    fileType: book.fileType,
    filePath: book.filePath,
  );

  /// צומת התיקייה [title] בעץ תחום החיפוש.
  ScopeNode scopeNode(String title) {
    ScopeNode? find(Iterable<ScopeNode> nodes) {
      for (final node in nodes) {
        if (!node.isBook && node.title == title) return node;
        final found = find(node.children);
        if (found != null) return found;
      }
      return null;
    }

    return find(ScopeTree.fromLibrary(library).rootNodes)!;
  }

  group('מול המנוע', () {
    late Directory temporary;
    late SearchEngine engine;
    late SearchRepository repository;

    setUpAll(() async {
      if (!ready) return;
      temporary = await Directory.systemTemp.createTemp('comma-category-');
      engine = await SearchEngine.newInstance(path: temporary.path);
      for (var i = 0; i < books.length; i++) {
        await engine.addDocument(
          ordinal: i,
          title: books[i].title,
          reference: books[i].title,
          topics: indexedFacetOf(books[i]),
          text: 'המוחזק בקרקע',
          segment: BigInt.zero,
          isPdf: false,
          filePath: filePathOf(books[i]),
        );
      }
      await engine.commit();
      repository = SearchRepository(
        engineProvider: () async => RustSearchEngineOperations(engine),
      );
    });

    tearDownAll(() async {
      if (!ready) return;
      engine.dispose();
      if (Platform.isWindows) return;
      try {
        await temporary.delete(recursive: true);
      } on FileSystemException {
        // ignore
      }
    });

    Future<List<String>> filePathsIn(List<String> facets) async {
      final results = await repository.searchTexts(
        SearchEngineRequest(query: 'המוחזק', facets: facets, limit: 10),
      );
      return results.map((result) => result.filePath).toList()..sort();
    }

    test('תיקייה עם פסיק כתחום חיפוש מוצאת את ספריה', () async {
      if (!ready) {
        markTestSkipped(searchEngineSkipReason);
        return;
      }
      final scope = scopeNode('נתיבות המשפט, ביאורים');

      expect(
        await filePathsIn([scope.facet]),
        [
          filePathOf(simanBook),
          filePathOf(biurim),
        ]..sort(),
      );
      final sibling = scopeNode('נתיבות המשפט, חידושים');
      expect(await filePathsIn([sibling.facet]), [filePathOf(chidushim)]);
    });

    test('@ לתת-תיקייה של תיקייה עם פסיק מוצא את ספריה', () async {
      if (!ready) {
        markTestSkipped(searchEngineSkipReason);
        return;
      }
      final parsed = parseCategoryQuery(
        'המוחזק@נתיבות המשפט/סימנים',
        library,
      );

      expect(parsed.categoryFound, isTrue);
      expect(await filePathsIn(parsed.facets!), [filePathOf(simanBook)]);
    });
  });

  Map<String, int> countsFor(Map<Book, int> bookCounts) =>
      FacetHelper.buildFacetCountsFromBookCounts(
        {
          for (final MapEntry(key: book, value: count) in bookCounts.entries)
            filePathOf(book): count,
        },
        {for (final book in books) filePathOf(book): book},
      );

  Future<void> pumpTree(
    WidgetTester tester, {
    required Map<String, int> counts,
    Set<String> selectedFacets = const {},
    Map<String, bool> expansion = const {},
    void Function(String facet)? onSetFacet,
    void Function(String path, bool isExpanded)? onToggleExpand,
  }) => tester.pumpWidget(
    MaterialApp(
      builder: (_, child) =>
          SettingsTextScope(language: SettingsLanguage.hebrew, child: child!),
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 600,
          child: SearchNavigationTree(
            library: library,
            facetCounts: counts,
            selectedFacets: selectedFacets,
            expansion: expansion,
            filterQuery: '',
            isLoading: false,
            hasResults: true,
            onSetFacet: onSetFacet ?? (_) {},
            onToggleFacet: (_) {},
            onToggleExpand: onToggleExpand ?? (_, _) {},
            onClearAll: () {},
          ),
        ),
      ),
    ),
  );

  testWidgets('עץ סינון התוצאות מציג תיקייה עם פסיק ובוחר את ספריה', (
    tester,
  ) async {
    final counts = countsFor({biurim: 2, ketzot: 1});
    String? picked;
    await pumpTree(
      tester,
      counts: counts,
      expansion: const {
        '/הלכה': true,
        '/הלכה/שולחן ערוך': true,
        '/הלכה/שולחן ערוך/מפרשים': true,
      },
      onSetFacet: (facet) => picked = facet,
    );

    expect(find.text('קצות החושן'), findsOneWidget);
    expect(find.text('נתיבות המשפט, ביאורים'), findsOneWidget);
    expect(find.text('נתיבות המשפט, חידושים'), findsNothing);

    await tester.tap(find.text('נתיבות המשפט, ביאורים'));
    await tester.pump();

    final bookFacet = FacetHelper.buildBookFacet(
      FacetHelper.resolveCategoryPath(biurim),
      biurim,
    );
    expect(picked, isNotNull);
    expect(SearchBloc.facetContains(picked!, bookFacet), isTrue);
    expect(counts[picked], 2);
  });

  testWidgets('"כווץ הכל" סוגר תיקייה עם פסיק שנפתחה אל הבחירה', (
    tester,
  ) async {
    final toggles = <(String, bool)>{};
    await pumpTree(
      tester,
      counts: countsFor({simanBook: 1}),
      selectedFacets: {
        FacetHelper.buildBookFacet(
          FacetHelper.resolveCategoryPath(simanBook),
          simanBook,
        ),
      },
      onToggleExpand: (path, isExpanded) => toggles.add((path, isExpanded)),
    );
    expect(find.text('סימנים'), findsOneWidget);

    await tester.tap(find.byTooltip('כווץ הכל'));
    await tester.pump();

    // אותם מפתחות שהעץ קורא בהם את מצב הפתיחה, אחרת התיקייה נפתחת שוב.
    expect(toggles, {
      ('/הלכה', true),
      ('/הלכה/שולחן ערוך', true),
      ('/הלכה/שולחן ערוך/מפרשים', true),
      ('/הלכה/שולחן ערוך/מפרשים/נתיבות המשפט/ביאורים', true),
      ('/הלכה/שולחן ערוך/מפרשים/נתיבות המשפט/ביאורים/סימנים', true),
    });
  });

  test('חיפוש חכם משאיר בהיקף תיקייה עם פסיק מתחום החיפוש ומ-@', () {
    final parsed = parseCategoryQuery('המוחזק@נתיבות המשפט/סימנים', library);
    final selection = [
      scopeNode('נתיבות המשפט, ביאורים').facet,
      scopeNode('נתיבות המשפט, חידושים').facet,
      ...parsed.facets!,
    ];

    expect(
      semanticScopeFacets(
        selection,
        isOfficialCategory: officialCategoryFilter(library),
      ),
      selection..sort(),
    );
  });
}
