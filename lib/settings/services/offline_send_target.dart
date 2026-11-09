import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:otzaria/services/offline_report_script_builder.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';

/// לאיזו מערכת הפעלה לבנות את סקריפט השליחה של הדיווחים השמורים.
/// ב-Windows אין שאלה; במחשב אחר שואלים; במובייל מסבירים שהקובץ ל-Windows.
Future<OfflineSendScriptTarget?> resolveOfflineSendTarget(
  BuildContext context,
) async {
  if (Platform.isWindows) {
    return OfflineSendScriptTarget.windows;
  }

  if (Platform.isMacOS || Platform.isLinux) {
    return showSelectionDialog<OfflineSendScriptTarget>(
      context: context,
      title: context.settingsText('מערכת ההפעלה של המחשב המחובר'),
      icon: FluentIcons.desktop_24_regular,
      searchHint: context.settingsText('חיפוש מערכת הפעלה...'),
      items: const [
        SelectionItem(label: 'Windows', value: OfflineSendScriptTarget.windows),
        SelectionItem(
          label: 'Linux / macOS',
          value: OfflineSendScriptTarget.unix,
        ),
      ],
    );
  }

  final proceed = await showTwoActionsDialog(
    context: context,
    title: context.settingsText('הקובץ מיועד למחשב Windows'),
    icon: FluentIcons.desktop_24_regular,
    content: context.settingsText(
      'במכשיר זה אי אפשר להריץ את סקריפט השליחה. יורד קובץ עבור '
      'מחשב Windows מחובר — העבירו אליו את הקובץ והפעילו אותו שם.',
    ),
    cancelText: context.settingsText('ביטול'),
    confirmText: context.settingsText('המשך'),
  );
  if (proceed != true) {
    return null;
  }
  return OfflineSendScriptTarget.windows;
}
