import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/user_content_import/models/user_import_models.dart';
import 'package:otzaria/user_content_import/repository/user_content_repository.dart';
import 'package:otzaria/user_content_import/services/user_headings_builder.dart';
import 'package:otzaria/user_content_import/services/user_import_parser.dart';
import 'package:otzaria/utils/file/document_converter.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/file/text_encoding.dart';
import 'package:path/path.dart' as p;

/// שמות קובץ הכותרות הרוחבי (לכל התיקייה), ושל קובץ הגרסאות.
const _folderHeadingFileNames = {'כותרות.csv', 'headings.csv'};
const _versionFileNames = {'גרסאות.csv', 'versions.csv'};

/// סיומות קובץ כותרות של ספר בודד: `<שם הקובץ>.כותרות.csv`.
const _perBookHeadingSuffixes = ['.כותרות.csv', '.headings.csv'];

/// קולט קובצי כותרות וגרסאות שיושבים בתיקיית הספרים האישיים, כחלק מסריקת
/// התיקייה. הזיהוי הוא לפי נתיב הקובץ, כך שהנתונים עוברים עם התיקייה
/// ונמחקים עם הספר.
///
/// קובץ שלא השתנה, ושהספרים שלו לא השתנו, מדולג.
class UserSidecarSync {
  /// מיישם את כל הקבצים הנלווים שתחת [folderPath]. מחזיר שגיאות לתצוגה
  /// למשתמש; לעולם אינו זורק.
  static Future<List<String>> applyForFolder({
    required MyDatabase userDb,
    required String folderPath,
  }) async {
    final repo = UserContentRepository(userDb);
    final errors = <String>[];
    final seen = <String>{};

    try {
      final dir = Directory(folderPath);
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is! File) continue;
          final name = p.basename(entity.path);
          final kind = _kindOf(name);
          if (kind == null) continue;
          seen.add(entity.path);
          try {
            await _applyFile(repo, entity, kind, errors);
          } catch (e) {
            errors.add('$name: הקליטה נכשלה ($e)');
          }
        }
      }

      // קובץ שנמחק מהתיקייה — הנתונים שהגיעו ממנו יורדים איתו.
      for (final tracked in await repo.trackedSidecarsUnder(folderPath)) {
        if (seen.contains(tracked)) continue;
        await repo.forgetSidecar(tracked);
      }
    } catch (e) {
      debugPrint('⚠️ [UserSidecarSync] failed for $folderPath: $e');
      errors.add('קליטת קובצי הכותרות והגרסאות נכשלה: $e');
    }
    return errors;
  }

  static _SidecarKind? _kindOf(String fileName) {
    if (_folderHeadingFileNames.contains(fileName)) {
      return _SidecarKind.folderHeadings;
    }
    if (_versionFileNames.contains(fileName)) return _SidecarKind.versions;
    final lower = fileName.toLowerCase();
    for (final suffix in _perBookHeadingSuffixes) {
      if (lower.endsWith(suffix.toLowerCase())) {
        return _SidecarKind.bookHeadings;
      }
    }
    return null;
  }

  static Future<void> _applyFile(
    UserContentRepository repo,
    File file,
    _SidecarKind kind,
    List<String> errors,
  ) async {
    final name = p.basename(file.path);
    final content = await readTextFileSmart(file);

    if (kind == _SidecarKind.versions) {
      final parsed = UserImportParser.parseVersions(content);
      _collectParseErrors(name, parsed.errors, errors);
      final records = <UserBookVersionRecord>[];
      final signature = StringBuffer(await _fileStamp(file));
      for (final row in parsed.rows) {
        if (!row.primarySource.isUser) {
          final version = await _bookAtRelativePath(repo, file, row.version);
          if (version == null) {
            errors.add(
              '$name שורה ${row.rowNumber}: הספר "${row.version}" לא נמצא',
            );
            continue;
          }
          signature.write(
            '|${row.primarySource.wireKey}:${row.primary}:'
            '${row.primaryCategoryPath ?? ''}:${version.id}',
          );
          records.add(
            UserBookVersionRecord.ofCatalogBook(
              versionBookId: version.id,
              primarySource: row.primarySource,
              primaryTitle: row.primary,
              primaryCategoryPath: row.primaryCategoryPath,
              versionTitle:
                  row.label ?? p.basenameWithoutExtension(row.version),
              versionNotes: row.notes,
              priority: row.priority,
            ),
          );
          continue;
        }
        final primary = await _bookAtRelativePath(repo, file, row.primary);
        final version = await _bookAtRelativePath(repo, file, row.version);
        if (primary == null || version == null) {
          errors.add(
            '$name שורה ${row.rowNumber}: הספר '
            '"${primary == null ? row.primary : row.version}" לא נמצא',
          );
          continue;
        }
        signature.write('|${primary.id}:${version.id}');
        records.add(
          UserBookVersionRecord(
            versionBookId: version.id,
            primaryBookId: primary.id,
            versionTitle: row.label ?? p.basenameWithoutExtension(row.version),
            versionNotes: row.notes,
            priority: row.priority,
          ),
        );
      }
      if (await _isUnchanged(repo, file.path, signature.toString())) return;
      await repo.replaceVersions(records, source: file.path);
      await repo.setSidecarSignature(file.path, signature.toString());
      return;
    }

    final perBook = kind == _SidecarKind.bookHeadings;
    final parsed = UserImportParser.parseHeadings(
      content,
      requireBook: !perBook,
    );
    _collectParseErrors(name, parsed.errors, errors);

    // כל הכותרות של ספר אחד נכתבות יחד, כדי שהקובץ יגדיר את מבניו במלואם.
    final rowsByBook = <String, List<ParsedHeading>>{};
    final booksByKey = <String, _UserBookFile>{};
    final fileBook = perBook ? await _bookOfPerBookFile(repo, file) : null;
    for (final row in parsed.rows) {
      final book = perBook
          ? fileBook
          : await _bookByTitle(repo, row.bookTitle!, row.categoryId);
      if (book == null) {
        errors.add(
          '$name שורה ${row.rowNumber}: הספר '
          '"${row.bookTitle ?? _bookFileBaseName(file)}" לא נמצא בספרייה האישית',
        );
        continue;
      }
      final key = '${book.id}';
      booksByKey[key] = book;
      (rowsByBook[key] ??= []).add(row);
    }

    final signature = StringBuffer(await _fileStamp(file));
    for (final key in rowsByBook.keys.toList()..sort()) {
      final book = booksByKey[key]!;
      signature.write('|${book.id}:${book.lastModified}');
    }
    if (await _isUnchanged(repo, file.path, signature.toString())) return;

    await repo.forgetSidecar(file.path);
    for (final entry in rowsByBook.entries) {
      final book = booksByKey[entry.key]!;
      final lines = await readBookLines(
        filePath: book.filePath,
        fileType: book.fileType,
        title: book.title,
        errors: errors,
        errorPrefix: name,
      );
      if (lines == null) continue;
      final built = UserHeadingsBuilder.build(entry.value, lines);
      for (final error in built.errors) {
        errors.add('$name $error');
      }
      await repo.replaceBookHeadings(
        book.id,
        built.structures,
        source: file.path,
      );
    }
    await repo.setSidecarSignature(file.path, signature.toString());
  }

  /// שורות הספר באותה המרה שבה הסורק מפרסר את תוכן העניינים — כך מספרי
  /// השורות תואמים לניווט. סינכרוני ובלי מטמון, כי רץ גם ב-isolate הסנכרון.
  static Future<List<String>?> readBookLines({
    required String filePath,
    required String? fileType,
    required String title,
    required List<String> errors,
    required String errorPrefix,
  }) async {
    final format = documentFormatOf(fileType: fileType, path: filePath);
    if (format == null || !format.isTextual) {
      errors.add(
        '$errorPrefix: כותרות נתמכות רק בספרי טקסט ("$title")',
      );
      return null;
    }
    try {
      final bytes = await File(filePath).readAsBytes();
      final text = convertDocumentBytesSync(
        bytes,
        title,
        format: format,
        embedImages: false,
        path: filePath,
      );
      return text.split('\n');
    } catch (e) {
      errors.add('$errorPrefix: קריאת הספר "$title" נכשלה ($e)');
      return null;
    }
  }

  /// הספר שקובץ הכותרות שלו הוא `<שם הספר>.כותרות.csv` — אותו שם בסיס
  /// באותה תיקייה.
  static Future<_UserBookFile?> _bookOfPerBookFile(
    UserContentRepository repo,
    File file,
  ) async {
    final base = _bookFileBaseName(file);
    final dir = Directory(p.dirname(file.path));
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (p.basenameWithoutExtension(entity.path) != base) continue;
      final book = await _bookAt(repo, entity.path);
      if (book != null) return book;
    }
    return null;
  }

  static Future<_UserBookFile?> _bookAtRelativePath(
    UserContentRepository repo,
    File sidecar,
    String relativePath,
  ) async {
    final resolved = p.normalize(
      p.join(p.dirname(sidecar.path), relativePath.replaceAll('\\', '/')),
    );
    return _bookAt(repo, resolved);
  }

  static Future<_UserBookFile?> _bookAt(
    UserContentRepository repo,
    String filePath,
  ) async {
    final row = await repo.bookByFilePath(filePath);
    if (row == null) return null;
    return _UserBookFile(
      id: row.id,
      title: p.basenameWithoutExtension(filePath),
      filePath: filePath,
      fileType: row.fileType,
      lastModified: row.lastModified,
    );
  }

  static Future<_UserBookFile?> _bookByTitle(
    UserContentRepository repo,
    String title,
    int? categoryId,
  ) async {
    final row = await repo.bookFileByTitle(title, categoryId: categoryId);
    if (row == null || row.filePath == null) return null;
    return _UserBookFile(
      id: row.id,
      title: title,
      filePath: row.filePath!,
      fileType: row.fileType,
      lastModified: row.lastModified,
    );
  }

  static String _bookFileBaseName(File file) {
    final name = p.basename(file.path);
    final lower = name.toLowerCase();
    for (final suffix in _perBookHeadingSuffixes) {
      if (lower.endsWith(suffix.toLowerCase())) {
        return name.substring(0, name.length - suffix.length);
      }
    }
    return p.basenameWithoutExtension(name);
  }

  static Future<bool> _isUnchanged(
    UserContentRepository repo,
    String path,
    String signature,
  ) async => await repo.sidecarSignature(path) == signature;

  static Future<String> _fileStamp(File file) async {
    final stat = await file.stat();
    return '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
  }

  static void _collectParseErrors(
    String fileName,
    List<ImportRowError> parseErrors,
    List<String> errors,
  ) {
    for (final error in parseErrors) {
      errors.add('$fileName שורה ${error.lineNumber}: ${error.message}');
    }
  }
}

enum _SidecarKind { bookHeadings, folderHeadings, versions }

class _UserBookFile {
  final int id;
  final String title;
  final String filePath;
  final String? fileType;
  final int lastModified;

  const _UserBookFile({
    required this.id,
    required this.title,
    required this.filePath,
    required this.fileType,
    required this.lastModified,
  });
}
