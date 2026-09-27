import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_chm.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_bibliography.dart';
import 'package:path/path.dart' as path;

/// איתור "רשימת הספרים והמהדורות" בהתקנה. החיפוש מבני ולא לפי נתיב קבוע,
/// כי שמות קובצי העזרה משתנים בין מהדורות; העברי נבדק ראשון.
class ResponsaBibliographyReader {
  ResponsaBibliographyReader._();

  /// רק ההתקנה ותיקיות הבת שלה - סריקה עמוקה יותר תעבור על `DB` (10GB).
  static const int _maxDepth = 1;

  /// קובץ עזרה שבשמו מופיע הסימן הזה נבדק ראשון.
  static const String _hebrewHint = 'heb';

  /// עובר על כל השורשים שהתוכנה עצמה פותרת מהם נתונים, כי בהתקנה חלקית
  /// חלק מהקבצים נשארים על ההתקן הנשלף. כישלון אינו עוצר בנייה.
  static ResponsaBibliography forInstallation(
    ResponsaInstallation installation,
  ) {
    final settings = installation.iniSettings;
    return forRoots([
      installation.installPath,
      settings['sh_hdisk'],
      installation.dataLocation,
      settings['sh_cdrom'],
    ]);
  }

  /// קורא את הביבליוגרפיה מתוך התיקיות שב-[roots], לפי סדר.
  @visibleForTesting
  static ResponsaBibliography forRoots(Iterable<String?> roots) {
    final seen = <String>{};
    final files = <String>[];
    for (final root in roots) {
      if (root == null || root.isEmpty) continue;
      for (final file in helpFiles(root)) {
        if (seen.add(file.toLowerCase())) files.add(file);
      }
    }
    for (final file in files) {
      // כל הקובץ ולא תיקייה בשם ידוע: השם משתנה בין מהדורות, והתיקייה
      // מאותרת לפי המבנה.
      final pages = ResponsaChm.read(file);
      if (pages.isEmpty) continue;
      final bibliography = ResponsaBibliography.parse(
        ResponsaBibliography.onlyBibliographyFolder(pages),
      );
      if (bibliography.isEmpty) continue;
      debugPrint(
        'ResponsaBibliography: ${bibliography.entryCount} entries '
        'from ${path.basename(file)}',
      );
      return bibliography;
    }
    return ResponsaBibliography.empty;
  }

  /// קובצי העזרה שבהתקנה, העברי ראשון.
  @visibleForTesting
  static List<String> helpFiles(String installPath) {
    final found = <String>[];
    _collect(Directory(installPath), 0, found);
    found.sort((a, b) {
      final rank = _rank(a).compareTo(_rank(b));
      return rank != 0 ? rank : a.compareTo(b);
    });
    return found;
  }

  static int _rank(String file) =>
      path.basename(file).toLowerCase().contains(_hebrewHint) ? 0 : 1;

  /// followLinks: בהתקנה שנייה `HELP` הוא לרוב קישור להתקנה הראשית, ובלי מעקב
  /// קובץ העזרה לא נמצא בשקט. מעגל קישורים חסום ממילא ב-[_maxDepth].
  static void _collect(Directory directory, int depth, List<String> into) {
    List<FileSystemEntity> entries;
    try {
      entries = directory.listSync(followLinks: true);
    } on FileSystemException {
      // תיקייה בלי הרשאת קריאה אינה סיבה לוותר על השאר.
      return;
    }
    for (final entry in entries) {
      if (entry is File) {
        if (path.extension(entry.path).toLowerCase() == '.chm') {
          into.add(entry.path);
        }
      } else if (entry is Directory && depth < _maxDepth) {
        _collect(entry, depth + 1, into);
      }
    }
  }
}
