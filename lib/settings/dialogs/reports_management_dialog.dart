import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/app_report/services/crash_report_decision.dart';
import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/plugins/services/plugin_report_service.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/panels/app_reports_panel.dart';
import 'package:otzaria/settings/panels/error_reports_panel.dart';
import 'package:otzaria/settings/panels/plugin_reports_panel.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/layout/panel_scrollable_content.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// A tab of the reports dialog. [name] is also the settings search section.
enum ReportsTab { books, app, plugins }

/// Saved (pending) reports per kind, and sent reports of all kinds.
@immutable
class ReportCounts {
  const ReportCounts({
    this.books = 0,
    this.app = 0,
    this.plugins = 0,
    this.sent = 0,
  });

  final int books;
  final int app;
  final int plugins;
  final int sent;

  int get pending => books + app + plugins;

  int pendingOf(ReportsTab tab) => switch (tab) {
    ReportsTab.books => books,
    ReportsTab.app => app,
    ReportsTab.plugins => plugins,
  };

  static Future<ReportCounts> load({PendingReportStore? reportStore}) async {
    final direct = DirectErrorReportService(reportStore: reportStore);
    final app = AppReportService(reportStore: reportStore);
    final plugins = PluginReportService(reportStore: reportStore);
    final (books, appPending, pluginPending, sent) = await (
      direct.getPendingReportsCount(),
      app.getPendingReportsCount(),
      plugins.getPendingReportsCount(),
      Future.wait([
        direct.getSentReportsTotal(),
        app.getSentReportsTotal(),
        plugins.getSentReportsTotal(),
      ]),
    ).wait;
    return ReportCounts(
      books: books,
      app: appPending,
      plugins: pluginPending,
      sent: sent.fold(0, (a, b) => a + b),
    );
  }
}

/// Opens the reports dialog on [initialTab], or on the first tab with saved
/// reports when none is given.
Future<void> showReportsManagementDialog(
  BuildContext context, {
  ReportsTab? initialTab,
}) async {
  var tab = initialTab;
  if (tab == null) {
    final counts = await ReportCounts.load();
    tab = ReportsTab.values.firstWhere(
      (t) => counts.pendingOf(t) > 0,
      orElse: () => ReportsTab.books,
    );
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: settingsDialogBuilder(
      context,
      (_) => ReportsManagementDialog(initialTab: tab!),
    ),
  );
}

class ReportsManagementDialog extends StatefulWidget {
  const ReportsManagementDialog({super.key, required this.initialTab});

  final ReportsTab initialTab;

  @override
  State<ReportsManagementDialog> createState() =>
      _ReportsManagementDialogState();
}

class _ReportsManagementDialogState extends State<ReportsManagementDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: ReportsTab.values.length,
    initialIndex: widget.initialTab.index,
    vsync: this,
  );
  final _counts = ValueNotifier(const ReportCounts());

  @override
  void initState() {
    super.initState();
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _loadCounts();
    });
    _loadCounts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _counts.dispose();
    super.dispose();
  }

  Future<void> _loadCounts() async {
    final counts = await ReportCounts.load();
    if (mounted) _counts.value = counts;
  }

  AppCrashReportMode get _crashReportMode => AppCrashReportMode.parse(
    Settings.getValue<String>(SettingsRepository.keyAppCrashReportMode),
  );

  Future<void> _setCrashReportMode(AppCrashReportMode mode) async {
    await Settings.setValue(
      SettingsRepository.keyAppCrashReportMode,
      mode.wireName,
    );
    if (mounted) setState(() {});
  }

  String _tabLabel(BuildContext context, ReportsTab tab, ReportCounts counts) {
    final label = context.settingsText(switch (tab) {
      ReportsTab.books => 'טעויות בספרים',
      ReportsTab.app => 'התוכנה',
      ReportsTab.plugins => 'תוספים',
    });
    final pending = counts.pendingOf(tab);
    return pending == 0 ? label : '$label ($pending)';
  }

  Widget _tabBody(String description, Widget panel) {
    return PanelScrollableContent(
      thumbVisibility: true,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 12),
            child: Text(description, style: kSettingsSubtitleStyle),
          ),
          panel,
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppCustomContentDialog(
      title: context.settingsText('הדיווחים שלך'),
      scrollable: false,
      child: BlocSelector<SettingsBloc, SettingsState, bool>(
        selector: (state) => state.isOfflineMode,
        builder: (context, isOfflineMode) => Column(
          children: [
            ValueListenableBuilder<ReportCounts>(
              valueListenable: _counts,
              builder: (context, counts, _) => TabBar(
                controller: _tabController,
                splashBorderRadius: AppTokens.borderRadiusAll,
                tabs: [
                  for (final tab in ReportsTab.values)
                    Tab(text: _tabLabel(context, tab, counts)),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _tabBody(
                    context.settingsText(
                      'שליחה ישירה לצוות אוצריא, כולל תור אוטומטי במצב אופליין.',
                    ),
                    ErrorReportsPanel(
                      isOfflineMode: isOfflineMode,
                      onPendingReportsChanged: _loadCounts,
                    ),
                  ),
                  _tabBody(
                    context.settingsText(
                      'דיווח על תקלות בתוכנה עצמה. הדיווח נפתח כדיווח ציבורי ב-GitHub, וקובצי האבחון גלויים למפתחי אוצריא בלבד.',
                    ),
                    AppReportsPanel(
                      isOfflineMode: isOfflineMode,
                      crashReportMode: _crashReportMode,
                      onCrashReportModeChanged: _setCrashReportMode,
                      onPendingReportsChanged: _loadCounts,
                    ),
                  ),
                  _tabBody(
                    context.settingsText(
                      'דיווחים ששלחתם למפתחי תוספים דרך אתר אוצריא, כולל תור אוטומטי במצב אופליין.',
                    ),
                    PluginReportsPanel(
                      isOfflineMode: isOfflineMode,
                      onPendingReportsChanged: _loadCounts,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
