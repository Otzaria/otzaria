import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/utils/link_anchor_markers.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/text_book/utils/inline_notes_utils.dart';

BookNote _note(int noteIndex, int charPos, String body, {String? marker}) =>
    (noteIndex: noteIndex, charPos: charPos, marker: marker, body: body);

LinkAnchorSpan _range(int start, int end) =>
    LinkAnchorSpan(start: start, end: end);

List<(int, int?)> _pairs(List<LinkAnchorSpan> spans) => [
  for (final span in spans) (span.start, span.end),
];

Link _linker(int start, int end) => Link(
  heRef: 'בראשית א, א',
  index1: 1,
  path2: 'בראשית',
  index2: 1,
  connectionType: 'LINKER',
  anchorStart: start,
  anchorEnd: end,
);

/// התווים הגלויים כפי ש-visibleCharCount סופר אותם (entity אחד = תו אחד).
List<String> _units(String html) {
  final units = <String>[];
  var i = 0;
  while (i < html.length) {
    if (html[i] == '<') {
      final close = html.indexOf('>', i);
      if (close < 0) break;
      i = close + 1;
    } else if (html[i] == '&') {
      final j = html.indexOf(';', i + 1);
      final end = j > 0 && j < i + 10 && j < html.length ? j + 1 : i + 1;
      units.add(html.substring(i, end));
      i = end;
    } else {
      units.add(html[i]);
      i++;
    }
  }
  return units;
}

List<LinkAnchorSpan> _referenceProjection(
  List<LinkAnchorSpan> spans,
  List<BookNote> notes, {
  int? note,
}) {
  if (notes.isEmpty) return note == null ? spans : const [];
  if (note != null && (note < 0 || note >= notes.length)) return const [];
  if (notes.any((n) => n.charPos < 0)) return const [];
  // גוף k תופס בשורה המלאה את [starts[k], ends[k]).
  final starts = List<int>.filled(notes.length, 0);
  final ends = List<int>.filled(notes.length, 0);
  var before = 0;
  for (var k = 0; k < notes.length; k++) {
    starts[k] = notes[k].charPos + before;
    before += visibleCharCount(notes[k].body);
    ends[k] = notes[k].charPos + before;
  }
  bool inside(int at, int k) => starts[k] < at && at < ends[k];
  int stored(int at) {
    var shift = 0;
    for (var k = 0; k < notes.length && starts[k] < at; k++) {
      if (at < ends[k]) return starts[k] - shift;
      shift += ends[k] - starts[k];
    }
    return at - shift;
  }

  final result = <LinkAnchorSpan>[];
  for (final span in spans) {
    final end = span.end;
    if (note != null) {
      final from = starts[note];
      if (end == null) {
        if (inside(span.start, note)) {
          result.add(
            LinkAnchorSpan(start: span.start - from, label: span.label),
          );
        }
      } else {
        final a = span.start > from ? span.start : from;
        final b = end < ends[note] ? end : ends[note];
        if (b > a) {
          result.add(
            LinkAnchorSpan(start: a - from, end: b - from, label: span.label),
          );
        }
      }
    } else if (end == null) {
      var inBody = false;
      for (var k = 0; k < notes.length && !inBody; k++) {
        inBody = inside(span.start, k);
      }
      if (!inBody) {
        result.add(
          LinkAnchorSpan(start: stored(span.start), label: span.label),
        );
      }
    } else {
      final a = stored(span.start);
      final b = stored(end);
      if (b > a) {
        result.add(LinkAnchorSpan(start: a, end: b, label: span.label));
      }
    }
  }
  return result;
}

