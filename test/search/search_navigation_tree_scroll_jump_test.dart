import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/view/search_navigation_tree.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';

/// קפיצה בפס הגלילה לסוף רשימה ארוכה בעץ הניווט של החיפוש (issue #4766):
/// ListView בונה בקפיצה כל שורה שבדרך.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bookCount = 3000;

  late Category folder;
  late Library library;
  late Map<String, int> facetCounts;

  setUp(() {
    folder = Category(
      title: 'תיקייה',
      description: '',
      shortDescription: '',
      order: 1,
      subCategories: const [],
      books: [
        for (var i = 0; i < bookCount; i++)
          TextBook(id: i + 1, title: 'ספר $i', order: i),
      ],
      parent: null,
    );
    library = Library(categories: [folder]);
    folder.parent = library;
    final folderFacet = FacetHelper.categoryFacet(folder);
    facetCounts = {
      library.path: bookCount,
      folderFacet: bookCount,
      for (final book in folder.books)
        FacetHelper.buildBookFacet(folderFacet, book): 1,
      // רשימת הסינון השטוחה מחשבת את ה-facet מנתיב הקטגוריה של הספר.
      for (final book in folder.books)
        FacetHelper.buildBookFacet(FacetHelper.resolveCategoryPath(book), book):
            1,
    };
  });

  Future<int> jumpToEndAndCountRows(
    WidgetTester tester, {
    required String filterQuery,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: SearchNavigationTree(
              library: library,
              facetCounts: facetCounts,
              selectedFacets: const [],
              expansion: {folder.path: true},
              filterQuery: filterQuery,
              isLoading: false,
              hasResults: true,
              onSetFacet: (_) {},
              onToggleFacet: (_) {},
              onToggleExpand: (_, _) {},
              onClearAll: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var rowBuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is NavTreeTile) rowBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    return rowBuilds;
  }

  testWidgets('קפיצה לסוף רשימת הסינון השטוחה בונה רק את שורות היעד '
      '(issue #4766)', (tester) async {
    final rowBuilds = await jumpToEndAndCountRows(tester, filterQuery: 'ספר');

    expect(rowBuilds, lessThan(200));
  });

  testWidgets('קפיצה לסוף העץ המורחב בונה רק את שורות היעד '
      '(issue #4766)', (tester) async {
    final rowBuilds = await jumpToEndAndCountRows(tester, filterQuery: '');

    expect(rowBuilds, lessThan(200));
  });
}
