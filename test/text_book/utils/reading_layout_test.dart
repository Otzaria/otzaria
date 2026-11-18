import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';

// 3 פרקים: כותרת ואחריה 9 פסוקים.
final List<String> _lines = [
  for (var chapter = 1; chapter <= 3; chapter++) ...[
    '<h2>פרק $chapter</h2>',
    for (var verse = 1; verse <= 9; verse++) 'פסוק $verse בפרק $chapter',
  ],
];

final List<TocEntry> _toc = _chapterToc();

List<TocEntry> _chapterToc() {
  final root = TocEntry(text: 'ספר', index: 0, level: 1);
  for (var chapter = 0; chapter < 3; chapter++) {
    root.children.add(
      TocEntry(
        text: 'פרק ${chapter + 1}',
        index: chapter * 10,
        level: 2,
        parent: root,
      ),
    );
  }
  return [root];
}

TextBookLoaded _state({
  required List<String> content,
  List<bool>? loadedLineFlags,
  List<TocEntry>? tableOfContents,
  bool continuous = true,
  Object? readerIdentity,
}) => TextBookLoaded(
  readerIdentity: readerIdentity,
  book: TextBook(title: 'ספר בדיקה'),
  showLeftPane: false,
  content: content,
  fontSize: 18,
  showSplitView: false,
  activeCommentators: const [],
  commentatorGroups: const [],
  availableCommentators: const [],
  links: const [],
  linksByLine: const {},
  tableOfContents: tableOfContents ?? _toc,
  visibleIndices: const [0],
  pinLeftPane: false,
  searchText: '',
  supportsContinuousReadingMode: true,
  continuousReadingMode: continuous,
  loadedLineFlags: loadedLineFlags,
);

List<String> _contentLoaded(List<bool> flags) => [
  for (var i = 0; i < _lines.length; i++) flags[i] ? _lines[i] : '',
];

List<bool> _window(int start, int end) => [
  for (var i = 0; i < _lines.length; i++) i >= start && i <= end,
];

