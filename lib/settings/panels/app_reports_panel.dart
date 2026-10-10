import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/app_report/models/app_report.dart';
import 'package:otzaria/app_report/repository/app_report_redactor.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/app_report/services/crash_report_decision.dart';
import 'package:otzaria/app_report/view/app_report_dialog.dart';
import 'package:otzaria/app_report/view/app_report_result_snack.dart';
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/panels/report_panel_widgets.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:url_launcher/url_launcher.dart';

/// דיווחים על התוכנה בחלון ניהול הדיווחים: פתיחת הטופס, מצב הדיווח אחרי
/// קריסה, וניהול התור וההיסטוריה — באותו מבנה כמו דיווחי הטעויות והתוספים.
class AppReportsPanel extends StatefulWidget {
  const AppReportsPanel({
    super.key,
    required this.isOfflineMode,
    required this.crashReportMode,
    required this.onCrashReportModeChanged,
    this.service,
    this.onPendingReportsChanged,
  });

  final bool isOfflineMode;
  final VoidCallback? onPendingReportsChanged;
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
    return AppCard.section(
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
              ).then(_refresh),
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
              subtitle: sentReportsSubtitle(
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
                        child: buildManagedActionButton(
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
          final send = buildManagedActionButton(
            enabled: !widget.isOfflineMode,
            child: ActionButton.recommended(
              text: context.settingsText('שלח עכשיו'),
              icon: FluentIcons.arrow_sync_24_regular,
              onPressed: _flush,
              isLoading: _isFlushing,
            ),
          );
          final clear = buildManagedActionButton(
            enabled: hasReports,
            child: ActionButton.neutral(
              text: context.settingsText('נקה דיווחים'),
              icon: FluentIcons.delete_24_regular,
              onPressed: _clearPending,
              isLoading: _isClearingPending,
            ),
          );
          final export = buildManagedActionButton(
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

  Widget _buildPendingTile(BuildContext context, AppReport report) =>
      buildPendingReportTile(
        context,
        icon: FluentIcons.bug_24_regular,
        title: report.title,
        subtitle: _summaryLine(context, report),
        canSend: !widget.isOfflineMode,
        isSending: _sendingReportId == report.reportId,
        onView: () => _showDetails(report, sent: false),
        onEdit: () => _editPending(report),
        onDelete: () => _deletePending(report),
        onMarkSent: () => _markPendingAsSent(report),
        onSend: () => _sendPending(report),
      );

  Widget _buildSentTile(BuildContext context, AppReport report) {
    final issueUrl = report.issueUrl;
    return buildSentReportTile(
      context,
      icon: FluentIcons.checkmark_24_regular,
      title: report.title,
      subtitle: _summaryLine(context, report),
      onView: () => _showDetails(report, sent: true),
      onDelete: () => _deleteSent(report),
      extraAction: issueUrl == null || issueUrl.isEmpty
          ? null
          : ActionButton.neutral(
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

  void _refresh(AppReportDeliveryResult? result) {
    if (!mounted) return;
    setState(() {});
    if (result != null) widget.onPendingReportsChanged?.call();
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

  Future<void> _flush() => flushReportQueue(
    context,
    pendingCount: _service.getPendingReportsCount,
    flush: _service.flushPendingReports,
    setBusy: (busy) => setState(() => _isFlushing = busy),
    onPendingReportsChanged: widget.onPendingReportsChanged,
  );

  Future<void> _sendPending(AppReport report) async {
    setState(() => _sendingReportId = report.reportId);
    AppReportDeliveryResult? result;
    try {
      result = await _service.submitPendingReport(report);
    } catch (e) {
      if (mounted) UiSnack.showError(ReportMessages.sendError(e));
    } finally {
      if (mounted) {
        setState(() => _sendingReportId = null);
        widget.onPendingReportsChanged?.call();
      }
    }
    if (result != null) showAppReportResultSnack(result);
  }

  Future<void> _editPending(AppReport report) async {
    var edited = report;
    final hasChanges = ValueNotifier(false);
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
          onChanged: (value) {
            edited = value;
            hasChanges.value =
                value.type != report.type ||
                value.title != report.title ||
                value.description != report.description ||
                value.stepsToReproduce != report.stepsToReproduce ||
                value.reporterEmail != report.reporterEmail;
          },
        ),
      ),
      hasUnsavedChanges: hasChanges,
    );
    hasChanges.dispose();
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
    widget.onPendingReportsChanged?.call();
    UiSnack.show(ReportMessages.removedFromQueue);
  }

  Future<void> _markPendingAsSent(AppReport report) async {
    final confirmed = await showTwoActionsDialog(
      context: context,
      title: context.settingsText('לסמן כנשלח?'),
      content: context.settingsText(
        'הדיווח יעבור להיסטוריית הדיווחים שנשלחו ויוסר מהתור, ללא שליחה לשרת. '
        'השתמשו בכך אם כבר שלחתם את הדיווח בדרך אחרת.',
      ),
      cancelText: context.settingsText('ביטול'),
      confirmText: context.settingsText('סמן כנשלח'),
    );
    if (confirmed != true) return;

    await _service.markPendingReportAsSent(report);
    if (!mounted) return;
    setState(() {});
    widget.onPendingReportsChanged?.call();
    UiSnack.show(ReportMessages.markedAsSent);
  }

  Future<void> _deleteSent(AppReport report) async {
    await _service.deleteSentReport(report.reportId);
    if (!mounted) return;
    setState(() {});
    UiSnack.show(ReportMessages.deletedFromHistory);
  }

  Future<void> _clearPending() => clearPendingReports(
    context,
    clear: _service.clearPendingReports,
    setBusy: (busy) => setState(() => _isClearingPending = busy),
    onPendingReportsChanged: widget.onPendingReportsChanged,
  );

  Future<void> _clearSent() => clearSentReports(
    context,
    subtitle: context.settingsText(
      'הפעולה לא מוחקת דיווחים שכבר נשלחו לצוות אוצריא.',
    ),
    clear: _service.clearSentReports,
    setBusy: (busy) => setState(() => _isClearingSent = busy),
  );

  Future<void> _exportScript() => exportOfflineSendScript(
    context,
    loadPending: _service.getPendingReports,
    buildScript: (reports, target) =>
        _service.buildOfflineSendScript(reports, target: target),
    setBusy: (busy) => setState(() => _isExporting = busy),
  );
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
