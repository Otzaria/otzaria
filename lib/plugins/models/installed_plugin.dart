import 'dart:convert';
import 'package:otzaria/plugins/models/plugin_manifest.dart';

class InstalledPlugin {
  final String pluginId;
  final String name;
  final String version;
  final String installPath;
  final String entrypointPath;
  final String? iconPath;
  final bool enabled;
  final bool pinned;
  final bool pinnedToNavRail;
  final PluginManifest manifest;
  final DateTime installedAt;
  final DateTime updatedAt;
  final String sourceType;
  final String? devRootPath;

  bool get isDevelopment => sourceType == 'development';
  String get resolvedRootPath => isDevelopment ? devRootPath! : installPath;

  /// האם התוסף מצהיר על שימוש ברשת. תוסף כזה מוסתר מהממשק כאשר אוצריא נמצאת
  /// במצב 'מנותק' (`SettingsState.isOfflineMode`).
  bool get requiresNetwork => manifest.networkEnabled;

  InstalledPlugin({
    required this.pluginId,
    required this.name,
    required this.version,
    required this.installPath,
    required this.entrypointPath,
    this.iconPath,
    required this.enabled,
    required this.pinned,
    this.pinnedToNavRail = false,
    required this.manifest,
    required this.installedAt,
    required this.updatedAt,
    this.sourceType = 'packaged',
    this.devRootPath,
  });

  factory InstalledPlugin.fromDbMap(Map<String, dynamic> map) {
    return InstalledPlugin(
      pluginId: map['plugin_id'] as String,
      name: map['name'] as String,
      version: map['version'] as String,
      installPath: map['install_path'] as String,
      entrypointPath: map['entrypoint_path'] as String,
      iconPath: map['icon_path'] as String?,
      enabled: (map['enabled'] as int) != 0,
      pinned: (map['pinned'] as int) != 0,
      pinnedToNavRail: ((map['pinned_to_nav_rail'] as int?) ?? 0) != 0,
      manifest: PluginManifest.fromJson(jsonDecode(map['manifest_json'] as String)),
      installedAt: DateTime.parse(map['installed_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      sourceType: map['source_type'] as String? ?? 'packaged',
      devRootPath: map['dev_root_path'] as String?,
    );
  }

  Map<String, dynamic> toDbMap() {
    return {
      'plugin_id': pluginId,
      'name': name,
      'version': version,
      'install_path': installPath,
      'entrypoint_path': entrypointPath,
      'icon_path': iconPath,
      'enabled': enabled ? 1 : 0,
      'pinned': pinned ? 1 : 0,
      'pinned_to_nav_rail': pinnedToNavRail ? 1 : 0,
      'manifest_json': jsonEncode(manifest.toJson()),
      'installed_at': installedAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'source_type': sourceType,
      'dev_root_path': devRootPath,
    };
  }

  InstalledPlugin copyWith({
    String? pluginId,
    String? name,
    String? version,
    String? installPath,
    String? entrypointPath,
    String? iconPath,
    bool? enabled,
    bool? pinned,
    bool? pinnedToNavRail,
    PluginManifest? manifest,
    DateTime? installedAt,
    DateTime? updatedAt,
    String? sourceType,
    String? devRootPath,
    bool clearDevRootPath = false,
  }) {
    return InstalledPlugin(
      pluginId: pluginId ?? this.pluginId,
      name: name ?? this.name,
      version: version ?? this.version,
      installPath: installPath ?? this.installPath,
      entrypointPath: entrypointPath ?? this.entrypointPath,
      iconPath: iconPath ?? this.iconPath,
      enabled: enabled ?? this.enabled,
      pinned: pinned ?? this.pinned,
      pinnedToNavRail: pinnedToNavRail ?? this.pinnedToNavRail,
      manifest: manifest ?? this.manifest,
      installedAt: installedAt ?? this.installedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sourceType: sourceType ?? this.sourceType,
      devRootPath: clearDevRootPath ? null : (devRootPath ?? this.devRootPath),
    );
  }
}

/// סינון תוספים לפי מצב 'מנותק' של אוצריא — תוספים שדורשים אינטרנט מוסתרים
/// מהממשק כאשר המשתמש הפעיל את מצב 'מנותק'.
extension OfflineModePluginFilter on List<InstalledPlugin> {
  List<InstalledPlugin> filterForOfflineMode(bool isOfflineMode) {
    if (!isOfflineMode) return this;
    return where((p) => !p.requiresNetwork).toList();
  }
}
