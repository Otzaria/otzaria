import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/aramaic_dictionary/aramaic_dictionary_screen.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

void main() {
  final repository = DictionaryLookupRepository();

  group('normalizeAramaicQuery', () {
    test('מסיר ניקוד, גרשיים, פיסוק וסימני כיווניות בקצוות ומצמצם רווחים', () {
      const expected = {
        'אמר': 'אמר',
        'אָמַר': 'אמר',
        'אמר,': 'אמר',
        'אמר.': 'אמר',
        '(אמר)': 'אמר',
        '«אמר»': 'אמר',
        'מאי?': 'מאי',
        'מאי:': 'מאי',
        '‏אמר': 'אמר',
        'אמר‏': 'אמר',
        '‎אמר‎': 'אמר',
        '  אמר  ': 'אמר',
        'אמר   ליה': 'אמר ליה',
        'אמר ליה': 'אמר ליה',
        'א"ל': 'אל',
        "א''ל": 'אל',
        'א״ל': 'אל',
        'א׳ל': 'אל',
        '"אמר"': 'אמר',
        '': '',
        '...': '',
      };
      expected.forEach((raw, normalized) {
        expect(
          repository.normalizeAramaicQuery(raw),
          normalized,
          reason: raw.codeUnits.toString(),
        );
      });
    });

    test('נרמול שאילתה עברית משאיר גרשיים ומסיר רק ניקוד וקצוות', () {
      expect(repository.normalizeHebrewMeaningQuery('עץ,'), 'עץ');
      expect(repository.normalizeHebrewMeaningQuery('(עֵץ)'), 'עץ');
      expect(repository.normalizeHebrewMeaningQuery('ר"ח'), 'ר"ח');
      expect(repository.normalizeHebrewMeaningQuery('‏עץ'), 'עץ');
    });

    test('חיפוש בפירושים משמר מספרים, שברים ואותיות לועזיות', () {
      for (final query in ['1/3', '2000', '2000 אמות', 'A', 'א A 2', '½']) {
        for (final decorated in [query, '($query)', '‏$query,']) {
          expect(repository.normalizeHebrewMeaningQuery(decorated), query);
        }
      }
    });
  });

  group('אותה שאילתה, אותן תוצאות בתפריט ההקשר, ב-API ובמסך המילון', () {
    late DictionaryLookupRepository real;
    late List<AramaicDictionaryEntry> entries;
    late List<Map<String, String>> screenData;

    setUpAll(() async {
      final raw = File('assets/dictionary.json').readAsStringSync();
      entries = DictionaryLookupRepository.decodeAramaicIndex(raw).entries;
      real = DictionaryLookupRepository(
        loadAramaicEntries: () async => entries,
      );
      await real.ensureAramaicLoaded();
      final keys = real.getAramaicNormalizedKeys();
      screenData = [
        for (final (i, e) in real.getAllAramaicEntries().indexed)
          {
            'aramaic': e.aramaic,
            'hebrew': e.hebrew,
            'dictionary': e.dictionary,
            'aramaicPlain': keys[i],
            'hebrewPlain': removeVolwels(e.hebrew),
          },
      ];
    });

    test('המפתחות המנורמלים מיושרים לערכים ושווים לנרמול המשותף', () {
      final keys = real.getAramaicNormalizedKeys();
      expect(keys.length, real.getAllAramaicEntries().length);
      for (final (i, e) in real.getAllAramaicEntries().indexed) {
        expect(
          keys[i],
          real.normalizeAramaicQuery(e.aramaic),
          reason: e.aramaic,
        );
      }
    });

    test(
      'גרסאות מקושטות של מפתח נותנות את אותן התאמות מדויקות בכל המסלולים',
      () {
        // מדגם יציב: כל ערך שלושים ושבעה בנכס, מילה בודדת או צירוף.
        final sample = <String>[];
        for (var i = 0; i < entries.length; i += 37) {
          final key = real.normalizeAramaicQuery(entries[i].aramaic);
          if (key.isNotEmpty) sample.add(key);
        }
        expect(sample.length, greaterThan(200));

        const decorations = <String Function(String)>[
          _plain,
          _comma,
          _parens,
          _rlm,
          _question,
        ];
        final names = {...real.aramaicDictionaryNames};

        for (final key in sample) {
          // ההתאמות המדויקות בתפריט ההקשר לשאילתה הנקייה.
          List<String> contextExact(String q) => [
            for (final e in real.findAramaicMatches(q, dictionaries: names))
              if (real.normalizeAramaicQuery(e.aramaic) == key) e.aramaic,
          ];
          List<String> screenExact(String q) {
            final normalized = real.normalizeAramaicQuery(q);
            if (normalized.isEmpty) return const [];
            return [
              for (final e in rankAramaicMatches(
                screenData,
                'aramaicPlain',
                normalized,
              ))
                if (e['aramaicPlain'] == normalized) e['aramaic']!,
            ];
          }

          final baseContext = contextExact(key);
          final baseScreen = screenExact(key);
          for (final decorate in decorations) {
            final q = decorate(key);
            expect(contextExact(q), baseContext, reason: 'תפריט הקשר: "$q"');
            expect(screenExact(q), baseScreen, reason: 'מסך: "$q"');
          }
          // המסך מוצא לפחות כל מה שהתפריט מוצא כהתאמה מדויקת.
          expect(
            baseScreen.toSet(),
            containsAll(baseContext.toSet()),
            reason: key,
          );
        }
      },
    );
  });
}

String _plain(String k) => k;
String _comma(String k) => '$k,';
String _parens(String k) => '($k)';
String _rlm(String k) => '‏$k‏';
String _question(String k) => '$k?';
