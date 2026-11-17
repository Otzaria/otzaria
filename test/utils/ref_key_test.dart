import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/ref_key.dart';

/// המפתח הקנוני נבנה גם בבונה ה-DB (SeforimLibrary) מול אותו קובץ fixtures.
/// שינוי כאן שמפיל את הבדיקה מחייב שינוי מקביל שם — אחרת ה-hash לא ייפגש.
void main() {
  final fixtures =
      jsonDecode(
            File('test/fixtures/ref_key_fixtures.json').readAsStringSync(),
          )
          as Map<String, dynamic>;

  group('buildRefKey', () {
    for (final entry in fixtures['refKeys'] as List) {
      final input = entry['input'] as String;
      test(input, () {
        final key = buildRefKey(input);
        expect(key, entry['key']);
        if (key != null) expect(refKeyHash(key), entry['hash']);
      });
    }
  });

  group('buildLineRefKey', () {
    for (final entry in fixtures['lineKeys'] as List) {
      final heRef = entry['heRef'] as String;
      test(heRef, () {
        final aliases = (entry['aliases'] as List).cast<String>();
        final key = buildLineRefKey(heRef, aliases);
        expect(key, entry['key']);
        if (key != null) expect(refKeyHash(key), entry['hash']);
      });
    }
  });

  group('heRefWithinLocation', () {
    const heRef = 'רש"י על סנהדרין, עט., ט, א';
    const title = 'רש"י על סנהדרין';

    test('דף ועמוד שהשורה בתוכם', () {
      expect(heRefWithinLocation(heRef, title, ['עט']), isTrue);
      expect(heRefWithinLocation(heRef, title, ['עט', 'א']), isTrue);
    });

    test('דף אחר, עמוד אחר או מספר שרק פותח באותן אותיות', () {
      expect(heRefWithinLocation(heRef, title, ['עט', 'ב']), isFalse);
      expect(heRefWithinLocation(heRef, title, ['מח']), isFalse);
      expect(
        heRefWithinLocation('ספר, יא, ב', 'ספר', ['י']),
        isFalse,
      );
    });

    test('heRef שאינו פותח בשם הספר אינו בתוך הציון', () {
      expect(heRefWithinLocation(heRef, 'רש"י על שבת', ['עט']), isFalse);
    });
  });

  group('partialLineRefKeys', () {
    for (final entry in fixtures['partialLineKeys'] as List) {
      final heRef = entry['heRef'] as String;
      test(heRef, () {
        final aliases = (entry['aliases'] as List).cast<String>();
        final expected = (entry['keys'] as List).cast<Map<String, dynamic>>();
        final keys = partialLineRefKeys(heRef, aliases);
        expect(keys, [for (final e in expected) e['key']]);
        expect(keys.map(refKeyHash), [for (final e in expected) e['hash']]);
      });
    }

    test('ספרות ASCII בכל אורך ואותיות עבריות בסדר לא עולה', () {
      expect(
        partialLineRefKeys('ספר, מבוא, 123456789, 007', const ['ספר']),
        ['~ 123456789 007'],
      );
      expect(
        partialLineRefKeys('ספר, מבוא, תתרריי, ט״ו', const ['ספר']),
        ['~ תתרריי טו'],
      );
    });

    test('רכיב לא מספרי אחרי המספר הראשון מבטל את המפתחות החלקיים', () {
      for (final component in ['1א', 'א1', 'ך', 'תתתתתתת', 'פרק', '١٢']) {
        final heRef = 'ספר, מבוא, יב, $component, ג';
        expect(
          partialLineRefKeys(heRef, const ['ספר']),
          isEmpty,
          reason: heRef,
        );
      }
    });

    test('קידומת ארוכה עם מקף, רכיב ריק וטווח בסוף ההפניה', () {
      expect(
        partialLineRefKeys('ספר־עיון, מבוא,, י״ב, ג–ד', const [
          'ספר',
          'ספר־עיון',
        ]),
        ['~ יב ג'],
      );
    });
  });

  group('buildPartialRefKey', () {
    for (final entry in fixtures['partialRefKeys'] as List) {
      final input = entry['input'] as String;
      test(input, () {
        final key = buildPartialRefKey(input);
        expect(key, entry['key']);
        expect(refKeyHash(key!), entry['hash']);
      });
    }
  });

  test('שאילתה וכותרת מגיעות לאותו מפתח', () {
    expect(
      buildRefKey('פרק לב פסוק יא'),
      buildLineRefKey('ישעיהו לב, יא', const ['ישעיהו']),
    );
  });

  test('שורת כותרת אינה מקבלת מפתח', () {
    expect(buildLineRefKey('ישעיהו', const ['ישעיהו']), isNull);
  });

  group('lineRefIndexEntries', () {
    // מפתחות כל שורה בנפרד — מה שהאינדקס חייב להכיל, באותו סדר.
    List<(int, int)> perLine(
      List<({int lineIndex, String heRef})> refs,
      String title,
    ) => [
      for (final ref in refs)
        if (buildLineRefKey(ref.heRef, [title]) case final key?) ...[
          (refKeyHash(key), ref.lineIndex),
          for (final partial in partialLineRefKeys(ref.heRef, [title]))
            (refKeyHash(partial), ref.lineIndex),
        ],
    ];

    // כמה שורות לכל heRef, heRef שחוזר אחרי הפסקה, שורת כותרת וכותרת זרה.
    const refs = [
      (lineIndex: 0, heRef: 'טור'),
      (lineIndex: 1, heRef: 'טור, חושן משפט, שט, ג'),
      (lineIndex: 2, heRef: 'טור, חושן משפט, שט, ג'),
      (lineIndex: 3, heRef: 'טור, חושן משפט, שט, ד'),
      (lineIndex: 4, heRef: 'טור, חושן משפט, שט, ג'),
      (lineIndex: 5, heRef: 'טור, יורה דעה, שט, ג'),
      (lineIndex: 6, heRef: 'ספר אחר, א, ב'),
      (lineIndex: 7, heRef: 'ספר אחר, א, ב'),
    ];

    test('זהה למפתחות שמחושבים לכל שורה בנפרד, כולל חלקיים', () {
      final entries = lineRefIndexEntries(
        refs,
        (heRef) => lineRefKeyHashes(heRef, 'טור'),
      );
      expect(entries, perLine(refs, 'טור'));
      expect(entries.length, greaterThan(refs.length));
    });

    test('המפתחות מחושבים פעם אחת לכל heRef', () {
      final computed = <String>[];
      lineRefIndexEntries(refs, (heRef) {
        computed.add(heRef);
        return lineRefKeyHashes(heRef, 'טור');
      });
      expect(computed, refs.map((ref) => ref.heRef).toSet().toList());
    });
  });
}
