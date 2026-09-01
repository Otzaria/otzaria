import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/bundled_plugin_ids.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;

/// רושמת את התוספים שהמתקין ארז ליד ה-executable, כדי שיהיו מותקנים כבר
/// בפתיחה הראשונה. ראה docs/bundled_plugins.md.
class BundledPluginSeedService {
  final PluginRegistryRepository _repository;
  final PluginInstallerService _installerService;
  final Set<String> _allowedIds;
  final String? _bundleDirPath;

  BundledPluginSeedService({
    PluginRegistryRepository? repository,
    PluginInstallerService? installerService,
    Set<String>? allowedIds,
    String? bundleDirPath,
  }) : _repository = repository ?? PluginRegistryRepository(),
       _installerService =
           installerService ?? PluginInstallerService(repository: repository),
       _allowedIds = allowedIds ?? bundledPluginIds,
       _bundleDirPath = bundleDirPath ?? AppPaths.getBundledPluginsPath();

  /// מחזירה `true` אם נרשם תוסף חדש — ואז על הקורא לרענן את רשימת התוספים.
  Future<bool> seedPending() async {
    final bundleDir = _bundleDirPath;
    if (_allowedIds.isEmpty || bundleDir == null) return false;

    final seeded = _readSeededIds();
    final initialSeededCount = seeded.length;
    var registered = false;

    for (final pluginId in _allowedIds) {
      if (seeded.contains(pluginId)) continue;

      // מותקן כבר (המשתמש הקדים אותנו) — מסמנים כמטופל בלי לגעת בהתקנה שלו.
      if (await _repository.getPlugin(pluginId) != null) {
        seeded.add(pluginId);
        continue;
      }

      final archive = File(p.join(bundleDir, '$pluginId.otzplugin'));
      if (!await archive.exists()) continue;

      if (await _install(pluginId, archive.path)) {
        seeded.add(pluginId);
        registered = true;
      }
    }

    if (seeded.length != initialSeededCount) {
      await Settings.setValue<String>(
        SettingsRepository.keySeededBundledPlugins,
        seeded.join(','),
      );
    }
    return registered;
  }

  Future<bool> _install(String pluginId, String archivePath) async {
    try {
      final prepared = await _installerService.prepareInstall(archivePath);
      // המזהה שברשימת ההיתר הוא מה שאושר, לא שם הקובץ: ארכיון שמצהיר על
      // מזהה אחר נדחה, אחרת החלפת קובץ הייתה מתקינה תוסף שלא אושר.
      if (prepared.manifest.id != pluginId) {
        await _installerService.cancelInstall(prepared.tempDirPath);
        debugPrint(
          'Bundled plugin id mismatch: archive "$pluginId.otzplugin" '
          'declares "${prepared.manifest.id}"',
        );
        return false;
      }

      await _installerService.finalizeInstall(
        prepared.tempDirPath,
        prepared.manifest,
        allowOrderBeforeBuiltInsGranted:
            prepared.manifest.allowOrderBeforeBuiltIns,
        grantedPermissions: {
          for (final permission in effectiveManifestPermissions(
            prepared.manifest.permissions,
          ))
            permission: true,
        },
      );
      return true;
    } catch (e) {
      // כשל אינו מסומן כמטופל — ניסיון חוזר בעלייה הבאה. שקט בכוונה: המשתמש
      // לא ביקש את ההתקנה הזו ואין לו מה לעשות עם השגיאה.
      debugPrint('Bundled plugin seed failed [$pluginId]: $e');
      return false;
    }
  }

  Set<String> _readSeededIds() {
    final raw = Settings.getValue<String>(
      SettingsRepository.keySeededBundledPlugins,
      defaultValue: '',
    );
    return (raw ?? '')
        .split(',')
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
  }
}
