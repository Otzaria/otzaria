import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:otzaria/update/app_release_version.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import 'package:otzaria/core/app_paths.dart';

/// שומר סימון לפני טעינת WebView ומסיר אותו בהצלחה או בסגירה תקינה.
/// סימון שנותר מהפעלה קודמת חוסם טעינה חוזרת של תוסף שקרס ב-native.
class PluginCrashGuard {
  static Set<String>? _blocked;
  static String? _currentAppVersion;
  static Completer<void>? _initFuture;

  /// תוספים שנוסה לטעון אותם בסשן הנוכחי. [isBlocked] מתעלם מהם — canary
  /// חי של הסשן הזה אינו עדות לקריסה בהפעלה קודמת.
  static final Set<String> _sessionAttempts = <String>{};

  /// בעלות נפרדת לכל ניסיון טעינה: סיום ישן לא מנקה סימון של ניסיון חדש.
  static final Map<String, Set<Object>> _loadsInFlight = {};

  /// מסיר את הטעינה של [owner]; true כשלא נותרה טעינה פתוחה לתוסף
  /// ומותר לנקות את ה-canary.
  static bool _finishLoad(String pluginId, Object owner) {
    final inFlight = _loadsInFlight[pluginId];
    if (inFlight == null) return true;
    inFlight.remove(owner);
    if (inFlight.isNotEmpty) return false;
    _loadsInFlight.remove(pluginId);
    return true;
  }

  static Future<String> _filePath() async {
    final root = await AppPaths.getDataRootPath();
    return p.join(root, 'plugin_crash_guard.json');
  }

