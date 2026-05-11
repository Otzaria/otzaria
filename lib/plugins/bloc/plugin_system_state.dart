import 'package:equatable/equatable.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';

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
  
  List<InstalledPlugin> get activePlugins => plugins.where((p) => p.enabled).toList();
  List<InstalledPlugin> get pinnedPlugins => plugins.where((p) => p.pinned && p.enabled).toList();
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

class PluginSystemInstallRequiresPermissions extends PluginSystemState {
  final PluginManifest manifest;
  final String tempDirPath;
  /// גרסה מותקנת קודמת — null אם זו התקנה ראשונה.
  final String? previousVersion;

  const PluginSystemInstallRequiresPermissions({
    required this.manifest,
    required this.tempDirPath,
    this.previousVersion,
  });

  bool get isUpdate => previousVersion != null;

  @override
  List<Object?> get props => [manifest, tempDirPath, previousVersion];
}
