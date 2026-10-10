import 'dart:convert';
import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/services/offline_report_script_builder.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/services/offline_send_target.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/utils/file/save_file_with_extension.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:path_provider/path_provider.dart';

/// Pieces shared by the book, plugin and app report panels.

/// The action row under a saved or sent report.
Widget buildReportActions({required List<Widget> children}) {
  return Padding(
    padding: const EdgeInsets.only(right: 56, left: 16, bottom: 12),
    child: Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: children,
      ),
    ),
  );
}

/// Dims [child] and blocks taps on it while [enabled] is false.
Widget buildManagedActionButton({
  required bool enabled,
  required Widget child,
}) {
  return IgnorePointer(
    ignoring: !enabled,
    child: Opacity(opacity: enabled ? 1 : 0.45, child: child),
  );
}

/// The history keeps a fixed number of reports, so the total is shown apart.
String sentReportsSubtitle(
  BuildContext context, {
  required int shown,
  required int total,
}) {
  if (shown == 0) {
    return context.settingsText('עדיין אין דיווחים שנשלחו דרך המערכת');
  }
  if (total > shown) {
    return context.settingsText(
      'נשלחו {total} דיווחים, מוצגים {shown} האחרונים',
      args: {'total': total, 'shown': shown},
    );
  }
  return context.settingsText(
    'נשמרו {count} דיווחים שנשלחו',
    args: {'count': shown},
  );
}

/// A report row: an icon, a title, a two-line summary and its actions.
Widget _buildReportTile({
  required IconData icon,
  required String title,
  required String subtitle,
  required List<Widget> actions,
}) {
  return Column(
    children: [
      ListTile(
        leading: Icon(icon),
        title: Text(title, style: kSettingsTitleStyle),
        subtitle: Text(
          subtitle,
          style: kSettingsSubtitleStyle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      buildReportActions(children: actions),
    ],
  );
}

/// A report saved in the queue. [onMarkSent] adds the "mark as sent" action.
Widget buildPendingReportTile(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
  required bool canSend,
  required bool isSending,
  required VoidCallback onView,
  required VoidCallback onEdit,
  required VoidCallback onDelete,
  required VoidCallback onSend,
  VoidCallback? onMarkSent,
}) {
  return _buildReportTile(
    icon: icon,
    title: title,
    subtitle: subtitle,
    actions: [
      ActionButton.neutral(
        text: context.settingsText('צפה'),
        icon: FluentIcons.eye_24_regular,
        onPressed: onView,
      ),
      ActionButton.neutral(
        text: context.settingsText('ערוך'),
        icon: FluentIcons.edit_24_regular,
        onPressed: onEdit,
      ),
      ActionButton.neutral(
        text: context.settingsText('מחק'),
        icon: FluentIcons.delete_24_regular,
        onPressed: onDelete,
      ),
      if (onMarkSent != null)
        ActionButton.neutral(
          text: context.settingsText('סמן כנשלח'),
          icon: FluentIcons.checkmark_24_regular,
          onPressed: onMarkSent,
        ),
      buildManagedActionButton(
        enabled: canSend,
        child: ActionButton.recommended(
          text: context.settingsText('שלח'),
          icon: FluentIcons.send_24_regular,
          isLoading: isSending,
          onPressed: onSend,
        ),
      ),
    ],
  );
}

/// A report in the sent history; [extraAction] sits between view and delete.
Widget buildSentReportTile(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
  required VoidCallback onView,
  required VoidCallback onDelete,
  Widget? extraAction,
}) {
  return _buildReportTile(
    icon: icon,
    title: title,
    subtitle: subtitle,
    actions: [
      ActionButton.neutral(
        text: context.settingsText('צפה'),
        icon: FluentIcons.eye_24_regular,
        onPressed: onView,
      ),
      ?extraAction,
      ActionButton.neutral(
        text: context.settingsText('מחק'),
        icon: FluentIcons.delete_24_regular,
        onPressed: onDelete,
      ),
    ],
  );
}

