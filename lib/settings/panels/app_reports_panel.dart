import 'dart:convert';
import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/app_report/models/app_report.dart';
import 'package:otzaria/app_report/repository/app_report_redactor.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/app_report/services/crash_report_decision.dart';
import 'package:otzaria/app_report/view/app_report_dialog.dart';
import 'package:otzaria/app_report/view/app_report_result_snack.dart';
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/services/offline_send_target.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/utils/file/save_file_with_extension.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// כרטיס "דיווחים על התוכנה" במסך ההגדרות: פתיחת הטופס, מצב הדיווח אחרי
/// קריסה, וניהול התור וההיסטוריה — באותו מבנה כמו דיווחי הטעויות והתוספים.
class AppReportsPanel extends StatefulWidget {
  const AppReportsPanel({
    super.key,
    required this.isOfflineMode,
    required this.crashReportMode,
    required this.onCrashReportModeChanged,
    this.service,
  });

  final bool isOfflineMode;
  final AppCrashReportMode crashReportMode;
  final ValueChanged<AppCrashReportMode> onCrashReportModeChanged;
  final AppReportService? service;

  @override
  State<AppReportsPanel> createState() => _AppReportsPanelState();
}

class _AppReportsPanelState extends State<AppReportsPanel> {
  late final AppReportService _service = widget.service ?? AppReportService();

