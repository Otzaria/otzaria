/// רשומת מטמון מתמשך לתוכן הממומר של קובץ Word (docx) חיצוני.
///
/// ההמרה של docx ל-HTML של אוצריא היא יקרה (פירוק XML מלא בכל פתיחה).
/// המטמון נשמר ב-`cache.db` (כתיב), ומפתח-התוקף שלו הוא שילוב של
/// [fileSize] + [lastModified] של קובץ ה-docx: אם המשתמש עורך את הקובץ
/// (ספרים אישיים), הערכים משתנים, ההתאמה נכשלת, והתוכן מומר מחדש — כך
/// הטריות נשמרת תמיד, בלי להקפיא תוכן ישן.
class DocxTextCacheEntry {
  final String filePath;
  final int fileSize;
  final int lastModified;

  /// גרסת הממיר שיצרה את הרשומה. חלק ממפתח-התוקף:
  /// שדרוג הממיר פוסל רשומות ישנות גם אם הקובץ עצמו לא השתנה.
  final int converterVersion;

  /// הטקסט הממומר המלא (פלט [docxToText]) — HTML שורות מופרדות ב-`\n`.
  final String text;
  final int createdAt;
  final int accessedAt;

  const DocxTextCacheEntry({
    required this.filePath,
    required this.fileSize,
    required this.lastModified,
    required this.converterVersion,
    required this.text,
    required this.createdAt,
    required this.accessedAt,
  });

  factory DocxTextCacheEntry.fromMap(Map<String, dynamic> map) {
    return DocxTextCacheEntry(
      filePath: map['filePath'] as String,
      fileSize: map['fileSize'] as int? ?? 0,
      lastModified: map['lastModified'] as int? ?? 0,
      converterVersion: map['converterVersion'] as int? ?? 0,
      text: map['text'] as String? ?? '',
      createdAt: map['createdAt'] as int? ?? 0,
      accessedAt: map['accessedAt'] as int? ?? 0,
    );
  }

  /// האם הרשומה תקפה: זהות הקובץ (גודל + זמן-שינוי) **וגם** התאמת גרסת
  /// הממיר. אי-התאמה באחד מהם — הרשומה נפסלת והתוכן מומר מחדש.
  bool isValidFor(int size, int modified, int version) =>
      fileSize == size &&
      lastModified == modified &&
      converterVersion == version;

  @override
  String toString() =>
      'DocxTextCacheEntry(filePath: $filePath, fileSize: $fileSize, '
      'lastModified: $lastModified, v: $converterVersion, '
      'textLen: ${text.length})';
}
