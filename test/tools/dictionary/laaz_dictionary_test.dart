import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/dictionary/dictionary_context_menu_entries.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';

void main() {
  group('LaazDictionaryEntry.parseLine', () {
    test('מפרק ערך תלמוד מלא עם תרגום אנגלי', () {
      final entry = LaazDictionaryEntry.parseLine(
        '7 / (ברכות ט:) / <b>כרתי</b> פוריל"ש / porels / '
        '<b>כרשים (ירק מאכל)</b> '
        '<span dir="ltr">✭ leek (vegetable used as food)</span>',
      );

      expect(entry, isNotNull);
      expect(entry!.entryNumber, '7');
      expect(entry.sourceReference, 'ברכות ט:');
      expect(entry.lemma, 'כרתי');
      expect(entry.laazHebrew, 'פוריל"ש');
      expect(entry.laazLatin, 'porels');
      expect(entry.meaning, 'כרשים (ירק מאכל)');
      expect(entry.note, isNull);
      expect(entry.english, 'leek (vegetable used as food)');
    });

    test('מפרק ערך תנ"ך עם הערה ובלי אנגלית', () {
      final entry = LaazDictionaryEntry.parseLine(
        '3001 / (בראשית א,ב) / <b>תהו</b> אישטורדישו"ן / estordison / '
        '<b>עילפון, הלם, מבוכה</b> <small>ר\' אה"ל 549 ועוד.</small>',
      );

      expect(entry, isNotNull);
      expect(entry!.sourceReference, 'בראשית א,ב');
      expect(entry.lemma, 'תהו');
      expect(entry.laazHebrew, 'אישטורדישו"ן');
      expect(entry.laazLatin, 'estordison');
      expect(entry.meaning, 'עילפון, הלם, מבוכה');
      expect(entry.note, 'ר\' אה"ל 549 ועוד.');
      expect(entry.english, isNull);
    });

    test('שומר צורה מנורמלת בסוגריים מרובעים בשדה הלטיני', () {
      final entry = LaazDictionaryEntry.parseLine(
        '14 / (ברכות כד.) / <b>פיהק</b> בדייליי"ר / '
        'badeilier [badaillier] / <b>לפהק</b> '
        '<span dir="ltr">✭ to yawn</span>',
      );

      expect(entry, isNotNull);
      expect(entry!.laazLatin, 'badeilier [badaillier]');
      expect(entry.meaning, 'לפהק');
      expect(entry.english, 'to yawn');
    });

    test('מפרק וריאנט שבו הלטינית מודגשת בשדה האחרון', () {
      final entry = LaazDictionaryEntry.parseLine(
        '210 / (שבת נג:) / <b>דה"מ שאכלה כרשינין</b> מיניישונ"ש שלשול / '
        '<b>meneisons [menaisons]</b> '
        '<small>ר\' מילונו של לוי (מס\' 736).</small> '
        '<span dir="ltr">✭ diarrhea</span>',
      );

      expect(entry, isNotNull);
      expect(entry!.laazHebrew, 'מיניישונ"ש');
      expect(entry.laazLatin, 'meneisons [menaisons]');
      expect(entry.meaning, 'שלשול');
    });

    test('מפרק ערך ללא שדה לטיני כשהפירוש מודגש בשדה האחרון', () {
      final entry = LaazDictionaryEntry.parseLine(
        '49א / (ברכות מג:) / <b>סמלק</b> יסמי"ן / '
        '<b>"בלשון ישמעאל".</b> <span dir="ltr">✭ jasmine</span>',
      );

      expect(entry, isNotNull);
      expect(entry!.entryNumber, '49א');
      expect(entry.laazHebrew, 'יסמי"ן');
      expect(entry.laazLatin, isEmpty);
      expect(entry.meaning, '"בלשון ישמעאל".');
      expect(entry.english, 'jasmine');
    });

    test('מפענח &amp; בשדות הערך (קיים בנתוני הספר בפועל)', () {
      final entry = LaazDictionaryEntry.parseLine(
        '1456 / (בבא קמא קיט.) / <b>מוכין</b> גרטויש"א / geatuise / '
        '<b>פסול הצמר</b> <small>יש לתקן ולקרוא a&amp;b bis 562.</small>',
      );

      expect(entry, isNotNull);
      expect(entry!.note, 'יש לתקן ולקרוא a&b bis 562.');
    });

    test('עמיד ל-&nbsp; סביב המפריד ובתוך שדות', () {
      final entry = LaazDictionaryEntry.parseLine(
        '7 / (ברכות ט:) /&nbsp;<b>כרתי</b> פוריל"ש / porels / '
        '<b>כרשים&nbsp;(ירק מאכל)</b>',
      );

      expect(entry, isNotNull);
      expect(entry!.lemma, 'כרתי');
      expect(entry.meaning, 'כרשים (ירק מאכל)');
    });

    test('מדלג על שורות כותרת ושורות ללא מפריד', () {
      final entries = LaazDictionaryEntry.parseLines(const <String>[
        '<h1>אוצר לעזי רש"י</h1>',
        '<h2>תלמוד</h2>',
        '<h3>ברכות</h3>',
        'משה קטן',
        '7 / (ברכות ט:) / <b>כרתי</b> פוריל"ש / porels / <b>כרשים</b>',
      ]);

      expect(entries, hasLength(1));
      expect(entries.single.lemma, 'כרתי');
    });
  });

  group('findLaazMatches', () {
    late DictionaryLookupRepository repository;

    DictionaryLookupRepository buildRepository(
      Future<List<LaazDictionaryEntry>> Function() loadLaazEntries,
    ) {
      return DictionaryLookupRepository(
        loadAcronyms: () async => <String, List<String>>{},
        loadAramaicEntries: () async => const <AramaicDictionaryEntry>[],
        loadLaazEntries: loadLaazEntries,
      );
    }

    setUp(() {
      repository = buildRepository(
        () async => LaazDictionaryEntry.parseLines(const <String>[
          '7 / (ברכות ט:) / <b>כרתי</b> פוריל"ש / porels / <b>כרשים (ירק מאכל)</b>',
          '3001 / (בראשית א,ב) / <b>תהו</b> אישטורדישו"ן / estordison / <b>עילפון</b>',
        ]),
      );
    });

    test('מוצא לעז לפי התעתיק העברי גם עם גרשיים עבריים וניקוד', () async {
      await repository.ensureLaazLoaded();

      expect(repository.findLaazMatches('פוריל"ש'), hasLength(1));
      expect(repository.findLaazMatches('פוריל״ש'), hasLength(1));
      expect(repository.findLaazMatches('פּוֹרִילְש'), hasLength(1));
      expect(
        repository.findLaazMatches('פוריל"ש').single.laazLatin,
        'porels',
      );
    });

    test('מילת הערך מרש"י אינה מפעילה התאמה - רק תעתיק', () async {
      await repository.ensureLaazLoaded();

      expect(repository.findLaazMatches('תָּהוּ'), isEmpty);
      expect(repository.findLaazMatches('כרתי'), isEmpty);
    });

    test('מחזיר ריק כשאין התאמה מדויקת', () async {
      await repository.ensureLaazLoaded();

      expect(repository.findLaazMatches('שלום'), isEmpty);
    });

    test('מוצא תעתיק בחילופי כתיב בין דפוסים (שבו"ן/שוו"ן/שיו"ן)', () async {
      // הערכים האמיתיים מהספר: שבו"ן (savon, מס' 1434) ושו"ן (son, מס' 1725).
      repository = buildRepository(
        () async => LaazDictionaryEntry.parseLines(const <String>[
          '1434 / (בבא קמא צג:) / <b>צפון</b> שבו"ן / savon / <b>סבון</b> '
              '<span dir="ltr">✭ soap</span>',
          '1725 / (סנהדרין צד:) / <b>משק</b> שו"ן / son / <b>צליל, רעש</b> '
              '<span dir="ltr">✭ sound, noise</span>',
        ]),
      );
      await repository.ensureLaazLoaded();

      // ברש"י על ב"ק צג: מודפס "שיו"ן" ועל ב"ק קא. "שוו"ן" - אותו לעז.
      expect(repository.findLaazMatches('שבו"ן').single.laazLatin, 'savon');
      expect(repository.findLaazMatches('שוו"ן').single.laazLatin, 'savon');
      expect(repository.findLaazMatches('שיו"ן').single.laazLatin, 'savon');
      expect(repository.findLaazMatches('שו"ן').single.laazLatin, 'son');
    });

    test('ספר חסר ב-DB — טעינה ריקה בלי שגיאות והתאמות ריקות', () async {
      repository = buildRepository(() async => const <LaazDictionaryEntry>[]);

      await repository.ensureLaazLoaded();

      expect(repository.areLaazLoaded, isTrue);
      expect(repository.findLaazMatches('כרתי'), isEmpty);
    });
  });

  group('isLikelyLaazTranslit', () {
    final repository = DictionaryLookupRepository(
      loadAcronyms: () async => <String, List<String>>{},
      loadAramaicEntries: () async => const <AramaicDictionaryEntry>[],
      loadLaazEntries: () async => const <LaazDictionaryEntry>[],
    );

    test('מזהה גרשיים בתוך המילה, כולל גרשיים עבריים וניקוד', () {
      expect(repository.isLikelyLaazTranslit('פוריל"ש'), isTrue);
      expect(repository.isLikelyLaazTranslit('פוריל״ש'), isTrue);
      expect(repository.isLikelyLaazTranslit('פּוֹרִיל"ש'), isTrue);
      expect(repository.isLikelyLaazTranslit('שיו"ן'), isTrue);
    });

    test('דוחה מילים רגילות וגרשיים שאינם בתוך המילה', () {
      expect(repository.isLikelyLaazTranslit('צפון'), isFalse);
      expect(repository.isLikelyLaazTranslit('"צפון"'), isFalse);
      expect(repository.isLikelyLaazTranslit('כרתי'), isFalse);
      expect(repository.isLikelyLaazTranslit(''), isFalse);
    });
  });

  group('findLaazMatchGroups', () {
    DictionaryLookupRepository buildRepository(List<String> lines) {
      return DictionaryLookupRepository(
        loadAcronyms: () async => <String, List<String>>{},
        loadAramaicEntries: () async => const <AramaicDictionaryEntry>[],
        loadLaazEntries: () async => LaazDictionaryEntry.parseLines(lines),
      );
    }

    test('מאחד ערכים זהים בתעתיק ובפירוש ממקורות רש"י שונים', () async {
      final repository = buildRepository(const <String>[
        '1432 / (בבא קמא צג:) / <b>נמטי</b> פילטרי"ש / feltres / <b>לבדים (מצעים של לֶבֶד)</b>',
        '1466 / (בבא קמא קיט:) / <b>נמטי</b> פילטרי"ש / feltres / <b>לבדים (מצעים של לֶבֶד)</b>',
        '1550 / (בבא מציעא פד:) / <b>נמטי</b> פילטרי"ש / feltres / <b>לבדים (מצעים של לֶבֶד)</b>',
        '2311 / (בכורות כט:) / <b>נמטי</b> פילטרי"ש / feltres / <b>לבדים (מצעים של לֶבֶד)</b>',
      ]);
      await repository.ensureLaazLoaded();

      final groups = repository.findLaazMatchGroups('פילטרי"ש');

      expect(groups, hasLength(1));
      expect(groups.single, hasLength(4));
      expect(
        groups.single.map((e) => e.sourceReference),
        containsAll(<String>['בבא קמא צג:', 'בכורות כט:']),
      );
    });

    test('תעתיק זהה עם פירושים שונים נשאר בקבוצות נפרדות', () async {
      final repository = buildRepository(const <String>[
        '1 / (ברכות ט:) / <b>כרתי</b> פוריל"ש / porels / <b>כרשים</b>',
        '2 / (שבת י.) / <b>כרתי</b> פוריל"ש / porels / <b>ירק אחר</b>',
      ]);
      await repository.ensureLaazLoaded();

      final groups = repository.findLaazMatchGroups('פוריל"ש');

      expect(groups, hasLength(2));
      expect(groups.first.single.meaning, 'כרשים');
      expect(groups.last.single.meaning, 'ירק אחר');
    });
  });

  group('ענף לעזי רש"י בתפריט ההקשר', () {
    late DictionaryLookupRepository repository;

    setUp(() {
      repository = DictionaryLookupRepository(
        loadAcronyms: () async => <String, List<String>>{},
        loadAramaicEntries: () async => const <AramaicDictionaryEntry>[],
        loadLaazEntries: () async => LaazDictionaryEntry.parseLines(
          const <String>[
            '7 / (ברכות ט:) / <b>כרתי</b> פוריל"ש / porels / <b>כרשים (ירק מאכל)</b>',
          ],
        ),
      );
    });

    Future<BuildContext> pumpHost(WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.shrink(),
          ),
        ),
      );
      return tester.element(find.byType(SizedBox));
    }

    testWidgets('מציג ענף לעזי רש"י כשיש התאמה ללעז', (tester) async {
      await repository.ensureLoaded();
      await repository.ensureLaazLoaded();
      final context = await pumpHost(tester);

      final entries = buildDictionaryContextMenuEntries(
        context: context,
        selectedText: 'פוריל"ש',
        repository: repository,
      );

      expect(entries, hasLength(1));
      expect(entries.single.label, contains('לעזי'));
      expect(entries.single.children, hasLength(1));
    });

    testWidgets('מילה ללא גרשיים לא מציגה ענף, גם כשהיא מילת ערך', (
      tester,
    ) async {
      await repository.ensureLoaded();
      final context = await pumpHost(tester);

      final entries = buildDictionaryContextMenuEntries(
        context: context,
        selectedText: 'כרתי',
        repository: repository,
      );

      expect(entries, isEmpty);
    });

    testWidgets('תעתיק בכתיב דפוס שונה (שיו"ן) מוצא את ערך שבו"ן', (
      tester,
    ) async {
      repository = DictionaryLookupRepository(
        loadAcronyms: () async => <String, List<String>>{},
        loadAramaicEntries: () async => const <AramaicDictionaryEntry>[],
        loadLaazEntries: () async => LaazDictionaryEntry.parseLines(
          const <String>[
            '1434 / (בבא קמא צג:) / <b>צפון</b> שבו"ן / savon / <b>סבון</b> '
                '<span dir="ltr">✭ soap</span>',
          ],
        ),
      );
      await repository.ensureLaazLoaded();
      final context = await pumpHost(tester);

      // כך הלעז מודפס ברש"י על בבא קמא צג: "צפון - שיו"ן".
      final entries = buildDictionaryContextMenuEntries(
        context: context,
        selectedText: 'שיו"ן',
        repository: repository,
      );

      expect(entries, hasLength(1));
      expect(entries.single.label, contains('לעזי'));
      expect(entries.single.children!.single.label, contains('סבון'));
    });

    testWidgets('ערכים כפולים ממקורות שונים מוצגים כפריט תפריט אחד', (
      tester,
    ) async {
      repository = DictionaryLookupRepository(
        loadAcronyms: () async => <String, List<String>>{},
        loadAramaicEntries: () async => const <AramaicDictionaryEntry>[],
        loadLaazEntries: () async => LaazDictionaryEntry.parseLines(
          const <String>[
            '1432 / (בבא קמא צג:) / <b>נמטי</b> פילטרי"ש / feltres / <b>לבדים (מצעים של לֶבֶד)</b>',
            '1466 / (בבא קמא קיט:) / <b>נמטי</b> פילטרי"ש / feltres / <b>לבדים (מצעים של לֶבֶד)</b>',
            '1550 / (בבא מציעא פד:) / <b>נמטי</b> פילטרי"ש / feltres / <b>לבדים (מצעים של לֶבֶד)</b>',
            '2311 / (בכורות כט:) / <b>נמטי</b> פילטרי"ש / feltres / <b>לבדים (מצעים של לֶבֶד)</b>',
          ],
        ),
      );
      await repository.ensureLaazLoaded();
      final context = await pumpHost(tester);

      final entries = buildDictionaryContextMenuEntries(
        context: context,
        selectedText: 'פילטרי"ש',
        repository: repository,
      );

      expect(entries, hasLength(1));
      expect(entries.single.children, hasLength(1));
      expect(entries.single.children!.single.label, contains('פילטרי"ש'));
    });

    testWidgets('פירושים שונים לאותו תעתיק נשארים פריטים נפרדים', (
      tester,
    ) async {
      repository = DictionaryLookupRepository(
        loadAcronyms: () async => <String, List<String>>{},
        loadAramaicEntries: () async => const <AramaicDictionaryEntry>[],
        loadLaazEntries: () async => LaazDictionaryEntry.parseLines(
          const <String>[
            '1 / (ברכות ט:) / <b>כרתי</b> פוריל"ש / porels / <b>כרשים</b>',
            '2 / (שבת י.) / <b>כרתי</b> פוריל"ש / porels / <b>ירק אחר</b>',
          ],
        ),
      );
      await repository.ensureLaazLoaded();
      final context = await pumpHost(tester);

      final entries = buildDictionaryContextMenuEntries(
        context: context,
        selectedText: 'פוריל"ש',
        repository: repository,
      );

      expect(entries, hasLength(1));
      expect(entries.single.children, hasLength(2));
    });

    testWidgets('לא מציג ענף כשאין התאמה', (tester) async {
      await repository.ensureLoaded();
      await repository.ensureLaazLoaded();
      final context = await pumpHost(tester);

      final entries = buildDictionaryContextMenuEntries(
        context: context,
        selectedText: 'שלום',
        repository: repository,
      );

      expect(entries, isEmpty);
    });
  });
}
