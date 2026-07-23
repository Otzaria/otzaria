import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/view/book_versions_dialog.dart';
import 'package:otzaria/models/book_version.dart';
import 'package:otzaria/models/books.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

void main() {
  final book = TextBook(title: 'כתובות');

  testWidgets('הערות גרסה עם HTML מוצגות כטקסט מרונדר ולא כתגיות גולמיות', (
    tester,
  ) async {
    const notes =
        'הטקסט הארמי מתוך <a href="https://www.korenpub.com/">מהדורת קורן</a> '
        'עם ביאור מאת <a href="/adin-even-israel-steinsaltz">הרב שטיינזלץ</a>';
    await tester.pumpWidget(
      _wrap(
        BookVersionTile(
          book: book,
          version: const BookVersionInfo(
            versionTitle: 'William Davidson Edition - Aramaic',
            heVersionTitle: 'מהדורת דיווידסון - ארמית',
            heVersionNotes: notes,
            hasContent: true,
          ),
          isOnlyVersion: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('a href', findRichText: true), findsNothing);
    expect(
      find.textContaining('מהדורת קורן', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('הרב שטיינזלץ', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('גרסה ללא הערות מציגה רק את שורת הסטטוס', (tester) async {
    await tester.pumpWidget(
      _wrap(
        BookVersionTile(
          book: book,
          version: const BookVersionInfo(
            versionTitle: 'Wikisource Talmud Bavli',
            heVersionTitle: 'תלמוד בבלי (ויקיטקסט)',
            hasContent: false,
          ),
          isOnlyVersion: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('טקסט הגרסה אינו כלול במאגר הנוכחי'), findsOneWidget);
  });
}
