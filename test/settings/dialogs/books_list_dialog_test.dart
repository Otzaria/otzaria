import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/dialogs/books_list_dialog.dart';

void main() {
  List<Book> buildBooks(int count) => List.generate(
    count,
    (i) => TextBook(
      title: 'ספר $i',
      author: 'מחבר $i',
      categoryPath: 'קטגוריה $i',
    ),
  );

  Future<void> openDialog(WidgetTester tester, List<Book> books) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    showBooksListDialog(context: context, books: books),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'פס הגלילה וה-ListView חולקים אותו ScrollController (פס גלילה לחיץ)',
    (tester) async {
      await openDialog(tester, buildBooks(50));

      final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
      final listView = tester.widget<ListView>(find.byType(ListView));

      // שורש התיקון: בלי controller משותף, ה-thumb אינו גריר.
      expect(scrollbar.controller, isNotNull);
      expect(listView.controller, isNotNull);
      expect(scrollbar.controller, same(listView.controller));
      expect(scrollbar.thumbVisibility, isTrue);
    },
  );

  testWidgets('גלילה דרך ה-controller המשותף מזיזה את הרשימה', (tester) async {
    await openDialog(tester, buildBooks(50));

    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    expect(controller.offset, 0);

    controller.jumpTo(200);
    await tester.pump();

    expect(controller.offset, 200);
  });
}
