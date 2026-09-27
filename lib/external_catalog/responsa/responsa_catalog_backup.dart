import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// עותק ביטחון של קטלוג בר אילן, מחוץ לתיקיית הספרייה.
///
/// הקטלוג יושב בתיקיית הספרייה (ראה `ResponsaPaths`), ושתי פעולות מוחקות
/// אותו בלי לדעת עליו: המתקין המלא מחליף את תיקיית הספרייה כולה, והורדה
/// או ייבוא של ספרייה למיקום חדש מוחקים את הקבצים המנוהלים מהמיקום הישן.
///
/// בנייה מחדש אורכת כשש דקות ומצריכה את בר אילן פתוח, אבל זה המחיר הקטן.
/// המזהים של הספרים נשמרים בין בניות רק מפני שהבנייה קוראת את הקטלוג
/// הקודם (`assignExternalKeys`). בלעדיו הם ממוספרים מחדש, וכל סימנייה
/// והיסטוריה של ספר בר אילן מצביעות אחר כך על ספר אחר.
///
/// העותק יושב בתיקיית הגיבויים של אוצריא, שנבחרה כך שהסרה והתקנה אינן
/// נוגעות בה.
class ResponsaCatalogBackup {
  ResponsaCatalogBackup._();

  /// תת-התיקייה בתוך תיקיית הגיבויים.
  static const String folderName = 'responsa';

  /// מיישר בין הקטלוג לעותק.
  ///
  /// קטלוג קיים — העותק מתעדכן כשהוא חסר או שונה. קטלוג חסר — הוא משוחזר
  /// מהעותק. מחזיר `true` רק כשהקטלוג שוחזר.
  ///
  /// כל כשל נבלע: העותק הוא רשת ביטחון, ואסור שכשל בו יפיל את טעינת
  /// הספרים.
  static Future<bool> sync({
    required String catalogPath,
    required String backupDirectory,
  }) async {
    final catalog = File(catalogPath);
    final backup = File(
      path.join(backupDirectory, folderName, path.basename(catalogPath)),
    );
    try {
      if (await catalog.exists()) {
        if (!await _same(catalog, backup)) await _copy(catalog, backup);
        return false;
      }
      if (!await backup.exists()) return false;
      await _copy(backup, catalog);
      debugPrint('ResponsaCatalogBackup: הקטלוג שוחזר מ-${backup.path}');
      return true;
    } catch (error) {
      debugPrint('ResponsaCatalogBackup: $error');
      return false;
    }
  }

  /// אותו גודל ואותו זמן שינוי. [_copy] מעתיק גם את זמן השינוי, ולכן
  /// שחזור אינו גורר העתקה חוזרת בכיוון ההפוך. בסבולת של שתי שניות — FAT
  /// שומר זמן שינוי ברזולוציה כזו, וכונן נשלף הוא מקום סביר לספרייה.
  static Future<bool> _same(File a, File b) async {
    if (!await b.exists()) return false;
    final (sa, sb) = (await a.stat(), await b.stat());
    return sa.size == sb.size &&
        sa.modified.difference(sb.modified).inSeconds.abs() < 2;
  }

  /// העתקה לקובץ צדדי והחלפה, כדי שקורא לעולם לא יראה קובץ חלקי.
  static Future<void> _copy(File from, File to) async {
    await to.parent.create(recursive: true);
    final temporary = File('${to.path}.copying');
    await from.copy(temporary.path);
    await temporary.setLastModified(await from.lastModified());
    if (await to.exists()) await to.delete();
    await temporary.rename(to.path);
  }
}
