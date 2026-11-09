import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_notes_import_export_service.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/printing/print_content_models.dart';

PersonalNote _note({
  required String id,
  required String bookId,
  int? lineNumber,
  String? displayTitle,
  String? anchorText,
  PersonalNoteStatus status = PersonalNoteStatus.located,
  String content = 'תוכן ההערה',
  String? contentPlain,
  PersonalNoteContentFormat contentFormat = PersonalNoteContentFormat.plain,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return PersonalNote(
    id: id,
    bookId: bookId,
    lineNumber: lineNumber,
    displayTitle: displayTitle,
    anchorText: anchorText,
    lastKnownLineNumber: null,
    status: status,
    content: content,
    contentPlain: contentPlain ?? content,
    contentFormat: contentFormat,
    createdAt: createdAt ?? DateTime(2025, 1, 1),
    updatedAt: updatedAt ?? DateTime(2025, 3, 7),
  );
}

class _CapturedNotesDatabase extends Fake implements PersonalNotesDatabase {
  PersonalNote? inserted;

  @override
  Future<void> insertNote(PersonalNote note) async {
    inserted = note;
  }
}

void main() {
  final service = PersonalNotesImportExportService();

  group('buildWordExportBlocks - מבנה חידושי תורה (issue #767)', () {
    test('כותרת רמה 1 לכל ספר וכותרת רמה 2 לכל מיקום', () {
      final blocks = service.buildWordExportBlocks(
        notes: [
          _note(id: 'a', bookId: 'ברכות', lineNumber: 10, content: 'הערה א'),
          _note(id: 'b', bookId: 'ברכות', lineNumber: 50, content: 'הערה ב'),
          _note(id: 'c', bookId: 'שבת', lineNumber: 3, content: 'הערה ג'),
        ],
        locationRef: (note) => switch (note.id) {
          'a' => 'דף ב עמוד א',
          'b' => 'דף ג עמוד ב',
          _ => 'דף ב עמוד א',
        },
      );

      final headings = blocks
          .where((b) => b.kind == PrintBlockKind.heading)
          .map((b) => (b.headingLevel, b.text))
          .toList();
      expect(headings, [
        (1, 'ברכות'),
        (2, 'דף ב עמוד א'),
        (2, 'דף ג עמוד ב'),
        (1, 'שבת'),
        (2, 'דף ב עמוד א'),
      ]);
    });

    test('הערות עוקבות באותו מיקום חולקות כותרת אחת', () {
      final blocks = service.buildWordExportBlocks(
        notes: [
          _note(id: 'a', bookId: 'ברכות', lineNumber: 10, content: 'ראשונה'),
          _note(id: 'b', bookId: 'ברכות', lineNumber: 11, content: 'שנייה'),
        ],
        locationRef: (_) => 'דף ב עמוד א',
      );

      final refHeadings = blocks.where(
        (b) => b.kind == PrintBlockKind.heading && b.headingLevel == 2,
      );
      expect(refHeadings, hasLength(1));
    });

    test('ההערות ממוינות לפי ספר ושורה גם כשהקלט לא ממוין', () {
      final blocks = service.buildWordExportBlocks(
        notes: [
          _note(id: 'b', bookId: 'שבת', lineNumber: 5, content: 'שבת-הערה'),
          _note(id: 'a', bookId: 'ברכות', lineNumber: 20, content: 'מאוחרת'),
          _note(id: 'c', bookId: 'ברכות', lineNumber: 2, content: 'מוקדמת'),
        ],
        locationRef: (_) => null,
      );

      final texts = blocks.map((b) => b.text).toList();
      expect(
        texts.indexOf('מוקדמת'),
        lessThan(texts.indexOf('מאוחרת')),
      );
      expect(
        texts.indexOf('מאוחרת'),
        lessThan(texts.indexOf('שבת-הערה')),
      );
    });

    test('אין מספרי שורה ותאריכים בפלט', () {
      final blocks = service.buildWordExportBlocks(
        notes: [
          _note(id: 'a', bookId: 'ברכות', lineNumber: 137, content: 'הערה'),
        ],
        locationRef: (_) => 'דף ב עמוד א',
      );

      final allText = blocks.map((b) => b.text).join('\n');
      expect(allText, isNot(contains('137')));
      expect(allText, isNot(contains('שורה')));
      expect(allText, isNot(contains('2025')));
    });

    test('סדר היצירה נשמר באותה שורה ועריכה אינה מזיזה הערה', () {
      final blocks = service.buildWordExportBlocks(
        notes: [
          _note(
            id: 'later',
            bookId: 'ספר בדיקה',
            lineNumber: 5,
            content: 'מאוחרת',
            createdAt: DateTime(2026, 2),
          ),
          _note(
            id: 'same-time-b',
            bookId: 'ספר בדיקה',
            lineNumber: 5,
            content: 'שנייה',
          ),
          _note(
            id: 'same-time-a',
            bookId: 'ספר בדיקה',
            lineNumber: 5,
            content: 'ראשונה',
            updatedAt: DateTime(2026, 3),
          ),
        ],
        locationRef: (_) => null,
      );

      expect(
        blocks.where((b) => b.kind == PrintBlockKind.text).map((b) => b.text),
        ['ראשונה', 'שנייה', 'מאוחרת'],
      );
    });

    test('חסרות מיקום נשארות אחרי הממוקמות ולפי העדכון האחרון', () {
      final blocks = service.buildWordExportBlocks(
        notes: [
          _note(
            id: 'older',
            bookId: 'ספר בדיקה',
            status: PersonalNoteStatus.missing,
            content: 'עדכון ישן',
            createdAt: DateTime(2026, 2),
          ),
          _note(
            id: 'newer',
            bookId: 'ספר בדיקה',
            status: PersonalNoteStatus.missing,
            content: 'עדכון חדש',
            updatedAt: DateTime(2026, 3),
          ),
          _note(
            id: 'located',
            bookId: 'ספר בדיקה',
            lineNumber: 5,
            content: 'ממוקמת',
          ),
        ],
        locationRef: (_) => null,
      );

      expect(
        blocks.where((b) => b.kind == PrintBlockKind.text).map((b) => b.text),
        ['ממוקמת', 'עדכון חדש', 'עדכון ישן'],
      );
    });

    test('הערות ללא מיקום מקובצות בסוף הספר תחת כותרת משלהן', () {
      final blocks = service.buildWordExportBlocks(
        notes: [
          _note(
            id: 'missing',
            bookId: 'ברכות',
            lineNumber: null,
            status: PersonalNoteStatus.missing,
            content: 'הערה אבודה',
          ),
          _note(id: 'a', bookId: 'ברכות', lineNumber: 5, content: 'הערה רגילה'),
        ],
        locationRef: (note) => note.id == 'a' ? 'דף ב עמוד א' : null,
      );

      final texts = blocks.map((b) => b.text).toList();
      expect(texts, contains('הערות ללא מיקום'));
      expect(
        texts.indexOf('הערה רגילה'),
        lessThan(texts.indexOf('הערות ללא מיקום')),
      );
      expect(
        texts.indexOf('הערות ללא מיקום'),
        lessThan(texts.indexOf('הערה אבודה')),
      );
    });

    test('הערה ריקה מדולגת ולא מייצרת כותרות מיותמות', () {
      final blocks = service.buildWordExportBlocks(
        notes: [
          _note(id: 'a', bookId: 'ברכות', lineNumber: 5, content: '   \n '),
        ],
        locationRef: (_) => 'דף ב עמוד א',
      );

      expect(blocks, isEmpty);
    });
  });

  group('QA: יצירה עד ייצוא דיבור המתחיל', () {
    test('גרש, גרשיים, מרכאות ASCII וניקוד עוברים יצירה וייצוא', () async {
      for (final (selected, expectedTitle, expectedAnchor) in [
        ('רש"י', 'רש"י', 'רשי'),
        ('רש״י', 'רש״י', 'רשי'),
        ('ר׳', 'ר׳', 'ר'),
        ('רַשּׁ״י', 'רש״י', 'רשי'),
      ]) {
        final database = _CapturedNotesDatabase();
        final note = await PersonalNotesService(database: database).createNote(
          bookId: 'ספר בדיקה',
          bookContent: 'פירוש $selected כאן',
          lineNumber: 1,
          selectedText: selected,
          sourceSelectedText: selected,
          content: 'פירוט',
          contentPlain: 'פירוט',
          contentFormat: PersonalNoteContentFormat.plain,
        );

        expect(database.inserted, note);
        expect(note.anchorText, expectedAnchor, reason: selected);
        expect(note.displayTitle, expectedTitle, reason: selected);
        final blocks = service.buildWordExportBlocks(
          notes: [note],
          locationRef: (_) => null,
        );
        expect(
          blocks.last.text,
          '<b>$expectedTitle.</b> פירוט',
          reason: selected,
        );
      }
    });

    test('כותרת שונה בשל החלפה בתצוגה אינה גוברת על עוגן המקור', () async {
      final database = _CapturedNotesDatabase();
      final note = await PersonalNotesService(database: database).createNote(
        bookId: 'ספר בדיקה',
        bookContent: 'פתיחה מקור ארוך ומסקנה',
        lineNumber: 1,
        selectedText: 'תצוגה',
        sourceSelectedText: 'מקור',
        sourceSelectionOffset: 7,
        content: 'פירוט',
        contentPlain: 'פירוט',
        contentFormat: PersonalNoteContentFormat.plain,
      );

      expect(note.anchorText, 'מקור');
      expect(note.displayTitle, 'תצוגה');
      final blocks = service.buildWordExportBlocks(
        notes: [note],
        locationRef: (_) => null,
      );
      expect(blocks.last.text, '<b>מקור.</b> פירוט');
    });
  });

  group('buildWordExportBlocks - דיבור המתחיל', () {
    test('כותרת הערת שורה נשמרת כשאין בחירת מילים', () {
      for (final anchor in [null, '', '   ']) {
        final blocks = service.buildWordExportBlocks(
          notes: [
            _note(
              id: 'whole-line',
              bookId: 'ספר בדיקה',
              lineNumber: 5,
              displayTitle: '  כותרת <שלמה> & מקור  ',
              anchorText: anchor,
              content: 'תוכן ההערה',
            ),
          ],
          locationRef: (_) => null,
        );

        expect(
          blocks.last.text,
          '<b>כותרת &lt;שלמה&gt; &amp; מקור.</b> תוכן ההערה',
        );
      }
    });

    test('גרשיים בבחירה נשמרים בייצוא כשהעוגן המנורמל תואם', () {
      final blocks = service.buildWordExportBlocks(
        notes: [
          _note(
            id: 'quote',
            bookId: 'ספר בדיקה',
            lineNumber: 1,
            displayTitle: 'אב״ג',
            anchorText: 'אבג',
            content: 'פירוט',
          ),
        ],
        locationRef: (_) => null,
      );

      expect(blocks.last.text, '<b>אב״ג.</b> פירוט');
    });

    test('גרש בבחירה נשמר אף שהעוגן המנורמל חסר אותו', () {
      final blocks = service.buildWordExportBlocks(
        notes: [
          _note(
            id: 'geresh',
            bookId: 'ספר בדיקה',
            lineNumber: 1,
            displayTitle: "ג׳",
            anchorText: 'ג',
            content: 'פירוט',
          ),
        ],
        locationRef: (_) => null,
      );

      expect(blocks.last.text, '<b>ג׳.</b> פירוט');
    });

    test('בחירת המילים עדיפה על כותרת התצוגה', () {
      final blocks = service.buildWordExportBlocks(
        notes: [
          _note(
            id: 'selection',
            bookId: 'ספר בדיקה',
            lineNumber: 5,
            displayTitle: 'כותרת שלמה',
            anchorText: 'בחירה מדויקת',
            content: 'תוכן ההערה',
          ),
        ],
        locationRef: (_) => null,
      );

      expect(blocks.last.text, '<b>בחירה מדויקת.</b> תוכן ההערה');
    });

    test('הטקסט שסומן נפתח מודגש עם נקודה בסוף', () {
      final blocks = service.buildWordExportBlocks(
        notes: [
          _note(
            id: 'a',
            bookId: 'ברכות',
            lineNumber: 5,
            anchorText: 'מאימתי קורין',
            content: 'נראה לומר',
          ),
        ],
        locationRef: (_) => null,
      );

      final body = blocks.last;
      expect(body.text, '<b>מאימתי קורין.</b> נראה לומר');
    });

    test('דיבור המתחיל שכבר מסתיים בפיסוק לא מקבל נקודה נוספת', () {
      final blocks = service.buildWordExportBlocks(
        notes: [
          _note(
            id: 'a',
            bookId: 'ברכות',
            lineNumber: 5,
            anchorText: 'מאימתי?',
            content: 'תשובה',
          ),
        ],
        locationRef: (_) => null,
      );

      expect(blocks.last.text, '<b>מאימתי?</b> תשובה');
    });

    test('ללא טקסט מסומן — הגוף מופיע כמות שהוא', () {
      final blocks = service.buildWordExportBlocks(
        notes: [
          _note(id: 'a', bookId: 'ברכות', lineNumber: 5, content: 'רק גוף'),
        ],
        locationRef: (_) => null,
      );

      expect(blocks.last.text, 'רק גוף');
    });
  });

  group('buildWordExportBlocks - עיצוב מ-Quill Delta', () {
    test('מודגש/נטוי/קו תחתי/קו חוצה ממופים לתגיות HTML', () {
      final blocks = service.buildWordExportBlocks(
        notes: [
          _note(
            id: 'a',
            bookId: 'ברכות',
            lineNumber: 5,
            contentFormat: PersonalNoteContentFormat.quillDelta,
            content: jsonEncode([
              {
                'insert': 'חשוב',
                'attributes': {'bold': true},
              },
              {'insert': ' רגיל '},
              {
                'insert': 'נטוי',
                'attributes': {'italic': true},
              },
              {
                'insert': 'תחתי',
                'attributes': {'underline': true},
              },
              {
                'insert': 'מחוק',
                'attributes': {'strike': true},
              },
              {'insert': '\n'},
            ]),
            contentPlain: 'חשוב רגיל נטויתחתימחוק',
          ),
        ],
        locationRef: (_) => null,
      );

      expect(
        blocks.last.text,
        '<b>חשוב</b> רגיל <i>נטוי</i><u>תחתי</u><s>מחוק</s>',
      );
    });

    test('שורות חדשות ב-Delta הופכות לפסקאות נפרדות', () {
      final blocks = service.buildWordExportBlocks(
        notes: [
          _note(
            id: 'a',
            bookId: 'ברכות',
            lineNumber: 5,
            contentFormat: PersonalNoteContentFormat.quillDelta,
            content: jsonEncode([
              {'insert': 'פסקה ראשונה\nפסקה שנייה\n'},
            ]),
            contentPlain: 'פסקה ראשונה\nפסקה שנייה',
          ),
        ],
        locationRef: (_) => null,
      );

      final bodyTexts = blocks
          .where((b) => b.kind == PrintBlockKind.text)
          .map((b) => b.text);
      expect(bodyTexts, ['פסקה ראשונה', 'פסקה שנייה']);
    });

    test('קישור חיצוני (http) נשמר כטקסט וקישור פנימי מושמט', () {
      final blocks = service.buildWordExportBlocks(
        notes: [
          _note(
            id: 'a',
            bookId: 'ברכות',
            lineNumber: 5,
            contentFormat: PersonalNoteContentFormat.quillDelta,
            content: jsonEncode([
              {
                'insert': 'מקור',
                'attributes': {'link': 'https://example.com'},
              },
              {'insert': ' וגם '},
              {
                'insert': 'הערה אחרת',
                'attributes': {'link': 'otzaria://note/pn_123'},
              },
              {'insert': '\n'},
            ]),
            contentPlain: 'מקור וגם הערה אחרת',
          ),
        ],
        locationRef: (_) => null,
      );

      final text = blocks.last.text;
      expect(text, contains('מקור (https://example.com)'));
      expect(text, contains('הערה אחרת'));
      expect(text, isNot(contains('otzaria://')));
    });

    test('תווי HTML בתוכן ובכותרות עוברים escaping', () {
      final blocks = service.buildWordExportBlocks(
        notes: [
          _note(
            id: 'a',
            bookId: 'ספר <מיוחד> & נדיר',
            lineNumber: 5,
            content: 'a < b & c > d',
          ),
        ],
        locationRef: (_) => null,
      );

      final bookHeading = blocks.first;
      expect(bookHeading.text, 'ספר &lt;מיוחד&gt; &amp; נדיר');
      expect(blocks.last.text, 'a &lt; b &amp; c &gt; d');
    });

    test('Delta לא תקין נופל בחזרה ל-contentPlain', () {
      final blocks = service.buildWordExportBlocks(
        notes: [
          _note(
            id: 'a',
            bookId: 'ברכות',
            lineNumber: 5,
            contentFormat: PersonalNoteContentFormat.quillDelta,
            content: 'לא JSON בכלל',
            contentPlain: 'הטקסט הפשוט',
          ),
        ],
        locationRef: (_) => null,
      );

      expect(blocks.last.text, 'הטקסט הפשוט');
    });
  });
}
