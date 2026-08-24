import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/models/plugin_published_record.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';

class PluginRegistryRepository {
  final PluginSystemDatabase _db;

  PluginRegistryRepository({PluginSystemDatabase? database})
    : _db = database ?? PluginSystemDatabase.instance;

  Future<List<InstalledPlugin>> getAllPlugins() async {
    final plugins = await _db.getAllInstalledPlugins();
    plugins.sort(_compareForDisplay);
    return plugins;
  }

  /// השוואת תוספים לצורך תצוגה — קודם לפי [InstalledPlugin.effectiveToolTabOrder],
  /// ואז tie-breakers דטרמיניסטיים: [InstalledPlugin.installedAt] ובסוף
  /// [InstalledPlugin.pluginId]. בלי tie-breaker, כש-N תוספים חולקים את
  /// אותו `toolTabOrder` (ברירת מחדל 900 ב-manifest), הסדר ביניהם משתנה
  /// בין הרצות.
  static int _compareForDisplay(InstalledPlugin a, InstalledPlugin b) {
    final orderCmp = a.effectiveToolTabOrder.compareTo(b.effectiveToolTabOrder);
    if (orderCmp != 0) return orderCmp;
    final timeCmp = a.installedAt.compareTo(b.installedAt);
    if (timeCmp != 0) return timeCmp;
    return a.pluginId.compareTo(b.pluginId);
  }

  /// מחזיר את [InstalledPlugin.userOrder] שיש להקצות לתוסף חדש כך שהוא
  /// יצטרף בסוף הסדר הידני הקיים.
  ///
  /// • אם אף תוסף לא סודר ידנית — מחזיר `null` (התוסף ישתמש ב-manifest order).
  /// • אם כן — מחזיר `max(userOrder) + 1` כדי שהתוסף החדש יהיה אחרון.
  ///
  /// בלי זה, תוסף חדש (userOrder=null → effective=900) נכנס *לפני* כל
  /// הבלוק שסודר ידנית (effective ≥ 1000), והמשתמש מאבד את הסדר שלו.
  Future<int?> getNextUserOrderForNewPlugin() async {
    final plugins = await _db.getAllInstalledPlugins();
    int? maxOrder;
    for (final p in plugins) {
      final uo = p.userOrder;
      if (uo == null) continue;
      if (maxOrder == null || uo > maxOrder) maxOrder = uo;
    }
    return maxOrder == null ? null : maxOrder + 1;
  }

  Future<InstalledPlugin?> getPlugin(String pluginId) async {
    return _db.getInstalledPlugin(pluginId);
  }

  Future<void> savePlugin(InstalledPlugin plugin) async {
    await _db.insertOrUpdatePlugin(plugin);
  }

  Future<void> savePluginWithPermissions(
    InstalledPlugin plugin,
    Map<String, bool> permissions,
  ) async {
    await _db.insertOrUpdatePluginWithPermissions(plugin, permissions);
  }

