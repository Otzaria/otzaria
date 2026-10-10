import 'dart:collection';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/view/commentary_list_base.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

Link _link(String path2, {int index2 = 1}) => Link(
  heRef: 'בראשית א',
  index1: 1,
  path2: path2,
  index2: index2,
  connectionType: 'commentary',
);

class _CountingLinks extends ListBase<Link> {
  final List<Link> links;
  int reads = 0;

  _CountingLinks(this.links);

  @override
  int get length => links.length;
  @override
  set length(int value) => throw UnsupportedError('read only');
  @override
  Link operator [](int index) {
    reads++;
    return links[index];
  }

  @override
  void operator []=(int index, Link value) =>
      throw UnsupportedError('read only');
}

void main() {
  group('pruneCommentaryExpansionStates', () {
    // המימוש הקודם, כאורקל: any() על כל הקישורים לכל מפתח.
    void oracle(Map<String, bool> states, List<Link> links) =>
        states.removeWhere(
          (key, _) =>
              !links.any((link) => key == utils.getTitleFromPath(link.path2)),
        );

    test('מפה ריקה אינה קוראת קישורים', () {
      final links = _CountingLinks([_link('רש"י.txt')]);
      pruneCommentaryExpansionStates({}, links);
      expect(links.reads, 0);
    });

    test('מפרש יחיד עוצר בקישור הראשון שלו', () {
      final links = _CountingLinks([
        for (var i = 0; i < 1000; i++) _link('רש"י.txt', index2: i + 1),
      ]);
      final states = {'רש"י': false};
      pruneCommentaryExpansionStates(states, links);
      expect(states, {'רש"י': false});
      expect(links.reads, 1);
    });

    test('עוצר כשכל המפתחות נמצאו גם עם כפילויות ומפתח ריק', () {
      final links = _CountingLinks([
        _link('רש"י.txt'),
        _link('רש"י.txt', index2: 2),
        _link(''),
        _link('רמב"ן.txt'),
        _link('ספורנו.txt'),
      ]);
      final states = {'רש"י': false, '': true, 'רמב"ן': true};
      pruneCommentaryExpansionStates(states, links);
      expect(states, {'רש"י': false, '': true, 'רמב"ן': true});
      expect(links.reads, 4);
    });

    test('מסיר רק מפרשים שאין להם קישור', () {
      final states = {'רש"י': true, 'רמב"ן': false, 'אבן עזרא': true};
      pruneCommentaryExpansionStates(states, [
        _link('תורה/רש"י על בראשית/רש"י.txt'),
        _link(r'C:\ספרים\אבן עזרא.txt'),
      ]);
      expect(states, {'רש"י': true, 'אבן עזרא': true});
    });

    test('זהה למימוש הקודם על קלטים אקראיים', () {
      final random = Random(42);
      const names = ['רש"י', 'רמב"ן', 'ספורנו', 'a.b', 'אור החיים', 'x'];
      const dirs = ['', 'תורה/', r'C:\ספרים\', 'א/ב/'];
      const exts = ['.txt', '.pdf', '', '.v2.txt'];
      for (var round = 0; round < 500; round++) {
        final links = [
          for (var i = random.nextInt(12); i > 0; i--)
            _link(
              '${dirs[random.nextInt(dirs.length)]}'
              '${names[random.nextInt(names.length)]}'
              '${exts[random.nextInt(exts.length)]}',
            ),
        ];
        final keys = [...names, 'a', 'x.txt', 'v2', ''];
        final states = {
          for (final key in keys)
            if (random.nextBool()) key: random.nextBool(),
        };
        final expected = Map.of(states);
        oracle(expected, links);
        pruneCommentaryExpansionStates(states, links);
        expect(states, expected, reason: 'round $round');
      }
    });
  });
}
