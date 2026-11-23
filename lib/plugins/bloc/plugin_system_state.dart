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
  final bool isUserInitiated;

  const PluginSystemOverwriteRequired({
    required this.archivePath,
    required this.pluginName,
    required this.version,
    this.isUserInitiated = false,
  });

  @override
  List<Object?> get props => [
    archivePath,
    pluginName,
    version,
    isUserInitiated,
  ];
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

  const PluginSystemDevInstallRequiresPermissions({
    required this.manifest,
    required this.sourcePath,
    required this.sourceType,
    this.previousVersion,
  });

  @override
  List<Object?> get props => [
    manifest,
    sourcePath,
    sourceType,
    previousVersion,
  ];
}

class PluginSystemInstallRequiresPermissions extends PluginSystemState {
  final PluginManifest manifest;
  final String tempDirPath;

  /// גרסה מותקנת קודמת — null אם זו התקנה ראשונה.
  final String? previousVersion;

  /// החלטות ההרשאה השמורות של הגרסה המותקנת. הרשאה שאינה במפה היא חדשה.
  final Map<String, bool> previousGrantedPermissions;
  final PluginInstallReportContext? reportContext;

  /// ההתקנה נדרשה מממשק התוכנה עצמו ולא מתוסף או מקישור חיצוני.
  final bool isUserInitiated;

  /// מזהה החבילה צריך להיות פנוי גם בעת השמירה.
  final bool requireNewInstallation;

  const PluginSystemInstallRequiresPermissions({
    required this.manifest,
    required this.tempDirPath,
    this.previousVersion,
    this.previousGrantedPermissions = const {},
    this.reportContext,
    this.isUserInitiated = false,
    this.requireNewInstallation = false,
  });

  @override
  List<Object?> get props => [
    manifest,
    tempDirPath,
    previousVersion,
    previousGrantedPermissions,
    reportContext?.token,
    reportContext?.callbackUrl,
    isUserInitiated,
    requireNewInstallation,
  ];
}
