import 'dart:collection';
import 'dart:convert';

import 'package:otzaria/plugins/plugin_constants.dart';

/// למה דף של מופע קיים נטען מחדש — נמסר לתוסף ב-`plugin.boot.restore.reason`.
enum PluginRestoreReason { discarded, crashed, reloaded, session }

/// מצב השחזור שתוסף שמר דרך `plugin.setRestoreState`, לפי מופע.
///
/// המצב של טאב כלי נשמר גם עם ה-JSON של הטאב (סשן וסביבות עבודה).
/// הזיכרון חסום; מצב של WebView שפונה נשמר עד שהדף החדש קיבל אותו.
class PluginRestoreStateStore {
  PluginRestoreStateStore._();
  static final PluginRestoreStateStore instance = PluginRestoreStateStore._();

  /// גבול לגודל המצב אחרי קידוד, בבתים של UTF-8.
  static const int maxStateBytes = 64 * 1024;
  static const int maxEntries = 64;
  static const int maxTotalBytes = 2 * 1024 * 1024;

  /// לפי סדר העדכון האחרון — הראשון הוא הוותיק.
  final LinkedHashMap<PluginInstanceKey, ({String json, int bytes})> _states =
      LinkedHashMap();
  final Map<PluginInstanceKey, Object> _retentions = {};
  final Set<PluginInstanceKey> _outdated = {};
  int _totalBytes = 0;

  int get length => _states.length;
  int get totalBytes => _totalBytes;

  /// שומר את [state] (כל ערך JSON) עבור [key]; `null` מוחק.
  ///
  /// זורק [ArgumentError] כשהערך אינו ניתן לקידוד או גדול מ-[maxStateBytes].
  void set(PluginInstanceKey key, Object? state) {
    if (state == null) {
      remove(key);
      return;
    }
    try {
      final encoded = jsonEncode(state);
      final bytes = utf8.encode(encoded).length;
      if (bytes > maxStateBytes) {
        throw ArgumentError('state exceeds $maxStateBytes bytes');
      }
      if (!_put(key, encoded, bytes)) {
        throw ArgumentError('restore state budget is held by released pages');
      }
    } on JsonUnsupportedObjectError {
      if (has(key)) _outdated.add(key);
      throw ArgumentError('state must be JSON-serializable');
    } on ArgumentError {
      if (has(key)) _outdated.add(key);
      rethrow;
    }
  }

  /// המצב המקודד כפי שנשמר, או `null`.
  String? jsonOf(PluginInstanceKey key) => _states[key]?.json;

  /// זורע מצב מקודד שנטען מסשן שמור. מצב פגום או גדול מדי נזרק.
  void seed(PluginInstanceKey key, String json) {
    final bytes = utf8.encode(json).length;
    if (bytes > maxStateBytes) return;
    try {
      if (jsonDecode(json) == null) return;
    } on FormatException {
      return;
    }
    _put(key, json, bytes);
  }

  bool _put(PluginInstanceKey key, String json, int bytes) {
    final previous = _states[key];
    var count = _states.length + (previous == null ? 1 : 0);
    var totalBytes = _totalBytes - (previous?.bytes ?? 0) + bytes;
    final victims = <PluginInstanceKey>[];
    for (final entry in _states.entries) {
      if (count <= maxEntries && totalBytes <= maxTotalBytes) break;
      if (entry.key == key || _retentions.containsKey(entry.key)) continue;
      victims.add(entry.key);
      count--;
      totalBytes -= entry.value.bytes;
    }
    // כשל קבלה אינו מוחק מצבים אחרים או את העותק הקודם של המצב הזה.
    if (count > maxEntries || totalBytes > maxTotalBytes) return false;
    for (final victim in victims) {
      remove(victim);
    }
    _states.remove(key);
    _totalBytes -= previous?.bytes ?? 0;
    _states[key] = (json: json, bytes: bytes);
    _totalBytes += bytes;
    _outdated.remove(key);
    return true;
  }

  bool has(PluginInstanceKey key) => _states.containsKey(key);

  /// כתיבה שנדחתה משאירה עותק ישן לשחזור, אך אינה מתירה פינוי של הדף החי.
  bool canDiscard(PluginInstanceKey key) =>
      has(key) && !_outdated.contains(key);

  /// שומר את העותק היחיד של דף ששוחרר. null מציין שאין מצב לשמור.
  Object? retain(PluginInstanceKey key) {
    if (!has(key)) return null;
    return _retentions[key] = Object();
  }

  /// תשובת boot ישנה אינה משחררת שמירה של דור חדש יותר.
  void releaseRetention(PluginInstanceKey key, Object token) {
    if (identical(_retentions[key], token)) _retentions.remove(key);
  }

  Object? stateOf(PluginInstanceKey key) {
    final json = _states[key]?.json;
    return json == null ? null : jsonDecode(json);
  }

  void remove(PluginInstanceKey key) {
    _retentions.remove(key);
    _outdated.remove(key);
    final removed = _states.remove(key);
    if (removed != null) _totalBytes -= removed.bytes;
  }

  /// מסיר את המצב של מופע לפי המזהה בלבד — כשהתוסף כבר אינו ידוע.
  void removeInstanceId(String instanceId) {
    for (final key in _states.keys.toList()) {
      if (key.instanceId == instanceId) remove(key);
    }
  }
}
