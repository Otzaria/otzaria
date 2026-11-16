import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/aramaic_dictionary/aramaic_dictionary_screen.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

const _dictionaryName = 'מילון פשיטא';

/// כלל המיון של הצינור (tool/aramaic_dictionary_pipeline/common.py: hebrew_sort_key):
/// אות-אחר-אות, סופיות כרגילות, רווח/מקף לפני אות, גרשיים מתעלמים.
String _sortKey(String key) {
  var k = removeVolwels(key)
      .replaceAll(RegExp('[״“”„]'), '"')
      .replaceAll(RegExp("[׳‘’‚´`]"), "'")
      .replaceAll("''", '"')
      .replaceAll(RegExp(r'\s*-\s*'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[ .,;:!?]+|[ .,;:!?]+$'), '');
  k = k.replaceAll('"', '').replaceAll("'", '').replaceAll('-', ' ');
  const finals = {'ך': 'כ', 'ם': 'מ', 'ן': 'נ', 'ף': 'פ', 'ץ': 'צ'};
  return k.split('').map((c) => finals[c] ?? c).join();
}

String _normalizeKey(String key) => removeVolwels(key)
    .replaceAll(RegExp('[״“”„]'), '"')
    .replaceAll("''", '"')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

void main() {
  late String rawJson;
  late Map<String, dynamic> data;
  late List<MapEntry<String, String>> entries;

  setUpAll(() {
    rawJson = File('assets/dictionary.json').readAsStringSync();
    data = jsonDecode(rawJson) as Map<String, dynamic>;
    entries = [
      for (final e in data[_dictionaryName] as List)
        for (final kv in (e as Map<String, dynamic>).entries)
          MapEntry(kv.key, kv.value as String),
    ];
  });

  group('assets/dictionary.json', () {
    test('כל המילונים בקובץ נשמרו, בסדר ובמבנה הקיימים', () {
      expect(data.keys.toList(), <String>[
        'מילון פשיטא',
        'מילון שיח ישראל',
        'מפירוש אונקלוס על התורה',
        'מושגים ואישים',
      ]);
      for (final list in data.values) {
        for (final entry in list as List) {
          expect(entry, isA<Map<String, dynamic>>());
          expect((entry as Map).length, 1);
          expect(entry.values.single, isA<String>());
        }
      }
      // המילונים האחרים אינם חלק מהרחבה זו (מאומת לעומק בצינור, validate.py).
      // 2,739 מקוריים פחות 699 ערכי מילוי ("*", "(סימן)") שנמחקו (add_bavli.py --drop-placeholders).
      expect((data['מילון שיח ישראל'] as List).length, 2040);
      expect((data['מפירוש אונקלוס על התורה'] as List).length, 2516);
      expect((data['מושגים ואישים'] as List).length, 1);
    });

    test('אין מפתחות או פירושים ריקים במילון הארמי-עברי', () {
      for (final entry in entries) {
        expect(entry.key.trim(), isNotEmpty);
        expect(entry.value.trim(), isNotEmpty, reason: entry.key);
      }
    });

    test('כל ערך עובר פענוח, וכל פירוש בו לא ריק ולא מכיל סימון שבור', () {
      for (final entry in entries) {
        final presentation = AramaicDictionaryEntryPresentation.parse(
          entry.value,
        );
        expect(presentation.meanings, isNotEmpty, reason: entry.key);
        for (final meaning in presentation.meanings) {
          // ערך קיים שכולו הרחבה "(=...)" (למשל א"כ) מותר: הטקסט הראשי ריק.
          expect(
            meaning.mainText.isNotEmpty || meaning.expansion != null,
            isTrue,
            reason: entry.key,
          );
          // סימון שנשאר גולמי בטקסט הראשי מעיד על תחביר שבור.
          expect(meaning.mainText, isNot(contains('***')), reason: entry.key);
          expect(meaning.mainText, isNot(contains('{')), reason: entry.key);
          expect(meaning.mainText, isNot(contains('}')), reason: entry.key);
        }
      }
    });

    test('סוגריים מאוזנים בכל ערך (סוגר פתוח בולע את שארית הפירוש)', () {
      int count(String s, String ch) => ch.allMatches(s).length;
      for (final entry in entries) {
        for (final pair in const [
          ['(', ')'],
          ['{', '}'],
          ['[', ']'],
        ]) {
          expect(
            count(entry.value, pair[0]),
            count(entry.value, pair[1]),
            reason: '${entry.key}: ${entry.value}',
          );
        }
      }
    });

    test('המילון לא התכווץ: לפחות כמספר הערכים המקורי', () {
      expect(entries.length, greaterThanOrEqualTo(1731));
    });

    test('הערכים ממוינים א-ב לפי כלל המיון היציב', () {
      for (var i = 1; i < entries.length; i++) {
        final a = _sortKey(entries[i - 1].key);
        final b = _sortKey(entries[i].key);
        expect(
          a.compareTo(b) <= 0,
          isTrue,
          reason: '${entries[i - 1].key} ≤ ${entries[i].key}',
        );
      }
    });

    test('אין כפילויות מפתח מנורמל מעבר לשתיים שהיו במקור', () {
      final counts = <String, int>{};
      for (final entry in entries) {
        counts.update(
          _normalizeKey(entry.key),
          (c) => c + 1,
          ifAbsent: () => 1,
        );
      }
      final duplicates = counts.entries
          .where((e) => e.value > 1)
          .map((e) => e.key)
          .toSet();
      expect(duplicates, <String>{'איתא', 'קשוט'});
    });

    test(
      'ערכי בבלי נכנסו ל"פשיטא" (דוגמאות), עם פירושים מרובים מופרדים ב-***',
      () {
        final map = {for (final e in entries) e.key: e.value};
        expect(map['אאנפייהו'], 'על פניהם');
        expect(map['מקצתן'], 'קצת מהם *** חלק מהם');
        expect(map['מטראתא'], 'שקים גדולים (עבודה זרה י ע"ב)');
      },
    );

    test('תרגומי בבלי אינם מבלבלים צוואר ובקעה ושומרים את מלוא הצירוף', () {
      final map = {for (final e in entries) e.key: e.value};
      expect(map, isNot(contains('צוואר')));
      expect(map['דפקא'], 'צוואר');
      expect(map['כיון דקם קם'], 'כיון שהתקלקלו, לא יתקלקלו יותר');
      expect(
        map['גוד או אגוד'],
        'קנה אתה את חלקי או שאני אקנה את חלקך (חלוקת שותפות)',
      );
      expect(
        map['על דאטפת אטפוך'],
        'על שהטבעת (אחרים), הטביעו אותך (סוכה נג.)',
      );
    });

    test('ערכי הרגרסיה הקיימים נשמרו, גם אם נוספו להם משמעויות', () {
      Map<String, String> byKey() => {for (final e in entries) e.key: e.value};
      final map = byKey();
      expect(
        map['אברא'],
        startsWith('{אַבָּרָא} אמת. *** {אֲבָרָא } אבר, עופרת.'),
      );
      expect(
        map['אהני'],
        // המשמעות הראשונה הורחבה באישור מפורש ("הועיל, הועילה"); המקורית נשמרת כתחילית
        allOf(
          startsWith('{אַהֲנֵי} הועיל'),
          contains(' *** {אַהָנֵי} (=א הני) על אלה'),
        ),
      );
      expect(map['אמאי'], '{אַמַּאי} מדוע, למה, על מה');
      expect(
        map['אגמרך'],
        startsWith('{אַגְמְרַךְ} לִמדך *** {אַגְמְרַךְ} אלמדך'),
      );
      expect(
        map['איבעי'],
        startsWith(
          '{אֶיבְעֵי} אשאל *** אִיבָּעֵי לֵיה. היה צריך *** {אִיבָּעֵי} נתבקש, היה צריך',
        ),
      );
    });
  });

  group('חיפוש במילון האמיתי', () {
    late List<Map<String, String>> searchData;

    setUpAll(() {
      searchData = [
        for (final e in entries)
          {
            'aramaic': e.key,
            'hebrew': e.value,
            'aramaicPlain': removeVolwels(e.key),
            'hebrewPlain': removeVolwels(e.value),
          },
      ];
    });

    test('ארמית ← עברית: מילה ללא ניקוד מוצאת גם מפתח מנוקד', () {
      final results = rankAramaicMatches(searchData, 'aramaicPlain', 'איתא');
      expect(results, isNotEmpty);
      expect(results.first['aramaicPlain'], 'איתא');
    });

    test('ארמית ← עברית: אברא מציג את שתי המשמעויות השונות', () {
      final results = rankAramaicMatches(searchData, 'aramaicPlain', 'אברא');
      final exact = results.firstWhere((e) => e['aramaic'] == 'אברא');
      final presentation = AramaicDictionaryEntryPresentation.parse(
        exact['hebrew']!,
      );
      expect(presentation.meanings.map((m) => m.mainText), contains('אמת.'));
      expect(
        presentation.meanings.map((m) => m.mainText),
        contains('אבר, עופרת.'),
      );
    });

    test('עברית ← ארמית: פירוש עברי מוצא את המילה הארמית', () {
      final results = rankAramaicMatches(searchData, 'hebrewPlain', 'עופרת');
      expect(results.map((e) => e['aramaic']), contains('אברא'));
    });

    test('מחרוזת חיפוש שאינה במילון אינה מחזירה תוצאות', () {
      expect(rankAramaicMatches(searchData, 'aramaicPlain', 'זזזזזז'), isEmpty);
    });

    test('הטעינה והאינדקס של הקובץ המלא מהירים ואינם ריקים', () {
      final stopwatch = Stopwatch()..start();
      final index = DictionaryLookupRepository.decodeAramaicIndex(rawJson);
      stopwatch.stop();

      expect(
        index.entries.where((e) => e.dictionary == _dictionaryName).length,
        entries.length,
      );
      // תקרה נדיבה (CI איטי): ב-5,000 ערכים הפענוח לוקח עשרות אלפיות שנייה.
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    });

    test('תפריט ההקשר: מילה שכיחה בצירופים מוגבלת, והמדויקת נשמרת', () async {
      final repo = DictionaryLookupRepository(
        loadAramaicEntries: () async => [
          for (final e in entries)
            AramaicDictionaryEntry(aramaic: e.key, hebrew: e.value),
        ],
      );
      await repo.ensureAramaicLoaded();

      final all = repo.findAramaicMatches('ליה');
      final capped = repo.findAramaicMatches('ליה', maxContainingMatches: 8);

      expect(capped.length, lessThanOrEqualTo(all.length));
      final exactCount = all
          .where((e) => removeVolwels(e.aramaic) == 'ליה')
          .length;
      expect(exactCount, greaterThan(0));
      expect(capped.length, lessThanOrEqualTo(exactCount + 8));
      expect(capped, isNotEmpty);
      expect(removeVolwels(capped.first.aramaic), 'ליה');
      // מילה שכיחה בצירופים באמת נחתכת (אחרת הבדיקה לא בודקת כלום)
      expect(all.length, greaterThan(capped.length));
    });
  });
}
