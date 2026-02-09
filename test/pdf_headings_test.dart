import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/pdf_headings.dart';
import 'package:otzaria/migration/core/models/toc_entry.dart'
    as migration_models;

void main() {
  group('PdfHeadings DB map builder', () {
    test('buildHeadingsMapFromTocEntries filters and dedupes', () {
      final entries = <migration_models.TocEntry>[
        migration_models.TocEntry(
          id: 1,
          bookId: 10,
          level: 1,
          text: 'פרק א',
          lineIndex: 5,
        ),
        migration_models.TocEntry(
          id: 2,
          bookId: 10,
          level: 1,
          text: 'פרק א',
          lineIndex: 3,
        ),
        migration_models.TocEntry(
          id: 3,
          bookId: 10,
          level: 1,
          text: '',
          lineIndex: 7,
        ),
        migration_models.TocEntry(
          id: 4,
          bookId: 10,
          level: 1,
          text: 'פרק ב',
          lineIndex: null,
        ),
        migration_models.TocEntry(
          id: 5,
          bookId: 10,
          level: 1,
          text: '  פרק ג  ',
          lineIndex: 9,
        ),
      ];

      final map = PdfHeadings.buildHeadingsMapFromTocEntries(entries);

      expect(map.length, 2);
      expect(map['פרק א'], 3);
      expect(map['פרק ג'], 9);
    });
  });
}