void main() {
  // השורה המלאה: "אב" + "1" + [גוף "גד" ב-3..5] + "הו" + [גוף "זחט" ב-7..10] + "יכ".
  final notes = [_note(0, 3, 'ג<b>ד</b>', marker: '1'), _note(1, 5, 'זחט')];

  group('projectAnchorSpans', () {
    test('בלי הערות — העוגן כמות שהוא, ואין חלק בהערה', () {
      final spans = [_range(1, 4)];
      expect(identical(projectAnchorSpans(spans, const []), spans), isTrue);
      expect(projectAnchorSpans(spans, const [], note: 0), isEmpty);
    });

    test('עוגן-נקודה: בתוך גוף שייך לגוף, בקצותיו לשורה', () {
      const points = [
        LinkAnchorSpan(start: 1),
        LinkAnchorSpan(start: 3),
        LinkAnchorSpan(start: 4),
        LinkAnchorSpan(start: 5),
        LinkAnchorSpan(start: 8),
        LinkAnchorSpan(start: 11),
      ];
      expect(_pairs(projectAnchorSpans(points, notes)), [
        (1, null),
        (3, null),
        (3, null),
        (6, null),
      ]);
      expect(_pairs(projectAnchorSpans(points, notes, note: 0)), [(1, null)]);
      expect(_pairs(projectAnchorSpans(points, notes, note: 1)), [(1, null)]);
    });

    test('טווח כולו בתוך הערה — חלק רק בה', () {
      final spans = [_range(7, 10), _range(8, 9)];
      expect(projectAnchorSpans(spans, notes), isEmpty);
      expect(_pairs(projectAnchorSpans(spans, notes, note: 1)), [
        (0, 3),
        (1, 2),
      ]);
      expect(projectAnchorSpans(spans, notes, note: 0), isEmpty);
    });

    test('טווח שחוצה הערה: טווח אחד בשורה וחלק בכל הערה', () {
      final spans = [_range(2, 12)];
      expect(_pairs(projectAnchorSpans(spans, notes)), [(2, 7)]);
      expect(_pairs(projectAnchorSpans(spans, notes, note: 0)), [(0, 2)]);
      expect(_pairs(projectAnchorSpans(spans, notes, note: 1)), [(0, 3)]);
      final fromBody = [_range(4, 6)];
      expect(_pairs(projectAnchorSpans(fromBody, notes)), [(3, 4)]);
      expect(_pairs(projectAnchorSpans(fromBody, notes, note: 0)), [(1, 2)]);
    });

    test('גוף ריק ושתי הערות באותו מקום', () {
      final stacked = [
        _note(0, 2, '', marker: ''),
        _note(1, 2, 'אב'),
        _note(2, 2, '&amp;ג'),
      ];
      // השורה המלאה: 2 תווים, הערה 1 ב-2..4, הערה 2 ב-4..6, ואז השאר.
      final spans = [_range(1, 7), const LinkAnchorSpan(start: 2)];
      expect(_pairs(projectAnchorSpans(spans, stacked)), [(1, 3), (2, null)]);
      expect(projectAnchorSpans(spans, stacked, note: 0), isEmpty);
      expect(_pairs(projectAnchorSpans(spans, stacked, note: 1)), [(0, 2)]);
      expect(_pairs(projectAnchorSpans(spans, stacked, note: 2)), [(0, 2)]);
    });

    test('הערה בלי מיקום (charPos -1) — אין לעוגן חלק בשום מקום', () {
      final unknown = [notes[0], _note(1, -1, 'זחט')];
      final spans = [_range(1, 4), const LinkAnchorSpan(start: 2)];
      expect(projectAnchorSpans(spans, unknown), isEmpty);
      expect(projectAnchorSpans(spans, unknown, note: 0), isEmpty);
    });

    test('הקרנה שומרת את החוזה גם בהערות לא ממוינות ובגבולות גוף ריק', () {
      final random = Random(12);
      for (var round = 0; round < 200; round++) {
        final lineNotes = <BookNote>[
          for (var k = 0; k < 8; k++)
            _note(
              k,
              random.nextInt(10),
              List.filled(random.nextInt(5), '&amp;').join(),
            ),
        ];
        final spans = <LinkAnchorSpan>[
          for (var at = -1; at < 45; at++) ...[
            LinkAnchorSpan(start: at, label: 'א'),
            LinkAnchorSpan(start: at, end: at + 4, label: 'ב'),
          ],
        ];
        for (final note in [null, -1, 0, 3, 7, 8]) {
          final actual = projectAnchorSpans(spans, lineNotes, note: note);
          final expected = _referenceProjection(spans, lineNotes, note: note);
          expect(_pairs(actual), _pairs(expected), reason: '$round/$note');
          expect(
            actual.map((span) => span.label),
            expected.map((span) => span.label),
          );
        }
      }
    });

    test('השורה המלאה נבנית מחדש בדיוק מהחלקים, בשורות אקראיות', () {
      final random = Random(7);
      const alphabet = ['א', 'ב', ' ', '&amp;', '<b>', '</b>', 'ג'];
      String text(int length) => [
        for (var i = 0; i < length; i++)
          alphabet[random.nextInt(alphabet.length)],
      ].join();
      for (var round = 0; round < 500; round++) {
        final stored = text(random.nextInt(12));
        final storedUnits = _units(stored);
        final lineNotes = <BookNote>[];
        var pos = 0;
        for (var k = random.nextInt(4); k > 0; k--) {
          pos += random.nextInt(storedUnits.length - pos + 1);
          lineNotes.add(_note(lineNotes.length, pos, text(random.nextInt(5))));
        }
        // השורה המלאה ומקור כל תו: -1 לשורה, אחרת מספר ההערה.
        final full = <String>[];
        final owner = <int>[];
        var cursor = 0;
        for (var k = 0; k < lineNotes.length; k++) {
          for (; cursor < lineNotes[k].charPos; cursor++) {
            full.add(storedUnits[cursor]);
            owner.add(-1);
          }
          for (final unit in _units(lineNotes[k].body)) {
            full.add(unit);
            owner.add(k);
          }
        }
        for (; cursor < storedUnits.length; cursor++) {
          full.add(storedUnits[cursor]);
          owner.add(-1);
        }
        expect(
          visibleCharCount(stored) +
              lineNotes.fold<int>(0, (n, e) => n + visibleCharCount(e.body)),
          full.length,
        );
        final start = random.nextInt(full.length + 1);
        final end = start + random.nextInt(full.length - start + 1);
        final spans = [_range(start, end)];
        // בלי הערות העוגן חוזר כמות שהוא, גם טווח ריק.
        final main = [
          for (final span in projectAnchorSpans(spans, lineNotes))
            if (span.end! > span.start) span,
        ];
        final mainUnits = [
          for (var i = start; i < end; i++)
            if (owner[i] == -1) full[i],
        ];
        if (mainUnits.isEmpty) {
          expect(main, isEmpty);
        } else {
          expect(
            storedUnits.sublist(main.single.start, main.single.end!),
            mainUnits,
          );
        }
        for (var k = 0; k < lineNotes.length; k++) {
          final piece = projectAnchorSpans(spans, lineNotes, note: k);
          final noteUnits = [
            for (var i = start; i < end; i++)
              if (owner[i] == k) full[i],
          ];
          if (noteUnits.isEmpty) {
            expect(piece, isEmpty);
          } else {
            expect(
              _units(
                lineNotes[k].body,
              ).sublist(piece.single.start, piece.single.end!),
              noteUnits,
            );
          }
        }
      }
    });
  });

  group('injectLinkAnchorMarkers עם הערות', () {
    const stored = 'אב<sup class="footnote-marker">1</sup>הויכ';

    test('גופי ההערות נסרקים פעם אחת לכל קישורי השורה', () {
      debugAnchorProjectionBodyScanCount = 0;
      final html = injectLinkAnchorMarkers(
        rawLine: stored,
        anchorLinks: [for (var i = 0; i < 40; i++) _linker(2, 12)],
        styleIndexByCommentator: const {},
        notes: notes,
      );
      expect(html, contains('link-anchor-range'));
      expect(debugAnchorProjectionBodyScanCount, notes.length);
    });

    test('בשורה השמורה מוזרק רק החלק שמחוץ להערות', () {
      final html = injectLinkAnchorMarkers(
        rawLine: stored,
        anchorLinks: [_linker(2, 12)],
        styleIndexByCommentator: const {},
        lineIndex: 4,
        notes: notes,
      );
      expect(
        html,
        'אב<sup class="footnote-marker"><a class="link-anchor-range" '
        'href="otzaria://anchor?ref=4_0&range=1">1</a></sup>'
        '<a class="link-anchor-range" href="otzaria://anchor?ref=4_0&range=1">'
        'הויכ</a>',
      );
    });

    test('בגוף ההערה — החלק שבתוכה, עם אותו href', () {
      final html = injectLinkAnchorMarkers(
        rawLine: notes[1].body,
        anchorLinks: [_linker(1, 4), _linker(8, 10)],
        styleIndexByCommentator: const {},
        lineIndex: 4,
        notes: notes,
        note: 1,
      );
      expect(
        html,
        'ז<a class="link-anchor-range" href="otzaria://anchor?ref=4_1&range=1">'
        'חט</a>',
      );
    });

    test('notesForLines מעביר את גוף הערת הטבלה דרך decorateBody', () {
      final builder = BookNotesBuilder()
        ..add(0, 0, '1', 'ג<b>ד</b>', charPos: 3)
        ..add(0, 1, null, 'זחט', charPos: 5);
      final bookNotes = builder.build();
      final result = notesForLines(
        [stored],
        [0],
        dbNotes: bookNotes,
        decorateBody: (line, note, body) => injectLinkAnchorMarkers(
          rawLine: body,
          anchorLinks: [_linker(4, 8)],
          styleIndexByCommentator: const {},
          lineIndex: line,
          notes: bookNotes.notesAt(line),
          note: note,
        ),
      );
      expect(result, [
        '<sup class="footnote-marker">1</sup> ג<b><a class="link-anchor-range" '
            'href="otzaria://anchor?ref=0_0&range=1">ד</a></b>',
        '<a class="link-anchor-range" href="otzaria://anchor?ref=0_0&range=1">'
            'ז</a>חט',
      ]);
    });
  });
}
