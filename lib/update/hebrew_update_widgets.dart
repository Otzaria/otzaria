import 'dart:io';
import 'package:otzaria/theme/app_tokens.dart';

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/messages/library_messages.dart';
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
  bool awaitingClose = false,
}) {
  // אחרי האישור התהליך עוד חי כי חלון כלשהו לא נסגר — המעדכן כבר ממתין לו.
  if (awaitingClose) {
    return Tooltip(
      message: LibraryMessages.smallUpdateAwaitingCloseMessage,
      child: _updateChipSurface(
        context,
        TextButton.icon(
          onPressed: null,
          style: _updateChipButtonStyle(context),
          icon: const Icon(FluentIcons.hourglass_24_regular),
          label: const Text(LibraryMessages.smallUpdateAwaitingCloseChip),
        ),
      ),
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
    // ההסבר המלא יושב כאן ולא בחלון קופץ: ברגע ה"מוכן" אין מה להפריע
    // למשתמש, והלחיצה ממילא פותחת את אותו נוסח בדיאלוג.
    return Tooltip(
      message: Platform.isWindows
          ? LibraryMessages.smallUpdateDialogContent
          : 'לחץ להתקנה',
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
