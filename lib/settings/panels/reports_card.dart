import 'package:flutter/material.dart';
import 'package:otzaria/app_report/view/app_report_dialog.dart';
import 'package:otzaria/settings/dialogs/reports_management_dialog.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/search/settings_search_registry.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// The "דיווחים" card in System settings: a summary of saved and sent reports
/// of every kind, with the reports dialog behind "הצג דיווחים".
class ReportsCard extends StatefulWidget {
  const ReportsCard({
    super.key,
    this.loadCounts = ReportCounts.load,
    this.openManagement = showReportsManagementDialog,
  });

  static const cardId = 'system.reports';

  final Future<ReportCounts> Function() loadCounts;
  final Future<void> Function(BuildContext context, {ReportsTab? initialTab})
  openManagement;

  @override
  State<ReportsCard> createState() => _ReportsCardState();
}

class _ReportsCardState extends State<ReportsCard> {
  ReportCounts? _counts;

  @override
  void initState() {
    super.initState();
    SettingsSearchRegistry.instance.registerSectionOpener(
      ReportsCard.cardId,
      _openSection,
    );
    _loadCounts();
  }

  @override
  void dispose() {
    SettingsSearchRegistry.instance.unregisterSectionOpener(
      ReportsCard.cardId,
      _openSection,
    );
    super.dispose();
  }

  Future<void> _loadCounts() async {
    final counts = await widget.loadCounts();
    if (mounted) setState(() => _counts = counts);
  }

  /// A [ReportsTab] name opens that tab; any other section opens the default.
  void _openSection(String section) =>
      _openDialog(ReportsTab.values.asNameMap()[section]);

  Future<void> _openDialog([ReportsTab? tab]) async {
    await widget.openManagement(context, initialTab: tab);
    await _loadCounts();
  }

  Future<void> _openReportForm() async {
    await showAppReportDialog(context, dialogBuilder: settingsDialogBuilder);
    await _loadCounts();
  }

  String _summary(BuildContext context) {
    final counts = _counts;
    if (counts == null) return context.settingsText('טוען...');
    final pending = counts.pending == 0
        ? context.settingsText('אין דיווחים שמורים בתור')
        : context.settingsText(
            '{count} שמורים בתור',
            args: {'count': counts.pending},
          );
    final sent = context.settingsText(
      '{count} נשלחו',
      args: {'count': counts.sent},
    );
    return '$pending · $sent';
  }

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      cardId: ReportsCard.cardId,
      title: context.settingsText('דיווחים'),
      children: [
        SettingsActionTile.text(
          icon: OtzariaIcons.task_list_24_regular,
          title: context.settingsText('טעויות בספרים, תקלות בתוכנה ותוספים'),
          subtitle: _summary(context),
          actions: [
            ActionButton.neutral(
              key: const ValueKey('reports-card-open-app-report'),
              text: context.settingsText('דווח על תקלה'),
              onPressed: _openReportForm,
            ),
            ActionButton.recommended(
              key: const ValueKey('reports-card-manage'),
              text: context.settingsText('הצג דיווחים'),
              onPressed: _openDialog,
            ),
          ],
        ),
      ],
    );
  }
}
