import 'dart:math';

import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/utils/note_collection_utils.dart';
import 'package:otzaria/personal_notes/utils/note_text_utils.dart';

class PersonalNotesService {
  final PersonalNotesDatabase _database;
  final Random _random;

  PersonalNotesService({
    PersonalNotesDatabase? database,
    Random? random,
  })  : _database = database ?? PersonalNotesDatabase.instance,
        _random = random ?? Random();

  Future<List<PersonalNote>> loadNotes({
    required String bookId,
    required String bookContent,
  }) async {
    final notes = await _database.loadNotes(bookId);
    final lines = splitBookContentIntoLines(bookContent);

    final changedNotes = <PersonalNote>[];
    final reconciled = <PersonalNote>[];

    for (final note in notes) {
      final updated = _reconcileLocation(note, lines, bookId);
      if (updated != note) {
        changedNotes.add(updated);
      }
      reconciled.add(updated);
    }

    // Batch update changed notes
    if (changedNotes.isNotEmpty) {
      await _database.batchUpdateNotes(changedNotes);
    }

    return sortPersonalNotes(reconciled);
  }

  Future<List<PersonalNote>> addNote({
    required String bookId,
    required String bookContent,
    required int lineNumber,
    required String content,
    required String contentPlain,
    required PersonalNoteContentFormat contentFormat,
    String? selectedText,
  }) async {
    final lines = splitBookContentIntoLines(bookContent);
    // Handle empty book content - use line 1 as minimum
    final maxLine = lines.isEmpty ? 1 : lines.length;
    final normalizedLineNumber = lineNumber.clamp(1, maxLine);

    // Use selectedText if provided, otherwise extract display text from the line
    // Always remove nikud and te'amim from the display title
    final trimmedSelectedText = selectedText?.trim();
    final displayTitle =
        (trimmedSelectedText != null && trimmedSelectedText.isNotEmpty)
            ? removeHebrewDiacritics(trimmedSelectedText)
            : extractDisplayTextFromLines(lines, normalizedLineNumber,
                excludeBookTitle: bookId);

    final now = DateTime.now();
    final newNote = PersonalNote(
      id: _generateId(),
      bookId: bookId,
      lineNumber: normalizedLineNumber,
      displayTitle: displayTitle,
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      content: content.trimRight(),
      contentPlain: contentPlain.trimRight(),
      contentFormat: contentFormat,
      createdAt: now,
      updatedAt: now,
    );

    await _database.insertNote(newNote);

    return await _database.loadNotes(bookId);
  }

  Future<List<PersonalNote>> updateNote({
    required String bookId,
    required String bookContent,
    required String noteId,
    String? content,
    String? contentPlain,
    PersonalNoteContentFormat? contentFormat,
  }) async {
    final note = await _database.getNote(noteId);
    if (note == null) {
      return await _database.loadNotes(bookId);
    }

    final now = DateTime.now();
    final updatedNote = note.copyWith(
      content: content?.trimRight() ?? note.content,
      contentPlain: contentPlain?.trimRight() ?? note.contentPlain,
      contentFormat: contentFormat ?? note.contentFormat,
      updatedAt: now,
    );

    await _database.updateNote(updatedNote);

    // Reconcile all notes after update
    return await loadNotes(bookId: bookId, bookContent: bookContent);
  }

  Future<List<PersonalNote>> deleteNote({
    required String bookId,
    required String bookContent,
    required String noteId,
  }) async {
    await _database.deleteNote(noteId);
    return await _database.loadNotes(bookId);
  }

  Future<List<PersonalNote>> repositionNote({
    required String bookId,
    required String bookContent,
    required String noteId,
    required int lineNumber,
  }) async {
    final note = await _database.getNote(noteId);
    if (note == null) {
      return await _database.loadNotes(bookId);
    }

    final lines = splitBookContentIntoLines(bookContent);
    // Handle empty book content - use line 1 as minimum
    final maxLine = lines.isEmpty ? 1 : lines.length;
    final normalizedLineNumber = lineNumber.clamp(1, maxLine);
    final newDisplayTitle = extractDisplayTextFromLines(
        lines, normalizedLineNumber,
        excludeBookTitle: bookId);
    final now = DateTime.now();

    final updatedNote = note.copyWith(
      lineNumber: normalizedLineNumber,
      displayTitle: newDisplayTitle,
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      updatedAt: now,
    );

    await _database.updateNote(updatedNote);

    return await _database.loadNotes(bookId);
  }

