import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';

/// אזהרה כש-Windows מתוזמן למחוק בהפעלה הבאה קבצים מנתוני אוצריא: הסרה שנתקלה
/// בקבצים נעולים מוחקת כך את ההתקנה החדשה שבאותם נתיבים (issue #2611).
class PendingRebootDeleteWarning {
  static bool _shown = false;

  @visibleForTesting
  static void debugReset() => _shown = false;

  /// ערך `PendingFileRenameOperations` כמו שהוא: זוגות מקור/יעד מופרדים ב-NUL.
  @visibleForTesting
  static Future<String> Function() readOperations = () async =>
      Platform.isWindows ? Isolate.run(_readRegistry) : '';

  /// קריאה גולמית: פענוח REG_MULTI_SZ רגיל נעצר ביעד הריק הראשון.
  static String _readRegistry() => using((arena) {
    final key = arena.pcwstr(
      r'SYSTEM\CurrentControlSet\Control\Session Manager',
    );
    final name = arena.pcwstr('PendingFileRenameOperations');
    final size = arena<DWORD>();
    WIN32_ERROR query(Pointer? data) => RegGetValue(
      HKEY_LOCAL_MACHINE,
      key,
      name,
      RRF_RT_REG_MULTI_SZ,
      null,
      data,
      size,
    );
    if (query(null) != ERROR_SUCCESS) return '';
    final data = arena<Uint16>(size.value ~/ 2 + 1);
    if (query(data) != ERROR_SUCCESS) return '';
    return String.fromCharCodes(data.asTypedList(size.value ~/ 2));
  });

  static bool _within(String root, String path) =>
      p.windows.equals(root, path) || p.windows.isWithin(root, path);

  /// מקורות הפעולות שיוציאו קובץ מאחת מ-[roots]: מחיקה (יעד ריק), או העברה
  /// אל מחוץ להן. הפיצול שומר את היעדים הריקים, אחרת הזוגות זזים.
  static List<String> scheduledRemovals(String raw, List<String> roots) {
    final operations = raw.split('\x00');
    String clean(String entry) => entry.split('\\??\\').last;
    bool inside(String path) =>
        path.isNotEmpty && roots.any((root) => _within(root, path));
    return [
      for (var i = 0; i + 1 < operations.length; i += 2)
        if (inside(clean(operations[i])) && !inside(clean(operations[i + 1])))
          clean(operations[i]),
    ];
  }

  static Future<void> showIfNeeded() async {
    if (_shown || WindowRole.isSecondary) return;
    final raw = await readOperations();
    if (raw.isEmpty) return;
    final backups = await AppPaths.getBackupPath();
    final roots = [
      await AppPaths.getDataRootPath(),
      await AppPaths.getDatabasesPath(),
      backups,
    ];
    final removals = scheduledRemovals(raw, roots);
    final context = navigatorKey.currentContext;
    if (removals.isEmpty || context == null || !context.mounted) return;
    _shown = true;
    final folders = roots.where((r) => removals.any((f) => _within(r, f)));
    final content = [
      context.settingsText(
        'בהפעלה הבאה של המחשב Windows ימחק קבצים מנתוני אוצריא (סך הכול '
        '{count}), כנראה שארית של הסרה קודמת של התוכנה. ההגדרות, ההערות '
        'והתוספים שבתיקיות האלה יאבדו:\n{folders}\n\nגבה עכשיו, ואחרי '
        'ההפעלה מחדש שחזר את הגיבוי בהגדרות ← מערכת. לביטול המחיקה עצמה '
        'נדרש מנהל מערכת שיסיר את הרישומים של אוצריא מהערך '
        'PendingFileRenameOperations.',
        // LRI/PDI: נתיב עם שם תיקייה עברי מתהפך בתוך פסקה מימין לשמאל.
        args: {
          'count': removals.length,
          'folders': folders.map((f) => '\u2066$f\u2069').join('\n'),
        },
      ),
      // הגיבוי נשמר בתיקיית הגיבויים, ולכן אינו בטוח כשגם היא ברשימה.
      if (removals.any((f) => _within(backups, f) || _within(f, backups)))
        context.settingsText(
          'גם תיקיית הגיבויים ברשימה: העתק את הגיבוי למקום אחר לפני ההפעלה מחדש.',
        ),
    ].join('\n\n');
    final backupNow = await showTwoActionsDialog(
      context: context,
      title: context.settingsText(
        'Windows ימחק את נתוני אוצריא בהפעלה הבאה של המחשב',
      ),
      content: content,
      cancelText: context.settingsText('סגור'),
      confirmText: context.settingsText('גבה עכשיו'),
    );
    if (backupNow != true) return;
    try {
      final result = await BackupService.createBackup(
        includeSettings: true,
        includeBookmarks: true,
        includeHistory: true,
        includeNotes: true,
        includeWorkspaces: true,
        includeShamorZachor: true,
        includePlugins: true,
      );
      final size =
          '${(await File(result.path).length() / 1024).toStringAsFixed(1)} KB';
      UiSnack.show(
        result.skippedSections.isEmpty
            ? SettingsMessages.backupSaved(size)
            : SettingsMessages.partialBackupSaved(
                size,
                result.skippedSections.join(', '),
              ),
      );
    } catch (e) {
      UiSnack.showError(SettingsMessages.backupCreateError(e));
    }
  }
}
