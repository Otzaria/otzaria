import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/models/book_source.dart';
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

    test('מפרש ברמה 2 נחתך ל-15 קטעים, ומפרש חופשי נשאר שלם', () async {
      final groups = [
        _group('מוגן', [for (var i = 1; i <= 20; i++) _link('a/מוגן.txt', i)]),
        _group('חופשי', [
          for (var i = 1; i <= 20; i++) _link('a/חופשי.txt', i),
        ]),
      ];

      final blocks = await buildCommentaryPrintBlocks(
        groups,
        contentResolver: (link) async => 'קטע ${link.index2}',
        protectionResolver: (link) async => link.path2.contains('מוגן')
            ? const BookProtection(level: 2)
            : BookProtection.none,
      );

      // כותרת + 15 קטעים, ואז כותרת + 20 קטעים.
      expect(blocks, hasLength(1 + 15 + 1 + 20));
      expect(blocks[15].text, 'קטע 15');
      expect(blocks[16].text, 'חופשי');
    });

    test('טווח מקור ארוך נחתך לפני קריאת התוכן', () async {
      final range = Link(
        heRef: 'ref',
        index1: 1,
        path2: 'מוגן.txt',
        index2: 1,
        index2End: 20,
        targetBookId: 7,
        connectionType: 'COMMENTARY',
      );
      final blocks = await buildCommentaryPrintBlocks(
        [
          _group('מוגן', [range]),
        ],
        protectionResolver: (_) async => const BookProtection(level: 2),
        contentResolver: (link) async {
          expect(link.index2End, 15);
          expect(link.targetBookId, 7);
          return [
            for (var i = link.index2; i <= link.index2End!; i++)
              '<p>שורה $i<br>המשך $i</p>',
          ].join('<br>');
        },
      );
      expect(blocks, hasLength(2));
      expect(blocks.last.text, contains('שורה 15'));
      expect(blocks.last.text, isNot(contains('שורה 16')));
      expect(blocks.last.text, contains('המשך 15'));
    });

    test('אותו שם בשני מסדים ומפרש חופשי אינם חולקים מכסת הדפסה', () async {
      final links = [
        for (final source in [
          BookSource.official,
          BookSource.attached('extra'),
        ])
          Link(
            heRef: 'ref',
            index1: 1,
            path2: 'מפרש.txt',
            index2: 1,
            index2End: 20,
            targetBookId: 1,
            targetSource: source,
            connectionType: 'COMMENTARY',
          ),
      ];
      final blocks = await buildCommentaryPrintBlocks(
        [_group('מפרש', links)],
        protectionResolver: (link) async => link.targetSource.isOfficial
            ? const BookProtection(level: 2)
            : BookProtection.none,
        contentResolver: (link) async =>
            '${link.targetSource.wireKey}:${link.index2End}',
      );
      expect(blocks, hasLength(3));
      expect(blocks[1].text, endsWith(':15'));
      expect(blocks[2].text, endsWith(':20'));
    });

    test(
      'שני ספרים מוגנים באותו שם ממסדים שונים מקבלים 15 שורות כל אחד',
      () async {
        final links = [
          for (final source in [
            BookSource.official,
            BookSource.attached('extra'),
          ])
            Link(
              heRef: 'ref',
              index1: 1,
              path2: 'מפרש.txt',
              index2: 1,
              index2End: 20,
              targetBookId: 1,
              targetSource: source,
              connectionType: 'COMMENTARY',
            ),
        ];
        final blocks = await buildCommentaryPrintBlocks(
          [_group('מפרש', links)],
          protectionResolver: (_) async => const BookProtection(level: 2),
          contentResolver: (link) async =>
              '${link.targetSource.wireKey}:${link.index2End}',
        );
        expect(blocks, hasLength(3));
        expect(blocks[1].text, endsWith(':15'));
        expect(blocks[2].text, endsWith(':15'));
      },
    );

    test('מכסת אותו ספר נצברת גם כשהוא מפוצל לכמה קבוצות', () async {
      final blocks = await buildCommentaryPrintBlocks(
        [
          _group('מוגן', [for (var i = 1; i <= 10; i++) _link('מוגן.txt', i)]),
          _group('מוגן', [for (var i = 11; i <= 20; i++) _link('מוגן.txt', i)]),
        ],
        protectionResolver: (_) async => const BookProtection(level: 2),
        contentResolver: (link) async => 'שורה ${link.index2}',
      );
      expect(
        blocks.where((block) => block.kind == PrintBlockKind.commentary),
        hasLength(15),
      );
      expect(blocks.last.text, 'שורה 15');
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
