import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/view/book_source_dialog.dart';
import 'package:otzaria/external_catalog/repository/external_catalog_repository.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/services/book_details_service.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/dialogs/details_info_section.dart';

void main() {
  group('libraryDisplayPath', () {
    test('strips the library prefix and the extension', () {
      expect(
        libraryDisplayPath(
          'אוצריא/תלמוד ירושלמי/סדר נזיקין/תלמוד ירושלמי שבועות.txt',
        ),
        'תלמוד ירושלמי/סדר נזיקין/תלמוד ירושלמי שבועות',
      );
    });

    test('keeps a dot inside a category name', () {
      expect(libraryDisplayPath('אוצריא/א.ב/ספר'), 'א.ב/ספר');
    });

    test('returns null for a path outside the library', () {
      expect(libraryDisplayPath('C:/books/ספר.pdf'), isNull);
    });
  });

  group('getSourceDisplayInfo', () {
    test('should resolve Sefaria source case-insensitively', () {
      final lower = getSourceDisplayInfo('sefaria');
      final upper = getSourceDisplayInfo('Sefaria');

      expect(lower.text, equals('ספריא'));
      expect(upper.text, equals('ספריא'));
      expect(lower.url, equals('https://www.sefaria.org/texts'));
      expect(upper.url, equals('https://www.sefaria.org/texts'));
    });

    test('should resolve Tashma source with link', () {
      final info = getSourceDisplayInfo('Tashma');

      expect(info.text, equals('תא שמע'));
      expect(info.url, equals('https://tashma.co.il/'));
    });

    test(
      'should resolve the wikiJewishBooksToOtzaria source as stored in DB',
      () {
        final info = getSourceDisplayInfo('wikiJewishBooksToOtzaria');

        expect(info.text, equals('אוצר הספרים היהודי השיתופי'));
        expect(info.url, equals('https://wiki.jewishbooks.org.il/'));
        expect(info.logo, isEmpty);
      },
    );

    test(
      'should resolve yam-HaHachma with its name, link and required logo',
      () {
        final info = getSourceDisplayInfo('yam-HaHachmaToOtzaria');

        expect(info.text, equals('ים החכמה'));
        expect(info.url, equals('https://github.com/torahtyh/yam-HaHachma'));
        expect(info.logo, equals(kYamHaHachmaLogoAsset));
      },
    );

    test('should resolve the KSK source as stored in DB', () {
      final info = getSourceDisplayInfo('KSK');

      expect(info.text, equals('קובץ שיטות קמאי'));
      expect(info.url, isEmpty);
      expect(info.logo, isEmpty);
    });

    test(
      'should resolve the BeitAharonVeYisraelToOtzaria source as stored in DB',
      () {
        final info = getSourceDisplayInfo('BeitAharonVeYisraelToOtzaria');

        expect(info.text, equals('מכון בית אהרן וישראל'));
        expect(info.url, equals('https://machon.co.il/'));
        expect(info.logo, isEmpty);
      },
    );

    test('unknown sources fall back to the raw name without a logo', () {
      final info = getSourceDisplayInfo('SomeNewSourceToOtzaria');

      expect(info.text, equals('SomeNewSourceToOtzaria'));
      expect(info.url, isEmpty);
      expect(info.logo, isEmpty);
    });
  });

  group('isTashmaSource', () {
    test('should detect Tashma source case-insensitively', () {
      expect(isTashmaSource('Tashma'), isTrue);
      expect(isTashmaSource('tashma'), isTrue);
      expect(isTashmaSource('TashmaToOtzaria'), isTrue);
    });

    test('should detect Tashma variants with separators', () {
      // אותו נרמול כמו getSourceDisplayInfo - הסרת רווחים/מקפים/קווים תחתונים
      expect(isTashmaSource('Ta-Shma'), isTrue);
      expect(isTashmaSource('Ta Shma'), isTrue);
      expect(isTashmaSource('Ta_Shma'), isTrue);
      // כל הווריאנטים האלה גם מזוהים כתא שמע בתצוגת המקור
      expect(getSourceDisplayInfo('Ta-Shma').text, equals('תא שמע'));
    });

    test('should return false for non-Tashma or empty sources', () {
      expect(isTashmaSource('sefaria'), isFalse);
      expect(isTashmaSource(''), isFalse);
      expect(isTashmaSource(null), isFalse);
    });
  });

  group('splitShortAndFullDescription', () {
    test('should split when the full description starts with the short', () {
      final r = splitShortAndFullDescription('קצר.', 'קצר. והמשך ארוך.');
      expect(r, isNotNull);
      expect(r!.lead, equals('קצר.'));
      expect(r.rest, equals('והמשך ארוך.'));
    });

    test('should ignore surrounding whitespace', () {
      final r = splitShortAndFullDescription('  קצר. ', '\nקצר.  המשך \n');
      expect(r!.lead, equals('קצר.'));
      expect(r.rest, equals('המשך'));
    });

    test('should drop punctuation that links the short to the long text', () {
      final r = splitShortAndFullDescription('קצר', 'קצר. והמשך ארוך.');
      expect(r!.rest, equals('והמשך ארוך.'));
      expect(
        splitShortAndFullDescription('קצר', 'קצר, והמשך')!.rest,
        equals('והמשך'),
      );
    });

    test('should return an empty rest when both are identical', () {
      final r = splitShortAndFullDescription('קצר.', 'קצר.');
      expect(r!.rest, isEmpty);
    });

    test('should match despite NBSP, quote variants and punctuation', () {
      final r = splitShortAndFullDescription(
        'חיבורו של החיד"א - עבודת הקודש',
        'חיבורו\u00A0של החיד“א - עבודת הקודש, אשר בו שבעה מחלקים',
      );
      expect(r!.lead, equals('חיבורו של החיד"א - עבודת הקודש'));
      expect(r.rest, equals('אשר בו שבעה מחלקים'));
    });

    for (final (short, full, rest) in [
      (
        "חיבורים בענייני מוסר ועבודת ה'.",
        "חיבורים בענייני מוסר ועבודת ה'.",
        '',
      ),
      ('פירוש (חדש)', 'פירוש (חדש). המשך', 'המשך'),
      ('פירוש (חדש)', 'פירוש\u00A0(חדש). המשך', 'המשך'),
      ('“פירוש”', '"פירוש". המשך', 'המשך'),
      ("עבודת ה׳.", "עבודת ה'. המשך", 'המשך'),
      ('“פירוש”', '"פירוש". "ציטוט"', '"ציטוט"'),
      ('קצר', 'קצר. (המשך)', '(המשך)'),
      ('קצר', 'קצר. "ציטוט"', '"ציטוט"'),
      ('פירוש (חדש)', 'פירוש (חדש). (המשך)', '(המשך)'),
    ]) {
      test('preserves the description boundary: $full', () {
        expect(splitShortAndFullDescription(short, full)!.rest, rest);
      });
    }

    test(
      'keeps separate fields when trailing punctuation cannot be matched',
      () {
        expect(
          splitShortAndFullDescription('פירוש (חדש).', 'פירוש (חדש), המשך'),
          isNull,
        );
      },
    );

    test('should return null when the full does not start with the short', () {
      expect(splitShortAndFullDescription('קצר.', 'אחר לגמרי'), isNull);
    });

    test('should return null when either description is missing or empty', () {
      expect(splitShortAndFullDescription(null, 'ארוך'), isNull);
      expect(splitShortAndFullDescription('   ', 'ארוך'), isNull);
      expect(splitShortAndFullDescription('קצר', null), isNull);
      expect(splitShortAndFullDescription('קצר', ''), isNull);
    });
  });

  group('hebrewPublicationDate', () {
    test('converts a bare Gregorian year to a Hebrew year', () {
      expect(hebrewPublicationDate('1884'), equals('ה׳תרמ״ד (1884)'));
    });

    test('keeps four-digit values that are not a plausible Gregorian year', () {
      expect(hebrewPublicationDate('5644'), equals('5644'));
      expect(hebrewPublicationDate('2240'), equals('2240'));
      expect(hebrewPublicationDate('1399'), equals('1399'));
      expect(hebrewPublicationDate('0650'), equals('0650'));
    });

    test('converts the boundary years', () {
      final now = DateTime.now().year;
      expect(hebrewPublicationDate('1400'), endsWith('(1400)'));
      expect(hebrewPublicationDate('$now'), endsWith('($now)'));
      expect(hebrewPublicationDate('${now + 1}'), endsWith('(${now + 1})'));
      expect(hebrewPublicationDate('${now + 2}'), equals('${now + 2}'));
    });

    test('keeps values that are not a four-digit year', () {
      expect(hebrewPublicationDate("ה' תרג"), equals("ה' תרג"));
      expect(hebrewPublicationDate('650'), equals('650'));
    });
  });

  testWidgets('אודות הספר מציג תקופה ותאריך פרסום עברי', (tester) async {
    final book = TextBook(title: 'משנה ברורה', pubDate: '1884');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showBookDetailsDialog(
              context,
              book,
              information: BookInformation(
                book: book,
                databaseBook: null,
                source: 'Sefaria',
                generation: 'אחרונים',
                fileDetails: const {
                  'נתיב הקובץ': BookDetailsService.bookNotFoundText,
                },
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('תקופה'), findsOneWidget);
    expect(find.text('אחרונים'), findsOneWidget);
    expect(find.text('דור'), findsNothing);
    expect(find.text('ה׳תרמ״ד (1884)'), findsOneWidget);
  });

  testWidgets('תקופה ריקה במסד נופלת לתקופת הספר', (tester) async {
    final book = TextBook(title: 'משנה ברורה', heEra: 'אחרונים');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showBookDetailsDialog(
              context,
              book,
              information: BookInformation(
                book: book,
                databaseBook: null,
                source: 'Sefaria',
                generation: '  ',
                fileDetails: const {
                  'נתיב הקובץ': BookDetailsService.bookNotFoundText,
                },
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('תקופה'), findsOneWidget);
    expect(find.text('אחרונים'), findsOneWidget);
  });

  group('אוצר החכמה באודות הספר', () {
    final defaultLoader = otzarBooksForOtzariaId;
    final defaultOpener = openOtzarBook;
    tearDown(() {
      otzarBooksForOtzariaId = defaultLoader;
      openOtzarBook = defaultOpener;
    });

    OtzarMappedBook mapped(
      int id,
      String? volume, {
      String title = 'הלכות גדולות',
      String? pubDate,
      String? author,
      String? pubPlace,
    }) => (
      book: ExternalLibraryBook(
        title: title,
        id: id,
        pubDate: pubDate,
        author: author,
        pubPlace: pubPlace,
        link: 'https://tablet.otzar.org/book/book.php?book=$id',
      ),
      volume: volume,
    );

    Future<void> openDialog(
      WidgetTester tester,
      Book book, {
      ThemeData? theme,
      TextScaler textScaler = TextScaler.noScaling,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showBookDetailsDialog(
                context,
                book,
                information: BookInformation(
                  book: book,
                  databaseBook: null,
                  source: 'Sefaria',
                  generation: 'ראשונים',
                  fileDetails: const {
                    'נתיב הקובץ': BookDetailsService.bookNotFoundText,
                  },
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('בלי מיפוי השורה אינה מוצגת', (tester) async {
      final requested = <int>[];
      otzarBooksForOtzariaId = (id) async {
        requested.add(id);
        return const [];
      };
      await openDialog(tester, TextBook(title: 'הלכות גדולות', id: 7));

      expect(requested, [7]);
      expect(find.text('ראשונים'), findsOneWidget);
      expect(find.text('פתח באוצר החכמה'), findsNothing);
    });

    testWidgets('ספר אישי אינו נבדק במיפוי', (tester) async {
      var called = false;
      otzarBooksForOtzariaId = (id) async {
        called = true;
        return [mapped(42, null)];
      };
      await openDialog(
        tester,
        TextBook(title: 'הלכות גדולות', id: 7, source: BookSource.user),
      );

      expect(called, isFalse);
      expect(find.text('פתח באוצר החכמה'), findsNothing);
    });

    testWidgets('ספר ממופה אחד מוצג כשורה אחת', (tester) async {
      otzarBooksForOtzariaId = (id) async => [
        mapped(42, 'כרך א', pubDate: 'תרכ"ה', author: 'מחבר', pubPlace: 'ורשה'),
      ];
      await openDialog(tester, TextBook(title: 'הלכות גדולות', id: 7));

      expect(find.text('אוצר החכמה'), findsOneWidget);
      expect(find.text('פתח באוצר החכמה'), findsOneWidget);
    });

    testWidgets('כמה ספרים ממופים מוצגים לפי הכרך', (tester) async {
      otzarBooksForOtzariaId = (id) async => [
        mapped(42, 'כרך א'),
        mapped(43, null, pubDate: 'תרכ"ה'),
        mapped(44, null),
      ];
      await openDialog(tester, TextBook(title: 'הלכות גדולות', id: 7));

      expect(find.text('אוצר החכמה – הלכות גדולות – כרך א'), findsOneWidget);
      expect(find.text('אוצר החכמה – הלכות גדולות (תרכ"ה)'), findsOneWidget);
      expect(find.text('אוצר החכמה – הלכות גדולות'), findsOneWidget);
      expect(find.text('פתח באוצר החכמה'), findsNWidgets(3));
    });

    testWidgets('הקשה על שורה פותחת את הספר הממופה שלה', (tester) async {
      final opened = <(int?, String)>[];
      openOtzarBook = (bookId, link) async {
        opened.add((bookId, link));
        return true;
      };
      otzarBooksForOtzariaId = (id) async => [
        mapped(42, 'כרך א'),
        mapped(43, 'כרך ב'),
      ];
      await openDialog(tester, TextBook(title: 'הלכות גדולות', id: 7));

      await tester.tap(find.text('פתח באוצר החכמה').last);
      await tester.pump();

      expect(opened, [(43, 'https://tablet.otzar.org/book/book.php?book=43')]);
    });

    for (final (name, seed, brightness) in [
      ('בהיר', AppSeedColors.defaultLight, Brightness.light),
      ('כהה', AppSeedColors.defaultDark, Brightness.dark),
      ('לבן', AppSeedColors.white, Brightness.light),
    ]) {
      for (final width in [360.0, 1200.0]) {
        testWidgets('מהדורות באותו כרך נבדלות לפי השנה, $name $width', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final cs = AppThemeData.createColorScheme(seed, brightness);
          final theme = brightness == Brightness.light
              ? AppThemeData.light(
                  cs,
                  compactMenuMode: false,
                  variant: AppThemeVariant.ofSeed(seed),
                )
              : AppThemeData.dark(cs, compactMenuMode: false);
          final opened = <int?>[];
          openOtzarBook = (bookId, link) async {
            opened.add(bookId);
            return true;
          };
          otzarBooksForOtzariaId = (_) async => [
            mapped(
              42,
              'יורה דעה',
              title: 'שלחן ערוך',
              pubDate: 'תשי"ג',
              author: 'קארו, יוסף',
              pubPlace: 'ניו יורק',
            ),
            mapped(
              43,
              'יורה דעה',
              title: 'שלחן ערוך',
              pubDate: 'שנ"ג–שנ"ד',
              author: 'קארו, יוסף',
              pubPlace: 'ונציה',
            ),
          ];
          await openDialog(
            tester,
            TextBook(title: 'שולחן ערוך, יורה דעה', id: 7),
            theme: theme,
            textScaler: TextScaler.linear(1.3),
          );

          expect(
            find.text('אוצר החכמה – שלחן ערוך – יורה דעה (תשי"ג)'),
            findsOneWidget,
          );
          final edition = find.text(
            'אוצר החכמה – שלחן ערוך – יורה דעה (שנ"ג–שנ"ד)',
          );
          expect(edition, findsOneWidget);
          final row = find.ancestor(
            of: edition,
            matching: find.byType(DetailsInfoSection),
          );
          final link = find.descendant(
            of: row,
            matching: find.text('פתח באוצר החכמה'),
          );
          await tester.ensureVisible(link);
          await tester.tap(link);
          await tester.pump();
          expect(opened, [43]);
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final year in [null, 'תרכ"ה']) {
      testWidgets('תוויות חופפות עם שנה $year נבדלות לפי פרטים קיימים', (
        tester,
      ) async {
        otzarBooksForOtzariaId = (_) async => [
          mapped(
            42,
            'כרך א',
            pubDate: year,
            author: 'מחבר א',
            pubPlace: 'ורשה',
          ),
          mapped(
            43,
            'כרך א',
            pubDate: year,
            author: 'מחבר ב',
            pubPlace: 'וילנה',
          ),
        ];
        await openDialog(tester, TextBook(title: 'הלכות גדולות', id: 7));
        final labels = tester
            .widgetList<DetailsInfoSection>(find.byType(DetailsInfoSection))
            .map((row) => row.title)
            .where((title) => title.startsWith('אוצר החכמה'))
            .toList();
        expect(labels, hasLength(2));
        expect(labels.first, contains('מחבר א, ורשה'));
        expect(labels.last, contains('מחבר ב, וילנה'));
      });
    }

    testWidgets('סגירת החלון לפני שהמיפוי נטען אינה זורקת', (tester) async {
      final pending = Completer<List<OtzarMappedBook>>();
      otzarBooksForOtzariaId = (id) => pending.future;
      await openDialog(tester, TextBook(title: 'הלכות גדולות', id: 7));

      await tester.tap(find.text('סגור'));
      await tester.pumpAndSettle();
      expect(find.text('אודות הספר'), findsNothing);

      pending.complete([mapped(42, 'כרך א')]);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