  bool _isFlushing = false;
  bool _isClearingPending = false;
  bool _isExporting = false;
  bool _isClearingSent = false;
  bool _isPendingExpanded = false;
  bool _isSentExpanded = false;
  String? _sendingReportId;

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      cardId: 'system.appReports',
      title: context.settingsText('דיווחים על התוכנה'),
      subtitle: context.settingsText(
        'דיווח על תקלות בתוכנה עצמה. הדיווח נפתח כדיווח ציבורי ב-GitHub, וקובצי האבחון גלויים למפתחי אוצריא בלבד.',
      ),
      children: [
        SettingsActionTile.text(
          icon: FluentIcons.bug_24_regular,
          title: context.settingsText('דווח על תקלה בתוכנה'),
          subtitle: context.settingsText(
            'תקלה, קריסה, בעיית ביצועים או הצעה לשיפור',
          ),
          actions: [
            ActionButton.recommended(
              key: const ValueKey('app-reports-open-dialog'),
              text: context.settingsText('פתח טופס דיווח'),
              onPressed: () => showAppReportDialog(
                context,
                dialogBuilder: settingsDialogBuilder,
              ).then((_) => _refresh()),
            ),
          ],
        ),
        SettingsActionTile.segmentedTile<AppCrashReportMode>(
          icon: FluentIcons.warning_24_regular,
          title: context.settingsText('דיווח אחרי סגירה לא צפויה'),
          subtitle: context.settingsText(
            'מה לעשות כשהתוכנה מזהה שנסגרה בלי סגירה מסודרת',
          ),
          options: [
            SegmentOption(
              value: AppCrashReportMode.ask,
              label: context.settingsText('שאל אותי'),
            ),
            SegmentOption(
              value: AppCrashReportMode.always,
              label: context.settingsText('שלח אוטומטית'),
            ),
            SegmentOption(
              value: AppCrashReportMode.never,
              label: context.settingsText('לעולם לא'),
            ),
          ],
          currentValue: widget.crashReportMode,
          onChanged: widget.onCrashReportModeChanged,
        ),
        FutureBuilder<List<AppReport>>(
          future: _service.getPendingReports(),
          builder: (context, snapshot) {
            final pending = snapshot.data ?? const <AppReport>[];
            final hasReports = pending.isNotEmpty;
            return ExpandableSection(
              icon: OtzariaIcons.task_list_24_regular,
              title: context.settingsText('ניהול דיווחים שמורים'),
              subtitle: pending.isEmpty
                  ? context.settingsText('אין כרגע דיווחים שמורים בתור')
                  : context.settingsText(
                      'יש כרגע {count} דיווחים שמורים בתור',
                      args: {'count': pending.length},
                    ),
              hasContent: hasReports,
              onTap: () =>
                  setState(() => _isPendingExpanded = !_isPendingExpanded),
              isExpanded: _isPendingExpanded,
              children: [
                if (hasReports) _buildPendingToolbar(context, hasReports),
                if (widget.isOfflineMode && hasReports)
                  Padding(
                    padding: const EdgeInsets.only(
                      right: 16,
                      left: 16,
                      bottom: 16,
                    ),
                    child: Text(
                      context.settingsText(
                        'במצב מנותק אי אפשר לשלוח כעת, אך ניתן להוריד סקריפט לשליחה ממחשב מחובר.',
                      ),
                      style: kSettingsSubtitleStyle,
                    ),
                  ),
                ...pending.map((report) => _buildPendingTile(context, report)),
              ],
            );
          },
        ),
        FutureBuilder<(List<AppReport>, int)>(
          future: (
            _service.getSentReports(),
            _service.getSentReportsTotal(),
          ).wait,
          builder: (context, snapshot) {
            final sent = snapshot.data?.$1 ?? const <AppReport>[];
            return ExpandableSection(
              icon: FluentIcons.checkmark_circle_24_regular,
              title: context.settingsText('דיווחים שנשלחו'),
              hasContent: sent.isNotEmpty,
              subtitle: _sentSubtitle(
                context,
                shown: sent.length,
                total: snapshot.data?.$2 ?? 0,
              ),
              onTap: () => setState(() => _isSentExpanded = !_isSentExpanded),
              isExpanded: _isSentExpanded,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    right: 16,
                    left: 16,
                    bottom: 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _managed(
                          enabled: sent.isNotEmpty,
                          child: ActionButton.neutral(
                            text: context.settingsText('נקה את כל ההיסטוריה'),
                            icon: FluentIcons.delete_24_regular,
                            onPressed: _clearSent,
                            isLoading: _isClearingSent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ...sent.map((report) => _buildSentTile(context, report)),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildPendingToolbar(BuildContext context, bool hasReports) {
    return Padding(
      padding: const EdgeInsets.only(right: 16, left: 16, top: 8, bottom: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < LayoutBreakpoints.compact;
          final send = _managed(
            enabled: !widget.isOfflineMode,
            child: ActionButton.recommended(
              text: context.settingsText('שלח עכשיו'),
              icon: FluentIcons.arrow_sync_24_regular,
              onPressed: _flush,
              isLoading: _isFlushing,
            ),
          );
          final clear = _managed(
            enabled: hasReports,
            child: ActionButton.neutral(
              text: context.settingsText('נקה דיווחים'),
              icon: FluentIcons.delete_24_regular,
              onPressed: _clearPending,
              isLoading: _isClearingPending,
            ),
          );
          final export = _managed(
            enabled: hasReports,
            child: ActionButton.neutral(
              text: context.settingsText('הורד לשליחה במחשב מחובר'),
              icon: FluentIcons.arrow_download_24_regular,
              onPressed: _exportScript,
              isLoading: _isExporting,
            ),
          );
          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                send,
                const SizedBox(height: 8),
                clear,
                const SizedBox(height: 8),
                export,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: send),
              const SizedBox(width: 12),
              Expanded(child: clear),
              const SizedBox(width: 12),
              Expanded(child: export),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPendingTile(BuildContext context, AppReport report) {
    final isSending = _sendingReportId == report.reportId;
    return Column(
      children: [
        ListTile(
          leading: const Icon(FluentIcons.bug_24_regular),
          title: Text(report.title, style: kSettingsTitleStyle),
          subtitle: Text(
            _summaryLine(context, report),
            style: kSettingsSubtitleStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _actions(
          children: [
            ActionButton.neutral(
              text: context.settingsText('צפה'),
              icon: FluentIcons.eye_24_regular,
              onPressed: () => _showDetails(report, sent: false),
            ),
            ActionButton.neutral(
              text: context.settingsText('ערוך'),
              icon: FluentIcons.edit_24_regular,
              onPressed: () => _editPending(report),
            ),
            ActionButton.neutral(
              text: context.settingsText('מחק'),
              icon: FluentIcons.delete_24_regular,
              onPressed: () => _deletePending(report),
            ),
            _managed(
              enabled: !widget.isOfflineMode,
              child: ActionButton.recommended(
                text: context.settingsText('שלח'),
                icon: FluentIcons.send_24_regular,
                isLoading: isSending,
                onPressed: () => _sendPending(report),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSentTile(BuildContext context, AppReport report) {
    final issueUrl = report.issueUrl;
    return Column(
      children: [
        ListTile(
          leading: const Icon(FluentIcons.checkmark_24_regular),
          title: Text(report.title, style: kSettingsTitleStyle),
          subtitle: Text(
            _summaryLine(context, report),
            style: kSettingsSubtitleStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _actions(
          children: [
            ActionButton.neutral(
              text: context.settingsText('צפה'),
              icon: FluentIcons.eye_24_regular,
              onPressed: () => _showDetails(report, sent: true),
            ),
            if (issueUrl != null && issueUrl.isNotEmpty)
              ActionButton.neutral(
                key: ValueKey('app-report-open-issue-${report.reportId}'),
                text: report.issueNumber == null
                    ? context.settingsText('פתח ב-GitHub')
                    : context.settingsText(
                        'פתח דיווח #{number}',
                        args: {'number': report.issueNumber},
                      ),
                icon: FluentIcons.open_24_regular,
                onPressed: () => _openIssue(issueUrl),
              ),
            ActionButton.neutral(
              text: context.settingsText('מחק'),
              icon: FluentIcons.delete_24_regular,
              onPressed: () => _deleteSent(report),
            ),
          ],
        ),
      ],
    );
  }

  Widget _actions({required List<Widget> children}) {
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

  Widget _managed({required bool enabled, required Widget child}) {
    return IgnorePointer(
      ignoring: !enabled,
      child: Opacity(opacity: enabled ? 1 : 0.45, child: child),
    );
  }

  String _summaryLine(BuildContext context, AppReport report) {
    final date = report.sentAt ?? report.createdAt;
    final local = date.toLocal();
    final parts = [
      _typeLabel(context, report.type),
      '${local.day}.${local.month}.${local.year}',
      if (report.issueNumber != null) '#${report.issueNumber}',
      if (report.merged) context.settingsText('צורף לדיווח קיים'),
    ];
    return parts.join(' · ');
  }

  String _typeLabel(BuildContext context, AppReportType type) => switch (type) {
    AppReportType.bug => context.settingsText('תקלה'),
    AppReportType.crash => context.settingsText('קריסה'),
    AppReportType.performance => context.settingsText('ביצועים'),
    AppReportType.suggestion => context.settingsText('הצעה'),
  };

  String _sentSubtitle(
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

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _showDetails(AppReport report, {required bool sent}) async {
    final buffer = StringBuffer()
      ..writeln(_summaryLine(context, report))
      ..writeln();
    if (report.description.trim().isNotEmpty) {
      buffer.writeln(report.description.trim());
    }
    if (report.stepsToReproduce.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(context.settingsText('שלבים לשחזור:'))
        ..writeln(report.stepsToReproduce.trim());
    }
    final signature = report.signature;
    if (signature != null && signature.exceptionType.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(signature.exceptionType)
        ..writeln(signature.frames.join('\n'));
    }
    await showSingleActionDialog(
      context: context,
      title: context.settingsText(
        sent ? 'פרטי דיווח שנשלח' : 'פרטי דיווח שמור',
      ),
      content: buffer.toString().trimRight(),
      confirmText: context.settingsText('סגור'),
    );
  }

  Future<void> _openIssue(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !await launchUrl(uri)) {
      UiSnack.showError(ReportMessages.appReportCannotOpenIssue);
    }
  }

  Future<void> _flush() async {
    setState(() => _isFlushing = true);
    final pendingBefore = await _service.getPendingReportsCount();
    final sentCount = await _service.flushPendingReports();
    final pendingAfter = await _service.getPendingReportsCount();
    if (!mounted) return;
    setState(() => _isFlushing = false);
    if (sentCount > 0) {
      UiSnack.showSuccess(ReportMessages.pendingFlushed(sentCount));
    } else if (pendingBefore == 0) {
      UiSnack.show(ReportMessages.noPendingToSend);
    } else {
      UiSnack.show(ReportMessages.pendingFlushFailed(pendingAfter));
    }
  }

  Future<void> _sendPending(AppReport report) async {
    setState(() => _sendingReportId = report.reportId);
    AppReportDeliveryResult? result;
    try {
      result = await _service.submitPendingReport(report);
    } catch (e) {
      if (mounted) UiSnack.showError(ReportMessages.sendError(e));
    } finally {
      if (mounted) setState(() => _sendingReportId = null);
    }
    if (result != null) showAppReportResultSnack(result);
  }

  Future<void> _editPending(AppReport report) async {
    var edited = report;
    final confirmed = await showTwoActionsDialog(
      context: context,
      title: context.settingsText('עריכת דיווח שמור'),
      content: '',
      cancelText: context.settingsText('ביטול'),
      confirmText: context.settingsText('שמור'),
      handleEnterKey: false,
      customContent: SizedBox(
        width: 560,
        child: AppReportEditFields(
          report: report,
          typeLabel: (type) => _typeLabel(context, type),
          onChanged: (value) => edited = value,
        ),
      ),
    );
    if (confirmed != true) return;

    // טקסט שהוקלד בעריכה עובר אותה הסתרה כמו בטופס המקורי.
    final redacted = edited.redactedWith(AppReportRedactor.fromPlatform());
    final invalidField = redacted.validate();
    if (invalidField != null) {
      UiSnack.showError(
        appReportInvalidFieldMessage(
          invalidField,
          emailEmpty: redacted.reporterEmail.trim().isEmpty,
        ),
      );
      return;
    }

    await _service.updatePendingReport(redacted);
    if (!mounted) return;
    setState(() {});
    UiSnack.showSuccess(ReportMessages.reportUpdated);
  }

  Future<void> _deletePending(AppReport report) async {
    await _service.deletePendingReport(report.reportId);
    if (!mounted) return;
    setState(() {});
    UiSnack.show(ReportMessages.removedFromQueue);
  }

  Future<void> _deleteSent(AppReport report) async {
    await _service.deleteSentReport(report.reportId);
    if (!mounted) return;
    setState(() {});
    UiSnack.show(ReportMessages.deletedFromHistory);
  }

  Future<void> _clearPending() async {
    final confirmed = await showWarningDialog(
      context: context,
      title: context.settingsText('למחוק דיווחים שמורים?'),
      content: context.settingsText('כל הדיווחים השמורים בתור יימחקו מהמחשב.'),
      subtitle: context.settingsText('לא ניתן לשחזר דיווחים שנמחקו.'),
      cancelText: context.settingsText('ביטול'),
      confirmText: context.settingsText('מחק'),
    );
    if (confirmed != true) return;
    setState(() => _isClearingPending = true);
    await _service.clearPendingReports();
    if (!mounted) return;
    setState(() => _isClearingPending = false);
    UiSnack.show(ReportMessages.pendingCleared);
  }

  Future<void> _clearSent() async {
    final confirmed = await showWarningDialog(
      context: context,
      title: context.settingsText('לנקות את היסטוריית הדיווחים?'),
      content: context.settingsText(
        'כל הדיווחים שנשלחו יימחקו מההיסטוריה המקומית.',
      ),
      subtitle: context.settingsText(
        'הפעולה לא מוחקת דיווחים שכבר נשלחו לצוות אוצריא.',
      ),
      cancelText: context.settingsText('ביטול'),
      confirmText: context.settingsText('נקה'),
    );
    if (confirmed != true) return;
    setState(() => _isClearingSent = true);
    await _service.clearSentReports();
    if (!mounted) return;
    setState(() => _isClearingSent = false);
    UiSnack.show(ReportMessages.historyCleared);
  }

  Future<void> _exportScript() async {
    if (!await verifySaferModePassword(context)) return;
    final reports = await _service.getPendingReports();
    if (reports.isEmpty) {
      if (mounted) UiSnack.show(ReportMessages.noPendingToExport);
      return;
    }
    if (!mounted) return;
    final target = await resolveOfflineSendTarget(context);
    if (target == null || !mounted) return;

    final script = _service.buildOfflineSendScript(reports, target: target);
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
    if (path == null || !mounted) return;

    setState(() => _isExporting = true);
    try {
      if (target == OfflineSendScriptTarget.unix &&
          (Platform.isLinux || Platform.isMacOS)) {
        await Process.run('chmod', ['+x', path]);
      }
      if (!mounted) return;
      UiSnack.showSuccess(
        target == OfflineSendScriptTarget.unix
            ? ReportMessages.scriptSavedUnix(script.fileName)
            : ReportMessages.scriptSavedWindows,
      );
    } catch (e) {
      if (mounted) UiSnack.showError(ReportMessages.scriptSaveError(e));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }
}

/// שדות העריכה של דיווח תוכנה שמור בתור; מדווח על כל שינוי כדיווח מעודכן.
@visibleForTesting
class AppReportEditFields extends StatefulWidget {
  const AppReportEditFields({
    super.key,
    required this.report,
    required this.typeLabel,
    required this.onChanged,
  });

  final AppReport report;
  final String Function(AppReportType type) typeLabel;
  final ValueChanged<AppReport> onChanged;

  @override
  State<AppReportEditFields> createState() => _AppReportEditFieldsState();
}

class _AppReportEditFieldsState extends State<AppReportEditFields> {
  late AppReportType _type = widget.report.type;
  late final _title = TextEditingController(text: widget.report.title);
  late final _description = TextEditingController(
    text: widget.report.description,
  );
  late final _steps = TextEditingController(
    text: widget.report.stepsToReproduce,
  );
  late final _email = TextEditingController(text: widget.report.reporterEmail);

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _steps.dispose();
    _email.dispose();
    super.dispose();
  }

  void _notifyChanged() => widget.onChanged(
    widget.report.copyWith(
      type: _type,
      title: _title.text,
      description: _description.text,
      stepsToReproduce: _steps.text,
      reporterEmail: _email.text.trim(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final emailRequired = widget.report.trigger.requiresEmail;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSegmentedControl<AppReportType>(
          expandToFillWidth: true,
          options: [
            for (final type in AppReportType.values)
              SegmentOption(value: type, label: widget.typeLabel(type)),
          ],
          currentValue: _type,
          onChanged: (type) {
            setState(() => _type = type);
            _notifyChanged();
          },
        ),
        const SizedBox(height: 12),
        RtlTextField(
          key: const ValueKey('app-report-edit-title'),
          controller: _title,
          onChanged: (_) => _notifyChanged(),
          decoration: InputDecoration(
            labelText: context.settingsText('כותרת'),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        RtlTextField(
          key: const ValueKey('app-report-edit-description'),
          controller: _description,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          minLines: 3,
          maxLines: 6,
          onChanged: (_) => _notifyChanged(),
          decoration: InputDecoration(
            labelText: context.settingsText('תיאור'),
            alignLabelWithHint: true,
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        RtlTextField(
          key: const ValueKey('app-report-edit-steps'),
          controller: _steps,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          minLines: 2,
          maxLines: 5,
          onChanged: (_) => _notifyChanged(),
          decoration: InputDecoration(
            labelText: context.settingsText('שלבים לשחזור (לא חובה)'),
            alignLabelWithHint: true,
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        Directionality(
          textDirection: TextDirection.ltr,
          child: RtlTextField(
            key: const ValueKey('app-report-edit-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => _notifyChanged(),
            decoration: InputDecoration(
              labelText: emailRequired
                  ? context.settingsText('דואר אלקטרוני')
                  : context.settingsText('דואר אלקטרוני (לא חובה)'),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }
}
