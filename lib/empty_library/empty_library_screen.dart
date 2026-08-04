import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/dialogs/library_setup_dialog.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// תוכן שמוצג באזור התוכן של LibraryBrowser כשאין ספרייה מוגדרת.
///
/// אינו Scaffold — הוא נכנס לתוך המסך הקיים (עם הסרגל העליון). מציג כפתור יחיד
/// שפותח את דיאלוג הגדרת המיקום ([showLibrarySetupDialog], המנהל bloc משלו).
/// [onLibraryLoaded] נקרא לאחר שהספרייה נבחרה/הורדה/יובאה בהצלחה.
class LibrarySetupView extends StatefulWidget {
  final Future<void> Function() onLibraryLoaded;

  const LibrarySetupView({super.key, required this.onLibraryLoaded});

  @override
  State<LibrarySetupView> createState() => _LibrarySetupViewState();
}

class _LibrarySetupViewState extends State<LibrarySetupView> {
  String _defaultTargetPath = '';

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
  }

  Future<void> _handleLibraryLoaded() async {
    try {
      await widget.onLibraryLoaded();
    } catch (error) {
      UiSnack.showError('שגיאה בטעינת הספרייה. נסה שוב.');
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
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.library_24_regular,
              size: 64,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            const Text(
              'לא נמצאה ספריית ספרים',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'ניתן להוריד את הספרייה מהאינטרנט, או להצביע על ספרייה קיימת\n'
              'שכבר יש במחשב — וגם לייבא אותה מתיקייה או מקובץ דחוס.',
              style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ActionButton.recommended(
                text: 'בחר מיקום או הורד ספריה',
                onPressed: _openSetupDialog,
                iconWidget: const Icon(FluentIcons.folder_add_24_regular),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
