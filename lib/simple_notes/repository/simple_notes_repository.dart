import '../models/simple_note.dart';
import '../models/annotation_mapping.dart';
import '../models/location_verification_result.dart';
import '../data/file_system_notes_provider.dart';
import '../services/location_verification_service.dart';

/// מאגר לניהול הערות פשוטות
///
/// אחראי על לוגיקה עסקית וניהול הערות, כולל יצירה, קריאה,
/// עדכון, מחיקה, ואימות מיקום.
class SimpleNotesRepository {
  static SimpleNotesRepository? _instance;

  final FileSystemNotesProvider _provider = FileSystemNotesProvider.instance;
  final LocationVerificationService _verificationService =
      LocationVerificationService.instance;

  SimpleNotesRepository._();

  /// Singleton instance
  static SimpleNotesRepository get instance {
    _instance ??= SimpleNotesRepository._();
    return _instance!;
  }

  /// יצירת הערה חדשה
  ///
  /// יוצר הערה חדשה ושומר אותה בקבצי הטקסט וה-JSON.
  Future<SimpleNote> createNote({
    required String bookTitle,
    required int lineNumber,
    required String lineText,
    required String content,
  }) async {
    // חילוץ 10 מילים ראשונות
    final firstWords = _verificationService.extractFirstWords(lineText);

    // יצירת מזהה ייחודי
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp % 10000).toString().padLeft(4, '0');
    final noteId = 'note_${timestamp}_$random';

    // יצירת ההערה
    final now = DateTime.now();
    final note = SimpleNote(
      id: noteId,
      bookTitle: bookTitle,
      lineNumber: lineNumber,
      firstWords: firstWords,
      content: content,
      createdAt: now,
      updatedAt: now,
      hasLocation: true,
    );

    // שמירה בקובץ הטקסט
    final escapedContent = _provider.escapeNoteContent(content);
    final noteLine = '$noteId|${now.toIso8601String()}|$escapedContent';
    final textFileLineNumber =
        await _provider.appendNoteToFile(bookTitle, noteLine);

    // עדכון המיפוי
    final mappings = await _provider.readMappingFile(bookTitle);
    mappings.add(AnnotationMapping(
      noteId: noteId,
      lineNumber: lineNumber,
      firstWords: firstWords,
      textFileLineNumber: textFileLineNumber,
      hasLocation: true,
      lastVerified: now,
    ));
    await _provider.writeMappingFile(bookTitle, mappings);

