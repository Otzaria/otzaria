import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text/ref_helper.dart';

/// הסריקה הרקורסיבית המקורית של [refFromTocList], כמדד לשקילות.
String _referenceRef(int index, List<TocEntry> toc) {
  var texts = <String>[];
  void searchToc(List<TocEntry> entries) {
    for (final entry in entries) {
      if (entry.index > index) return;
      if (entry.level <= 0) {
        searchToc(entry.children);
        continue;
      }
      while (texts.length <= entry.level - 1) {
        texts.add('');
      }
      texts[entry.level - 1] = entry.text;
      texts = texts.getRange(0, entry.level).toList();
      searchToc(entry.children);
    }
  }

  searchToc(toc);
  return texts.map((e) => e.trim()).where((e) => e.isNotEmpty).join(', ');
}

List<TocEntry> _loadMikropediaToc() {
  final json =
      jsonDecode(
            File(
              'test/fixtures/toc/mikropedia_talmudit_toc.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final roots = <TocEntry>[];
  final stack = <TocEntry>[];
  for (final row in json['entries'] as List) {
    final [int level, int line, String text] = row as List;
    while (stack.isNotEmpty && stack.last.level >= level) {
      stack.removeLast();
    }
    final parent = stack.isEmpty ? null : stack.last;
    final entry = TocEntry(
      text: text,
      index: line,
      level: level,
      parent: parent,
    );
    (parent?.children ?? roots).add(entry);
    stack.add(entry);
  }
  return roots;
}

/// עץ אקראי: אחים ברמות שונות, רמות 0 ושליליות, דילוג רמות, אינדקסים לא
/// מונוטוניים, כפילויות וטקסטים ריקים — כמו התקלות שבנתוני המסד.
List<TocEntry> _randomToc(Random rnd, {required int size, required int lines}) {
  final roots = <TocEntry>[];
  final all = <TocEntry>[];
  var line = 0;
  for (var n = 0; n < size; n++) {
    final parent = all.isEmpty || rnd.nextInt(4) == 0
        ? null
        : all[all.length - 1 - rnd.nextInt(min(all.length, 6))];
    line = rnd.nextInt(8) == 0
        ? rnd.nextInt(lines)
        : min(lines, line + rnd.nextInt(4));
    final prefix = const ['', ' ', 'פרק', ' סימן א ', 'הלכה'][rnd.nextInt(5)];
    final entry = TocEntry(
      text: '$prefix$n',
      index: line,
      level: rnd.nextInt(7) - 1,
      parent: parent,
    );
    (parent?.children ?? roots).add(entry);
    all.add(entry);
  }
  return roots;
}

void main() {
  test('תוכן העניינים האמיתי של מיקרופדיה תלמודית — זהה בכל שורה', () {
    final toc = _loadMikropediaToc();
    final maxLine = flattenToc(toc).map((e) => e.index).reduce(max);
    for (var i = -1; i <= maxLine + 2; i++) {
      expect(refFromTocList(i, toc), _referenceRef(i, toc), reason: 'שורה $i');
    }
  });

  test('ילד שאחרי האח הבא של אביו (כמו בספר 7414) — זהה בכל שורה', () {
    final root = TocEntry(text: 'מיקרופדיה', index: 0);
    final a = TocEntry(text: 'אגרת', index: 10, level: 2, parent: root);
    final aChild = TocEntry(text: 'שאילת שלום', index: 21, level: 4, parent: a);
    final b = TocEntry(text: 'אגרת רשות', index: 15, level: 2, parent: root);
    final bChild = TocEntry(text: 'הכלל', index: 25, level: 3, parent: b);
    a.children.add(aChild);
    b.children.add(bChild);
    root.children.addAll([a, b]);
    final toc = [root];
    for (var i = 0; i <= 30; i++) {
      expect(refFromTocList(i, toc), _referenceRef(i, toc), reason: 'שורה $i');
    }
  });

  test('עצים אקראיים ברמות מעורבות — זהה בכל שורה', () {
    for (var seed = 0; seed < 300; seed++) {
      final rnd = Random(seed);
      final lines = 5 + rnd.nextInt(80);
      final toc = _randomToc(rnd, size: 1 + rnd.nextInt(60), lines: lines);
      for (var i = -1; i <= lines + 1; i++) {
        expect(
          refFromTocList(i, toc),
          _referenceRef(i, toc),
          reason: 'seed $seed, שורה $i',
        );
      }
    }
  });

  test('רשימה ריקה מחזירה מחרוזת ריקה', () {
    expect(refFromTocList(0, const []), '');
  });

  test('קריאות חוזרות על TOC גדול אינן סורקות את כל העץ בכל פעם', () {
    // ‏30 אלף כותרות, כמו בספרים הגדולים; הסריקה המלאה לוקחת ~1ms לקריאה.
    final toc = <TocEntry>[];
    for (var s = 0; s < 3000; s++) {
      final siman = TocEntry(text: 'סימן $s', index: s * 30, level: 2);
      for (var k = 0; k < 9; k++) {
        siman.children.add(
          TocEntry(
            text: 'סעיף $k',
            index: s * 30 + 1 + k * 3,
            level: 3,
            parent: siman,
          ),
        );
      }
      toc.add(siman);
    }
    final rnd = Random(1);
    final stopwatch = Stopwatch()..start();
    for (var n = 0; n < 2000; n++) {
      refFromTocList(rnd.nextInt(90000), toc);
    }
    expect(stopwatch.elapsedMilliseconds, lessThan(300));
  });
}
