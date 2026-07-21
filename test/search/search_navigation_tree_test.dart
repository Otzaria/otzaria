import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/search/view/search_navigation_tree.dart';

void main() {
  Category makeCategory(String title) => Category(
    title: title,
    description: '',
    shortDescription: '',
    order: 1,
    subCategories: const [],
    books: const [],
    parent: null,
  );

  Library makeLibrary() {
    final tanach = makeCategory('תנ"ך');
    final library = Library(categories: [tanach]);
    tanach.parent = library;
    return library;
  }

  Future<void> pumpTree(
    WidgetTester tester, {
    required Library library,
    Set<String> selectedFacets = const {},
    void Function(String facet)? onSetFacet,
    VoidCallback? onClearAll,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 600,
            child: SearchNavigationTree(
              library: library,
              facetCounts: const {'/': 3, '/תנ"ך': 3},
              selectedFacets: selectedFacets,
              expansion: const {},
              filterQuery: '',
              isLoading: false,
              hasResults: true,
              onSetFacet: onSetFacet ?? (_) {},
              onToggleFacet: (_) {},
              onToggleExpand: (_) {},
              isMultiSelectPressed: () => false,
              onClearAll: onClearAll ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('ללא סינון: כותרת השורש היא "ספריית אוצריא" והקטגוריה מוצגת', (
    tester,
  ) async {
    await pumpTree(tester, library: makeLibrary());

    expect(find.text('ספריית אוצריא'), findsOneWidget);
    expect(find.text('תנ"ך'), findsOneWidget);
    expect(find.text('נקה סינון'), findsNothing);
  });

  testWidgets('סינון ממד: כותרת השורש מציגה את שם הממד במקום "ספריית אוצריא"', (
    tester,
  ) async {
    await pumpTree(
      tester,
      library: makeLibrary(),
      selectedFacets: {'/era/ראשונים'},
    );

    expect(find.text('ראשונים'), findsOneWidget);
    expect(find.text('ספריית אוצריא'), findsNothing);
    expect(find.text('נקה סינון'), findsOneWidget);
  });

  testWidgets('לחיצה על "נקה סינון" בשורש מפעילה onClearAll', (tester) async {
    var cleared = false;
    await pumpTree(
      tester,
      library: makeLibrary(),
      selectedFacets: {'/era/ראשונים'},
      onClearAll: () => cleared = true,
    );

    await tester.tap(find.text('נקה סינון'));
    await tester.pump();
    expect(cleared, isTrue);
  });

  testWidgets('לחיצה על קטגוריה מפעילה onSetFacet עם הנתיב שלה', (
    tester,
  ) async {
    String? facet;
    await pumpTree(
      tester,
      library: makeLibrary(),
      onSetFacet: (f) => facet = f,
    );

    await tester.tap(find.text('תנ"ך'));
    await tester.pump();
    expect(facet, '/תנ"ך');
  });
}
