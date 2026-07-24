import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/utils/link_processing.dart';

Link makeLink({
  String heRef = 'בראשית א',
  int index1 = 1,
  String path2 = 'תנ"ך/ספר.txt',
  int index2 = 1,
  String connectionType = 'reference',
  int? start,
  int? end,
}) {
  return Link(
    heRef: heRef,
    index1: index1,
    path2: path2,
    index2: index2,
    connectionType: connectionType,
    start: start,
    end: end,
  );
}

void main() {
  group('mergeLinksByIdentity', () {
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
  });

  group('computeVisibleLinks', () {
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
