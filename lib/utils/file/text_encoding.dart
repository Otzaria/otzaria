import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// מתחת לערך הזה הזיהוי אינו ודאי — ראוי לתת למשתמש לבחור קידוד בעצמו.
const double kLowConfidenceThreshold = 0.60;

/// חלון הזיהוי הראשון. קובץ טקסט אמיתי מוכרע בו, והוא זול מספיק כדי לא
/// להאט import של אלפי קבצים.
const int kDetectionProbeBytes = 16 * 1024;

/// תקרת הדגימה כשהחלון הראשון לא הכריע — ראש, אמצע וזנב הקובץ יחד.
const int kDetectionSampleBytes = 128 * 1024;

/// שיעור בתי-האפס ב-UTF-8 חוקי שמעליו נשקל גם UTF-16/32 בלי BOM.
const double _maxUtf8NulRatio = 0.05;

/// מספר נקודות הקוד שסבירות הטקסט של UTF-8 נמדדת עליהן. נמדד בנקודות קוד
/// ולא בבתים, כדי ששני מסלולי ה-UTF-8 (אימות בלבד ופענוח מלא) יחזירו ניקוד
/// זהה בדיוק.
const int _utf8ProbeRunes = 8192;

const String _utf8StrictReason = 'UTF-8 עבר אימות קפדני';
const String _utf8BomReason = 'BOM של UTF-8, והמצע עבר אימות קפדני';

/// ניקוד מינימלי שמועמד legacy חייב לעבור כדי להיחשב הסבר סביר לבייטים.
const double _minLegacyScore = 0.55;

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
///
/// מיוצרת על ידי [detectTextEncoding], שקורא לכל היותר
/// [kDetectionSampleBytes] בתים לצורך הניקוד ולכן זול גם על קובץ של מגה-בתים.
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

  /// מספר הבייטים ‎≥ 0x80‎ בדגימה — הבייטים שיש בהם בכלל עדות לקידוד.
  final int highBytes;

  final int sampleLength;
}

/// קריאת קובץ טקסט עם זיהוי קידוד סלחני.
///
/// ספרים אישיים מגיעים לא פעם מקבצים ישנים שנשמרו ב-ANSI עברית
/// (Windows-1255), ב-DOS עברית (CP862) או ב-UTF-16, ו-`readAsString()` הרגיל
/// זורק עליהם `FileSystemException: Failed to decode data using encoding
/// 'utf-8'`. סדר הזיהוי: BOM → UTF-8 קפדני → UTF-16 → UTF-32 → קידודי עברית
/// מדור קודם בהשוואת ניקוד.
Future<String> readTextFileSmart(File file) async =>
    (await readTextFileSmartDetailed(file)).text;

/// מפענח בייטים של טקסט לפי אותה לוגיקת זיהוי של [readTextFileSmart].
String decodeTextBytesSmart(Uint8List bytes) =>
    decodeTextBytesSmartDetailed(bytes).text;

/// כמו [readTextFileSmart], ובנוסף מחזיר את מה שהזיהוי יודע על הקובץ.
///
/// [forcedEncoding] מדלג על הזיהוי ומפענח בקידוד המבוקש — התשתית ל"פתח
/// באמצעות קידוד…" בממשק.
Future<TextDecodingResult> readTextFileSmartDetailed(
  File file, {
  TextEncoding? forcedEncoding,
}) async {
  final bytes = await file.readAsBytes();
  return decodeTextBytesSmartDetailed(bytes, forcedEncoding: forcedEncoding);
}

/// כמו [decodeTextBytesSmart], ובנוסף מחזיר את מה שהזיהוי יודע על הבייטים.
TextDecodingResult decodeTextBytesSmartDetailed(
  Uint8List bytes, {
  TextEncoding? forcedEncoding,
}) {
  if (forcedEncoding != null) {
    final bomLength = _bomLengthFor(bytes, forcedEncoding);
    return TextDecodingResult(
      text: _decodeRange(bytes, bomLength, bytes.length, forcedEncoding),
      encoding: forcedEncoding,
      confidence: 1.0,
      hadBom: bomLength > 0,
      encodingWasForced: true,
      detectionReason: 'הקידוד נכפה על ידי הקורא',
    );
  }

  final fastUtf8 = _decodeValidUtf8(bytes);
  if (fastUtf8 != null) return fastUtf8;

  final detection = detectTextEncoding(bytes);
  return TextDecodingResult(
    text: _decodeRange(
      bytes,
      detection.bomLength,
      detection.validPrefixLength ?? bytes.length,
      detection.encoding,
    ),
    encoding: detection.encoding,
    confidence: detection.confidence,
    hadBom: detection.hadBom,
    detectionReason: detection.reason,
    candidateScores: detection.candidateScores,
  );
}

/// המסלול המהיר של הרוב המוחלט של הקבצים: פענוח קפדני אחד גם מאמת וגם מפיק
/// את הטקסט, במקום מעבר אימות ומעבר פענוח בנפרד.
///
/// מחזיר `null` בכל מקרה שאינו UTF-8 חוקי חלק — ואז מתבצע הזיהוי המלא.
/// ההכרעה, ה-confidence והנימוק חייבים להיות זהים לאלה של [detectTextEncoding]
/// על אותם בייטים; `text_encoding_detection_test.dart` נועץ את השקילות.
TextDecodingResult? _decodeValidUtf8(Uint8List bytes) {
  if (bytes.isEmpty) return null;

  final boms = _matchingBoms(bytes);
  final bool hadBom;
  if (boms.isEmpty) {
    hadBom = false;
  } else if (boms.length == 1 && boms.first.encoding == TextEncoding.utf8) {
    hadBom = true;
  } else {
    return null;
  }
  final start = hadBom ? 3 : 0;

  final String text;
  try {
    text = utf8.decode(Uint8List.sublistView(bytes, start));
  } on FormatException {
    return null;
  }
  // קובץ שכולו BOM — למסלול הרגיל, שיש לו מדיניות משלו לתוכן ריק.
  if (text.isEmpty) return null;

  final probe = _Plausibility();
  var nuls = 0;
  var runes = 0;
  for (final rune in text.runes) {
    if (runes >= _utf8ProbeRunes) break;
    if (rune == 0) nuls++;
    probe.addRune(rune);
    runes++;
  }
  // בתי אפס פותחים את השאלה אם זה בכלל UTF-16/32 בלי BOM — ואז נדרש הזיהוי
  // המלא. BOM מכריע לבדו, ולכן הוא פטור מהבדיקה.
  if (!hadBom && runes > 0 && nuls / runes > _maxUtf8NulRatio) return null;

  return TextDecodingResult(
    text: text,
    encoding: TextEncoding.utf8,
    confidence: _utf8ConfidenceFor(probe.score),
    hadBom: hadBom,
    detectionReason: hadBom ? _utf8BomReason : _utf8StrictReason,
    candidateScores: {TextEncoding.utf8: probe.score},
  );
}

/// מזהה את קידוד הבייטים בלי לפענח אותם.
///
/// אימות ה-UTF-8 עובר על כל הבייטים (זנב פגום חייב להיתפס), אבל הניקוד
/// ההשוואתי מחושב על דגימה מוגבלת — ולכן אין כאן פענוח מלא ואין הקצאת
/// מחרוזת. הפונקציה טהורה ובטוחה ל-`Isolate.run`.
TextEncodingDetection detectTextEncoding(Uint8List bytes) {
  if (bytes.isEmpty) {
    return const TextEncodingDetection(
      encoding: TextEncoding.utf8,
      confidence: 1.0,
      reason: 'קובץ ריק',
    );
  }

  final boms = _matchingBoms(bytes);
  for (final bom in boms) {
    final fromBom = _detectFromBom(bytes, bom);
    if (fromBom != null) return fromBom;
  }

  // BOM שהמצע שלו לא נאמת: ממשיכים לזהות את המצע עצמו, וה-confidence נחסם.
  return _detectWithoutBom(
    bytes,
    boms.isEmpty ? 0 : boms.first.length,
    contradictedBom: boms.isEmpty ? null : boms.first.encoding,
  );
}

