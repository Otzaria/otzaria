import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart'
    hide SettingsGroup, SwitchSettingsTile;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
// import 'package:path/path.dart' as p;
// import 'package:otzaria/data/constants/database_constants.dart';
import 'package:path_provider/path_provider.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/messages/report_messages.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/app_runtime_reset.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/settings/engine/settings_engine_exports.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/search/settings_search_models.dart';
import 'package:otzaria/settings/view/settings_screen.dart';
import 'package:otzaria/settings/dialogs/settings_dialogs_exports.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/settings/services/backup_service.dart';
import 'package:otzaria/settings/services/backup/backup_maintenance.dart';
import 'package:otzaria/settings/services/backup/backup_rotation.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/empty_library/bloc/empty_library_event.dart';
import 'package:otzaria/empty_library/bloc/empty_library_state.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/models/direct_error_report.dart';
import 'package:otzaria/plugins/models/plugin_report_record.dart';
import 'package:otzaria/plugins/services/plugin_report_service.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/services/data_collection_service.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/widgets/dialogs/error_report_sender_email_dialog.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:otzaria/tools/calendar/helpers/calendar_date_helpers.dart';
import 'package:otzaria/tour/bloc/tour_cubit.dart';
import 'package:otzaria/utils/file/save_file_with_extension.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';
import 'package:otzaria/widgets/misc/restart_widget.dart';
import 'package:url_launcher/url_launcher.dart';

/// טאב "אוצריא" — גרסאות, נתיב ספרייה, גיבוי, מצב סייפר, איפוס.
class SystemSettingsTab extends StatefulWidget {
  const SystemSettingsTab({super.key});

  /// פריטי חיפוש בהגדרות. נסרק על-ידי tool/generate_search_index.dart.
  static const List<SettingsSearchEntry> searchEntries = [
    SettingsSearchEntry(
      id: 'system.versions.app',
      title: 'גרסת תוכנה',
      subtitle: 'גרסת אוצריא המותקנת',
      tab: SettingsTab.system,
      cardId: 'system.versions',
      keywords: ['גרסה', 'version'],
    ),
    SettingsSearchEntry(
      id: 'system.versions.library',
      title: 'גרסת ספרייה',
      subtitle: 'גרסת מאגר הספרים וכמות הספרים בספרייה',
      tab: SettingsTab.system,
      cardId: 'system.versions',
      keywords: ['גרסה', 'ספריה', 'ספרים', 'כמות'],
    ),
    SettingsSearchEntry(
      id: 'system.updates.network_mode',
      title: 'סינכרון ומצב רשת',
      subtitle: 'מקוון / מנותק לחלוטין מהרשת',
      tab: SettingsTab.system,
      cardId: 'system.updates',
      keywords: ['רשת', 'אופליין', 'אונליין', 'מקוון', 'מנותק'],
    ),
    SettingsSearchEntry(
      id: 'system.updates.software',
      title: 'עדכוני תוכנה וספרים',
      subtitle: 'הפעלת עדכוני תוכנה וספרים אוטומטיים',
      tab: SettingsTab.system,
      cardId: 'system.updates',
      keywords: ['עדכון', 'גרסה', 'מופעל', 'לא מופעל'],
    ),
    SettingsSearchEntry(
      id: 'system.updates.library_sync',
      title: 'סינכרון הספרייה באופן אוטומטי',
      subtitle: 'עדכון מסד הנתונים של הספרייה אוטומטית',
      tab: SettingsTab.system,
      cardId: 'system.updates',
      keywords: ['סנכרון', 'ספריה', 'אוטומטי', 'מופעל', 'לא מופעל'],
    ),
    SettingsSearchEntry(
      id: 'system.updates.dev_channel',
      title: 'עדכון לגרסאות מפתחים',
      subtitle: 'קבלת גרסאות בדיקה (Beta)',
      tab: SettingsTab.system,
      cardId: 'system.updates',
      keywords: ['בטא', 'מפתחים', 'יציבה', 'מופעל', 'לא מופעל'],
    ),
    SettingsSearchEntry(
      id: 'system.reports.email',
      title: 'כתובת דואר אלקטרוני לזיהוי',
      subtitle: 'דואר אלקטרוני לזיהוי בדיווחי טעויות',
      tab: SettingsTab.system,
      cardId: 'system.reports',
      keywords: ['מייל', 'דיווח', 'דואר אלקטרוני', 'email'],
    ),
    SettingsSearchEntry(
      id: 'system.reports.queue_offline',
      title: 'שמירת דיווחים אוטומטית כשאין חיבור',
      subtitle: 'תור אוטומטי לדיווחים במצב אופליין',
      tab: SettingsTab.system,
      cardId: 'system.reports',
      keywords: ['דיווח', 'אופליין', 'תור', 'מופעל', 'לא מופעל'],
    ),
    SettingsSearchEntry(
      id: 'system.reports.pending',
      title: 'ניהול דיווחים שמורים',
      subtitle: 'צפיה ושליחה של דיווחים שעדיין לא נשלחו',
      tab: SettingsTab.system,
      cardId: 'system.reports',
      keywords: ['דיווח', 'תור', 'שליחה'],
    ),
    SettingsSearchEntry(
      id: 'system.reports.sent',
      title: 'דיווחים שנשלחו',
      subtitle: 'היסטוריית דיווחים שנשלחו',
      tab: SettingsTab.system,
      cardId: 'system.reports',
      keywords: ['דיווח', 'היסטוריה'],
    ),
    SettingsSearchEntry(
      id: 'system.advanced.backup',
      title: 'גיבוי אוטומטי',
      subtitle: 'תדירות גיבוי + יצירה ושחזור גיבוי',
      tab: SettingsTab.system,
      cardId: 'system.advanced',
      keywords: [
        'גיבוי',
        'שחזור',
        'backup',
        'ללא',
        'שבועי',
        'חודשי',
        'תדירות',
      ],
    ),
    SettingsSearchEntry(
      id: 'system.advanced.backup.mode',
      title: 'מצב גיבוי',
      subtitle: 'גבה הכל / מותאם אישית',
      tab: SettingsTab.system,
      cardId: 'system.advanced',
      keywords: ['גיבוי', 'הכל', 'מותאם אישית'],
    ),
    SettingsSearchEntry(
      id: 'system.advanced.backup.settings',
      title: 'גיבוי הגדרות',
      subtitle: 'כולל את כלל הגדרות התוכנה',
      tab: SettingsTab.system,
      cardId: 'system.advanced',
      keywords: ['גיבוי', 'הגדרות'],
    ),
    SettingsSearchEntry(
      id: 'system.advanced.backup.bookmarks',
      title: 'גיבוי סימניות',
      subtitle: 'כל הסימניות שנשמרו',
      tab: SettingsTab.system,
      cardId: 'system.advanced',
      keywords: ['גיבוי', 'סימניות'],
    ),
    SettingsSearchEntry(
      id: 'system.advanced.backup.history',
      title: 'גיבוי היסטוריה',
      subtitle: 'היסטוריית הלימוד',
      tab: SettingsTab.system,
      cardId: 'system.advanced',
      keywords: ['גיבוי', 'היסטוריה', 'לימוד'],
    ),
    SettingsSearchEntry(
      id: 'system.advanced.backup.notes',
      title: 'גיבוי הערות אישיות',
      subtitle: 'כל ההערות האישיות שלך',
      tab: SettingsTab.system,
      cardId: 'system.advanced',
      keywords: ['גיבוי', 'הערות'],
    ),
    SettingsSearchEntry(
      id: 'system.advanced.backup.workspaces',
      title: 'גיבוי שולחנות עבודה',
      subtitle: 'כל שולחנות העבודה',
      tab: SettingsTab.system,
      cardId: 'system.advanced',
      keywords: ['גיבוי', 'שולחנות עבודה', 'workspace'],
    ),
    SettingsSearchEntry(
      id: 'system.advanced.backup.shamor_zachor',
      title: 'גיבוי שמור וזכור',
      subtitle: 'ספרים ומעקב לימוד',
      tab: SettingsTab.system,
      cardId: 'system.advanced',
      keywords: ['גיבוי', 'שמור וזכור', 'מעקב לימוד'],
    ),
    // [EDITING DISABLED]
    // SettingsSearchEntry(
    //   id: 'system.advanced.backup.user_overrides',
    //   title: 'גיבוי הגדרות מתקדמות',
    //   subtitle: 'הגדרות נוספות שדרסת',
    //   tab: SettingsTab.system,
    //   cardId: 'system.advanced',
    //   keywords: ['גיבוי', 'הגדרות מתקדמות', 'overrides'],
    // ),
    SettingsSearchEntry(
      id: 'system.advanced.backup.create',
      title: 'צור גיבוי עכשיו',
      subtitle: 'יצירת קובץ גיבוי באופן ידני',
      tab: SettingsTab.system,
      cardId: 'system.advanced',
      keywords: ['גיבוי', 'יצירה', 'ידני', 'export'],
    ),
    SettingsSearchEntry(
      id: 'system.advanced.backup.restore',
      title: 'שחזר מגיבוי',
      subtitle: 'שחזור הנתונים מקובץ גיבוי',
      tab: SettingsTab.system,
      cardId: 'system.advanced',
      keywords: ['שחזור', 'גיבוי', 'restore', 'import'],
    ),
    SettingsSearchEntry(
      id: 'system.advanced.backup.retention',
      title: 'ניקוי גיבויים ישנים',
      subtitle: 'מדיניות שמירת גיבויים ומיזוגם לארכיון',
      tab: SettingsTab.system,
      cardId: 'system.advanced',
      keywords: ['גיבוי', 'ניקוי', 'רוטציה', 'ארכיון', 'מקום', 'חסכוני'],
    ),
    SettingsSearchEntry(
      id: 'system.advanced.backup.archive_restore',
      title: 'שחזר מהארכיון',
      subtitle: 'שחזור כל הנתונים שגובו אי-פעם, כולל פריטים שנמחקו',
      tab: SettingsTab.system,
      cardId: 'system.advanced',
      keywords: ['שחזור', 'ארכיון', 'גיבוי', 'היסטוריה'],
    ),
    SettingsSearchEntry(
      id: 'system.advanced.cypher',
      title: 'מצב סייפר',
      subtitle: 'נעילת הגדרות בסיסמה',
      tab: SettingsTab.system,
      cardId: 'system.advanced',
      keywords: ['נעילה', 'סיסמה', 'הגנה', 'מופעל', 'לא מופעל', 'מוגן'],
    ),
    SettingsSearchEntry(
      id: 'system.advanced.cypher.toggle',
      title: 'הפעל מצב סייפר',
      subtitle: 'הפעלה/השבתה של נעילת ההגדרות',
      tab: SettingsTab.system,
      cardId: 'system.advanced',
      keywords: ['סייפר', 'מצב מוגן', 'מופעל', 'לא מופעל', 'נעילה'],
    ),
    SettingsSearchEntry(
      id: 'system.advanced.cypher.password',
      title: 'סיסמה',
      subtitle: 'הגדרת או שינוי סיסמת מצב סייפר',
      tab: SettingsTab.system,
      cardId: 'system.advanced',
      keywords: ['סיסמה', 'סייפר', 'password', 'שינוי סיסמה'],
    ),
    SettingsSearchEntry(
      id: 'system.versions.tour',
      title: 'סיור מודרך להכרת התוכנה',
      subtitle: 'הפעל סיור מודרך להדרכה והכרת כל מסכי אוצריא',
      tab: SettingsTab.system,
      cardId: 'system.versions',
      keywords: ['סיור', 'הדרכה', 'tour', 'מודרך'],
    ),
    SettingsSearchEntry(
      id: 'system.reset',
      title: 'איפוס הגדרות',
      subtitle: 'מחיקת כל ההגדרות וחזרה למצב ההתחלתי',
      tab: SettingsTab.system,
      cardId: 'system.reset',
      keywords: ['איפוס', 'reset'],
    ),
  ];

