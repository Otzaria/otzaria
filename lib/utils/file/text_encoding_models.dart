/// מתחת לערך הזה הזיהוי אינו ודאי — ראוי לתת למשתמש לבחור קידוד בעצמו.
const double kLowConfidenceThreshold = 0.60;

/// הקידודים שהזיהוי מכיר.
enum TextEncoding {
  utf8('UTF-8'),
  utf16LE('UTF-16LE'),
  utf16BE('UTF-16BE'),
  utf32LE('UTF-32LE'),
  utf32BE('UTF-32BE'),
  windows1255('Windows-1255'),
  iso88598('ISO-8859-8'),
  cp862('CP862');

  const TextEncoding(this.label);

  /// שם הקידוד לתצוגה ולרישום ניפוי.
  final String label;

  /// קידוד עברי חד-בייטי מדור קודם — אלה המועמדים שנשקלים זה מול זה.
  bool get isLegacyHebrew =>
      this == windows1255 || this == iso88598 || this == cp862;

  bool get isUtf32 => this == utf32LE || this == utf32BE;
}

/// תוצאת הזיהוי — בלי הפענוח עצמו.
class TextEncodingDetection {
  const TextEncodingDetection({
    required this.encoding,
    required this.confidence,
    required this.reason,
    this.hadBom = false,
    this.bomLength = 0,
    this.validPrefixLength,
    this.candidateScores = const {},
  });

  final TextEncoding encoding;

  /// 0..1 — מידת הוודאות שזהו הקידוד ושהטקסט שיצא ממנו נכון.
  final double confidence;

  /// למה נבחר הקידוד הזה. נכנס לרישום הניפוי ולדיווחי כשל.
  final String reason;

  final bool hadBom;

  /// אורך ה-BOM שיש לדלג עליו לפני הפענוח (0 כשאין).
  final int bomLength;

  /// עד לאן הבייטים תקינים, כשזנב הקובץ קטוע. `null` = הקובץ כולו.
  final int? validPrefixLength;

  /// הניקוד של כל המועמדים שנשקלו — לניפוי, לבדיקות ולטלמטריה.
  final Map<TextEncoding, double> candidateScores;

  bool get lowConfidence => confidence < kLowConfidenceThreshold;
}

/// תוצאת פענוח מלאה: הטקסט עצמו וכל מה שהזיהוי יודע עליו.
class TextDecodingResult {
  const TextDecodingResult({
    required this.text,
    required this.encoding,
    required this.confidence,
    required this.hadBom,
    required this.detectionReason,
    this.encodingWasForced = false,
    this.candidateScores = const {},
  });

  final String text;
  final TextEncoding encoding;

  /// 0..1 — מידת הוודאות שזהו הקידוד ושהטקסט שיצא ממנו נכון.
  final double confidence;

  /// היה BOM בראש הקובץ (והוא הוסר מהטקסט).
  final bool hadBom;

  /// הקידוד נכפה על ידי הקורא ולא זוהה.
  final bool encodingWasForced;

  final String? detectionReason;

  /// הניקוד של כל המועמדים שנשקלו — לניפוי, לבדיקות ולטלמטריה.
  final Map<TextEncoding, double> candidateScores;

  /// הזיהוי לא הגיע לוודאות מעשית; ראוי להציג למשתמש אפשרות לבחור קידוד.
  bool get lowConfidence => confidence < kLowConfidenceThreshold;
}

/// מועמד לפענוח: הקידוד, הניקוד שקיבל והעדות הייחודית שנמצאה לו.
class DecodedCandidate {
  const DecodedCandidate({
    required this.encoding,
    required this.score,
    required this.plausibility,
    required this.distinctiveBytes,
    required this.highBytes,
    required this.sampleLength,
  });

  final TextEncoding encoding;

  /// 0..1 — עד כמה הטקסט שיצא נראה טקסט של ספר עברי.
  final double score;

  /// 0..1 — עד כמה התווים שיצאו הם בכלל תווי טקסט חוקיים.
  final double plausibility;

  /// מספר הבייטים שרק הקידוד הזה מסביר כטקסט סביר.
  final int distinctiveBytes;

  /// מספר הבייטים ≥ 0x80 בדגימה — הבייטים שיש בהם בכלל עדות לקידוד.
  final int highBytes;

  final int sampleLength;
}
