import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/user_content_import/models/user_import_models.dart';
import 'package:otzaria/user_content_import/services/user_headings_builder.dart';
import 'package:otzaria/user_content_import/services/user_import_parser.dart';

void main() {
  group('parseHeadings', () {
    test('קורא מבנה, רמה, כותרת ומיקום', () {
      final result = UserImportParser.parseHeadings(
        'מבנה,רמה,כותרת,שורה\n'
        'סימנים,1,סימן א,3\n'
        'סימנים,2,סעיף ב,5\n',
        requireBook: false,
      );

      expect(result.errors, isEmpty);
      expect(result.rows, hasLength(2));
      expect(result.rows.first.structure, 'סימנים');
      expect(result.rows.first.lineNumber, 3);
      expect(result.rows.last.level, 2);
    });

    test('עמודת טקסט משמשת עוגן כשאין מספר שורה', () {
      final result = UserImportParser.parseHeadings(
        'כותרת,שורה,טקסט\nפרק ראשון,,בראשית ברא\n',
        requireBook: false,
      );

      expect(result.rows.single.lineNumber, isNull);
      expect(result.rows.single.anchorText, 'בראשית ברא');
      expect(result.rows.single.structure, 'כותרות');
    });

    test('קובץ רוחבי בלי עמודת ספר נפסל', () {
      final result = UserImportParser.parseHeadings(
        'כותרת,שורה\nסימן א,2\n',
        requireBook: true,
      );

      expect(result.rows, isEmpty);
      expect(result.errors.single.message, contains('"ספר"'));
    });

    test('שורה לא חוקית מדווחת ושאר השורות נקלטות', () {
      final result = UserImportParser.parseHeadings(
        'כותרת,שורה\nסימן א,אאא\nסימן ב,4\n',
        requireBook: false,
      );

      expect(result.rows.single.title, 'סימן ב');
      expect(result.errors.single.lineNumber, 2);
    });
  });

  group('parseVersions', () {
    test('קורא ראשי, גרסה ושם', () {
      final result = UserImportParser.parseVersions(
        'ראשי,גרסה,שם,עדיפות\n'
        'רשבא.pdf,רשבא-קוק.pdf,מוסד הרב קוק,2\n',
      );

      expect(result.errors, isEmpty);
      expect(result.rows.single.primary, 'רשבא.pdf');
      expect(result.rows.single.version, 'רשבא-קוק.pdf');
      expect(result.rows.single.label, 'מוסד הרב קוק');
      expect(result.rows.single.priority, 2);
    });

    test('שורה בלי ספר גרסה מדווחת', () {
      final result = UserImportParser.parseVersions('ראשי,גרסה\nא.pdf,\n');

      expect(result.rows, isEmpty);
      expect(result.errors.single.message, contains('ספר הגרסה'));
    });
  });

  group('UserHeadingsBuilder', () {
    ParsedHeading heading(
      String title, {
      int level = 1,
      int? line,
      String? anchor,
      String structure = 'סימנים',
      int row = 2,
    }) => ParsedHeading(
      rowNumber: row,
      structure: structure,
      level: level,
      title: title,
      lineNumber: line,
      anchorText: anchor,
    );

    test('בונה עץ לפי רמות, עם אב וילדים', () {
      final built = UserHeadingsBuilder.build(
        [
          heading('חלק א', level: 1, line: 1),
          heading('סימן א', level: 2, line: 2),
          heading('סימן ב', level: 2, line: 4),
        ],
        List.generate(5, (i) => 'שורה $i'),
      );

      expect(built.errors, isEmpty);
      final entries = built.structures.single.entries;
      expect(entries.map((e) => e.lineIndex), [0, 1, 3]);
      expect(entries.first.hasChildren, isTrue);
      expect(entries[1].parentIndex, 0);
      expect(entries[2].isLastChild, isTrue);
      expect(built.structures.single.key, 'Simanim');
    });

    test('עוגן טקסטואלי נפתר לשורה, והחיפוש ממשיך קדימה', () {
      final built = UserHeadingsBuilder.build(
        [
          heading('ראשון', anchor: 'פתיחה'),
          heading('שני', anchor: 'פתיחה'),
        ],
        ['הקדמה', 'פתיחה ראשונה', 'אמצע', 'פתיחה שנייה'],
      );

      expect(built.errors, isEmpty);
      expect(built.structures.single.entries.map((e) => e.lineIndex), [1, 3]);
    });

    test('עוגן מתעלם מניקוד ומתגיות HTML', () {
      final built = UserHeadingsBuilder.build(
        [heading('פרק', anchor: 'בראשית ברא')],
        ['<b>בְּרֵאשִׁית בָּרָא</b> אלהים'],
      );

      expect(built.errors, isEmpty);
      expect(built.structures.single.entries.single.lineIndex, 0);
    });

    test('שורה שחורגת מגבולות הספר ועוגן שלא נמצא מדווחים', () {
      final built = UserHeadingsBuilder.build(
        [
          heading('חורגת', line: 9, row: 2),
          heading('חסרה', anchor: 'לא קיים', row: 3),
        ],
        ['שורה אחת'],
      );

      expect(built.structures, isEmpty);
      expect(built.errors, hasLength(2));
      expect(built.errors.first, contains('חורגת מגבולות הספר'));
      expect(built.errors.last, contains('לא נמצא בספר'));
    });

    test('כותרת-אב בלי שורה נשמרת כשיש לה צאצא עם שורה', () {
      final built = UserHeadingsBuilder.build(
        [
          heading('נושא', level: 1),
          heading('סימן א', level: 2, line: 2),
        ],
        ['א', 'ב'],
      );

      expect(built.errors, isEmpty);
      final entries = built.structures.single.entries;
      expect(entries.first.lineIndex, isNull);
      expect(entries.last.parentIndex, 0);
    });

    test('כותרת בלי שורה ובלי צאצאים מדווחת ומושמטת', () {
      final built = UserHeadingsBuilder.build(
        [
          heading('יתומה', level: 1),
        ],
        ['א'],
      );

      expect(built.structures, isEmpty);
      expect(built.errors.single, contains('אין שורה'));
    });

    test('כמה מבנים באותו קובץ נשמרים בנפרד', () {
      final built = UserHeadingsBuilder.build(
        [
          heading('סימן א', line: 1, structure: 'סימנים'),
          heading('הלכות ציצית', line: 1, structure: 'נושאים'),
        ],
        ['א', 'ב'],
      );

      expect(built.structures.map((s) => s.key), ['Simanim', 'Topic']);
      expect(built.structures.map((s) => s.heTitle), ['סימנים', 'נושאים']);
    });

    test('כותרות לפי מספר שורה בלבד אינן קוראות את תוכן שורות הספר', () {
      final lines = _CountingLines(List.generate(1000, (i) => 'שורה $i'));
      final built = UserHeadingsBuilder.build([
        heading('סימן א', line: 1),
        heading('סימן ב', line: 500),
        heading('חורגת', line: 2000, row: 4),
      ], lines);

      expect(built.structures.single.entries.map((e) => e.lineIndex), [0, 499]);
      expect(built.errors.single, contains('(1000 שורות)'));
      expect(lines.reads, 0);
    });

    test('עוגן במבנה אחד ומספר שורה במבנה אחר נפתרים יחד', () {
      final built = UserHeadingsBuilder.build(
        [
          heading('סימן א', line: 2, structure: 'סימנים'),
          heading('פרק', anchor: 'בראשית ברא', structure: 'נושאים'),
        ],
        ['הקדמה', '<b>בְּרֵאשִׁית בָּרָא</b> אלהים'],
      );

      expect(built.errors, isEmpty);
      expect(
        built.structures.map((s) => s.entries.single.lineIndex),
        [1, 1],
      );
    });
  });
}

class _CountingLines extends ListBase<String> {
  _CountingLines(this._lines);

  final List<String> _lines;
  int reads = 0;

  @override
  int get length => _lines.length;

  @override
  set length(int value) => throw UnsupportedError('read-only');

  @override
  String operator [](int index) {
    reads++;
    return _lines[index];
  }

  @override
  void operator []=(int index, String value) =>
      throw UnsupportedError('read-only');
}
