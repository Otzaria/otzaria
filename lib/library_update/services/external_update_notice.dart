import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// הסימון שהמעדכן הלא-מקוון כותב ליד `seforim.db` אחרי שעדכן אותו מבחוץ.
///
/// `isBookIndexed` בודק נוכחות ולא תוכן, ולכן בלי אינדוקס מחדש ספר שהשתנה
/// מבחוץ נשאר בחיפוש בגרסתו הישנה.
class ExternalUpdateNotice {
  ExternalUpdateNotice._(
    this._file,
    this._rawContent,
    this.booksTouched, {
    required this.needsFullReconcile,
  });

  static const String fileName = '.otzaria-external-update.json';
  static const int _formatVersion = 1;

  final File _file;
  final String _rawContent;

  /// מזהי `seforim.db` של הספרים שתוכנם השתנה (מסלול דלתא בלבד).
  final Set<int> booksTouched;

  /// הוחלף מסד שלם, חסרה רשימת ספרים, או שהסימון אינו קריא.
  final bool needsFullReconcile;

  /// דלתא שלא שינתה אף ספר אינה דורשת אינדוקס.
  bool get needsIndexing => needsFullReconcile || booksTouched.isNotEmpty;

  static File fileFor(String dbPath) =>
      File(p.join(p.dirname(dbPath), fileName));

  /// `null` כשאין סימון.
  static Future<ExternalUpdateNotice?> read(String dbPath) async {
    final file = fileFor(dbPath);
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic> &&
          json['formatVersion'] == _formatVersion) {
        final books = json['booksTouched'];
        return ExternalUpdateNotice._(
          file,
          raw,
          books is List ? books.whereType<int>().toSet() : const {},
          needsFullReconcile:
              json['route'] != 'delta' ||
              json['fullReconcile'] == true ||
              books is! List,
        );
      }
    } on FormatException {
      // סימון פגום עדיין מעיד על עדכון חיצוני — נופלים להשוואה מלאה.
    }
    return ExternalUpdateNotice._(
      file,
      raw,
      const {},
      needsFullReconcile: true,
    );
  }

  /// מוחק את הסימון, אלא אם המעדכן כתב בינתיים סימון חדש במקומו.
  Future<void> delete() async {
    if (!await _file.exists()) return;
    if (await _file.readAsString() != _rawContent) return;
    await _file.delete();
  }
}
