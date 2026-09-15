import 'dart:io';

import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/utils/file/document_converter.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:path/path.dart' as p;

/// תוצאת העתקת קבצים לתיקיית הספרים האישיים.
class PersonalBooksImportResult {
  const PersonalBooksImportResult({
    this.copied = 0,
    this.skippedUnsupported = 0,
    this.errors = const [],
  });

  /// מספר הקבצים שהועתקו בהצלחה (כולל דריסת גרסה קודמת של אותו קובץ).
  final int copied;

  /// מספר הקבצים שדולגו כי סיומתם אינה נתמכת.
  final int skippedUnsupported;

  final List<String> errors;
}

/// שירות ייבוא ספרים אישיים במובייל.
///
/// קבצים שנבחרו דרך בורר המערכת (SAF מספק נתיב זמני נגיש) מועתקים לתיקייה
/// קבועה בתוך אחסון האפליקציה ([AppPaths.getPersonalBooksImportPath]).
/// התיקייה נרשמת כתיקייה מותאמת אישית רגילה, וכל צינור הסריקה, האינדוקס
/// וה-prune הקיים חל עליה ללא שינוי.
class PersonalBooksImportService {
  PersonalBooksImportService({this._folderPathOverride});

  final String? _folderPathOverride;

  /// הסיומות שמנוע הסנכרון יודע לקלוט — נגזרות מה-registry היחיד.
  static final Set<String> supportedExtensions = kSupportedDottedBookExtensions
      .toSet();

  /// נתיב תיקיית הספרים האישיים.
  Future<String> getFolderPath() async =>
      _folderPathOverride ?? await AppPaths.getPersonalBooksImportPath();

  /// תיקיית היעד לייבוא תיקייה שלמה: תת-תיקייה בשם [folderName], כך
  /// שמבנה התיקייה נשמר כקטגוריה בעץ הספרייה.
  Future<String> folderImportTarget(String folderName) async {
    final name = folderName.replaceAll(RegExp(r'[\\/]'), '_').trim();
    return p.join(
      await getFolderPath(),
      name.isEmpty || name == '..' ? 'תיקייה מיובאת' : name,
    );
  }

  /// מוחק מבין הקבצים שהועתקו מתיקייה את מה שאינו ספר תקין לפי תוכנו —
  /// ההעתקה הנייטיבית מסננת לפי סיומת בלבד.
  Future<PersonalBooksImportResult> keepValidCopiedFiles(
    List<String> copiedPaths,
  ) async {
    var copied = 0;
    var skippedUnsupported = 0;
    for (final path in copiedPaths) {
      if (await isSupportedBookFileByContent(path)) {
        copied++;
      } else {
        skippedUnsupported++;
        await File(path).delete();
      }
    }
    return PersonalBooksImportResult(
      copied: copied,
      skippedUnsupported: skippedUnsupported,
    );
  }

  /// הודעת שגיאה למשתמש על קובץ שלא הועתק.
  static String describeCopyError(String fileName, Object error) {
    final text = error.toString();
    final isNoSpace =
        (error is FileSystemException && error.osError?.errorCode == 28) ||
        text.contains('No space') ||
        text.contains('ENOSPC');
    return isNoSpace
        ? '"$fileName": אין מספיק מקום פנוי באחסון המכשיר'
        : '"$fileName": $text';
  }

  /// בדיקת סיומת בלבד, לרשימת הקבצים שכבר יובאו. לשער הכניסה משמש
  /// `isSupportedBookFileByContent`, שבודק גם את תוכן הקובץ.
  static bool isSupportedFile(String filePath) =>
      supportedExtensions.contains(p.extension(filePath).toLowerCase());

  /// מעתיק את הקבצים שנבחרו לתיקיית הספרים האישיים.
  ///
  /// קובץ בעל שם זהה לקובץ קיים דורס אותו — כך ייבוא חוזר של גרסה מעודכנת
  /// יעדכן את הספר בסנכרון הבא. קבצי המקור לעולם אינם נמחקים.
  Future<PersonalBooksImportResult> copyFiles(List<String> sourcePaths) async {
    final folderPath = await getFolderPath();
    await Directory(folderPath).create(recursive: true);

    var copied = 0;
    var skippedUnsupported = 0;
    final errors = <String>[];

    for (final sourcePath in sourcePaths) {
      // שער התוכן ולא הסיומת בלבד: ‎.xml‎ שאינו מסמך Word היה מועתק, ואז
      // מדולג בשקט בסריקה — המשתמש רואה "יובא" וספר שלעולם אינו מופיע.
      if (!await isSupportedBookFileByContent(sourcePath)) {
        skippedUnsupported++;
        continue;
      }
      final fileName = p.basename(sourcePath);
      try {
        final targetPath = p.join(folderPath, fileName);
        // העתקת קובץ על עצמו (openRead+openWrite לאותו נתיב) מרוקנת אותו.
        if (p.equals(sourcePath, targetPath)) {
          copied++;
          continue;
        }
        // העתקה בזרימה — קבצי PDF עלולים להיות גדולים מהזיכרון הפנוי.
        await File(sourcePath).openRead().pipe(File(targetPath).openWrite());
        copied++;
      } catch (e) {
        errors.add(describeCopyError(fileName, e));
      }
    }

    return PersonalBooksImportResult(
      copied: copied,
      skippedUnsupported: skippedUnsupported,
      errors: errors,
    );
  }

  /// מחזיר את קבצי הספרים שבתיקייה, ממוינים לפי שם.
  Future<List<File>> listImportedFiles() async {
    final dir = Directory(await getFolderPath());
    if (!await dir.exists()) return [];

    final files = <File>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File && isSupportedFile(entity.path)) {
        files.add(entity);
      }
    }
    files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    return files;
  }

  /// מוחק קובץ ספר מיובא. הסרת הספר מה-DB מתבצעת בסריקה הבאה (prune).
  ///
  /// זורק [ArgumentError] אם הנתיב אינו בתוך תיקיית הספרים האישיים —
  /// הגנה מפני מחיקת קובץ שרירותי.
  Future<void> deleteImportedFile(String filePath) async {
    final folderPath = await getFolderPath();
    if (!p.isWithin(folderPath, filePath)) {
      throw ArgumentError('הקובץ אינו בתיקיית הספרים האישיים: $filePath');
    }
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
