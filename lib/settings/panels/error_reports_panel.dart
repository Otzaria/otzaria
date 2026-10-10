import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/panels/report_panel_widgets.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/models/direct_error_report.dart';
import 'package:otzaria/text_book/view/text_correction_editor.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/widgets/dialogs/error_report_sender_email_dialog.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/utils/canonical_json.dart';

/// Direct error reports on books: identification email, offline queueing,
/// the saved queue and the sent history.
class ErrorReportsPanel extends StatefulWidget {
  const ErrorReportsPanel({
    super.key,
    required this.isOfflineMode,
    this.onPendingReportsChanged,
  });

  final bool isOfflineMode;
  final VoidCallback? onPendingReportsChanged;

  @override
  State<ErrorReportsPanel> createState() => _ErrorReportsPanelState();
}

class _ErrorReportsPanelState extends State<ErrorReportsPanel> {
  bool _isFlushingPendingReports = false;
  bool _isClearingPendingReports = false;
  bool _isExportingPendingReports = false;
  bool _isClearingSentReports = false;
  bool _isPendingReportsExpanded = false;
  bool _isSentReportsExpanded = false;
  String? _sendingPendingReportId;

  @override
  Widget build(BuildContext context) {
    final reportService = DirectErrorReportService();
    final senderEmail = reportService.senderEmail;
    final queueWhenOffline = reportService.queueWhenOfflineEnabled;

    return AppCard.section(
      children: [
        SettingsActionTile.text(
          icon: FluentIcons.mail_24_regular,
          title: context.settingsText('כתובת דואר אלקטרוני לזיהוי'),
          subtitle: senderEmail.isEmpty
              ? context.settingsText('עדיין לא הוגדרה כתובת זיהוי')
              : senderEmail,
          subtitleLtr: senderEmail.isNotEmpty,
          actions: [
            if (senderEmail.isNotEmpty)
              ActionButton.neutral(
                text: context.settingsText('נקה'),
                onPressed: _clearSenderEmail,
              ),
            ActionButton.recommended(
              text: context.settingsText(
                senderEmail.isEmpty ? 'הגדר' : 'ערוך',
              ),
              onPressed: _editSenderEmail,
            ),
          ],
        ),
        SettingsActionTile.switchTile(
          icon: FluentIcons.cloud_arrow_up_24_regular,
          title: context.settingsText('שמירת דיווחים אוטומטית כשאין חיבור'),
          subtitle: queueWhenOffline
              ? context.settingsText(
                  'דיווחים שלא נשלחו יישמרו ויישלחו אוטומטית בהמשך',
                )
              : context.settingsText(
                  'במצב אופליין לא יתבצע תור אוטומטי לדיווחים ישירים',
                ),
          value: queueWhenOffline,
          onChanged: (value) async {
            await reportService.setQueueWhenOfflineEnabled(value);
            if (!mounted) return;
            setState(() {});
          },
        ),
        FutureBuilder<List<DirectErrorReport>>(
          future: reportService.getPendingReports(),
          builder: (context, snapshot) {
            final pendingReports = snapshot.data ?? const <DirectErrorReport>[];
            final pendingCount = pendingReports.length;
            final hasReports = pendingCount > 0;

            return ExpandableSection(
              icon: OtzariaIcons.task_list_24_regular,
              title: context.settingsText('ניהול דיווחים שמורים'),
              subtitle: pendingCount == 0
                  ? context.settingsText('אין כרגע דיווחים שמורים בתור')
                  : context.settingsText(
                      'יש כרגע {count} דיווחים שמורים בתור',
                      args: {'count': pendingCount},
                    ),
              hasContent: hasReports,
              onTap: () => setState(
                () => _isPendingReportsExpanded = !_isPendingReportsExpanded,
              ),
              isExpanded: _isPendingReportsExpanded,
              children: [
                if (hasReports)
                  Padding(
                    padding: const EdgeInsets.only(
                      right: 16,
                      left: 16,
                      top: 8,
                      bottom: 16,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow =
                            constraints.maxWidth < LayoutBreakpoints.compact;
                        final sendButton = buildManagedActionButton(
                          enabled: !widget.isOfflineMode,
                          child: ActionButton.recommended(
                            text: context.settingsText('שלח עכשיו'),
                            icon: FluentIcons.arrow_sync_24_regular,
                            onPressed: _flushPendingReports,
                            isLoading: _isFlushingPendingReports,
                          ),
                        );
                        final clearButton = buildManagedActionButton(
                          enabled: hasReports,
                          child: ActionButton.neutral(
                            text: context.settingsText('נקה דיווחים'),
                            icon: FluentIcons.delete_24_regular,
                            onPressed: _clearPendingReports,
                            isLoading: _isClearingPendingReports,
                          ),
                        );
                        final exportButton = buildManagedActionButton(
                          enabled: hasReports,
                          child: ActionButton.neutral(
                            text: context.settingsText(
                              'הורד לשליחה במחשב מחובר',
                            ),
                            icon: FluentIcons.arrow_download_24_regular,
                            onPressed: _exportPendingReportsScript,
                            isLoading: _isExportingPendingReports,
                          ),
                        );

                        if (isNarrow) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              sendButton,
                              const SizedBox(height: 8),
                              clearButton,
                              const SizedBox(height: 8),
                              exportButton,
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(child: sendButton),
                            const SizedBox(width: 12),
                            Expanded(child: clearButton),
                            const SizedBox(width: 12),
                            Expanded(child: exportButton),
                          ],
                        );
                      },
                    ),
                  ),
                if (widget.isOfflineMode)
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
                if (pendingReports.isNotEmpty)
                  ...pendingReports.map(
                    (report) => _buildPendingReportTile(
                      context,
                      report,
                      canSend: !widget.isOfflineMode,
                    ),
                  ),
              ],
            );
          },
        ),
        FutureBuilder<(List<DirectErrorReport>, int)>(
          future: (
            reportService.getSentReports(),
            reportService.getSentReportsTotal(),
          ).wait,
          builder: (context, snapshot) {
            final sentReports =
                snapshot.data?.$1 ?? const <DirectErrorReport>[];

            return ExpandableSection(
              icon: FluentIcons.checkmark_circle_24_regular,
              title: context.settingsText('דיווחים שנשלחו'),
              hasContent: sentReports.isNotEmpty,
              subtitle: sentReportsSubtitle(
                context,
                shown: sentReports.length,
                total: snapshot.data?.$2 ?? 0,
              ),
              onTap: () => setState(
                () => _isSentReportsExpanded = !_isSentReportsExpanded,
              ),
              isExpanded: _isSentReportsExpanded,
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
                          enabled: sentReports.isNotEmpty,
                          child: ActionButton.neutral(
                            text: context.settingsText(
                              'נקה את כל ההיסטוריה',
                            ),
                            icon: FluentIcons.delete_24_regular,
                            onPressed: _clearSentReports,
                            isLoading: _isClearingSentReports,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (sentReports.isNotEmpty)
                  ...sentReports.map(
                    (report) => _buildSentReportTile(context, report),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _editSenderEmail() async {
    final reportService = DirectErrorReportService();
    final email = await showErrorReportSenderEmailDialog(
      context: context,
      initialValue: reportService.senderEmail,
      validator: (value) => DirectErrorReportService.isValidSenderEmail(value)
          ? null
          : context.settingsText('יש להזין כתובת דוא"ל תקינה.'),
    );

    if (email == null) {
      return;
    }

    await reportService.saveSenderEmail(email);
    if (!mounted) return;
    setState(() {});
    UiSnack.showSuccess(ReportMessages.senderEmailSaved);
  }

  Future<void> _clearSenderEmail() async {
    await DirectErrorReportService().clearSenderEmail();
    if (!mounted) return;
    setState(() {});
    UiSnack.show(ReportMessages.senderEmailCleared);
  }

  Future<void> _flushPendingReports() {
    final reportService = DirectErrorReportService();
    return flushReportQueue(
      context,
      pendingCount: reportService.getPendingReportsCount,
      flush: reportService.flushPendingReports,
      setBusy: (busy) => setState(() => _isFlushingPendingReports = busy),
      onPendingReportsChanged: widget.onPendingReportsChanged,
    );
  }

  Future<void> _sendPendingReport(DirectErrorReport report) async {
    setState(() {
      _sendingPendingReportId = report.id;
    });

    DirectReportDeliveryResult? result;
    try {
      result = await DirectErrorReportService().submitPendingReport(report);
    } catch (e) {
      debugPrint('Failed to send pending direct report: $e');
      if (mounted) {
        UiSnack.showError(ReportMessages.sendError(e));
      }
      return;
    } finally {
      if (mounted) {
        setState(() {
          _sendingPendingReportId = null;
        });
        widget.onPendingReportsChanged?.call();
      }
    }

    if (!mounted) return;
    if (result.isSent) {
      if (result.isDuplicate || result.correctionNotSupported) {
        UiSnack.show(result.message);
      } else {
        await ErrorReportHelper.showDirectReportDetailsDialog(
          context,
          title: ReportMessages.sentSuccessTitle,
          report: report,
        );
      }
      if (!mounted) return;
      setState(() {});
    } else if (result.isQueued) {
      UiSnack.show(result.message);
    } else {
      UiSnack.showError(result.message);
    }
  }

  Future<void> _markPendingReportAsSent(DirectErrorReport report) async {
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
    if (confirmed != true) {
      return;
    }

    await DirectErrorReportService().markPendingReportAsSent(report);
    if (!mounted) return;
    setState(() {});
    widget.onPendingReportsChanged?.call();
    UiSnack.show(ReportMessages.markedAsSent);
  }

  Future<void> _editPendingReport(DirectErrorReport report) async {
    var editValues = _PendingReportEditValues(
      selectedText: report.selectedText,
      errorDetails: report.errorDetails,
      contextText: report.contextText,
    );
    final hasChanges = ValueNotifier(false);

    final confirmed = await showTwoActionsDialog(
      context: context,
      title: context.settingsText('עריכת דיווח שמור'),
      content: '',
      cancelText: context.settingsText('ביטול'),
      confirmText: context.settingsText('שמור'),
      handleEnterKey: false,
      hasUnsavedChanges: hasChanges,
      customContent: SizedBox(
        width: 560,
        child: _PendingReportEditFields(
          initialValues: editValues,
          correction: report.correction,
          onChanged: (values) {
            editValues = values;
            final draft = values.correctionDraft;
            hasChanges.value =
                values.selectedText != report.selectedText ||
                values.errorDetails != report.errorDetails ||
                values.contextText != report.contextText ||
                (draft != null && draft.correction != report.correction);
          },
        ),
      ),
    );
    hasChanges.dispose();

    if (confirmed == true) {
      final draft = editValues.correctionDraft;
      if (draft != null &&
          (!draft.isValid ||
              (!draft.hasProposal && editValues.errorDetails.trim().isEmpty))) {
        UiSnack.showError(
          draft.error ?? ReportMessages.proposalNeedsDetailsOrChange,
        );
        return;
      }
      await DirectErrorReportService().updatePendingReport(
        report.copyWith(
          selectedText: replaceLoneSurrogates(editValues.selectedText.trim()),
          errorDetails: replaceLoneSurrogates(editValues.errorDetails.trim()),
          contextText: replaceLoneSurrogates(editValues.contextText.trim()),
          correction: draft?.correction,
        ),
      );
      if (!mounted) return;
      setState(() {});
      UiSnack.showSuccess(ReportMessages.reportUpdated);
    }
  }

  Future<void> _showReportDetails(
    DirectErrorReport report, {
    required bool sent,
  }) async {
    await ErrorReportHelper.showDirectReportDetailsDialog(
      context,
      title: context.settingsText(
        sent ? 'פרטי דיווח שנשלח' : 'פרטי דיווח שמור',
      ),
      report: report,
    );
  }

  Future<void> _deletePendingReport(DirectErrorReport report) async {
    await DirectErrorReportService().deletePendingReport(report.id);
    if (!mounted) return;
    setState(() {});
    widget.onPendingReportsChanged?.call();
    UiSnack.show(ReportMessages.removedFromQueue);
  }

  Future<void> _deleteSentReport(DirectErrorReport report) async {
    await DirectErrorReportService().deleteSentReport(report.id);
    if (!mounted) return;
    setState(() {});
    UiSnack.show(ReportMessages.deletedFromHistory);
  }

  Future<void> _clearSentReports() => clearSentReports(
    context,
    subtitle: context.settingsText('הפעולה לא מוחקת דיווחים שכבר נשלחו לצוות.'),
    clear: () => DirectErrorReportService().clearSentReports(),
    setBusy: (busy) => setState(() => _isClearingSentReports = busy),
  );

  Future<void> _clearPendingReports() => clearPendingReports(
    context,
    clear: () => DirectErrorReportService().clearPendingReports(),
    setBusy: (busy) => setState(() => _isClearingPendingReports = busy),
    onPendingReportsChanged: widget.onPendingReportsChanged,
  );

  Future<void> _exportPendingReportsScript() {
    final reportService = DirectErrorReportService();
    return exportOfflineSendScript(
      context,
      loadPending: reportService.getPendingReports,
      buildScript: (reports, target) =>
          reportService.buildOfflineSendScript(reports, target: target),
      setBusy: (busy) => setState(() => _isExportingPendingReports = busy),
    );
  }

  String _reportSummary(BuildContext context, DirectErrorReport report) {
    final noDetails = context.settingsText('ללא פירוט');
    return '${report.currentRef} · '
        '${report.errorDetails.isEmpty ? noDetails : report.errorDetails}';
  }

  Widget _buildPendingReportTile(
    BuildContext context,
    DirectErrorReport report, {
    required bool canSend,
  }) => buildPendingReportTile(
    context,
    icon: OtzariaIcons.document_bullet_list_24_regular,
    title: report.bookTitle,
    subtitle: _reportSummary(context, report),
    canSend: canSend,
    isSending: _sendingPendingReportId == report.id,
    onView: () => _showReportDetails(report, sent: false),
    onEdit: () => _editPendingReport(report),
    onDelete: () => _deletePendingReport(report),
    onMarkSent: () => _markPendingReportAsSent(report),
    onSend: () => _sendPendingReport(report),
  );

  Widget _buildSentReportTile(BuildContext context, DirectErrorReport report) =>
      buildSentReportTile(
        context,
        icon: report.rejectionReason == null
            ? FluentIcons.checkmark_24_regular
            : FluentIcons.error_circle_24_regular,
        title: report.bookTitle,
        subtitle: _reportSummary(context, report),
        onView: () => _showReportDetails(report, sent: true),
        onDelete: () => _deleteSentReport(report),
      );
}

class _PendingReportEditValues {
  final String selectedText;
  final String errorDetails;
  final String contextText;
  final TextCorrectionDraft? correctionDraft;

  const _PendingReportEditValues({
    required this.selectedText,
    required this.errorDetails,
    required this.contextText,
    this.correctionDraft,
  });

  _PendingReportEditValues copyWith({
    String? selectedText,
    String? errorDetails,
    String? contextText,
  }) {
    return _PendingReportEditValues(
      selectedText: selectedText ?? this.selectedText,
      errorDetails: errorDetails ?? this.errorDetails,
      contextText: contextText ?? this.contextText,
      correctionDraft: correctionDraft,
    );
  }
}

class _PendingReportEditFields extends StatefulWidget {
  final _PendingReportEditValues initialValues;
  final ValueChanged<_PendingReportEditValues> onChanged;

  /// בדיווח הצעת תיקון נפתח אותו עורך כמו בטופס המקורי.
  final TextCorrection? correction;

  const _PendingReportEditFields({
    required this.initialValues,
    required this.onChanged,
    this.correction,
  });

  @override
  State<_PendingReportEditFields> createState() =>
      _PendingReportEditFieldsState();
}

class _PendingReportEditFieldsState extends State<_PendingReportEditFields> {
  late final TextEditingController _selectedTextController;
  late final TextEditingController _detailsController;
  late final TextEditingController _contextController;
  TextCorrectionDraft? _draft;

  @override
  void initState() {
    super.initState();
    _selectedTextController = TextEditingController(
      text: widget.initialValues.selectedText,
    );
    _detailsController = TextEditingController(
      text: widget.initialValues.errorDetails,
    );
    _contextController = TextEditingController(
      text: widget.initialValues.contextText,
    );
  }

  @override
  void dispose() {
    _selectedTextController.dispose();
    _detailsController.dispose();
    _contextController.dispose();
    super.dispose();
  }

  void _notifyChanged() {
    widget.onChanged(
      _PendingReportEditValues(
        selectedText: _selectedTextController.text,
        errorDetails: _detailsController.text,
        contextText: _contextController.text,
        correctionDraft: _draft,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final correction = widget.correction;
    if (correction != null) {
      return SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextCorrectionEditor(
              original: correction,
              restoreProposal: true,
              fontSize: Theme.of(context).textTheme.bodyLarge?.fontSize ?? 16,
              onChanged: (draft) {
                _draft = draft;
                _notifyChanged();
              },
            ),
            const SizedBox(height: 12),
            RtlTextField(
              controller: _detailsController,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              minLines: 1,
              maxLines: 6,
              onChanged: (_) => _notifyChanged(),
              decoration: InputDecoration(
                labelText: context.settingsText('פירוט הטעות'),
                isDense: true,
                contentPadding: const EdgeInsets.only(top: 12, bottom: 12),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RtlTextField(
          controller: _selectedTextController,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          minLines: 1,
          maxLines: 5,
          onChanged: (_) => _notifyChanged(),
          decoration: InputDecoration(
            labelText: context.settingsText('הטקסט שנבחר'),
            isDense: true,
            contentPadding: EdgeInsets.only(
              top: 12,
              bottom: 12,
            ),
          ),
        ),
        const SizedBox(height: 12),
        RtlTextField(
          controller: _detailsController,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          minLines: 1,
          maxLines: 6,
          onChanged: (_) => _notifyChanged(),
          decoration: InputDecoration(
            labelText: context.settingsText('פירוט הטעות'),
            isDense: true,
            contentPadding: EdgeInsets.only(
              top: 12,
              bottom: 12,
            ),
          ),
        ),
        const SizedBox(height: 12),
        RtlTextField(
          controller: _contextController,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          minLines: 1,
          maxLines: 6,
          onChanged: (_) => _notifyChanged(),
          decoration: InputDecoration(
            labelText: context.settingsText('הקשר'),
            isDense: true,
            contentPadding: EdgeInsets.only(
              top: 12,
              bottom: 12,
            ),
          ),
        ),
      ],
    );
  }
}
