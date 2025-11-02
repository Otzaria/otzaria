import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:otzaria/core/app_paths.dart';
import '../models/annotation_mapping.dart';

/// ספק נתונים לניהול קבצי הערות במערכת הקבצים
///
/// אחראי על קריאה וכתיבה של קבצי טקסט ו-JSON של הערות.
class FileSystemNotesProvider {
  static FileSystemNotesProvider? _instance;

  FileSystemNotesProvider._();

  /// Singleton instance
  static FileSystemNotesProvider get instance {
    _instance ??= FileSystemNotesProvider._();
    return _instance!;
  }

  /// קבלת נתיב תיקיית ההערות
  ///
  /// מחזיר את הנתיב המלא לתיקיית "הערות" תחת תיקיית אוצריא.
  Future<String> getNotesDirectory() async {
    final libraryPath = await AppPaths.getLibraryPath();
    return p.join(libraryPath, 'אוצריא', 'הערות אישיות');
  }

  /// יצירת תיקיית הערות אם לא קיימת
  ///
  /// מוודא שתיקיית ההערות קיימת, ויוצר אותה אם צריך.
  Future<void> ensureNotesDirectoryExists() async {
    final notesDir = await getNotesDirectory();
    final directory = Directory(notesDir);

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
  }

  /// קבלת נתיב קובץ הערות לספר
  String _getNotesFilePath(String notesDir, String bookTitle) {
    return p.join(notesDir, 'הערות אישיות על $bookTitle.txt');
  }

  /// קבלת נתיב קובץ מיפוי לספר
  String _getMappingFilePath(String notesDir, String bookTitle) {
    return p.join(notesDir, '${bookTitle}_annotations.json');
  }

  /// Escape תוכן הערה לשמירה בקובץ
  ///
  /// מבצע escape של תווים מיוחדים:
  /// - `\` → `\\`
  /// - `|` → `\|`
  /// - ירידת שורה → `\\n`
  String escapeNoteContent(String content) {
    return content
        .replaceAll('\\', '\\\\') // חייב להיות ראשון!
        .replaceAll('|', '\\|')
        .replaceAll('\n', '\\n');
  }

  /// Unescape תוכן הערה מקובץ
  ///
  /// מבטל את ה-escape של תווים מיוחדים.
  String unescapeNoteContent(String content) {
    return content
        .replaceAll('\\n', '\n')
        .replaceAll('\\|', '|')
        .replaceAll('\\\\', '\\'); // חייב להיות אחרון!
  }

  /// קריאת קובץ הערות
  ///
  /// מחזיר רשימה של שורות מקובץ ההערות.
  /// אם הקובץ לא קיים, מחזיר רשימה ריקה.
  Future<List<String>> readNotesFile(String bookTitle) async {
    await ensureNotesDirectoryExists();
    final notesDir = await getNotesDirectory();
    final filePath = _getNotesFilePath(notesDir, bookTitle);
    final file = File(filePath);

    if (!await file.exists()) {
      return [];
    }

    try {
      final content = await file.readAsString(encoding: utf8);
      return content
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();
    } catch (e) {
      throw FileSystemNotesException('Failed to read notes file: $e');
    }
  }

  /// כתיבת קובץ הערות
  ///
  /// שומר רשימה של שורות לקובץ ההערות.
  /// יוצר גיבוי לפני הכתיבה.
  Future<void> writeNotesFile(String bookTitle, List<String> notes) async {
    await ensureNotesDirectoryExists();
    final notesDir = await getNotesDirectory();
    final filePath = _getNotesFilePath(notesDir, bookTitle);
    final file = File(filePath);

    // יצירת גיבוי אם הקובץ קיים
    if (await file.exists()) {
      await _createBackup(filePath);
    }

    try {
      await file.writeAsString(notes.join('\n') + '\n', encoding: utf8);

      // ניקוי גיבויים ישנים
      await _cleanupOldBackups(filePath);
    } catch (e) {
      // ניסיון לשחזר מגיבוי
      await _restoreFromBackup(filePath);
      throw FileSystemNotesException('Failed to write notes file: $e');
    }
  }

  /// הוספת הערה לקובץ
  ///
  /// מוסיף שורה חדשה לסוף קובץ ההערות.
  /// מחזיר את מספר השורה החדשה (מתחיל מ-1).
  Future<int> appendNoteToFile(String bookTitle, String noteContent) async {
    await ensureNotesDirectoryExists();

    // קריאת השורות הקיימות
    final existingLines = await readNotesFile(bookTitle);
    final newLineNumber = existingLines.length + 1;

    // הוספת השורה החדשה
    existingLines.add(noteContent);
    await writeNotesFile(bookTitle, existingLines);

    return newLineNumber;
  }

