import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/dialogs/books_list_dialog.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

void main() {
  List<Book> buildBooks(int count) => List.generate(
    count,
    (i) => TextBook(
      title: 'ספר $i',
      author: 'מחבר $i',
      categoryPath: 'קטגוריה $i',
    ),
  );

  int naiveCount(List<Book> books, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return books.length;
    return books.where((b) {
      final category = (b.categoryPath ?? '').replaceFirst(RegExp(r'^/+'), '');
      return [
        b.title,
        b.author ?? '',
        category,
        b.fileType ?? '',
      ].any((f) => f.toLowerCase().contains(q));
    }).length;
  }

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

  testWidgets('ריחוף מציג שם ופרטים מלאים גם כשהשורה מקוצרת', (tester) async {
    final title = List.filled(14, 'שם ספר ארוך').join(' ');
    final author = List.filled(14, 'שם מחבר ארוך').join(' ');
    await openDialog(tester, [TextBook(title: title, author: author)]);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    final details = tester.widget<Text>(find.textContaining(author)).data!;
    for (final text in [title, details]) {
      final label = find.text(text);
      expect(
        tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
        isTrue,
      );
      expect(find.byTooltip(text), findsOneWidget);
      await mouse.moveTo(tester.getCenter(label));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text(text), findsNWidgets(2));
      expect(
        tester
            .renderObject<RenderParagraph>(find.text(text).last)
            .didExceedMaxLines,
        isFalse,
      );
      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('סינון אחרי קפיצה לסוף מעדכן את תחום הגלילה והתוצאות', (
    tester,
  ) async {
    await openDialog(tester, buildBooks(3000));
    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'מחבר 2999');
    await tester.pumpAndSettle();
    expect(find.text('1 / 3000'), findsOneWidget);
    expect(find.text('ספר 2999'), findsOneWidget);
    expect(controller.offset, 0);
    await tester.enterText(find.byType(TextField), 'לא קיים');
    await tester.pumpAndSettle();
    expect(find.text('לא נמצאו ספרים'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('3000 / 3000'), findsOneWidget);
    expect(find.text('ספר 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('קפיצה לסוף הרשימה לא בונה את כל השורות שבדרך (#3022)', (
    tester,
  ) async {
    await openDialog(tester, buildBooks(3000));
    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;

    var builtRows = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget.runtimeType.toString() == '_BookListRow') builtRows++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    // כמו גרירת ה-thumb לסוף: קפיצה רחוקה בפריים אחד.
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();

    expect(builtRows, lessThan(100));
    expect(find.text('ספר 2999'), findsOneWidget);
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
      expect(
        find.text('${naiveCount(books, query)} / ${books.length}'),
        findsOneWidget,
        reason: query,
      );
    }
  });

  testWidgets('הקלדה ומחיקה אות אחר אות ומעבר בין הרשימות: אותו סינון', (
    tester,
  ) async {
    const letters = ['א', 'ב', 'ג', 'A', 'b', ' '];
    final random = Random(7);
    String word(int length) => [
      for (var k = 0; k < length; k++) letters[random.nextInt(letters.length)],
    ].join();
    final books = [
      for (var i = 0; i < 300; i++)
        TextBook(
          title: word(4),
          author: word(3),
          categoryPath: '/${word(3)}',
          source: i % 3 == 0 ? BookSource.user : BookSource.official,
        ),
    ];
    final library = books.where((b) => !b.isPersonalBook).toList();
    final personal = books.where((b) => b.isPersonalBook).toList();
    await openDialog(tester, books);
    final field = find.byType(TextField);
    for (var n = 0; n < 12; n++) {
      final shown = n.isEven ? library : personal;
      if (n > 0) {
        await tester.tap(find.text(n.isEven ? 'ספרייה 200' : 'אישיים 100'));
        await tester.pumpAndSettle();
      }
      final text = word(5);
      final steps = [
        for (var k = 1; k <= text.length; k++) text.substring(0, k),
        for (var k = text.length - 1; k >= 0; k--) text.substring(0, k),
        // השאילתה מתארכת גם בתחילתה.
        text.substring(2),
        text,
      ];
      for (final query in steps) {
        await tester.enterText(field, query);
        await tester.pump();
        expect(
          find.text('${naiveCount(shown, query)} / ${shown.length}'),
          findsOneWidget,
          reason: '$n "$query"',
        );
      }
    }
  });

  group('שתי רשימות: ספרייה ואישיים', () {
    List<Book> mixedBooks() => [
      TextBook(title: 'ספר רשמי'),
      TextBook(title: 'ספר אישי', source: BookSource.user, fileType: 'txt'),
      TextBook(
        title: 'מסמך וורד',
        source: BookSource.user,
        fileType: 'docx',
        filePath: 'C:/docs/a.docx',
      ),
      TextBook(title: 'ספר ממסד מצורף', source: BookSource.attached('lib')),
    ];

    IconData leadingIcon(WidgetTester tester, String title) => tester
        .widget<Icon>(
          find
              .descendant(
                of: find.ancestor(
                  of: find.text(title),
                  matching: find.byType(ListTile),
                ),
                matching: find.byType(Icon),
              )
              .first,
        )
        .icon!;

    testWidgets('ברירת המחדל מציגה ספרי ספרייה, ואישיים מופרדים בלשונית', (
      tester,
    ) async {
      await openDialog(tester, mixedBooks());

      expect(find.text('ספרייה 1'), findsOneWidget);
      expect(find.text('אישיים 3'), findsOneWidget);
      expect(find.text('1 / 1'), findsOneWidget);
      expect(find.text('ספר רשמי'), findsOneWidget);
      expect(find.text('ספר אישי'), findsNothing);

      await tester.tap(find.text('אישיים 3'));
      await tester.pumpAndSettle();

      expect(find.text('3 / 3'), findsOneWidget);
      expect(find.text('ספר רשמי'), findsNothing);
      // ספר ממסד מצורף הוא ספר אישי לכל דבר.
      for (final title in ['ספר אישי', 'מסמך וורד', 'ספר ממסד מצורף']) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
    });

    testWidgets('מעבר בין הרשימות מנקה את החיפוש', (tester) async {
      await openDialog(tester, mixedBooks());
      await tester.enterText(find.byType(TextField), 'לא קיים');
      await tester.pumpAndSettle();
      expect(find.text('לא נמצאו ספרים'), findsOneWidget);

      await tester.tap(find.text('אישיים 3'));
      await tester.pumpAndSettle();

      expect(find.text('3 / 3'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
    });

    testWidgets('לכל ספר אייקון סוג כמו בספרייה', (tester) async {
      await openDialog(tester, mixedBooks());
      expect(
        leadingIcon(tester, 'ספר רשמי'),
        FluentIcons.document_text_24_regular,
      );

      await tester.tap(find.text('אישיים 3'));
      await tester.pumpAndSettle();

      expect(
        leadingIcon(tester, 'ספר אישי'),
        OtzariaIcons.document_alef_24_regular,
      );
      expect(
        leadingIcon(tester, 'מסמך וורד'),
        OtzariaIcons.document_word_24_regular,
      );
    });
  });

  group('אייקון לפי פורמט, כמו בספרייה', () {
    testWidgets('HTML ו-Markdown אישיים מקבלים אייקון משלהם', (tester) async {
      TextBook personal(String type) => TextBook(
        title: 'קובץ $type',
        source: BookSource.user,
        fileType: type,
        filePath: 'C:/docs/a.$type',
      );
      await openDialog(tester, [
        personal('html'),
        personal('htm'),
        personal('md'),
        personal('markdown'),
        personal('doc'),
        personal('epub'),
        personal('odt'),
        personal('rtf'),
        personal('pdf'),
        TextBook(
          title: 'html מצורף',
          source: BookSource.attached('lib'),
          fileType: 'html',
        ),
        TextBook(title: 'md רשמי', fileType: 'md'),
      ]);
      // הרשימה עצלה: שורה נבנית רק כשגוללים אליה, לכן בודקים לפי הסדר.
      Future<IconData> icon(String title) async {
        await tester.scrollUntilVisible(
          find.text(title),
          100,
          scrollable: find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
        );
        return tester
            .widget<Icon>(
              find
                  .descendant(
                    of: find.ancestor(
                      of: find.text(title),
                      matching: find.byType(ListTile),
                    ),
                    matching: find.byType(Icon),
                  )
                  .first,
            )
            .icon!;
      }

      expect(await icon('md רשמי'), FluentIcons.document_text_24_regular);

      await tester.tap(find.textContaining('אישיים'));
      await tester.pumpAndSettle();

      final expected = {
        'קובץ html': OtzariaIcons.document_html_24_regular,
        'קובץ htm': OtzariaIcons.document_html_24_regular,
        'קובץ md': OtzariaIcons.document_md_24_regular,
        'קובץ markdown': OtzariaIcons.document_md_24_regular,
        'קובץ doc': OtzariaIcons.document_word_24_regular,
        'קובץ epub': OtzariaIcons.book_pdf_24_regular,
        'קובץ odt': OtzariaIcons.document_word_24_regular,
        'קובץ rtf': OtzariaIcons.document_word_24_regular,
        'קובץ pdf': OtzariaIcons.book_pdf_24_regular,
        'html מצורף': OtzariaIcons.document_html_24_regular,
      };
      for (final MapEntry(key: title, value: expectedIcon)
          in expected.entries) {
        expect(await icon(title), expectedIcon, reason: title);
      }
    });
  });

  group('buildBooksCsv', () {
    test('מתחיל ב-BOM ובכותרות העמודות', () {
      final csv = buildBooksCsv(const []);
      expect(csv.codeUnitAt(0), 0xFEFF);
      expect(
        csv.substring(1),
        'כותרת,מחבר,קטגוריה,סוג קובץ,מקור\r\n',
      );
    });

    test('מצטט פסיקים, מרכאות ושורות חדשות', () {
      final csv = buildBooksCsv([
        TextBook(
          title: 'שם, עם פסיק',
          author: 'ה"מחבר"',
          categoryPath: 'שורה א\nשורה ב',
          fileType: 'txt',
        ),
      ]);
      expect(
        csv.split('\r\n')[1],
        '"שם, עם פסיק","ה""מחבר""","שורה א\nשורה ב",txt,ספרייה',
      );
    });

    test('עמודת המקור: ספרייה לפני אישי, גם לספר ממסד מצורף', () {
      final csv = buildBooksCsv([
        TextBook(title: 'אישי', source: BookSource.user),
        TextBook(title: 'מצורף', source: BookSource.attached('lib')),
        TextBook(title: 'רשמי'),
      ]);
      expect(csv.split('\r\n').skip(1).where((line) => line.isNotEmpty), [
        'רשמי,,,txt,ספרייה',
        'אישי,,,txt,אישי',
        'מצורף,,,txt,אישי',
      ]);
    });
  });
}
