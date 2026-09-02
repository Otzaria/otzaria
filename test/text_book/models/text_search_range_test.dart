import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/text_book/models/text_search_range.dart';

/// עץ לדוגמה (אינדקס = שורה בספר):
/// 0 ספר · 1 פרק א · 2 סימן א · 4 סימן ב · 6 פרק ב · 8 פרק ג
List<TocEntry> _toc() {
  final book = TocEntry(text: 'ספר', index: 0, level: 1);
  final chapterA = TocEntry(text: 'פרק א', index: 1, level: 2, parent: book);
  chapterA.children = [
    TocEntry(text: 'סימן א', index: 2, level: 3, parent: chapterA),
    TocEntry(text: 'סימן ב', index: 4, level: 3, parent: chapterA),
  ];
  final chapterB = TocEntry(text: 'פרק ב', index: 6, level: 2, parent: book);
  final chapterC = TocEntry(text: 'פרק ג', index: 8, level: 2, parent: book);
  book.children = [chapterA, chapterB, chapterC];
  return [book];
}

void main() {
  group('TextSearchRange.fromToc', () {
    test('ענף יחיד: מכותרתו ועד הכותרת הבאה ברמה שווה או גבוהה', () {
      final toc = _toc();
      final chapterA = toc.first.children[0];

      final range = TextSearchRange.fromToc(toc: toc, start: chapterA);

      expect(range.startLine, 1);
      expect(range.endLine, 6, reason: 'סימן ב (רמה 3) אינו סוגר את פרק א');
      expect(range.label, 'פרק א');
      expect(range.contains(5), isTrue);
      expect(range.contains(6), isFalse);
    });

    test('תת-כותרת נסגרת על-ידי אחותה', () {
      final toc = _toc();
      final simanA = toc.first.children[0].children[0];

      final range = TextSearchRange.fromToc(toc: toc, start: simanA);

      expect(range.startLine, 2);
      expect(range.endLine, 4);
      expect(range.label, 'פרק א, סימן א');
    });

    test('מכותרת עד כותרת: הסיום כולל את כל ענף כותרת הסיום', () {
      final toc = _toc();
      final simanB = toc.first.children[0].children[1];
      final chapterB = toc.first.children[1];

      final range = TextSearchRange.fromToc(
        toc: toc,
        start: simanB,
        end: chapterB,
      );

      expect(range.startLine, 4);
      expect(range.endLine, 8);
      expect(range.label, 'פרק א, סימן ב — פרק ב');
    });

    test('הענף האחרון נמשך עד סוף הספר', () {
      final toc = _toc();
      final chapterC = toc.first.children[2];

      final range = TextSearchRange.fromToc(toc: toc, start: chapterC);

      expect(range.endLine, isNull);
      expect(range.contains(8), isTrue);
      expect(range.contains(10_000), isTrue);
      expect(range.contains(7), isFalse);
    });

    test('סדר הפוך של הכותרות מתוקן', () {
      final toc = _toc();
      final chapterA = toc.first.children[0];
      final chapterB = toc.first.children[1];

      final range = TextSearchRange.fromToc(
        toc: toc,
        start: chapterB,
        end: chapterA,
      );

      expect(range.startLine, 1);
      expect(range.endLine, 8);
    });
  });

  group('searchRangeHeadings', () {
    test('משמיט את שורש שם הספר ומשטח את העץ בסדר הספר', () {
      final headings = searchRangeHeadings(_toc());

      expect(headings.map((h) => h.text), [
        'פרק א',
        'סימן א',
        'סימן ב',
        'פרק ב',
        'פרק ג',
      ]);
    });

    test('עץ בלי שורש שם ספר נשמר במלואו', () {
      final chapter = TocEntry(text: 'פרק א', index: 0, level: 2);
      expect(searchRangeHeadings([chapter]), [chapter]);
    });
  });
}
