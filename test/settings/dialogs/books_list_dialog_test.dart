import 'dart:math';

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

  testWidgets('הסינון זהה להשוואה נאיבית של כל שדה באותיות קטנות', (
    tester,
  ) async {
    const letters = ['א', 'ב', 'A', 'b', 'Ä', 'ß', 'İ', ' ', '/'];
    final random = Random(3);
    String word() => [
      for (var k = random.nextInt(5); k > 0; k--)
        letters[random.nextInt(letters.length)],
    ].join();
    final books = [
      for (var i = 0; i < 300; i++)
        TextBook(
          title: word(),
          author: random.nextBool() ? word() : null,
          categoryPath: random.nextBool() ? '/${word()}' : null,
        ),
    ];
    await openDialog(tester, books);
    final field = find.byType(TextField);
    for (var n = 0; n < 60; n++) {
      final query = word();
      await tester.enterText(field, query);
      await tester.pump();
      final q = query.trim().toLowerCase();
      final expected = q.isEmpty
          ? books.length
          : books.where((b) {
              final category = (b.categoryPath ?? '').replaceFirst(
                RegExp(r'^/+'),
                '',
              );
              return [
                b.title,
                b.author ?? '',
                category,
                b.fileType ?? '',
              ].any((f) => f.toLowerCase().contains(q));
            }).length;
      expect(
        find.text('$expected / ${books.length}'),
        findsOneWidget,
        reason: query,
      );
    }
  });
}