  @override
  State<SystemSettingsTab> createState() => _SystemSettingsTabState();
}

class _SystemSettingsTabState extends State<SystemSettingsTab> {
  final GlobalKey _networkModeTileKey = GlobalKey();
  final EmptyLibraryBloc _librarySelectionBloc = EmptyLibraryBloc();

  // ── מפתחות גיבוי ──────────────────────────────────────────────────────────
  static const _keyBackupSettings = 'key-backup-settings';
  static const _keyBackupBookmarks = 'key-backup-bookmarks';
  static const _keyBackupHistory = 'key-backup-history';
  static const _keyBackupNotes = 'key-backup-notes';
  static const _keyBackupWorkspaces = 'key-backup-workspaces';
  static const _keyBackupShamorZachor = 'key-backup-shamor-zachor';
  // [EDITING DISABLED] static const _keyBackupUserOverrides = 'key-backup-user-overrides';
  static const _keyBackupPlugins = 'key-backup-plugins';
  static const _keyAutoBackupFrequency = 'key-auto-backup-frequency';

  _BackupMode _selectedBackupMode = _BackupMode.all;

  // ── גיבוי (expandable) ─────────────────────────────────────────────────────
  bool _isBackupExpanded = false;
  BackupStatus? _backupStatus;
  BackupOverview? _backupOverview;
  bool _isRunningMaintenance = false;

  // ── גרסאות ────────────────────────────────────────────────────────────────
  String? _appVersion;
  String? _libraryVersion;
  int? _bookCount;
  bool _isFlushingPendingReports = false;
  bool _isClearingPendingReports = false;
  bool _isExportingPendingReports = false;
  bool _isClearingSentReports = false;
  bool _isPendingReportsExpanded = false;
  static const _backupFolderName = 'תיקיית גיבוי';

  bool _isSentReportsExpanded = false;
  String? _sendingPendingReportId;
  bool _isFlushingPluginReports = false;
  bool _isClearingPluginPendingReports = false;
  bool _isExportingPluginReports = false;
  bool _isClearingPluginSentReports = false;
  bool _isPluginPendingReportsExpanded = false;
  bool _isPluginSentReportsExpanded = false;
  String? _sendingPluginReportId;
  String _resolvedBackupPath = '';
  String _defaultBackupPath = '';

  @override
  void initState() {
    super.initState();
    _loadVersionInfo();
    _loadBackupStatus();
    _loadResolvedBackupPath();
    AppPaths.getDefaultBackupPath().then((p) {
      if (mounted) setState(() => _defaultBackupPath = p);
    });
  }

  void _loadResolvedBackupPath() {
    AppPaths.getBackupPath().then((path) {
      if (mounted) setState(() => _resolvedBackupPath = path);
    });
  }

  @override
  void dispose() {
    _librarySelectionBloc.close();
    super.dispose();
  }

  /// התרגום נעשה כאן ולא בטעינה: `context.settingsText` בגוף הסינכרוני של
  /// [_loadVersionInfo] רץ בתוך `initState` ושם רישום תלות ב-InheritedWidget זורק.
  String _libraryVersionLabel(BuildContext context) {
    final version = _libraryVersion;
    if (version == null) return context.settingsText('טוען...');
    if (version == 'unknown') return context.settingsText('לא ידוע');
    return version;
  }

  Future<void> _loadVersionInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final dataService = DataCollectionService();
    final libVersion = await dataService.readLibraryVersion();

    int? count;
    try {
      final library = await DataRepository.instance.library;
      count = library.getAllBooks().length;
    } catch (_) {
      count = 0;
    }

