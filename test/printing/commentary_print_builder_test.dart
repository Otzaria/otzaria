import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/printing/commentary_print_builder.dart';
import 'package:otzaria/printing/print_content_models.dart';
import 'package:otzaria/services/commentary_service.dart';

Link _link(String path, int index2) => Link(
  heRef: 'ref',
  index1: 1,
  path2: path,
  index2: index2,
  connectionType: 'COMMENTARY',
);

LinkGroup _group(String title, List<Link> links) =>
    LinkGroup(bookTitle: title, links: links);

void main() {
  group('buildCommentaryPrintBlocks', () {
    test('בונה כותרת קבוצה ובלוק תוכן לכל קישור', () async {
      final groups = [
        _group('רש"י', [_link('a/רשי.txt', 1), _link('a/רשי.txt', 2)]),
        _group('רמב"ן', [_link('a/רמבן.txt', 1)]),
      ];

      final contents = {
        'a/רשי.txt:1': '<b>בראשית</b> ברא',
        'a/רשי.txt:2': 'את השמים',
        'a/רמבן.txt:1': 'דעת רבותינו',
      };

      final blocks = await buildCommentaryPrintBlocks(
        groups,
        contentResolver: (link) async =>
            contents['${link.path2}:${link.index2}']!,
      );

      expect(blocks, hasLength(5));
      expect(blocks[0].kind, PrintBlockKind.commentaryGroupTitle);
      expect(blocks[0].text, 'רש"י');
      expect(blocks[1].kind, PrintBlockKind.commentary);
      // ניקוי HTML
      expect(blocks[1].text, 'בראשית ברא');
      expect(blocks[2].text, 'את השמים');
      expect(blocks[3].kind, PrintBlockKind.commentaryGroupTitle);
      expect(blocks[3].text, 'רמב"ן');
      expect(blocks[4].text, 'דעת רבותינו');
    });

    test('מדלג על קישורים עם תוכן ריק', () async {
      final groups = [
        _group('רש"י', [_link('a/רשי.txt', 1), _link('a/רשי.txt', 2)]),
      ];

      final blocks = await buildCommentaryPrintBlocks(
        groups,
        contentResolver: (link) async => link.index2 == 1 ? 'תוכן' : '   ',
      );

      expect(blocks, hasLength(2));
      expect(blocks[0].kind, PrintBlockKind.commentaryGroupTitle);
      expect(blocks[1].text, 'תוכן');
    });

    test('מדלג על קבוצה שכל הקישורים בה ריקים (ללא כותרת)', () async {
      final groups = [
        _group('ריק', [_link('a/ריק.txt', 1)]),
        _group('מלא', [_link('a/מלא.txt', 1)]),
      ];

      final blocks = await buildCommentaryPrintBlocks(
        groups,
        contentResolver: (link) async => link.path2.contains('מלא') ? 'יש' : '',
      );

      expect(blocks, hasLength(2));
      expect(blocks[0].text, 'מלא');
      expect(blocks[1].text, 'יש');
    });

    test('שגיאה בטעינת תוכן לא מפילה את הבנייה', () async {
      final groups = [
        _group('רש"י', [_link('a/רשי.txt', 1), _link('a/רשי.txt', 2)]),
      ];

      final blocks = await buildCommentaryPrintBlocks(
        groups,
        contentResolver: (link) async {
          if (link.index2 == 1) throw StateError('fail');
          return 'תקין';
        },
      );

      expect(blocks, hasLength(2));
      expect(blocks[1].text, 'תקין');
    });

    test('רשימת קבוצות ריקה מחזירה בלוקים ריקים', () async {
      final blocks = await buildCommentaryPrintBlocks(
        const [],
        contentResolver: (link) async => 'x',
      );
      expect(blocks, isEmpty);
    });
  });
}