  PersonalNote _reconcileLocation(
      PersonalNote note, List<String> lines, String bookId) {
    if (note.status == PersonalNoteStatus.missing || note.lineNumber == null) {
      return note;
    }

    final lineIndex = note.lineNumber! - 1;
    if (lineIndex < 0 || lineIndex >= lines.length) {
      return note.copyWith(
        status: PersonalNoteStatus.missing,
        lastKnownLineNumber: note.lineNumber,
        lineNumber: null,
        updatedAt: DateTime.now(),
      );
    }

    // Check if displayTitle exists in the current line (anywhere, not just at the start)
    // This handles cases where user selected text from the middle of the line
    if (_displayTitleExistsInLine(note.displayTitle, lines[lineIndex])) {
      // Location is still valid - no change needed
      return note;
    }

    // Fallback: check if line start matches (for notes without selected text)
    final actualDisplayTitle = extractDisplayTextFromLines(
        lines, note.lineNumber!,
        excludeBookTitle: bookId);
    if (_displayTitleMatches(note.displayTitle, actualDisplayTitle)) {
      return note;
    }

    // Try to find the note in nearby lines using displayTitle
    final match =
        _searchNearby(lines, note.lineNumber!, note.displayTitle, bookId);
    if (match != null) {
      // Found the note in a new location - update line number but keep displayTitle
      return note.copyWith(
        lineNumber: match.line,
        lastKnownLineNumber: note.lineNumber,
        status: PersonalNoteStatus.located,
        updatedAt: DateTime.now(),
      );
    }

    return note.copyWith(
      status: PersonalNoteStatus.missing,
      lastKnownLineNumber: note.lineNumber,
      lineNumber: null,
      updatedAt: DateTime.now(),
    );
  }

  /// Check if the displayTitle text exists anywhere in the line
  bool _displayTitleExistsInLine(String? displayTitle, String lineContent) {
    if (displayTitle == null || displayTitle.isEmpty) {
      return false;
    }

    // Normalize both strings for comparison (remove diacritics)
    final normalizedTitle = removeHebrewDiacritics(displayTitle);
    final normalizedLine = removeHebrewDiacritics(lineContent);

    // Check if the title exists in the line
    return normalizedLine.contains(normalizedTitle);
  }

  _LineMatch? _searchNearby(
    List<String> lines,
    int centerLine,
    String? referenceTitle,
    String bookId,
  ) {
    if (referenceTitle == null || referenceTitle.isEmpty) {
      return null;
    }

    for (int offset = -5; offset <= 5; offset++) {
      if (offset == 0) continue;
      final candidateLine = centerLine + offset;
      if (candidateLine < 1 || candidateLine > lines.length) {
        continue;
      }

      final lineIndex = candidateLine - 1;

      // First check if displayTitle exists anywhere in the line
      if (_displayTitleExistsInLine(referenceTitle, lines[lineIndex])) {
        return _LineMatch(line: candidateLine);
      }

      // Fallback: check line start match
      final candidateTitle = extractDisplayTextFromLines(lines, candidateLine,
          excludeBookTitle: bookId);
      if (_displayTitleMatches(referenceTitle, candidateTitle)) {
        return _LineMatch(line: candidateLine);
      }
    }
    return null;
  }

  /// Check if two display titles match (at least 80% word overlap)
  bool _displayTitleMatches(String? stored, String? actual) {
    if (stored == null || stored.isEmpty) {
      return actual == null || actual.isEmpty;
    }
    if (actual == null || actual.isEmpty) {
      return false;
    }

    final storedWords =
        stored.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final actualWords =
        actual.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    return computeWordOverlapRatio(storedWords, actualWords) >= 0.8;
  }

  String _generateId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final randomPart =
        _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return 'pn_$timestamp$randomPart';
  }
}

class _LineMatch {
  final int line;

  _LineMatch({
    required this.line,
  });
}
