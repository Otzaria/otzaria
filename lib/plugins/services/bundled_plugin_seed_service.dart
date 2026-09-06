import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/bundled_plugin_ids.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;

/// רושמת את התוספים שחבילת ההתקנה ארזה, כדי שיהיו מותקנים כבר בפתיחה
/// הראשונה. בדסקטופ הארכיונים יושבים ליד ה-executable (במק ב-Contents/
/// Resources); במובייל אין תיקייה
/// כזו והם נארזים כ-assets בתוך החבילה. ראה docs/bundled_plugins.md.
class BundledPluginSeedService {
  /// מבחין בין "לא הועבר" (ברירת המחדל של הפלטפורמה) לבין `null` מפורש
  /// (מצב assets) — נדרש לבדיקות שרצות על דסקטופ ומדמות מובייל.
  static const Object _defaultBundleDir = Object();

  /// תיקיית ה-assets של הארכיונים במובייל — חייבת להתאים ל-pubspec.yaml.
  static const String bundledPluginsAssetDir = 'assets/bundled_plugins';

  final PluginRegistryRepository _repository;
  final PluginInstallerService _installerService;
  final Set<String> _allowedIds;
  final String? _bundleDirPath;
  final AssetBundle _assetBundle;

  BundledPluginSeedService({
    PluginRegistryRepository? repository,
    PluginInstallerService? installerService,
    Set<String>? allowedIds,
    Object? bundleDirPath = _defaultBundleDir,
    AssetBundle? assetBundle,
  }) : _repository = repository ?? PluginRegistryRepository(),
       _installerService =
           installerService ?? PluginInstallerService(repository: repository),
       // הזהות בצד האפליקציה היא מזהי המניפסט; מזהי החנות משמשים רק להורדה.
       _allowedIds =
           allowedIds ?? bundledPluginIdsForPlatform(Platform.operatingSystem),
       _bundleDirPath = identical(bundleDirPath, _defaultBundleDir)
           ? AppPaths.getBundledPluginsPath()
           : bundleDirPath as String?,
       _assetBundle = assetBundle ?? rootBundle;

  /// מחזירה `true` אם נרשם תוסף חדש — ואז על הקורא לרענן את רשימת התוספים.
  Future<bool> seedPending() async {
    if (_allowedIds.isEmpty) return false;

    final seeded = _readSeededIds();
    final initialSeededCount = seeded.length;
    var registered = false;
    Directory? assetStagingDir;

    try {
      for (final pluginId in _allowedIds) {
        if (seeded.contains(pluginId)) continue;

        // מותקן כבר (המשתמש הקדים אותנו) — מסמנים כמטופל בלי לגעת בהתקנה שלו.
        if (await _repository.getPlugin(pluginId) != null) {
          seeded.add(pluginId);
          continue;
        }

        final String archivePath;
        final bundleDir = _bundleDirPath;
        if (bundleDir != null) {
          final archive = File(p.join(bundleDir, '$pluginId.otzplugin'));
          if (!await archive.exists()) continue;
          archivePath = archive.path;
        } else {
          // מובייל: הארכיון נארז כ-asset ומועתק לקובץ זמני לצורך ההתקנה.
          assetStagingDir ??= await Directory.systemTemp.createTemp(
            'otz_bundled_assets_',
          );
          final staged = await _stageAssetArchive(pluginId, assetStagingDir);
          if (staged == null) continue;
          archivePath = staged;
        }

        if (await _install(pluginId, archivePath)) {
          seeded.add(pluginId);
          registered = true;
        }
      }
    } finally {
      if (assetStagingDir != null && assetStagingDir.existsSync()) {
        assetStagingDir.deleteSync(recursive: true);
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

  /// כותבת את ה-asset לקובץ זמני; `null` כשהארכיון לא נארז בחבילה זו.
  Future<String?> _stageAssetArchive(
    String pluginId,
    Directory stagingDir,
  ) async {
    try {
      final data = await _assetBundle.load(
        '$bundledPluginsAssetDir/$pluginId.otzplugin',
      );
      final file = File(p.join(stagingDir.path, '$pluginId.otzplugin'));
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      return file.path;
    } catch (_) {
      return null;
    }
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
