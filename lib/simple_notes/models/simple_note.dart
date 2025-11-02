import 'package:equatable/equatable.dart';

/// מודל פשוט להערה אישית על ספר
///
/// מייצג הערה שמקושרת לשורה מסוימת בספר באמצעות מספר שורה
/// ו-10 מילים ראשונות לאימות המיקום.
class SimpleNote extends Equatable {
  /// מזהה ייחודי להערה (פורמט: note_timestamp_random)
  final String id;

  /// שם הספר שההערה משויכת אליו
  final String bookTitle;

  /// מספר השורה בספר (מתחיל מ-1)
  final int lineNumber;

  /// 10 המילים הראשונות של השורה (לאימות מיקום)
  final List<String> firstWords;

  /// תוכן ההערה
  final String content;

  /// תאריך יצירת ההערה
  final DateTime createdAt;

  /// תאריך עדכון אחרון
  final DateTime updatedAt;

  /// האם להערה יש מיקום תקין בספר
  final bool hasLocation;

  /// מספר השורה בקובץ הטקסט של ההערות (אופציונלי)
  final int? textFileLineNumber;

  const SimpleNote({
    required this.id,
    required this.bookTitle,
    required this.lineNumber,
    required this.firstWords,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.hasLocation,
    this.textFileLineNumber,
  });

  /// יצירת עותק של ההערה עם שדות מעודכנים
  SimpleNote copyWith({
    String? id,
    String? bookTitle,
    int? lineNumber,
    List<String>? firstWords,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? hasLocation,
    int? textFileLineNumber,
  }) {
    return SimpleNote(
      id: id ?? this.id,
      bookTitle: bookTitle ?? this.bookTitle,
      lineNumber: lineNumber ?? this.lineNumber,
      firstWords: firstWords ?? this.firstWords,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      hasLocation: hasLocation ?? this.hasLocation,
      textFileLineNumber: textFileLineNumber ?? this.textFileLineNumber,
    );
  }

  /// המרה ל-JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bookTitle': bookTitle,
      'lineNumber': lineNumber,
      'firstWords': firstWords,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'hasLocation': hasLocation,
      'textFileLineNumber': textFileLineNumber,
    };
  }

  /// יצירה מ-JSON
  factory SimpleNote.fromJson(Map<String, dynamic> json) {
    return SimpleNote(
      id: json['id'] as String,
      bookTitle: json['bookTitle'] as String,
      lineNumber: json['lineNumber'] as int,
      firstWords: (json['firstWords'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
      content: json['content'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      hasLocation: json['hasLocation'] as bool,
      textFileLineNumber: json['textFileLineNumber'] as int?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        bookTitle,
        lineNumber,
        firstWords,
        content,
        createdAt,
        updatedAt,
        hasLocation,
        textFileLineNumber,
      ];

  @override
  String toString() {
    return 'SimpleNote(id: $id, bookTitle: $bookTitle, lineNumber: $lineNumber, hasLocation: $hasLocation)';
  }
}
