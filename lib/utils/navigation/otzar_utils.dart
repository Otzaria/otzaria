import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'otzar_main_window_input.dart';
import 'package:flutter/foundation.dart';

import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher_string.dart';

class OtzarUtils {
  static final List<String> _availableDrives = [
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
  ];

  /// תיקיות העגינה שבהן מק מציגה כוננים — המקבילה לאותיות הכוננים ב-Windows.
  static const List<String> _macMountRoots = ['/Volumes'];

  /// ה-URI שמטפל הפרוטוקול של אוצר החכמה מקבל במק.
  ///
  /// בלי הרווח שלפני `/c` שבמסלול Windows: שם ה-URI הוא ארגומנט תהליך, וכאן
  /// כתובת שעוברת ב-LaunchServices ורווח בה היה נחתך.
  @visibleForTesting
  static String macBookUri(int bookId, {int? tabId, int page = 1}) =>
      'OtzarBook://book/$bookId/p/${_page(page)}'
      '/t/${tabId ?? Random().nextInt(1000000)}/fs/0/start/0/end/0/c';

  /// מספר העמוד בקישור — מבוסס-1; ערך קטן מ-1 נחשב לעמוד הראשון.
  static int _page(int page) => page < 1 ? 1 : page;

  /// הקישור ש-Windows מעביר לתוכנה כארגומנט `BOOK=`.
  @visibleForTesting
  static String windowsBookLink(int bookId, int tabId, {int page = 1}) =>
      'OtzarBook://book/$bookId/p/${_page(page)}/t/$tabId/fs/0/start/0/end/0 /c';

  /// סורק את הכוננים המעוגנים במק אחרי `<כונן>/books/<id>.book`.
  static Future<bool> _checkBookExistenceMac(int bookId) async {
    for (final mountRoot in _macMountRoots) {
      final root = Directory(mountRoot);
      if (!await root.exists()) continue;
      try {
        await for (final entry in root.list(followLinks: false)) {
          if (entry is! Directory) continue;
          for (final relative in const ['books', 'Otzardisk/books']) {
            final file = File(path.join(entry.path, relative, '$bookId.book'));
            if (await file.exists()) return true;
          }
        }
      } on FileSystemException {
        // כונן בלי הרשאת קריאה — ממשיכים לבא.
        continue;
      }
    }
    debugPrint('Book $bookId not found in any mounted Otzar disk');
    return false;
  }

  static Future<bool> checkBookExistence(int bookId) async {
    if (Platform.isMacOS) return _checkBookExistenceMac(bookId);
    if (!Platform.isWindows) return false;
    for (final drive in _availableDrives) {
      //newer version teh path is under the /books folder with the extension .book
      final bookPath = '$drive:\\books\\$bookId.book';
      final bookFile = File(bookPath);
      if (await bookFile.exists()) {
        return true;
      }
      //newer version teh path is under the /Otzardisk/books folder with the extension .book
      final bookPathLocalDisk = '$drive:\\Otzardisk\\books\\$bookId.book';
      final bookFileLocalDisk = File(bookPathLocalDisk);
      if (await bookFileLocalDisk.exists()) {
        return true;
      }

      final zipPath = '$drive:\\zip';

      try {
        final zipDir = Directory(zipPath);
        if (await zipDir.exists()) {
          final bookPath = '$zipPath\\$bookId.ocd';
          final bookFile = File(bookPath);
          if (await bookFile.exists()) {
            return true;
          }
        }
      } catch (e) {
        // Continue to the next possible drive  if there's an error
        continue;
      }
    }
    debugPrint('Book $bookId not found in any "<drive>" <book> folder');
    return false;
  }

  static Future<(String, bool)> findOtzarExePath() async {
    final String? otzarPath = Platform.environment['OTZARAPPCD'];
    if (otzarPath != null) {
      final String exePath = '$otzarPath\\otzar.exe';
      if (await File(exePath).exists()) {
        return (exePath, true); // true indicates version 18 and above
      }
    }

    // Check for older versions
    const String oldPath = 'C:\\OTZAR\\otzar.exe';
    if (await File(oldPath).exists()) {
      return (oldPath, false); // false indicates version < 18
    }

    return ('', false); // Not found
  }

