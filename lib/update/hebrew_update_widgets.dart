import 'dart:io';
import 'package:otzaria/theme/app_tokens.dart';

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/windowing/app_quit.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'install_mode_switch.dart';
import 'updat_compat.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:otzaria/widgets/controls/status_chip.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';

/// רכיב לחיצה (chip) בעברית - דומה ל-flatChip המקורי
Widget hebrewFlatChip({
  required BuildContext context,
  required String? latestVersion,
  required String appVersion,
  required UpdatStatus status,
  required void Function() checkForUpdate,
  required void Function() openDialog,
  required void Function() startUpdate,
  required Future<void> Function() launchInstaller,
  required void Function() dismissUpdate,
  bool awaitingClose = false,
}) {
  // אחרי האישור התהליך עוד חי כי חלון כלשהו לא נסגר — המעדכן כבר ממתין לו.
  if (awaitingClose) {
    return StatusChip(
      tooltip: LibraryMessages.smallUpdateAwaitingCloseMessage,
      onPressed: null,
      icon: const Icon(FluentIcons.hourglass_24_regular),
      label: LibraryMessages.smallUpdateAwaitingCloseChip,
    );
  }

  if (UpdatStatus.available == status ||
      UpdatStatus.availableWithChangelog == status) {
    // בדוק אם הדיאלוג כבר הוצג לגרסה זו
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final shownKey = 'update_dialog_shown_$latestVersion';
      final alreadyShown = Settings.getValue<bool>(shownKey) ?? false;

      if (!alreadyShown && context.mounted) {
        // סמן שהדיאלוג הוצג לגרסה זו
        await Settings.setValue<bool>(shownKey, true);
        openDialog();
      }
    });
    return StatusChip(
      tooltip: 'עדכון לגרסה ${latestVersion!.toString()}',
      onPressed: openDialog,
      icon: const Icon(FluentIcons.arrow_download_24_regular),
      label: 'עדכון זמין',
    );
  }

  if (UpdatStatus.downloading == status) {
    return StatusChip.busy(
      tooltip: 'אנא המתן...',
      icon: SizedBox(
        width: 15,
        height: 15,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
      label: 'מוריד...',
    );
  }

  if (UpdatStatus.readyToInstall == status) {
    // ההסבר המלא יושב כאן ולא בחלון קופץ: ברגע ה"מוכן" אין מה להפריע
    // למשתמש, והלחיצה ממילא פותחת את אותו נוסח בדיאלוג.
    return StatusChip(
      tooltip: Platform.isWindows
          ? LibraryMessages.smallUpdateDialogContent
          : 'לחץ להתקנה',
      onPressed: launchInstaller,
      icon: const Icon(FluentIcons.checkmark_circle_24_regular),
      label: 'מוכן להתקנה',
    );
  }

  if (UpdatStatus.error == status) {
    return Container();
  }

  return Container();
}

/// דיאלוג ברירת מחדל בעברית - דומה ל-defaultDialog
void hebrewDefaultDialog({
  required BuildContext context,
  required String? latestVersion,
  required String appVersion,
  required UpdatStatus status,
  required String? changelog,
  required void Function() checkForUpdate,
  required void Function() openDialog,
  required void Function() startUpdate,
  required Future<void> Function() launchInstaller,
  required void Function() dismissUpdate,
  InstallModeSwitcher? installModeSwitcher,
}) {
  final changelogText = changelog?.trim() ?? '';
  // התקנה בהיקף האחר (forum/topic/3173): המתקין המלא של הגרסה החדשה רץ במצב
  // ההחלפה במקום העדכון הרגיל.
  final switcher =
      installModeSwitcher ?? InstallModeSwitcher.forCurrentProcess();
  var switchScope = false;

  showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AppDialog.twoActions(
        title: 'עדכון זמין',
        icon: FluentIcons.arrow_sync_24_regular,
        size: AppDialogSize.small,
        cancelText: 'מאוחר יותר',
        confirmText: 'עדכן כעת',
        customContent: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('גרסה חדשה של האפליקציה זמינה.'),
                const SizedBox(height: AppTokens.spaceXS),
                Text('גרסה חדשה: ${latestVersion!.toString()}'),
                if (status == UpdatStatus.availableWithChangelog) ...[
                  const SizedBox(height: AppTokens.spaceMD),
                  Text(
                    'יומן שינויים:',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceSM),
                  changelogText.isEmpty
                      ? const Text('לא נמצאו פריטי יומן שינויים לעדכון זה.')
                      : MarkdownBody(
                          data: changelogText,
                          onTapLink: (text, href, title) {
                            if (href != null) launchUrl(Uri.parse(href));
                          },
                        ),
                ],
                if (switcher != null)
                  StatefulBuilder(
                    builder: (context, setState) => CheckboxListTile(
                      key: const ValueKey('update-switch-install-mode'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: switchScope,
                      onChanged: (value) =>
                          setState(() => switchScope = value ?? false),
                      title: Text(
                        switcher.otherScope == WindowsInstallScope.allUsers
                            ? 'התקנת העדכון לכל המשתמשים במחשב'
                            : 'התקנת העדכון רק למשתמש הנוכחי',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  ).then((confirmed) async {
    if (confirmed != true) return;
    if (switcher == null || !switchScope) return startUpdate();
    if (!context.mounted) return;
    var launched = false;
    try {
      launched = await switcher.switchTo(
        switcher.otherScope,
        quit: () => AppQuit.quitAll(
          AppQuitReason.update,
          window: AppWindowScope.controllerOf(context),
        ),
      );
    } catch (_) {
      // הורדה שנכשלה מדווחת כמו שיגור שנכשל.
    }
    if (!launched) {
      UiSnack.showError(LibraryMessages.updateInstallerLaunchError);
    }
  });
}
