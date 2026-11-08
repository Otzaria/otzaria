import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';

import 'package:otzaria/core/app_runtime_reset.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/windowing/app_quit.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// מסלול השחזור (החלפה) המשותף למסך ההגדרות ולהודעת העלייה: אישור, שחזור,
/// משוב וטעינה מחדש של האפליקציה.
class BackupRestoreFlow {
  @visibleForTesting
  static Future<void> Function(BuildContext context, String filePath)?
  debugRestoreOverride;

  /// "שחזור מהגיבוי האחרון" — הגיבוי החדש ביותר בתיקיית הגיבוי.
  static Future<void> restoreLatest(BuildContext context) async {
    final backups = await BackupService.getAvailableBackups();
    if (backups.isEmpty) {
      if (!context.mounted) return;
      UiSnack.showError(SettingsMessages.noBackupFileFound);
      return;
    }
    final filePath = backups.first.path;
    if (!context.mounted) return;

    final confirmed = await showWarningDialog(
      context: context,
      title: context.settingsText('שחזור מגיבוי?'),
      content: context.settingsText(
        'פעולה זו תחליף את הנתונים הקיימים בנתונים מקובץ הגיבוי העדכני ביותר שנמצא בתיקיית הגיבוי.',
      ),
      subtitle: context.settingsText('פעולה זו אינה הפיכה!'),
      cancelText: context.settingsText('ביטול'),
      confirmText: context.settingsText('שחזר'),
    );
    if (confirmed != true || !context.mounted) return;

    final override = debugRestoreOverride;
    if (override != null) return override(context, filePath);
    try {
      final result = await BackupService.restoreFromBackup(filePath);
      if (!context.mounted) return;
      await showResultAndRestart(context, result);
    } catch (e) {
      if (!context.mounted) return;
      UiSnack.showError(SettingsMessages.backupRestoreError(e));
    }
  }

  /// סיכום השחזור, ואחריו טעינה מחדש של האפליקציה.
  static Future<void> showResultAndRestart(
    BuildContext context,
    BackupRestoreResult result,
  ) async {
    final skipped = result.skippedSections;
    final missingFolders = result.missingCustomFolders;
    final isPartial =
        skipped.isNotEmpty ||
        missingFolders.isNotEmpty ||
        result.hasLegacyPartialSettings ||
        result.notesWithoutAnchor > 0 ||
        result.userBooksNotReplaced;
    final content = [
      if (skipped.isEmpty)
        context.settingsText('הנתונים שוחזרו בהצלחה.')
      else
        context.settingsText(
          'שחזור חלקי — חסרים בקובץ הגיבוי: {items}.',
          args: {'items': skipped.join(", ")},
        ),
      if (result.userBooksNotReplaced)
        context.settingsText(
          'הספרים האישיים לא שוחזרו: לא ניתן היה להחליף את הקובץ שלהם '
          '(ייתכן שהוא בשימוש). יש לשחזר שוב אחרי הפעלה מחדש של התוכנה.',
        ),
      if (result.hasLegacyPartialSettings)
        context.settingsText(
          'קובץ גיבוי זה נוצר בגרסה שגיבתה רק חלק מההגדרות, ולכן הגדרות '
          'שאינן בו לא שוחזרו — בהן קיצורי מקלדת, ברירות המחדל של החיפוש, '
          'התאמות צורת הדף והתאמות פר-ספר. יש לבדוק אם קיים גיבוי חדש יותר, '
          'או להגדיר אותן מחדש.',
        ),
      if (result.notesWithoutAnchor > 0)
        context.settingsText(
          'ב-{count} הערות קובץ הגיבוי אינו כולל את המילים שאליהן הן קושרו, '
          'ולכן הן מסומנות כעת על הקטע כולו. הקישור למילים נכנס לגיבוי '
          'בגרסה מאוחרת יותר.',
          args: {'count': result.notesWithoutAnchor},
        ),
      if (result.restoredPlugins > 0)
        context.settingsText(
          'התוספים שוחזרו מושבתים. יש להפעיל אותם בהגדרות ← ניהול כלים, '
          'ולתת מחדש גישה לתיקיות אם נדרשת.',
        ),
      if (missingFolders.isNotEmpty)
        context.settingsText(
          'תיקיות הספרים הבאות שוחזרו אך לא נמצאו במחשב זה:\n{folders}\n'
          'יש להוסיף אותן מחדש בהגדרות הספרייה, או לחברן לאותו נתיב.',
          args: {'folders': missingFolders.join('\n')},
        ),
      context.settingsText('האפליקציה תיטען מחדש כעת.'),
    ].join('\n\n');
    await showSingleActionDialog(
      context: context,
      title: context.settingsText(isPartial ? 'שחזור חלקי' : 'השחזור הושלם'),
      icon: FluentIcons.arrow_clockwise_24_regular,
      content: content,
      confirmText: context.settingsText('טען מחדש'),
    );
    if (!context.mounted) return;
    await resetRuntimeStateAfterSettingsReset();
    if (!context.mounted) return;
    AppQuit.restartAll(
      context,
      afterRestart: WebViewEnvironmentHolder.disposeForAppRestart,
    );
  }
}
