// וקטורי הבדיקה המשותפים לתיקון הזה ולתוסף «המקרא כמסורה»: אותם קלטים (שורות
// המסד כמות שהן) ואותן ציפיות, כדי שהתוסף והאפליקציה לא ייפרדו בהתנהגותם.
// המקור: tests/vectors/mikra-structure.json שבתוסף; כאן העתק ב-test/fixtures.
//
// ההבדל היחיד בייצוג: בתוסף פתוחה באמצע פסוק מחלקת את הפסוק לשתי פסקאות;
// כאן הפסוק נשאר שורה אחת, והפתוחה שבאמצעו היא שבירת שורה (<br>) בתוכו.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/mikra_selection.dart';
import 'package:otzaria/text_book/utils/mikra_structure.dart';

void main() {
  final doc =
      jsonDecode(
            File(
              'test/fixtures/mikra_structure_vectors.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  for (final c in (doc['cases'] as List).cast<Map<String, dynamic>>()) {
    test(c['name'] as String, () {
      final lines = (c['lines'] as List).cast<List<dynamic>>();
      final content = [for (final l in lines) l[2] as String];
      final mikra = MikraStructure.parse(
        content,
        bookTitle: c['divisions'] == null ? null : c['book'] as String,
      );
      expect(mikra, isNotNull, reason: 'המבנה לא זוהה');
      int pos(String lineIndex) {
        final p = lines.indexWhere((l) => l[0] == int.parse(lineIndex));
        expect(p, isNonNegative, reason: 'שורה $lineIndex חסרה בפרוסה');
        return p;
      }

      final e = c['expect'] as Map<String, dynamic>;
      Map<String, dynamic> of(String key) =>
          (e[key] as Map<String, dynamic>?) ?? const {};

      of('gutter').forEach((line, want) {
        expect(
          mikra!.gutterLabelAt(pos(line))?.toString(),
          want,
          reason: 'גליון $line',
        );
      });
      of('division').forEach((line, want) {
        final d = mikra!.divisionAt(pos(line));
        expect(
          d == null ? null : [d.parasha, d.aliyah],
          want,
          reason: 'עלייה $line',
        );
      });
      of('endsParagraph').forEach((line, want) {
        expect(mikra!.petuchaAt(pos(line)), want, reason: 'פתוחה $line');
      });
      of('citation').forEach((line, want) {
        final got = mikra!.citationAt(pos(line));
        expect(
          got == null ? null : [got.parasha, got.aliyah],
          want,
          reason: 'ציון $line',
        );
      });
      of('verse').forEach((line, want) {
        final l = mikra!.lines[pos(line)];
        expect([l.chapter, l.verse], want, reason: 'פסוק $line');
      });
      of('pieces').forEach((line, want) {
        final pieces = (want as List).cast<bool>();
        final html = mikraDisplayHtml(content[pos(line)]);
        expect(
          '<br>'.allMatches(html).length,
          pieces.length - 1,
          reason: 'שבירות בתוך הפסוק $line',
        );
        expect(mikra!.petuchaAt(pos(line)), pieces.last, reason: 'סוף $line');
      });
      of('gaps').forEach((line, want) {
        expect(
          '{ס}'.allMatches(mikraDisplayHtml(content[pos(line)])).length,
          want,
          reason: 'סתומות $line',
        );
      });

      // הפסקאות: שורות הפסוק לפי הסדר, וחיתוך אחרי פתוחה בסוף פסוק.
      final paragraphs = <List<int>>[];
      var current = <int>[];
      for (var i = 0; i < lines.length; i++) {
        if (mikra!.kindAt(i) != MikraLineKind.verse) continue;
        current.add(lines[i][0] as int);
        if (mikra.petuchaAt(i)) {
          paragraphs.add(current);
          current = [];
        }
      }
      if (current.isNotEmpty) paragraphs.add(current);
      final first = (e['firstParagraphs'] as List?)
          ?.map((p) => (p as List).cast<int>())
          .toList();
      if (first != null) {
        expect(paragraphs.take(first.length).toList(), first);
      }
      of('paragraphsWithLine').forEach((line, want) {
        // כאן: פסקה אחת, ושבירת שורה בתוכה לכל פתוחה שבאמצע הפסוק.
        expect(
          1 + '<br>'.allMatches(mikraDisplayHtml(content[pos(line)])).length,
          want,
          reason: 'פסקאות עם $line',
        );
      });
    });
  }

  test('העתקה: בלי {פ} ו-{ס} ובלי ריווח הסתומה', () {
    for (final pair in (doc['copyText'] as List).cast<List<dynamic>>()) {
      expect(mikraCopyText(pair[0] as String), pair[1]);
    }
  });

  test('העתקת פסקה: פתוחה באמצע פסוק היא שבירת שורה, ובסופו — כלום', () {
    final genesis = (doc['cases'] as List).cast<Map<String, dynamic>>()[1];
    final line = ((genesis['lines'] as List).cast<List<dynamic>>())
        .firstWhere((l) => l[0] == 1069)[2] as String;
    final copy = mikraCopyHtml(line);
    expect('<br>'.allMatches(copy).length, 1);
    expect(copy, isNot(contains('{פ}')));
    expect(copy, isNot(startsWith('(')));
  });
}
