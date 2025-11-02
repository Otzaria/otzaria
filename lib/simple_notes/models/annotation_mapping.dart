import 'package:equatable/equatable.dart';

/// מיפוי בין הערה למיקום שלה בספר ובקובץ הטקסט
///
/// מכיל את כל המידע הדרוש לאיתור ההערה בספר ובקובץ ההערות.
class AnnotationMapping extends Equatable {
  /// מזהה ההערה
  final String noteId;

  /// מספר השורה בספר (מתחיל מ-1)
  final int lineNumber;

  /// 10 המילים הראשונות של השורה
  final List<String> firstWords;

  /// מספר השורה בקובץ הטקסט של ההערות (מתחיל מ-1)
  final int textFileLineNumber;

  /// האם להערה יש מיקום תקין
  final bool hasLocation;

  /// מתי המיקום אומת לאחרונה
  final DateTime lastVerified;

  const AnnotationMapping({
    required this.noteId,
    required this.lineNumber,
    required this.firstWords,
    required this.textFileLineNumber,
    required this.hasLocation,
    required this.lastVerified,
  });

  /// יצירת עותק עם שדות מעודכנים
  AnnotationMapping copyWith({
    String? noteId,
    int? lineNumber,
    List<String>? firstWords,
    int? textFileLineNumber,
    bool? hasLocation,
    DateTime? lastVerified,
  }) {
    return AnnotationMapping(
      noteId: noteId ?? this.noteId,
      lineNumber: lineNumber ?? this.lineNumber,
      firstWords: firstWords ?? this.firstWords,
      textFileLineNumber: textFileLineNumber ?? this.textFileLineNumber,
      hasLocation: hasLocation ?? this.hasLocation,
      lastVerified: lastVerified ?? this.lastVerified,
    );
  }

  /// המרה ל-JSON
  Map<String, dynamic> toJson() {
    return {
      'noteId': noteId,
      'lineNumber': lineNumber,
      'firstWords': firstWords,
      'textFileLineNumber': textFileLineNumber,
      'hasLocation': hasLocation,
      'lastVerified': lastVerified.toIso8601String(),
    };
  }

  /// יצירה מ-JSON
  factory AnnotationMapping.fromJson(Map<String, dynamic> json) {
    return AnnotationMapping(
      noteId: json['noteId'] as String,
      lineNumber: json['lineNumber'] as int,
      firstWords: (json['firstWords'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
      textFileLineNumber: json['textFileLineNumber'] as int,
      hasLocation: json['hasLocation'] as bool,
      lastVerified: DateTime.parse(json['lastVerified'] as String),
    );
  }

  @override
  List<Object?> get props => [
        noteId,
        lineNumber,
        firstWords,
        textFileLineNumber,
        hasLocation,
        lastVerified,
      ];

  @override
  String toString() {
    return 'AnnotationMapping(noteId: $noteId, lineNumber: $lineNumber, hasLocation: $hasLocation)';
  }
}