  static Future<bool> canLaunchLocally() async {
    // במק אין נתיב ל-exe: ההפעלה עוברת דרך מטפל הפרוטוקול `OtzarBook://`
    // שההתקנה רושמת, ולכן קיומו של מטפל רשום הוא התנאי.
    if (Platform.isMacOS) {
      return canLaunchUrlString(macBookUri(1, tabId: 0));
    }
    if (!Platform.isWindows) return false;
    final (exePath, _) = await findOtzarExePath();
    return exePath.isNotEmpty;
  }

  /// With [preferMainWindow] on modern Windows and default page=1, F1
  /// selects the book in the running app; it does NOT force page 1. Set false
  /// for the existing page-aware BOOK= route. macOS and legacy Windows retain
  /// their existing behavior.
  /// [page] — מספר העמוד לפתיחה (מבוסס-1; ברירת מחדל: הראשון). בגרסאות ישנות של
  /// התוכנה (לפני 18) נפתח הספר מתחילתו.
  static Future<void> launchOtzarLocal(
    int bookId, {
    int page = 1,
    bool preferMainWindow = true,
  }) async {
    if (Platform.isMacOS) {
      if (!await launchUrlString(macBookUri(bookId, page: page))) {
        throw Exception('Failed to launch Otzar: no handler for OtzarBook://');
      }
      return;
    }
    final (exePath, isVersion18OrAbove) = await findOtzarExePath();
    if (exePath.isEmpty) {
      throw Exception('Otzar.exe not found');
    }

    // F1 selects a book, not a page. Keep explicit page requests on the
    // existing BOOK= route. In the default catalog case, Otzar must already be
    // running and may restore the book's last-read page.
    if (isVersion18OrAbove && preferMainWindow && _page(page) == 1) {
      await OtzarMainWindowInput.openBook(bookId);
      return;
    }

    final tabId = Random().nextInt(1000000); // Random tab ID
    final String bookLink = windowsBookLink(bookId, tabId, page: page);
    List<String> arguments = isVersion18OrAbove ? ['BOOK=$bookLink'] : [];

    final workingDir = path.dirname(exePath);

    try {
      if (isVersion18OrAbove) {
        // Try running with full path
        final result = await Process.run(
          exePath,
          arguments,
          workingDirectory: workingDir,
        );

        if (result.exitCode != 0) {
          // If failed, try running through cmd
          final cmdResult = await Process.run(
            'cmd',
            ['/c', 'start', '', exePath, ...arguments],
            workingDirectory: workingDir,
          );

          if (cmdResult.exitCode != 0) {
            throw Exception(
              'otzar.exe exited with non-zero code: ${cmdResult.exitCode}\nError: ${cmdResult.stderr}',
            );
          }
        }
      } else {
        Process.run(exePath, []);

        if (await checkBookExistence(bookId)) {
          await Future.delayed(
            const Duration(seconds: 5),
            () => Process.run(
              "c:\\OTZAR\\view.exe",
              ['$bookId', 'DtnOzrV'],
            ),
          );
        } else {
          throw Exception('Book $bookId not found in any /zip folder');
        }
      }
    } catch (e) {
      throw Exception('Failed to launch Otzar: $e');
    }
  }

  /// פותח בתוכנת אוצר החכמה כשהיא מותקנת והספר על הכונן, אחרת באתר.
  ///
  /// [page] — העמוד לפתיחה בתוכנה (מבוסס-1; ברירת מחדל: הראשון). באתר נפתח הספר כולו.
  static Future<bool> openBook(
    int? bookId,
    String link, {
    int page = 1,
    bool preferMainWindow = true,
  }) async {
    if (bookId != null &&
        await canLaunchLocally() &&
        await checkBookExistence(bookId)) {
      // לא ממתינים: בגרסאות ישנות Process.run חוזר רק כשהתוכנה נסגרת.
      unawaited(
        launchOtzarLocal(
          bookId,
          page: page,
          preferMainWindow: preferMainWindow,
        ).catchError((_) => launchOtzarWeb(link)),
      );
      return true;
    }
    return launchOtzarWeb(link);
  }

  static Future<bool> launchOtzarWeb(String url) async {
    return await canLaunchUrlString(url) && await launchUrlString(url);
  }
}
