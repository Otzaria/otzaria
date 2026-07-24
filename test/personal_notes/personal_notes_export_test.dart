import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_notes_import_export_service.dart';

void main() {
  test('export payload includes content format fields', () {
    final service = PersonalNotesImportExportService();
    final note = PersonalNote(
      id: 'pn_1',
      bookId: 'Test Book',
      lineNumber: 1,
      displayTitle: 'כותרת',
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      content: '[{"insert":"שלום"},{"insert":"\n"}]',
      contentPlain: 'שלום',
      contentFormat: PersonalNoteContentFormat.quillDelta,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 2),
    );

    final payload = service.buildExport(notes: [note]);
    expect(payload['version'], '2.0');
    final notes = payload['notes'] as List<dynamic>;
    expect(notes, hasLength(1));
    final exported = notes.first as Map<String, dynamic>;
    expect(exported['contentFormat'], 'quillDelta');
    expect(exported['contentPlain'], 'שלום');
  });

  test('plain text export is human readable and uses contentPlain', () {
    final service = PersonalNotesImportExportService();
    final notes = [
      PersonalNote(
        id: 'pn_1',
        bookId: 'בראשית',
        lineNumber: 5,
        displayTitle: 'הערה ראשונה',
        lastKnownLineNumber: null,
        status: PersonalNoteStatus.located,
        content: '[{"insert":"טקסט מעוצב"},{"insert":"\n"}]',
        contentPlain: 'טקסט מעוצב',
        contentFormat: PersonalNoteContentFormat.quillDelta,
        createdAt: DateTime(2025, 1, 1),
        updatedAt: DateTime(2025, 3, 7),
      ),
      PersonalNote(
        id: 'pn_2',
        bookId: 'שמות',
        lineNumber: null,
        displayTitle: null,
        lastKnownLineNumber: null,
        status: PersonalNoteStatus.located,
        content: 'הערה שנייה',
        contentPlain: 'הערה שנייה',
        contentFormat: PersonalNoteContentFormat.plain,
        createdAt: DateTime(2025, 1, 1),
        updatedAt: DateTime(2025, 1, 2),
      ),
    ];

    final text = service.buildPlainTextExport(
      notes: notes,
      description: 'כל ההערות',
    );

    // כותרת ומטא-דאטה קריאים
    expect(text, contains('הערות אישיות מאוצריא'));
    expect(text, contains('כל ההערות'));
    expect(text, contains('מספר הערות: 2'));
    // תוכן ההערה (טקסט פשוט, לא JSON גולמי)
    expect(text, contains('טקסט מעוצב'));
    expect(text, isNot(contains('"insert"')));
    // כותרת ושורה מוצגים, ותאריך מפורמט dd/MM/yyyy
    expect(text, contains('[1] הערה ראשונה'));
    expect(text, contains('שורה: 5'));
    expect(text, contains('07/03/2025'));
    // הערה ללא כותרת נופלת חזרה לשם הספר, וללא שדה "שורה"
    expect(text, contains('[2] שמות'));
  });

  test('plain text export preserves link targets (P2)', () {
    final service = PersonalNotesImportExportService();
    final note = PersonalNote(
      id: 'pn_1',
      bookId: 'Test',
      lineNumber: 1,
      displayTitle: 'הערה עם קישור',
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      content: jsonEncode([
        {'insert': 'ראו '},
        {
          'insert': 'לחץ כאן',
          'attributes': {'link': 'https://example.com/page'},
        },
        {'insert': ' להמשך'},
        {'insert': '\n'},
      ]),
      contentPlain: 'ראו לחץ כאן להמשך',
      contentFormat: PersonalNoteContentFormat.quillDelta,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 2),
    );

    final text = service.buildPlainTextExport(notes: [note]);

    // יעד הקישור נשמר בתבנית "טקסט (יעד)" ולא אובד
    expect(text, contains('לחץ כאן (https://example.com/page) להמשך'));
  });

  test('plain text export keeps intentional leading whitespace (P3)', () {
    final service = PersonalNotesImportExportService();
    final note = PersonalNote(
      id: 'pn_1',
      bookId: 'Test',
      lineNumber: 1,
      displayTitle: 'כותרת',
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      // שורת רווח פותחת + הזחה — נשמרו בעת השמירה (trimRight בלבד)
      content: '\n  טקסט מוזח',
      contentPlain: '\n  טקסט מוזח',
      contentFormat: PersonalNoteContentFormat.plain,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 2),
    );

    final text = service.buildPlainTextExport(notes: [note]);

    // ההזחה והשורה הפותחת לא נמחקות (לא נעשה trim מוביל)
    expect(text, contains('\n  טקסט מוזח'));
  });
}
