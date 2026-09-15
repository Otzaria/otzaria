import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/text/ref_helper.dart';

void main() {
  // פרק א (0) > הלכה א (1), הלכה ב (5); פרק ב (10) > הלכה א (11)
  late List<TocEntry> toc;

  setUp(() {
    final chapterA = TocEntry(text: 'פרק א', index: 0, level: 2);
    chapterA.children = [
      TocEntry(text: 'הלכה א', index: 1, level: 3, parent: chapterA),
      TocEntry(text: 'הלכה ב', index: 5, level: 3, parent: chapterA),
    ];
    final chapterB = TocEntry(text: 'פרק ב', index: 10, level: 2);
    chapterB.children = [
      TocEntry(text: 'הלכה א', index: 11, level: 3, parent: chapterB),
    ];
    toc = [chapterA, chapterB];
  });

  test('תת-כותרת — עד הכותרת הבאה באותה רמה', () {
    final section = tocSectionAt(toc, 3);
    expect(section, (start: 1, end: 5, title: 'הלכה א'));
  });

  test('תת-כותרת אחרונה בפרק — נסגרת בכותרת הבאה ברמה גבוהה יותר', () {
    final section = tocSectionAt(toc, 7);
    expect(section, (start: 5, end: 10, title: 'הלכה ב'));
  });

  test('על שורת כותרת עליונה — הפרק כולו', () {
    final section = tocSectionAt(toc, 0);
    expect(section, (start: 0, end: 10, title: 'פרק א'));
  });

  test('הקטע האחרון בספר — end null', () {
    final section = tocSectionAt(toc, 20);
    expect(section, (start: 11, end: null, title: 'הלכה א'));
  });

  test('אין כותרת מעל השורה — null', () {
    final later = [TocEntry(text: 'פרק', index: 4, level: 2)];
    expect(tocSectionAt(later, 2), isNull);
  });
}
