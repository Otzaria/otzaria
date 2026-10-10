import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive_io.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/update/app_release_version.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_manifest_validator.dart';
import 'package:otzaria/plugins/services/plugin_extended_validator.dart';
import 'package:otzaria/plugins/utils/plugin_version_utils.dart';
import 'package:otzaria/plugins/services/plugin_crash_guard.dart';
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

  /// החלטת המשתמש על ההקדמה — null כשהמניפסט הקודם כלל לא ביקש אותה,
  /// שאם לא כן בקשה חדשה הייתה נראית כסירוב קודם.
  final bool? previousAllowOrderBeforeBuiltInsGranted;

  /// החלטות ההרשאה השמורות של הגרסה המותקנת. הרשאה שאינה במפה היא חדשה.
  final Map<String, bool> previousGrantedPermissions;

  PreparedInstall(
    this.manifest,
    this.tempDirPath,
    this.isOverwrite, {
    this.previousVersion,
    this.previousAllowOrderBeforeBuiltInsGranted,
    this.previousGrantedPermissions = const {},
  });
}

class PluginInstallerService {
  final PluginRegistryRepository _repository;

  PluginInstallerService({PluginRegistryRepository? repository})
    : _repository = repository ?? PluginRegistryRepository();

  Future<PreparedInstall> prepareInstall(
    String archivePath, {
    bool forceOverwrite = false,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('otz_plugin_');
    try {
      // 1. Extract zip to temp on a worker isolate to avoid blocking the UI.
      await Isolate.run(
        () => _extractPluginArchiveSync(archivePath, tempDir.path),
      );

      // 2. Read manifest
      final manifestFile = File(p.join(tempDir.path, 'manifest.json'));
      if (!await manifestFile.exists()) {
        throw Exception('manifest.json לא נמצא בחבילת התוסף');
      }

      final manifestJson = Map<String, dynamic>.from(
        jsonDecode(await manifestFile.readAsString()) as Map,
      );
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
        currentAppVersion: canonicalAppVersion(packageInfo),
      );
      final extendedReport = await Isolate.run(
        () => PluginExtendedValidator.validate(
          manifest: manifest,
          manifestJson: manifestJson,
          directoryPath: tempDir.path,
        ),
      );
      if (extendedReport.hasErrors) {
        throw Exception(extendedReport.errors.join('\n'));
      }

      final previousGrants = existingPlugin == null
          ? const <String, bool>{}
          : await _grantsFor(existingPlugin);

      return PreparedInstall(
        manifest,
        tempDir.path,
        isOverwrite,
        previousVersion: existingPlugin?.version,
        previousAllowOrderBeforeBuiltInsGranted:
            existingPlugin != null &&
                existingPlugin.manifest.allowOrderBeforeBuiltIns
            ? existingPlugin.allowOrderBeforeBuiltInsGranted
            : null,
        previousGrantedPermissions: previousGrants,
      );
    } catch (e) {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      rethrow;
    }
  }