  Future<void> deletePlugin(String pluginId) async {
    final plugin = await getPlugin(pluginId);
    if (plugin != null && plugin.isDevelopment) {
      throw ArgumentError(
        'Cannot delete a development plugin. Use detachDevelopmentPlugin instead.',
      );
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

  Future<void> saveDevelopmentPluginWithPermissions(
    InstalledPlugin plugin,
    Map<String, bool> permissions,
  ) async {
    if (!plugin.isDevelopment) {
      throw ArgumentError('Cannot save a packaged plugin as development');
    }
    if (plugin.devRootPath == null || plugin.devRootPath!.trim().isEmpty) {
      throw ArgumentError('Development plugin must have a valid devRootPath');
    }
    await _db.insertOrUpdatePluginWithPermissions(plugin, permissions);
  }

  Future<void> detachDevelopmentPlugin(String pluginId) async {
    final plugin = await getPlugin(pluginId);
    if (plugin != null && !plugin.isDevelopment) {
      throw ArgumentError(
        'Cannot detach a packaged plugin. Use deletePlugin instead.',
      );
    }
    await _db.deletePlugin(pluginId);
  }

  Future<void> updatePinState(String pluginId, bool pinned) async {
    await _db.updatePluginPinState(pluginId, pinned);
  }

  Future<void> updateNavRailPinState(
    String pluginId,
    bool pinnedToNavRail,
  ) async {
    await _db.updatePluginNavRailPinState(pluginId, pinnedToNavRail);
  }

  Future<void> updateShowInTools(String pluginId, bool showInTools) async {
    await _db.updatePluginShowInTools(pluginId, showInTools);
  }

  /// שומר סדר מותאם אישית של תוספים לפי מיקומם ברשימה הנתונה.
  ///
  /// המיקום הראשון מקבל סדר 0, השני 1 וכן הלאה. מזהים שלא קיימים ב-DB
  /// יתעלמו בשקט (UPDATE ללא שורות תואמות).
  Future<void> reorderPlugins(List<String> orderedPluginIds) async {
    final ordering = <String, int>{
      for (var i = 0; i < orderedPluginIds.length; i++) orderedPluginIds[i]: i,
    };
    await _db.updatePluginsUserOrder(ordering);
  }

  Future<void> setPermission(
    String pluginId,
    String permission,
    bool granted,
  ) async {
    await _db.setPermission(pluginId, permission, granted);
  }

  Future<bool?> getPermission(String pluginId, String permission) async {
    if (pluginBaselinePermissions.contains(permission)) return true;
    final stored = await _db.getPermission(pluginId, permission);
    if (stored != null) return stored;
    // תוסף ותיק: החלטה שנשמרה על ההרשאה הישנה מכסה את זו שפוצלה ממנה.
    final legacy = pluginLegacyPermissionAliases[permission];
    if (legacy == null) return null;
    return _db.getPermission(pluginId, legacy);
  }

  /// שמות ההרשאות המוענקות בפועל, כולל הרשאות הבסיס האוטומטיות.
  Future<List<String>> getGrantedPermissionNames(String pluginId) async {
    final grants = await getPluginPermissions(pluginId);
    return withBaselinePermissions(
      grants.where((g) => g.granted).map((g) => g.permission),
    );
  }

  Future<List<PluginPermissionGrant>> getPluginPermissions(
    String pluginId,
  ) async {
    return _db.getPluginPermissions(pluginId);
  }

  Future<void> setKV(
    String pluginId,
    String namespace,
    String key,
    String valueJson,
  ) async {
    await _db.setPluginKV(pluginId, namespace, key, valueJson);
  }

  Future<String?> getKV(String pluginId, String namespace, String key) async {
    return _db.getPluginKV(pluginId, namespace, key);
  }

  /// קריאה מרוכזת: שאילתה אחת לכל המפתחות. מפתח חסר אינו במפה המוחזרת.
  Future<Map<String, String>> getKVMany(
    String pluginId,
    String namespace,
    Iterable<String> keys,
  ) async {
    return _db.getPluginKVMany(pluginId, namespace, keys);
  }

  Future<void> removeKV(String pluginId, String namespace, String key) async {
    await _db.removePluginKV(pluginId, namespace, key);
  }

  Future<List<String>> listKVKeys(String pluginId, String namespace) async {
    return _db.listPluginKVKeys(pluginId, namespace);
  }

  Future<void> publishRecord(
    String pluginId,
    String type,
    String scope,
    String recordKey,
    String payloadJson,
    String? expiresAt,
  ) async {
    await _db.publishRecord(
      pluginId,
      type,
      scope,
      recordKey,
      payloadJson,
      expiresAt,
    );
  }

  Future<void> unpublishRecord(
    String pluginId,
    String type,
    String scope,
    String recordKey,
  ) async {
    await _db.unpublishRecord(pluginId, type, scope, recordKey);
  }

  Future<List<PluginPublishedRecord>> getPluginPublishedRecords(
    String pluginId,
  ) async {
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
