import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/aramaic_dictionary/aramaic_dictionary_screen.dart';
import 'package:otzaria/tools/aramaic_dictionary/widgets/aramaic_result_card.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

const _peshita = AramaicDictionaryEntry.peshitaDictionary;
final _hebrewLetter = RegExp('[א-ת]');

bool _isPlaceholder(String key, String value) {
  if (!_hebrewLetter.hasMatch(key)) return true;
  return value
      .split('***')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .every(
        (part) =>
            part == '*' || part == '(סימן)' || !_hebrewLetter.hasMatch(part),
      );
}

String _json(Map<String, List<Map<String, String>>> dictionaries) =>
    jsonEncode(dictionaries);

void main() {
  late String rawJson;
  late Map<String, dynamic> data;
  late AramaicIndex index;

  setUpAll(() {
    rawJson = File('assets/dictionary.json').readAsStringSync();
    data = jsonDecode(rawJson) as Map<String, dynamic>;
    index = DictionaryLookupRepository.decodeAramaicIndex(rawJson);
  });

  List<MapEntry<String, String>> rawEntries(String name) => [
    for (final e in data[name] as List)
      for (final kv in (e as Map<String, dynamic>).entries)
        MapEntry(kv.key, kv.value as String),
  ];

  group('assets/dictionary.json', () {
    test('כל מילון הוא רשימה של ערכים בני מפתח אחד עם פירוש טקסטואלי', () {
      expect(data.keys, contains(_peshita));
      for (final MapEntry(:key, :value) in data.entries) {
        expect(value, isA<List>(), reason: key);
        for (final entry in value as List) {
          expect(entry, isA<Map<String, dynamic>>(), reason: key);
          expect((entry as Map).length, 1, reason: key);
          expect(entry.values.single, isA<String>(), reason: key);
        }
      }
    });

    test('אין מפתח כפול בתוך אותו מילון', () {
      for (final name in data.keys) {
        final keys = rawEntries(name).map((e) => e.key).toList();
        expect(keys.toSet().length, keys.length, reason: name);
      }
    });

    test('סוגריים מאוזנים בכל פירוש בכל המילונים', () {
      for (final name in data.keys) {
        for (final entry in rawEntries(name)) {
          for (final pair in const ['()', '{}', '[]']) {
            expect(
              entry.value.split(pair[0]).length,
              entry.value.split(pair[1]).length,
              reason: '$name/${entry.key}',
            );
          }
        }
      }
    });
  });

  group('decodeAramaicIndex על הנכס האמיתי', () {
    test('טוען את כל המילונים, "פשיטא" ראשון, ושם המילון נשמר בכל ערך', () {
      final names = index.entries.map((e) => e.dictionary).toSet().toList();

      expect(names.first, _peshita);
      expect(names.toSet(), data.keys.toSet());
      var seenOther = false;
      for (final entry in index.entries) {
        if (entry.dictionary != _peshita) seenOther = true;
        expect(
          seenOther && entry.dictionary == _peshita,
          isFalse,
          reason: 'ערכי "פשיטא" חייבים לבוא לפני כל השאר',
        );
      }
    });

    test('כל ערך שאינו מחזיק מקום נטען, ואף פירוש לא משתנה', () {
      for (final name in data.keys) {
        final expected = [
          for (final e in rawEntries(name))
            if (!_isPlaceholder(e.key, e.value)) e,
        ];
        final actual = [
          for (final e in index.entries)
            if (e.dictionary == name) e,
        ];

        expect(actual.length, expected.length, reason: name);
        for (var i = 0; i < expected.length; i++) {
          expect(actual[i].aramaic, expected[i].key, reason: name);
          expect(actual[i].hebrew, expected[i].value, reason: name);
        }
      }
    });

    test('"פשיטא" נטען במלואו: אף ערך שלו אינו מחזיק מקום', () {
      expect(
        index.entries.where((e) => e.dictionary == _peshita).length,
        (data[_peshita] as List).length,
      );
    });

    test('אין מחזיקי מקום במילון הטעון', () {
      for (final entry in index.entries) {
        expect(_isPlaceholder(entry.aramaic, entry.hebrew), isFalse);
        expect(entry.hebrew.trim(), isNot('*'));
        expect(entry.hebrew.trim(), isNot('(סימן)'));
      }
    });

    test('כל ערך עובר פענוח עיצוב וכל פירוש בו אינו ריק', () {
      for (final entry in index.entries) {
        final presentation = AramaicDictionaryEntryPresentation.parse(
          entry.hebrew,
        );
        expect(
          presentation.meanings.every(
            (m) =>
                m.mainText.isNotEmpty ||
                (m.expression ?? '').isNotEmpty ||
                (m.expansion ?? '').isNotEmpty,
          ),
          isTrue,
          reason: '${entry.dictionary}/${entry.aramaic}',
        );
      }
    });

    test('הפענוח והאינדקס נבנים בזמן סביר', () {
      final stopwatch = Stopwatch()..start();
      DictionaryLookupRepository.decodeAramaicIndex(rawJson);
      stopwatch.stop();

      // הסף רחב כדי לא להיכשל על מכונה עמוסה.
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });

  group('חיפוש במסך המילון בשני הכיוונים', () {
    late List<Map<String, String>> screenData;

    setUpAll(() {
      screenData = [
        for (final e in index.entries)
          {
            'aramaic': e.aramaic,
            'hebrew': e.hebrew,
            'dictionary': e.dictionary,
            'aramaicPlain': removeVolwels(e.aramaic),
            'hebrewPlain': removeVolwels(e.hebrew),
          },
      ];
    });

    test('כל מילון מגיע לתוצאות לפי המפתח הארמי של ערך שלו', () {
      for (final name in index.entries.map((e) => e.dictionary).toSet()) {
        final sample = screenData
            .where((e) => e['dictionary'] == name)
            .take(40);
        for (final entry in sample) {
          final results = rankAramaicMatches(
            screenData,
            'aramaicPlain',
            entry['aramaicPlain']!,
          );
          expect(results, contains(same(entry)), reason: '$name/$entry');
        }
      }
    });

    test('כל מילון מגיע לתוצאות לפי הפירוש העברי של ערך שלו', () {
      for (final name in index.entries.map((e) => e.dictionary).toSet()) {
        final sample = screenData
            .where((e) => e['dictionary'] == name)
            .take(40);
        for (final entry in sample) {
          final results = rankAramaicMatches(
            screenData,
            'hebrewPlain',
            entry['hebrewPlain']!,
          );
          expect(results, contains(same(entry)), reason: '$name/$entry');
        }
      }
    });

    test('בשוויון דירוג "פשיטא" קודם, והסדר יציב', () {
      final byKey = <String, List<Map<String, String>>>{};
      for (final entry in screenData) {
        byKey.putIfAbsent(entry['aramaicPlain']!, () => []).add(entry);
      }
      final shared = byKey.entries
          .where(
            (e) =>
                e.value.any((x) => x['dictionary'] == _peshita) &&
                e.value.any((x) => x['dictionary'] != _peshita),
          )
          .take(200);

      for (final MapEntry(:key, :value) in shared) {
        final exact = rankAramaicMatches(
          screenData,
          'aramaicPlain',
          key,
        ).where((e) => e['aramaicPlain'] == key).toList();

        expect(exact.first['dictionary'], _peshita, reason: key);
        expect(exact.length, value.length, reason: key);
      }
    });
  });

  group('rankAramaicMatches', () {
    Map<String, String> entry(String key, String dictionary) => {
      'aramaicPlain': key,
      'dictionary': dictionary,
    };

    test('בכל רמת התאמה "פשיטא" קודם, והרמות עצמן נשמרות', () {
      final data = [
        entry('אבגד', 'אחר'),
        entry('אבג', 'אחר'),
        entry('אב', 'אחר'),
        entry('אבה', _peshita),
        entry('אבגדה', _peshita),
      ];

      final results = rankAramaicMatches(data, 'aramaicPlain', 'אב');

      expect(results.map((e) => e['aramaicPlain']), [
        'אב',
        'אבה',
        'אבגדה',
        'אבג',
        'אבגד',
      ]);
    });
  });

  group('mergeAramaicMatches', () {
    Map<String, String> entry(String key, String meaning, String dictionary) =>
        {
          'aramaic': key,
          'aramaicPlain': removeVolwels(key),
          'hebrew': meaning,
          'hebrewPlain': removeVolwels(meaning),
          'dictionary': dictionary,
        };

    test('מפתח זהה ממילונים שונים הופך לכרטיס אחד, פירושי "פשיטא" קודם', () {
      final merged = mergeAramaicMatches([
        entry('אַרְעָא', '{אַרְעָא} אֶרֶץ', 'אחר'),
        entry('דנא', 'זה', _peshita),
        entry('ארעא', 'ארץ, קרקע', _peshita),
      ]);

      expect(merged.map((e) => e['aramaic']), ['ארעא', 'דנא']);
      expect(merged.first['hebrew'], 'ארץ, קרקע *** {אַרְעָא} אֶרֶץ');
    });

    test('פירוש זהה שחוזר במילונים שונים מוצג פעם אחת', () {
      final merged = mergeAramaicMatches([
        entry('אבוך', 'אביך', _peshita),
        entry('אבוך', 'אָבִיךָ *** אביך *** אב', 'אחר'),
        entry('אבוך', 'אביך', 'עוד'),
      ]);

      expect(merged.single['hebrew'], 'אביך *** אב');
    });

    test('סדר הקבוצות לפי התוצאה הראשונה בדירוג, וערך יחיד נשאר כמות שהוא', () {
      final single = entry('גברא', 'איש', _peshita);
      final merged = mergeAramaicMatches([
        single,
        entry('בר', 'בן', _peshita),
        entry('גברא', 'אדם', 'אחר'),
      ]);

      expect(merged.map((e) => e['aramaic']), ['גברא', 'בר']);
      expect(merged.first['hebrew'], 'איש *** אדם');
      expect(
        mergeAramaicMatches([single]).single,
        same(single),
      );
    });
  });

  group('AramaicResultCard', () {
    test('פירוש שכל חלקיו כבר הופיעו אינו מוצג שוב', () {
      final meanings = AramaicResultCard.visibleMeanings(
        'ארץ, קרקע *** קרקע *** ארץ *** {אַרְעָא} אֲדָמָה',
      );

      expect(meanings.map((m) => m.mainText), ['ארץ, קרקע', 'אֲדָמָה']);
    });

    test('מונח החיפוש ההפוך הוא הראשון, בלי ניקוד והערות', () {
      expect(AramaicResultCard.searchTermOf('אֶרֶץ, קרקע'), 'ארץ');
      expect(AramaicResultCard.searchTermOf('(למעלה) עָלָה; עלה'), 'עלה');
      expect(AramaicResultCard.searchTermOf('(הערה)'), '');
    });

    test('מונח החיפוש ההפוך נלקח מהשורה הראשונה בלי נקודת הרשימה', () {
      expect(AramaicResultCard.searchTermOf('• ארץ, קרקע\n• אדמה'), 'ארץ');
      expect(AramaicResultCard.searchTermOf('שורה א\nשורה ב'), 'שורה א');
      expect(AramaicResultCard.searchTermOf('• (הערה)\n• אדמה'), 'אדמה');
    });
  });

  group('decodeAramaicIndex על נתונים סינתטיים', () {
    test('"פשיטא" ראשון גם כשאינו ראשון בקובץ', () {
      final index = DictionaryLookupRepository.decodeAramaicIndex(
        _json({
          'מילון אחר': [
            {'אבא': 'פרי'},
          ],
          _peshita: [
            {'אבא': 'אב'},
          ],
        }),
      );

      expect(index.entries.map((e) => (e.dictionary, e.hebrew)), [
        (_peshita, 'אב'),
        ('מילון אחר', 'פרי'),
      ]);
    });

    test('מחזיקי מקום, פירוש ריק ומפתח בלי אות עברית אינם נטענים', () {
      final index = DictionaryLookupRepository.decodeAramaicIndex(
        _json({
          _peshita: [
            {'אל"ף': '*'},
            {'אמ"ת': '(סימן)'},
            {'ריק': '  '},
            {'abc': 'פירוש'},
            {'שלוש': '123'},
            {'אבא': 'אב'},
            {'רב': '* *** רב'},
          ],
        }),
      );

      expect(index.entries.map((e) => e.aramaic), ['אבא', 'רב']);
      expect(index.entries.last.hebrew, '* *** רב');
    });

    test('ערך שאינו רשימה נדלג, וערך בלי פשיטא לא מכשיל', () {
      final index = DictionaryLookupRepository.decodeAramaicIndex(
        '{"הערה":"טקסט","מילון אחר":[{"גברא":"איש"},{}]}',
      );

      expect(index.entries.single.dictionary, 'מילון אחר');
    });
  });
}
