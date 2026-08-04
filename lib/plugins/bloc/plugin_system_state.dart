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
        (p) => p.pinned && p.enabled && p.showInTools && !p.pinnedToNavRail,
      )
      .toList();
  List<InstalledPlugin> get pluginsPinnedToNavRail =>
      plugins.where((p) => p.pinnedToNavRail && p.enabled).toList();
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
  final PluginInstallReportContext? reportContext;

  const PluginSystemInstallRequiresPermissions({
    required this.manifest,
    required this.tempDirPath,
    this.previousVersion,
    this.previousAllowOrderBeforeBuiltInsGranted,
    this.reportContext,
  });

  bool get isUpdate => previousVersion != null;

  @override
  List<Object?> get props => [
    manifest,
    tempDirPath,
    previousVersion,
    previousAllowOrderBeforeBuiltInsGranted,
    reportContext?.token,
    reportContext?.callbackUrl,
  ];
}