/// Sends every queued report and tells how it went.
Future<void> flushReportQueue(
  BuildContext context, {
  required Future<int> Function() pendingCount,
  required Future<int> Function() flush,
  required ValueChanged<bool> setBusy,
  VoidCallback? onPendingReportsChanged,
}) async {
  setBusy(true);
  final pendingBefore = await pendingCount();
  final sentCount = await flush();
  final pendingAfter = await pendingCount();
  if (!context.mounted) return;
  onPendingReportsChanged?.call();
  setBusy(false);
  if (sentCount > 0) {
    UiSnack.showSuccess(ReportMessages.pendingFlushed(sentCount));
  } else if (pendingBefore == 0) {
    UiSnack.show(ReportMessages.noPendingToSend);
  } else {
    UiSnack.show(ReportMessages.pendingFlushFailed(pendingAfter));
  }
}

/// Deletes the whole queue after a confirmation.
Future<void> clearPendingReports(
  BuildContext context, {
  required Future<void> Function() clear,
  required ValueChanged<bool> setBusy,
  VoidCallback? onPendingReportsChanged,
}) async {
  final confirmed = await showWarningDialog(
    context: context,
    title: context.settingsText('למחוק דיווחים שמורים?'),
    content: context.settingsText('כל הדיווחים השמורים בתור יימחקו מהמחשב.'),
    subtitle: context.settingsText('לא ניתן לשחזר דיווחים שנמחקו.'),
    cancelText: context.settingsText('ביטול'),
    confirmText: context.settingsText('מחק'),
  );
  if (confirmed != true) return;
  setBusy(true);
  await clear();
  if (!context.mounted) return;
  onPendingReportsChanged?.call();
  setBusy(false);
  UiSnack.show(ReportMessages.pendingCleared);
}

/// Clears the local sent history after a confirmation; [subtitle] says
/// whom the reports already reached.
Future<void> clearSentReports(
  BuildContext context, {
  required String subtitle,
  required Future<void> Function() clear,
  required ValueChanged<bool> setBusy,
}) async {
  final confirmed = await showWarningDialog(
    context: context,
    title: context.settingsText('לנקות את היסטוריית הדיווחים?'),
    content: context.settingsText(
      'כל הדיווחים שנשלחו יימחקו מההיסטוריה המקומית.',
    ),
    subtitle: subtitle,
    cancelText: context.settingsText('ביטול'),
    confirmText: context.settingsText('נקה'),
  );
  if (confirmed != true) return;
  setBusy(true);
  await clear();
  if (!context.mounted) return;
  setBusy(false);
  UiSnack.show(ReportMessages.historyCleared);
}

/// Saves a script that sends the queued reports from another computer.
Future<void> exportOfflineSendScript<T>(
  BuildContext context, {
  required Future<List<T>> Function() loadPending,
  required OfflineSendScript Function(
    List<T> reports,
    OfflineSendScriptTarget target,
  )
  buildScript,
  required ValueChanged<bool> setBusy,
}) async {
  if (!await verifySaferModePassword(context)) return;
  final reports = await loadPending();
  if (reports.isEmpty) {
    if (context.mounted) UiSnack.show(ReportMessages.noPendingToExport);
    return;
  }
  if (!context.mounted) return;
  final target = await resolveOfflineSendTarget(context);
  if (target == null || !context.mounted) return;

  final script = buildScript(reports, target);
  final saveDialogTitle = context.settingsText(
    'בחר מיקום לשמירת סקריפט השליחה',
  );
  final downloadsDirectory = await getDownloadsDirectory();
  final path = await saveFileWithExtension(
    dialogTitle: saveDialogTitle,
    fileName: script.fileName,
    initialDirectory: downloadsDirectory?.path,
    extension: target == OfflineSendScriptTarget.windows ? 'bat' : 'sh',
    bytes: Uint8List.fromList(utf8.encode(script.content)),
  );
  if (path == null || !context.mounted) return;

  setBusy(true);
  try {
    // קובץ .sh נשמר ללא הרשאת הרצה; מוסיפים אותה כדי שאפשר יהיה להפעילו ישירות.
    if (target == OfflineSendScriptTarget.unix &&
        (Platform.isLinux || Platform.isMacOS)) {
      await Process.run('chmod', ['+x', path]);
    }
    if (!context.mounted) return;
    UiSnack.showSuccess(
      target == OfflineSendScriptTarget.unix
          ? ReportMessages.scriptSavedUnix(script.fileName)
          : ReportMessages.scriptSavedWindows,
    );
  } catch (e) {
    if (context.mounted) UiSnack.showError(ReportMessages.scriptSaveError(e));
  } finally {
    if (context.mounted) setBusy(false);
  }
}