  static Future<String> _resolveAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final v = canonicalAppVersion(info);
      final b = info.buildNumber.trim();
      if (v.isEmpty) return b.isEmpty ? 'unknown' : b;
      if (b.isEmpty || v.endsWith('+$b')) return v;
      return '$v+$b';
    } catch (_) {
      return 'unknown';
    }
  }

  /// טוען פעם אחת את החסימות מהדיסק; שינוי גרסת האפליקציה משחרר אותן
  /// כדי לאפשר ניסיון חדש אחרי תיקון אפשרי של קריסת native.
  static Future<void> ensureInitialized() async {
    if (_blocked != null) return;
    if (_initFuture != null) return _initFuture!.future;
    _initFuture = Completer<void>();
    try {
      _currentAppVersion = await _resolveAppVersion();
      final file = File(await _filePath());
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final decoded = jsonDecode(content);
          if (decoded is Map) {
            final storedVersion = decoded['version'];
            if (storedVersion == _currentAppVersion) {
              final list = decoded['blocked'];
              if (list is List) {
                _blocked = list.whereType<String>().toSet();
              }
            } else {
              debugPrint(
                'PluginCrashGuard: app version changed ($storedVersion → '
                '$_currentAppVersion). Clearing previous quarantine to give '
                'plugins another chance.',
              );
            }
          }
          // אם הקובץ במבנה ישן (List) — מתעלמים, כי אין לנו דרך לדעת אם
          // התוסף נחסם בגרסה הנוכחית או קודמת.
        }
      }
      _blocked ??= <String>{};
    } catch (e) {
      debugPrint('PluginCrashGuard: failed to read state: $e');
      _blocked = <String>{};
    } finally {
      _initFuture!.complete();
    }
  }

  /// חסימה שנותרה מההפעלה הקודמת; ניסיון בסשן הנוכחי אינו חסימה,
  /// כדי ש-rebuild במהלך טעינה תקינה לא יקטע אותה.
  static bool isBlocked(String pluginId) {
    if (_sessionAttempts.contains(pluginId)) return false;
    return _blocked?.contains(pluginId) ?? false;
  }

  /// שומר סימון לפני טעינת התוסף. [owner] מזהה את ניסיון הטעינה,
  /// וה-Future מסתיים כשהסימון בדיסק ויכול להגן מקריסת native.
  static Future<void> markLoadAttempt(
    String pluginId, {
    Object owner = '',
  }) async {
    // אחרי האתחול העדכון בזיכרון סינכרוני, כדי ש-dispose מיידי ימצא אותו.
    if (_blocked == null) await ensureInitialized();
    _sessionAttempts.add(pluginId);
    _loadsInFlight.putIfAbsent(pluginId, () => <Object>{}).add(owner);
    _blocked!.add(pluginId);
    await _persist();
  }

  /// [markLoadAttempt] למסלול פתיחת התוסף: לפני האתחול (main.dart דואג לו)
  /// אין סימון ואין IO, ומוחזר null.
  static Future<void>? markLoadAttemptIfInitialized(
    String pluginId, {
    Object owner = '',
  }) => _blocked == null ? null : markLoadAttempt(pluginId, owner: owner);

  /// מסמן שסיום הטעינה של [owner] הגיע בעוד התהליך חי. הסימון מוסר מ-disk
  /// רק כשלא נותרה טעינה פתוחה של מופע אחר לאותו תוסף.
  static Future<void> markLoadSuccess(
    String pluginId, {
    Object owner = '',
  }) async {
    // לפני האתחול ה-pluginId עוד לא נרשם, לא בזיכרון ולא בקובץ.
    final blocked = _blocked;
    if (blocked == null) return;
    if (!_finishLoad(pluginId, owner)) return;
    if (blocked.remove(pluginId)) await _persist();
  }

  /// נקרא בתחילת סגירה יזומה (onWindowClose): מנקה canaries של טעינות בטיסה.
  /// סגירה רגילה אינה קריסה, וה-dispose של הטאבים לא רץ במסלול היציאה.
  static Future<void> markCleanShutdown() async {
    final blocked = _blocked;
    if (blocked != null && _sessionAttempts.isNotEmpty) {
      _loadsInFlight.clear();
      final before = blocked.length;
      blocked.removeAll(_sessionAttempts);
      if (blocked.length != before) unawaited(_persist());
    }
    // ממתינים גם לכתיבות שכבר בתור, למשל של טאב שנסגר רגע לפני היציאה.
    await _writes;
  }

  /// המשתמש לחץ "נסה שוב". מסיר את הסימון לתוסף ספציפי כך שהוא ינסה
  /// להיטען שוב בפעם הבאה ש-WebView ייווצר.
  static Future<void> retry(String pluginId) async {
    await ensureInitialized();
    _sessionAttempts.remove(pluginId);
    _loadsInFlight.remove(pluginId);
    final removed = _blocked!.remove(pluginId);
    if (removed) await _persist();
  }

  /// משמש לטסטים בלבד — מאפס את כל ה-state ה-static.
  @visibleForTesting
  static void resetForTesting() {
    _blocked = null;
    _currentAppVersion = null;
    _initFuture = null;
    _sessionAttempts.clear();
    _loadsInFlight.clear();
    _writes = Future<void>.value();
  }

  /// משמש לטסטים בלבד — מאפשר להחדיר state התחלתי.
  @visibleForTesting
  static void setInitialBlockedForTesting(
    Set<String> blocked, {
    String appVersion = 'test',
  }) {
    _blocked = {...blocked};
    _currentAppVersion = appVersion;
    _initFuture = Completer<void>()..complete();
  }

  static Map<String, dynamic> _serializeState() {
    return {
      'version': _currentAppVersion ?? 'unknown',
      'blocked': (_blocked ?? <String>{}).toList()..sort(),
    };
  }

  /// תור כתיבות סדרתי: כל כתיבה שומרת את המצב העדכני בזמן ריצתה, כך שכתיבה
  /// מאוחרת לעולם אינה נדרסת על ידי מוקדמת.
  static Future<void> _writes = Future<void>.value();

  static Future<void> _persist() => _writes = _writes.then((_) => _write());

  static Future<void> _write() async {
    try {
      final file = File(await _filePath());
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode(_serializeState()),
        flush: true, // חיוני: צריך flush ל-disk לפני קריסה אפשרית
      );
    } catch (e) {
      debugPrint('PluginCrashGuard: failed to persist state: $e');
    }
  }
}
