import 'dart:convert';

import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:path/path.dart' as p;

/// תיקייה שהמשתמש העניק לתוסף גישה קבועה אליה (`fs.pickUserFolder`).
/// [path] הוא הנתיב הקנוני בזמן האישור.
typedef PluginUserFolderGrant = ({String token, String path});

/// הרשאות התיקייה הקבועות של תוסף, ב-KV `_internal/user_folder_grants` כמיפוי
/// token→{path}.
///
/// משותף לאדפטר (בחירה, ביטול, ובדיקת התיקיות המאושרות של פעולות הכתיבה)
/// ולמסך הגדרות התוסף, כדי שהפענוח יהיה במקום אחד. ה-namespace `_internal`
/// אינו נגיש לתוסף דרך `storage.*`, ולכן תוסף אינו יכול לרשום לעצמו תיקייה —
/// רשומה נוצרת רק אחרי דיאלוג ההסכמה של אוצריא.
class PluginUserFolderGrants {
  const PluginUserFolderGrants(this._repo);

  final PluginRegistryRepository _repo;
  static final Map<String, Set<void Function(String)>> _revokeListeners = {};

  /// מודיע למופעים פעילים להסיר גם הרשאה חד-פעמית לאותה תיקייה.
  static void Function() onRevoke(
    String pluginId,
    void Function(String) listener,
  ) {
    final listeners = _revokeListeners.putIfAbsent(pluginId, () => {});
    listeners.add(listener);
    return () {
      listeners.remove(listener);
      if (listeners.isEmpty) _revokeListeners.remove(pluginId);
    };
  }

  static const String namespace = '_internal';
  static const String key = 'user_folder_grants';

  Future<Map<String, dynamic>> _read(String pluginId) async {
    final raw = await _repo.getKV(pluginId, namespace, key);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _write(String pluginId, Map<String, dynamic> grants) =>
      _repo.setKV(pluginId, namespace, key, jsonEncode(grants));

  static PluginUserFolderGrant? _grantOf(String token, Object? value) =>
      switch (value) {
        {'path': final String path} => (token: token, path: path),
        _ => null,
      };

  /// כל התיקיות של התוסף, לפי סדר האישור.
  Future<List<PluginUserFolderGrant>> list(String pluginId) async => [
    for (final entry in (await _read(pluginId)).entries)
      ?_grantOf(entry.key, entry.value),
  ];

  Future<PluginUserFolderGrant?> byToken(String pluginId, String token) async =>
      _grantOf(token, (await _read(pluginId))[token]);

  /// ה-grant של [canonicalPath], אם התיקייה כבר אושרה.
  Future<PluginUserFolderGrant?> byPath(
    String pluginId,
    String canonicalPath,
  ) async {
    for (final grant in await list(pluginId)) {
      if (p.equals(grant.path, canonicalPath)) return grant;
    }
    return null;
  }

  Future<void> add(String pluginId, PluginUserFolderGrant grant) async {
    final grants = await _read(pluginId);
    grants[grant.token] = {'path': grant.path};
    await _write(pluginId, grants);
  }

  /// מבטל את ה-grant ומחזיר אותו, או `null` אם לא היה. אינו נוגע בדיסק.
  Future<PluginUserFolderGrant?> revoke(String pluginId, String token) async {
    final grants = await _read(pluginId);
    if (!grants.containsKey(token)) return null;
    final removed = _grantOf(token, grants.remove(token));
    await _write(pluginId, grants);
    if (removed != null) {
      PluginRegistryRepository.revokePendingFileAccess(pluginId);
      for (final listener in [...?_revokeListeners[pluginId]]) {
        listener(removed.path);
      }
    }
    return removed;
  }
}