    if (!mounted) return;
    setState(() {
      _appVersion = packageInfo.version;
      _libraryVersion = libVersion;
      _bookCount = count;
    });
  }

  Future<void> _loadBackupStatus() async {
    final status = await BackupService.analyzeBackupStatus();
    if (!mounted) return;
    setState(() => _backupStatus = status);
    final overview = await BackupMaintenance.getOverview();
    if (!mounted) return;
    setState(() => _backupOverview = overview);
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  String _buildOverviewSubtitle(RetentionProfile profile) {
    final base = switch (profile) {
      RetentionProfile.economy => context.settingsText(
        'שמירה מצומצמת — גיבויים ישנים ממוזגים לארכיון מוקדם',
      ),
      RetentionProfile.balanced => context.settingsText(
        'שבוע מלא, חודשיים שבועי, שנה חודשי — הישן ממוזג לארכיון',
      ),
      RetentionProfile.keepAll => context.settingsText('שום גיבוי לא נמחק'),
    };
    final overview = _backupOverview;
    if (overview == null) return base;
    final parts = [
      context.settingsText(
        '{count} גיבויים',
        args: {'count': overview.backupCount},
      ),
      if (overview.archiveExists) context.settingsText('ארכיון'),
      _formatBytes(overview.totalBytes),
    ];
    final now = context.settingsText(
      'כעת: {parts}',
      args: {'parts': parts.join(' · ')},
    );
    return '$base\n$now';
  }

  Future<void> _openBooksListDialog(BuildContext context) async {
    try {
      final library = await DataRepository.instance.library;
      if (!context.mounted) return;
      await showBooksListDialog(
        context: context,
        books: library.getAllBooks(),
      );
    } catch (e) {
      if (!mounted) return;
      UiSnack.showError(SettingsMessages.booksListLoadError(e));
    }
  }

  String? _buildAutoBackupSubtitle(String frequency) {
    final status = _backupStatus;
    if (status == null) return null;

    if (status.lastBackupDate == null) {
      return context.settingsText(
        'לא נמצא קובץ גיבוי במערכת. מומלץ ליצור גיבוי כדי לשמור על הנתונים שלך.',
      );
    }

    if (frequency == 'none') {
      final dateStr = getHebrewDateFormattedAsString(status.lastBackupDate!);
      return context.settingsText(
        'גיבוי אוטומטי מושבת. הגיבוי האחרון נוצר ב{date}.',
        args: {'date': dateStr},
      );
    }

    if (frequency == 'daily') {
      return context.settingsText('הגיבוי מתבצע כל יום.');
    }

    final thresholdDays = frequency == 'weekly' ? 7 : 30;
    final isUpToDate =
        DateTime.now().difference(status.lastBackupDate!).inDays <=
        thresholdDays;
    final isWeekly = frequency == 'weekly';
    final unitLabel = context.settingsText(isWeekly ? 'שבוע' : 'חודש');

    if (isUpToDate) {
      return context.settingsText(
        'הגיבוי מתבצע כל {unit}, ומעודכן לשינויים האחרונים.',
        args: {'unit': unitLabel},
      );
    }
    if (!status.hasSignificantChanges) {
      return context.settingsText(
        'העדכון מתבצע כל {unit}, ואינו מעודכן לשינויים האחרונים - לא קרו הרבה שינויים.',
        args: {'unit': unitLabel},
      );
    }
    final recommendedUnitLabel = context.settingsText(
      isWeekly ? 'יומי' : 'שבועי',
    );
    return context.settingsText(
      'העדכון מתבצע כל {unit} ואינו מעודכן, מומלץ להגדיר גיבוי {recommended}.',
      args: {'unit': unitLabel, 'recommended': recommendedUnitLabel},
    );
  }

  bool _shouldInclude(String key) =>
      _selectedBackupMode == _BackupMode.all ||
      (Settings.getValue<bool>(key) ?? true);

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

  Future<void> _flushPendingReports() async {
    setState(() {
      _isFlushingPendingReports = true;
    });

    final reportService = DirectErrorReportService();
    final pendingBefore = await reportService.getPendingReportsCount();
    final sentCount = await reportService.flushPendingReports();
    final pendingAfter = await reportService.getPendingReportsCount();

    if (!mounted) return;
    setState(() {
      _isFlushingPendingReports = false;
    });

    if (sentCount > 0) {
      UiSnack.showSuccess(ReportMessages.pendingFlushed(sentCount));
    } else if (pendingBefore == 0) {
      UiSnack.show(ReportMessages.noPendingToSend);
    } else {
      UiSnack.show(ReportMessages.pendingFlushFailed(pendingAfter));
    }
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
      }
    }

    if (!mounted) return;
    if (result.isSent) {
      await ErrorReportHelper.showDirectReportDetailsDialog(
        context,
        title: ReportMessages.sentSuccessTitle,
        report: report,
      );
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
    UiSnack.show(ReportMessages.markedAsSent);
  }

  Future<void> _editPendingReport(DirectErrorReport report) async {
    var editValues = _PendingReportEditValues(
      selectedText: report.selectedText,
      errorDetails: report.errorDetails,
      contextText: report.contextText,
    );

    final confirmed = await showTwoActionsDialog(
      context: context,
      title: context.settingsText('עריכת דיווח שמור'),
      content: '',
      cancelText: context.settingsText('ביטול'),
      confirmText: context.settingsText('שמור'),
      handleEnterKey: false,
      customContent: SizedBox(
        width: 560,
        child: _PendingReportEditFields(
          initialValues: editValues,
          onChanged: (values) => editValues = values,
        ),
      ),
    );

    if (confirmed == true) {
      await DirectErrorReportService().updatePendingReport(
        report.copyWith(
          selectedText: editValues.selectedText.trim(),
          errorDetails: editValues.errorDetails.trim(),
          contextText: editValues.contextText.trim(),
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
    UiSnack.show(ReportMessages.removedFromQueue);
  }

  Future<void> _deleteSentReport(DirectErrorReport report) async {
    await DirectErrorReportService().deleteSentReport(report.id);
    if (!mounted) return;
    setState(() {});
    UiSnack.show(ReportMessages.deletedFromHistory);
  }

  Future<void> _clearSentReports() async {
    final confirmed = await showWarningDialog(
      context: context,
      title: context.settingsText('לנקות את היסטוריית הדיווחים?'),
      content: context.settingsText(
        'כל הדיווחים שנשלחו יימחקו מההיסטוריה המקומית.',
      ),
      subtitle: context.settingsText(
        'הפעולה לא מוחקת דיווחים שכבר נשלחו לצוות.',
      ),
      cancelText: context.settingsText('ביטול'),
      confirmText: context.settingsText('נקה'),
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _isClearingSentReports = true;
    });

    await DirectErrorReportService().clearSentReports();

    if (!mounted) return;
    setState(() {
      _isClearingSentReports = false;
    });
    UiSnack.show(ReportMessages.historyCleared);
  }

  Future<void> _clearPendingReports() async {
    final confirmed = await showWarningDialog(
      context: context,
      title: context.settingsText('למחוק דיווחים שמורים?'),
      content: context.settingsText('כל הדיווחים השמורים בתור יימחקו מהמחשב.'),
      subtitle: context.settingsText('לא ניתן לשחזר דיווחים שנמחקו.'),
      cancelText: context.settingsText('ביטול'),
      confirmText: context.settingsText('מחק'),
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _isClearingPendingReports = true;
    });

    await DirectErrorReportService().clearPendingReports();

    if (!mounted) return;
    setState(() {
      _isClearingPendingReports = false;
    });
    UiSnack.show(ReportMessages.pendingCleared);
  }

  /// קובע לאיזו מערכת הפעלה יותאם סקריפט השליחה. בוינדוס מחזיר מיד Windows;
  /// ב-Linux/macOS שואל את המשתמש; בשאר (נייד) מחזיר Windows אחרי הבהרה
  /// שהקובץ מיועד למחשב Windows מחובר. מחזיר null אם המשתמש ביטל.
  Future<OfflineSendScriptTarget?> _resolveOfflineSendTarget() async {
    if (Platform.isWindows) {
      return OfflineSendScriptTarget.windows;
    }

    if (Platform.isMacOS || Platform.isLinux) {
      return showSelectionDialog<OfflineSendScriptTarget>(
        context: context,
        title: context.settingsText('מערכת ההפעלה של המחשב המחובר'),
        searchHint: context.settingsText('חיפוש מערכת הפעלה...'),
        items: const [
          SelectionItem(
            label: 'Windows',
            value: OfflineSendScriptTarget.windows,
          ),
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

  Future<void> _exportPendingReportsScript() async {
    final verified = await verifySaferModePassword(context);
    if (!verified) {
      return;
    }

    final reportService = DirectErrorReportService();
    final reports = await reportService.getPendingReports();
    if (reports.isEmpty) {
      if (!mounted) return;
      UiSnack.show(ReportMessages.noPendingToExport);
      return;
    }

    final target = await _resolveOfflineSendTarget();
    if (target == null || !mounted) {
      return;
    }

    final script = reportService.buildOfflineSendScript(
      reports,
      target: target,
    );

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
    if (path == null || !mounted) {
      return;
    }

    setState(() {
      _isExportingPendingReports = true;
    });

    try {
      // קובץ .sh נשמר ללא הרשאת הרצה; מוסיפים אותה כדי שאפשר יהיה להפעילו ישירות.
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
      if (!mounted) return;
      UiSnack.showError(ReportMessages.scriptSaveError(e));
    } finally {
      if (mounted) {
        setState(() {
          _isExportingPendingReports = false;
        });
      }
    }
  }

  Widget _buildManagedActionButton({
    required bool enabled,
    required Widget child,
  }) {
    return IgnorePointer(
      ignoring: !enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: child,
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        return BlocListener<LibraryBloc, LibraryState>(
          // הספרייה נטענת מחדש אחרי עדכון/החלפת מיקום — בלי ריענון כאן
          // כרטיס "מערכת" ממשיך להציג גרסת ספרייה ישנה (issue #895).
          listenWhen: LibraryState.reloadCompleted,
          listener: (context, libraryState) => _loadVersionInfo(),
          child: BlocListener<EmptyLibraryBloc, EmptyLibraryState>(
            bloc: _librarySelectionBloc,
            listener: (context, librarySelectionState) async {
              if (librarySelectionState is EmptyLibraryDirectorySelected) {
                await context.read<NavigationBloc>().refreshLibrary();
                if (!context.mounted) {
                  return;
                }
                context.read<LibraryBloc>().add(RefreshLibrary());
                UiSnack.showSuccess(SettingsMessages.libraryLoaded);
              }

              if (librarySelectionState is EmptyLibraryError &&
                  librarySelectionState.errorMessage != null) {
                UiSnack.showError(librarySelectionState.errorMessage!);
              }

              // [בדיקת אנדרואיד] דיאלוג ה-SAF להעתקת seforim.db לאחסון פנימי.
              // אינו ניתן-להתנעה כרגע (שום דבר לא משגר PickDirectoryRequested
              // ל-bloc זה) — לאמת על מכשיר לפני חיבור מחדש או מחיקה.
              if (librarySelectionState is EmptyLibraryAskingDbCopy) {
                if (librarySelectionState.errorMessage != null) {
                  UiSnack.showError(librarySelectionState.errorMessage!);
                }
                if (!context.mounted) {
                  return;
                }
                _showLibraryDbCopyDialog(context, librarySelectionState);
              }
            },
            child: SingleChildScrollView(
              primary: true,
              padding: const EdgeInsets.all(16.0),
              child: ToolPanelWrapper(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. גרסאות + נתיב ספרייה
                    _buildVersionAndPathSection(context, state),

                    // 2. עדכוני מערכת (רשת + עדכון מפתחים)
                    _buildSystemUpdatesSection(context, state),

                    // 3. דיווחי טעויות
                    _buildErrorReportsSection(context, state),

                    // 3ב. דיווחים על תוספים
                    _buildPluginReportsSection(context, state),

                    // 4. מתקדם (גיבוי + מצב סייפר)
                    _buildAdvancedSection(context, state),

                    // 6. איפוס
                    _buildResetSection(context),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  2. עדכוני מערכת (רשת + עדכון מפתחים)
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildSystemUpdatesSection(BuildContext context, SettingsState state) {
    return SettingsCard(
      cardId: 'system.updates',
      title: context.settingsText('עדכוני מערכת'),
      children: [
        KeyedSubtree(
          key: _networkModeTileKey,
          child: SettingsActionTile.segmentedTile<bool>(
            title: context.settingsText('סינכרון ומצב רשת'),
            options: [
              SegmentOption<bool>(
                value: false,
                label: context.settingsText('מקוון'),
                icon: FluentIcons.wifi_1_24_regular,
                subtitle: context.settingsText('התוכנה יכולה להתחבר לרשת'),
              ),
              SegmentOption<bool>(
                value: true,
                label: context.settingsText('מנותק'),
                icon: FluentIcons.wifi_off_24_regular,
                subtitle: context.settingsText('התוכנה מנותקת לגמרי מהרשת'),
              ),
            ],
            currentValue: state.isOfflineMode,
            onChanged: (value) {
              context.read<SettingsBloc>().add(UpdateOfflineMode(value));
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final ctx = _networkModeTileKey.currentContext;
                if (ctx != null) {
                  Scrollable.ensureVisible(
                    ctx,
                    duration: const Duration(milliseconds: 200),
                    alignment: 0.0,
                  );
                }
              });
            },
          ),
        ),
        SettingsActionTile.switchTile(
          icon: FluentIcons.arrow_download_24_regular,
          title: context.settingsText('עדכוני תוכנה וספרים'),
          subtitle: state.isOfflineMode
              ? context.settingsText('מושבת במצב מנותק')
              : state.softwareAndBookUpdatesEnabled
              ? context.settingsText('עדכוני תוכנה וספרים פעילים')
              : context.settingsText('עדכוני מערכת של התוכנה והספרים מושבתים'),
          value: state.canUseSoftwareAndBookUpdates,
          enabled: !state.isOfflineMode,
          onChanged: state.isOfflineMode
              ? null
              : (value) {
                  context.read<SettingsBloc>().add(
                    UpdateSoftwareAndBookUpdatesEnabled(value),
                  );
                },
        ),
        if (!(Platform.isAndroid || Platform.isIOS) &&
            state.canUseSoftwareAndBookUpdates) ...[
          SettingsActionTile.switchTile(
            icon: FluentIcons.arrow_sync_24_regular,
            title: context.settingsText('סינכרון הספרייה באופן אוטומטי'),
            subtitle:
                (Settings.getValue<bool>(SettingsRepository.keyAutoSync) ??
                    true)
                ? context.settingsText(
                    'מסד הנתונים של הספרייה יתעדכן אוטומטית בטעינת הספרייה',
                  )
                : context.settingsText(
                    'סינכרון הספרייה לא יופעל אוטומטית, אך עדיין אפשר להפעיל סינכרון ידני',
                  ),
            value:
                Settings.getValue<bool>(SettingsRepository.keyAutoSync) ?? true,
            onChanged: (value) {
              Settings.setValue<bool>(SettingsRepository.keyAutoSync, value);
              setState(() {});
            },
          ),
          SettingsActionTile.switchTile(
            icon: FluentIcons.beaker_24_regular,
            title: context.settingsText('עדכון לגרסאות מפתחים'),
            subtitle:
                Settings.getValue<bool>(SettingsRepository.keyDevChannel) ??
                    false
                ? context.settingsText(
                    'בדיקת העדכונים הבאה תחפש גם גרסאות בדיקה — ייתכנו באגים',
                  )
                : context.settingsText(
                    'בדיקת העדכונים הבאה תחפש גרסאות יציבות בלבד',
                  ),
            value:
                Settings.getValue<bool>(SettingsRepository.keyDevChannel) ??
                false,
            onChanged: (value) {
              Settings.setValue<bool>(SettingsRepository.keyDevChannel, value);
              setState(() {});
            },
          ),
        ],
      ],
    );
  }

  Widget _buildErrorReportsSection(BuildContext context, SettingsState state) {
    final reportService = DirectErrorReportService();
    final senderEmail = reportService.senderEmail;
    final queueWhenOffline = reportService.queueWhenOfflineEnabled;

    return SettingsCard(
      cardId: 'system.reports',
      title: context.settingsText('דיווחי טעויות'),
      subtitle: context.settingsText(
        'שליחה ישירה לצוות אוצריא, כולל תור אוטומטי במצב אופליין.',
      ),
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
                        final sendButton = _buildManagedActionButton(
                          enabled: !state.isOfflineMode,
                          child: ActionButton.recommended(
                            text: context.settingsText('שלח עכשיו'),
                            icon: FluentIcons.arrow_sync_24_regular,
                            onPressed: _flushPendingReports,
                            isLoading: _isFlushingPendingReports,
                          ),
                        );
                        final clearButton = _buildManagedActionButton(
                          enabled: hasReports,
                          child: ActionButton.neutral(
                            text: context.settingsText('נקה דיווחים'),
                            icon: FluentIcons.delete_24_regular,
                            onPressed: _clearPendingReports,
                            isLoading: _isClearingPendingReports,
                          ),
                        );
                        final exportButton = _buildManagedActionButton(
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
                if (state.isOfflineMode)
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
                      canSend: !state.isOfflineMode,
                    ),
                  ),
              ],
            );
          },
        ),
        FutureBuilder<List<DirectErrorReport>>(
          future: reportService.getSentReports(),
          builder: (context, snapshot) {
            final sentReports = snapshot.data ?? const <DirectErrorReport>[];

            return ExpandableSection(
              icon: FluentIcons.checkmark_circle_24_regular,
              title: context.settingsText('דיווחים שנשלחו'),
              hasContent: sentReports.isNotEmpty,
              subtitle: sentReports.isEmpty
                  ? context.settingsText('עדיין אין דיווחים שנשלחו דרך המערכת')
                  : context.settingsText(
                      'נשמרו {count} דיווחים שנשלחו',
                      args: {'count': sentReports.length},
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
                        child: _buildManagedActionButton(
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

  Widget _buildPendingReportTile(
    BuildContext context,
    DirectErrorReport report, {
    required bool canSend,
  }) {
    final isSending = _sendingPendingReportId == report.id;
    final noDetails = context.settingsText('ללא פירוט');
    return Column(
      children: [
        ListTile(
          leading: const Icon(OtzariaIcons.document_bullet_list_24_regular),
          title: Text(
            report.bookTitle,
            style: kSettingsTitleStyle,
          ),
          subtitle: Text(
            '${report.currentRef} · '
            '${report.errorDetails.isEmpty ? noDetails : report.errorDetails}',
            style: kSettingsSubtitleStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _buildReportActions(
          children: [
            ActionButton.neutral(
              text: context.settingsText('צפה'),
              icon: FluentIcons.eye_24_regular,
              onPressed: () => _showReportDetails(report, sent: false),
            ),
            ActionButton.neutral(
              text: context.settingsText('ערוך'),
              icon: FluentIcons.edit_24_regular,
              onPressed: () => _editPendingReport(report),
            ),
            ActionButton.neutral(
              text: context.settingsText('מחק'),
              icon: FluentIcons.delete_24_regular,
              onPressed: () => _deletePendingReport(report),
            ),
            ActionButton.neutral(
              text: context.settingsText('סמן כנשלח'),
              icon: FluentIcons.checkmark_24_regular,
              onPressed: () => _markPendingReportAsSent(report),
            ),
            _buildManagedActionButton(
              enabled: canSend,
              child: ActionButton.recommended(
                text: context.settingsText('שלח'),
                icon: FluentIcons.send_24_regular,
                isLoading: isSending,
                onPressed: () => _sendPendingReport(report),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSentReportTile(BuildContext context, DirectErrorReport report) {
    final noDetails = context.settingsText('ללא פירוט');
    return Column(
      children: [
        ListTile(
          leading: const Icon(FluentIcons.checkmark_24_regular),
          title: Text(
            report.bookTitle,
            style: kSettingsTitleStyle,
          ),
          subtitle: Text(
            '${report.currentRef} · '
            '${report.errorDetails.isEmpty ? noDetails : report.errorDetails}',
            style: kSettingsSubtitleStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _buildReportActions(
          children: [
            ActionButton.neutral(
              text: context.settingsText('צפה'),
              icon: FluentIcons.eye_24_regular,
              onPressed: () => _showReportDetails(report, sent: true),
            ),
            ActionButton.neutral(
              text: context.settingsText('מחק'),
              icon: FluentIcons.delete_24_regular,
              onPressed: () => _deleteSentReport(report),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReportActions({
    required List<Widget> children,
  }) {
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

  // ════════════════════════════════════════════════════════════════════════════
  //  דיווחים על תוספים
  // ════════════════════════════════════════════════════════════════════════════

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

  Future<void> _flushPluginReports() async {
    setState(() {
      _isFlushingPluginReports = true;
    });

    final reportService = PluginReportService();
    final pendingBefore = await reportService.getPendingReportsCount();
    final sentCount = await reportService.flushPendingReports();
    final pendingAfter = await reportService.getPendingReportsCount();

    if (!mounted) return;
    setState(() {
      _isFlushingPluginReports = false;
    });

    if (sentCount > 0) {
      UiSnack.showSuccess(ReportMessages.pendingFlushed(sentCount));
    } else if (pendingBefore == 0) {
      UiSnack.show(ReportMessages.noPendingToSend);
    } else {
      UiSnack.show(ReportMessages.pendingFlushFailed(pendingAfter));
    }
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

  Future<void> _deletePendingPluginReport(PluginReportRecord record) async {
    await PluginReportService().deletePendingReport(record.reportId);
    if (!mounted) return;
    setState(() {});
    UiSnack.show(ReportMessages.removedFromQueue);
  }

  Future<void> _deleteSentPluginReport(PluginReportRecord record) async {
    await PluginReportService().deleteSentReport(record.reportId);
    if (!mounted) return;
    setState(() {});
    UiSnack.show(ReportMessages.deletedFromHistory);
  }

  Future<void> _clearPluginPendingReports() async {
    final confirmed = await showWarningDialog(
      context: context,
      title: context.settingsText('למחוק דיווחים שמורים?'),
      content: context.settingsText('כל הדיווחים השמורים בתור יימחקו מהמחשב.'),
      subtitle: context.settingsText('לא ניתן לשחזר דיווחים שנמחקו.'),
      cancelText: context.settingsText('ביטול'),
      confirmText: context.settingsText('מחק'),
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _isClearingPluginPendingReports = true;
    });

    await PluginReportService().clearPendingReports();

    if (!mounted) return;
    setState(() {
      _isClearingPluginPendingReports = false;
    });
    UiSnack.show(ReportMessages.pendingCleared);
  }

  Future<void> _clearPluginSentReports() async {
    final confirmed = await showWarningDialog(
      context: context,
      title: context.settingsText('לנקות את היסטוריית הדיווחים?'),
      content: context.settingsText(
        'כל הדיווחים שנשלחו יימחקו מההיסטוריה המקומית.',
      ),
      subtitle: context.settingsText(
        'הפעולה לא מוחקת דיווחים שכבר נשלחו למפתחים.',
      ),
      cancelText: context.settingsText('ביטול'),
      confirmText: context.settingsText('נקה'),
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _isClearingPluginSentReports = true;
    });

    await PluginReportService().clearSentReports();

    if (!mounted) return;
    setState(() {
      _isClearingPluginSentReports = false;
    });
    UiSnack.show(ReportMessages.historyCleared);
  }

  Future<void> _exportPluginReportsScript() async {
    final verified = await verifySaferModePassword(context);
    if (!verified) {
      return;
    }

    final reportService = PluginReportService();
    final records = await reportService.getPendingReports();
    if (records.isEmpty) {
      if (!mounted) return;
      UiSnack.show(ReportMessages.noPendingToExport);
      return;
    }

    final target = await _resolveOfflineSendTarget();
    if (target == null || !mounted) {
      return;
    }

    final script = reportService.buildOfflineSendScript(
      records,
      target: target,
    );

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
    if (path == null || !mounted) {
      return;
    }

    setState(() {
      _isExportingPluginReports = true;
    });

    try {
      // קובץ .sh נשמר ללא הרשאת הרצה; מוסיפים אותה כדי שאפשר יהיה להפעילו ישירות.
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
      if (!mounted) return;
      UiSnack.showError(ReportMessages.scriptSaveError(e));
    } finally {
      if (mounted) {
        setState(() {
          _isExportingPluginReports = false;
        });
      }
    }
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

  Widget _buildPluginReportsSection(
    BuildContext context,
    SettingsState state,
  ) {
    final reportService = PluginReportService();

    return SettingsCard(
      cardId: 'system.pluginReports',
      title: context.settingsText('דיווחים על תוספים'),
      subtitle: context.settingsText(
        'דיווחים ששלחתם למפתחי תוספים דרך אתר אוצריא, כולל תור אוטומטי במצב אופליין.',
      ),
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
                        final sendButton = _buildManagedActionButton(
                          enabled: !state.isOfflineMode,
                          child: ActionButton.recommended(
                            text: context.settingsText('שלח עכשיו'),
                            icon: FluentIcons.arrow_sync_24_regular,
                            onPressed: _flushPluginReports,
                            isLoading: _isFlushingPluginReports,
                          ),
                        );
                        final clearButton = _buildManagedActionButton(
                          enabled: hasReports,
                          child: ActionButton.neutral(
                            text: context.settingsText('נקה דיווחים'),
                            icon: FluentIcons.delete_24_regular,
                            onPressed: _clearPluginPendingReports,
                            isLoading: _isClearingPluginPendingReports,
                          ),
                        );
                        final exportButton = _buildManagedActionButton(
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
                if (state.isOfflineMode && hasReports)
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
                    canSend: !state.isOfflineMode,
                  ),
                ),
              ],
            );
          },
        ),
        FutureBuilder<List<PluginReportRecord>>(
          future: reportService.getSentReports(),
          builder: (context, snapshot) {
            final sentRecords = snapshot.data ?? const <PluginReportRecord>[];

            return ExpandableSection(
              icon: FluentIcons.checkmark_circle_24_regular,
              title: context.settingsText('דיווחים שנשלחו'),
              hasContent: sentRecords.isNotEmpty,
              subtitle: sentRecords.isEmpty
                  ? context.settingsText('עדיין אין דיווחים שנשלחו דרך המערכת')
                  : context.settingsText(
                      'נשמרו {count} דיווחים שנשלחו',
                      args: {'count': sentRecords.length},
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
                        child: _buildManagedActionButton(
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

  Widget _buildPluginPendingReportTile(
    BuildContext context,
    PluginReportRecord record, {
    required bool canSend,
  }) {
    final isSending = _sendingPluginReportId == record.reportId;
    return Column(
      children: [
        ListTile(
          leading: const Icon(FluentIcons.puzzle_piece_24_regular),
          title: Text(
            record.pluginName,
            style: kSettingsTitleStyle,
          ),
          subtitle: Text(
            '${_pluginReportTypeLabel(context, record.reportType)} · '
            '${record.details}',
            style: kSettingsSubtitleStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _buildReportActions(
          children: [
            ActionButton.neutral(
              text: context.settingsText('צפה'),
              icon: FluentIcons.eye_24_regular,
              onPressed: () => _showPluginReportDetails(record, sent: false),
            ),
            ActionButton.neutral(
              text: context.settingsText('מחק'),
              icon: FluentIcons.delete_24_regular,
              onPressed: () => _deletePendingPluginReport(record),
            ),
            _buildManagedActionButton(
              enabled: canSend,
              child: ActionButton.recommended(
                text: context.settingsText('שלח'),
                icon: FluentIcons.send_24_regular,
                isLoading: isSending,
                onPressed: () => _sendPendingPluginReport(record),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPluginSentReportTile(
    BuildContext context,
    PluginReportRecord record,
  ) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(FluentIcons.checkmark_24_regular),
          title: Text(
            record.pluginName,
            style: kSettingsTitleStyle,
          ),
          subtitle: Text(
            '${_pluginReportTypeLabel(context, record.reportType)} · '
            '${record.details}',
            style: kSettingsSubtitleStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _buildReportActions(
          children: [
            ActionButton.neutral(
              text: context.settingsText('צפה'),
              icon: FluentIcons.eye_24_regular,
              onPressed: () => _showPluginReportDetails(record, sent: true),
            ),
            ActionButton.neutral(
              text: context.settingsText('מחק'),
              icon: FluentIcons.delete_24_regular,
              onPressed: () => _deleteSentPluginReport(record),
            ),
          ],
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  2. גרסאות + נתיב ספרייה
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildVersionAndPathSection(
    BuildContext context,
    SettingsState state,
  ) {
    return SettingsCard(
      cardId: 'system.versions',
      title: context.settingsText('מערכת אוצריא'),
      children: [
        SettingsActionTile.text(
          icon: FluentIcons.info_24_regular,
          title: context.settingsText('גרסת תוכנה'),
          subtitle: _appVersion ?? context.settingsText('טוען...'),
          subtitleLtr: _appVersion != null,
          actions: [
            ActionButton.ghost(
              icon: FluentIcons.history_24_regular,
              text: context.settingsText('יומן שינויים'),
              onPressed: () => _showChangelogDialog(context),
            ),
          ],
        ),
        SettingsActionTile.text(
          icon: FluentIcons.library_24_regular,
          title: context.settingsText(
            'גרסת ספרייה {version}',
            args: {'version': _libraryVersionLabel(context)},
          ),
          subtitle: _bookCount != null
              ? context.settingsText(
                  '{count} ספרים',
                  args: {'count': _bookCount!},
                )
              : context.settingsText('טוען...'),
          actions: [
            if (_bookCount != null)
              ActionButton.ghost(
                icon: OtzariaIcons.list_24_regular,
                text: context.settingsText('הצג רשימה'),
                onPressed: () => _openBooksListDialog(context),
              ),
          ],
        ),
        SettingsActionTile.text(
          icon: FluentIcons.sparkle_24_regular,
          title: context.settingsText('סיור מודרך להכרת התוכנה'),
          subtitle: context.settingsText(
            'הפעל סיור מודרך להדרכה והכרת כל מסכי אוצריא',
          ),
          actions: [
            ActionButton.recommended(
              icon: FluentIcons.play_24_regular,
              text: context.settingsText('הפעל'),
              onPressed: () {
                final libraryLoaded = !context
                    .read<NavigationBloc>()
                    .state
                    .isLibraryEmpty;
                context.read<NavigationBloc>().add(
                  const CheckLibrary(),
                );
                context.read<TourCubit>().restart(libraryLoaded: libraryLoaded);
              },
            ),
          ],
        ),
      ],
    );
  }

  void _showLibraryDbCopyDialog(
    BuildContext context,
    EmptyLibraryAskingDbCopy state,
  ) async {
    final sizeText = state.dbSizeBytes > 0
        ? '${(state.dbSizeBytes / 1024 / 1024).toStringAsFixed(1)} MB'
        : context.settingsText('לא ידוע');

    final shouldMove = await showDbCopyRequiredDialog(
      context: context,
      sizeText: sizeText,
    );

    if (shouldMove == null) {
      return;
    }

    _librarySelectionBloc.add(
      PickDbFileRequested(
        libraryPath: state.libraryPath,
        internalDbPath: state.internalDbPath,
        externalDbPath: state.externalDbPath,
        shouldMove: shouldMove,
      ),
    );
  }

  Future<void> _createBackup() async {
    try {
      final result = await BackupService.createBackup(
        includeSettings: _shouldInclude(_keyBackupSettings),
        includeBookmarks: _shouldInclude(_keyBackupBookmarks),
        includeHistory: _shouldInclude(_keyBackupHistory),
        includeNotes: _shouldInclude(_keyBackupNotes),
        includeWorkspaces: _shouldInclude(_keyBackupWorkspaces),
        includeShamorZachor: _shouldInclude(_keyBackupShamorZachor),
        // [EDITING DISABLED] includeUserOverrides: _shouldInclude(_keyBackupUserOverrides),
        includePlugins: _shouldInclude(_keyBackupPlugins),
      );
      if (!mounted) return;
      final backupPath = result.path;
      final file = File(backupPath);
      final exists = await file.exists();
      final size = exists ? await file.length() : 0;
      if (!mounted) return;
      if (exists) {
        _loadBackupStatus();
        final partial = result.skippedSections.isNotEmpty;
        final sizeStr = '${(size / 1024).toStringAsFixed(1)} KB';
        final message = partial
            ? SettingsMessages.partialBackupSaved(
                sizeStr,
                result.skippedSections.join(", "),
              )
            : SettingsMessages.backupSaved(sizeStr);
        UiSnack.showWithAction(
          message: message,
          actionLabel: context.settingsText('פתח מיקום קובץ'),
          onAction: () async {
            final dir = file.parent;
            if (Platform.isWindows) {
              await Process.run('explorer', [dir.path]);
            } else if (Platform.isMacOS) {
              await Process.run('open', [dir.path]);
            } else if (Platform.isLinux) {
              await Process.run('xdg-open', [dir.path]);
            }
          },
          icon: FluentIcons.checkmark_circle_24_regular,
        );
      }
    } catch (e) {
      if (!mounted) return;
      UiSnack.showError(SettingsMessages.backupCreateError(e));
    }
  }

  Future<void> _restoreBackup() async {
    final backups = await BackupService.getAvailableBackups();
    if (backups.isEmpty) {
      if (!mounted) return;
      UiSnack.showError(SettingsMessages.noBackupFileFound);
      return;
    }
    final filePath = backups.first.path;
    if (!mounted) return;

    final confirmed = await showWarningDialog(
      context: context,
      title: context.settingsText('שחזור מגיבוי?'),
      content: context.settingsText(
        'פעולה זו תחליף את הנתונים הקיימים בנתונים מקובץ הגיבוי העדכני ביותר שנמצא בתיקיית הגיבוי.',
      ),
      subtitle: context.settingsText('פעולה זו אינה הפיכה!'),
      cancelText: context.settingsText('ביטול'),
      confirmText: context.settingsText('שחזר'),
    );
    if (confirmed != true) return;

    await _performRestore(filePath);
  }

  /// שחזור מהארכיון הממוזג — כולל פריטים שנמחקו בעבר, ולכן אזהרה נפרדת.
  Future<void> _restoreFromArchive() async {
    final archivePath = await BackupService.getArchivePathIfExists();
    if (!mounted) return;
    if (archivePath == null) {
      UiSnack.show(SettingsMessages.archiveNotCreatedYet);
      return;
    }

    final confirmed = await showWarningDialog(
      context: context,
      title: context.settingsText('שחזור מהארכיון?'),
      content: context.settingsText(
        'הארכיון מאחד את כל הגיבויים הישנים, ולכן הוא כולל גם פריטים '
        '(סימניות, הערות, תוספים ועוד) שנמחקו מאז בכוונה — הם ישוחזרו גם הם.',
      ),
      subtitle: context.settingsText('פעולה זו אינה הפיכה!'),
      cancelText: context.settingsText('ביטול'),
      confirmText: context.settingsText('שחזר הכל'),
    );
    if (confirmed != true) return;

    await _performRestore(archivePath);
  }

  Future<void> _performRestore(String filePath) async {
    try {
      final result = await BackupService.restoreFromBackup(filePath);
      if (!mounted) return;
      final skipped = result.skippedSections;
      final missingFolders = result.missingCustomFolders;
      final isPartial =
          skipped.isNotEmpty ||
          missingFolders.isNotEmpty ||
          result.hasLegacyPartialSettings ||
          result.notesWithoutAnchor > 0;
      final content = [
        if (skipped.isEmpty)
          context.settingsText('הנתונים שוחזרו בהצלחה.')
        else
          context.settingsText(
            'שחזור חלקי — חסרים בקובץ הגיבוי: {items}.',
            args: {'items': skipped.join(", ")},
          ),
        if (result.hasLegacyPartialSettings)
          context.settingsText(
            'קובץ גיבוי זה נוצר בגרסה שגיבתה רק חלק מההגדרות, ולכן הגדרות '
            'שאינן בו לא שוחזרו — בהן קיצורי מקלדת, ברירות המחדל של החיפוש, '
            'התאמות צורת הדף והתאמות פר-ספר. יש לבדוק אם קיים גיבוי חדש יותר, '
            'או להגדיר אותן מחדש.',
          ),
        if (result.notesWithoutAnchor > 0)
          context.settingsText(
            'ב-{count} הערות קובץ הגיבוי אינו כולל את המילים שאליהן הן קושרו, '
            'ולכן הן מסומנות כעת על הקטע כולו. הקישור למילים נכנס לגיבוי '
            'בגרסה מאוחרת יותר.',
            args: {'count': result.notesWithoutAnchor},
          ),
        if (missingFolders.isNotEmpty)
          context.settingsText(
            'תיקיות הספרים הבאות שוחזרו אך לא נמצאו במחשב זה:\n{folders}\n'
            'יש להוסיף אותן מחדש בהגדרות הספרייה, או לחברן לאותו נתיב.',
            args: {'folders': missingFolders.join('\n')},
          ),
        context.settingsText('האפליקציה תיטען מחדש כעת.'),
      ].join('\n\n');
      await showSingleActionDialog(
        context: context,
        title: context.settingsText(
          isPartial ? 'שחזור חלקי' : 'השחזור הושלם',
        ),
        content: content,
        confirmText: context.settingsText('טען מחדש'),
      );
      if (!mounted) return;
      await resetRuntimeStateForAppRestart();
      if (!mounted) return;
      RestartWidget.restartApp(
        context,
        afterRestart: WebViewEnvironmentHolder.disposeForAppRestart,
      );
    } catch (e) {
      if (!mounted) return;
      UiSnack.showError(SettingsMessages.backupRestoreError(e));
    }
  }

  /// "נקה עכשיו" — רוטציה, מיזוג לארכיון ואיסוף קבצים יתומים.
  Future<void> _runMaintenanceNow() async {
    setState(() => _isRunningMaintenance = true);
    try {
      final result = await BackupMaintenance.runMaintenance();
      if (!mounted) return;
      final actions = <String>[
        if (result.mergedIntoArchive > 0)
          SettingsMessages.backupsMergedToArchive(result.mergedIntoArchive),
        if (result.deletedBackups > 0)
          SettingsMessages.backupFilesDeleted(result.deletedBackups),
        if (result.freedBytes > 0)
          SettingsMessages.backupSpaceFreed(_formatBytes(result.freedBytes)),
      ];
      UiSnack.show(
        actions.isEmpty ? SettingsMessages.nothingToClean : actions.join(', '),
      );
      await _loadBackupStatus();
    } catch (e) {
      if (!mounted) return;
      UiSnack.showError(SettingsMessages.backupCleanupError(e));
    } finally {
      if (mounted) setState(() => _isRunningMaintenance = false);
    }
  }

  Future<void> _handleToggleProtectedMode(
    BuildContext context,
    SettingsRepository repository,
    bool newValue,
  ) async {
    final verified = await showDialog<bool>(
      context: context,
      builder: settingsDialogBuilder(
        context,
        (ctx) => SaferModePasswordDialog(
          title: ctx.settingsText('אמת סיסמה'),
          hint: newValue
              ? ctx.settingsText('הזן את הסיסמה כדי להפעיל את המצב המוגן')
              : ctx.settingsText('הזן את הסיסמה כדי להשבית את המצב המוגן'),
          onVerify: (password) async =>
              repository.verifyProtectedModePassword(password),
        ),
      ),
    );
    if (verified != true) return;
    if (context.mounted) {
      context.read<SettingsBloc>().add(UpdateProtectedModeEnabled(newValue));
      UiSnack.show(
        newValue
            ? SettingsMessages.protectedModeEnabled
            : SettingsMessages.protectedModeDisabled,
      );
    }
  }

  Future<void> _handleSetPassword(
    BuildContext context,
    SettingsRepository repository,
    bool hasExistingPassword,
    bool isSaferModeEnabled,
  ) async {
    if (hasExistingPassword) {
      final verified = await showDialog<bool>(
        context: context,
        builder: settingsDialogBuilder(
          context,
          (ctx) => SaferModePasswordDialog(
            title: ctx.settingsText('אמת סיסמה נוכחית'),
            hint: ctx.settingsText('הזן את הסיסמה הנוכחית כדי לשנות אותה'),
            onVerify: (password) async =>
                repository.verifyProtectedModePassword(password),
          ),
        ),
      );
      if (verified != true) return;
    }
    if (!context.mounted) return;
    final settingsBloc = context.read<SettingsBloc>();
    final result = await showDialog<bool>(
      context: context,
      builder: settingsDialogBuilder(
        context,
        (_) => SaferModeSetPasswordDialog(
          onSetPassword: (password) async {
            settingsBloc.add(UpdateProtectedModePassword(password));
          },
          onClearPassword: hasExistingPassword
              ? () async {
                  settingsBloc.add(const ClearProtectedModePassword());
                }
              : null,
          isSaferModeEnabled: isSaferModeEnabled,
        ),
      ),
    );
    if (result == true && context.mounted && !hasExistingPassword) {
      final activate = await showTwoActionsDialog(
        context: context,
        title: context.settingsText('הפעלת מצב סייפר'),
        content: context.settingsText(
          'האם להפעיל כעת את מצב הסייפר?\n'
          'ניתן להפעיל ולבטל אותו מאוחר יותר דרך ההגדרות.',
        ),
        cancelText: context.settingsText('לא עכשיו'),
        confirmText: context.settingsText('הפעל'),
      );
      if (activate == true && context.mounted) {
        context.read<SettingsBloc>().add(
          const UpdateProtectedModeEnabled(true),
        );
      }
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  4. מתקדם (גיבוי + מצב סייפר)
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildAdvancedSection(BuildContext context, SettingsState state) {
    final autoFrequency =
        Settings.getValue<String>(_keyAutoBackupFrequency) ?? 'weekly';
    final retentionProfile = RetentionProfile.fromName(
      Settings.getValue<String>(BackupMaintenance.keyRetentionProfile),
    );
    final repository = RepositoryProvider.of<SettingsRepository>(context);
    final hasPassword = state.protectedModePasswordSet;

    return SettingsCard(
      cardId: 'system.advanced',
      title: context.settingsText('מתקדם'),
      children: [
        // ── צור/שחזר גיבוי ──
        SettingsActionTile.text(
          icon: FluentIcons.arrow_sync_24_regular,
          title: context.settingsText('גיבוי ושחזור'),
          subtitle: context.settingsText(
            'צור גיבוי, או שחזר מהגיבוי האחרון או מהארכיון המלא',
          ),
          actions: [
            ActionButton.recommended(
              icon: FluentIcons.arrow_upload_24_regular,
              text: context.settingsText('צור כעת'),
              onPressed: _createBackup,
            ),
            AppDropdownField<String>(
              value: null,
              isExpanded: false,
              selectedBuilder: (context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FluentIcons.arrow_download_24_regular),
                  const SizedBox(width: 8),
                  Text(context.settingsText('שחזור')),
                ],
              ),
              entries: [
                AppMenuEntry(
                  value: 'latest',
                  label: context.settingsText('מהגיבוי האחרון'),
                  icon: FluentIcons.arrow_download_24_regular,
                ),
                AppMenuEntry(
                  value: 'archive',
                  label: context.settingsText('מהארכיון (כולל שנמחקו)'),
                  icon: FluentIcons.archive_24_regular,
                ),
              ],
              onSelected: (value) {
                if (value == 'latest') {
                  _restoreBackup();
                } else if (value == 'archive') {
                  _restoreFromArchive();
                }
              },
            ),
          ],
        ),

        // ── גיבוי אוטומטי ──
        ExpandableSection(
          icon: FluentIcons.calendar_clock_24_regular,
          title: context.settingsText('גיבוי אוטומטי'),
          subtitle: _buildAutoBackupSubtitle(autoFrequency),
          trailing: AppDropdownField<String>(
            value: autoFrequency,
            entries: [
              AppMenuEntry(
                value: 'none',
                label: context.settingsText('ללא'),
                subtitle: context.settingsText('גיבוי אוטומטי מושבת'),
              ),
              AppMenuEntry(
                value: 'daily',
                label: context.settingsText('יומי'),
                subtitle: context.settingsText('יתבצע גיבוי בכל יום'),
              ),
              AppMenuEntry(
                value: 'weekly',
                label: context.settingsText('שבועי'),
                subtitle: context.settingsText('יתבצע גיבוי כל שבוע'),
              ),
              AppMenuEntry(
                value: 'monthly',
                label: context.settingsText('חודשי'),
                subtitle: context.settingsText('יתבצע גיבוי כל חודש'),
              ),
            ],
            onSelected: (value) {
              if (value == null) return;
              Settings.setValue<String>(_keyAutoBackupFrequency, value);
              setState(() {});
            },
            isExpanded: false,
          ),
          onTap: () => setState(() => _isBackupExpanded = !_isBackupExpanded),
          isExpanded: _isBackupExpanded,
          children: [
            SettingsActionTile.pathTile(
              icon: FluentIcons.folder_24_regular,
              title: context.settingsText('תיקיית גיבוי'),
              currentPath: _resolvedBackupPath,
              placeholder: context.settingsText('שימוש בתיקיית ברירת המחדל'),
              simpleButtonWhenEmpty: false,
              clearPathEnabled:
                  (Settings.getValue<String>(
                            SettingsRepository.keyBackupPath,
                          ) ??
                          '')
                      .isNotEmpty,
              onFolderChanged: (path) async {
                Settings.setValue<String>(
                  SettingsRepository.keyBackupPath,
                  path,
                );
                _loadResolvedBackupPath();
              },
              requestChangeLocation: makeChangeLocationCallback(
                currentPath: _resolvedBackupPath,
                folderName: _backupFolderName,
                onPathChanged: (newPath) async {
                  Settings.setValue<String>(
                    SettingsRepository.keyBackupPath,
                    newPath,
                  );
                  _loadResolvedBackupPath();
                },
                onAfterMove: _resolvedBackupPath.isNotEmpty
                    ? (newPath) async {
                        Settings.setValue<String>(
                          SettingsRepository.keyBackupPath,
                          newPath,
                        );
                        _loadResolvedBackupPath();
                      }
                    : null,
                defaultPath: _defaultBackupPath.isNotEmpty
                    ? _defaultBackupPath
                    : null,
              ),
              onOpenFolder: () {
                final path = _resolvedBackupPath;
                if (path.isEmpty) return;
                if (Platform.isWindows) {
                  unawaited(Process.run('explorer', [path]));
                } else if (Platform.isMacOS) {
                  unawaited(Process.run('open', [path]));
                } else if (Platform.isLinux) {
                  unawaited(Process.run('xdg-open', [path]));
                }
              },
              onClearPath: () {
                Settings.setValue<String>(SettingsRepository.keyBackupPath, '');
                _loadResolvedBackupPath();
              },
            ),
            SettingsActionTile.segmentedTile<_BackupMode>(
              icon: FluentIcons.options_24_regular,
              title: context.settingsText('מצב גיבוי'),
              subtitle: context.settingsText(
                'בחר האם לגבות את כל הנתונים או רק חלק מהם',
              ),
              options: [
                SegmentOption<_BackupMode>(
                  value: _BackupMode.all,
                  label: context.settingsText('גבה הכל'),
                ),
                SegmentOption<_BackupMode>(
                  value: _BackupMode.custom,
                  label: context.settingsText('מותאם אישית'),
                ),
              ],
              currentValue: _selectedBackupMode,
              onChanged: (value) => setState(() => _selectedBackupMode = value),
            ),
            if (_selectedBackupMode == _BackupMode.custom) ...[
              _BackupOptionTile(
                icon: FluentIcons.settings_24_regular,
                title: context.settingsText('הגדרות'),
                subtitle: context.settingsText('כולל את כלל הגדרות התוכנה'),
                settingKey: _keyBackupSettings,
                onChanged: () => setState(() {}),
              ),
              _BackupOptionTile(
                icon: FluentIcons.bookmark_24_regular,
                title: context.settingsText('סימניות'),
                subtitle: context.settingsText('כל הסימניות שנשמרו'),
                settingKey: _keyBackupBookmarks,
                onChanged: () => setState(() {}),
              ),
              _BackupOptionTile(
                icon: FluentIcons.history_24_regular,
                title: context.settingsText('היסטוריה'),
                subtitle: context.settingsText('היסטוריית הלימוד'),
                settingKey: _keyBackupHistory,
                onChanged: () => setState(() {}),
              ),
              _BackupOptionTile(
                icon: FluentIcons.note_24_regular,
                title: context.settingsText('הערות אישיות'),
                subtitle: context.settingsText('כל ההערות האישיות שלך'),
                settingKey: _keyBackupNotes,
                onChanged: () => setState(() {}),
              ),
              _BackupOptionTile(
                icon: FluentIcons.grid_24_regular,
                title: context.settingsText('שולחנות עבודה'),
                subtitle: context.settingsText('כל שולחנות העבודה'),
                settingKey: _keyBackupWorkspaces,
                onChanged: () => setState(() {}),
              ),
              _BackupOptionTile(
                icon: OtzariaIcons.book_24_regular,
                title: context.settingsText('שמור וזכור'),
                subtitle: context.settingsText('ספרים ומעקב לימוד'),
                settingKey: _keyBackupShamorZachor,
                onChanged: () => setState(() {}),
              ),
              // [EDITING DISABLED]
              // _BackupOptionTile(
              //   icon: FluentIcons.document_edit_24_regular,
              //   title: 'הגדרות מתקדמות',
              //   subtitle: 'הגדרות נוספות שדרסת',
              //   settingKey: _keyBackupUserOverrides,
              //   onChanged: () => setState(() {}),
              // ),
              _BackupOptionTile(
                icon: FluentIcons.puzzle_piece_24_regular,
                title: context.settingsText('תוספים'),
                subtitle: context.settingsText(
                  'התוספים שהותקנו, הגדרותיהם ונתוניהם',
                ),
                settingKey: _keyBackupPlugins,
                onChanged: () => setState(() {}),
              ),
            ],
            SettingsActionTile.text(
              icon: FluentIcons.broom_24_regular,
              title: context.settingsText('ניקוי גיבויים ישנים'),
              subtitle: _buildOverviewSubtitle(retentionProfile),
              actions: [
                AppDropdownField<String>(
                  value: retentionProfile.name,
                  isExpanded: false,
                  entries: [
                    AppMenuEntry(
                      value: 'economy',
                      label: context.settingsText('חסכוני'),
                    ),
                    AppMenuEntry(
                      value: 'balanced',
                      label: context.settingsText('מאוזן'),
                    ),
                    AppMenuEntry(
                      value: 'keepAll',
                      label: context.settingsText('שמור הכל'),
                    ),
                  ],
                  onSelected: (value) {
                    if (value == null) return;
                    Settings.setValue<String>(
                      BackupMaintenance.keyRetentionProfile,
                      value,
                    );
                    setState(() {});
                  },
                ),
                ActionButton.neutral(
                  text: context.settingsText('נקה עכשיו'),
                  isLoading: _isRunningMaintenance,
                  onPressed: _runMaintenanceNow,
                ),
              ],
            ),
          ],
        ),

        // ── מצב סייפר ──
        if (hasPassword)
          SettingsActionTile.switchTile(
            icon: state.protectedModeEnabled
                ? FluentIcons.shield_lock_24_filled
                : FluentIcons.shield_lock_24_regular,
            iconColor: state.protectedModeEnabled
                ? Theme.of(context).colorScheme.primary
                : null,
            title: context.settingsText('מצב סייפר'),
            subtitle: context.settingsText(
              state.protectedModeEnabled
                  ? 'נעילת ההגדרות וסייר הקבצים פעילה'
                  : 'נעילת ההגדרות וסייר הקבצים מושבתת',
            ),
            value: state.protectedModeEnabled,
            onChanged: (value) =>
                _handleToggleProtectedMode(context, repository, value),
          )
        else
          SettingsActionTile.text(
            icon: FluentIcons.shield_lock_24_regular,
            title: context.settingsText('מצב סייפר'),
            subtitle: context.settingsText(
              'נעילת הגדרות וסייר הקבצים, יש להגדיר סיסמה תחילה',
            ),
            actions: [
              ActionButton.recommended(
                icon: FluentIcons.key_24_regular,
                text: context.settingsText('בחר סיסמה'),
                onPressed: () => _handleSetPassword(
                  context,
                  repository,
                  hasPassword,
                  state.protectedModeEnabled,
                ),
              ),
            ],
          ),
        if (hasPassword)
          SettingsActionTile.text(
            icon: FluentIcons.key_24_regular,
            title: context.settingsText('סיסמה'),
            subtitle: context.settingsText(
              'סיסמה הוגדרה, ניתן לשנות או למחוק את הסיסמה',
            ),
            actions: [
              ActionButton.recommended(
                icon: FluentIcons.key_24_regular,
                text: context.settingsText('אפשרויות'),
                onPressed: () => _handleSetPassword(
                  context,
                  repository,
                  hasPassword,
                  state.protectedModeEnabled,
                ),
              ),
            ],
          ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  //  6. איפוס
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildResetSection(BuildContext context) {
    return SettingsCard(
      cardId: 'system.reset',
      title: context.settingsText('איפוס'),
      children: [
        SettingsActionTile.text(
          icon: FluentIcons.arrow_reset_24_regular,
          title: context.settingsText('איפוס הגדרות'),
          subtitle: context.settingsText('מחיקת כל ההגדרות וחזרה למצב ההתחלתי'),
          actions: [
            ActionButton.ghost(
              icon: FluentIcons.arrow_reset_24_regular,
              text: context.settingsText('אפס הגדרות'),
              onPressed: () async {
                if (!await verifySaferModePassword(context)) return;
                if (!context.mounted) return;

                final confirmed = await showWarningDialog(
                  context: context,
                  title: context.settingsText('איפוס הגדרות?'),
                  content: context.settingsText(
                    'כל ההגדרות האישיות שלך ימחקו.',
                  ),
                  subtitle: context.settingsText('פעולה זו אינה הפיכה!'),
                  cancelText: context.settingsText('ביטול'),
                  confirmText: context.settingsText('אפס'),
                );
                if (confirmed == true && mounted) {
                  await HiveCache.clearAllPreferences();
                  await resetRuntimeStateAfterSettingsReset();
                  if (!mounted) return;
                  RestartWidget.restartApp(
                    this.context,
                    afterRestart: WebViewEnvironmentHolder.disposeForAppRestart,
                  );
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  // ── Changelog dialogs ──────────────────────────────────────────────────────

  Future<void> _showChangelogDialog(BuildContext context) async {
    final notFoundText = context.settingsText('לא נמצא קובץ יומן שינויים.');
    String changelog;
    try {
      changelog = await rootBundle.loadString('assets/יומן שינויים.md');
    } catch (_) {
      changelog = notFoundText;
    }
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: settingsDialogBuilder(
        context,
        (ctx) => AlertDialog(
          title: Text(ctx.settingsText('יומן שינויים בתוכנה')),
          content: SizedBox(
            width: 600,
            height: 400,
            // Markdown הגלילתי אומד את היקף התוכן מהפריטים הבנויים בלבד
            // והאגודל "רוקד" בגלילה; היקף מדויק דרך SingleChildScrollView.
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: MarkdownBody(
                data: changelog,
                onTapLink: (text, href, title) {
                  if (href != null) launchUrl(Uri.parse(href));
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.settingsText('סגור')),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  כרטיסי זיכרון — עיצוב נקי ורספונסיבי למסכים, תואם M3
// ══════════════════════════════════════════════════════════════════════════════

class _PendingReportEditValues {
  final String selectedText;
  final String errorDetails;
  final String contextText;

  const _PendingReportEditValues({
    required this.selectedText,
    required this.errorDetails,
    required this.contextText,
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
    );
  }
}

class _PendingReportEditFields extends StatefulWidget {
  final _PendingReportEditValues initialValues;
  final ValueChanged<_PendingReportEditValues> onChanged;

  const _PendingReportEditFields({
    required this.initialValues,
    required this.onChanged,
  });

  @override
  State<_PendingReportEditFields> createState() =>
      _PendingReportEditFieldsState();
}

class _PendingReportEditFieldsState extends State<_PendingReportEditFields> {
  late final TextEditingController _selectedTextController;
  late final TextEditingController _detailsController;
  late final TextEditingController _contextController;

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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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

// ── _BackupOptionTile ─────────────────────────────────────────────────────────

class _BackupOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String settingKey;
  final VoidCallback onChanged;

  const _BackupOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.settingKey,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsActionTile.switchTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      value: Settings.getValue<bool>(settingKey) ?? true,
      onChanged: (value) {
        Settings.setValue<bool>(settingKey, value);
        onChanged();
      },
    );
  }
}

enum _BackupMode { all, custom }
