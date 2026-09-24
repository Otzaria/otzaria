import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_chm.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation.dart';
import 'package:otzaria/external_catalog/responsa/text/responsa_bibliography.dart';
import 'package:path/path.dart' as path;

/// איתור "רשימת הספרים והמהדורות" בתוך ההתקנה, וקריאתה.
///
/// **החיפוש מבני ולא לפי נתיב קבוע.** ב-CD25 הקובץ הוא
/// `HELP/Respheb.chm`, אבל שם התיקייה, שם הקובץ ומספר קובצי העזרה
/// משתנים בין מהדורות. לכן נסרקים קובצי ה-CHM שבהתקנה, והעברי — זה
/// שהשמות בו תואמים לעץ — נבדק ראשון.
class ResponsaBibliographyReader {
  ResponsaBibliographyReader._();

  /// עד כמה עמוק לחפש קובצי עזרה מתחת לתיקיית ההתקנה.
  ///
  /// רמה אחת: ההתקנה עצמה ותיקיות הבת שלה. סריקה עמוקה יותר הייתה עוברת
  /// על `DB`, שהוא 10GB.
  static const int _maxDepth = 1;

  /// קובץ עזרה שבשמו מופיע הסימן הזה נבדק ראשון.
  static const String _hebrewHint = 'heb';

  /// קורא את הביבליוגרפיה של [installation].
  ///
  /// החיפוש עובר על אותם שורשים שהתוכנה עצמה פותרת מהם את הנתונים —
  /// תיקיית ההרצה, `Sh_hdisk`, אתר הנתונים ו-`Sh_cdrom` — כי בהתקנה
  /// חלקית חלק מהקבצים נשארים על ההתקן הנשלף.
  ///
  /// מחזיר [ResponsaBibliography.empty] כשאין קובץ עזרה, כשאין בו תיקיית
  /// ביבליוגרפיה, או כשהקריאה נכשלה. אף אחד מאלה אינו שגיאה שמצדיקה
  /// עצירת בנייה: הקטלוג שלם גם בלי מטא-דאטה, פשוט בלי שם מחבר ובלי
  /// פרטי הדפסה.
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
      // כל הקובץ, ולא תיקייה בשם ידוע: שם התיקייה משתנה בין מהדורות,
      // ו-[ResponsaBibliography.onlyBibliographyFolder] מאתר אותה לפי
      // המבנה.
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

  /// סורק תיקייה אחת ויורד לתיקיות הבת עד [_maxDepth].
  ///
  /// **עוקב אחרי קישורים.** התקנה שנייה על אותו מחשב נבנית לעיתים
  /// כתיקייה שבה `HELP` ו-`DB` הם קישורים לתיקיות של ההתקנה הראשית —
  /// זה בדיוק מה שמאפשר שתי גרסאות בלי לשכפל 10GB. בלי מעקב, `HELP`
  /// חוזר כ-[Link] ולא כ-[Directory], קובץ העזרה אינו נמצא, והקטלוג
  /// נבנה בלי שם מחבר ובלי פרטי הדפסה — בלי שום סימן למשתמש.
  ///
  /// מעגל קישורים אינו מסוכן כאן: העומק חסום ב-[_maxDepth] ממילא.
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
