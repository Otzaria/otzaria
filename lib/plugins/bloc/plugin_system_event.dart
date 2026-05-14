import 'package:equatable/equatable.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';

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

  const InstallRemotePluginRequested(
    this.downloadUrl, {
    this.forceOverwrite = false,
  });

  @override
  List<Object?> get props => [downloadUrl, forceOverwrite];
}

class ConfirmPluginInstall extends PluginSystemEvent {
  final String tempDirPath;
  final PluginManifest manifest;

  /// מיפוי הרשאה → האם הוענקה. הרשאות עם ערך false יישמרו כחסומות.
  final Map<String, bool> grantedPermissions;

  const ConfirmPluginInstall(
      this.tempDirPath, this.manifest, this.grantedPermissions);

  @override
  List<Object?> get props => [tempDirPath, manifest, grantedPermissions];
}

class CancelPluginInstall extends PluginSystemEvent {
  final String tempDirPath;
  const CancelPluginInstall(this.tempDirPath);

  @override
  List<Object?> get props => [tempDirPath];
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