    return note.copyWith(textFileLineNumber: textFileLineNumber);
  }

  /// קבלת כל ההערות לספר
  ///
  /// טוען את כל ההערות מקבצי הטקסט וה-JSON.
  Future<List<SimpleNote>> getNotesForBook(String bookTitle) async {
    final notesLines = await _provider.readNotesFile(bookTitle);
    final mappings = await _provider.readMappingFile(bookTitle);

    final notes = <SimpleNote>[];

    for (final mapping in mappings) {
      // מציאת השורה המתאימה בקובץ הטקסט
      if (mapping.textFileLineNumber < 1 ||
          mapping.textFileLineNumber > notesLines.length) {
        continue;
      }

      final noteLine = notesLines[mapping.textFileLineNumber - 1];
      final note = _parseNoteLine(noteLine, mapping);

      if (note != null) {
        notes.add(note);
      }
    }

    // מיון לפי מספר שורה
    notes.sort((a, b) => a.lineNumber.compareTo(b.lineNumber));

    return notes;
  }

  /// קבלת הערות עם מיקום תקין
  Future<List<SimpleNote>> getLocatedNotes(String bookTitle) async {
    final allNotes = await getNotesForBook(bookTitle);
    return allNotes.where((note) => note.hasLocation).toList();
  }

  /// קבלת הערות ללא מיקום
  Future<List<SimpleNote>> getLocationlessNotes(String bookTitle) async {
    final allNotes = await getNotesForBook(bookTitle);
    return allNotes.where((note) => !note.hasLocation).toList();
  }

  /// עדכון הערה
  ///
  /// מעדכן את תוכן ההערה בקבצי הטקסט וה-JSON.
  Future<SimpleNote> updateNote(SimpleNote note) async {
    final notesLines = await _provider.readNotesFile(note.bookTitle);
    final mappings = await _provider.readMappingFile(note.bookTitle);

    // מציאת המיפוי המתאים
    final mappingIndex = mappings.indexWhere((m) => m.noteId == note.id);
    if (mappingIndex == -1) {
      throw RepositoryException('Note not found: ${note.id}');
    }

    final mapping = mappings[mappingIndex];

    // עדכון השורה בקובץ הטקסט
    if (mapping.textFileLineNumber < 1 ||
        mapping.textFileLineNumber > notesLines.length) {
      throw RepositoryException('Invalid text file line number');
    }

    final escapedContent = _provider.escapeNoteContent(note.content);
    final updatedNoteLine =
        '${note.id}|${note.updatedAt.toIso8601String()}|$escapedContent';
    notesLines[mapping.textFileLineNumber - 1] = updatedNoteLine;

    await _provider.writeNotesFile(note.bookTitle, notesLines);

    return note.copyWith(updatedAt: DateTime.now());
  }

  /// מחיקת הערה
  ///
  /// מוחק את ההערה מקבצי הטקסט וה-JSON.
  Future<void> deleteNote(String noteId, String bookTitle) async {
    final notesLines = await _provider.readNotesFile(bookTitle);
    final mappings = await _provider.readMappingFile(bookTitle);

    // מציאת המיפוי המתאים
    final mappingIndex = mappings.indexWhere((m) => m.noteId == noteId);
    if (mappingIndex == -1) {
      throw RepositoryException('Note not found: $noteId');
    }

    final mapping = mappings[mappingIndex];

    // מחיקת השורה מקובץ הטקסט
    if (mapping.textFileLineNumber >= 1 &&
        mapping.textFileLineNumber <= notesLines.length) {
      notesLines.removeAt(mapping.textFileLineNumber - 1);
    }

    // עדכון מספרי השורות של המיפויים האחרים
    for (int i = 0; i < mappings.length; i++) {
      if (mappings[i].textFileLineNumber > mapping.textFileLineNumber) {
        mappings[i] = mappings[i].copyWith(
          textFileLineNumber: mappings[i].textFileLineNumber - 1,
        );
      }
    }

    // מחיקת המיפוי
    mappings.removeAt(mappingIndex);

    // שמירה
    await _provider.writeNotesFile(bookTitle, notesLines);
    await _provider.writeMappingFile(bookTitle, mappings);
  }

  /// מיקום מחדש של הערה
  ///
  /// מעדכן את המיקום של הערה לשורה חדשה.
  Future<SimpleNote> relocateNote({
    required String noteId,
    required String bookTitle,
    required int newLineNumber,
    required String newLineText,
  }) async {
    final mappings = await _provider.readMappingFile(bookTitle);

    // מציאת המיפוי המתאים
    final mappingIndex = mappings.indexWhere((m) => m.noteId == noteId);
    if (mappingIndex == -1) {
      throw RepositoryException('Note not found: $noteId');
    }

    // חילוץ מילים ראשונות חדשות
    final newFirstWords = _verificationService.extractFirstWords(newLineText);

    // עדכון המיפוי
    mappings[mappingIndex] = mappings[mappingIndex].copyWith(
      lineNumber: newLineNumber,
      firstWords: newFirstWords,
      hasLocation: true,
      lastVerified: DateTime.now(),
    );

    await _provider.writeMappingFile(bookTitle, mappings);

    // החזרת ההערה המעודכנת
    final notes = await getNotesForBook(bookTitle);
    return notes.firstWhere((note) => note.id == noteId);
  }

  /// אימות מיקום הערות
  ///
  /// בודק את כל ההערות ומעדכן את המיקומים שלהן לפי הצורך.
  Future<LocationVerificationResult> verifyNoteLocations({
    required String bookTitle,
    required String bookText,
  }) async {
    final notes = await getNotesForBook(bookTitle);
    final updates = await _verificationService.verifyAllNotes(
      notes: notes,
      bookText: bookText,
    );

    int anchoredCount = 0;
    int shiftedCount = 0;
    int locationlessCount = 0;

    // עדכון המיפויים
    final mappings = await _provider.readMappingFile(bookTitle);

    for (final update in updates) {
      final mappingIndex =
          mappings.indexWhere((m) => m.noteId == update.noteId);
      if (mappingIndex == -1) continue;

      if (update.isLocationless) {
        // הערה ללא מיקום
        mappings[mappingIndex] = mappings[mappingIndex].copyWith(
          hasLocation: false,
          lastVerified: DateTime.now(),
        );
        locationlessCount++;
      } else if (update.newLine != update.originalLine) {
        // מיקום השתנה
        final lines = bookText.split('\n');
        final newLineIndex = update.newLine! - 1;
        final newLineText = lines[newLineIndex];
        final newFirstWords =
            _verificationService.extractFirstWords(newLineText);

        mappings[mappingIndex] = mappings[mappingIndex].copyWith(
          lineNumber: update.newLine!,
          firstWords: newFirstWords,
          hasLocation: true,
          lastVerified: DateTime.now(),
        );
        shiftedCount++;
      } else {
        // מיקום נשאר זהה
        mappings[mappingIndex] = mappings[mappingIndex].copyWith(
          lastVerified: DateTime.now(),
        );
        anchoredCount++;
      }
    }

    await _provider.writeMappingFile(bookTitle, mappings);

    return LocationVerificationResult(
      totalNotes: notes.length,
      anchoredNotes: anchoredCount,
      shiftedNotes: shiftedCount,
      locationlessNotes: locationlessCount,
      updates: updates,
    );
  }

  /// פענוח שורת הערה מקובץ הטקסט
  SimpleNote? _parseNoteLine(String noteLine, AnnotationMapping mapping) {
    try {
      final parts = noteLine.split('|');
      if (parts.length < 3) return null;

      final noteId = parts[0];
      final timestamp = DateTime.parse(parts[1]);
      final escapedContent = parts.sublist(2).join('|'); // במקרה שיש | בתוכן
      final content = _provider.unescapeNoteContent(escapedContent);

      return SimpleNote(
        id: noteId,
        bookTitle: mapping.noteId.split('_').first, // זמני
        lineNumber: mapping.lineNumber,
        firstWords: mapping.firstWords,
        content: content,
        createdAt: timestamp,
        updatedAt: timestamp,
        hasLocation: mapping.hasLocation,
        textFileLineNumber: mapping.textFileLineNumber,
      );
    } catch (e) {
      return null;
    }
  }
}

/// Exception for repository operations
class RepositoryException implements Exception {
  final String message;

  RepositoryException(this.message);

  @override
  String toString() => 'RepositoryException: $message';
}
