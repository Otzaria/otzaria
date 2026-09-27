import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// המתקין והעברת ספרייה מוחקים את הקטלוג, ובלעדיו בנייה מחדש ממספרת מחדש
/// את הספרים וכל סימנייה והיסטוריה מצביעות על ספר אחר.
class ResponsaCatalogBackup {
  ResponsaCatalogBackup._();

  /// תת-התיקייה בתוך תיקיית הגיבויים.
  static const String folderName = 'responsa';

  /// מחזיר `true` רק כשהקטלוג שוחזר. כל כשל נבלע: העותק הוא רשת ביטחון,
  /// ואסור שיפיל את טעינת הספרים.
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
        if (!await _same(catalog, backup)) {
          await _copy(catalog, backup, replace: true);
        }
        return false;
      }
      if (!await backup.exists() || !await _canRestoreInto(catalog)) {
        return false;
      }
      if (!await _copy(backup, catalog, replace: false)) return false;
      debugPrint('ResponsaCatalogBackup: הקטלוג שוחזר מ-${backup.path}');
      return true;
    } catch (error) {
      debugPrint('ResponsaCatalogBackup: $error');
      return false;
    }
  }

  /// [_copy] מעתיק גם את זמן השינוי כדי ששחזור לא יגרור העתקה הפוכה.
  /// סבולת של שתי שניות - הרזולוציה של FAT בכונן נשלף.
  static Future<bool> _same(File a, File b) async {
    if (!await b.exists()) return false;
    final (sa, sb) = (await a.stat(), await b.stat());
    return sa.size == sb.size &&
        sa.modified.difference(sb.modified).inSeconds.abs() < 2;
  }

  /// תיקייה חסרה היא ספרייה שנמחקה - אין ליצור אותה. `.building`/`.previous`
  /// הם הרגע שבין שני שינויי השם של הבנייה, שבו הקטלוג חסר זמנית.
  static Future<bool> _canRestoreInto(File catalog) async =>
      await catalog.parent.exists() &&
      !await File('${catalog.path}.building').exists() &&
      !await File('${catalog.path}.previous').exists();

  /// קובץ צדדי ושינוי שם, כדי שקורא לא יראה קובץ חלקי. בלי [replace] שחזור
  /// אינו דורס קטלוג שבנייה כתבה באותו רגע.
  static Future<bool> _copy(File from, File to, {required bool replace}) async {
    if (replace) await to.parent.create(recursive: true);
    final temporary = File('${to.path}.copying');
    await from.copy(temporary.path);
    await temporary.setLastModified(await from.lastModified());
    if (await to.exists()) {
      if (!replace) {
        await temporary.delete();
        return false;
      }
      await to.delete();
    }
    await temporary.rename(to.path);
    return true;
  }
}
