import 'package:equatable/equatable.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_install_report_service.dart';

sealed class PluginSystemEvent extends Equatable {
  const PluginSystemEvent();

  @override
  List<Object?> get props => [];
}

class LoadPlugins extends PluginSystemEvent {}

class InstallPluginRequested extends PluginSystemEvent {
  final String archivePath;
  final bool forceOverwrite;
  const InstallPluginRequested(this.archivePath, {this.forceOverwrite = false});

  @override
  List<Object?> get props => [archivePath, forceOverwrite];
}

class InstallRemotePluginRequested extends PluginSystemEvent {
  final String downloadUrl;
  final bool forceOverwrite;

  /// הקשר דיווח תוצאה חזרה לאתר החנות (טוקן + callback). null = ללא דיווח.
  final PluginInstallReportContext? reportContext;

  /// ההתקנה יזומה ע"י תוסף (`plugin.requestInstall`) ולא ע"י המשתמש. במצב
  /// כזה ההורדה מוגבלת למארחי החנות בכל hop, כולל אחרי redirect.
  final bool storeOnly;

  const InstallRemotePluginRequested(
    this.downloadUrl, {
    this.forceOverwrite = false,
    this.reportContext,
    this.storeOnly = false,
  });

  @override
  List<Object?> get props => [
    downloadUrl,
    forceOverwrite,
    reportContext?.token,
    reportContext?.callbackUrl,
      storeOnly,
  ];
}

class ConfirmPluginInstall extends PluginSystemEvent {
  final String tempDirPath;
  final PluginManifest manifest;

  /// מיפוי הרשאה → האם הוענקה. הרשאות עם ערך false יישמרו כחסומות.
  final Map<String, bool> grantedPermissions;
  final bool allowOrderBeforeBuiltInsGranted;
  final PluginInstallReportContext? reportContext;

  /// גרסה מותקנת קודמת — null אם זו התקנה ראשונה. נושא את ההבחנה מדיאלוג
  /// האישור אל הודעת הסיום ואל הדיווח לאתר.
  final String? previousVersion;

  const ConfirmPluginInstall(
    this.tempDirPath,
    this.manifest,
    this.grantedPermissions,
    this.allowOrderBeforeBuiltInsGranted, {
    this.reportContext,
    this.previousVersion,
  });

  bool get isUpdate => previousVersion != null;

  @override
  List<Object?> get props => [
    tempDirPath,
    manifest,
    grantedPermissions,
    allowOrderBeforeBuiltInsGranted,
    reportContext?.token,
    reportContext?.callbackUrl,
    previousVersion,
  ];
}

class CancelPluginInstall extends PluginSystemEvent {
  final String tempDirPath;
  final PluginInstallReportContext? reportContext;
  const CancelPluginInstall(this.tempDirPath, {this.reportContext});

  @override
  List<Object?> get props => [
    tempDirPath,
    reportContext?.token,
    reportContext?.callbackUrl,
  ];
}

class UninstallPluginRequested extends PluginSystemEvent {
  final String pluginId;
  const UninstallPluginRequested(this.pluginId);

  @override
  List<Object?> get props => [pluginId];
}

class EnablePluginRequested extends PluginSystemEvent {
  final String pluginId;
  const EnablePluginRequested(this.pluginId);

  @override
  List<Object?> get props => [pluginId];
}

class DisablePluginRequested extends PluginSystemEvent {
  final String pluginId;
  const DisablePluginRequested(this.pluginId);

  @override
  List<Object?> get props => [pluginId];
}

class SetPluginPermissionRequested extends PluginSystemEvent {
  final String pluginId;
  final String permission;
  final bool granted;

  const SetPluginPermissionRequested({
    required this.pluginId,
    required this.permission,
    required this.granted,
  });

  @override
  List<Object?> get props => [pluginId, permission, granted];
}

class PinPluginRequested extends PluginSystemEvent {
  final String pluginId;
  const PinPluginRequested(this.pluginId);

  @override
  List<Object?> get props => [pluginId];
}

class UnpinPluginRequested extends PluginSystemEvent {
  final String pluginId;
  const UnpinPluginRequested(this.pluginId);

  @override
  List<Object?> get props => [pluginId];
}

class PinPluginToNavRailRequested extends PluginSystemEvent {
  final String pluginId;
  const PinPluginToNavRailRequested(this.pluginId);

  @override
  List<Object?> get props => [pluginId];
}

class UnpinPluginFromNavRailRequested extends PluginSystemEvent {
  final String pluginId;
  const UnpinPluginFromNavRailRequested(this.pluginId);

  @override
  List<Object?> get props => [pluginId];
}

/// קובע האם תוסף מוצג במסך הכלים.
class SetPluginShowInToolsRequested extends PluginSystemEvent {
  final String pluginId;
  final bool showInTools;

  const SetPluginShowInToolsRequested({
    required this.pluginId,
    required this.showInTools,
  });

  @override
  List<Object?> get props => [pluginId, showInTools];
}

class ReorderPluginsRequested extends PluginSystemEvent {
  /// רשימת מזהי תוספים בסדר החדש שנקבע ע"י המשתמש.
  final List<String> orderedPluginIds;
  const ReorderPluginsRequested(this.orderedPluginIds);

  @override
  List<Object?> get props => [orderedPluginIds];
}

class RefreshPlugins extends PluginSystemEvent {}

class LoadDevelopmentPluginRequested extends PluginSystemEvent {
  final String directoryPath;
  const LoadDevelopmentPluginRequested(this.directoryPath);

  @override
  List<Object?> get props => [directoryPath];
}

class DetachDevelopmentPluginRequested extends PluginSystemEvent {
  final String pluginId;
  const DetachDevelopmentPluginRequested(this.pluginId);

  @override
  List<Object?> get props => [pluginId];
}

class ReloadDevelopmentPluginRequested extends PluginSystemEvent {
  final String pluginId;
  const ReloadDevelopmentPluginRequested(this.pluginId);

  @override
  List<Object?> get props => [pluginId];
}

class DevelopmentPluginManifestChanged extends PluginSystemEvent {
  final String pluginId;
  const DevelopmentPluginManifestChanged(this.pluginId);

  @override
  List<Object?> get props => [pluginId];
}

class ConfirmDevPluginInstall extends PluginSystemEvent {
  final PluginManifest manifest;
  final String sourcePath;
  final String sourceType;
  final Map<String, bool> grantedPermissions;
  final bool allowOrderBeforeBuiltInsGranted;

  /// גרסה מותקנת קודמת — null אם זו התקנה ראשונה.
  final String? previousVersion;

  const ConfirmDevPluginInstall({
    required this.manifest,
    required this.sourcePath,
    required this.sourceType,
    required this.grantedPermissions,
    required this.allowOrderBeforeBuiltInsGranted,
    this.previousVersion,
  });

  bool get isUpdate => previousVersion != null;

  @override
  List<Object?> get props => [
    manifest,
    sourcePath,
    sourceType,
    grantedPermissions,
    allowOrderBeforeBuiltInsGranted,
    previousVersion,
  ];
}

class LoadLocalhostPluginRequested extends PluginSystemEvent {
  final String baseUrl;
  const LoadLocalhostPluginRequested(this.baseUrl);

  @override
  List<Object?> get props => [baseUrl];
}