  /// קריאת קובץ מיפוי
  ///
  /// מחזיר רשימה של מיפויים מקובץ ה-JSON.
  /// אם הקובץ לא קיים, מחזיר רשימה ריקה.
  Future<List<AnnotationMapping>> readMappingFile(String bookTitle) async {
    await ensureNotesDirectoryExists();
    final notesDir = await getNotesDirectory();
    final filePath = _getMappingFilePath(notesDir, bookTitle);
    final file = File(filePath);

    if (!await file.exists()) {
      return [];
    }

    try {
      final content = await file.readAsString(encoding: utf8);
      final json = jsonDecode(content) as Map<String, dynamic>;
      final annotations = json['annotations'] as List<dynamic>;

      return annotations
          .map((item) =>
              AnnotationMapping.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw FileSystemNotesException('Failed to read mapping file: $e');
    }
  }

  /// כתיבת קובץ מיפוי
  ///
  /// שומר רשימה של מיפויים לקובץ JSON.
  /// יוצר גיבוי לפני הכתיבה.
  Future<void> writeMappingFile(
    String bookTitle,
    List<AnnotationMapping> mappings,
  ) async {
    await ensureNotesDirectoryExists();
    final notesDir = await getNotesDirectory();
    final filePath = _getMappingFilePath(notesDir, bookTitle);
    final file = File(filePath);

    // יצירת גיבוי אם הקובץ קיים
    if (await file.exists()) {
      await _createBackup(filePath);
    }

    try {
      final json = {
        'version': '1.0',
        'bookTitle': bookTitle,
        'lastModified': DateTime.now().toIso8601String(),
        'annotations': mappings.map((m) => m.toJson()).toList(),
      };

      final jsonString = JsonEncoder.withIndent('  ').convert(json);
      await file.writeAsString(jsonString, encoding: utf8);

      // ניקוי גיבויים ישנים
      await _cleanupOldBackups(filePath);
    } catch (e) {
      // ניסיון לשחזר מגיבוי
      await _restoreFromBackup(filePath);
      throw FileSystemNotesException('Failed to write mapping file: $e');
    }
  }

  /// יצירת גיבוי של קובץ
  Future<void> _createBackup(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final backupPath = '$filePath.backup.$timestamp';

    try {
      await file.copy(backupPath);
    } catch (e) {
      // אם הגיבוי נכשל, ממשיכים בכל זאת
    }
  }

  /// שחזור מגיבוי
  Future<void> _restoreFromBackup(String filePath) async {
    final directory = Directory(p.dirname(filePath));
    final baseName = p.basename(filePath);

    // חיפוש הגיבוי האחרון
    final backups = <File>[];
    await for (final entity in directory.list()) {
      if (entity is File) {
        final fileName = p.basename(entity.path);
        if (fileName.startsWith('$baseName.backup.')) {
          backups.add(entity);
        }
      }
    }

    if (backups.isEmpty) return;

    // מיון לפי זמן (החדש ביותר ראשון)
    backups.sort((a, b) {
      final aTime = _getBackupTimestamp(a.path);
      final bTime = _getBackupTimestamp(b.path);
      return bTime.compareTo(aTime);
    });

    // שחזור מהגיבוי האחרון
    try {
      await backups.first.copy(filePath);
    } catch (e) {
      // אם השחזור נכשל, אין מה לעשות
    }
  }

  /// ניקוי גיבויים ישנים
  ///
  /// שומר רק 3 גיבויים אחרונים ומוחק את השאר.
  Future<void> _cleanupOldBackups(String filePath) async {
    final directory = Directory(p.dirname(filePath));
    final baseName = p.basename(filePath);

    // חיפוש כל הגיבויים
    final backups = <File>[];
    await for (final entity in directory.list()) {
      if (entity is File) {
        final fileName = p.basename(entity.path);
        if (fileName.startsWith('$baseName.backup.')) {
          backups.add(entity);
        }
      }
    }

    // מיון לפי זמן (החדש ביותר ראשון)
    backups.sort((a, b) {
      final aTime = _getBackupTimestamp(a.path);
      final bTime = _getBackupTimestamp(b.path);
      return bTime.compareTo(aTime);
    });

    // שמירת 3 ראשונים, מחיקת השאר
    for (int i = 3; i < backups.length; i++) {
      try {
        await backups[i].delete();
      } catch (e) {
        // אם המחיקה נכשלה, ממשיכים
      }
    }

    // מחיקת גיבויים ישנים מעל שבוע
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    for (final backup in backups) {
      final timestamp = _getBackupTimestamp(backup.path);
      final backupDate = DateTime.fromMillisecondsSinceEpoch(timestamp);

      if (backupDate.isBefore(weekAgo)) {
        try {
          await backup.delete();
        } catch (e) {
          // אם המחיקה נכשלה, ממשיכים
        }
      }
    }
  }

  /// חילוץ timestamp מנתיב גיבוי
  int _getBackupTimestamp(String backupPath) {
    try {
      final fileName = p.basename(backupPath);
      final parts = fileName.split('.backup.');
      if (parts.length < 2) return 0;
      return int.parse(parts.last);
    } catch (e) {
      return 0;
    }
  }
}

/// Exception for file system notes operations
class FileSystemNotesException implements Exception {
  final String message;

  FileSystemNotesException(this.message);

  @override
  String toString() => 'FileSystemNotesException: $message';
}
