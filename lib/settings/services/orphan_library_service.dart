import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:otzaria/core/app_paths.dart';
import 'package:path/path.dart' as p;

/// עותק ספרייה יתום שנשאר בנתיב המערכתי הישן, והנפח שהוא תופס.
class OrphanLibraryInfo {
  final String path;
  final int sizeBytes;

  const OrphanLibraryInfo({required this.path, required this.sizeBytes});
}

/// זיהוי ומחיקה של עותק ספרייה יתום ב-`ProgramData\otzaria` — שארית ממעבר
/// מהתקנת מנהל להתקנת משתמש, שתופסת גיגה-בייטים בלי חיווי.
abstract class OrphanLibraryService {
  /// מזהה עותק ספרייה יתום בנתיב המערכתי הישן ב-Windows.
  ///
  /// מחזיר null כשאין עותק כזה, או כשלא בטוח להציע מחיקה: התקנה מערכתית או
  /// ניידת, התקנת מנהל אחרת שקיימת במחשב, או נתיב פעיל שיושב תחת התיקייה.
  static Future<OrphanLibraryInfo?> detect() async {
    if (!Platform.isWindows || AppPaths.isPortable) return null;
    if (await AppPaths.detectInstallMode() != InstallMode.perUser) return null;
    // התקנת מנהל במחשב (גם של משתמש אחר) עשויה להשתמש ב-ProgramData באופן
    // פעיל — גם כשהותקנה בנתיב מותאם, ולכן הזיהוי דרך רישומי ההסרה.
    if (await machineWideInstallRegistered()) return null;
    if (_programFilesInstallExists()) return null;

    final programData =
        Platform.environment['ProgramData'] ?? r'C:\ProgramData';
    return evaluateCandidate(
      candidateRoot: p.join(programData, 'otzaria'),
      activePaths: [
        await AppPaths.getLibraryPath(),
        await AppPaths.getIndexPath(),
        await AppPaths.getDatabasesPath(),
      ],
    );
  }

  /// ליבת הזיהוי: [candidateRoot] נחשב יתום רק כשקיימת בו תיקיית `books`
  /// לא-ריקה ואף נתיב מ-[activePaths] אינו יושב בתוכו.
  @visibleForTesting
  static Future<OrphanLibraryInfo?> evaluateCandidate({
    required String candidateRoot,
    required List<String> activePaths,
  }) async {
    final root = p.normalize(candidateRoot);
    if (!await Directory(root).exists()) return null;

    for (final path in activePaths) {
      if (path.isEmpty) continue;
      final normalized = p.normalize(path);
      if (p.equals(normalized, root) || p.isWithin(root, normalized)) {
        return null;
      }
    }

    final books = Directory(p.join(root, 'books'));
    if (!await books.exists()) return null;
    if (await books.list().isEmpty) return null;

    return OrphanLibraryInfo(path: root, sizeBytes: await _directorySize(root));
  }

  /// מוחק את העותק היתום. מאמת מחדש שהוא עדיין יתום לפני המחיקה — הגנה מפני
  /// נתיב פעיל שהשתנה בין הזיהוי ללחיצה.
  static Future<void> delete(
    OrphanLibraryInfo info, {
    @visibleForTesting Future<OrphanLibraryInfo?> Function()? redetect,
  }) async {
    final current = await (redetect ?? detect)();
    if (current == null || !p.equals(current.path, info.path)) {
      throw StateError('העותק אינו מזוהה עוד כיתום — המחיקה בוטלה');
    }
    await Directory(info.path).delete(recursive: true);
  }

  /// AppId של המתקין — רשומת ההסרה ב-HKLM נכתבת רק בהתקנת מנהל
  /// (CreateUninstallRegKey), ולכן קיומה שם מעיד על התקנה מערכתית בכל נתיב.
  static const String _installerUninstallKey =
      r'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
      r'\{EEC4F712-CD05-4D15-A753-509E840A51A5}_is1';

  /// Process.run חוסם את ה-thread הקורא ב-Windows; לכן רץ ב-isolate עזר.
  @visibleForTesting
  static Future<bool> machineWideInstallRegistered() =>
      Isolate.run(_queryUninstallKey);

  static Future<bool> _queryUninstallKey() async {
    for (final view in const ['/reg:64', '/reg:32']) {
      try {
        final result = await Process.run('reg', [
          'query',
          'HKLM\\$_installerUninstallKey',
          view,
        ], runInShell: false);
        if (result.exitCode == 0) return true;
      } catch (_) {}
    }
    return false;
  }

  /// רשת ביטחון לרישום שנוקה ידנית: ה-EXE בנתיב ברירת המחדל של התקנת מנהל.
  static bool _programFilesInstallExists() {
    final roots = [
      Platform.environment['ProgramFiles'] ?? r'C:\Program Files',
      Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)',
    ];
    return roots.any(
      (root) => File(p.join(root, 'Otzaria', 'otzaria.exe')).existsSync(),
    );
  }

  static Future<int> _directorySize(String path) async {
    var total = 0;
    await for (final entity in Directory(
      path,
    ).list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }

  /// עיצוב נפח לתצוגה: GB מעל ג'יגה, אחרת MB.
  static String formatBytes(int bytes) {
    const gb = 1024 * 1024 * 1024;
    const mb = 1024 * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
    return '${(bytes / mb).toStringAsFixed(1)} MB';
  }
}
