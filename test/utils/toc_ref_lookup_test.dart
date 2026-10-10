import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text/ref_helper.dart';

class _CountedEntry extends TocEntry {
  static int reads = 0;
  _CountedEntry(String text, int index, int level)
    : super(text: text, index: index, level: level);

  @override
  int get level {
    reads++;
    return super.level;
  }
}

String _scan(int index, List<TocEntry> toc) {
  final texts = <String>[];
  void visit(List<TocEntry> entries) {
    for (final entry in entries) {
      if (entry.index > index) return;
      if (entry.level > 0) {
        while (texts.length < entry.level) {
          texts.add('');
        }
        texts[entry.level - 1] = entry.text;
        texts.length = entry.level;
      }
      visit(entry.children);
    }
  }

  visit(toc);
  return texts
      .map((text) => text.trim())
      .where((text) => text.isNotEmpty)
      .join(', ');
}

void main() {
  test('חיפוש חוזר מדלג על ענף רחב שאינו פעיל', () {
    final root = _CountedEntry('חלק', 0, 1);
    root.children = List.generate(
      30000,
      (i) => _CountedEntry('פרק $i', 100, 2),
    );
    final toc = <TocEntry>[root, _CountedEntry('סעיף', 15, 3)];
    expect(refFromTocList(15, toc), _scan(15, toc));
    _CountedEntry.reads = 0;
    for (var i = 0; i < 20; i++) {
      expect(refFromTocList(15, toc), 'חלק, סעיף');
    }
    expect(_CountedEntry.reads, lessThan(1000));
  });

  test('עומק גדול ורמות קצה אינם מוגבלים על ידי מבנה החיפוש', () {
    final root = TocEntry(text: 'ראשון', index: -0x8000000000000000);
    var parent = root;
    for (var i = 0; i < 10000; i++) {
      final child = TocEntry(text: 'כותרת $i', index: 0, parent: parent);
      parent.children.add(child);
      parent = child;
    }
    final toc = [root];
    expect(refFromTocList(-0x8000000000000000, toc), 'ראשון');
    expect(refFromTocList(0, toc), 'כותרת 9999');
    expect(
      refFromTocList(0, [TocEntry(text: 'גבוה', index: 0, level: 1 << 30)]),
      'גבוה',
    );
  });

  test('שקילות בכל שורה בתוכן העניינים האמיתי של מיקרופדיה', () {
    final data =
        jsonDecode(
              File(
                'test/fixtures/toc/mikropedia_talmudit_toc.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final toc = <TocEntry>[];
    final stack = <TocEntry>[];
    var lastIndex = 0;
    for (final row in data['entries'] as List) {
      final level = row[0] as int;
      final index = row[1] as int;
      while (stack.isNotEmpty && stack.last.level >= level) {
        stack.removeLast();
      }
      final parent = stack.lastOrNull;
      final entry = TocEntry(
        text: row[2] as String,
        index: index,
        level: level,
        parent: parent,
      );
      (parent?.children ?? toc).add(entry);
      stack.add(entry);
      lastIndex = max(lastIndex, index);
    }
    for (var index = -1; index <= lastIndex + 1; index++) {
      expect(
        refFromTocList(index, toc),
        _scan(index, toc),
        reason: 'index=$index',
      );
    }
  });

  test('שקילות לסריקה בכל שורה בעצים עם אינדקסים ורמות חריגים', () {
    final random = Random(1832);
    for (var tree = 0; tree < 500; tree++) {
      final toc = <TocEntry>[];
      final entries = <TocEntry>[];
      for (var i = 0; i < 80; i++) {
        final parent = entries.isEmpty || random.nextInt(4) == 0
            ? null
            : entries[random.nextInt(entries.length)];
        final entry = TocEntry(
          text: i % 7 == 0 ? ' ' : ' כותרת $i ',
          index: random.nextInt(41) - 10,
          level: random.nextInt(9) - 2,
          parent: parent,
        );
        (parent?.children ?? toc).add(entry);
        entries.add(entry);
      }
      for (var index = -11; index <= 41; index++) {
        expect(
          refFromTocList(index, toc),
          _scan(index, toc),
          reason: 'tree=$tree index=$index',
        );
      }
    }
    expect(refFromTocList(0, []), '');
  });
}
