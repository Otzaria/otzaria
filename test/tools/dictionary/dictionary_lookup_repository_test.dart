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

    test('מזהה ראשי תיבות עם גרשיים טיפוגרפיים', () {
      expect(repository.isLikelyAcronym('רש”י'), isTrue);
      expect(repository.isLikelyAcronym('רש“י'), isTrue);
      expect(repository.isLikelyAcronym('וכו’'), isTrue);
      expect(repository.isLikelyAcronym('וכו‘'), isTrue);
      expect(repository.isLikelyAcronym('רשי'), isFalse);
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

  group('getAcronymSearchCatalog (issue: חיפוש ראשי תיבות איטי)', () {
    // מילון סינתטי בסדר גודל של המילון האמיתי (כ-13,000 ערכים), כדי שהבדל
    // הביצועים בין נירמול-פעם-אחת לנירמול-לכל-רשומה יהיה מדיד ולא רועש.
    // אותיות עבריות בלבד, בלי ספרות: _trimDecorations גוזם ספרות וסימנים
    // זרים מקצה המחרוזת, וכל סיומת מספרית הייתה מתכווצת לאותו מפתח מנורמל
    // יחיד — בדיוק המלכודת שתפסה את הבדיקה הראשונה בטיוטה הזאת.
    const hebrewLetters = 'אבגדהוזחטיכלמנסעפצקרשת'; // 22 אותיות, בלי סופיות
    const letterBase = hebrewLetters.length;
    String uniqueAcronymBody(int i) {
      final c1 = hebrewLetters[(i ~/ (letterBase * letterBase)) % letterBase];
      final c2 = hebrewLetters[(i ~/ letterBase) % letterBase];
      final c3 = hebrewLetters[i % letterBase];
      return '$c1$c2$c3';
    }

    /// בונה את ראשי-התיבות המלאים (עם הגרשיים) לאינדקס נתון — אותה נוסחה
    /// בדיוק כמו [buildLargeAcronymMap], כדי שבדיקות יוכלו לבנות שאילתות
    /// אמיתיות (ולא מנחשות) מתוך אותה טבלה.
    String acronymFor(int i) {
      final body = uniqueAcronymBody(i);
      // גרשיים כפולים/בודדים מערבבים צורות שדורשות נירמול אמיתי, לא רק
      // השוואת מחרוזות — אחרת הבדיקה הייתה יכולה לעבור גם בלי התיקון.
      final mark = i.isEven ? '"' : "'";
      return '${body.substring(0, body.length - 1)}$mark${body.substring(body.length - 1)}';
    }

    Map<String, List<String>> buildLargeAcronymMap(int count) {
      final map = <String, List<String>>{};
      for (var i = 0; i < count; i++) {
        map[acronymFor(i)] = <String>['פירוש מספר $i', 'עוד פירוש ל-$i'];
      }
      return map;
    }

    /// מסלול החיפוש הישן: מנרמל כל מפתח בקטלוג מחדש בכל קריאה ל-
    /// acronymMatchesQuery — כפי שהמסך עשה לפני התיקון.
    List<String> searchLegacy(
      DictionaryLookupRepository repo,
      Map<String, List<String>> dictionaryData,
      String query,
    ) {
      return dictionaryData.entries
          .where(
            (entry) =>
                entry.key.contains(query) ||
                repo.acronymMatchesQuery(acronym: entry.key, query: query) ||
                entry.value.any((meaning) => meaning.contains(query)),
          )
          .map((entry) => entry.key)
          .toList();
    }

    /// מסלול החיפוש החדש: המפתח המנורמל כבר מחושב בקטלוג, והשאילתה מנורמלת
    /// פעם אחת בלבד.
    List<String> searchCatalog(
      DictionaryLookupRepository repo,
      List<AcronymCatalogEntry> catalog,
      String query,
    ) {
      final normalizedQuery = repo.normalizeAcronymQuery(query);
      return catalog
          .where(
            (entry) =>
                entry.displayAcronym.contains(query) ||
                (normalizedQuery.isNotEmpty &&
                    entry.normalizedKey.contains(normalizedQuery)) ||
                entry.meanings.any((meaning) => meaning.contains(query)),
          )
          .map((entry) => entry.displayAcronym)
          .toList();
    }

    test('המפתח המנורמל בקטלוג זהה לנירמול שהמסלול הישן היה מחשב', () async {
      final dictionaryData = buildLargeAcronymMap(50);
      final repo = DictionaryLookupRepository(
        loadAcronyms: () async => dictionaryData,
        loadAramaicEntries: () async => const [],
        loadLaazEntries: () async => const [],
      );
      await repo.ensureAcronymsLoaded();

      final catalog = repo.getAcronymSearchCatalog();
      expect(catalog, isNotEmpty);
      for (final entry in catalog) {
        expect(
          entry.normalizedKey,
          repo.normalizeAcronymQuery(entry.displayAcronym),
        );
      }
    });

    test(
      'מחזיר בדיוק את אותן תוצאות כמו המסלול הישן, על אותו מילון',
      () async {
        final dictionaryData = buildLargeAcronymMap(500);
        final repo = DictionaryLookupRepository(
          loadAcronyms: () async => dictionaryData,
          loadAramaicEntries: () async => const [],
          loadLaazEntries: () async => const [],
        );
        await repo.ensureAcronymsLoaded();
        final catalog = repo.getAcronymSearchCatalog();

        final queries = <String>[
          hebrewLetters[0], // אות בודדת — תתאים לחלק ניכר מהקטלוג
          acronymFor(7), // התאמה מדויקת, כולל הגרש/גרשיים
          acronymFor(321).substring(0, 2), // התאמה חלקית מהתחלה
        ];
        for (final query in queries) {
          final legacy = searchLegacy(repo, dictionaryData, query)..sort();
          final updated = searchCatalog(repo, catalog, query)..sort();
          expect(
            updated,
            legacy,
            reason: 'השאילתה "$query" הניבה תוצאות שונות מהמסלול הישן',
          );
        }
      },
    );

    test(
      'מסלול הקטלוג מהיר משמעותית מהמסלול הישן על מילון בגודל אמיתי',
      () async {
        // 22^3 = 10,648 מפתחות בני 3 אותיות בלבד אפשריים עם ה-builder הנוכחי;
        // 9,000 נשאר קרוב בגודלו למילון האמיתי (12,832 אחרי מיזוג התנגשויות)
        // בלי להתנגש בתקרה.
        final dictionaryData = buildLargeAcronymMap(9000);
        final repo = DictionaryLookupRepository(
          loadAcronyms: () async => dictionaryData,
          loadAramaicEntries: () async => const [],
          loadLaazEntries: () async => const [],
        );
        await repo.ensureAcronymsLoaded();
        final catalog = repo.getAcronymSearchCatalog();

        final queries = <String>[
          hebrewLetters[0],
          acronymFor(7),
          acronymFor(321).substring(0, 2),
          hebrewLetters[10],
        ];

        final legacyStopwatch = Stopwatch()..start();
        for (final query in queries) {
          searchLegacy(repo, dictionaryData, query);
        }
        legacyStopwatch.stop();

        final catalogStopwatch = Stopwatch()..start();
        for (final query in queries) {
          searchCatalog(repo, catalog, query);
        }
        catalogStopwatch.stop();

        // סף פי 3 משאיר מרווח לתנודות זמן במכונות CI איטיות.
        expect(
          legacyStopwatch.elapsedMicroseconds,
          greaterThan(catalogStopwatch.elapsedMicroseconds * 3),
          reason:
              'מסלול הקטלוג (${catalogStopwatch.elapsedMicroseconds}µs) '
              'אמור להיות מהיר בהרבה מהמסלול הישן '
              '(${legacyStopwatch.elapsedMicroseconds}µs)',
        );
      },
    );
  });

  group('מיזוג פירושים', () {
    test('mergeAramaicMeanings משמיט חלק זהה (גם עם ניקוד) ושומר סדר', () {
      expect(
        DictionaryLookupRepository.mergeAramaicMeanings([
          'אביך',
          'אָבִיךָ *** אב',
          'אב',
        ]),
        'אביך *** אב',
      );
    });

    test('mergeAramaicMatches ממזג מפתחות זהים בסדר ההופעה', () {
      final merged = DictionaryLookupRepository.mergeAramaicMatches(const [
        AramaicDictionaryEntry(aramaic: 'אַבָּא', hebrew: 'אב'),
        AramaicDictionaryEntry(aramaic: 'גברא', hebrew: 'איש'),
        AramaicDictionaryEntry(
          aramaic: 'אבא',
          hebrew: 'פרי',
          dictionary: 'אחר',
        ),
      ]);

      expect(merged.map((e) => e.aramaic), ['אַבָּא', 'גברא']);
      expect(merged.first.hebrew, 'אב *** פרי');
      expect(merged.first.dictionary, AramaicDictionaryEntry.peshitaDictionary);
    });

    test('withoutRepeatedMeanings מדלג על פירוש שכבר הופיע', () {
      final presentation = AramaicDictionaryEntryPresentation.parse(
        'ארץ, קרקע *** קרקע *** ארץ (= הסבר) *** אדמה',
      ).withoutRepeatedMeanings();

      expect(presentation.meanings.map((m) => m.mainText), [
        'ארץ, קרקע',
        'ארץ',
        'אדמה',
      ]);
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

    testWidgets('התפריט מציג ערך אחד לכל מפתח, מכל המילונים', (tester) async {
      final repo = DictionaryLookupRepository(
        loadAramaicEntries: () async => const <AramaicDictionaryEntry>[
          AramaicDictionaryEntry(aramaic: 'ארעא', hebrew: 'ארץ'),
          AramaicDictionaryEntry(
            aramaic: 'ארעא',
            hebrew: '{אַרְעָא} אֲדָמָה',
            dictionary: 'מפירוש אונקלוס על התורה',
          ),
          AramaicDictionaryEntry(
            aramaic: 'גברא',
            hebrew: 'איש',
            dictionary: 'מילון שיח ישראל',
          ),
        ],
      );
      await repo.ensureAramaicLoaded();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      final context = tester.element(find.byType(SizedBox));

      final merged = buildDictionaryContextMenuEntries(
        context: context,
        selectedText: 'ארעא',
        repository: repo,
      );
      final other = buildDictionaryContextMenuEntries(
        context: context,
        selectedText: 'גברא',
        repository: repo,
      );

      // ערך אחד לכל מפתח; אחריו מפריד ופעולת "פתח במילון".
      expect(merged.single.children!, hasLength(3));
      expect(merged.single.children!.first.label, contains('ארץ'));
      expect(merged.single.children!.first.label, contains('אֲדָמָה'));
      expect(other.single.children!.first.label, contains('איש'));
    });

    testWidgets(
      'התפריט: התאמה מדויקת, מפריד, צירופים קצרים קודם ופעולת פתיחה בכלי',
      (tester) async {
        final repo = DictionaryLookupRepository(
          loadAramaicEntries: () async => const <AramaicDictionaryEntry>[
            AramaicDictionaryEntry(aramaic: 'א ב ג ליה', hebrew: 'ארוך'),
            AramaicDictionaryEntry(aramaic: 'בעי ליה', hebrew: 'צריך לו'),
            AramaicDictionaryEntry(aramaic: 'ליה', hebrew: 'לו'),
          ],
        );
        await repo.ensureAramaicLoaded();
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
        );
        final context = tester.element(find.byType(SizedBox));
        final opened = <String>[];

        final entries = buildDictionaryContextMenuEntries(
          context: context,
          selectedText: ' ליה ',
          repository: repo,
          openInDictionaryTool: (_, text) => opened.add(text),
        );
        final children = entries.single.children!;

        expect(children.map((e) => e.isDivider), [
          false, // ליה
          true,
          false, // בעי ליה
          false, // א ב ג ליה
          true,
          false, // פתח במילון
        ]);
        expect(children[0].label, startsWith('ליה - '));
        expect(children[2].label, startsWith('בעי ליה - '));
        expect(children[3].label, startsWith('א ב ג ליה - '));
        expect(children.last.label, 'פתח במילון הארמי-עברי');

        children.last.onTap!();
        expect(opened, ['ליה']);
      },
    );

    testWidgets('התפריט: בלי התאמה מדויקת אין מפריד ראשון, ועם חיתוך מוצג המספר', (
      tester,
    ) async {
      final repo = DictionaryLookupRepository(
        loadAramaicEntries: () async => [
          for (var i = 0; i < 12; i++)
            AramaicDictionaryEntry(aramaic: 'מילה$i ליה', hebrew: 'פירוש $i'),
        ],
      );
      await repo.ensureAramaicLoaded();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      final context = tester.element(find.byType(SizedBox));

      final children = buildDictionaryContextMenuEntries(
        context: context,
        selectedText: 'ליה',
        repository: repo,
      ).single.children!;

      // 8 צירופים (התקרה), מפריד, ופעולת פתיחה שמציינת את 4 החתוכים.
      expect(children, hasLength(10));
      expect(children.first.isDivider, isFalse);
      expect(children[8].isDivider, isTrue);
      expect(children.last.label, 'פתח במילון (עוד 4 צירופים)');
    });

    testWidgets('התפריט: טקסט מסומן שאינו מפתח מציג צירופים שלמים שבתוכו', (
      tester,
    ) async {
      final repo = DictionaryLookupRepository(
        loadAramaicEntries: () async => const <AramaicDictionaryEntry>[
          AramaicDictionaryEntry(aramaic: 'אמר ליה', hebrew: 'אמר לו'),
          AramaicDictionaryEntry(aramaic: 'ליה רב', hebrew: 'לו רב'),
        ],
      );
      await repo.ensureAramaicLoaded();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      final context = tester.element(find.byType(SizedBox));
      final opened = <String>[];

      final children = buildDictionaryContextMenuEntries(
        context: context,
        selectedText: 'אמר ליה רב',
        repository: repo,
        openInDictionaryTool: (_, text) => opened.add(text),
      ).single.children!;

      expect(children.map((e) => e.isDivider), [false, false, true, false]);
      expect(children[0].label, startsWith('אמר ליה - '));
      expect(children[1].label, startsWith('ליה רב - '));
      children.last.onTap!();
      expect(opened, ['אמר ליה']); // הצירוף הראשון, לא כל הטקסט שמסומן
    });

    testWidgets('התפריט: כשהטקסט כולו מפתח, מעדיפים אותו ולא את הצירופים שבתוכו', (
      tester,
    ) async {
      final repo = DictionaryLookupRepository(
        loadAramaicEntries: () async => const <AramaicDictionaryEntry>[
          AramaicDictionaryEntry(aramaic: 'אמר ליה', hebrew: 'אמר לו'),
          AramaicDictionaryEntry(aramaic: 'אמר ליה רב', hebrew: 'אמר לו רב'),
        ],
      );
      await repo.ensureAramaicLoaded();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      final context = tester.element(find.byType(SizedBox));

      final children = buildDictionaryContextMenuEntries(
        context: context,
        selectedText: 'אמר ליה רב',
        repository: repo,
      ).single.children!;

      expect(children, hasLength(3)); // המפתח, מפריד, פתיחה
      expect(children.first.label, startsWith('אמר ליה רב - '));
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

  group('findAramaicMatches (maxContainingMatches)', () {
    late DictionaryLookupRepository repo;

    setUp(() async {
      repo = DictionaryLookupRepository(
        loadAramaicEntries: () async => <AramaicDictionaryEntry>[
          const AramaicDictionaryEntry(aramaic: 'ליה', hebrew: 'לו'),
          // ארבע מילים — הארוך ביותר, לא ייבחר כשהתקרה נמוכה.
          const AramaicDictionaryEntry(aramaic: 'א ב ג ליה', hebrew: 'ארוך'),
          const AramaicDictionaryEntry(aramaic: 'בעי ליה', hebrew: 'צריך לו'),
          const AramaicDictionaryEntry(aramaic: 'גמר ליה', hebrew: 'למד לו'),
          const AramaicDictionaryEntry(aramaic: 'דבר ליה', hebrew: 'אמר לו'),
        ],
      );
      await repo.ensureAramaicLoaded();
    });

    test('ללא תקרה מחזיר את כל הצירופים (התנהגות קודמת)', () {
      expect(repo.findAramaicMatches('ליה'), hasLength(5));
    });

    test('התאמה מדויקת תמיד נשארת, והצירופים מוגבלים לקצרים ביותר', () {
      final matches = repo.findAramaicMatches(
        'ליה',
        maxContainingMatches: 2,
      );

      expect(matches.map((e) => e.aramaic), <String>[
        'ליה',
        'בעי ליה',
        'גמר ליה',
      ]);
    });

    test('תקרה גבוהה מהמספר הקיים אינה משנה את התוצאה', () {
      expect(
        repo.findAramaicMatches('ליה', maxContainingMatches: 10),
        hasLength(5),
      );
    });

    test('תקרת אפס משאירה רק התאמה מדויקת', () {
      expect(
        repo
            .findAramaicMatches('ליה', maxContainingMatches: 0)
            .map((e) => e.aramaic),
        <String>['ליה'],
      );
    });
  });

  group('findAramaicMatchGroups', () {
    late DictionaryLookupRepository repo;

    setUp(() async {
      repo = DictionaryLookupRepository(
        loadAramaicEntries: () async => <AramaicDictionaryEntry>[
          const AramaicDictionaryEntry(aramaic: 'ליה', hebrew: 'לו'),
          const AramaicDictionaryEntry(aramaic: 'א ב ג ליה', hebrew: 'ארוך'),
          const AramaicDictionaryEntry(aramaic: 'בעי ליה', hebrew: 'צריך לו'),
          const AramaicDictionaryEntry(aramaic: 'גמר ליה', hebrew: 'למד לו'),
          const AramaicDictionaryEntry(aramaic: 'דבר ליה', hebrew: 'אמר לו'),
        ],
      );
      await repo.ensureAramaicLoaded();
    });

    List<String> keys(List<AramaicDictionaryEntry> entries) => [
      for (final e in entries) e.aramaic,
    ];

    test('מפריד התאמה מדויקת מצירופים; בלי תקרה הצירופים בסדר המילון', () {
      final groups = repo.findAramaicMatchGroups('ליה');

      expect(keys(groups.exact), ['ליה']);
      expect(keys(groups.containing), [
        'א ב ג ליה',
        'בעי ליה',
        'גמר ליה',
        'דבר ליה',
      ]);
      expect(groups.hiddenContainingKeys, 0);
    });

    test('עם תקרה הצירופים לפי רלוונטיות (הקצרים קודם), וסופרים את החתוכים', () {
      final roomy = repo.findAramaicMatchGroups(
        'ליה',
        maxContainingMatches: 10,
      );
      expect(keys(roomy.containing), [
        'בעי ליה',
        'גמר ליה',
        'דבר ליה',
        'א ב ג ליה',
      ]);
      expect(roomy.hiddenContainingKeys, 0);

      final cut = repo.findAramaicMatchGroups('ליה', maxContainingMatches: 2);
      expect(keys(cut.containing), ['בעי ליה', 'גמר ליה']);
      expect(cut.hiddenContainingKeys, 2);

      final none = repo.findAramaicMatchGroups('ליה', maxContainingMatches: 0);
      expect(none.containing, isEmpty);
      expect(none.hiddenContainingKeys, 4);
      expect(keys(none.exact), ['ליה']);
    });

    test('מילה שאינה במילון מחזירה קבוצות ריקות', () {
      final groups = repo.findAramaicMatchGroups('זזזזזז');

      expect(groups.exact, isEmpty);
      expect(groups.containing, isEmpty);
      expect(groups.hiddenContainingKeys, 0);
    });

    test('findAramaicMatches הוא החיבור של הקבוצות', () {
      for (final cap in <int?>[null, 0, 2, 10]) {
        final groups = repo.findAramaicMatchGroups(
          'ליה',
          maxContainingMatches: cap,
        );
        expect(
          keys(repo.findAramaicMatches('ליה', maxContainingMatches: cap)),
          [...keys(groups.exact), ...keys(groups.containing)],
          reason: 'תקרה: $cap',
        );
      }
    });
  });

  group('findAramaicPhrasesWithin', () {
    const other = 'מילון שיח ישראל';
    late DictionaryLookupRepository repo;

    setUp(() async {
      repo = DictionaryLookupRepository(
        loadAramaicEntries: () async => const <AramaicDictionaryEntry>[
          AramaicDictionaryEntry(aramaic: 'אמר ליה', hebrew: 'אמר לו'),
          AramaicDictionaryEntry(aramaic: 'ליה רב', hebrew: 'לו רב'),
          AramaicDictionaryEntry(aramaic: 'אמר ליה רב', hebrew: 'אמר לו רב'),
          AramaicDictionaryEntry(
            aramaic: 'רב אשי',
            hebrew: 'אשי',
            dictionary: other,
          ),
          AramaicDictionaryEntry(aramaic: 'אמר ליה רב אשי הכל', hebrew: 'ארוך'),
        ],
      );
      await repo.ensureAramaicLoaded();
    });

    List<String> keys(List<AramaicDictionaryEntry> entries) => [
      for (final e in entries) e.aramaic,
    ];

    test('צירופים שלמים בתוך הטקסט, הארוך קודם ובשוויון לפי מיקום', () {
      expect(
        keys(
          repo.findAramaicPhrasesWithin(
            'אמר ליה רב אשי',
            dictionaries: {...repo.aramaicDictionaryNames},
          ),
        ),
        ['אמר ליה רב', 'אמר ליה', 'ליה רב', 'רב אשי'],
      );
    });

    test('הטקסט כולו אינו נכלל, גם כשהוא עצמו מפתח', () {
      expect(keys(repo.findAramaicPhrasesWithin('אמר ליה רב')), [
        'אמר ליה',
        'ליה רב',
      ]);
    });

    test('מילון שאינו נבחר אינו נכלל, וניקוד ופיסוק אינם מפריעים', () {
      expect(keys(repo.findAramaicPhrasesWithin('אמר ליה רב אשי')), [
        'אמר ליה רב',
        'אמר ליה',
        'ליה רב',
      ]);
      expect(keys(repo.findAramaicPhrasesWithin('אָמַר לֵיהּ רַב,')), [
        'אמר ליה',
        'ליה רב',
      ]);
    });

    test('תקרת צירופים נחתכת לפי הסדר', () {
      expect(
        keys(repo.findAramaicPhrasesWithin('אמר ליה רב אשי', maxPhrases: 2)),
        ['אמר ליה רב', 'אמר ליה'],
      );
    });

    test('פחות משלוש מילים, או בלי צירוף במילון, מחזירים ריק', () {
      expect(repo.findAramaicPhrasesWithin('אמר ליה'), isEmpty);
      expect(repo.findAramaicPhrasesWithin('אבגד הוזח טיכל'), isEmpty);
      expect(repo.findAramaicPhrasesWithin(''), isEmpty);
    });

    test('דיוק: משפט עברי, מילים שאינן סמוכות או בסדר הפוך אינם מתאימים', () {
      expect(repo.findAramaicPhrasesWithin('הוא אמר לו שלום'), isEmpty);
      expect(repo.findAramaicPhrasesWithin('אמר מר ליה'), isEmpty);
      expect(repo.findAramaicPhrasesWithin('רב ליה אמר'), isEmpty);
    });

    test('דיוק: אין ניחוש קידומת בצירוף, ופיסוק שבתוך הטקסט שובר צירוף', () {
      // "ואמר ליה" אינו "אמר ליה" עם קידומת; נשאר רק הצירוף שנמצא כלשונו.
      expect(keys(repo.findAramaicPhrasesWithin('ואמר ליה רב')), ['ליה רב']);
      // פסיק בין המילים: "אמר," אינה "אמר".
      expect(keys(repo.findAramaicPhrasesWithin('אמר, ליה רב')), ['ליה רב']);
    });

    test('דיוק: צירוף בן חמש מילים בתוך משפט ארוך, והוא הראשון', () {
      expect(
        keys(
          repo.findAramaicPhrasesWithin('והוא אמר ליה רב אשי הכל שם'),
        ).first,
        'אמר ליה רב אשי הכל',
      );
    });

    test('דיוק: מפתח עם כמה משמעויות מוחזר בכולן ומתמזג לכרטיס אחד', () async {
      final multi = DictionaryLookupRepository(
        loadAramaicEntries: () async => const <AramaicDictionaryEntry>[
          AramaicDictionaryEntry(aramaic: 'בר נש', hebrew: 'אדם'),
          AramaicDictionaryEntry(
            aramaic: 'בר נש',
            hebrew: 'בן אנוש',
            dictionary: other,
          ),
        ],
      );
      await multi.ensureAramaicLoaded();
      final found = multi.findAramaicPhrasesWithin(
        'ההוא בר נש',
        dictionaries: {...multi.aramaicDictionaryNames},
      );

      expect(found.map((e) => e.hebrew), ['אדם', 'בן אנוש']);
      expect(DictionaryLookupRepository.mergeAramaicMatches(found), hasLength(1));
    });

    test('ביצועים: בחירה של 20,000 מילים אינה מאטה (לא מתחילות בצירוף)', () {
      final text = List.generate(20000, (i) => 'מילה${i % 50}').join(' ');
      final stopwatch = Stopwatch()..start();
      expect(repo.findAramaicPhrasesWithin(text), isEmpty);
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('suggestAramaicBaseWord', () {
    late DictionaryLookupRepository repo;

    setUp(() async {
      repo = DictionaryLookupRepository(
        loadAramaicEntries: () async => const <AramaicDictionaryEntry>[
          AramaicDictionaryEntry(aramaic: 'אמר', hebrew: 'דיבר'),
          AramaicDictionaryEntry(aramaic: 'ליה', hebrew: 'לו'),
          AramaicDictionaryEntry(aramaic: 'בעי ליה', hebrew: 'צריך לו'),
        ],
      );
      await repo.ensureAramaicLoaded();
    });

    test('קידומת של אות או שתיים ממילה שבמילון', () {
      expect(repo.suggestAramaicBaseWord('דאמר'), (prefix: 'ד', word: 'אמר'));
      expect(repo.suggestAramaicBaseWord('ואמר'), (prefix: 'ו', word: 'אמר'));
      expect(repo.suggestAramaicBaseWord('ודאמר'), (prefix: 'וד', word: 'אמר'));
      expect(
        repo.suggestAramaicBaseWord('דָּאָמַר,'),
        (prefix: 'ד', word: 'אמר'),
      );
    });

    test('דיוק: שתי אותיות קידומת רק כשהראשונה ו/ד/ש', () {
      expect(repo.suggestAramaicBaseWord('ולאמר'), (prefix: 'ול', word: 'אמר'));
      expect(repo.suggestAramaicBaseWord('שבאמר'), (prefix: 'שב', word: 'אמר'));
      expect(repo.suggestAramaicBaseWord('דלאמר'), (prefix: 'דל', word: 'אמר'));
      // רצפים שאינם קידומות: אות ראשונה אחרת
      expect(repo.suggestAramaicBaseWord('בלאמר'), isNull);
      expect(repo.suggestAramaicBaseWord('הלאמר'), isNull);
      expect(repo.suggestAramaicBaseWord('מואמר'), isNull);
    });

    test('אין הצעה למילה שכבר במילון, לצירוף, או כשאין מילה בסיס', () {
      expect(repo.suggestAramaicBaseWord('אמר'), isNull);
      expect(repo.suggestAramaicBaseWord('דבעי'), isNull); // "בעי" רק בתוך צירוף
      expect(repo.suggestAramaicBaseWord('דאמר ליה'), isNull);
      expect(repo.suggestAramaicBaseWord('גאמר'), isNull); // ג אינה קידומת נפוצה
      expect(repo.suggestAramaicBaseWord('ודבאמר'), isNull); // שלוש אותיות
      expect(repo.suggestAramaicBaseWord('זזזזזז'), isNull);
      expect(repo.suggestAramaicBaseWord(''), isNull);
    });
  });

  group('מספר מילונים ארמיים', () {
    const other = 'מילון שיח ישראל';
    const entries = <AramaicDictionaryEntry>[
      AramaicDictionaryEntry(aramaic: 'אבא', hebrew: 'אב'),
      AramaicDictionaryEntry(
        aramaic: 'אבא',
        hebrew: 'פרי',
        dictionary: 'מפירוש אונקלוס על התורה',
      ),
      AramaicDictionaryEntry(
        aramaic: 'גברא',
        hebrew: 'איש',
        dictionary: other,
      ),
      AramaicDictionaryEntry(aramaic: 'בר אבא', hebrew: 'בן אבא'),
    ];

    Future<DictionaryLookupRepository> load() async {
      final repo = DictionaryLookupRepository(
        loadAramaicEntries: () async => entries,
      );
      await repo.ensureAramaicLoaded();
      return repo;
    }

    test('ברירת המחדל מחזירה ערכי "פשיטא" בלבד', () async {
      final repo = await load();

      expect(repo.findAramaicMatches('אבא').map((e) => e.hebrew), <String>[
        'אב',
        'בן אבא',
      ]);
      expect(repo.findAramaicMatches('גברא'), isEmpty);
    });

    test('ערך במילון אחר אינו משנה את תוצאות ברירת המחדל', () async {
      final repo = DictionaryLookupRepository(
        loadAramaicEntries: () async => const [
          AramaicDictionaryEntry(aramaic: 'בר גברא', hebrew: 'בן אדם'),
          AramaicDictionaryEntry(
            aramaic: 'גברא',
            hebrew: 'איש',
            dictionary: other,
          ),
        ],
      );
      await repo.ensureAramaicLoaded();

      expect(repo.findAramaicMatches('גברא').map((e) => e.hebrew), <String>[
        'בן אדם',
      ]);
    });

    test('מפתח זהה בכמה מילונים מוצג בכולם, "פשיטא" ראשון', () async {
      final repo = await load();
      final matches = repo.findAramaicMatches(
        'אבא',
        dictionaries: {...repo.aramaicDictionaryNames},
      );

      expect(matches.map((e) => (e.dictionary, e.hebrew)), [
        (AramaicDictionaryEntry.peshitaDictionary, 'אב'),
        ('מפירוש אונקלוס על התורה', 'פרי'),
        (AramaicDictionaryEntry.peshitaDictionary, 'בן אבא'),
      ]);
    });

    test('אפשר לבקש מילון אחד בשמו', () async {
      final repo = await load();

      expect(
        repo.findAramaicMatches('גברא', dictionaries: {other}).single.hebrew,
        'איש',
      );
      expect(repo.aramaicDictionaryNames, <String>[
        AramaicDictionaryEntry.peshitaDictionary,
        'מפירוש אונקלוס על התורה',
        other,
      ]);
    });
  });

  group('findAramaicMatches (perf)', () {
    test('חיפוש אינו מנרמל מחדש את ערכי המילון בכל קריאה', () async {
      final entries = [
        for (var i = 0; i < 200; i++) _CountingAramaicEntry('צירוף $i אבא'),
        _CountingAramaicEntry('אבא'),
      ];
      final repo = DictionaryLookupRepository(
        loadAramaicEntries: () async => entries,
      );
      await repo.ensureAramaicLoaded();
      for (final entry in entries) {
        entry.reads = 0;
      }

      for (var i = 0; i < 5; i++) {
        expect(repo.findAramaicMatches('אבא'), hasLength(201));
      }

      expect(entries.fold<int>(0, (sum, e) => sum + e.reads), 0);
    });

    test(
      'מנרמל ניקוד, מקף וגרשיים כמו קודם ומחזיר התאמה מדויקת ראשונה',
      () async {
        final repo = DictionaryLookupRepository(
          loadAramaicEntries: () async => const <AramaicDictionaryEntry>[
            AramaicDictionaryEntry(aramaic: 'בַּר־אַבָּא', hebrew: 'בן היער'),
            AramaicDictionaryEntry(aramaic: 'אבא-מרי', hebrew: 'אבי'),
            AramaicDictionaryEntry(aramaic: '  אַבָּא. ', hebrew: 'יער'),
            AramaicDictionaryEntry(aramaic: 'אבאי', hebrew: 'שם'),
            AramaicDictionaryEntry(aramaic: '', hebrew: 'ריק'),
          ],
        );
        await repo.ensureAramaicLoaded();

        expect(repo.findAramaicMatches('אַבָּא').map((e) => e.hebrew), <String>[
          'יער',
          'בן היער',
          'אבי',
        ]);
        expect(repo.findAramaicMatches('מרי').map((e) => e.hebrew), <String>[
          'אבי',
        ]);
      },
    );
  });
}

class _CountingAramaicEntry implements AramaicDictionaryEntry {
  _CountingAramaicEntry(this._aramaic);

  final String _aramaic;
  int reads = 0;

  @override
  String get aramaic {
    reads++;
    return _aramaic;
  }

  @override
  String get hebrew => '';

  @override
  String get dictionary => AramaicDictionaryEntry.peshitaDictionary;
}
