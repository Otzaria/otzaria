import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/library/view/book_versions_dialog.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/book_version.dart';
import 'package:otzaria/models/books.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

void main() {
  final book = TextBook(title: 'כתובות');

  const davidson = BookVersionInfo(
    versionTitle: 'William Davidson Edition - Aramaic',
    heVersionTitle: 'מהדורת דיווידסון - ארמית',
    hasContent: true,
  );
  const wikisource = BookVersionInfo(
    versionTitle: 'Wikisource Talmud Bavli',
    heVersionTitle: 'תלמוד בבלי (ויקיטקסט)',
    hasContent: true,
  );

  group('selectableVersionsFor', () {
    test('בנוסח הממוזג כל המהדורות מוצעות', () {
      expect(
        selectableVersionsFor(const [davidson, wikisource], null),
        [davidson, wikisource],
      );
    });

    test('הנוסח שכבר פתוח אינו מוצע שוב', () {
      expect(
        selectableVersionsFor(const [
          davidson,
          wikisource,
        ], davidson.versionTitle),
        [wikisource],
      );
    });
  });

  group('רשימת הנוסחאות בדיאלוג', () {
    tearDown(() => bookVersionsListProbeForTesting = null);

    Future<void> pumpDialog(WidgetTester tester, TextBook book) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showBookVersionsDialog(context, book),
              child: const Text('פתח'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();
    }

    testWidgets('כשהנוסח הפתוח הוא היחיד במאגר מוצג מצב ריק ולא רשימה', (
      tester,
    ) async {
      bookVersionsListProbeForTesting = (_) async => const [davidson];

      await pumpDialog(
        tester,
        book.copyWith(versionTitle: davidson.versionTitle),
      );

      expect(find.text('אין נוסחאות נוספות מלבד הנוסח הפתוח.'), findsOneWidget);
      expect(find.text(davidson.displayTitle), findsNothing);
    });

    testWidgets('הנוסח הפתוח מסונן, והאחרים נשארים ברשימה', (tester) async {
      bookVersionsListProbeForTesting = (_) async => const [
        davidson,
        wikisource,
      ];

      await pumpDialog(
        tester,
        book.copyWith(versionTitle: davidson.versionTitle),
      );

      expect(find.text(davidson.displayTitle), findsNothing);
      expect(find.text(wikisource.displayTitle), findsOneWidget);
    });

    testWidgets('ספר בלי מידע גרסאות מציג מצב ריק', (tester) async {
      bookVersionsListProbeForTesting = (_) async => const [];

      await pumpDialog(tester, book);

      expect(find.text('לא נמצא מידע על גרסאות לספר זה.'), findsOneWidget);
    });

    testWidgets('בספר אישי הקובץ הפתוח מסונן, ובחירה פותחת את קובץ הגרסה', (
      tester,
    ) async {
      final primary = PdfBook(
        id: 1,
        title: 'רשבא',
        path: '/b/רשבא.pdf',
        source: BookSource.user,
      );
      final kook = PdfBook(
        id: 2,
        title: 'רשבא קוק',
        path: '/b/רשבא קוק.pdf',
        source: BookSource.user,
      );
      bookVersionsListProbeForTesting = (_) async => [
        BookVersionInfo(
          versionTitle: 'דפוס ישן',
          hasContent: true,
          separateBook: primary,
        ),
        BookVersionInfo(
          versionTitle: 'מוסד הרב קוק',
          hasContent: true,
          separateBook: kook,
        ),
      ];
      Book? selected;

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showBookVersionsDialog(
                context,
                primary,
                onVersionSelected: (target) => selected = target,
              ),
              child: const Text('פתח'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('פתח'));
      await tester.pumpAndSettle();

      expect(find.text('דפוס ישן'), findsNothing);
      await tester.tap(find.text('מוסד הרב קוק'));
      await tester.pumpAndSettle();

      expect(selected, same(kook));
    });

    group('ספר רשמי עם גרסה אישית', () {
      final personal = TextBook(
        id: 7,
        title: 'כתובות - כתב יד',
        source: BookSource.user,
      );
      final personalVersion = BookVersionInfo(
        versionTitle: 'כתב יד מינכן',
        hasContent: true,
        separateBook: personal,
      );

      Future<Book?> pumpAndPick(
        WidgetTester tester,
        TextBook opened,
        String pick, {
        void Function()? beforePick,
      }) async {
        Book? selected;
        await tester.pumpWidget(
          _wrap(
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showBookVersionsDialog(
                  context,
                  opened,
                  onVersionSelected: (target) => selected = target,
                ),
                child: const Text('פתח'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('פתח'));
        await tester.pumpAndSettle();
        beforePick?.call();
        await tester.tap(find.text(pick));
        await tester.pumpAndSettle();
        return selected;
      }

      testWidgets(
        'הגרסה האישית מוצגת לצד המהדורות, ובחירתה פותחת את הספר האישי',
        (
          tester,
        ) async {
          bookVersionsListProbeForTesting = (_) async => [
            davidson,
            wikisource,
            personalVersion,
          ];

          final selected = await pumpAndPick(
            tester,
            book.copyWith(versionTitle: davidson.versionTitle),
            'כתב יד מינכן',
          );

          expect(find.text(davidson.displayTitle), findsNothing);
          expect(selected, same(personal));
        },
      );

      testWidgets('גרסה אישית אינה הופכת מהדורה יחידה בלי טקסט ללא-זמינה', (
        tester,
      ) async {
        const metadataOnly = BookVersionInfo(
          versionTitle: 'Vilna Edition',
          heVersionTitle: 'דפוס וילנא',
          hasContent: false,
        );
        bookVersionsListProbeForTesting = (_) async => [
          metadataOnly,
          personalVersion,
        ];

        final selected = await pumpAndPick(
          tester,
          book,
          'דפוס וילנא',
          beforePick: () => expect(
            find.text('הנוסח המוצג בספרייה'),
            findsOneWidget,
          ),
        );

        expect(selected, same(book));
      });
    });
  });

  testWidgets('onSelected מקבל את הספר בנוסח שנבחר במקום לפתוח כרטיסייה', (
    tester,
  ) async {
    Book? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: BookVersionTile(
                    book: book,
                    version: davidson,
                    isOnlyVersion: false,
                    onSelected: (target) => selected = target,
                  ),
                ),
              ),
              child: const Text('פתח'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('מהדורת דיווידסון - ארמית'));
    await tester.pumpAndSettle();

    expect(selected?.title, 'כתובות');
    expect((selected as TextBook?)?.versionTitle, davidson.versionTitle);
  });

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
