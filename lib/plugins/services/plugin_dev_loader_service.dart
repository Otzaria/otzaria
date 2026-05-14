import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_manifest_validator.dart';

class PluginDevLoaderService {
  final PluginRegistryRepository _repository;

  PluginDevLoaderService({PluginRegistryRepository? repository})
      : _repository = repository ?? PluginRegistryRepository();

  Future<void> loadDevelopmentPlugin(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) {
      throw Exception('תיקיית התוסף לא נמצאה: $directoryPath');
    }

    final manifestFile = File(p.join(directoryPath, 'manifest.json'));
    if (!manifestFile.existsSync()) {
      throw Exception('manifest.json לא נמצא בתיקיית התוסף');
    }

    final manifestStr = manifestFile.readAsStringSync();
    final manifestJson = jsonDecode(manifestStr);
    final manifest = PluginManifest.fromJson(manifestJson);

    final packageInfo = await PackageInfo.fromPlatform();

    await PluginManifestValidator.validateManifest(
      manifest: manifest,
      directoryPath: directoryPath,
      currentAppVersion: packageInfo.version,
    );

    final existingPlugin = await _repository.getPlugin(manifest.id);
    if (existingPlugin != null && !existingPlugin.isDevelopment) {
      throw Exception('כבר קיים תוסף מותקן (רגיל) עם אותו מזהה. מחק או שנה id.');
    }

    final plugin = InstalledPlugin(
      pluginId: manifest.id,
      name: manifest.name,
      version: manifest.version,
      installPath: directoryPath, 
      entrypointPath: manifest.entrypoint,
      iconPath: manifest.icon,
      enabled: existingPlugin?.enabled ?? true,
      pinned: existingPlugin?.pinned ?? manifest.defaultPinned,
      pinnedToNavRail: existingPlugin?.pinnedToNavRail ?? false,
      manifest: manifest,
      installedAt: existingPlugin?.installedAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      sourceType: 'development',
      devRootPath: directoryPath,
    );

    await _repository.saveDevelopmentPlugin(plugin);

    final existingGrants = <String, bool>{};
    if (existingPlugin != null) {
      for (final perm in existingPlugin.manifest.permissions) {
        final granted = await _repository.getPermission(manifest.id, perm);
        if (granted != null) existingGrants[perm] = granted;
      }
      for (final oldPerm in existingPlugin.manifest.permissions) {
        if (!manifest.permissions.contains(oldPerm)) {
          await _repository.setPermission(manifest.id, oldPerm, false);
        }
      }
    }
    for (final perm in manifest.permissions) {
      if (existingGrants.containsKey(perm)) continue;
      await _repository.setPermission(manifest.id, perm, true);
    }
  }
}
