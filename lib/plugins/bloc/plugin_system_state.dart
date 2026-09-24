import 'package:equatable/equatable.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_install_report_service.dart';

sealed class PluginSystemState extends Equatable {
  const PluginSystemState();

  @override
  List<Object?> get props => [];
}

class PluginSystemInitial extends PluginSystemState {}

class PluginSystemLoading extends PluginSystemState {}

class PluginSystemLoaded extends PluginSystemState {
  final List<InstalledPlugin> plugins;

  const PluginSystemLoaded(this.plugins);

  @override
  List<Object?> get props => [plugins];

  List<InstalledPlugin> get activePlugins =>
      plugins.where((p) => p.enabled).toList();

  /// תוספים שמקבלים לשונית קבועה במסך "כלים". תוסף שהוצמד לסרגל הניווט
  /// הראשי (pinnedToNavRail) מקבל שם מקום משלו, ולכן מוחרג כאן כדי שלא
  /// יתפוס גם לשונית בכלים — הצגה כפולה מיותרת.
  List<InstalledPlugin> get pinnedPlugins => plugins
      .where(
        (p) =>
            p.pinned &&
            p.enabled &&
            p.showInTools &&
            p.hasToolPage &&
            !p.pinnedToNavRail,
      )
      .toList();
  List<InstalledPlugin> get pluginsPinnedToNavRail => plugins
      .where((p) => p.pinnedToNavRail && p.enabled && p.hasToolPage)
      .toList();
}

class PluginSystemError extends PluginSystemState {
  final String message;

  const PluginSystemError(this.message);

  @override
  List<Object?> get props => [message];
}

class PluginSystemOverwriteRequired extends PluginSystemState {
  final String archivePath;
  final String pluginName;
  final String version;

  const PluginSystemOverwriteRequired({
    required this.archivePath,
    required this.pluginName,
    required this.version,
  });

  @override
  List<Object?> get props => [archivePath, pluginName, version];
}

/// אחרי התקנה שהושלמה: נמצאו תוספים מותקנים אחרים בעלי אותו שם אך מזהה שונה
/// (למשל גרסה ישנה שהמפתח שינה לה את ה-id). הממשק שואל אם להסיר אותם —
/// אחרת המשתמש נשאר עם שני "אותם" תוספים, והישן מוצג לו כעדכון לנצח.
class PluginSystemDuplicateNameDetected extends PluginSystemState {
  /// התוסף שהותקן זה עתה.
  final String installedPluginId;
  final String pluginName;
  final String installedVersion;

  /// התוספים הישנים באותו שם — המועמדים להסרה.
  final List<InstalledPlugin> duplicates;

  const PluginSystemDuplicateNameDetected({
    required this.installedPluginId,
    required this.pluginName,
    required this.installedVersion,
    required this.duplicates,
  });

  @override
  List<Object?> get props => [
    installedPluginId,
    pluginName,
    installedVersion,
    duplicates.map((p) => '${p.pluginId}@${p.version}').toList(),
  ];
}

/// מצב המופעל כאשר תוסף פיתוח (תיקייה או localhost) מותקן לראשונה —
/// מציג דיאלוג הרשאות זהה לתוסף ארוז, ללא tempDir.
class PluginSystemDevInstallRequiresPermissions extends PluginSystemState {
  final PluginManifest manifest;

  /// נתיב תיקייה (sourceType='development') או URL (sourceType='localhost_dev').
  final String sourcePath;
  final String sourceType;
  final String? previousVersion;
  final bool? previousAllowOrderBeforeBuiltInsGranted;

  const PluginSystemDevInstallRequiresPermissions({
    required this.manifest,
    required this.sourcePath,
    required this.sourceType,
    this.previousVersion,
    this.previousAllowOrderBeforeBuiltInsGranted,
  });

  bool get isUpdate => previousVersion != null;

  @override
  List<Object?> get props => [
    manifest,
    sourcePath,
    sourceType,
    previousVersion,
    previousAllowOrderBeforeBuiltInsGranted,
  ];
}

class PluginSystemInstallRequiresPermissions extends PluginSystemState {
  final PluginManifest manifest;
  final String tempDirPath;

  /// גרסה מותקנת קודמת — null אם זו התקנה ראשונה.
  final String? previousVersion;
  final bool? previousAllowOrderBeforeBuiltInsGranted;

  /// החלטות ההרשאה השמורות של הגרסה המותקנת. הרשאה שאינה במפה היא חדשה.
  final Map<String, bool> previousGrantedPermissions;
  final PluginInstallReportContext? reportContext;

  /// ההתקנה נדרשה מממשק התוכנה עצמו ולא מתוסף או מקישור חיצוני.
  final bool isUserInitiated;

  const PluginSystemInstallRequiresPermissions({
    required this.manifest,
    required this.tempDirPath,
    this.previousVersion,
    this.previousAllowOrderBeforeBuiltInsGranted,
    this.previousGrantedPermissions = const {},
    this.reportContext,
    this.isUserInitiated = false,
  });

  bool get isUpdate => previousVersion != null;

  @override
  List<Object?> get props => [
    manifest,
    tempDirPath,
    previousVersion,
    previousAllowOrderBeforeBuiltInsGranted,
    previousGrantedPermissions,
    reportContext?.token,
    reportContext?.callbackUrl,
    isUserInitiated,
  ];
}
