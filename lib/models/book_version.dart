import 'package:otzaria/models/books.dart';

/// מהדורה (גרסה) של ספר מטבלת book_version ב-seforim.db.
///
/// [hasContent] — הטקסט המלא של המהדורה שמור ב-version_line וניתן לפתיחה.
/// כש-false השורה היא מטא-דאטה בלבד: בספר חד-גרסתי הנוסח המוצג הוא-הוא
/// המהדורה; בספר רב-גרסתי ממאגר ישן טקסט המהדורה אינו כלול.
class BookVersionInfo {
  final String versionTitle;
  final String? heVersionTitle;
  final String? versionSource;
  final double? priority;
  final String? license;
  final String? versionNotes;
  final String? heVersionNotes;
  final bool hasContent;

  /// גרסה שהיא ספר נפרד בקטלוג (ספר אישי, או הראשי הרשמי של גרסה אישית),
  /// שנפתח כמות שהוא ולא דרך version_line.
  final Book? separateBook;

  const BookVersionInfo({
    required this.versionTitle,
    this.heVersionTitle,
    this.versionSource,
    this.priority,
    this.license,
    this.versionNotes,
    this.heVersionNotes,
    required this.hasContent,
    this.separateBook,
  });

  /// שם התצוגה: הכותרת העברית כשקיימת (ולא ריקה), אחרת ה-versionTitle של ספריא.
  String get displayTitle => heVersionTitle?.trim().isNotEmpty == true
      ? heVersionTitle!
      : versionTitle;

  factory BookVersionInfo.fromDbRow(Map<String, dynamic> row) {
    return BookVersionInfo(
      versionTitle: row['versionTitle'] as String,
      heVersionTitle: row['heVersionTitle'] as String?,
      versionSource: row['versionSource'] as String?,
      priority: (row['priority'] as num?)?.toDouble(),
      license: row['license'] as String?,
      versionNotes: row['versionNotes'] as String?,
      heVersionNotes: row['heVersionNotes'] as String?,
      hasContent: (row['hasContent'] as int? ?? 0) != 0,
    );
  }
}
