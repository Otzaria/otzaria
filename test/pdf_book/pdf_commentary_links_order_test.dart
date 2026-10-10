import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/pdf_book/view/pdf_commentary_panel.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

Link _link(String path2, int index1, int index2) => Link(
  heRef: path2,
  index1: index1,
  path2: path2,
  index2: index2,
  connectionType: 'commentary',
);

void main() {
  test('קטעי מפרש על אותה שורה ממוינים לפי שורת היעד (#1330)', () {
    // מעל 32 פריטים המיון של Dart עובר ל-quicksort לא יציב.
    final expected = [
      for (var line = 1; line <= 20; line++)
        for (var target = 0; target < 3; target++)
          _link('חברותא על סנהדרין', line, line * 10 + target),
      _link('רש"י על סנהדרין', 1, 5),
      _link('רש"י על סנהדרין', 1, 6),
    ];

    for (var seed = 0; seed < 20; seed++) {
      final links = [...expected]..shuffle(Random(seed));
      links.sort(comparePdfCommentaryLinks);
      expect(
        links.map((l) => '${l.path2}|${l.index1}|${l.index2}').toList(),
        expected.map((l) => '${l.path2}|${l.index1}|${l.index2}').toList(),
        reason: 'seed $seed',
      );
    }
  });

  test('ההשוואה זהה להשוואה לפי שם המפרש מהנתיב, גם בקריאה חוזרת', () {
    int naive(Link a, Link b) {
      final byTitle = getTitleFromPath(
        a.path2,
      ).compareTo(getTitleFromPath(b.path2));
      if (byTitle != 0) return byTitle;
      final bySource = a.index1.compareTo(b.index1);
      return bySource != 0 ? bySource : a.index2.compareTo(b.index2);
    }

    const paths = [
      'רש"י על ברכות',
      'מפרשים/תוספות על ברכות.txt',
      r'C:\ספרים\מהרש"א.txt',
      'א/ב.ג/ד',
      '.txt',
      '',
      'תוספות על ברכות',
    ];
    final random = Random(11);
    final links = [
      for (var i = 0; i < 300; i++)
        _link(
          paths[random.nextInt(paths.length)],
          random.nextInt(5),
          random.nextInt(5),
        ),
    ];
    for (var n = 0; n < 2000; n++) {
      final a = links[random.nextInt(links.length)];
      final b = links[random.nextInt(links.length)];
      expect(
        comparePdfCommentaryLinks(a, b).sign,
        naive(a, b).sign,
        reason: '${a.path2} ${b.path2}',
      );
    }
    final sorted = [...links]..sort(comparePdfCommentaryLinks);
    for (var i = 1; i < sorted.length; i++) {
      expect(naive(sorted[i - 1], sorted[i]), lessThanOrEqualTo(0));
    }
  });
}
