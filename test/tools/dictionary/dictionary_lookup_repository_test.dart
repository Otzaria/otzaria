import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/dictionary/dictionary_context_menu_entries.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';

void main() {
  group('DictionaryLookupRepository', () {
    late DictionaryLookupRepository repository;

    setUp(() {
      repository = DictionaryLookupRepository(
        loadAcronyms: () async => <String, List<String>>{
          'רש"י': <String>['רבי שלמה יצחקי', 'רבן של ישראל'],
          "וכו'": <String>['וכולי, וכן הלאה'],
        },
        loadAramaicEntries: () async => const <AramaicDictionaryEntry>[
          AramaicDictionaryEntry(aramaic: 'אבא', hebrew: 'יער'),
          AramaicDictionaryEntry(aramaic: 'בר אבא', hebrew: 'בן היער'),
          AramaicDictionaryEntry(aramaic: 'אבוה', hebrew: 'אביו'),
        ],
        loadLaazEntries: () async => const <LaazDictionaryEntry>[],
      );
    });

    test('מוצא ראשי תיבות גם עם גרשיים עבריים', () async {
      await repository.ensureLoaded();

      final entry = repository.findAcronym('רש״י');

      expect(entry, isNotNull);
      expect(entry!.meanings, contains('רבי שלמה יצחקי'));
      expect(entry.meanings, contains('רבן של ישראל'));
    });

    test('מוצא קיצורים עם גרש בודד', () async {
      await repository.ensureLoaded();

      final entry = repository.findAcronym("וכו'");

      expect(entry, isNotNull);
      expect(entry!.meanings, contains('וכולי, וכן הלאה'));
    });

    test('מחזיר הרחבות לראשי תיבות חלקיים עם גרש בודד', () async {
      repository = DictionaryLookupRepository(
        loadAcronyms: () async => <String, List<String>>{
          'ועי"ל': <String>['ועיין לעיל'],
          'ועי"ש': <String>['ועיין שם'],
        },
        loadAramaicEntries: () async => const <AramaicDictionaryEntry>[
          AramaicDictionaryEntry(aramaic: 'אבא', hebrew: 'יער'),
        ],
      );
      await repository.ensureAcronymsLoaded();

      final matches = repository.findAcronymMatches("ועי'");

      expect(matches.map((entry) => entry.acronym), <String>[
        'ועי"ל',
        'ועי"ש',
      ]);
    });

    test('שאילתת חיפוש מנורמלת מזהה גרש מול גרשיים', () async {
      await repository.ensureAcronymsLoaded();

      final matches = repository.acronymMatchesQuery(
        acronym: 'וכ"ו',
        query: "וכו'",
      );

      expect(matches, isTrue);
    });

    test('מחזיר צירופים ארמיים רק אם המילה קיימת כמונח במילון', () async {
      await repository.ensureLoaded();

      final matches = repository.findAramaicMatches('אבא');

      expect(matches.map((entry) => entry.aramaic), <String>[
        'אבא',
        'בר אבא',
      ]);
    });

    test('לא מחזיר צירופים אם המילה לא קיימת במילון כמונח עצמאי', () async {
      await repository.ensureLoaded();

      final matches = repository.findAramaicMatches('אביו');

      expect(matches, isEmpty);
    });
  });

  group('AramaicDictionaryEntryPresentation', () {
    test('מפרק פירושים מרובים לצורות תצוגה נפרדות', () {
      final presentation = AramaicDictionaryEntryPresentation.parse(
        '{אַהֲנֵי} הועיל *** {אַהָנֵי} (=א הני) על אלה',
      );

      expect(presentation.meanings, hasLength(2));
      expect(presentation.meanings.first.expression, 'אַהֲנֵי');
      expect(presentation.meanings.first.mainText, 'הועיל');
      expect(presentation.meanings.first.expansion, isNull);
      expect(presentation.meanings.last.expression, 'אַהָנֵי');
      expect(presentation.meanings.last.mainText, 'על אלה');
      expect(presentation.meanings.last.expansion, 'א הני');
    });

    test('מפרק גם הסבר שמופיע בתחילת הפירוש בלי ציטוט', () {
      final presentation = AramaicDictionaryEntryPresentation.parse(
        '(=אם תימצי לומר) אם תשיב לשאלה הקודמת באופן זה',
      );

      expect(presentation.meanings, hasLength(1));
      expect(presentation.meanings.single.expression, isNull);
      expect(
        presentation.meanings.single.mainText,
        'אם תשיב לשאלה הקודמת באופן זה',
      );
      expect(presentation.meanings.single.expansion, 'אם תימצי לומר');
    });
  });

  group('buildDictionaryContextMenuEntries', () {
    late DictionaryLookupRepository repository;

    setUp(() {
      repository = DictionaryLookupRepository(
        loadAcronyms: () async => <String, List<String>>{
          'רש"י': <String>['רבי שלמה יצחקי'],
        },
        loadAramaicEntries: () async => const <AramaicDictionaryEntry>[
          AramaicDictionaryEntry(
            aramaic: 'אבא',
            hebrew: '{אַבָּא} אב *** {אֲבָא} רוצה',
          ),
        ],
        loadLaazEntries: () async => const <LaazDictionaryEntry>[],
      );
    });

    testWidgets('בונה תפריט משנה לראשי תיבות', (tester) async {
      await repository.ensureLoaded();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.shrink(),
          ),
        ),
      );

      final context = tester.element(find.byType(SizedBox));
      final entries = buildDictionaryContextMenuEntries(
        context: context,
        selectedText: 'רש״י',
        repository: repository,
      );

      expect(entries, hasLength(1));
    });

    testWidgets('בונה תפריט משנה למילה ארמית רגילה', (tester) async {
      await repository.ensureLoaded();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.shrink(),
          ),
        ),
      );

      final context = tester.element(find.byType(SizedBox));
      final entries = buildDictionaryContextMenuEntries(
        context: context,
        selectedText: 'אבא',
        repository: repository,
      );

      expect(entries, hasLength(1));
    });

    testWidgets('נופל חזרה לחיפוש ארמי כשאין התאמת ראשי תיבות', (tester) async {
      await repository.ensureLoaded();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.shrink(),
          ),
        ),
      );

      final context = tester.element(find.byType(SizedBox));
      final entries = buildDictionaryContextMenuEntries(
        context: context,
        selectedText: '"אבא"',
        repository: repository,
      );

      expect(entries, hasLength(1));
    });

    testWidgets('מציג חיפוש ארמי גם כשמילון ראשי התיבות לא נטען', (
      tester,
    ) async {
      await repository.ensureAramaicLoaded();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.shrink(),
          ),
        ),
      );

      final context = tester.element(find.byType(SizedBox));
      final entries = buildDictionaryContextMenuEntries(
        context: context,
        selectedText: 'אבא',
        repository: repository,
      );

      expect(entries, hasLength(1));
    });

    testWidgets('מציג ראשי תיבות גם כשמילון ארמי לא נטען', (tester) async {
      repository = DictionaryLookupRepository(
        loadAcronyms: () async => <String, List<String>>{
          'וכ"ו': <String>['וכו'],
        },
        loadAramaicEntries: () async => const <AramaicDictionaryEntry>[
          AramaicDictionaryEntry(aramaic: 'אבא', hebrew: 'יער'),
        ],
        loadLaazEntries: () async => const <LaazDictionaryEntry>[],
      );
      await repository.ensureAcronymsLoaded();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.shrink(),
          ),
        ),
      );

      final context = tester.element(find.byType(SizedBox));
      final entries = buildDictionaryContextMenuEntries(
        context: context,
        selectedText: "וכו'",
        repository: repository,
      );

      expect(entries, hasLength(1));
    });
  });
}