/// מפענח בייטים בקידוד מפורש, בלי זיהוי. BOM של אותו קידוד מוסר.
String decodeTextBytesWith(Uint8List bytes, TextEncoding encoding) =>
    _decodeRange(bytes, _bomLengthFor(bytes, encoding), bytes.length, encoding);

/// 0..1 — עד כמה [text] נראה טקסט של ספר עברי.
///
/// עולה עם אותיות עבריות, ניקוד, ASCII, רווחים ופיסוק תקין; יורד עם תווי
/// בקרה, `U+FFFD`, תווים לא מוקצים וסימנים גרפיים שאין להם מה לחפש בספר.
double scoreDecodedText(String text) {
  final acc = _Plausibility();
  for (final rune in text.runes) {
    acc.addRune(rune);
  }
  return acc.score;
}

/// מנקד את [sample] כאילו פוענח ב-[encoding] — לקידודי עברית חד-בייטיים.
///
/// חשוף לצורכי בדיקות וניפוי: כך אפשר להשוות מועמדים על אותם בייטים בלי
/// לעבור דרך הזיהוי כולו.
DecodedCandidate scoreLegacyEncoding(Uint8List sample, TextEncoding encoding) {
  assert(encoding.isLegacyHebrew, 'הניקוד ההשוואתי הוא לקידודי עברית ישנים');
  final histogram = Uint32List(256);
  for (final byte in sample) {
    histogram[byte]++;
  }
  return _scoreLegacyHistogram(histogram, encoding, sample.length);
}

/// דוח ניפוי קריא של הכרעת הזיהוי (§66).
String describeTextEncodingDetection(Uint8List bytes) {
  final detection = detectTextEncoding(bytes);
  final lines = <String>['Encoding detection'];
  for (final entry in detection.candidateScores.entries) {
    lines.add('${entry.key.label}: ${entry.value.toStringAsFixed(2)}');
  }
  lines
    ..add('Selected: ${detection.encoding.label}')
    ..add('Confidence: ${detection.confidence.toStringAsFixed(2)}')
    ..add('Reason: ${detection.reason}');
  return lines.join('\n');
}

/// ממיר בית בודד לנקודת קוד לפי דף-קוד של Windows.
///
/// משמש את ממיר ה-RTF, שבו `\'hh` מקודד בית בדף-הקוד שהמסמך הכריז עליו
/// (`\ansicpg`). דף-קוד לא מוכר נופל ל-Latin-1 — פירוש חלקי עדיף על אובדן.
int decodeCodepageByte(int byte, int codepage) {
  if (byte < 0x80) return byte;
  return switch (codepage) {
    1255 => _cp1255High[byte - 0x80],
    1252 => _cp1252High[byte - 0x80],
    862 => _cp862High[byte - 0x80],
    28598 => _iso88598High[byte - 0x80],
    _ => byte,
  };
}

// ===========================================================================
// זיהוי לפי BOM
// ===========================================================================

class _Bom {
  const _Bom(this.encoding, this.length);

  final TextEncoding encoding;
  final int length;
}

/// כל ה-BOM-ים שתואמים את ראש הקובץ, בסדר עדיפות.
///
/// UTF-32 לפני UTF-16: `FF FE 00 00` הוא גם BOM של UTF-16LE ואחריו `U+0000`,
/// ובדיקה בסדר ההפוך הייתה תופסת כל קובץ UTF-32LE כ-UTF-16.
List<_Bom> _matchingBoms(Uint8List bytes) {
  final boms = <_Bom>[];
  if (bytes.length >= 4 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xFE &&
      bytes[2] == 0x00 &&
      bytes[3] == 0x00) {
    boms.add(const _Bom(TextEncoding.utf32LE, 4));
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x00 &&
      bytes[1] == 0x00 &&
      bytes[2] == 0xFE &&
      bytes[3] == 0xFF) {
    boms.add(const _Bom(TextEncoding.utf32BE, 4));
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    boms.add(const _Bom(TextEncoding.utf8, 3));
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    boms.add(const _Bom(TextEncoding.utf16LE, 2));
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    boms.add(const _Bom(TextEncoding.utf16BE, 2));
  }
  return boms;
}

int _bomLengthFor(Uint8List bytes, TextEncoding encoding) {
  for (final bom in _matchingBoms(bytes)) {
    if (bom.encoding == encoding) return bom.length;
  }
  return 0;
}

/// ה-BOM מזהה את הקידוד, אבל המצע נאמת בפני עצמו: BOM אינו הבטחה שהתוכן
/// תקין, ו-`allowMalformed` היה מחליף שקט תוכן פגום ב-`U+FFFD`.
TextEncodingDetection? _detectFromBom(Uint8List bytes, _Bom bom) {
  final start = bom.length;
  if (start >= bytes.length) {
    return TextEncodingDetection(
      encoding: bom.encoding,
      confidence: 1.0,
      hadBom: true,
      bomLength: start,
      reason: 'הקובץ מכיל BOM של ${bom.encoding.label} בלבד',
      candidateScores: {bom.encoding: 1.0},
    );
  }

  if (bom.encoding == TextEncoding.utf8) {
    final scan = _scanUtf8(bytes, start);
    if (scan.valid) {
      return TextEncodingDetection(
        encoding: TextEncoding.utf8,
        confidence: _utf8Confidence(scan),
        hadBom: true,
        bomLength: start,
        reason: _utf8BomReason,
        candidateScores: {TextEncoding.utf8: scan.score},
      );
    }
    if (scan.truncatedTail && scan.score >= _minLegacyScore) {
      return TextEncodingDetection(
        encoding: TextEncoding.utf8,
        confidence: 0.70,
        hadBom: true,
        bomLength: start,
        validPrefixLength: scan.validPrefixLength,
        reason: 'BOM של UTF-8, אך רצף הבתים האחרון קטוע — הזנב הפגום נחתך',
        candidateScores: {TextEncoding.utf8: scan.score},
      );
    }
    return null;
  }

  final unitBytes = bom.encoding.isUtf32 ? 4 : 2;
  final payload = bytes.length - start;
  final aligned = start + (payload ~/ unitBytes) * unitBytes;
  if (aligned == start) return null;

  final candidate = bom.encoding.isUtf32
      ? _scoreUtf32(
          bytes,
          _probeWindows(bytes, start),
          littleEndian: bom.encoding == TextEncoding.utf32LE,
        )
      : _scoreUtf16(
          bytes,
          _probeWindows(bytes, start),
          littleEndian: bom.encoding == TextEncoding.utf16LE,
        );
  if (candidate.units >= 2 && candidate.plausibility < 0.60) return null;

  // אימות המצע כולו, לא רק הדגימה: יחידה פסולה מרובה פירושה ש-BOM שיקר,
  // ויחידה בודדת פירושה קובץ פגום — ואז הקידוד נשמר וה-confidence מדווח.
  final invalid = _countInvalidUnits(bytes, start, bom.encoding);
  final units = payload ~/ unitBytes;
  if (invalid > units * _maxInvalidUnitRatio) return null;
  final truncated = aligned != bytes.length;

  final problem = switch ((truncated, invalid > 0)) {
    (true, true) => 'זנב קטוע ו-$invalid יחידות פסולות',
    (true, false) =>
      unitBytes == 4 ? 'יחידת ארבעת הבתים האחרונה קטועה' : 'אורך אי-זוגי',
    (false, true) => '$invalid יחידות פסולות הוחלפו',
    _ => null,
  };
  return TextEncodingDetection(
    encoding: bom.encoding,
    confidence: problem == null ? _bomPayloadConfidence(candidate) : 0.75,
    hadBom: true,
    bomLength: start,
    validPrefixLength: truncated ? aligned : null,
    reason: problem == null
        ? 'BOM של ${bom.encoding.label}, והמצע נאמת'
        : 'BOM של ${bom.encoding.label}, אך המצע פגום ($problem)',
    candidateScores: {bom.encoding: candidate.score},
  );
}

