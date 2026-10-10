import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text/ref_helper.dart';

// אורקל: הסריקה הרקורסיבית המקורית של closestTocEntryIndex.
int? _oracleClosest(List<TocEntry> entries, int targetIndex) {
  TocEntry? closest;
  void search(List<TocEntry> toc) {
    for (final entry in toc) {
      if (entry.index <= targetIndex) {
        if (closest == null || entry.index > closest!.index) {
          closest = entry;
        }
        search(entry.children);
      }
    }
  }

  search(entries);
  return closest?.index;
}

/// עץ אקראי: ילדים שהאינדקס שלהם קטן מזה של אביהם או מאחיו, כפילויות וקפיצות.
List<TocEntry> _randomToc(Random rnd, {required int size, required int lines}) {
  final roots = <TocEntry>[];
  final all = <TocEntry>[];
  var line = 0;
  for (var n = 0; n < size; n++) {
    final parent = all.isEmpty || rnd.nextInt(4) == 0
        ? null
        : all[all.length - 1 - rnd.nextInt(min(all.length, 6))];
    line = rnd.nextInt(5) == 0
        ? rnd.nextInt(lines)
        : min(lines, line + rnd.nextInt(4));
    final entry = TocEntry(
      text: '$n',
      index: line,
      level: rnd.nextInt(5),
      parent: parent,
    );
    (parent?.children ?? roots).add(entry);
    all.add(entry);
  }
  return roots;
}

void main() {
  test(
    'closestTocEntryIndex matches the recursive scan',
    () {
      final cases = <List<TocEntry>>[[]];
      // ילד שקטן מאביו נסרק רק משורת אביו.
      final parent = TocEntry(text: 'א', index: 10, level: 1);
      parent.children.addAll([
        TocEntry(text: 'ב', index: 5, level: 2, parent: parent),
        TocEntry(text: 'ג', index: 20, level: 2, parent: parent),
      ]);
      cases.add([parent, TocEntry(text: 'ד', index: 15, level: 1)]);
      const minInt = -0x8000000000000000;
      final lowest = [TocEntry(text: 'ה', index: minInt)];
      expect(
        closestTocEntryIndex(lowest, minInt),
        _oracleClosest(lowest, minInt),
      );
      final random = Random(3);
      for (var i = 0; i < 2000; i++) {
        cases.add(
          _randomToc(
            random,
            size: random.nextInt(40),
            lines: 1 + random.nextInt(60),
          ),
        );
      }
      for (final (n, toc) in cases.indexed) {
        final maxLine = flattenToc(toc).map((e) => e.index).fold(0, max);
        for (var i = -1; i <= maxLine + 1; i++) {
          expect(
            closestTocEntryIndex(toc, i),
            _oracleClosest(toc, i),
            reason: 'case $n, line $i',
          );
        }
      }
    },
  );
}
