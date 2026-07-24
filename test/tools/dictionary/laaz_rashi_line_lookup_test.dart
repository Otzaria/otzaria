import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';

/// בונה קישור-לעז מינימלי: index1 = שורת המקור בספר-הלעז, index2 = שורת רש"י.
Link _laazLink({
  required int sourceLineIndex,
  required String rashiTitle,
  required int rashiLineIndex,
  String connectionType = 'COMMENTARY',
}) {
  return Link(
    heRef: 'ref',
    index1: sourceLineIndex,
    path2: rashiTitle,
    index2: rashiLineIndex,
    connectionType: connectionType,
  );
}

LaazDictionaryEntry _entry({
  required int sourceLineIndex,
  String laazHebrew = 'פוריל"ש',
  String meaning = 'כרשים',
  String? note,
  String? english,
}) {
  return LaazDictionaryEntry(
    entryNumber: '$sourceLineIndex',
    sourceReference: 'בראשית א,א',
    lemma: 'כרתי',
    laazHebrew: laazHebrew,
    laazLatin: 'porels',
    meaning: meaning,
    note: note,
    english: english,
    sourceLineIndex: sourceLineIndex,
  );
}

void main() {
  group('parseLines source-line-index alignment', () {
    test('כותרות מדולגות לא מזיזות את sourceLineIndex של הערכים', () {
      // שתי שורות כותרת בראש + שורה ריקה => הערך הראשון יושב בשורת-מקור 4.
      final lines = <String>[
        '<h2>אות א</h2>',
        '<h3>ערכים</h3>',
        '',
        '10 / (בראשית א,א) / <b>כרתי</b> פוריל"ש / porels / <b>כרשים</b>',
        '20 / (בראשית א,ב) / <b>תהו</b> אישטו"ן / eston / <b>מבוכה</b>',
      ];

      final entries = LaazDictionaryEntry.parseLines(lines);

      expect(entries.length, 2);
      // המיקום ברשימה (0,1) שונה ממספר שורת-המקור (4,5) — זה בדיוק הסיכון.
      expect(entries[0].sourceLineIndex, 4);
      expect(entries[1].sourceLineIndex, 5);
      expect(entries[0].lemma, 'כרתי');
      expect(entries[1].lemma, 'תהו');
    });
  });

  group('laazForRashiLine', () {
    test('ערך עם שורות-כותרת לפניו מתמפה ל-index1 הנכון של הקישור', () async {
      // הערך יושב בשורת-מקור 4 (אחרי 3 שורות מדולגות); הקישור מפנה ל-index1=4.
      final entry = _entry(sourceLineIndex: 4);
      final repository = DictionaryLookupRepository(
        loadLaazEntries: () async => <LaazDictionaryEntry>[entry],
        loadLaazLinks: () async => <Link>[
          _laazLink(
            sourceLineIndex: 4,
            rashiTitle: 'רש"י על בראשית',
            rashiLineIndex: 15,
          ),
        ],
      );

      await repository.ensureLaazLinksLoaded();

      final matches = repository.laazForRashiLine(
        rashiBookTitle: 'רש"י על בראשית',
        rashiLineIndex: 15,
      );

      expect(matches, hasLength(1));
      expect(matches.single.sourceLineIndex, 4);
      expect(matches.single.laazHebrew, 'פוריל"ש');
    });

    test('רשימת ערכים מרובים על אותה שורת רש"י', () async {
      final repository = DictionaryLookupRepository(
        loadLaazEntries: () async => <LaazDictionaryEntry>[
          _entry(sourceLineIndex: 4, laazHebrew: 'פוריל"ש'),
          _entry(sourceLineIndex: 5, laazHebrew: 'אישטו"ן'),
          _entry(sourceLineIndex: 6, laazHebrew: 'בדייליי"ר'),
        ],
        loadLaazLinks: () async => <Link>[
          _laazLink(
            sourceLineIndex: 4,
            rashiTitle: 'רש"י על בראשית',
            rashiLineIndex: 15,
          ),
          _laazLink(
            sourceLineIndex: 5,
            rashiTitle: 'רש"י על בראשית',
            rashiLineIndex: 15,
          ),
          _laazLink(
            sourceLineIndex: 6,
            rashiTitle: 'רש"י על בראשית',
            rashiLineIndex: 15,
          ),
        ],
      );

      await repository.ensureLaazLinksLoaded();

      final matches = repository.laazForRashiLine(
        rashiBookTitle: 'רש"י על בראשית',
        rashiLineIndex: 15,
      );

      expect(matches.map((e) => e.laazHebrew), <String>[
        'פוריל"ש',
        'אישטו"ן',
        'בדייליי"ר',
      ]);
    });

    test('שומר ערכים עם פירוש ריק (הגנת הסלוט הראשי נעשית בתצוגה)', () async {
      final entry = _entry(
        sourceLineIndex: 4,
        meaning: '',
        note: 'הערת עורך',
      );
      final repository = DictionaryLookupRepository(
        loadLaazEntries: () async => <LaazDictionaryEntry>[entry],
        loadLaazLinks: () async => <Link>[
          _laazLink(
            sourceLineIndex: 4,
            rashiTitle: 'רש"י על בראשית',
            rashiLineIndex: 15,
          ),
        ],
      );

      await repository.ensureLaazLinksLoaded();

      final matches = repository.laazForRashiLine(
        rashiBookTitle: 'רש"י על בראשית',
        rashiLineIndex: 15,
      );

      expect(matches, hasLength(1));
      expect(matches.single.meaning, isEmpty);
      expect(matches.single.note, 'הערת עורך');
    });

    test('מפריד בין ספרי רש"י שונים לפי כותרת', () async {
      final repository = DictionaryLookupRepository(
        loadLaazEntries: () async => <LaazDictionaryEntry>[
          _entry(sourceLineIndex: 4, laazHebrew: 'בראשיתי'),
          _entry(sourceLineIndex: 5, laazHebrew: 'שמותי'),
        ],
        loadLaazLinks: () async => <Link>[
          _laazLink(
            sourceLineIndex: 4,
            rashiTitle: 'רש"י על בראשית',
            rashiLineIndex: 15,
          ),
          _laazLink(
            sourceLineIndex: 5,
            rashiTitle: 'רש"י על שמות',
            rashiLineIndex: 15,
          ),
        ],
      );

      await repository.ensureLaazLinksLoaded();

      expect(
        repository
            .laazForRashiLine(
              rashiBookTitle: 'רש"י על בראשית',
              rashiLineIndex: 15,
            )
            .single
            .laazHebrew,
        'בראשיתי',
      );
      expect(
        repository
            .laazForRashiLine(
              rashiBookTitle: 'רש"י על שמות',
              rashiLineIndex: 15,
            )
            .single
            .laazHebrew,
        'שמותי',
      );
    });

    test('מתעלם מקישורים שאינם תלויי-טקסט (למשל REFERENCE)', () async {
      final repository = DictionaryLookupRepository(
        loadLaazEntries: () async => <LaazDictionaryEntry>[
          _entry(sourceLineIndex: 4),
        ],
        loadLaazLinks: () async => <Link>[
          _laazLink(
            sourceLineIndex: 4,
            rashiTitle: 'רש"י על בראשית',
            rashiLineIndex: 15,
            connectionType: 'REFERENCE',
          ),
        ],
      );

      await repository.ensureLaazLinksLoaded();

      expect(
        repository.laazForRashiLine(
          rashiBookTitle: 'רש"י על בראשית',
          rashiLineIndex: 15,
        ),
        isEmpty,
      );
    });

    test('שורה ללא לעז מחזירה const [] ולא זורקת', () async {
      final repository = DictionaryLookupRepository(
        loadLaazEntries: () async => <LaazDictionaryEntry>[
          _entry(sourceLineIndex: 4),
        ],
        loadLaazLinks: () async => <Link>[
          _laazLink(
            sourceLineIndex: 4,
            rashiTitle: 'רש"י על בראשית',
            rashiLineIndex: 15,
          ),
        ],
      );

      await repository.ensureLaazLinksLoaded();

      expect(
        repository.laazForRashiLine(
          rashiBookTitle: 'רש"י על בראשית',
          rashiLineIndex: 999,
        ),
        same(const <LaazDictionaryEntry>[]),
      );
      expect(
        repository.laazForRashiLine(
          rashiBookTitle: 'ספר לא קיים',
          rashiLineIndex: 1,
        ),
        isEmpty,
      );
    });

    test('רשימת קישורים ריקה => מפה ריקה בלי חריגה', () async {
      final repository = DictionaryLookupRepository(
        loadLaazEntries: () async => <LaazDictionaryEntry>[
          _entry(sourceLineIndex: 4),
        ],
        loadLaazLinks: () async => const <Link>[],
      );

      await repository.ensureLaazLinksLoaded();

      expect(repository.areLaazLinksLoaded, isTrue);
      expect(
        repository.laazForRashiLine(
          rashiBookTitle: 'רש"י על בראשית',
          rashiLineIndex: 15,
        ),
        isEmpty,
      );
    });

    test(
      'קישור ל-index1 שאין לו ערך (שורה מדולגת) לא מתקשר לשום שורת רש"י',
      () async {
        // הקישור מפנה ל-index1=2 (שורת כותרת מדולגת), שאין לה ערך => מתעלמים.
        final repository = DictionaryLookupRepository(
          loadLaazEntries: () async => <LaazDictionaryEntry>[
            _entry(sourceLineIndex: 4),
          ],
          loadLaazLinks: () async => <Link>[
            _laazLink(
              sourceLineIndex: 2,
              rashiTitle: 'רש"י על בראשית',
              rashiLineIndex: 15,
            ),
          ],
        );

        await repository.ensureLaazLinksLoaded();

        expect(
          repository.laazForRashiLine(
            rashiBookTitle: 'רש"י על בראשית',
            rashiLineIndex: 15,
          ),
          isEmpty,
        );
      },
    );
  });
}
