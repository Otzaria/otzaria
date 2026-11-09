import 'dart:math';

import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';
import 'package:otzaria/personal_notes/utils/note_anchor_utils.dart';
import 'package:otzaria/personal_notes/utils/note_collection_utils.dart';
import 'package:otzaria/personal_notes/utils/note_text_utils.dart';
import 'package:otzaria/personal_notes/utils/personal_notes_book_key.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as text_utils;

class PersonalNotesService {
  final PersonalNotesDatabase _database;
  final Random _random;

  PersonalNotesService({PersonalNotesDatabase? database, Random? random})
    : _database = database ?? PersonalNotesDatabase.instance,
      _random = random ?? Random();

  Future<List<PersonalNote>> loadNotes({
    required String bookId,
    required String bookContent,
  }) async {
    final notes = await _database.loadNotes(bookId);
    // רוב הספרים בלי הערות, ופיצול ספר גדול לשורות עולה עשרות ms.
    if (notes.isEmpty) return notes;
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
    int? selectionColumn,
    String? sourceSelectedText,
    int? sourceSelectionOffset,
    bool punctuationHidden = false,
    PdfNoteAnchor? pdfAnchor,
  }) async {
    await createNote(
      bookId: bookId,
      bookContent: bookContent,
      lineNumber: lineNumber,
      content: content,
      contentPlain: contentPlain,
      contentFormat: contentFormat,
      selectedText: selectedText,
      selectionColumn: selectionColumn,
      sourceSelectedText: sourceSelectedText,
      sourceSelectionOffset: sourceSelectionOffset,
      punctuationHidden: punctuationHidden,
      pdfAnchor: pdfAnchor,
    );
    return _database.loadNotes(bookId);
  }

  /// אישור השמירה תלוי בכתיבה בלבד; כשל ברענון אינו מצדיק הוספה חוזרת.
  Future<PersonalNote> createNote({
    required String bookId,
    required String bookContent,
    required int lineNumber,
    required String content,
    required String contentPlain,
    required PersonalNoteContentFormat contentFormat,
    String? selectedText,
    int? selectionColumn,
    String? sourceSelectedText,
    int? sourceSelectionOffset,
    bool punctuationHidden = false,
    PdfNoteAnchor? pdfAnchor,
  }) async {
    final lines = splitBookContentIntoLines(bookContent);
    // ספר ללא תוכן טקסטואלי (PDF): lineNumber הוא מספר עמוד ונשמר כפי שהוא,
    // אחרת כיווץ ל-1 היה מאחד את כל ההערות לעמוד הראשון.
    final normalizedLineNumber =
        pdfAnchor?.pageNumber ??
        (lines.isEmpty
            ? max(1, lineNumber)
            : lineNumber.clamp(1, lines.length));

    // Use selectedText if provided, otherwise extract display text from the line
    // Always remove nikud and te'amim from the display title
    final trimmedSelectedText = selectedText?.trim();
    final hasSelection =
        trimmedSelectedText != null && trimmedSelectedText.isNotEmpty;
    final displayTitle = hasSelection
        ? removeHebrewDiacritics(trimmedSelectedText)
        : pdfAnchor != null
        ? ''
        : extractDisplayTextFromLines(
            lines,
            normalizedLineNumber,
            excludeBookTitle: _bookTitle(bookId),
          );

    // עיגון לפי מילים: כשנבחר טקסט ספציפי, מחשבים offset והקשר בשורה הגולמית.
    // ללא בחירה — ההערה נחשבת הערת-שורה-שלמה (anchorText = null).
    String? anchorText;
    String? anchorPrefix;
    String? anchorSuffix;
    int? anchorStart;
    int? anchorEnd;
    if (hasSelection && lines.isNotEmpty && pdfAnchor == null) {
      final rawLine = lines[normalizedLineNumber - 1];
      final computed = computeAnchorForSelection(
        rawLine: rawLine,
        selectedText: sourceSelectedText ?? trimmedSelectedText,
        selectionColumnHint: selectionColumn,
        sourceSelectionOffset: sourceSelectionOffset,
        sourceSelectionText: sourceSelectedText == null
            ? null
            : text_utils.stripHtmlIfNeeded(rawLine),
        punctuationHidden: punctuationHidden,
      );
      if (computed != null) {
        anchorText = normalizeAnchorText(
          sourceSelectedText ?? trimmedSelectedText,
        );
        anchorPrefix = computed.prefix;
        anchorSuffix = computed.suffix;
        anchorStart = computed.start;
        anchorEnd = computed.end;
      }
    }

    final now = DateTime.now();
    final newNote = PersonalNote(
      id: _generateId(),
      bookId: bookId,
      lineNumber: normalizedLineNumber,
      displayTitle: displayTitle,
      anchorText: anchorText,
      anchorPrefix: anchorPrefix,
      anchorSuffix: anchorSuffix,
      anchorStart: anchorStart,
      anchorEnd: anchorEnd,
      pdfAnchor: pdfAnchor,
      lastKnownLineNumber: null,
      status: PersonalNoteStatus.located,
      content: content.trimRight(),
      contentPlain: contentPlain.trimRight(),
      contentFormat: contentFormat,
      createdAt: now,
      updatedAt: now,
    );

    await _database.insertNote(newNote);
    return newNote;
  }

  Future<List<PersonalNote>> updateNote({
    required String bookId,
    required String bookContent,
    required String noteId,
    String? content,
    String? contentPlain,
    PersonalNoteContentFormat? contentFormat,
  }) async {
    await persistNote(
      bookId: bookId,
      bookContent: bookContent,
      noteId: noteId,
      content: content,
      contentPlain: contentPlain,
      contentFormat: contentFormat,
    );
    return loadNotes(bookId: bookId, bookContent: bookContent);
  }

  /// העריכה נשמרת לפני אישור הסגירה, בלי לחייב רענון של יתר הערות הספר.
  Future<PersonalNote> persistNote({
    required String bookId,
    required String bookContent,
    required String noteId,
    String? content,
    String? contentPlain,
    PersonalNoteContentFormat? contentFormat,
  }) async {
    final note = await _database.getNote(noteId);
    if (note == null) {
      throw StateError(NotesMessages.noteNoLongerExists);
    }
    if (note.bookId != bookId) {
      throw StateError(NotesMessages.noteMovedToDifferentBook);
    }

    final nextContent = content?.trimRight() ?? note.content;
    final nextContentPlain = contentPlain?.trimRight() ?? note.contentPlain;
    final nextContentFormat = contentFormat ?? note.contentFormat;
    final hasContentChanges =
        nextContent != note.content ||
        nextContentPlain != note.contentPlain ||
        nextContentFormat != note.contentFormat;
    final updatedNote = _reconcileLocation(
      note.copyWith(
        content: nextContent,
        contentPlain: nextContentPlain,
        contentFormat: nextContentFormat,
        // פתיחה ושמירה ללא שינוי אינן עריכה ואינן משנות את מועד העדכון.
        updatedAt: hasContentChanges ? DateTime.now() : note.updatedAt,
      ),
      splitBookContentIntoLines(bookContent),
      bookId,
    );

    await _database.updateNote(updatedNote);
    return updatedNote;
  }

  Future<List<PersonalNote>> deleteNote({
    required String bookId,
    required String noteId,
  }) async {
    await removeNote(noteId: noteId);
    return await _database.loadNotes(bookId);
  }

  /// אישור המחיקה אינו תלוי בקריאת הרשימה שאחריה.
  Future<void> removeNote({required String noteId}) =>
      _database.deleteNote(noteId);

  Future<List<PersonalNote>> repositionNote({
    required String bookId,
    required String bookContent,
    required String noteId,
    required int lineNumber,
    PdfNoteAnchor? pdfAnchor,
  }) async {
    await moveNote(
      bookId: bookId,
      bookContent: bookContent,
      noteId: noteId,
      lineNumber: lineNumber,
      pdfAnchor: pdfAnchor,
    );
    return _database.loadNotes(bookId);
  }

  /// מחזיר את ההערה לאחר כתיבת המיקום, בלי לטעון את יתר הערות הספר.
  Future<PersonalNote> moveNote({
    required String bookId,
    required String bookContent,
    required String noteId,
    required int lineNumber,
    PdfNoteAnchor? pdfAnchor,
  }) async {
    final note = await _database.getNote(noteId);
    if (note == null) {
      throw StateError(NotesMessages.noteNoLongerExists);
    }
    if (note.bookId != bookId) {
      throw StateError(NotesMessages.noteMovedToDifferentBook);
    }

    final lines = splitBookContentIntoLines(bookContent);
    // ספר ללא תוכן טקסטואלי (PDF): lineNumber הוא מספר עמוד ונשמר כפי שהוא,
    // אחרת כיווץ ל-1 היה מאחד את כל ההערות לעמוד הראשון.
    final normalizedLineNumber =
        pdfAnchor?.pageNumber ??
        (lines.isEmpty
            ? max(1, lineNumber)
            : lineNumber.clamp(1, lines.length));
    final newDisplayTitle = pdfAnchor != null
        ? ''
        : extractDisplayTextFromLines(
            lines,
            normalizedLineNumber,
            excludeBookTitle: _bookTitle(bookId),
          );
    final now = DateTime.now();

    final updatedNote = note.copyWith(
      lineNumber: normalizedLineNumber,
      displayTitle: newDisplayTitle,
      // מיקום ידני מחדש הופך את ההערה להערת-שורה-שלמה (אין עוד מילים מעוגנות).
      clearAnchor: true,
      pdfAnchor: pdfAnchor,
      clearPdfAnchor: pdfAnchor == null,
      clearLastKnownLineNumber: true,
      status: PersonalNoteStatus.located,
      updatedAt: now,
    );

    await _database.updateNote(updatedNote);
    return updatedNote;
  }

  PersonalNote _reconcileLocation(
    PersonalNote note,
    List<String> lines,
    String bookId,
  ) {
    // ספר ללא תוכן טקסטואלי (PDF): אין שורות לעגן אליהן — ה-lineNumber הוא
    // מספר עמוד ונשאר תקף, בלי לסמן 'חסר'.
    if (lines.isEmpty || note.pdfAnchor != null) {
      return note;
    }

    if (note.status == PersonalNoteStatus.missing) {
      final previousLine = note.lastKnownLineNumber ?? note.lineNumber;
      if (previousLine != null &&
          previousLine > 0 &&
          previousLine <= lines.length &&
          _noteMatchesLine(note, lines[previousLine - 1])) {
        return note.copyWith(
          lineNumber: previousLine,
          status: PersonalNoteStatus.located,
        );
      }
      return note;
    }
    if (note.lineNumber == null) return note;

    final lineIndex = note.lineNumber! - 1;
    if (lineIndex < 0 || lineIndex >= lines.length) {
      return note.copyWith(
        status: PersonalNoteStatus.missing,
        lastKnownLineNumber: note.lineNumber,
        clearLineNumber: true,
      );
    }

    // הטקסט המעוגן (בהערה בלי עוגן — הכותרת) עדיין בשורה: המיקום תקף.
    if (_noteMatchesLine(note, lines[lineIndex])) {
      return note;
    }

    // Fallback: check if line start matches (for notes without selected text)
    if (!_hasAnchor(note)) {
      final actualDisplayTitle = extractDisplayTextFromLines(
        lines,
        note.lineNumber!,
        excludeBookTitle: _bookTitle(bookId),
      );
      if (_displayTitleMatches(note.displayTitle, actualDisplayTitle)) {
        return note;
      }
    }

    // הערות מעוגנות יחפשו nearby לפי טקסט המקור; ישנות לפי כותרת.
    final match = _searchNearby(
      lines,
      note.lineNumber!,
      note,
      bookId,
    );
    if (match != null) {
      // Found the note in a new location - update line number but keep displayTitle
      return note.copyWith(
        lineNumber: match.line,
        lastKnownLineNumber: note.lineNumber,
        status: PersonalNoteStatus.located,
      );
    }

    return note.copyWith(
      status: PersonalNoteStatus.missing,
      lastKnownLineNumber: note.lineNumber,
      clearLineNumber: true,
    );
  }

  /// האם הטקסט שאליו [note] מעוגנת נמצא בשורה [lineNumber] של [lines].
  bool noteTextMatchesLine(
    PersonalNote note,
    List<String> lines,
    int lineNumber,
    String bookId,
  ) {
    if (lineNumber < 1 || lineNumber > lines.length) return false;
    if (_noteMatchesLine(note, lines[lineNumber - 1])) return true;
    if (_hasAnchor(note)) return false;
    final title = note.displayTitle;
    if (title == null || title.isEmpty) return false;
    return _displayTitleMatches(
      title,
      extractDisplayTextFromLines(
        lines,
        lineNumber,
        excludeBookTitle: _bookTitle(bookId),
      ),
    );
  }

  bool _hasAnchor(PersonalNote note) =>
      note.anchorText != null && note.anchorText!.isNotEmpty;

  bool _noteMatchesLine(PersonalNote note, String lineContent) {
    if (_hasAnchor(note)) {
      final anchor = normalizeAnchorText(note.anchorText!);
      return anchor.isNotEmpty && lineContainsAnchorText(lineContent, anchor);
    }
    return _displayTitleExistsInLine(note.displayTitle, lineContent);
  }

  /// Check if the displayTitle text exists anywhere in the line
  bool _displayTitleExistsInLine(String? displayTitle, String lineContent) {
    if (displayTitle == null || displayTitle.isEmpty) {
      return false;
    }

    final normalizedTitle = normalizeAnchorText(displayTitle);
    if (normalizedTitle.isEmpty) return false;
    return lineContainsAnchorText(lineContent, normalizedTitle);
  }

  _LineMatch? _searchNearby(
    List<String> lines,
    int centerLine,
    PersonalNote note,
    String bookId,
  ) {
    final referenceTitle = note.displayTitle;
    if (_hasAnchor(note)) {
      for (int offset = -5; offset <= 5; offset++) {
        if (offset == 0) continue;
        final candidateLine = centerLine + offset;
        if (candidateLine < 1 || candidateLine > lines.length) continue;
        if (_noteMatchesLine(note, lines[candidateLine - 1])) {
          return _LineMatch(line: candidateLine);
        }
      }
      return null;
    }
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
      final candidateTitle = extractDisplayTextFromLines(
        lines,
        candidateLine,
        excludeBookTitle: _bookTitle(bookId),
      );
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

    final storedWords = stored
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final actualWords = actual
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    return computeWordOverlapRatio(storedWords, actualWords) >= 0.8;
  }

  // מילות הכותרת מוחרגות מתמצית השורה; סיומת המקור במפתח אינה חלק מהכותרת.
  static String _bookTitle(String bookId) =>
      parsePersonalNotesBookKey(bookId).title;

  String _generateId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final randomPart = _random
        .nextInt(1 << 32)
        .toRadixString(16)
        .padLeft(8, '0');
    return 'pn_$timestamp$randomPart';
  }
}

class _LineMatch {
  final int line;

  _LineMatch({required this.line});
}
