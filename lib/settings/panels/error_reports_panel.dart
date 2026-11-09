import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/reports/view_scope.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/panels/report_panel_widgets.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/text_book/view/text_correction_editor.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/widgets/dialogs/error_report_sender_email_dialog.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

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
        SettingsSwitchTile(
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
              subtitle: pendingReportsSubtitle(context, count: pendingCount),
              hasContent: hasReports,
              onTap: () => setState(
                () => _isPendingReportsExpanded = !_isPendingReportsExpanded,
              ),
              isExpanded: _isPendingReportsExpanded,
              children: [
                if (hasReports)
                  buildPendingQueueToolbar(
                    canSend: !widget.isOfflineMode,
                    hasReports: hasReports,
                    onSend: _flushPendingReports,
                    isSending: _isFlushingPendingReports,
                    onClear: _clearPendingReports,
                    isClearing: _isClearingPendingReports,
                    onExport: _exportPendingReportsScript,
                    isExporting: _isExportingPendingReports,
                  ),
                if (widget.isOfflineMode) buildOfflineQueueNote(context),
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
                buildClearSentHistoryButton(
                  context,
                  enabled: sentReports.isNotEmpty,
                  onPressed: _clearSentReports,
                  isLoading: _isClearingSentReports,
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
    UiSnack.showSuccess(context.settingsText(ReportMessages.senderEmailSaved));
  }

  Future<void> _clearSenderEmail() async {
    await DirectErrorReportService().clearSenderEmail();
    if (!mounted) return;
    setState(() {});
    UiSnack.show(context.settingsText(ReportMessages.senderEmailCleared));
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
        UiSnack.showError(
          context.settingsText(
            'שגיאה בשליחת הדיווח: {error}',
            args: {'error': e},
          ),
        );
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
        UiSnack.show(reportFeedbackText(context, result.message));
      } else {
        await ErrorReportHelper.showDirectReportDetailsDialog(
          context,
          title: context.settingsText(ReportMessages.sentSuccessTitle),
          report: report,
        );
      }
      if (!mounted) return;
      setState(() {});
    } else if (result.isQueued) {
      UiSnack.show(reportFeedbackText(context, result.message));
    } else {
      UiSnack.showError(reportFeedbackText(context, result.message));
    }
  }

  Future<void> _markPendingReportAsSent(DirectErrorReport report) async {
    final confirmed = await showTwoActionsDialog(
      context: context,
      title: context.settingsText('לסמן כנשלח?'),
      icon: FluentIcons.mail_checkmark_24_regular,
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
    UiSnack.show(context.settingsText(ReportMessages.markedAsSent));
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
      icon: FluentIcons.edit_24_regular,
      size: AppDialogSize.medium,
      cancelText: context.settingsText('ביטול'),
      confirmText: context.settingsText('שמור'),
      handleEnterKey: false,
      isDirty: hasChanges,
      customContent: wrapWithReportScope(
        context,
        SizedBox(
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
      ),
    );
    hasChanges.dispose();

    if (confirmed == true && mounted) {
      final draft = editValues.correctionDraft;
      if (draft == null && editValues.errorDetails.trim().isEmpty) {
        UiSnack.showError(context.settingsText(ReportMessages.detailsRequired));
        return;
      }
      if (draft != null &&
          (!draft.isValid ||
              (!draft.hasProposal && editValues.errorDetails.trim().isEmpty))) {
        UiSnack.showError(
          reportFeedbackText(
            context,
            draft.error ?? ReportMessages.proposalNeedsDetailsOrChange,
          ),
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
      UiSnack.showSuccess(context.settingsText(ReportMessages.reportUpdated));
    }
  }

  Future<void> _showReportDetails(
    DirectErrorReport report, {
    required bool sent,
  }) async {
    await ErrorReportHelper.showDirectReportDetailsDialog(
      context,
      title: sent
          ? sentReportDetailsTitle(
              context,
              carried: report.isCarriedByOfflineUpdate,
            )
          : context.settingsText('פרטי דיווח שמור'),
      report: report,
    );
  }

  Future<void> _deletePendingReport(DirectErrorReport report) async {
    await DirectErrorReportService().deletePendingReport(report.id);
    if (!mounted) return;
    setState(() {});
    widget.onPendingReportsChanged?.call();
    UiSnack.show(context.settingsText(ReportMessages.removedFromQueue));
  }

  Future<void> _deleteSentReport(DirectErrorReport report) async {
    await DirectErrorReportService().deleteSentReport(report.id);
    if (!mounted) return;
    setState(() {});
    UiSnack.show(context.settingsText(ReportMessages.deletedFromHistory));
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
        icon: report.isCarriedByOfflineUpdate
            ? carriedReportIcon
            : report.rejectionReason == null
            ? FluentIcons.checkmark_24_regular
            : FluentIcons.error_circle_24_regular,
        title: report.bookTitle,
        subtitle: [
          ?carriedReportStatus(
            context,
            carried: report.isCarriedByOfflineUpdate,
            carriedAt: report.carriedAt,
          ),
          _reportSummary(context, report),
        ].join(' · '),
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
    return SingleChildScrollView(
      key: const ValueKey('book-report-edit-scroll'),
      // Floating labels extend above an outlined field's border.
      padding: const EdgeInsets.only(top: AppTokens.spaceSM),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Directionality(
            textDirection: reportContentDirection(_selectedTextController.text),
            child: RtlTextField(
              key: const ValueKey('book-report-edit-selection'),
              controller: _selectedTextController,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              minLines: 1,
              maxLines: 5,
              onChanged: (_) => _notifyChanged(),
              decoration: InputDecoration(
                labelText: context.settingsText('הטקסט שנבחר'),
                isDense: true,
                contentPadding: const EdgeInsets.only(top: 12, bottom: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          RtlTextField(
            key: const ValueKey('book-report-edit-details'),
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
          const SizedBox(height: 12),
          Directionality(
            textDirection: reportContentDirection(_contextController.text),
            child: RtlTextField(
              key: const ValueKey('book-report-edit-context'),
              controller: _contextController,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              minLines: 1,
              maxLines: 6,
              onChanged: (_) => _notifyChanged(),
              decoration: InputDecoration(
                labelText: context.settingsText('הקשר'),
                isDense: true,
                contentPadding: const EdgeInsets.only(top: 12, bottom: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
