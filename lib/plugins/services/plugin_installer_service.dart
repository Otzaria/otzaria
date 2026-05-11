import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_manifest_validator.dart';
import 'package:otzaria/plugins/utils/plugin_version_utils.dart';
import 'dart:isolate';

class PluginOverwriteException implements Exception {
  final String pluginName;
  final String version;
  PluginOverwriteException(this.pluginName, this.version);
}

class PluginNewerVersionInstalledException implements Exception {
  final String pluginName;
  final String requestedVersion;
  final String installedVersion;

  PluginNewerVersionInstalledException(
    this.pluginName,
    this.requestedVersion,
    this.installedVersion,
  );
}

class PreparedInstall {
  final PluginManifest manifest;
  final String tempDirPath;
  final bool isOverwrite;
  /// גרסה מותקנת קודמת — null אם זו התקנה ראשונה.
  final String? previousVersion;

  PreparedInstall(this.manifest, this.tempDirPath, this.isOverwrite,
      {this.previousVersion});
}

class PluginInstallerService {
  final PluginRegistryRepository _repository;

  PluginInstallerService({PluginRegistryRepository? repository})
      : _repository = repository ?? PluginRegistryRepository();

  Future<PreparedInstall> prepareInstall(String archivePath,
      {bool forceOverwrite = false}) async {
    final tempDir = await Directory.systemTemp.createTemp('otz_plugin_');
    try {
      // 1. Extract zip to temp on a worker isolate to avoid blocking the UI.
      await Isolate.run(
          () => _extractPluginArchiveSync(archivePath, tempDir.path));

      // 2. Read manifest
      final manifestFile = File(p.join(tempDir.path, 'manifest.json'));
      if (!await manifestFile.exists()) {
        throw Exception('manifest.json לא נמצא בחבילת התוסף');
      }

      final manifestJson = jsonDecode(await manifestFile.readAsString());
      final manifest = PluginManifest.fromJson(manifestJson);

      bool isOverwrite = false;
      final existingPlugin = await _repository.getPlugin(manifest.id);
      if (existingPlugin != null) {
        final diff = PluginVersionUtils.compareCoreVersions(
          manifest.version,
          existingPlugin.version,
        );
        if (diff < 0) {
          throw PluginNewerVersionInstalledException(
            manifest.name,
            manifest.version,
            existingPlugin.version,
          );
        } else if (diff == 0 && !forceOverwrite) {
          throw PluginOverwriteException(manifest.name, manifest.version);
        }
        isOverwrite = true;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      await PluginManifestValidator.validateManifest(
        manifest: manifest,
        directoryPath: tempDir.path,
        currentAppVersion: packageInfo.version,
      );

      return PreparedInstall(manifest, tempDir.path, isOverwrite,
          previousVersion: existingPlugin?.version);
    } catch (e) {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<void> finalizeInstall(
      String tempDirPath, PluginManifest manifest) async {
    final tempDir = Directory(tempDirPath);
    try {
      final existingPlugin = await _repository.getPlugin(manifest.id);

      // 3. Move to install path
      final installPath = await AppPaths.getPluginInstallPath(manifest.id);
      final installDir = Directory(installPath);
      if (await installDir.exists()) {
        await installDir.delete(recursive: true);
      }
      await installDir.create(recursive: true);

      // We move files by copying
      await _copyDirectory(tempDir, installDir);

      // 4. Save to DB
      final plugin = InstalledPlugin(
        pluginId: manifest.id,
        name: manifest.name,
        version: manifest.version,
        installPath: installPath,
        entrypointPath: manifest.entrypoint,
        iconPath: manifest.icon,
        enabled: existingPlugin?.enabled ?? true,
        pinned: existingPlugin?.pinned ?? manifest.defaultPinned,
        pinnedToNavRail: existingPlugin?.pinnedToNavRail ?? false,
        manifest: manifest,
        installedAt: existingPlugin?.installedAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _repository.savePlugin(plugin);

      // Seed grants: for new installs, grant all. For updates:
      // - Only grant permissions that did NOT previously have an explicit decision.
      //   This preserves user revokes across updates.
      // - Remove grants for permissions that no longer exist in the new manifest.
      final existingGrants = <String, bool>{};
      if (existingPlugin != null) {
        for (final perm in existingPlugin.manifest.permissions) {
          final granted = await _repository.getPermission(manifest.id, perm);
          if (granted != null) existingGrants[perm] = granted;
        }
        // Clean up grants for permissions removed from the new manifest.
        for (final oldPerm in existingPlugin.manifest.permissions) {
          if (!manifest.permissions.contains(oldPerm)) {
            await _repository.setPermission(manifest.id, oldPerm, false);
          }
        }
      }
      for (final perm in manifest.permissions) {
        // If user already made a decision on this permission, keep it.
        if (existingGrants.containsKey(perm)) continue;
        await _repository.setPermission(manifest.id, perm, true);
      }
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  Future<void> cancelInstall(String tempDirPath) async {
    final tempDir = Directory(tempDirPath);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await for (var entity in source.list(recursive: false)) {
      if (entity is Directory) {
        var newDirectory =
            Directory(p.join(destination.path, p.basename(entity.path)));
        await newDirectory.create(recursive: true);
        await _copyDirectory(entity.absolute, newDirectory);
      } else if (entity is File) {
        await entity.copy(p.join(destination.path, p.basename(entity.path)));
      }
    }
  }

  Future<void> uninstallPlugin(String pluginId) async {
    final plugin = await _repository.getPlugin(pluginId);
    if (plugin != null) {
      await _repository.deletePlugin(pluginId);
      final installDir = Directory(plugin.installPath);
      if (installDir.existsSync()) {
        installDir.deleteSync(recursive: true);
      }
      final dataPath = await AppPaths.getPluginDataPath(pluginId);
      final cachePath = await AppPaths.getPluginCachePath(pluginId);
      final dataDir = Directory(dataPath);
      if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
      final cacheDir = Directory(cachePath);
      if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
    }
  }
}

void _extractPluginArchiveSync(String archivePath, String tempDirPath) {
  final bytes = File(archivePath).readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);

  for (final file in archive) {
    final filename = file.name;
    final targetPath = p.normalize(p.join(tempDirPath, filename));
    if (!p.isWithin(tempDirPath, targetPath)) {
      throw Exception('נתיב חולץ מקובץ ZIP באופן לא חוקי: $filename');
    }

    if (file.isFile) {
      final data = file.content as List<int>;
      File(targetPath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(data);
    } else {
      Directory(targetPath).createSync(recursive: true);
    }
  }
}
