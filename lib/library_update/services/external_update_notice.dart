import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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

  static const String markerFileName = '.otzaria-external-update.json';
  static const int _formatVersion = 1;

  final File _file;
  final List<int> _rawContent;

  /// מזהי `seforim.db` של הספרים שתוכנם השתנה (מסלול דלתא בלבד).
  final Set<int> booksTouched;

  /// הוחלף מסד שלם, חסרה רשימת ספרים, או שהסימון אינו קריא.
  final bool needsFullReconcile;

  /// דלתא שלא שינתה אף ספר אינה דורשת אינדוקס.
  bool get needsIndexing => needsFullReconcile || booksTouched.isNotEmpty;

  static File fileFor(String dbPath) =>
      File(p.join(p.dirname(dbPath), markerFileName));

  /// `null` כשאין סימון.
  static Future<ExternalUpdateNotice?> read(String dbPath) async {
    final file = fileFor(dbPath);
    if (!await file.exists()) return null;
    final raw = await file.readAsBytes();
    try {
      final json = jsonDecode(utf8.decode(raw));
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
    } on FormatException catch (e) {
      // סימון פגום עדיין מעיד על עדכון חיצוני — השוואה מלאה, ואז נמחק כרגיל.
      debugPrint('External update notice unreadable: $e');
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
    if (!listEquals(await _file.readAsBytes(), _rawContent)) return;
    await _file.delete();
  }
}
