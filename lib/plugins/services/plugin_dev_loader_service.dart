import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_manifest_validator.dart';

bool _isLocalhostUri(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  final host = uri.host.toLowerCase();
  return host == 'localhost' || host == '127.0.0.1' || host == '::1';
}

class PluginDevLoaderService {
  final PluginRegistryRepository _repository;

  PluginDevLoaderService({PluginRegistryRepository? repository})
    : _repository = repository ?? PluginRegistryRepository();

  Future<void> _validateDevelopmentManifest(
    PluginManifest manifest,
    String directoryPath, {
    bool skipFileValidation = false,
  }) {
    // תוסף פיתוח פטור מבדיקת תאימות גרסה כדי לאפשר בדיקה מול גרסאות עתידיות.
    return PluginManifestValidator.validateManifest(
      manifest: manifest,
      directoryPath: directoryPath,
      skipFileValidation: skipFileValidation,
      skipAppVersionValidation: true,
    );
  }

  /// קורא את manifest.json מתיקייה ומאמת אותו. לא שומר לDB.
  Future<PluginManifest> fetchDevelopmentManifest(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) {
      throw Exception('תיקיית התוסף לא נמצאה: $directoryPath');
    }
    final manifestFile = File(p.join(directoryPath, 'manifest.json'));
    if (!manifestFile.existsSync()) {
      throw Exception('manifest.json לא נמצא בתיקיית התוסף');
    }
    final manifestStr = manifestFile.readAsStringSync();
    final manifest = PluginManifest.fromJson(jsonDecode(manifestStr));
    await _validateDevelopmentManifest(manifest, directoryPath);
    return manifest;
  }

  /// [preValidatedManifest] — מניפסט שכבר אומת (למשל, שהוצג בדיאלוג הרשאות).
  /// כשמסופק, אין קריאה חוזרת מהדיסק — מונע התקנת הרשאות שלא הוצגו למשתמש.
  Future<void> loadDevelopmentPlugin(
    String directoryPath, {
    PluginManifest? preValidatedManifest,
  }) async {
    final dir = Directory(directoryPath);
    if (!dir.existsSync()) {
      throw Exception('תיקיית התוסף לא נמצאה: $directoryPath');
    }

    final PluginManifest manifest;
    if (preValidatedManifest != null) {
      manifest = preValidatedManifest;
    } else {
      final manifestFile = File(p.join(directoryPath, 'manifest.json'));
      if (!manifestFile.existsSync()) {
        throw Exception('manifest.json לא נמצא בתיקיית התוסף');
      }
      final manifestStr = manifestFile.readAsStringSync();
      final manifestJson = jsonDecode(manifestStr);
      manifest = PluginManifest.fromJson(manifestJson);
      await _validateDevelopmentManifest(manifest, directoryPath);
    }

    final existingPlugin = await _repository.getPlugin(manifest.id);
    if (existingPlugin != null && !existingPlugin.isDevelopment) {
      throw Exception(
        'כבר קיים תוסף מותקן (רגיל) עם אותו מזהה. מחק או שנה id.',
      );
    }

    // טעינה-מחדש של תוסף פיתוח: שומרים את הסדר הידני.
    // טעינה ראשונה: אם כבר יש תוספים שסודרו ידנית, מצטרפים לסוף הסדר.
    final newUserOrder = existingPlugin != null
        ? existingPlugin.userOrder
        : await _repository.getNextUserOrderForNewPlugin();

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
      allowOrderBeforeBuiltInsGranted:
          existingPlugin?.allowOrderBeforeBuiltInsGranted ??
          manifest.allowOrderBeforeBuiltIns,
      manifest: manifest,
      installedAt: existingPlugin?.installedAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      sourceType: 'development',
      devRootPath: directoryPath,
      userOrder: newUserOrder,
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
      // הרשאה חדשה: בהתקנה ראשונה מאשרים (ConfirmDevPluginInstall ידרוס אחר כך),
      // בעדכון — שוללים כברירת מחדל עד שהמשתמש יאשר מפורשות.
      await _repository.setPermission(
        manifest.id,
        perm,
        existingPlugin == null,
      );
    }
  }

  /// טוען manifest.json מ-localhost ומאמת אותו. לא שומר לDB.
  Future<PluginManifest> fetchLocalhostManifest(String baseUrl) async {
    final normalizedUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');
    if (!_isLocalhostUri(normalizedUrl)) {
      throw Exception('כתובת localhost בלבד נתמכת (localhost / 127.0.0.1)');
    }
    final client = HttpClient();
    try {
      final HttpClientRequest request;
      try {
        request = await client.getUrl(
          Uri.parse('$normalizedUrl/manifest.json'),
        );
      } on SocketException {
        throw Exception('לא ניתן להתחבר ל-$normalizedUrl — ודא ששרת הפיתוח רץ');
      }
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception(
          'לא ניתן לטעון manifest.json — קוד שגיאה ${response.statusCode}',
        );
      }
      final manifestStr = await response.transform(const Utf8Decoder()).join();
      // SPA dev servers return index.html as fallback for unknown paths
      if (manifestStr.trimLeft().startsWith('<')) {
        throw Exception(
          'השרת החזיר HTML במקום manifest.json.\n'
          'הוסף את manifest.json לתיקיית הנכסים הסטטיים:\n'
          '• Vite: תיקיית public/\n'
          '• webpack: תיקיית static/ או CopyWebpackPlugin',
        );
      }
      final manifest = PluginManifest.fromJson(jsonDecode(manifestStr));
      await _validateDevelopmentManifest(
        manifest,
        normalizedUrl,
        skipFileValidation: true,
      );
      return manifest;
    } finally {
      client.close();
    }
  }

  /// [preValidatedManifest] — מניפסט שכבר אומת (למשל, שהוצג בדיאלוג הרשאות).
  /// כשמסופק, אין fetch חוזר מהשרת — מונע התקנת הרשאות שלא הוצגו למשתמש.
  Future<void> loadLocalhostPlugin(
    String baseUrl, {
    PluginManifest? preValidatedManifest,
  }) async {
    final normalizedUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final manifest =
        preValidatedManifest ?? await fetchLocalhostManifest(normalizedUrl);

    final existingPlugin = await _repository.getPlugin(manifest.id);
    if (existingPlugin != null && !existingPlugin.isDevelopment) {
      throw Exception(
        'כבר קיים תוסף מותקן (רגיל) עם אותו מזהה. מחק או שנה id.',
      );
    }

    final newUserOrder = existingPlugin != null
        ? existingPlugin.userOrder
        : await _repository.getNextUserOrderForNewPlugin();

    final plugin = InstalledPlugin(
      pluginId: manifest.id,
      name: manifest.name,
      version: manifest.version,
      installPath: normalizedUrl,
      entrypointPath: manifest.entrypoint,
      iconPath: manifest.icon,
      enabled: existingPlugin?.enabled ?? true,
      pinned: existingPlugin?.pinned ?? manifest.defaultPinned,
      pinnedToNavRail: existingPlugin?.pinnedToNavRail ?? false,
      allowOrderBeforeBuiltInsGranted:
          existingPlugin?.allowOrderBeforeBuiltInsGranted ??
          manifest.allowOrderBeforeBuiltIns,
      manifest: manifest,
      installedAt: existingPlugin?.installedAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      sourceType: 'localhost_dev',
      devRootPath: normalizedUrl,
      userOrder: newUserOrder,
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
      // הרשאה חדשה: בהתקנה ראשונה מאשרים, בעדכון — שוללים עד לאישור מפורש.
      await _repository.setPermission(
        manifest.id,
        perm,
        existingPlugin == null,
      );
    }
  }
}
