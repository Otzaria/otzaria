/// הפניה שזוהתה בטקסט על-ידי כלל זיהוי.
///
/// ה-rule אחראי רק לזיהוי; הוא לא פותח ספרים, לא כותב cache, ולא מייצר HTML.
class DetectedReference {
  /// מספר השורה (0-based) שבה זוהתה ההפניה.
  final int sourceLineIndex;

  /// מיקום תחילת ההפניה בשורה (0-based, inclusive), לפי הטקסט הגולמי.
  final int start;

  /// מיקום סוף ההפניה בשורה (0-based, exclusive), לפי הטקסט הגולמי.
  final int end;

  /// הטקסט שהתאים לכלל.
  final String matchedText;

  /// שם ספר היעד כפי שיש לחפש אותו בספרייה.
  final String targetBookTitle;

  /// טקסט המראה מקום שיש לפתור לאינדקס, למשל 'ב א' (דף ב עמוד א).
  final String targetRefText;

  /// מזהה הכלל שזיהה, למשל 'gemara.reference.v1'.
  final String ruleId;

  /// ציון ביטחון בין 0.0 ל-1.0.
  final double confidence;

  const DetectedReference({
    required this.sourceLineIndex,
    required this.start,
    required this.end,
    required this.matchedText,
    required this.targetBookTitle,
    required this.targetRefText,
    required this.ruleId,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
        'sourceLineIndex': sourceLineIndex,
        'start': start,
        'end': end,
        'matchedText': matchedText,
        'targetBookTitle': targetBookTitle,
        'targetRefText': targetRefText,
        'ruleId': ruleId,
        'confidence': confidence,
      };

  factory DetectedReference.fromJson(Map<String, dynamic> json) =>
      DetectedReference(
        sourceLineIndex: json['sourceLineIndex'] as int,
        start: json['start'] as int,
        end: json['end'] as int,
        matchedText: json['matchedText'] as String,
        targetBookTitle: json['targetBookTitle'] as String,
        targetRefText: json['targetRefText'] as String,
        ruleId: json['ruleId'] as String,
        confidence: (json['confidence'] as num).toDouble(),
      );
}

/// הקשר שמועבר לכל כלל בזמן הזיהוי.
class GeneratedLinkRuleContext {
  final int sourceBookId;
  final String sourceBookTitle;

  /// הפניות שכבר זוהו לפני ה-batch הנוכחי — לשימוש כלל 'שם'.
  final List<DetectedReference> previousReferences;

  const GeneratedLinkRuleContext({
    required this.sourceBookId,
    required this.sourceBookTitle,
    this.previousReferences = const [],
  });
}

/// טווח שורות לעיבוד (גבולות inclusive).
class LineRange {
  final int start;
  final int end;

  const LineRange(this.start, this.end);
}

/// ממשק בסיסי לכלל זיהוי הפניות.
abstract class GeneratedLinkRule {
  /// מזהה ייחודי של הכלל, למשל 'gemara.reference.v1'.
  String get id;

  /// גרסת הכלל; שינוי גרסה גורר פסילת cache קיים.
  int get version;

  /// מזהה הפניות ב-[lines] בטווח [lineRange].
  ///
  /// [context] מכיל מידע על ספר המקור וקישורים קודמים.
  /// [lines] הוא כל הטקסט הגולמי של הספר (לא רק הטווח),
  ///   כדי לאפשר look-behind לכללי 'שם'.
  /// [lineRange] מגדיר את הטווח שיש לעבד בקריאה זו.
  Future<List<DetectedReference>> detect(
    GeneratedLinkRuleContext context,
    List<String> lines,
    LineRange lineRange,
  );
}
