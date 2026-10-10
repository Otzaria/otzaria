import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/book_common/utils/commentary_flat_items.dart';
import 'package:otzaria/services/commentary_service.dart';

Link _link(String path2, int index2) => Link(
  heRef: '$path2 $index2',
  index1: 1,
  path2: path2,
  index2: index2,
  connectionType: 'commentary',
);

String _key(Link link) => '${link.index1}_${link.path2}_${link.index2}';

void main() {
  final rashi = LinkGroup(
    bookTitle: 'רש"י',
    links: [_link('רש"י', 3), _link('רש"י', 4)],
  );
  final ramban = LinkGroup(
    bookTitle: 'רמב"ן',
    links: [_link('רמב"ן', 7)],
  );

  group('buildCommentaryFlatItems', () {
    test('קבוצות מורחבות — כותרת + פריט לכל קטע, מפריד רק על האחרון', () {
      final headerIdx = <String, int>{};
      final linkIdx = <String, int>{};
      final items = buildCommentaryFlatItems(
        groups: [rashi, ramban],
        isGroupExpanded: (_) => true,
        linkKey: _key,
        headerIndexOut: headerIdx,
        linkIndexOut: linkIdx,
      );

      expect(items, hasLength(5));
      expect(items[0].link, isNull);
      expect(items[0].showDivider, isFalse);
      expect(items[1].link, same(rashi.links[0]));
      expect(items[1].showDivider, isFalse);
      expect(items[2].link, same(rashi.links[1]));
      expect(items[2].showDivider, isTrue);
      expect(items[3].link, isNull);
      expect(items[4].link, same(ramban.links[0]));
      expect(items[4].showDivider, isTrue);

      expect(headerIdx, {'רש"י': 0, 'רמב"ן': 3});
      expect(linkIdx, {
        _key(rashi.links[0]): 1,
        _key(rashi.links[1]): 2,
        _key(ramban.links[0]): 4,
      });
    });

    test('קבוצה מכווצת — כותרת בלבד עם מפריד, והקטעים אינם ממופים', () {
      final headerIdx = <String, int>{};
      final linkIdx = <String, int>{};
      final items = buildCommentaryFlatItems(
        groups: [rashi, ramban],
        isGroupExpanded: (title) => title != 'רש"י',
        linkKey: _key,
        headerIndexOut: headerIdx,
        linkIndexOut: linkIdx,
      );

      expect(items, hasLength(3));
      expect(items[0].link, isNull);
      expect(items[0].showDivider, isTrue);
      expect(items[1].link, isNull);
      expect(items[2].link, same(ramban.links[0]));

      expect(headerIdx, {'רש"י': 0, 'רמב"ן': 1});
      expect(linkIdx, {_key(ramban.links[0]): 2});
    });

    test('קבוצה מורחבת ללא קטעים — כותרת ללא מפריד (אין פריט אחרון)', () {
      final items = buildCommentaryFlatItems(
        groups: [const LinkGroup(bookTitle: 'ריק', links: [])],
        isGroupExpanded: (_) => true,
        linkKey: _key,
        headerIndexOut: {},
        linkIndexOut: {},
      );

      expect(items, hasLength(1));
      expect(items[0].showDivider, isFalse);
    });
  });
}