void main() {
  group('ReadingLayout מה-TOC', () {
    test('כל שורת TOC פריט לבדה, והשורות שביניהן פסקה אחת', () {
      final layout = readingLayoutOf(_state(content: _lines));

      expect(layout.itemCount, 6);
      for (var chapter = 0; chapter < 3; chapter++) {
        final header = chapter * 2;
        expect(layout.firstLineOf(header), chapter * 10);
        expect(layout.lastLineOf(header), chapter * 10);
        expect(layout.firstLineOf(header + 1), chapter * 10 + 1);
        expect(layout.lastLineOf(header + 1), chapter * 10 + 9);
      }
    });

    test('שורה → פריט → שורות: כל שורה נמצאת בטווח הפריט שלה', () {
      final layout = readingLayoutOf(_state(content: _lines));
      var expectedItem = 0;
      for (var line = 0; line < _lines.length; line++) {
        final item = layout.itemForLine(line);
        expect(
          line,
          inInclusiveRange(layout.firstLineOf(item), layout.lastLineOf(item)),
        );
        expect(item, greaterThanOrEqualTo(expectedItem));
        expectedItem = item;
      }
      expect(layout.itemForLine(-3), 0);
      expect(layout.itemForLine(1000), layout.itemCount - 1);
    });

    test('שורה מיושרת אינה משנה את הפריסה, טעונה או לא (issue #1293)', () {
      final controller = Object();
      final lines = [
        'פתיחה',
        '<center>הדרן</center>',
        'המשך',
      ];
      final partial = _state(
        content: const ['פתיחה', '', ''],
        tableOfContents: const [],
        loadedLineFlags: const [true, false, false],
        readerIdentity: controller,
      );
      final layout = readingLayoutOf(partial);
      expect(layout.itemCount, 1);

      final full = partial.copyWith(
        content: lines,
        loadedLineFlags: const [true, true, true],
      );
      expect(identical(readingLayoutOf(full), layout), isTrue);
      expect(
        readingLayoutOf(
          _state(content: lines, tableOfContents: const []),
        ).itemCount,
        1,
      );
      expect(readingSegmentsOf(full)[0].text, contains('הדרן'));
    });

    test('ספר בלי TOC במצב רציף הוא פריט אחד', () {
      final layout = readingLayoutOf(
        _state(content: _lines, tableOfContents: const []),
      );
      expect(layout.itemCount, 1);
      expect(layout.lastLineOf(0), _lines.length - 1);
    });

    test('רצף ארוך בלי שבירה נחתך כל $kMaxReadingParagraphLines שורות', () {
      const max = kMaxReadingParagraphLines;
      final noToc = ReadingLayout.continuous(
        lineCount: max * 2 + 50,
        breakLines: const [],
      );
      expect(noToc.itemCount, 3);
      expect(noToc.firstLineOf(1), max);
      expect(noToc.firstLineOf(2), max * 2);
      expect(noToc.lastLineOf(2), max * 2 + 49);

      // החיתוך נמדד מתחילת הרצף, אחרי שורת השבירה.
      final withBreak = ReadingLayout.continuous(
        lineCount: 10 + max + 5,
        breakLines: const [9],
      );
      expect(
        [
          for (var i = 0; i < withBreak.itemCount; i++)
            (withBreak.firstLineOf(i), withBreak.lastLineOf(i)),
        ],
        [(0, 8), (9, 9), (10, 10 + max - 1), (10 + max, 10 + max + 4)],
      );

      final exact = ReadingLayout.continuous(
        lineCount: max,
        breakLines: const [],
      );
      expect(exact.itemCount, 1);
    });

    test('מצב רגיל הוא זהות: פריט לכל שורה', () {
      final layout = readingLayoutOf(
        _state(content: _lines, continuous: false),
      );
      expect(layout.continuous, isFalse);
      expect(layout.itemCount, _lines.length);
      for (var line = 0; line < _lines.length; line++) {
        expect(layout.itemForLine(line), line);
        expect(layout.firstLineOf(line), line);
        expect(layout.lastLineOf(line), line);
      }
    });
  });

  group('יציבות הפריסה מול טעינת תוכן', () {
    test('טעינת טווח, תוכן מלא ושחרור מחזירים את אותה פריסה', () {
      final controller = Object();
      final partialFlags = _window(11, 15);
      final partial = _state(
        content: _contentLoaded(partialFlags),
        loadedLineFlags: partialFlags,
        readerIdentity: controller,
      );
      final layout = readingLayoutOf(partial);
      expect(layout.itemCount, 6);

      final rangeFlags = _window(0, 19);
      final ranged = partial.copyWith(
        content: _contentLoaded(rangeFlags),
        contentVersion: 2,
        loadedLineFlags: rangeFlags,
      );
      final full = ranged.copyWith(
        content: _lines,
        contentVersion: 3,
        loadedLineFlags: List<bool>.filled(_lines.length, true),
      );
      final releasedFlags = _window(10, 19);
      final released = full.copyWith(
        content: _contentLoaded(releasedFlags),
        contentVersion: 4,
        loadedLineFlags: releasedFlags,
      );

      for (final state in [ranged, full, released]) {
        expect(identical(readingLayoutOf(state), layout), isTrue);
      }
    });

    test('הסגמנטים מתמלאים במקום בלי לשנות את מספור הפריטים', () {
      final controller = Object();
      final partialFlags = _window(11, 15);
      final partial = _state(
        content: _contentLoaded(partialFlags),
        loadedLineFlags: partialFlags,
        readerIdentity: controller,
      );
      final before = readingSegmentsOf(partial);
      expect(before[3].isLoaded, isFalse);
      expect(before[3].sourceLineIndices, [11, 12, 13, 14, 15, 16, 17, 18, 19]);

      final full = partial.copyWith(
        content: _lines,
        loadedLineFlags: List<bool>.filled(_lines.length, true),
      );
      final after = readingSegmentsOf(full);
      expect(after.length, before.length);
      expect(after[3].isLoaded, isTrue);
      expect(after[3].sourceLineIndices, before[3].sourceLineIndices);
      expect(after[3].text, startsWith('פסוק 1 בפרק 2 פסוק 2 בפרק 2'));
    });

    test('דלתא משמרת מקטעים בנויים מחוץ לטווח שהשתנה', () {
      final flags = List<bool>.filled(_lines.length, true)..[13] = false;
      final content = List<String>.of(_lines)..[13] = '';
      final partial = _state(content: content, loadedLineFlags: flags);
      final before = readingSegmentsOf(partial);
      final unchanged = before[1];
      final unloaded = before[3];
      expect(unloaded.isLoaded, isFalse);

      final loaded = partial.copyWith(
        loadedLineFlags: List<bool>.of(flags)..[13] = true,
        contentVersion: 1,
        contentChanges: ContentLineChanges(
          fromVersion: 0,
          previousContent: partial.content,
          previousLoadedLineFlags: partial.loadedLineFlags,
          ranges: [(first: 13, last: 13)],
        ),
      );
      final afterLoad = readingSegmentsOf(loaded);
      expect(afterLoad[1], same(unchanged));
      expect(afterLoad[3], isNot(same(unloaded)));
      expect(afterLoad[3].isLoaded, isTrue);

      final corrected = loaded.copyWith(
        content: List<String>.of(content)..[13] = 'טקסט מתוקן',
        contentVersion: 2,
        contentChanges: ContentLineChanges(
          fromVersion: 1,
          previousContent: loaded.content,
          previousLoadedLineFlags: loaded.loadedLineFlags,
          ranges: [(first: 13, last: 13)],
        ),
      );
      final afterCorrection = readingSegmentsOf(corrected);
      expect(afterCorrection[1], same(unchanged));
      expect(afterCorrection[3].text, contains('טקסט מתוקן'));
      expect(afterLoad[3].text, isNot(contains('טקסט מתוקן')));
    });

    test('עדכון במצב רגיל בונה רק את השורות שנדרשות לאחריו', () {
      final normal = _state(content: _lines, continuous: false);
      final before = readingSegmentsOf(normal);
      final unchanged = before[1];

      final updated = normal.copyWith(
        content: List<String>.of(normal.content)..[13] = 'שורה מתוקנת',
        contentVersion: 1,
        contentChanges: ContentLineChanges(
          fromVersion: 0,
          previousContent: normal.content,
          ranges: [(first: 13, last: 13)],
        ),
      );
      final after = readingSegmentsOf(updated);

      expect(after.debugBuiltCount, 0);
      expect(after[1], isNot(same(unchanged)));
      expect(after[13].text, 'שורה מתוקנת');
      expect(after.changedLinesSince(before), [(first: 13, last: 13)]);
    });

    test('מקטע בנוי דורש דלתא מהגרסה הקודמת באותה פריסה', () {
      final original = _state(content: _lines);
      final first = readingSegmentsOf(original)[1];
      final missingPredecessor = original.copyWith(
        content: List<String>.of(_lines),
        contentVersion: 2,
        contentChanges: ContentLineChanges(
          fromVersion: 1,
          previousContent: original.content,
          ranges: [(first: 13, last: 13)],
        ),
      );
      final afterGap = readingSegmentsOf(missingPredecessor);
      expect(afterGap[1], isNot(same(first)));

      final normal = missingPredecessor.copyWith(
        continuousReadingMode: false,
        contentVersion: 3,
        contentChanges: ContentLineChanges(
          fromVersion: 2,
          previousContent: missingPredecessor.content,
          ranges: [(first: 13, last: 13)],
        ),
      );
      expect(readingSegmentsOf(normal)[1].sourceLineIndices, [1]);

      final otherReader = _state(content: _lines).copyWith(
        contentVersion: 3,
        contentChanges: ContentLineChanges(
          fromVersion: 2,
          previousContent: missingPredecessor.content,
          ranges: [(first: 13, last: 13)],
        ),
      );
      expect(readingSegmentsOf(otherReader)[1], isNot(same(afterGap[1])));
    });

    test('טעינה מחדש באותה גרסה אינה משחזרת טקסט מהטעינה הקודמת', () {
      final original = _state(content: _lines);
      final oldSegment = readingSegmentsOf(original)[1];
      final reloaded = original.copyWith(
        content: List<String>.of(_lines)..[1] = 'טקסט מהטעינה החדשה',
      );
      final prefetched = reloaded.copyWith(
        content: List<String>.of(reloaded.content)..[13] = 'שורה חדשה',
        contentVersion: 1,
        contentChanges: ContentLineChanges(
          fromVersion: 0,
          previousContent: reloaded.content,
          ranges: [(first: 13, last: 13)],
        ),
      );

      final segment = readingSegmentsOf(prefetched)[1];
      expect(segment, isNot(same(oldSegment)));
      expect(segment.text, startsWith('טקסט מהטעינה החדשה'));
    });

    test('TOC חדש כמופע וזהה בתוכנו מחזיר את אותה פריסה', () {
      final controller = Object();
      final state = _state(content: _lines, readerIdentity: controller);
      final layout = readingLayoutOf(state);
      final sameToc = state.copyWith(tableOfContents: _chapterToc());
      expect(identical(readingLayoutOf(sameToc), layout), isTrue);
      // state ישן אחרי החדש לא בונה מחדש.
      expect(identical(readingLayoutOf(state), layout), isTrue);

      final otherToc = state.copyWith(
        tableOfContents: [TocEntry(text: 'פרק', index: 5)],
      );
      expect(readingLayoutOf(otherToc).itemCount, 3);
    });

    test('הפריסה נבנית מחדש בהחלפת מצב רציף', () {
      final controller = Object();
      final continuous = _state(content: _lines, readerIdentity: controller);
      final normal = continuous.copyWith(continuousReadingMode: false);
      expect(readingLayoutOf(continuous).itemCount, 6);
      expect(readingLayoutOf(normal).itemCount, _lines.length);
      expect(readingLayoutOf(continuous).itemCount, 6);
    });

    test('emit שאינו משנה תוכן מחזיר את אותם סגמנטים', () {
      final state = _state(content: _lines);
      final scrolled = state.copyWith(visibleIndices: const [12]);
      expect(
        identical(readingSegmentsOf(state), readingSegmentsOf(scrolled)),
        isTrue,
      );
    });
  });
}
