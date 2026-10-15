import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/ui_snack.dart' show navigatorKey;
import 'package:otzaria/settings/l10n/settings_text.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:otzaria/settings/tabs/system_settings_tab.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';

/// הצעה לשחזר מגיבוי כשהמסדים האישיים נמחקו מבחוץ (issue #2610). בלעדיה
/// התוכנה יוצרת מסדים ריקים וממשיכה כאילו הותקנה זה עתה.
class PersonalDataMissingPrompt {
  static bool _pending = false;

  /// נקרא לפני פתיחת המסדים האישיים, שיוצרת אותם מחדש.
  static Future<void> detect() async {
    _pending = await AppPaths.personalDatabasesMissing().catchError(
      (_) => false,
    );
  }

  /// מוצג פעם אחת, אחרי שהחלון נחשף.
  static Future<void> showIfNeeded() async {
    final context = navigatorKey.currentContext;
    if (!_pending || context == null || !context.mounted) return;
    _pending = false;
    final restore = await showTwoActionsDialog(
      context: context,
      title: context.settingsText('הנתונים האישיים לא נמצאו'),
      content: context.settingsText(
        'הסימניות, ההערות, ההיסטוריה והכלים לא נמצאו בתיקיית הנתונים של '
        'התוכנה. אם יש גיבוי, אפשר לבחור אותו ולשחזר ממנו.',
      ),
      cancelText: context.settingsText('המשך בלי לשחזר'),
      confirmText: context.settingsText('שחזר מגיבוי'),
    );
    if (restore != true) return;
    final backups = await BackupService.getBackupDirectory();
    if (!context.mounted) return;
    await SystemSettingsTab.restoreFromPickedFile(
      context,
      initialDirectory: backups,
    );
  }
}
