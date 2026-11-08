import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/settings/dialogs/library_setup_dialog.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/widgets/feedback/app_info_banner.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// תוכן שמוצג באזור התוכן של LibraryBrowser כשאין ספרייה מוגדרת.
///
/// אינו Scaffold — הוא נכנס לתוך המסך הקיים (עם הסרגל העליון). מציג כפתור יחיד
/// שפותח את דיאלוג הגדרת המיקום ([showLibrarySetupDialog], המנהל bloc משלו).
/// [onLibraryLoaded] נקרא לאחר שהספרייה נבחרה/הורדה/יובאה בהצלחה.
class LibrarySetupView extends StatefulWidget {
  final Future<void> Function() onLibraryLoaded;

  /// סכמת מסד שנחסם כי הגרסה הזו אינה קוראת אותה; null — אין ספרייה.
  final int? unsupportedDbSchemaVersion;

  const LibrarySetupView({
    super.key,
    required this.onLibraryLoaded,
    this.unsupportedDbSchemaVersion,
  });

  @override
  State<LibrarySetupView> createState() => _LibrarySetupViewState();
}

class _LibrarySetupViewState extends State<LibrarySetupView> {
  String _defaultTargetPath = '';
  bool _sdLibraryWiped = false;

  @override
  void initState() {
    super.initState();
    // best-effort: כשל בזיהוי נתיב ברירת המחדל משאיר יעד ריק והמשתמש בוחר ידנית.
    AppPaths.getDefaultLibraryPath()
        .then((path) {
          if (mounted) {
            setState(() => _defaultTargetPath = AppPaths.libraryRootOf(path));
          }
        })
        .catchError((_) {});
    AppPaths.wasSdLibraryWiped()
        .then((wiped) {
          if (mounted && wiped) setState(() => _sdLibraryWiped = true);
        })
        .catchError((_) {});
  }

  Future<void> _handleLibraryLoaded() async {
    try {
      await widget.onLibraryLoaded();
    } catch (error) {
      UiSnack.showError(LibraryMessages.libraryLoadError);
      debugPrint('Failed to refresh library after selection: $error');
    }
  }

  Future<void> _openSetupDialog() async {
    if (!await verifySaferModePassword(context)) return;
    if (!mounted) return;
    final configured = await showLibrarySetupDialog(
      context: context,
      defaultTargetPath: _defaultTargetPath,
    );
    if (configured) await _handleLibraryLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final unsupportedSchema = widget.unsupportedDbSchemaVersion;
    return OtzariaEmptyState.large(
      icon: FluentIcons.library_24_regular,
      title: unsupportedSchema == null
          ? 'לא נמצאה ספריית ספרים'
          : 'ספריית הספרים חדשה מגרסת התוכנה',
      message: unsupportedSchema == null
          ? 'ניתן להוריד את הספרייה מהאינטרנט, להצביע על ספרייה קיימת\n'
                'שכבר יש במחשב, או לייבא אותה מהתיקייה שבה נמצאים קובצי הספרייה.'
          : 'הספרייה במחשב בפורמט מסד $unsupportedSchema, וגרסה זו של '
                'אוצריא קוראת עד פורמט '
                '${DatabaseConstants.readableDbSchemaVersion}.\n'
                'יש לעדכן את התוכנה לגרסה האחרונה, או לבחור ספרייה אחרת.',
      body: _sdLibraryWiped
          ? const AppInfoBanner(
              tone: AppInfoBannerTone.error,
              message:
                  'הספרייה שהייתה שמורה על כרטיס ה-SD נמחקה — ככל הנראה '
                  'בניקוי מטמון של המכשיר, שמוחק את תיקיית האפליקציה '
                  'שבכרטיס. כדי שזה לא יחזור, מומלץ להתקין את הספרייה '
                  'באחסון הפנימי.',
            )
          : null,
      actions: [
        ActionButton.recommended(
          text: 'בחר מיקום או הורד ספרייה',
          onPressed: _openSetupDialog,
          iconWidget: const Icon(FluentIcons.folder_add_24_regular),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
