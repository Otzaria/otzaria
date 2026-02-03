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
}
