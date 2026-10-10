import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/utils/link_processing.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

Link makeLink({
  String heRef = 'בראשית א',
  int index1 = 1,
  int? index1End,
  String path2 = 'תנ"ך/ספר.txt',
  int index2 = 1,
  String connectionType = 'reference',
  int? start,
  int? end,
  int baseProvenance = 0,
  BookSource targetSource = BookSource.official,
  int? targetCategoryId,
  int? anchorStart,
}) {
  return Link(
    heRef: heRef,
    index1: index1,
    index1End: index1End,
    path2: path2,
    index2: index2,
    connectionType: connectionType,
    start: start,
    end: end,
    baseProvenance: baseProvenance,
    targetSource: targetSource,
    targetCategoryId: targetCategoryId,
    anchorStart: anchorStart,
  );
}

void main() {
  group('mergeLinksByIdentity', () {
    test('שומר טווחים, עוגנים ויעדים שונים באותו זוג שורות', () {
      final links = [
        makeLink(index1End: 3),
        makeLink(index1End: 4),
        makeLink(anchorStart: 2),
        makeLink(anchorStart: 5),
        makeLink(targetSource: BookSource.user),
        makeLink(targetCategoryId: 7),
      ];
      expect(mergeLinksByIdentity([], links), hasLength(links.length));
    });

    test('ממזג קישורים ללא כפילויות לפי זהות', () {
      final existing = [makeLink(index1: 1), makeLink(index1: 2)];
      final incoming = [makeLink(index1: 1), makeLink(index1: 3)];

      final merged = mergeLinksByIdentity(existing, incoming);

      expect(merged, hasLength(3));
      expect(merged.map((l) => l.index1), [1, 2, 3]);
    });

    test('קישור נכנס מחליף קיים עם אותה זהות', () {
      final existing = [makeLink(index1: 1, heRef: 'ישן')];
      final incoming = [makeLink(index1: 1, heRef: 'חדש')];

      final merged = mergeLinksByIdentity(existing, incoming);

      expect(merged, hasLength(1));
      expect(merged.first.heRef, 'חדש');
    });

    test('קישור חלש אינו דורס provenance גבוה באותה זהות', () {
      final existing = [makeLink(baseProvenance: 2)];
      final incoming = [makeLink(baseProvenance: 0)];

      final merged = mergeLinksByIdentity(existing, incoming);

      expect(merged, hasLength(1));
      expect(merged.single.baseProvenance, 2);
    });

    test('קישורים עם start/end שונים נחשבים נפרדים', () {
      final merged = mergeLinksByIdentity(
        [makeLink(start: 0, end: 5)],
        [makeLink(start: 6, end: 10)],
      );
      expect(merged, hasLength(2));
    });

    test('התוצאה ממוינת לפי index1 ואז path2 ואז index2', () {
      final merged = mergeLinksByIdentity([], [
        makeLink(index1: 2, path2: 'א.txt', index2: 1),
        makeLink(index1: 1, path2: 'ב.txt', index2: 1),
        makeLink(index1: 1, path2: 'א.txt', index2: 2),
        makeLink(index1: 1, path2: 'א.txt', index2: 1),
      ]);

      expect(
        merged.map((l) => '${l.index1}|${l.path2}|${l.index2}').toList(),
        ['1|א.txt|1', '1|א.txt|2', '1|ב.txt|1', '2|א.txt|1'],
      );
    });
  });

  group('buildLinksByLineMap', () {
    test('טווח גדול מאונדקס ללא שכפול, כולל שורת אמצע וסוף', () {
      final link = makeLink(index1: 2, index1End: 1000000);
      final map = buildLinksByLineMap([link]);
      expect(map[1], isNull);
      expect(map[500000], [link]);
      expect(map[1000000], [link]);
      expect(map[1000001], isNull);
      expect(map.containsKey(500000), isTrue);
    });

    test('מחזיר טווחים חופפים בסדר המקורי ובמפתחות הפנימיים', () {
      final a = makeLink(index1: 1, index1End: 5);
      final b = makeLink(index1: 3);
      final c = makeLink(index1: 2, index1End: 4);
      final map = buildLinksByLineMap([a, b, c]);
      expect(map[3], [a, b, c]);
      expect(map.keys.toSet(), {1, 2, 3, 4, 5});
    });

    test('מקבץ קישורים לפי index1', () {
      final map = buildLinksByLineMap([
        makeLink(index1: 1),
        makeLink(index1: 1, index2: 2),
        makeLink(index1: 5),
      ]);

      expect(map[1], hasLength(2));
      expect(map[5], hasLength(1));
      expect(map[2], isNull);
    });

    test('תוצאה זהה לחיפוש נאיבי גם בשאילתה חוזרת לאותה שורה', () {
      final random = Random(7);
      final links = [
        for (var i = 0; i < 2000; i++)
          makeLink(
            index1: random.nextInt(300),
            index1End: random.nextInt(4) == 0 ? 300 + random.nextInt(50) : null,
            index2: i,
          ),
      ];
      List<Link>? naive(int line) {
        final found = [
          for (final link in links)
            if (link.index1 == line ||
                (link.index1 < line && (link.index1End ?? 0) >= line))
              link,
        ];
        return found.isEmpty ? null : found;
      }

      final map = buildLinksByLineMap(links);
      for (var pass = 0; pass < 2; pass++) {
        for (var line = -1; line <= 360; line++) {
          expect(map[line], naive(line), reason: 'line $line pass $pass');
        }
      }
    });
  });

  group('computeVisibleLinks', () {
    test('קישור טווח המופיע בשתי שורות נראות נכלל פעם אחת', () {
      final link = makeLink(index1: 2, index1End: 4);
      final visible = computeVisibleLinks(
        links: [link],
        visibleIndices: const [1, 2, 3],
        selectedIndices: const {},
        linksByLine: buildLinksByLineMap([link]),
      );
      expect(visible, [link]);
    });

    test('מחזיר רק קישורים שאינם פרשנות/תרגום ושאינם מבוססי-תווים', () {
      final links = [
        makeLink(index1: 1, connectionType: 'reference'),
        makeLink(index1: 1, connectionType: 'commentary', index2: 2),
        makeLink(index1: 1, connectionType: 'targum', index2: 3),
        makeLink(index1: 1, start: 0, end: 5, index2: 4),
      ];

      final visible = computeVisibleLinks(
        links: links,
        visibleIndices: [0],
        selectedIndices: const {},
        linksByLine: buildLinksByLineMap(links),
      );

      expect(visible, hasLength(1));
      expect(visible.first.connectionType, 'reference');
    });

    test('האינדקסים הגלויים מומרים לשורות 1-based', () {
      final links = [makeLink(index1: 3)];

      final visible = computeVisibleLinks(
        links: links,
        visibleIndices: [2],
        selectedIndices: const {},
        linksByLine: buildLinksByLineMap(links),
      );

      expect(visible, hasLength(1));
    });

    test('selectedIndices גובר על visibleIndices', () {
      final links = [makeLink(index1: 1), makeLink(index1: 5)];
      final byLine = buildLinksByLineMap(links);

      final visible = computeVisibleLinks(
        links: links,
        visibleIndices: [0],
        selectedIndices: const {4},
        linksByLine: byLine,
      );

      expect(visible, hasLength(1));
      expect(visible.first.index1, 5);
    });

    test('ריבוי קטעים נבחרים מאחד קישורים מכל הקטעים', () {
      final links = [
        makeLink(index1: 1),
        makeLink(index1: 5, index2: 2),
        makeLink(index1: 9, index2: 3),
      ];
      final byLine = buildLinksByLineMap(links);

      final visible = computeVisibleLinks(
        links: links,
        visibleIndices: const [],
        selectedIndices: const {0, 4},
        linksByLine: byLine,
      );

      // index1 הוא 1-based: הקטעים 0 ו-4 ממופים לשורות 1 ו-5 (9 לא נבחר).
      expect(visible.map((l) => l.index1).toSet(), {1, 5});
    });

    test('התוצאה ממוינת לפי שם הספר מהנתיב', () {
      final links = [
        makeLink(index1: 1, path2: 'דרך/בבב.txt'),
        makeLink(index1: 1, path2: 'דרך/אאא.txt', index2: 2),
      ];

      final visible = computeVisibleLinks(
        links: links,
        visibleIndices: [0],
        selectedIndices: const {},
        linksByLine: buildLinksByLineMap(links),
      );

      expect(visible.map((l) => l.path2).toList(), [
        'דרך/אאא.txt',
        'דרך/בבב.txt',
      ]);
    });

    test('מיון לפי כותרות מחושבות מראש זהה למיון עם חיפוש במפה (perf)', () {
      final rnd = Random(7);
      const types = ['reference', 'commentary', 'targum', 'other'];
      final links = [
        for (var i = 0; i < 2000; i++)
          makeLink(
            index1: 1 + rnd.nextInt(60),
            index1End: rnd.nextInt(5) == 0 ? 61 + rnd.nextInt(5) : null,
            // מעט שמות — הרבה כותרות שוות, כדי לבדוק גם את סדר השווים.
            path2:
                'ספרים/${rnd.nextBool() ? 'א' : 'ב'}/ספר ${rnd.nextInt(30)}.txt',
            index2: i,
            connectionType: types[rnd.nextInt(types.length)],
            start: rnd.nextInt(8) == 0 ? 0 : null,
          ),
      ];
      final linksByLine = buildLinksByLineMap(links);
      for (final selected in [
        <int>{},
        {3, 1, 40},
      ]) {
        final visibleIndices = [for (var i = 0; i < 70; i += 2) i];
        final expected = <Link>[];
        final seen = <Link>{};
        for (final index in selected.isNotEmpty ? selected : visibleIndices) {
          for (final link in linksByLine[index + 1] ?? const <Link>[]) {
            if (!LinkTypes.isDependentTextLink(link.connectionType) &&
                link.start == null &&
                link.end == null &&
                seen.add(link)) {
              expected.add(link);
            }
          }
        }
        final titles = {for (final l in expected) l: getTitleFromPath(l.path2)};
        expected.sort((a, b) => titles[a]!.compareTo(titles[b]!));

        final actual = computeVisibleLinks(
          links: links,
          visibleIndices: visibleIndices,
          selectedIndices: selected,
          linksByLine: linksByLine,
        );

        expect(actual.length, expected.length);
        for (var i = 0; i < expected.length; i++) {
          expect(identical(actual[i], expected[i]), isTrue, reason: 'מיקום $i');
        }
      }
    });
  });

  group('processLinksForState', () {
    test('מסלול סינכרוני: ממזג ומחשב קישורים גלויים', () async {
      final result = await processLinksForState(
        existingLinks: [makeLink(index1: 1)],
        incomingLinks: [makeLink(index1: 2)],
        replaceExisting: false,
        visibleIndices: [0, 1],
        selectedIndices: const {},
      );

      expect(result.links, hasLength(2));
      expect(result.linksByLine[1], hasLength(1));
      expect(result.visibleLinks, hasLength(2));
    });

    test('replaceExisting מתעלם מהקישורים הקיימים', () async {
      final result = await processLinksForState(
        existingLinks: [makeLink(index1: 1)],
        incomingLinks: [makeLink(index1: 2)],
        replaceExisting: true,
        visibleIndices: [0, 1],
        selectedIndices: const {},
      );

      expect(result.links, hasLength(1));
      expect(result.links.first.index1, 2);
    });

    test('מעל סף 250 קישורים העיבוד עובר ב-isolate ומחזיר תוצאה זהה', () async {
      final incoming = [
        for (var i = 1; i <= 300; i++) makeLink(index1: i, index2: i),
      ];

      final result = await processLinksForState(
        existingLinks: const [],
        incomingLinks: incoming,
        replaceExisting: false,
        visibleIndices: [0],
        selectedIndices: const {},
      );

      expect(result.links, hasLength(300));
      expect(result.visibleLinks, hasLength(1));
      expect(result.visibleLinks.first.index1, 1);
    });

    test('מסלול isolate שומר provenance גבוה מול קישור נכנס זהה', () async {
      final result = await processLinksForState(
        existingLinks: [
          makeLink(index1: 1, baseProvenance: 2),
          for (var i = 2; i <= 251; i++) makeLink(index1: i, index2: i),
        ],
        incomingLinks: [makeLink(index1: 1, baseProvenance: 0)],
        replaceExisting: false,
        visibleIndices: [0],
        selectedIndices: const {},
      );

      expect(
        result.links.singleWhere((link) => link.index1 == 1).baseProvenance,
        2,
      );
    });
  });

  group('buildPreviewLines', () {
    test('ללא היסט מחזיר את השורות כמו שהן', () {
      expect(buildPreviewLines('א\nב', 0), ['א', 'ב']);
    });

    test('היסט חיובי מוסיף שורות ריקות בתחילה', () {
      expect(buildPreviewLines('א\nב', 2), ['', '', 'א', 'ב']);
    });
  });

  group('splitContentLines', () {
    test('תוכן ריק מחזיר רשימה ריקה', () async {
      expect(await splitContentLines(''), isEmpty);
    });

    test('מפצל תוכן לפי שורות ב-isolate', () async {
      expect(await splitContentLines('א\nב\nג'), ['א', 'ב', 'ג']);
    });
  });
}
