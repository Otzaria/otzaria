import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/category_details_dialog.dart';

Category _category(String shortDescription, String description) => Category(
  title: 'הלכה',
  description: description,
  shortDescription: shortDescription,
  order: 1,
  subCategories: [],
  books: [],
  parent: null,
);

Future<void> _open(WidgetTester tester, Category category) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showCategoryDetailsDialog(context, category),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('תיאור קצר ותיאור מורחב שונים מוצגים פעם אחת כל אחד', (
    tester,
  ) async {
    await _open(tester, _category('תיאור קצר', 'תיאור מורחב אחר לגמרי'));

    expect(find.text('תיאור קצר'), findsOneWidget);
    expect(find.text('תיאור מורחב אחר לגמרי'), findsOneWidget);
  });

  testWidgets('תיאור מורחב זהה לקצר אינו חוזר פעמיים', (tester) async {
    await _open(
      tester,
      _category('הספרים המורים את ההלכה', 'הספרים המורים את ההלכה'),
    );

    expect(find.text('הספרים המורים את ההלכה'), findsOneWidget);
  });

  testWidgets('הבדל ברווח קשיח, גרשיים ופיסוק אינו מכפיל את התיאור', (
    tester,
  ) async {
    await _open(
      tester,
      _category(
        'חיבורו של החיד"א - עבודת הקודש',
        'חיבורו\u00A0של החיד“א - עבודת הקודש, אשר בו שבעה מחלקים',
      ),
    );

    expect(find.textContaining('חיבורו של החיד"א'), findsOneWidget);
    expect(find.text('אשר בו שבעה מחלקים'), findsOneWidget);
  });
}
