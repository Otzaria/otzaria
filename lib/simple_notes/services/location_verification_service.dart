import '../models/simple_note.dart';
import '../models/location_verification_result.dart';

/// שירות לאימות מיקום הערות בספר
///
/// אחראי על בדיקת התאמה בין הערות לטקסט הספר,
/// וחיפוש מיקום חדש להערות שהמיקום שלהן השתנה.
class LocationVerificationService {
  static LocationVerificationService? _instance;

  LocationVerificationService._();

  /// Singleton instance
  static LocationVerificationService get instance {
    _instance ??= LocationVerificationService._();
    return _instance!;
  }

  /// חילוץ 10 מילים ראשונות משורה
  ///
  /// מפצל את השורה למילים ולוקח עד 10 ראשונות.
  /// מסיר רווחים מיותרים וניקוד בסיסי.
  List<String> extractFirstWords(String lineText) {
    // הסרת רווחים מיותרים
    final cleaned = lineText.trim().replaceAll(RegExp(r'\s+'), ' ');

    // פיצול למילים
    final words = cleaned.split(' ');

    // לקיחת עד 10 מילים ראשונות
    final firstWords = words.take(10).toList();

    return firstWords;
  }

  /// חישוב ציון התאמה בין שתי רשימות מילים
  ///
  /// מחזיר ערך בין 0.0 ל-1.0 המייצג את אחוז ההתאמה.
  /// השוואה פשוטה של מילים (ללא נירמול מורכב).
  double calculateMatchScore(List<String> words1, List<String> words2) {
    if (words1.isEmpty && words2.isEmpty) return 1.0;
    if (words1.isEmpty || words2.isEmpty) return 0.0;

    // השוואה של המילים המשותפות
    int matches = 0;
    final minLength =
        words1.length < words2.length ? words1.length : words2.length;

    for (int i = 0; i < minLength; i++) {
      if (words1[i] == words2[i]) {
        matches++;
      }
    }

    // חישוב אחוז ההתאמה
    return matches / minLength;
  }

  /// חיפוש מיקום חדש להערה
  ///
  /// מחפש את המיקום הטוב ביותר להערה בטווח של ±5 שורות
  /// מהמיקום המקורי. מחזיר את מספר השורה החדש או null אם לא נמצא.
  Future<int?> findNewLocation({
    required List<String> firstWords,
    required int originalLine,
    required String bookText,
  }) async {
    final lines = bookText.split('\n');

    // בדיקה שהמיקום המקורי בטווח תקין
    if (originalLine < 1 || originalLine > lines.length) {
      return null;
    }

    // חיפוש בטווח של ±5 שורות
    const searchRange = 5;
    final startLine = (originalLine - searchRange).clamp(1, lines.length);
    final endLine = (originalLine + searchRange).clamp(1, lines.length);

    double bestScore = 0.0;
    int? bestLine;

    for (int lineNum = startLine; lineNum <= endLine; lineNum++) {
      final lineIndex = lineNum - 1; // המרה לאינדקס (מתחיל מ-0)
      if (lineIndex >= lines.length) continue;

      final lineText = lines[lineIndex];
      final lineWords = extractFirstWords(lineText);
      final score = calculateMatchScore(firstWords, lineWords);

      if (score > bestScore) {
        bestScore = score;
        bestLine = lineNum;
      }
    }

    // מחזיר את המיקום הטוב ביותר רק אם הציון מעל 0.8
    if (bestScore >= 0.8) {
      return bestLine;
    }

    return null;
  }

  /// אימות כל ההערות לספר
  ///
  /// בודק את כל ההערות ומחזיר רשימת עדכונים נדרשים.
  Future<List<LocationUpdate>> verifyAllNotes({
    required List<SimpleNote> notes,
    required String bookText,
  }) async {
    final lines = bookText.split('\n');
    final updates = <LocationUpdate>[];

    for (final note in notes) {
      // בדיקה שהמיקום המקורי בטווח תקין
      if (note.lineNumber < 1 || note.lineNumber > lines.length) {
        updates.add(LocationUpdate(
          noteId: note.id,
          originalLine: note.lineNumber,
          newLine: null,
          matchScore: 0.0,
          isLocationless: true,
        ));
        continue;
      }

      // בדיקת התאמה במיקום המקורי
      final lineIndex = note.lineNumber - 1;
      final lineText = lines[lineIndex];
      final lineWords = extractFirstWords(lineText);
      final score = calculateMatchScore(note.firstWords, lineWords);

      if (score >= 0.8) {
        // המיקום תקין
        updates.add(LocationUpdate(
          noteId: note.id,
          originalLine: note.lineNumber,
          newLine: note.lineNumber,
          matchScore: score,
          isLocationless: false,
        ));
      } else {
        // חיפוש מיקום חדש
        final newLine = await findNewLocation(
          firstWords: note.firstWords,
          originalLine: note.lineNumber,
          bookText: bookText,
        );

        if (newLine != null) {
          // נמצא מיקום חדש
          final newLineIndex = newLine - 1;
          final newLineText = lines[newLineIndex];
          final newLineWords = extractFirstWords(newLineText);
          final newScore = calculateMatchScore(note.firstWords, newLineWords);

          updates.add(LocationUpdate(
            noteId: note.id,
            originalLine: note.lineNumber,
            newLine: newLine,
            matchScore: newScore,
            isLocationless: false,
          ));
        } else {
          // לא נמצא מיקום - הערה ללא מיקום
          updates.add(LocationUpdate(
            noteId: note.id,
            originalLine: note.lineNumber,
            newLine: null,
            matchScore: score,
            isLocationless: true,
          ));
        }
      }
    }

    return updates;
  }
}
