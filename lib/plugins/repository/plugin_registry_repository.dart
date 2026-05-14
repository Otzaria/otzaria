import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/models/plugin_published_record.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';

class PluginRegistryRepository {
  final PluginSystemDatabase _db;

  PluginRegistryRepository({PluginSystemDatabase? database})
      : _db = database ?? PluginSystemDatabase.instance;

  Future<List<InstalledPlugin>> getAllPlugins() async {
    return _db.getAllInstalledPlugins();
  }

  Future<InstalledPlugin?> getPlugin(String pluginId) async {
    return _db.getInstalledPlugin(pluginId);
  }

  Future<void> savePlugin(InstalledPlugin plugin) async {
    await _db.insertOrUpdatePlugin(plugin);
  }

  Future<void> deletePlugin(String pluginId) async {
    final plugin = await getPlugin(pluginId);
    if (plugin != null && plugin.isDevelopment) {
      throw ArgumentError('Cannot delete a development plugin. Use detachDevelopmentPlugin instead.');
    }
    await _db.deletePlugin(pluginId);
  }

  Future<List<InstalledPlugin>> getDevelopmentPlugins() async {
    final plugins = await getAllPlugins();
    return plugins.where((p) => p.isDevelopment).toList();
  }

  Future<void> saveDevelopmentPlugin(InstalledPlugin plugin) async {
    if (!plugin.isDevelopment) {
      throw ArgumentError('Cannot save a packaged plugin as development');
    }
    if (plugin.devRootPath == null || plugin.devRootPath!.trim().isEmpty) {
      throw ArgumentError('Development plugin must have a valid devRootPath');
    }
    await _db.insertOrUpdatePlugin(plugin);
  }

  Future<void> detachDevelopmentPlugin(String pluginId) async {
    final plugin = await getPlugin(pluginId);
    if (plugin != null && !plugin.isDevelopment) {
      throw ArgumentError('Cannot detach a packaged plugin. Use deletePlugin instead.');
    }
    await _db.deletePlugin(pluginId);
  }

  Future<void> updatePinState(String pluginId, bool pinned) async {
    await _db.updatePluginPinState(pluginId, pinned);
  }

  Future<void> updateNavRailPinState(
      String pluginId, bool pinnedToNavRail) async {
    await _db.updatePluginNavRailPinState(pluginId, pinnedToNavRail);
  }

  Future<void> setPermission(
      String pluginId, String permission, bool granted) async {
    await _db.setPermission(pluginId, permission, granted);
  }

  Future<bool?> getPermission(String pluginId, String permission) async {
    return _db.getPermission(pluginId, permission);
  }

  Future<List<PluginPermissionGrant>> getPluginPermissions(
      String pluginId) async {
    return _db.getPluginPermissions(pluginId);
  }

  Future<void> setKV(
      String pluginId, String namespace, String key, String valueJson) async {
    await _db.setPluginKV(pluginId, namespace, key, valueJson);
  }

  Future<String?> getKV(String pluginId, String namespace, String key) async {
    return _db.getPluginKV(pluginId, namespace, key);
  }

  Future<void> removeKV(String pluginId, String namespace, String key) async {
    await _db.removePluginKV(pluginId, namespace, key);
  }

  Future<List<String>> listKVKeys(String pluginId, String namespace) async {
    return _db.listPluginKVKeys(pluginId, namespace);
  }

  Future<void> publishRecord(String pluginId, String type, String scope,
      String recordKey, String payloadJson, String? expiresAt) async {
    await _db.publishRecord(
        pluginId, type, scope, recordKey, payloadJson, expiresAt);
  }

  Future<void> unpublishRecord(
      String pluginId, String type, String scope, String recordKey) async {
    await _db.unpublishRecord(pluginId, type, scope, recordKey);
  }

  Future<List<PluginPublishedRecord>> getPluginPublishedRecords(
      String pluginId) async {
    return _db.getPluginPublishedRecords(pluginId);
  }

  Future<List<String>> getPublishedRecordsByType(String type) async {
    return _db.getPublishedRecordsByType(type);
  }

  /// מחזיר האם התוסף מופעל. null = לא נמצא (=treat as disabled).
  Future<bool> getIsEnabled(String pluginId) async {
    final plugin = await _db.getInstalledPlugin(pluginId);
    return plugin?.enabled ?? false;
  }
}
