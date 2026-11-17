import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/view/page_shape/utils/super_commentary_links.dart';

const _main = 'שולחן ערוך, אורח חיים';
const _parent = 'משנה ברורה';
const _super = 'שער הציון';

Link _link(
  String target,
  int index1,
  int index2, {
  String type = 'COMMENTARY',
  int? index1End,
  int? index2End,
}) => Link(
  heRef: '$target $index2',
  index1: index1,
  index1End: index1End,
  path2: target,
  index2: index2,
  index2End: index2End,
  connectionType: type,
  targetCategoryId: 703,
);

void main() {
  group('superCommentatorTitles', () {
    test('מחזיר יעדים תלויי-טקסט שאינם הספר הראשי ואינם מפרשיו הישירים', () {
      final titles = superCommentatorTitles(
        parentTargets: const [
          LinkTargetSummary(
            targetTitle: _super,
            connectionType: 'COMMENTARY',
            linkCount: 17980,
          ),
          LinkTargetSummary(
            targetTitle: _main,
            connectionType: 'COMMENTARY',
            linkCount: 3,
          ),
          LinkTargetSummary(
            targetTitle: 'ביאור הלכה',
            connectionType: 'COMMENTARY',
            linkCount: 50,
          ),
          LinkTargetSummary(
            targetTitle: 'בבלי ברכות',
            connectionType: 'LINKER',
            linkCount: 9,
          ),
        ],
        mainBookTitle: _main,
        directCommentators: const [_parent, 'ביאור הלכה'],
      );
      expect(titles, {_super});
    });
  });

  test('superCommentatorParents משייך מפרש-על למפרש הראשון שבסדר', () {
    expect(
      superCommentatorParents(
        const ['א', 'ב'],
        const {
          'א': {'על א'},
          'ב': {'על א', 'על ב'},
        },
      ),
      {'על א': 'א', 'על ב': 'ב'},
    );
  });

  group('composeSuperCommentaryLinks', () {
    test('מרכיב ראשי←מפרש-על דרך שורת המפרש, ממוין ובלי כפילויות', () {
      final composed = composeSuperCommentaryLinks(
        mainToParent: [
          // סימן א סעיף א: שורת שו"ע 5 → משנ"ב 30..31
          _link(_parent, 5, 30),
          _link(_parent, 5, 31),
          _link(_parent, 7, 40, index2End: 41),
          _link(_parent, 9, 50, type: 'REFERENCE'),
          _link('ביאור הלכה', 9, 30),
        ],
        parentToSuper: [
          _link(_super, 30, 4),
          _link(_super, 31, 4),
          _link(_super, 41, 6),
          _link(_super, 50, 9),
          _link('בבלי ברכות', 30, 2, type: 'LINKER'),
        ],
        parentTitle: _parent,
        superTitle: _super,
      );
      expect(
        composed.map((link) => (link.index1, link.index2, link.path2)),
        [(5, 4, _super), (7, 6, _super)],
      );
      expect(composed.first.heRef, '$_super 4');
    });

    test('קישור מפרש-על שמכסה טווח שורות מפרש נמצא מכל שורה בטווח', () {
      final composed = composeSuperCommentaryLinks(
        mainToParent: [_link(_parent, 12, 61)],
        parentToSuper: [_link(_super, 60, 8, index1End: 62)],
        parentTitle: _parent,
        superTitle: _super,
      );
      expect(composed.single.index1, 12);
      expect(composed.single.index2, 8);
    });

    test('קישור כפול נבחר לפי סדר הקישור הראשי, שורת החפיפה וסדר הקלט', () {
      final composed = composeSuperCommentaryLinks(
        mainToParent: [
          _link(_parent, 12, 60, index1End: 15, index2End: 64),
          _link(_parent, 12, 30, index1End: 16),
        ],
        parentToSuper: [
          _link(_super, 62, 8, index2End: 80),
          _link(_super, 59, 8, index1End: 60, index2End: 81),
          _link(_super, 55, 8, index1End: 64, index2End: 82),
          _link(_super, 30, 8, index2End: 83),
          _link(_super, 30, 9),
        ],
        parentTitle: _parent,
        superTitle: _super,
      );
      expect(
        composed.map((link) => (link.index1End, link.index2, link.index2End)),
        [(15, 8, 81), (16, 9, null)],
      );
    });

    test('חפיפה בטווח של מיליוני שורות שומרת גבולות כלולים', () {
      final composed = composeSuperCommentaryLinks(
        mainToParent: [
          _link(_parent, 12, 2_000_000, index2End: 8_000_000),
          _link(_parent, 14, 3, index2End: 2),
        ],
        parentToSuper: [
          _link(_super, 8_000_000, 8, index1End: 8_025_000),
          _link(_super, 1_975_000, 9, index1End: 2_000_000),
          _link(_super, 8_000_001, 10, index1End: 8_000_002),
          _link(_super, 4_000_000, 11, index1End: 3_000_000),
        ],
        parentTitle: _parent,
        superTitle: _super,
      );
      expect(composed.map((link) => (link.index1, link.index2)), [
        (12, 8),
        (12, 9),
      ]);
    });
  });

  test(
    'rapid distant navigation coalesces pending ranges to the latest target',
    () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      final calls = <int>[];
      final loader = SuperCommentaryLinkLoader(
        mainTitle: 'main',
        mainCategoryId: 1,
        mainSource: BookSource.official,
        parentTitle: 'parent',
        superTitle: 'super',
        windowLines: 10,
        reloadThresholdLines: 2,
        fetch:
            ({
              required bookTitle,
              required categoryId,
              required source,
              required startLine,
              required endLine,
              required targetTitle,
            }) async {
              calls.add(startLine);
              if (calls.length == 1) {
                started.complete();
                await gate.future;
              }
              return <Link>[];
            },
      );
      final first = loader.ensureLoaded(0, 10000);
      await started.future;
      final pending = [
        for (var line = 1000; line <= 9000; line += 1000)
          loader.ensureLoaded(line, 10000),
      ];
      gate.complete();
      await Future.wait([first, ...pending]);
      expect(
        calls,
        [0, 8990],
        reason:
            'the final viewport should not wait for eight stale range queries',
      );
    },
  );
  test('כשל בפעילה משלים בקשות שבוטלו ושומר השהיה ליעד העדכני', () async {
    final gate = Completer<void>();
    final calls = <int>[];
    var now = DateTime(2026);
    final loader = SuperCommentaryLinkLoader(
      mainTitle: _main,
      mainCategoryId: 1,
      mainSource: BookSource.official,
      parentTitle: _parent,
      superTitle: _super,
      windowLines: 10,
      now: () => now,
      fetch:
          ({
            required bookTitle,
            required categoryId,
            required source,
            required startLine,
            required endLine,
            required targetTitle,
          }) async {
            calls.add(startLine);
            if (calls.length == 1) {
              await gate.future;
              throw StateError('db closed');
            }
            return const [];
          },
    );
    final failed = expectLater(loader.ensureLoaded(0, 10000), throwsStateError);
    final stale = loader.ensureLoaded(1000, 10000);
    final latest = loader.ensureLoaded(9000, 10000);
    gate.complete();
    await failed;
    expect(await Future.wait([stale, latest]), [false, false]);
    expect(calls, [0]);
    now = now.add(const Duration(seconds: 3));
    expect(await loader.ensureLoaded(9000, 10000), isFalse);
    expect(calls, [0, 8990]);
  });

  group('SuperCommentaryLinkLoader', () {
    late List<({String book, int start, int end, String target})> calls;

    SuperCommentaryLinkLoader loader() => SuperCommentaryLinkLoader(
      mainTitle: _main,
      mainCategoryId: 1,
      mainSource: BookSource.official,
      parentTitle: _parent,
      superTitle: _super,
      windowLines: 10,
      reloadThresholdLines: 2,
      fetch:
          ({
            required bookTitle,
            required categoryId,
            required source,
            required startLine,
            required endLine,
            required targetTitle,
          }) async {
            calls.add((
              book: bookTitle,
              start: startLine,
              end: endLine,
              target: targetTitle,
            ));
            if (bookTitle == _main) {
              return [
                for (var line = startLine; line <= endLine; line++)
                  _link(_parent, line + 1, (line + 1) * 2),
              ];
            }
            expect(categoryId, 703);
            return [
              for (var line = startLine; line <= endLine; line++)
                if (line.isOdd) _link(_super, line + 1, line + 100),
            ];
          },
    );

    setUp(() => calls = []);

    test(
      'טוען חלון סביב השורה: ראשי←מפרש ואז מפרש←מפרש-על בטווח שעלה',
      () async {
        final links = loader();
        expect(await links.ensureLoaded(20, 1000), isTrue);
        expect(calls, [
          (book: _main, start: 10, end: 30, target: _parent),
          (book: _parent, start: 21, end: 61, target: _super),
        ]);
        expect(links.links, isNotEmpty);
        expect(
          links.links.every((link) => link.index2 == link.index1 * 2 - 1 + 100),
          isTrue,
        );
      },
    );

    test('שורה בתוך החלון הטעון אינה שולפת שוב; קצה הספר אינו לולאה', () async {
      final links = loader();
      await links.ensureLoaded(20, 1000);
      expect(await links.ensureLoaded(25, 1000), isFalse);
      expect(calls, hasLength(2));

      await links.ensureLoaded(995, 1000);
      final count = calls.length;
      expect(await links.ensureLoaded(999, 1000), isFalse);
      expect(calls, hasLength(count));
    });

    test('קריאות מקבילות לאותו חלון שולפות פעם אחת', () async {
      final links = loader();
      final results = await Future.wait([
        links.ensureLoaded(20, 1000),
        links.ensureLoaded(20, 1000),
      ]);
      expect(results, [true, false]);
      expect(calls, hasLength(2));
    });

    test('כשל נרשם: השהיה, ניסיון חוזר ועצירה אחרי המגבלה', () async {
      var now = DateTime(2026);
      var failing = true;
      var fetches = 0;
      final links = SuperCommentaryLinkLoader(
        mainTitle: _main,
        mainCategoryId: 1,
        mainSource: BookSource.official,
        parentTitle: _parent,
        superTitle: _super,
        maxFailures: 2,
        retryBackoff: const Duration(seconds: 2),
        now: () => now,
        fetch:
            ({
              required bookTitle,
              required categoryId,
              required source,
              required startLine,
              required endLine,
              required targetTitle,
            }) async {
              fetches++;
              if (failing) throw StateError('db closed');
              return const [];
            },
      );

      await expectLater(links.ensureLoaded(5, 100), throwsStateError);
      expect(fetches, 1);
      expect(await links.ensureLoaded(5, 100), isFalse, reason: 'בהשהיה');
      expect(fetches, 1);

      now = now.add(const Duration(seconds: 3));
      await expectLater(links.ensureLoaded(5, 100), throwsStateError);
      expect(fetches, 2);

      now = now.add(const Duration(minutes: 5));
      failing = false;
      expect(await links.ensureLoaded(5, 100), isFalse, reason: 'נעצר');
      expect(fetches, 2);
    });
  });
}
