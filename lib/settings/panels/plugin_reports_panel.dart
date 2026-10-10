import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/panels/report_panel_widgets.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/models/plugin_report_record.dart';
import 'package:otzaria/plugins/services/plugin_report_service.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// Reports sent to plugin developers through the Otzaria site: the saved
/// queue and the sent history.
class PluginReportsPanel extends StatefulWidget {
  const PluginReportsPanel({
    super.key,
    required this.isOfflineMode,
    this.onPendingReportsChanged,
  });

  final bool isOfflineMode;
  final VoidCallback? onPendingReportsChanged;

  @override
  State<PluginReportsPanel> createState() => _PluginReportsPanelState();
}

class _PluginReportsPanelState extends State<PluginReportsPanel> {
  bool _isFlushingPluginReports = false;
  bool _isClearingPluginPendingReports = false;
  bool _isExportingPluginReports = false;
  bool _isClearingPluginSentReports = false;
  bool _isPluginPendingReportsExpanded = false;
  bool _isPluginSentReportsExpanded = false;
  String? _sendingPluginReportId;

  @override
  Widget build(BuildContext context) {
    final reportService = PluginReportService();

    return AppCard.section(
      children: [
        FutureBuilder<List<PluginReportRecord>>(
          future: reportService.getPendingReports(),
          builder: (context, snapshot) {
            final pendingRecords =
                snapshot.data ?? const <PluginReportRecord>[];
            final pendingCount = pendingRecords.length;
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
                () => _isPluginPendingReportsExpanded =
                    !_isPluginPendingReportsExpanded,
              ),
              isExpanded: _isPluginPendingReportsExpanded,
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
                            onPressed: _flushPluginReports,
                            isLoading: _isFlushingPluginReports,
                          ),
                        );
                        final clearButton = buildManagedActionButton(
                          enabled: hasReports,
                          child: ActionButton.neutral(
                            text: context.settingsText('נקה דיווחים'),
                            icon: FluentIcons.delete_24_regular,
                            onPressed: _clearPluginPendingReports,
                            isLoading: _isClearingPluginPendingReports,
                          ),
                        );
                        final exportButton = buildManagedActionButton(
                          enabled: hasReports,
                          child: ActionButton.neutral(
                            text: context.settingsText(
                              'הורד לשליחה במחשב מחובר',
                            ),
                            icon: FluentIcons.arrow_download_24_regular,
                            onPressed: _exportPluginReportsScript,
                            isLoading: _isExportingPluginReports,
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
                ...pendingRecords.map(
                  (record) => _buildPluginPendingReportTile(
                    context,
                    record,
                    canSend: !widget.isOfflineMode,
                  ),
                ),
              ],
            );
          },
        ),
        FutureBuilder<(List<PluginReportRecord>, int)>(
          future: (
            reportService.getSentReports(),
            reportService.getSentReportsTotal(),
          ).wait,
          builder: (context, snapshot) {
            final sentRecords =
                snapshot.data?.$1 ?? const <PluginReportRecord>[];

            return ExpandableSection(
              icon: FluentIcons.checkmark_circle_24_regular,
              title: context.settingsText('דיווחים שנשלחו'),
              hasContent: sentRecords.isNotEmpty,
              subtitle: sentReportsSubtitle(
                context,
                shown: sentRecords.length,
                total: snapshot.data?.$2 ?? 0,
              ),
              onTap: () => setState(
                () => _isPluginSentReportsExpanded =
                    !_isPluginSentReportsExpanded,
              ),
              isExpanded: _isPluginSentReportsExpanded,
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
                          enabled: sentRecords.isNotEmpty,
                          child: ActionButton.neutral(
                            text: context.settingsText(
                              'נקה את כל ההיסטוריה',
                            ),
                            icon: FluentIcons.delete_24_regular,
                            onPressed: _clearPluginSentReports,
                            isLoading: _isClearingPluginSentReports,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ...sentRecords.map(
                  (record) => _buildPluginSentReportTile(context, record),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  String _pluginReportTypeLabel(BuildContext context, String reportType) {
    switch (reportType) {
      case 'bug':
        return context.settingsText('תקלה');
      case 'crash':
        return context.settingsText('קריסה');
      case 'content':
        return context.settingsText('תוכן לא תקין');
      default:
        return context.settingsText('אחר');
    }
  }

  String _formatPluginReportDate(DateTime date) {
    return '${date.day}.${date.month}.${date.year}';
  }

  Future<void> _flushPluginReports() {
    final reportService = PluginReportService();
    return flushReportQueue(
      context,
      pendingCount: reportService.getPendingReportsCount,
      flush: reportService.flushPendingReports,
      setBusy: (busy) => setState(() => _isFlushingPluginReports = busy),
      onPendingReportsChanged: widget.onPendingReportsChanged,
    );
  }

  Future<void> _sendPendingPluginReport(PluginReportRecord record) async {
    setState(() {
      _sendingPluginReportId = record.reportId;
    });

    PluginReportDeliveryStatus? status;
    try {
      status = await PluginReportService().submitPendingReport(record);
    } catch (e) {
      debugPrint('Failed to send pending plugin report: $e');
      if (mounted) {
        UiSnack.showError(ReportMessages.sendError(e));
      }
      return;
    } finally {
      if (mounted) {
        setState(() {
          _sendingPluginReportId = null;
        });
        widget.onPendingReportsChanged?.call();
      }
    }

    if (!mounted) return;
    if (status == PluginReportDeliveryStatus.sent) {
      setState(() {});
      UiSnack.showSuccess(ReportMessages.sentToOtzaria);
    } else {
      UiSnack.show(ReportMessages.queuedAfterFailure('אוצריא'));
    }
  }

  Future<void> _editPendingPluginReport(PluginReportRecord record) async {
    var reportType = record.reportType;
    var details = record.details;
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
        child: _PluginReportEditFields(
          initialType: record.reportType,
          initialDetails: record.details,
          typeLabel: (type) => _pluginReportTypeLabel(context, type),
          onChanged: (type, text) {
            reportType = type;
            details = text;
            hasChanges.value =
                type != record.reportType || text != record.details;
          },
        ),
      ),
      hasUnsavedChanges: hasChanges,
    );
    hasChanges.dispose();
    if (confirmed != true) return;
    if (details.trim().isEmpty) {
      UiSnack.showError(ReportMessages.detailsRequired);
      return;
    }

    await PluginReportService().updatePendingReport(
      record.reportId,
      reportType: reportType,
      details: details,
    );
    if (!mounted) return;
    setState(() {});
    UiSnack.showSuccess(ReportMessages.reportUpdated);
  }

  Future<void> _deletePendingPluginReport(PluginReportRecord record) async {
    await PluginReportService().deletePendingReport(record.reportId);
    if (!mounted) return;
    setState(() {});
    widget.onPendingReportsChanged?.call();
    UiSnack.show(ReportMessages.removedFromQueue);
  }

  Future<void> _deleteSentPluginReport(PluginReportRecord record) async {
    await PluginReportService().deleteSentReport(record.reportId);
    if (!mounted) return;
    setState(() {});
    UiSnack.show(ReportMessages.deletedFromHistory);
  }

  Future<void> _clearPluginPendingReports() => clearPendingReports(
    context,
    clear: () => PluginReportService().clearPendingReports(),
    setBusy: (busy) => setState(() => _isClearingPluginPendingReports = busy),
    onPendingReportsChanged: widget.onPendingReportsChanged,
  );

  Future<void> _clearPluginSentReports() => clearSentReports(
    context,
    subtitle: context.settingsText(
      'הפעולה לא מוחקת דיווחים שכבר נשלחו למפתחים.',
    ),
    clear: () => PluginReportService().clearSentReports(),
    setBusy: (busy) => setState(() => _isClearingPluginSentReports = busy),
  );

  Future<void> _exportPluginReportsScript() {
    final reportService = PluginReportService();
    return exportOfflineSendScript(
      context,
      loadPending: reportService.getPendingReports,
      buildScript: (records, target) =>
          reportService.buildOfflineSendScript(records, target: target),
      setBusy: (busy) => setState(() => _isExportingPluginReports = busy),
    );
  }

  Future<void> _showPluginReportDetails(
    PluginReportRecord record, {
    required bool sent,
  }) async {
    final typeLabel = _pluginReportTypeLabel(context, record.reportType);
    final date = _formatPluginReportDate(record.createdAt);
    await showSingleActionDialog(
      context: context,
      title: context.settingsText(
        sent ? 'פרטי דיווח שנשלח' : 'פרטי דיווח שמור',
      ),
      content:
          '${record.pluginName} (${record.pluginVersion})\n'
          '$typeLabel · $date\n\n${record.details}',
      confirmText: context.settingsText('סגור'),
    );
  }

  String _pluginReportSummary(
    BuildContext context,
    PluginReportRecord record,
  ) =>
      '${_pluginReportTypeLabel(context, record.reportType)} · ${record.details}';

  Widget _buildPluginPendingReportTile(
    BuildContext context,
    PluginReportRecord record, {
    required bool canSend,
  }) => buildPendingReportTile(
    context,
    icon: FluentIcons.puzzle_piece_24_regular,
    title: record.pluginName,
    subtitle: _pluginReportSummary(context, record),
    canSend: canSend,
    isSending: _sendingPluginReportId == record.reportId,
    onView: () => _showPluginReportDetails(record, sent: false),
    onEdit: () => _editPendingPluginReport(record),
    onDelete: () => _deletePendingPluginReport(record),
    onSend: () => _sendPendingPluginReport(record),
  );

  Widget _buildPluginSentReportTile(
    BuildContext context,
    PluginReportRecord record,
  ) => buildSentReportTile(
    context,
    icon: FluentIcons.checkmark_24_regular,
    title: record.pluginName,
    subtitle: _pluginReportSummary(context, record),
    onView: () => _showPluginReportDetails(record, sent: true),
    onDelete: () => _deleteSentPluginReport(record),
  );
}

class _PluginReportEditFields extends StatefulWidget {
  final String initialType;
  final String initialDetails;
  final String Function(String type) typeLabel;
  final void Function(String type, String details) onChanged;

  const _PluginReportEditFields({
    required this.initialType,
    required this.initialDetails,
    required this.typeLabel,
    required this.onChanged,
  });

  @override
  State<_PluginReportEditFields> createState() =>
      _PluginReportEditFieldsState();
}

class _PluginReportEditFieldsState extends State<_PluginReportEditFields> {
  late String _type = PluginReportService.normalizeReportType(
    widget.initialType,
  );
  late final TextEditingController _detailsController = TextEditingController(
    text: widget.initialDetails,
  );

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  void _notifyChanged() => widget.onChanged(_type, _detailsController.text);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSegmentedControl<String>(
          expandToFillWidth: true,
          options: [
            for (final type in PluginReportService.reportTypes)
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
          controller: _detailsController,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          minLines: 3,
          maxLines: 8,
          onChanged: (_) => _notifyChanged(),
          decoration: InputDecoration(
            labelText: context.settingsText('פירוט'),
            isDense: true,
            contentPadding: const EdgeInsets.only(top: 12, bottom: 12),
          ),
        ),
      ],
    );
  }
}
