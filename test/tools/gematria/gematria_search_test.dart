import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/models/toc_entry.dart';
import 'package:otzaria/tools/gematria/gematria_search.dart';

void main() {
  test('Gematria path extraction keeps chapter in Tanach results', () {
    final path = GimatriaSearch.extractPathFromTocEntries(
      currentLineIndex: 8,
      bookTitle: 'בראשית',
      tocEntries: const [
        TocEntry(
          id: 1,
          bookId: 1,
          text: 'בראשית',
          level: 1,
          lineIndex: 0,
        ),
        TocEntry(
          id: 2,
          bookId: 1,
          parentId: 1,
          text: 'פרק א',
          level: 2,
          lineIndex: 1,
        ),
      ],
    );

    expect(path, 'בראשית, פרק א');
  });

  test('Gematria path extraction keeps nested TOC hierarchy', () {
    final path = GimatriaSearch.extractPathFromTocEntries(
      currentLineIndex: 30,
      bookTitle: 'משנה תורה',
      tocEntries: const [
        TocEntry(
          id: 1,
          bookId: 1,
          text: 'משנה תורה',
          level: 1,
          lineIndex: 0,
        ),
        TocEntry(
          id: 2,
          bookId: 1,
          parentId: 1,
          text: 'הלכות תשובה',
          level: 2,
          lineIndex: 10,
        ),
        TocEntry(
          id: 3,
          bookId: 1,
          parentId: 2,
          text: 'פרק ב',
          level: 3,
          lineIndex: 20,
        ),
      ],
    );

    expect(path, 'משנה תורה, הלכות תשובה, פרק ב');
  });

  test('מיקום הכותרת קובע, ורמה גבוהה והופעה ראשונה מכריעות על אותה שורה', () {
    const tocEntries = [
      TocEntry(id: 5, bookId: 1, level: 1, text: 'סוף', lineIndex: 30),
      TocEntry(id: 1, bookId: 1, level: 1, text: 'שער', lineIndex: 10),
      TocEntry(id: 2, bookId: 1, level: 2, text: 'פרק', lineIndex: 10),
      TocEntry(id: 3, bookId: 1, level: 2, text: 'כותרת מקבילה', lineIndex: 10),
      TocEntry(id: 4, bookId: 1, level: 8, text: 'ללא שורה'),
    ];

    String pathAt(int line) => GimatriaSearch.extractPathFromTocEntries(
      currentLineIndex: line,
      bookTitle: 'ספר',
      tocEntries: tocEntries,
    );

    expect(pathAt(9), '');
    expect(pathAt(10), 'ספר, פרק');
    expect(pathAt(29), 'ספר, פרק');
    expect(pathAt(30), 'ספר, סוף');
  });

  test(
    'נתיב עובר דרך הורה ללא שורה ומשתמש ברשומת ההורה האחרונה לאותו מזהה',
    () {
      final path = GimatriaSearch.extractPathFromTocEntries(
        currentLineIndex: 20,
        bookTitle: 'ספר',
        tocEntries: const [
          TocEntry(id: 1, bookId: 1, level: 0, text: 'ישן'),
          TocEntry(
            id: 2,
            bookId: 1,
            parentId: 99,
            level: 0,
            text: '<b>ספר</b>',
          ),
          TocEntry(
            id: 3,
            bookId: 1,
            parentId: 1,
            level: 2,
            text: '<b>פרק&nbsp;א</b>',
            lineIndex: 10,
          ),
          TocEntry(id: 1, bookId: 1, parentId: 2, level: 1, text: 'שער'),
        ],
      );

      expect(path, 'ספר, שער, פרק א');
    },
  );
}
