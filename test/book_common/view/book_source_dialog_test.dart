import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/view/book_source_dialog.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/services/book_details_service.dart';
import 'package:otzaria/theme/app_tokens.dart';

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

  group('descriptionSpans', () {
    const base = 14.0;
    const muted = Color(0xFF888888);

    test('text without parentheses stays a single span', () {
      final spans = descriptionSpans('פירוש על התורה', base, muted);
      expect(spans, hasLength(1));
      expect((spans.single as TextSpan).text, equals('פירוש על התורה'));
    });

    test('round is smaller and muted, square is slightly smaller', () {
      final spans = descriptionSpans('א (ב) ג [ד] ה', base, muted);
      expect(
        spans.map((s) => (s as TextSpan).text),
        equals(['א ', '(ב)', ' ג ', '[ד]', ' ה']),
      );
      final round = (spans[1] as TextSpan).style!;
      final square = (spans[3] as TextSpan).style!;
      expect(round.fontSize, closeTo(base * 0.78, 0.001));
      expect(round.color, equals(muted));
      expect(round.fontWeight, equals(FontWeight.normal));
      expect(square.fontSize, closeTo(base * 0.92, 0.001));
      expect(square.color, isNull);
      expect(square.fontWeight, equals(FontWeight.normal));
    });

    test('a text that is only parenthetical is a single span', () {
      final spans = descriptionSpans('(א)', base, muted);
      expect(spans, hasLength(1));
      expect((spans.single as TextSpan).text, equals('(א)'));
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

  testWidgets('בתיאור הקצר בהדגשה מעודנת וההמשך מוקטן, והתווית היא מדף', (
    tester,
  ) async {
    final book = TextBook(
      title: 'משנה ברורה',
      heCategories: 'הלכה',
      heShortDesc: 'ביאור על התורה.',
      heDesc: "ביאור על התורה. חובר בצפת (בערך ה'ש\"ך).",
    );
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

    expect(find.text('מדף'), findsOneWidget);
    expect(find.text('קטגוריות'), findsNothing);

    final description = tester.widget<RichText>(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().startsWith('ביאור על'),
      ),
    );
    // visitChildren מדלג על קטעים שאין להם טקסט משלהם, ולכן עוברים ידנית.
    final spans = <TextSpan>[];
    void collect(InlineSpan span) {
      if (span is! TextSpan) return;
      spans.add(span);
      span.children?.forEach(collect);
    }

    collect(description.text);
    final lead = spans.firstWhere(
      (s) =>
          s.toPlainText() == 'ביאור על התורה.' &&
          s.style?.fontWeight == FontWeight.w600,
    );
    final rest = spans.firstWhere(
      (s) => s.toPlainText().startsWith('חובר') && s.style?.fontSize != null,
    );
    expect(lead.style!.fontWeight, equals(FontWeight.w600));
    expect(rest.style!.fontSize, lessThan(AppTokens.fontMD));
    expect(rest.style!.fontWeight, isNull);
  });
}