/// BOM שמצעו נאמת הוא ודאי; תווים לא חוקיים בתוכו מורידים את הוודאות גם אם
/// ה-BOM עצמו תקין.
double _bomPayloadConfidence(_UnicodeCandidate candidate) =>
    candidate.plausibility >= 0.98 ? 1.0 : 0.85;

/// שיעור היחידות הפסולות שמעליו הקידוד עצמו נפסל, ולא רק ה-confidence יורד.
const double _maxInvalidUnitRatio = 0.10;

/// מספר היחידות הפסולות בכל המצע: surrogate בודד ב-UTF-16, או נקודת קוד
/// מחוץ לטווח ב-UTF-32.
///
/// האימות חייב לכסות את הקובץ כולו ולא רק את הדגימה: יחידה פסולה מחוץ לחלון
/// הייתה מוחלפת ב-`U+FFFD` בוודאות מלאה — בדיוק מה ש-§37 אוסר.
int _countInvalidUtf16Units(Uint8List bytes, int start, bool littleEndian) {
  final end = bytes.length;
  var invalid = 0;
  var i = start;
  while (i + 1 < end) {
    final unit = littleEndian
        ? bytes[i] | (bytes[i + 1] << 8)
        : (bytes[i] << 8) | bytes[i + 1];
    i += 2;
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (i + 1 < end) {
        final low = littleEndian
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1];
        if (low >= 0xDC00 && low <= 0xDFFF) {
          i += 2;
          continue;
        }
      }
      invalid++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      invalid++;
    }
  }
  return invalid;
}