  Future<void> finalizeInstall(
    String tempDirPath,
    PluginManifest manifest, {
    required bool allowOrderBeforeBuiltInsGranted,
    required Map<String, bool> grantedPermissions,
  }) async {
    final tempDir = Directory(tempDirPath);
    Directory? stagedInstallDir;
    var installCommitted = false;
    try {
      // הרשאות הבסיס אינן החלטות משתמש — ההשוואה מול הרשימה האפקטיבית.
      final requestedPermissions = effectiveManifestPermissions(
        manifest.permissions,
      ).toSet();
      if (grantedPermissions.keys
              .toSet()
              .difference(requestedPermissions)
              .isNotEmpty ||
          requestedPermissions
              .difference(grantedPermissions.keys.toSet())
              .isNotEmpty) {
        throw ArgumentError(
          'Permission decisions must exactly match manifest permissions',
        );
      }
      final existingPlugin = await _repository.getPlugin(manifest.id);

      final canonicalPath = await AppPaths.getPluginInstallPath(manifest.id);
      final installParent = Directory(p.dirname(canonicalPath));
      await installParent.create(recursive: true);
      stagedInstallDir = await installParent.createTemp('.release-');
      await _copyDirectory(tempDir, stagedInstallDir);

      // 4. Save to DB
      // לעדכון/התקנה-מחדש: שומרים את הסדר הידני של המשתמש.
      // להתקנה חדשה: אם כבר יש תוספים שסודרו ידנית, התוסף החדש מצטרף
      // בסוף הסדר — אחרת הוא היה נכנס *לפני* הבלוק המסודר (raw 900 < 1000+).
      final newUserOrder = existingPlugin != null
          ? existingPlugin.userOrder
          : await _repository.getNextUserOrderForNewPlugin();

      final plugin = InstalledPlugin(
        pluginId: manifest.id,
        name: manifest.name,
        version: manifest.version,
        installPath: stagedInstallDir.path,
        entrypointPath: manifest.entrypoint,
        iconPath: manifest.icon,
        enabled: existingPlugin?.enabled ?? true,
        pinned: existingPlugin?.pinned ?? manifest.defaultPinned,
        pinnedToNavRail: existingPlugin?.pinnedToNavRail ?? false,
        showInTools: existingPlugin?.showInTools ?? true,
        allowOrderBeforeBuiltInsGranted: allowOrderBeforeBuiltInsGranted,
        manifest: manifest,
        installedAt: existingPlugin?.installedAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
        userOrder: newUserOrder,
      );

      await _repository.savePluginWithPermissions(
        plugin,
        Map.unmodifiable(grantedPermissions),
      );
      installCommitted = true;

      final pluginInstallRoot = p.dirname(canonicalPath);
      final oldInstallDir =
          existingPlugin == null || existingPlugin.isDevelopment
          ? null
          : Directory(existingPlugin.installPath);
      if (oldInstallDir != null &&
          p.isWithin(pluginInstallRoot, oldInstallDir.path) &&
          !p.isWithin(oldInstallDir.path, stagedInstallDir.path) &&
          oldInstallDir.path != stagedInstallDir.path &&
          await oldInstallDir.exists()) {
        try {
          await oldInstallDir.delete(recursive: true);
        } catch (error) {
          debugPrint('Failed to remove previous plugin release: $error');
        }
      }

      // אם התוסף היה ב-quarantine (קרס בטעינה קודמת), שדרוג מוצלח מוריד אותו.
      await PluginCrashGuard.retry(manifest.id);
    } finally {
      if (!installCommitted &&
          stagedInstallDir != null &&
          await stagedInstallDir.exists()) {
        await stagedInstallDir.delete(recursive: true);
      }
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  /// החלטות ההרשאה השמורות של תוסף מותקן, מסוננות למניפסט שלו.
  Future<Map<String, bool>> _grantsFor(InstalledPlugin plugin) async {
    final grants = await _repository.getPluginPermissions(plugin.pluginId);
    return {
      for (final grant in grants)
        if (plugin.manifest.permissions.contains(grant.permission))
          grant.permission: grant.granted,
    };
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
        var newDirectory = Directory(
          p.join(destination.path, p.basename(entity.path)),
        );
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
      await _deletePluginDataDirs(pluginId);
    }
  }

  /// מאפס את התוסף למצב שלאחר התקנה: מוחק את הנתונים שאגר במסד ואת תיקיות
  /// ה-data וה-cache שלו. קבצי התוסף עצמו, ההרשאות והגדרות התצוגה נשארים.
  Future<void> resetPluginData(String pluginId) async {
    await _repository.clearPluginData(pluginId);
    await _deletePluginDataDirs(pluginId);
  }

  Future<void> _deletePluginDataDirs(String pluginId) async {
    final dataPath = await AppPaths.getPluginDataPath(pluginId);
    final cachePath = await AppPaths.getPluginCachePath(pluginId);
    final dataDir = Directory(dataPath);
    if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
    final cacheDir = Directory(cachePath);
    if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
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
