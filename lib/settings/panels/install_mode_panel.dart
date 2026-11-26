import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/windowing/app_quit.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/update/install_mode_switch.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// כרטיס "התקנה": לאילו משתמשים אוצריא מותקנת, והעברה להיקף האחר דרך
/// המתקין (forum/topic/3173). מוצג רק בהתקנת Windows שאינה ניידת.
class InstallModePanel extends StatefulWidget {
  const InstallModePanel({super.key, this.switcher, this.quit});

  /// ברירת המחדל: [InstallModeSwitcher.forCurrentProcess].
  final InstallModeSwitcher? switcher;

  /// ברירת המחדל: יציאה מכל החלונות, כמו בהתקנת עדכון.
  final Future<void> Function()? quit;

  @override
  State<InstallModePanel> createState() => _InstallModePanelState();
}

class _InstallModePanelState extends State<InstallModePanel> {
  late final InstallModeSwitcher? _switcher =
      widget.switcher ?? InstallModeSwitcher.forCurrentProcess();
  bool _busy = false;

  Future<void> _switch(InstallModeSwitcher switcher) async {
    final toAllUsers = switcher.otherScope == WindowsInstallScope.allUsers;
    final confirmed = await showTwoActionsDialog(
      context: context,
      title: toAllUsers
          ? context.settingsText('העברת אוצריא לכל המשתמשים')
          : context.settingsText('העברת אוצריא למשתמש הנוכחי בלבד'),
      content: toAllUsers
          ? context.settingsText(
              'אוצריא תיסגר וייפתח המתקין. הוא יבקש אישור מנהל, יתקין את אוצריא לכל המשתמשים במחשב ויסיר את ההתקנה הקודמת. ההגדרות, הספרים וההערות נשארים במקומם.',
            )
          : context.settingsText(
              'אוצריא תיסגר וייפתח המתקין. הוא יתקין את אוצריא רק למשתמש הנוכחי ויסיר, באישור מנהל, את ההתקנה לכל המשתמשים — שאר המשתמשים במחשב לא יוכלו לפתוח אותה. ההגדרות, הספרים וההערות נשארים במקומם.',
            ),
      confirmText: context.settingsText('המשך'),
    );
    if (confirmed != true || !mounted) return;
    final quit =
        widget.quit ??
        (() => AppQuit.quitAll(
          AppQuitReason.update,
          window: AppWindowScope.controllerOf(context),
        ));
    setState(() => _busy = true);
    var launched = false;
    try {
      launched = await switcher.switchTo(switcher.otherScope, quit: quit);
    } catch (_) {
      // הורדה שנכשלה מדווחת כמו שיגור שנכשל.
    }
    if (!launched) UiSnack.showError(SettingsMessages.installModeSwitchFailed);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final switcher = _switcher;
    if (switcher == null) return const SizedBox.shrink();
    final isAllUsers = switcher.currentScope == WindowsInstallScope.allUsers;
    return SettingsCard(
      cardId: 'system.installMode',
      title: context.settingsText('התקנה'),
      subtitle: context.settingsText('למי במחשב הזה אוצריא מותקנת'),
      children: [
        SettingsActionTile.text(
          key: const ValueKey('install-mode-switch'),
          icon: FluentIcons.people_24_regular,
          title: context.settingsText('סוג ההתקנה'),
          subtitle: isAllUsers
              ? context.settingsText('מותקנת לכל המשתמשים במחשב')
              : context.settingsText('מותקנת רק למשתמש הנוכחי'),
          actions: [
            ActionButton.neutral(
              text: isAllUsers
                  ? context.settingsText('העברה למשתמש הנוכחי בלבד')
                  : context.settingsText('העברה לכל המשתמשים'),
              isLoading: _busy,
              onPressed: _busy ? null : () => _switch(switcher),
            ),
          ],
        ),
      ],
    );
  }
}