int _countInvalidUtf32Units(Uint8List bytes, int start, bool littleEndian) {
  var invalid = 0;
  for (var i = start; i + 3 < bytes.length; i += 4) {
    final codePoint = littleEndian
        ? bytes[i] |
              (bytes[i + 1] << 8) |
              (bytes[i + 2] << 16) |
              (bytes[i + 3] << 24)
        : (bytes[i] << 24) |
              (bytes[i + 1] << 16) |
              (bytes[i + 2] << 8) |
              bytes[i + 3];
    if (codePoint > 0x10FFFF || (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
      invalid++;
    }
  }
  return invalid;
}

int _countInvalidUnits(Uint8List bytes, int start, TextEncoding encoding) =>
    encoding.isUtf32
    ? _countInvalidUtf32Units(bytes, start, encoding == TextEncoding.utf32LE)
    : _countInvalidUtf16Units(bytes, start, encoding == TextEncoding.utf16LE);

// ===========================================================================
// זיהוי בלי BOM
// ===========================================================================

TextEncodingDetection _detectWithoutBom(
  Uint8List bytes,
  int offset, {
  TextEncoding? contradictedBom,
}) {
  final scores = <TextEncoding, double>{};
  final scan = _scanUtf8(bytes, offset);
  scores[TextEncoding.utf8] = scan.valid ? scan.score : 0.0;

  // UTF-8 קפדני לפני כל היוריסטיקה: קובץ UTF-8 תקין לא ייחטף בידי ניחוש.
  if (scan.valid && scan.nulRatio <= _maxUtf8NulRatio) {
    return _capped(
      TextEncodingDetection(
        encoding: TextEncoding.utf8,
        confidence: _utf8Confidence(scan),
        reason: _utf8StrictReason,
        candidateScores: scores,
      ),
      contradictedBom,
      offset,
    );
  }

  var detection = _detectInWindows(
    bytes,
    offset,
    _probeWindows(bytes, offset),
    scan,
    scores,
  );
  // דגימת הראש לא הכריעה — מרחיבים לראש, אמצע וזנב הקובץ.
  if (detection.confidence < 0.85 &&
      bytes.length - offset > kDetectionProbeBytes) {
    detection = _detectInWindows(
      bytes,
      offset,
      _wideWindows(bytes, offset),
      scan,
      scores,
    );
  }
  return _capped(detection, contradictedBom, offset);
}

TextEncodingDetection _detectInWindows(
  Uint8List bytes,
  int offset,
  List<_Window> windows,
  _Utf8Scan scan,
  Map<TextEncoding, double> scores,
) =>
    _detectUnicodeWithoutBom(bytes, offset, windows, scores) ??
    _detectUtf8Remainder(scan, scores) ??
    _detectLegacy(bytes, offset, windows, scores);

/// חוסם את ה-confidence כשה-BOM הבטיח קידוד אחר מזה שנבחר (§12).
TextEncodingDetection _capped(
  TextEncodingDetection detection,
  TextEncoding? contradictedBom,
  int bomLength,
) {
  if (contradictedBom == null) return detection;
  return TextEncodingDetection(
    encoding: detection.encoding,
    confidence: detection.confidence > 0.55 ? 0.55 : detection.confidence,
    hadBom: true,
    bomLength: bomLength,
    validPrefixLength: detection.validPrefixLength,
    reason:
        'BOM של ${contradictedBom.label} אך המצע אינו כזה — '
        '${detection.reason}',
    candidateScores: detection.candidateScores,
  );
}

/// UTF-8 חוקי שהתוכן שלו אינו נראה טקסט, או UTF-8 שרק זנבו קטוע.
///
/// מגיע רק אחרי שהיוריסטיקות של UTF-16/32 נכשלו: קובץ UTF-8 עם הרבה בתי-אפס
/// עדיין עשוי להיות UTF-16 בלי BOM.
TextEncodingDetection? _detectUtf8Remainder(
  _Utf8Scan scan,
  Map<TextEncoding, double> scores,
) {
  if (scan.valid) {
    return TextEncodingDetection(
      encoding: TextEncoding.utf8,
      confidence: _utf8Confidence(scan),
      reason: 'UTF-8 עבר אימות קפדני, אך התוכן אינו נראה טקסט',
      candidateScores: scores,
    );
  }
  if (scan.truncatedTail && scan.score >= _minLegacyScore) {
    return TextEncodingDetection(
      encoding: TextEncoding.utf8,
      confidence: 0.70,
      validPrefixLength: scan.validPrefixLength,
      reason: 'UTF-8 חוקי עד לרצף הבתים האחרון שקטוע — הזנב הפגום נחתך',
      candidateScores: scores,
    );
  }
  return null;
}

double _utf8Confidence(_Utf8Scan scan) => _utf8ConfidenceFor(scan.score);

/// UTF-8 שנאמת קפדנית הוא ודאי; ה-confidence יורד רק כשהתוכן עצמו אינו נראה
/// טקסט — קובץ בינארי לא יקבל ודאות גבוהה (§36).
double _utf8ConfidenceFor(double score) =>
    (0.30 + 0.80 * score).clamp(0.0, 1.0);

// ===========================================================================
// אימות UTF-8
// ===========================================================================

class _Utf8Scan {
  const _Utf8Scan({
    required this.valid,
    required this.truncatedTail,
    required this.validPrefixLength,
    required this.score,
    required this.nulRatio,
  });

  final bool valid;

  /// הכשל היחיד הוא רצף רב-בתי שנקטע בסוף הקובץ.
  final bool truncatedTail;

  final int validPrefixLength;

  /// 0..1 — סבירות הטקסט של החלק שנקרא.
  final double score;

  final double nulRatio;
}

/// אימות UTF-8 קפדני בלי הקצאת מחרוזת, זהה בהחמרתו ל-`utf8.decode`.
///
/// דוחה רצפים מקוצרים-יתר (overlong), surrogates ונקודות קוד מעל `U+10FFFF`,
/// ובדרך אוסף את סבירות הטקסט ואת שיעור בתי-האפס.
_Utf8Scan _scanUtf8(Uint8List bytes, int start) {
  final length = bytes.length;
  final acc = _Plausibility();
  var nuls = 0;
  var chars = 0;
  var i = start;

  while (i < length) {
    final lead = bytes[i];
    if (lead < 0x80) {
      if (chars < _utf8ProbeRunes) {
        if (lead == 0) nuls++;
        acc.addRune(lead);
      }
      i++;
      chars++;
      continue;
    }

    final int need;
    int codePoint;
    if (lead >= 0xC2 && lead <= 0xDF) {
      need = 1;
      codePoint = lead & 0x1F;
    } else if (lead >= 0xE0 && lead <= 0xEF) {
      need = 2;
      codePoint = lead & 0x0F;
    } else if (lead >= 0xF0 && lead <= 0xF4) {
      need = 3;
      codePoint = lead & 0x07;
    } else {
      return _failedUtf8(i, acc, nuls, chars, truncated: false);
    }

    if (i + need >= length) {
      // "קטוע" רק אם הבתים שכן קיימים הם המשך תקין; אחרת זה רצף פגום, ואסור
      // לחתוך אותו כאילו נגמר הקובץ — כך נעלמו תווים תקינים שאחריו.
      for (var k = 1; i + k < length; k++) {
        if ((bytes[i + k] & 0xC0) != 0x80) {
          return _failedUtf8(i, acc, nuls, chars, truncated: false);
        }
      }
      return _failedUtf8(i, acc, nuls, chars, truncated: true);
    }
    for (var k = 1; k <= need; k++) {
      final continuation = bytes[i + k];
      if ((continuation & 0xC0) != 0x80) {
        return _failedUtf8(i, acc, nuls, chars, truncated: false);
      }
      codePoint = (codePoint << 6) | (continuation & 0x3F);
    }
    final overlongOrSurrogate =
        (need == 2 &&
            (codePoint < 0x800 ||
                (codePoint >= 0xD800 && codePoint <= 0xDFFF))) ||
        (need == 3 && (codePoint < 0x10000 || codePoint > 0x10FFFF));
    if (overlongOrSurrogate) {
      return _failedUtf8(i, acc, nuls, chars, truncated: false);
    }

    // `utf8.decode` מפשיט U+FEFF פותח, ולכן גם הניקוד כאן מדלג עליו — אחרת
    // שני מסלולי ה-UTF-8 היו מנקדים רצף תווים אחר על אותו קובץ.
    if (chars == 0 && codePoint == 0xFEFF) {
      i += need + 1;
      continue;
    }
    if (chars < _utf8ProbeRunes) acc.addRune(codePoint);
    i += need + 1;
    chars++;
  }

  return _Utf8Scan(
    valid: true,
    truncatedTail: false,
    validPrefixLength: length,
    score: acc.score,
    nulRatio: _probeNulRatio(nuls, chars),
  );
}

/// שיעור בתי-האפס בחלון הזיהוי בלבד — אותו חלון שבו נמדד גם הניקוד.
double _probeNulRatio(int nuls, int chars) {
  final probed = chars < _utf8ProbeRunes ? chars : _utf8ProbeRunes;
  return probed == 0 ? 0 : nuls / probed;
}

_Utf8Scan _failedUtf8(
  int failureOffset,
  _Plausibility acc,
  int nuls,
  int chars, {
  required bool truncated,
}) => _Utf8Scan(
  valid: false,
  truncatedTail: truncated,
  validPrefixLength: failureOffset,
  score: acc.score,
  nulRatio: _probeNulRatio(nuls, chars),
);

// ===========================================================================
// היוריסטיקות UTF-16 / UTF-32
// ===========================================================================

class _UnicodeCandidate {
  const _UnicodeCandidate({
    required this.encoding,
    required this.score,
    required this.plausibility,
    required this.units,
    required this.loneSurrogates,
    required this.invalidScalars,
    required this.trustedUnits,
  });

  final TextEncoding encoding;
  final double score;
  final double plausibility;
  final int units;
  final int loneSurrogates;
  final int invalidScalars;

  /// יחידות בטווחים שהיוריסטיקת ה-UTF-16 הקודמת סמכה עליהם — רחבים מ"עברית
  /// או ASCII", ולכן שומרים על קובץ ביוונית או בקירילית שפוענח נכון לפני כן.
  final int trustedUnits;
}

bool _isPreviouslyTrustedUnit(int unit) =>
    unit == 0x09 ||
    unit == 0x0A ||
    unit == 0x0D ||
    (unit >= 0x20 && unit <= 0x7E) ||
    (unit >= 0x00A0 && unit <= 0x05FF) ||
    (unit >= 0x2000 && unit <= 0x206F);

/// UTF-16 לפני UTF-32, ושתיהן רק אחרי ש-UTF-8 הקפדני נכשל.
///
/// השערים דורשים גם תווים חוקיים (`plausibility`) וגם טקסט שנראה עברי/לטיני
/// (`score`): רק בתי-אפס אינם עדות, וטקסט ASCII שנקרא כזוגות בתים מייצר
/// תווי CJK "חוקיים" שהיו נראים אמינים לכל בדיקה מבנית.
TextEncodingDetection? _detectUnicodeWithoutBom(
  Uint8List bytes,
  int offset,
  List<_Window> windows,
  Map<TextEncoding, double> scores,
) {
  final candidates = <_UnicodeCandidate>[
    _scoreUtf16(bytes, windows, littleEndian: true),
    _scoreUtf16(bytes, windows, littleEndian: false),
    _scoreUtf32(bytes, windows, littleEndian: true),
    _scoreUtf32(bytes, windows, littleEndian: false),
  ];
  for (final candidate in candidates) {
    scores[candidate.encoding] = candidate.score;
  }

  final passing = candidates.where(_passesUnicodeGate).toList();
  if (passing.isEmpty) return null;

  var best = passing.first;
  for (final candidate in passing.skip(1)) {
    if (candidate.score > best.score) best = candidate;
  }

  // הקטיעה והיחידות הפסולות נמדדות על המצע כולו ולא על החלון שנדגם: בקובץ
  // גדול הפגם יושב מחוץ לדגימה, והיה נשמט בשקט בלי לרדת ב-confidence.
  final unitBytes = best.encoding.isUtf32 ? 4 : 2;
  final payload = bytes.length - offset;
  final truncated = payload % unitBytes != 0;
  final units = payload ~/ unitBytes;
  final invalid = _countInvalidUnits(bytes, offset, best.encoding);
  if (invalid > units * _maxInvalidUnitRatio) return null;

  final ambiguous = passing.any(
    (other) => other != best && (best.score - other.score).abs() < 0.05,
  );
  var confidence = best.encoding.isUtf32
      ? 0.80 + 0.15 * _quality(best.score, 0.70, 0.30)
      : 0.80 + 0.18 * _quality(best.score, 0.70, 0.30);
  final cap = _unitEvidenceCap(best.units);
  if (confidence > cap) confidence = cap;
  if (truncated && confidence > 0.70) confidence = 0.70;
  if (invalid > 0 && confidence > 0.70) confidence = 0.70;
  if (ambiguous && confidence > 0.70) confidence = 0.70;

  final flaws = [
    if (truncated) 'זנב קטוע',
    if (invalid > 0) '$invalid יחידות פסולות',
  ];
  return TextEncodingDetection(
    encoding: best.encoding,
    confidence: confidence,
    validPrefixLength: truncated
        ? offset + (payload ~/ unitBytes) * unitBytes
        : null,
    reason:
        'היוריסטיקת ${best.encoding.label}: ניקוד '
        '${best.score.toStringAsFixed(2)} על ${best.units} יחידות'
        '${flaws.isEmpty ? '' : ' (${flaws.join(', ')})'}',
    candidateScores: scores,
  );
}

bool _passesUnicodeGate(_UnicodeCandidate candidate) {
  // רף הניקוד גבוה מסתם "תווים חוקיים": טקסט ASCII שנקרא כזוגות בתים מייצר
  // תווי CJK מוקצים לגמרי, שמנקדים כ-0.5 — ורק רף גבוה מהם דוחה אותם. הנתיב
  // השני, של הטווחים שהמימוש הקודם סמך עליהם, מציל כתבים כמו יוונית וקירילית
  // שמנקדים נמוך אך פוענחו נכון לפני ההרחבה.
  final trustedRatio = candidate.units == 0
      ? 0.0
      : candidate.trustedUnits / candidate.units;
  final looksLikeText = candidate.score >= 0.62 || trustedRatio >= 0.90;

  if (candidate.encoding.isUtf32) {
    // UTF-32 נדיר, ו-false positive עליו הרסני יותר — לכן שער גבוה יותר.
    return candidate.units >= 8 &&
        candidate.invalidScalars == 0 &&
        candidate.plausibility >= 0.98 &&
        (candidate.score >= 0.70 || trustedRatio >= 0.90);
  }
  return candidate.units >= 2 &&
      candidate.loneSurrogates == 0 &&
      candidate.plausibility >= 0.98 &&
      looksLikeText;
}

/// פחות יחידות = פחות עדות. קובץ של שתי מילים לא יקבל ודאות של ספר שלם.
double _unitEvidenceCap(int units) {
  if (units >= 64) return 1.0;
  if (units >= 32) return 0.85;
  if (units >= 8) return 0.75;
  return 0.55;
}

_UnicodeCandidate _scoreUtf16(
  Uint8List bytes,
  List<_Window> windows, {
  required bool littleEndian,
}) {
  final acc = _Plausibility();
  var units = 0;
  var lone = 0;
  var trusted = 0;

  for (final window in windows) {
    var i = window.start;
    while (i + 1 < window.end) {
      final unit = littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1];
      i += 2;
      units++;
      if (_isPreviouslyTrustedUnit(unit)) trusted++;
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        if (i + 1 < window.end) {
          final low = littleEndian
              ? bytes[i] | (bytes[i + 1] << 8)
              : (bytes[i] << 8) | bytes[i + 1];
          if (low >= 0xDC00 && low <= 0xDFFF) {
            i += 2;
            units++;
            acc.addRune(0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00));
            continue;
          }
        }
        lone++;
        acc.addRune(unit);
        continue;
      }
      if (unit >= 0xDC00 && unit <= 0xDFFF) {
        lone++;
        acc.addRune(unit);
        continue;
      }
      acc.addRune(unit);
    }
  }

  return _UnicodeCandidate(
    encoding: littleEndian ? TextEncoding.utf16LE : TextEncoding.utf16BE,
    score: acc.score,
    plausibility: acc.plausibility,
    units: units,
    loneSurrogates: lone,
    invalidScalars: lone,
    trustedUnits: trusted,
  );
}

