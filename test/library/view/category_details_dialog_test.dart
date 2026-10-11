import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/category_details_dialog.dart';

void main() {
  group('category details descriptions (issue #2071)', () {
    Future<void> openDialog(WidgetTester tester, String short, String full) {
      final category = Category(
        title: 'קטגוריה',
        description: full,
        shortDescription: short,
        order: 0,
        subCategories: [],
        books: [],
        parent: null,
      );
      return tester
          .pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showCategoryDetailsDialog(context, category),
                  child: const Text('open'),
                ),
              ),
            ),
          )
          .then((_) => tester.tap(find.text('open')))
          .then((_) => tester.pumpAndSettle());
    }

    testWidgets('identical extended description is shown once', (
      tester,
    ) async {
      await openDialog(tester, 'תיאור זהה', ' תיאור זהה \n');
      expect(find.text('תיאור מורחב:'), findsNothing);
      expect(find.textContaining('תיאור זהה'), findsOneWidget);
    });

    testWidgets('different descriptions are both shown', (tester) async {
      await openDialog(tester, 'קצר', 'ארוך יותר');
      expect(find.text('תיאור קצר:'), findsOneWidget);
      expect(find.text('תיאור מורחב:'), findsOneWidget);
    });
  });
}
