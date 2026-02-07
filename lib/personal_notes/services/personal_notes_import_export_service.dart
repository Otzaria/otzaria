import 'dart:convert';
import 'dart:io';

import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';

enum NotesImportConflictStrategy {
  merge,
  skip,
  keepBoth,
  overwrite,
}

class NotesImportSummary {
  final int inserted;
  final int updated;
  final int skipped;
  final int duplicated;

  const NotesImportSummary({
    required this.inserted,
    required this.updated,
    required this.skipped,
    required this.duplicated,
  });
}

class PersonalNotesImportExportService {
  final PersonalNotesDatabase _database;

  PersonalNotesImportExportService({PersonalNotesDatabase? database})
      : _database = database ?? PersonalNotesDatabase.instance;

  Map<String, dynamic> buildExport({
    required List<PersonalNote> notes,
    String? description,
  }) {
    return {
      'version': '2.0',
      'exportedAt': DateTime.now().toIso8601String(),
      if (description != null) 'description': description,
      'notes': notes.map(_noteToJson).toList(),
    };
  }

  Future<void> exportToFile({
    required String path,
    required List<PersonalNote> notes,
    String? description,
  }) async {
    final payload = buildExport(notes: notes, description: description);
    final file = File(path);
    await file.writeAsString(jsonEncode(payload));
  }

  Future<NotesImportSummary> importFromFile({
    required String path,
    required NotesImportConflictStrategy strategy,
  }) async {
    final file = File(path);
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final version = decoded['version'] as String? ?? '1.0';
    if (!version.startsWith('2')) {
      throw Exception('גרסת ייצוא לא נתמכת: $version');
    }

    final notesJson = decoded['notes'] as List<dynamic>? ?? const [];
    int inserted = 0;
    int updated = 0;
    int skipped = 0;
    int duplicated = 0;

    for (final item in notesJson) {
      if (item is! Map<String, dynamic>) continue;
      final note = _noteFromJson(item);
      final existing = await _database.getNote(note.id);

      if (existing == null) {
        await _database.insertNote(note);
        inserted++;
        continue;
      }

      switch (strategy) {
        case NotesImportConflictStrategy.skip:
          skipped++;
          break;
        case NotesImportConflictStrategy.overwrite:
          await _database.updateNote(note);
          updated++;
          break;
        case NotesImportConflictStrategy.merge:
          if (note.updatedAt.isAfter(existing.updatedAt)) {
            await _database.updateNote(note);
            updated++;
          } else {
            skipped++;
          }
          break;
        case NotesImportConflictStrategy.keepBoth:
          final duplicatedNote = note.copyWith(
            content: note.content,
            contentPlain: note.contentPlain,
            contentFormat: note.contentFormat,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
          );
          final withNewId = duplicatedNote.copyWith(
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
          );
          await _database.insertNote(
            PersonalNote(
              id: _generateId(),
              bookId: withNewId.bookId,
              lineNumber: withNewId.lineNumber,
              displayTitle: withNewId.displayTitle,
              lastKnownLineNumber: withNewId.lastKnownLineNumber,
              status: withNewId.status,
              content: withNewId.content,
              contentPlain: withNewId.contentPlain,
              contentFormat: withNewId.contentFormat,
              createdAt: withNewId.createdAt,
              updatedAt: withNewId.updatedAt,
            ),
          );
          duplicated++;
          break;
      }
    }

    return NotesImportSummary(
      inserted: inserted,
      updated: updated,
      skipped: skipped,
      duplicated: duplicated,
    );
  }

  Map<String, dynamic> _noteToJson(PersonalNote note) {
    return {
      'id': note.id,
      'bookId': note.bookId,
      'lineNumber': note.lineNumber,
      'displayTitle': note.displayTitle,
      'lastKnownLineNumber': note.lastKnownLineNumber,
      'status': note.status.name,
      'content': note.content,
      'contentPlain': note.contentPlain,
      'contentFormat': note.contentFormat.name,
      'createdAt': note.createdAt.toIso8601String(),
      'updatedAt': note.updatedAt.toIso8601String(),
    };
  }

  PersonalNote _noteFromJson(Map<String, dynamic> json) {
    return PersonalNote(
      id: json['id'] as String,
      bookId: json['bookId'] as String,
      lineNumber: json['lineNumber'] as int?,
      displayTitle: json['displayTitle'] as String?,
      lastKnownLineNumber: json['lastKnownLineNumber'] as int?,
      status: PersonalNoteStatus.values.byName(json['status'] as String),
      content: json['content'] as String,
      contentPlain:
          (json['contentPlain'] as String?) ?? (json['content'] as String),
      contentFormat: PersonalNoteContentFormat.values.byName(
        json['contentFormat'] as String? ??
            PersonalNoteContentFormat.plain.name,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  String _generateId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final randomPart = timestamp.toRadixString(16).padLeft(8, '0');
    return 'pn_${timestamp}_$randomPart';
  }
}
