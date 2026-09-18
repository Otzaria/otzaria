import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/view/external_book_dialog.dart';
import 'package:otzaria/models/books.dart';

/// דיאלוג פרטי הספר עבור ספר של בר אילן.
///
/// הניסוח כאן אינו קוסמטיקה: המשתמש מגיע לדיאלוג כדי להחליט אם ללחוץ,
/// ו"פתח בתוכנה" משאיר אותו לנחש איזו תוכנה תיפתח. כך גם "מקור" מול
/// "מקור הספר" ו"הקשר" מול "קטגוריה".
void main() {
  ExternalLibraryBook book() => ExternalLibraryBook(
    title: 'הון עשיר אבות',
    id: 1524,
    link: null,
    categoryPath: 'מפרשי המשנה ומדרשי הלכה/הון עשיר',
    externalLibraryId: 'rp:1524',
  );

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ExternalBookDialog(
            book: book(),
            onOpenLocally: (_) async => null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('הכפתור נושא את שם התוכנה', (tester) async {
    await show(tester);

    expect(find.text('פתח בבר אילן'), findsOneWidget);
    expect(find.text('פתח בתוכנה'), findsNothing);
  });

  testWidgets('שמות השדות', (tester) async {
    await show(tester);

    expect(
      find.textContaining('מקור הספר', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('קטגוריה', findRichText: true), findsOneWidget);
  });

  testWidgets('שם הספק כולל את "בר אילן"', (tester) async {
    await show(tester);

    expect(find.textContaining('בר אילן'), findsWidgets);
  });

  testWidgets('אין "פתח באתר" — לבר אילן אין אתר', (tester) async {
    await show(tester);

    expect(find.text('פתח באתר'), findsNothing);
    expect(find.text('הורדת הקובץ'), findsNothing);
  });

  testWidgets('שדה בלי מקור אינו מוצג כ"לא ידוע"', (tester) async {
    await show(tester);

    // למאגר אין שדה מחבר, שנת הדפסה או מקום הדפסה.
    expect(find.textContaining('לא ידוע', findRichText: true), findsNothing);
    expect(find.textContaining('מחבר:', findRichText: true), findsNothing);
  });
}
