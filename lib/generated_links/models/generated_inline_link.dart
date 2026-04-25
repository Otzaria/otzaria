import 'package:otzaria/generated_links/models/generated_link_target.dart';

/// קישור inline שזוהה אוטומטית בתוך טקסט ספר ונשמר ב-cache מקומי.
///
/// אינו נשמר ב-DB הראשי ואינו מרחיב את סכמת ה-DB.
class GeneratedInlineLink {
  /// ה-ID היציב של ספר המקור.
  final int sourceBookId;

  /// מספר שורת המקור (0-based).
  final int sourceLineIndex;

  /// מיקום תחילת הקישור בשורה (0-based, inclusive), לפי הטקסט הגולמי לפני עיבוד.
  final int start;

  /// מיקום סוף הקישור בשורה (0-based, exclusive), לפי הטקסט הגולמי לפני עיבוד.
  final int end;

  /// הטקסט שזוהה כקישור.
  final String matchedText;

  /// יעד הקישור.
  final GeneratedLinkTarget target;

  /// מזהה הכלל שזיהה את הקישור, למשל 'gemara.reference.v1'.
  final String ruleId;

  /// ציון ביטחון בין 0.0 ל-1.0.
  final double confidence;

  /// זמן יצירת הקישור.
  final DateTime createdAt;

  const GeneratedInlineLink({
    required this.sourceBookId,
    required this.sourceLineIndex,
    required this.start,
    required this.end,
    required this.matchedText,
    required this.target,
    required this.ruleId,
    required this.confidence,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'sourceBookId': sourceBookId,
        'sourceLineIndex': sourceLineIndex,
        'start': start,
        'end': end,
        'matchedText': matchedText,
        'target': target.toJson(),
        'ruleId': ruleId,
        'confidence': confidence,
        'createdAt': createdAt.toIso8601String(),
      };

  factory GeneratedInlineLink.fromJson(Map<String, dynamic> json) =>
      GeneratedInlineLink(
        sourceBookId: json['sourceBookId'] as int,
        sourceLineIndex: json['sourceLineIndex'] as int,
        start: json['start'] as int,
        end: json['end'] as int,
        matchedText: json['matchedText'] as String,
        target: GeneratedLinkTarget.fromJson(
            json['target'] as Map<String, dynamic>),
        ruleId: json['ruleId'] as String,
        confidence: (json['confidence'] as num).toDouble(),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeneratedInlineLink &&
          sourceBookId == other.sourceBookId &&
          sourceLineIndex == other.sourceLineIndex &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode =>
      Object.hash(sourceBookId, sourceLineIndex, start, end);
}