_UnicodeCandidate _scoreUtf32(
  Uint8List bytes,
  List<_Window> windows, {
  required bool littleEndian,
}) {
  final acc = _Plausibility();
  var units = 0;
  var invalid = 0;
  var trusted = 0;

  for (final window in windows) {
    var i = window.start;
    while (i + 3 < window.end) {
      final codePoint = littleEndian
          ? bytes[i] |
                (bytes[i + 1] << 8) |
                (bytes[i + 2] << 16) |
                (bytes[i + 3] << 24)
          : (bytes[i] << 24) |
                (bytes[i + 1] << 16) |
                (bytes[i + 2] << 8) |
                bytes[i + 3];
      i += 4;
      units++;
      if (codePoint > 0x10FFFF ||
          (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
        invalid++;
      } else if (_isPreviouslyTrustedUnit(codePoint)) {
        trusted++;
      }
      acc.addRune(codePoint);
    }
  }

  return _UnicodeCandidate(
    encoding: littleEndian ? TextEncoding.utf32LE : TextEncoding.utf32BE,
    score: acc.score,
    plausibility: acc.plausibility,
    units: units,
    loneSurrogates: 0,
    invalidScalars: invalid,
    trustedUnits: trusted,
  );
}

// ===========================================================================
// קידודי עברית מדור קודם — ניקוד השוואתי
// ===========================================================================

/// הסדר הוא גם סדר העדיפות בתיקו: הבתים `0x80`–`0x9F` הם פיסוק טיפוגרפי
/// ב-Windows-1255 ואותיות עבריות ב-CP862, ולכן טקסט שכולו פיסוק כזה מנקד זהה
/// בשניהם — והעדפת Windows-1255 היא מה שמונע ממנו לצאת ג'יבריש.
const List<TextEncoding> _legacyEncodings = [
  TextEncoding.windows1255,
  TextEncoding.iso88598,
  TextEncoding.cp862,
];

/// בוחר בין Windows-1255, ISO-8859-8 ו-CP862 בהשוואת ניקוד.
///
/// לא נפילה עיוורת ל-Windows-1255: שלושת המועמדים מנוקדים על אותם בייטים,
/// והמנצח נבחר לפי סבירות הטקסט שיצא ולפי הפער מהמועמד הבא.
TextEncodingDetection _detectLegacy(
  Uint8List bytes,
  int offset,
  List<_Window> windows,
  Map<TextEncoding, double> scores,
) {
  final histogram = _histogramOf(bytes, windows);
  final sampleLength = windows.fold<int>(0, (sum, w) => sum + w.length);
  final candidates = [
    for (final encoding in _legacyEncodings)
      _scoreLegacyHistogram(histogram, encoding, sampleLength),
  ];
  for (final candidate in candidates) {
    scores[candidate.encoding] = candidate.score;
  }

  var winner = candidates.first;
  for (final candidate in candidates.skip(1)) {
    if (candidate.score > winner.score) winner = candidate;
  }
  var runnerUp = candidates.firstWhere((c) => c != winner);
  for (final candidate in candidates) {
    if (candidate != winner && candidate.score > runnerUp.score) {
      runnerUp = candidate;
    }
  }

  if (winner.score < _minLegacyScore) {
    return TextEncodingDetection(
      encoding: TextEncoding.windows1255,
      confidence: (0.20 + 0.50 * winner.score).clamp(0.0, 0.55),
      reason:
          'אין מועמד legacy סביר (הטוב שבהם ${winner.encoding.label} '
          '${winner.score.toStringAsFixed(2)}) — נבחר Windows-1255 כברירת מחדל',
      candidateScores: scores,
    );
  }

  final cap = _highByteEvidenceCap(winner.highBytes);
  final quality = _quality(winner.score, _minLegacyScore, 0.40);

  // אותם בייטים, אותו טקסט: הקידוד אינו ניתן להכרעה, אבל הטקסט ודאי. כל
  // מועמד יפיק את אותו פלט, ולכן נבחר Windows-1255 — ברירת המחדל המוצהרת.
  if (_mapsAgreeOnSample(histogram, winner.encoding, runnerUp.encoding)) {
    final confidence = 0.60 + 0.30 * quality;
    return TextEncodingDetection(
      encoding: TextEncoding.windows1255,
      confidence: confidence > cap ? cap : confidence,
      reason:
          'הטקסט זהה ב-${winner.encoding.label} וב-${runnerUp.encoding.label} '
          '— נבחר Windows-1255 כברירת מחדל',
      candidateScores: scores,
    );
  }

  final margin = winner.score - runnerUp.score;
  var marginFactor = (margin / 0.15).clamp(0.0, 1.0);
  if (winner.distinctiveBytes >= 4) {
    marginFactor = (marginFactor + 0.25).clamp(0.0, 1.0);
  }
  final confidence = 0.50 + 0.40 * quality * (0.5 + 0.5 * marginFactor);
  final distinctive = winner.distinctiveBytes > 0
      ? ' (עדות ייחודית: ${winner.distinctiveBytes} בתים)'
      : '';
  return TextEncodingDetection(
    encoding: winner.encoding,
    confidence: confidence > cap ? cap : confidence,
    reason:
        'ניקוד ${winner.encoding.label} עקף את ${runnerUp.encoding.label} '
        'ב-${margin.toStringAsFixed(2)}$distinctive',
    candidateScores: scores,
  );
}

/// העדות שמבדילה בין קידודי העברית היא בתים ‎≥ 0x80‎ בלבד: ASCII מתפרש זהה
/// בשלושתם. דגימה של מגה-בית ASCII אינה עדות, וכשהיא כל מה שיש — ה-confidence
/// נשאר נמוך, מה שגם מרחיב את הדגימה לאמצע הקובץ ולזנבו.
double _highByteEvidenceCap(int highBytes) {
  if (highBytes >= 64) return 0.90;
  if (highBytes >= 16) return 0.75;
  if (highBytes >= 4) return 0.65;
  return 0.55;
}

DecodedCandidate _scoreLegacyHistogram(
  Uint32List histogram,
  TextEncoding encoding,
  int sampleLength,
) {
  final acc = _Plausibility();
  var distinctive = 0;
  var highBytes = 0;
  for (var byte = 0; byte < 256; byte++) {
    final count = histogram[byte];
    if (count == 0) continue;
    acc.addRunes(_mapLegacyByte(byte, encoding), count);
    if (_isDistinctiveByte(byte, encoding)) distinctive += count;
    if (byte >= 0x80) highBytes += count;
  }
  return DecodedCandidate(
    encoding: encoding,
    score: acc.score,
    plausibility: acc.plausibility,
    distinctiveBytes: distinctive,
    highBytes: highBytes,
    sampleLength: sampleLength,
  );
}

/// בית שרק [encoding] מסביר כטקסט סביר — זו העדות שמפרידה בין Windows-1255,
/// ISO-8859-8 ו-CP862, שכולם מפרשים את `0xE0`–`0xFA` כאותן אותיות עבריות.
bool _isDistinctiveByte(int byte, TextEncoding encoding) {
  if (!_isPlausibleClass(_classifyRune(_mapLegacyByte(byte, encoding)))) {
    return false;
  }
  for (final other in _legacyEncodings) {
    if (other == encoding) continue;
    if (_isPlausibleClass(_classifyRune(_mapLegacyByte(byte, other)))) {
      return false;
    }
  }
  return true;
}

bool _isPlausibleClass(_RuneClass runeClass) =>
    runeClass == _RuneClass.hebrewOrAscii || runeClass == _RuneClass.formatMark;

/// האם שני הקידודים מפענחים את הבייטים שבדגימה לאותו טקסט בדיוק.
bool _mapsAgreeOnSample(Uint32List histogram, TextEncoding a, TextEncoding b) {
  for (var byte = 0; byte < 256; byte++) {
    if (histogram[byte] == 0) continue;
    if (_mapLegacyByte(byte, a) != _mapLegacyByte(byte, b)) return false;
  }
  return true;
}

Uint32List _histogramOf(Uint8List bytes, List<_Window> windows) {
  final histogram = Uint32List(256);
  for (final window in windows) {
    for (var i = window.start; i < window.end; i++) {
      histogram[bytes[i]]++;
    }
  }
  return histogram;
}

int _mapLegacyByte(int byte, TextEncoding encoding) {
  if (byte < 0x80) return byte;
  return switch (encoding) {
    TextEncoding.windows1255 => _cp1255High[byte - 0x80],
    TextEncoding.iso88598 => _iso88598High[byte - 0x80],
    TextEncoding.cp862 => _cp862High[byte - 0x80],
    _ => byte,
  };
}

// ===========================================================================
// דגימה
// ===========================================================================

class _Window {
  const _Window(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;
}

/// חלון הזיהוי הראשון — ראש הקובץ.
List<_Window> _probeWindows(Uint8List bytes, int offset) => [
  _Window(offset, _min(bytes.length, offset + kDetectionProbeBytes)),
];

/// ראש, אמצע וזנב, בלי חפיפה ביניהם. תחילת כל חלון מיושרת ל-4 בתים מתחילת
/// המצע, כדי שחיתוך הדגימה לא ישבור זוג UTF-16 או יחידת UTF-32 ויפיל את
/// הזיהוי לשווא. חפיפה הייתה סופרת אותה עדות פעמיים ומעלה את ה-confidence
/// לפי מיקום הבתים בקובץ.
List<_Window> _wideWindows(Uint8List bytes, int offset) {
  final total = bytes.length - offset;
  if (total <= kDetectionSampleBytes) {
    return [_Window(offset, bytes.length)];
  }
  final headEnd = offset + kDetectionSampleBytes ~/ 2;
  final chunk = kDetectionSampleBytes ~/ 4;
  int align(int position) => offset + ((position - offset) & ~3);
  final tailStart = align(bytes.length - chunk);
  final middleStart = align(headEnd + (tailStart - headEnd - chunk) ~/ 2);
  return [
    _Window(offset, headEnd),
    _Window(middleStart, middleStart + chunk),
    _Window(tailStart, bytes.length),
  ];
}

int _min(int a, int b) => a < b ? a : b;

double _quality(double score, double floor, double span) =>
    ((score - floor) / span).clamp(0.0, 1.0);

// ===========================================================================
// סיווג תווים
// ===========================================================================

enum _RuneClass {
  /// עברית, ניקוד, ASCII, רווחים ופיסוק תקין.
  hebrewOrAscii,

  /// תווי כיווניות ורווחים דקים — סבירים, אך אינם עדות לטקסט.
  formatMark,

  /// תו מוקצה שאינו עברית/ASCII: לטינית מוטעמת, יוונית, CJK, מסגרות DOS.
  /// סביר בטקסט, אך אינו עדות שזה הקידוד הנכון — ולכן משקל חלקי.
  otherAssigned,

  control,

  replacement,

  /// surrogate בודד, noncharacter, שימוש פרטי, מעל `U+10FFFF`.
  invalidScalar,
}

_RuneClass _classifyRune(int rune) {
  if (rune == 0x09 || rune == 0x0A || rune == 0x0D) {
    return _RuneClass.hebrewOrAscii;
  }
  if (rune < 0x20 || rune == 0x7F) return _RuneClass.control;
  if (rune <= 0x7E) return _RuneClass.hebrewOrAscii;
  if (rune <= 0x9F) return _RuneClass.control;
  if (rune == 0x00A0 || rune == 0x00AD) return _RuneClass.formatMark;
  if (rune <= 0x00FF) return _RuneClass.otherAssigned;
  if (rune >= 0x0591 && rune <= 0x05F4) return _RuneClass.hebrewOrAscii;
  if (rune >= 0x0590 && rune <= 0x05FF) return _RuneClass.otherAssigned;
  if (rune >= 0x200B && rune <= 0x200F) return _RuneClass.formatMark;
  if (rune >= 0x2010 && rune <= 0x2027) return _RuneClass.hebrewOrAscii;
  if (rune >= 0x202A && rune <= 0x202E) return _RuneClass.formatMark;
  if (rune == 0x20AA) return _RuneClass.hebrewOrAscii;
  if (rune >= 0xD800 && rune <= 0xDFFF) return _RuneClass.invalidScalar;
  if (rune >= 0xE000 && rune <= 0xF8FF) return _RuneClass.invalidScalar;
  if (rune >= 0xFDD0 && rune <= 0xFDEF) return _RuneClass.invalidScalar;
  if (rune == 0xFEFF) return _RuneClass.formatMark;
  if (rune == 0xFFFD) return _RuneClass.replacement;
  if (rune == 0xFFFE || rune == 0xFFFF) return _RuneClass.invalidScalar;
  if (rune > 0x10FFFF) return _RuneClass.invalidScalar;
  return _RuneClass.otherAssigned;
}

/// אוסף סבירות טקסט. שני מדדים: `score` — עד כמה זה טקסט של ספר עברי,
/// `plausibility` — עד כמה אלה בכלל תווי טקסט חוקיים.
class _Plausibility {
  double _weight = 0;
  int _total = 0;
  int _control = 0;
  int _replacement = 0;
  int _invalid = 0;

  void addRune(int rune) => addRunes(rune, 1);

  void addRunes(int rune, int count) {
    final runeClass = _classifyRune(rune);
    _total += count;
    _weight +=
        count *
        switch (runeClass) {
          _RuneClass.hebrewOrAscii => 1.0,
          _RuneClass.formatMark => 0.6,
          _RuneClass.otherAssigned => 0.5,
          _ => 0.0,
        };
    switch (runeClass) {
      case _RuneClass.control:
        _control += count;
      case _RuneClass.replacement:
        _replacement += count;
      case _RuneClass.invalidScalar:
        _invalid += count;
      default:
        break;
    }
  }

  double get score => _total == 0
      ? 0
      : (_weight / _total -
                3.0 * (_control + _invalid) / _total -
                4.0 * _replacement / _total)
            .clamp(0.0, 1.0);

  double get plausibility =>
      _total == 0 ? 0 : (_total - _control - _replacement - _invalid) / _total;
}

// ===========================================================================
// פענוח
// ===========================================================================

/// מפענח את [bytes] בטווח `[start, end)` לפי [encoding].
String _decodeRange(
  Uint8List bytes,
  int start,
  int end,
  TextEncoding encoding,
) {
  if (start >= end) return '';
  return switch (encoding) {
    TextEncoding.utf8 => utf8.decode(
      Uint8List.sublistView(bytes, start, end),
      allowMalformed: true,
    ),
    TextEncoding.utf16LE => _decodeUtf16(bytes, start, end, littleEndian: true),
    TextEncoding.utf16BE => _decodeUtf16(
      bytes,
      start,
      end,
      littleEndian: false,
    ),
    TextEncoding.utf32LE => _decodeUtf32(bytes, start, end, littleEndian: true),
    TextEncoding.utf32BE => _decodeUtf32(
      bytes,
      start,
      end,
      littleEndian: false,
    ),
    TextEncoding.windows1255 ||
    TextEncoding.iso88598 ||
    TextEncoding.cp862 => _decodeLegacy(bytes, start, end, encoding),
  };
}

String _decodeUtf16(
  Uint8List bytes,
  int start,
  int end, {
  required bool littleEndian,
}) {
  final codeUnits = <int>[];
  for (var i = start; i + 1 < end; i += 2) {
    codeUnits.add(
      littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1],
    );
  }
  return String.fromCharCodes(codeUnits);
}

String _decodeUtf32(
  Uint8List bytes,
  int start,
  int end, {
  required bool littleEndian,
}) {
  final codePoints = <int>[];
  for (var i = start; i + 3 < end; i += 4) {
    final codePoint = littleEndian
        ? bytes[i] |
              (bytes[i + 1] << 8) |
              (bytes[i + 2] << 16) |
              (bytes[i + 3] << 24)
        : (bytes[i] << 24) |
              (bytes[i + 1] << 16) |
              (bytes[i + 2] << 8) |
              bytes[i + 3];
    final valid =
        codePoint <= 0x10FFFF && !(codePoint >= 0xD800 && codePoint <= 0xDFFF);
    codePoints.add(valid ? codePoint : 0xFFFD);
  }
  return String.fromCharCodes(codePoints);
}

String _decodeLegacy(
  Uint8List bytes,
  int start,
  int end,
  TextEncoding encoding,
) {
  final codeUnits = List<int>.filled(end - start, 0);
  for (var i = start; i < end; i++) {
    codeUnits[i - start] = _mapLegacyByte(bytes[i], encoding);
  }
  return String.fromCharCodes(codeUnits);
}

// ===========================================================================
// טבלאות המיפוי
// ===========================================================================

/// מיפוי Windows-1255 עבור 0x80–0xFF (לפי מפת WHATWG; תווים לא מוגדרים → U+FFFD).
const List<int> _cp1255High = [
  0x20AC, 0xFFFD, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, // 0x80
  0x02C6, 0x2030, 0xFFFD, 0x2039, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, // 0x88
  0xFFFD, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, // 0x90
  0x02DC, 0x2122, 0xFFFD, 0x203A, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, // 0x98
  0x00A0, 0x00A1, 0x00A2, 0x00A3, 0x20AA, 0x00A5, 0x00A6, 0x00A7, // 0xA0
  0x00A8, 0x00A9, 0x00D7, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x00AF, // 0xA8
  0x00B0, 0x00B1, 0x00B2, 0x00B3, 0x00B4, 0x00B5, 0x00B6, 0x00B7, // 0xB0
  0x00B8, 0x00B9, 0x00F7, 0x00BB, 0x00BC, 0x00BD, 0x00BE, 0x00BF, // 0xB8
  0x05B0, 0x05B1, 0x05B2, 0x05B3, 0x05B4, 0x05B5, 0x05B6, 0x05B7, // 0xC0
  0x05B8, 0x05B9, 0x05BA, 0x05BB, 0x05BC, 0x05BD, 0x05BE, 0x05BF, // 0xC8
  0x05C0, 0x05C1, 0x05C2, 0x05C3, 0x05F0, 0x05F1, 0x05F2, 0x05F3, // 0xD0
  0x05F4, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, // 0xD8
  0x05D0, 0x05D1, 0x05D2, 0x05D3, 0x05D4, 0x05D5, 0x05D6, 0x05D7, // 0xE0
  0x05D8, 0x05D9, 0x05DA, 0x05DB, 0x05DC, 0x05DD, 0x05DE, 0x05DF, // 0xE8
  0x05E0, 0x05E1, 0x05E2, 0x05E3, 0x05E4, 0x05E5, 0x05E6, 0x05E7, // 0xF0
  0x05E8, 0x05E9, 0x05EA, 0xFFFD, 0xFFFD, 0x200E, 0x200F, 0xFFFD, // 0xF8
];

/// מיפוי ISO-8859-8 עבור 0x80–0xFF (לפי 8859-8.TXT של Unicode Consortium;
/// 0x80–0x9F הם תווי בקרה C1, ובתים לא מוגדרים → U+FFFD).
const List<int> _iso88598High = [
  0x0080, 0x0081, 0x0082, 0x0083, 0x0084, 0x0085, 0x0086, 0x0087, // 0x80
  0x0088, 0x0089, 0x008A, 0x008B, 0x008C, 0x008D, 0x008E, 0x008F, // 0x88
  0x0090, 0x0091, 0x0092, 0x0093, 0x0094, 0x0095, 0x0096, 0x0097, // 0x90
  0x0098, 0x0099, 0x009A, 0x009B, 0x009C, 0x009D, 0x009E, 0x009F, // 0x98
  0x00A0, 0xFFFD, 0x00A2, 0x00A3, 0x00A4, 0x00A5, 0x00A6, 0x00A7, // 0xA0
  0x00A8, 0x00A9, 0x00D7, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x00AF, // 0xA8
  0x00B0, 0x00B1, 0x00B2, 0x00B3, 0x00B4, 0x00B5, 0x00B6, 0x00B7, // 0xB0
  0x00B8, 0x00B9, 0x00F7, 0x00BB, 0x00BC, 0x00BD, 0x00BE, 0xFFFD, // 0xB8
  0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, // 0xC0
  0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, // 0xC8
  0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, // 0xD0
  0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0xFFFD, 0x2017, // 0xD8
  0x05D0, 0x05D1, 0x05D2, 0x05D3, 0x05D4, 0x05D5, 0x05D6, 0x05D7, // 0xE0
  0x05D8, 0x05D9, 0x05DA, 0x05DB, 0x05DC, 0x05DD, 0x05DE, 0x05DF, // 0xE8
  0x05E0, 0x05E1, 0x05E2, 0x05E3, 0x05E4, 0x05E5, 0x05E6, 0x05E7, // 0xF0
  0x05E8, 0x05E9, 0x05EA, 0xFFFD, 0xFFFD, 0x200E, 0x200F, 0xFFFD, // 0xF8
];

/// מיפוי CP862 (IBM862 / DOS עברית) עבור 0x80–0xFF, לפי CP862.TXT של
/// Unicode Consortium. האותיות העבריות יושבות ב-0x80–0x9A, והשאר זהה ל-CP437.
const List<int> _cp862High = [
  0x05D0, 0x05D1, 0x05D2, 0x05D3, 0x05D4, 0x05D5, 0x05D6, 0x05D7, // 0x80
  0x05D8, 0x05D9, 0x05DA, 0x05DB, 0x05DC, 0x05DD, 0x05DE, 0x05DF, // 0x88
  0x05E0, 0x05E1, 0x05E2, 0x05E3, 0x05E4, 0x05E5, 0x05E6, 0x05E7, // 0x90
  0x05E8, 0x05E9, 0x05EA, 0x00A2, 0x00A3, 0x00A5, 0x20A7, 0x0192, // 0x98
  0x00E1, 0x00ED, 0x00F3, 0x00FA, 0x00F1, 0x00D1, 0x00AA, 0x00BA, // 0xA0
  0x00BF, 0x2310, 0x00AC, 0x00BD, 0x00BC, 0x00A1, 0x00AB, 0x00BB, // 0xA8
  0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x2561, 0x2562, 0x2556, // 0xB0
  0x2555, 0x2563, 0x2551, 0x2557, 0x255D, 0x255C, 0x255B, 0x2510, // 0xB8
  0x2514, 0x2534, 0x252C, 0x251C, 0x2500, 0x253C, 0x255E, 0x255F, // 0xC0
  0x255A, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256C, 0x2567, // 0xC8
  0x2568, 0x2564, 0x2565, 0x2559, 0x2558, 0x2552, 0x2553, 0x256B, // 0xD0
  0x256A, 0x2518, 0x250C, 0x2588, 0x2584, 0x258C, 0x2590, 0x2580, // 0xD8
  0x03B1, 0x00DF, 0x0393, 0x03C0, 0x03A3, 0x03C3, 0x00B5, 0x03C4, // 0xE0
  0x03A6, 0x0398, 0x03A9, 0x03B4, 0x221E, 0x03C6, 0x03B5, 0x2229, // 0xE8
  0x2261, 0x00B1, 0x2265, 0x2264, 0x2320, 0x2321, 0x00F7, 0x2248, // 0xF0
  0x00B0, 0x2219, 0x00B7, 0x221A, 0x207F, 0x00B2, 0x25A0, 0x00A0, // 0xF8
];

/// מיפוי Windows-1252 עבור 0x80–0x9F. מ-0xA0 ומעלה הוא זהה ל-Latin-1.
const List<int> _cp1252High = [
  0x20AC, 0xFFFD, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, // 0x80
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0xFFFD, 0x017D, 0xFFFD, // 0x88
  0xFFFD, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, // 0x90
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0xFFFD, 0x017E, 0x0178, // 0x98
  0x00A0, 0x00A1, 0x00A2, 0x00A3, 0x00A4, 0x00A5, 0x00A6, 0x00A7, // 0xA0
  0x00A8, 0x00A9, 0x00AA, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x00AF, // 0xA8
  0x00B0, 0x00B1, 0x00B2, 0x00B3, 0x00B4, 0x00B5, 0x00B6, 0x00B7, // 0xB0
  0x00B8, 0x00B9, 0x00BA, 0x00BB, 0x00BC, 0x00BD, 0x00BE, 0x00BF, // 0xB8
  0x00C0, 0x00C1, 0x00C2, 0x00C3, 0x00C4, 0x00C5, 0x00C6, 0x00C7, // 0xC0
  0x00C8, 0x00C9, 0x00CA, 0x00CB, 0x00CC, 0x00CD, 0x00CE, 0x00CF, // 0xC8
  0x00D0, 0x00D1, 0x00D2, 0x00D3, 0x00D4, 0x00D5, 0x00D6, 0x00D7, // 0xD0
  0x00D8, 0x00D9, 0x00DA, 0x00DB, 0x00DC, 0x00DD, 0x00DE, 0x00DF, // 0xD8
  0x00E0, 0x00E1, 0x00E2, 0x00E3, 0x00E4, 0x00E5, 0x00E6, 0x00E7, // 0xE0
  0x00E8, 0x00E9, 0x00EA, 0x00EB, 0x00EC, 0x00ED, 0x00EE, 0x00EF, // 0xE8
  0x00F0, 0x00F1, 0x00F2, 0x00F3, 0x00F4, 0x00F5, 0x00F6, 0x00F7, // 0xF0
  0x00F8, 0x00F9, 0x00FA, 0x00FB, 0x00FC, 0x00FD, 0x00FE, 0x00FF, // 0xF8
];
