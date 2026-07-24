import 'dart:io';
import 'package:otzaria/theme/app_tokens.dart';

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:updat/updat.dart';
import 'package:url_launcher/url_launcher.dart';

/// עוטף את צ'יפ העדכון בצבע פעולה בולט, בלי לצאת מצבעי התמה.
Widget _updateChipSurface(BuildContext context, Widget child) {
  final colorScheme = Theme.of(context).colorScheme;
  return Material(
    color: colorScheme.primaryContainer,
    shape: RoundedRectangleBorder(
      borderRadius: AppTokens.borderRadiusAll,
      side: BorderSide(color: colorScheme.primary, width: 1.2),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

ButtonStyle _updateChipButtonStyle(BuildContext context) {
  final theme = Theme.of(context);
  return TextButton.styleFrom(
    foregroundColor: theme.colorScheme.onPrimaryContainer,
    textStyle: theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
    ),
    minimumSize: const Size(0, 32),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

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
}) {
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
    return Tooltip(
      message: 'עדכון לגרסה ${latestVersion!.toString()}',
      child: _updateChipSurface(
        context,
        TextButton.icon(
          onPressed: openDialog,
          style: _updateChipButtonStyle(context),
          icon: const Icon(FluentIcons.arrow_download_24_regular),
          label: const Text('עדכון זמין'),
        ),
      ),
    );
  }

  if (UpdatStatus.downloading == status) {
    return Tooltip(
      message: 'אנא המתן...',
      child: _updateChipSurface(
        context,
        TextButton.icon(
          onPressed: () {},
          style: _updateChipButtonStyle(context),
          icon: SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          label: const Text('מוריד...'),
        ),
      ),
    );
  }

  if (UpdatStatus.readyToInstall == status) {
    // ב-Windows העדכון מותקן ברקע (מתקין שקט) והתוכנה נפתחת מחדש לבד —
    return Tooltip(
      message: Platform.isWindows ? 'לחץ לעדכון' : 'לחץ להתקנה',
      child: _updateChipSurface(
        context,
        TextButton.icon(
          onPressed: launchInstaller,
          style: _updateChipButtonStyle(context),
          icon: const Icon(FluentIcons.checkmark_circle_24_regular),
          label: const Text('מוכן להתקנה'),
        ),
      ),
    );
  }

  if (UpdatStatus.error == status) {
    return Container();
  }

  return Container();
}

/// רכיב לחיצה מורחב בעברית עם הורדה שקטה - דומה ל-floatingExtendedChipWithSilentDownload
Widget hebrewFloatingExtendedChipWithSilentDownload({
  required BuildContext context,
  required String? latestVersion,
  required String appVersion,
  required UpdatStatus status,
  required void Function() checkForUpdate,
  required void Function() openDialog,
  required void Function() startUpdate,
  required Future<void> Function() launchInstaller,
  required void Function() dismissUpdate,
}) {
  if (UpdatStatus.available == status ||
      UpdatStatus.availableWithChangelog == status) {
    startUpdate();
  }

  if (UpdatStatus.downloading == status) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "מוריד עדכון...",
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              "מוריד גרסה ${latestVersion.toString()}",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 15),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text("אנא המתן..."),
              ],
            ),
          ],
        ),
      ),
    );
  }

  if (UpdatStatus.readyToInstall == status) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "עדכון מוכן",
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              "גרסה ${latestVersion.toString()} מוכנה להתקנה!",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              "אתה משתמש כרגע בגרסה $appVersion.",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              "עדכן כעת כדי לקבל את התכונות והתיקונים החדשים.",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: dismissUpdate,
                  child: const Text('מאוחר יותר'),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: startUpdate,
                  icon: const Icon(FluentIcons.desktop_arrow_down_24_regular),
                  label: const Text('התקן כעת'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
}) {
  final changelogText = changelog?.trim() ?? '';

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: Flex(
        direction: Theme.of(context).useMaterial3
            ? Axis.vertical
            : Axis.horizontal,
        children: const [
          Icon(FluentIcons.arrow_sync_24_regular),
          Text('עדכון זמין'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('גרסה חדשה של האפליקציה זמינה.'),
          const SizedBox(width: 10),
          Text('גרסה חדשה: ${latestVersion!.toString()}'),
          const SizedBox(height: 10),
          if (status == UpdatStatus.availableWithChangelog) ...[
            Text(
              'יומן שינויים:',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: changelogText.isEmpty
                  ? const Text('לא נמצאו פריטי יומן שינויים לעדכון זה.')
                  : MarkdownBody(
                      data: changelogText,
                      onTapLink: (text, href, title) {
                        if (href != null) launchUrl(Uri.parse(href));
                      },
                    ),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('מאוחר יותר'),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            startUpdate();
          },
          child: const Text('עדכן כעת'),
        ),
      ],
    ),
  );
}

/// פונקציה שעוטפת את _flatChipAutoHideError אבל עם הרכיב העברי
Widget hebrewFlatChipAutoHideError({
  required BuildContext context,
  required String? latestVersion,
  required String appVersion,
  required UpdatStatus status,
  required void Function() checkForUpdate,
  required void Function() openDialog,
  required void Function() startUpdate,
  required Future<void> Function() launchInstaller,
  required void Function() dismissUpdate,
}) {
  if (status == UpdatStatus.error) {
    Future.delayed(const Duration(seconds: 3), dismissUpdate);
  }
  return hebrewFlatChip(
    context: context,
    latestVersion: latestVersion,
    appVersion: appVersion,
    status: status,
    checkForUpdate: checkForUpdate,
    openDialog: openDialog,
    startUpdate: startUpdate,
    launchInstaller: launchInstaller,
    dismissUpdate: dismissUpdate,
  );
}
