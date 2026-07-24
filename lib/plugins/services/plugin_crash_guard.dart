import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import 'package:otzaria/core/app_paths.dart';

/// שומר על האפליקציה מפני קריסות native חוזרות בעת טעינת תוסף.
///
/// הרעיון: לפני יצירת WebView לתוסף רושמים את ה-pluginId לקובץ דיסק.
/// אם הטעינה הצליחה (`onLoadStop` ירה) — מסירים. אם התהליך מת באמצע
/// (קריסה native ב-`MSVCP140`/`EmbeddedBrowserWebView` שלא ניתן לתפוס
/// מ-Dart) — הרישום נשאר. בהפעלה הבאה אנחנו רואים שהתוסף "תקוע במצב
/// טעינה" מהריצה הקודמת, וזה אינדיקטור חזק שהוא הקריס את התוכנה —
/// אז לא מנסים לטעון אותו שוב אוטומטית; מציגים מסך הסבר עם אפשרות
/// לנסות שוב ידנית.
///
/// **למה זה עובד גם כשהבאג מתוקן**: ברגע ש-WebView מצליח לטעון תקין
/// (אצל המשתמש, אחרי שדרוג של WebView2/Flutter/בלי-קשר), הרישום מסיר
/// את עצמו ב-`onLoadStop` — והתוסף חוזר לעבוד אוטומטית.
class PluginCrashGuard {
  static Set<String>? _blocked;
  static String? _currentAppVersion;
  static Completer<void>? _initFuture;

  static Future<String> _filePath() async {
    final root = await AppPaths.getDataRootPath();
    return p.join(root, 'plugin_crash_guard.json');
  }

  static Future<String> _resolveAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final v = info.version.trim();
      final b = info.buildNumber.trim();
      if (v.isEmpty) return b.isEmpty ? 'unknown' : b;
      if (b.isEmpty || v.endsWith('+$b')) return v;
      return '$v+$b';
    } catch (_) {
      return 'unknown';
    }
  }

  /// טוען את מצב הquarantine מ-disk. מומלץ לקרוא פעם אחת באתחול האפליקציה;
  /// קריאות נוספות הן no-op.
  ///
  /// **שחרור אוטומטי בשדרוג גרסה**: הקובץ שומר את גרסת האפליקציה שתחתיה
  /// ה-canary נכתב. אם הגרסה הנוכחית שונה (כלומר המשתמש שדרג את אוצריא),
  /// אנחנו מתעלמים מה-canary הישן ומתחילים מ-state ריק. ההנחה: שדרוג של
  /// אוצריא עשוי לכלול תיקון של flutter_inappwebview שיצור WebView ללא
  /// קריסה, ולכן ראוי לתת לתוסף הזדמנות נוספת אוטומטית. אם זה עדיין קורס,
  /// ה-canary יתעדכן בגרסה החדשה.
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

  /// `true` אם התוסף נמצא ב-quarantine — כלומר הופיע בקובץ בתחילת ההפעלה
  /// הזו (= הופיע בריצה הקודמת בלי שהושלם markSuccess).
  static bool isBlocked(String pluginId) {
    return _blocked?.contains(pluginId) ?? false;
  }

  /// מסמן שמתחילים לטעון את התוסף. אם הקוד יקרוס מכאן והלאה, ההפעלה הבאה
  /// תראה את ה-pluginId בקובץ ותסרב לטעון אותו אוטומטית.
  static Future<void> markLoadAttempt(String pluginId) async {
    await ensureInitialized();
    _blocked!.add(pluginId);
    await _persist();
  }

  /// גרסה סינכרונית של [markLoadAttempt] — לשימוש בנקודות שבהן חייבים
  /// לעדכן את ה-canary לפני שקוד native קריטי רץ, ובלי לפתוח race עם
  /// [markLoadSuccessSync] (לדוגמה, סגירה מהירה של הטאב/האפליקציה מיד
  /// אחרי onWebViewCreated).
  ///
  /// דורש ש-[ensureInitialized] כבר רץ (main.dart דואג לזה באתחול).
  static void markLoadAttemptSync(String pluginId) {
    final blocked = _blocked;
    if (blocked == null) {
      debugPrint('PluginCrashGuard.markLoadAttemptSync called before init');
      return;
    }
    if (blocked.contains(pluginId)) return;
    blocked.add(pluginId);
    _persistSync();
  }

  /// מסמן שהתוסף נטען בהצלחה. מסיר את הסימון מ-disk כדי שההפעלה הבאה
  /// תאפשר טעינה רגילה.
  static Future<void> markLoadSuccess(String pluginId) async {
    await ensureInitialized();
    final removed = _blocked!.remove(pluginId);
    if (removed) await _persist();
  }

  /// גרסה סינכרונית של [markLoadSuccess] — לשימוש ב-`State.dispose()` בלבד,
  /// כי שם async writes לא תמיד מגיעים ל-disk לפני שהאפליקציה נסגרת.
  /// מבטיח שניקוי ה-canary יקרה גם בעת סגירה רגילה של התוכנה בזמן טעינה.
  static void markLoadSuccessSync(String pluginId) {
    // לפני ensureInitialized — אם הגענו לכאן בלי שאתחלנו, _blocked עוד null.
    // במקרה כזה אין מה לעדכן בזיכרון, אבל גם הקובץ לא מכיל את ה-pluginId
    // (כי לא הוספנו אותו עדיין). אין מה לעשות.
    final blocked = _blocked;
    if (blocked == null) return;
    final removed = blocked.remove(pluginId);
    if (!removed) return;
    _persistSync();
  }

  /// כתיבה סינכרונית ל-disk של מצב ה-_blocked הנוכחי.
  /// חישוב הנתיב חייב להיות sync — `AppPaths.getDataRootPath()` הוא async,
  /// ולכן משתמשים ב-`cachedDataRootPath` ש-AppPaths חושף אחרי שהוא חושב
  /// פעם אחת (קורה ב-`_initializeDataRootForEarlyLogging` ב-main.dart,
  /// ושוב ב-ensureInitialized של ה-guard).
  static void _persistSync() {
    final blocked = _blocked;
    if (blocked == null) return;
    try {
      final cachedRoot = AppPaths.cachedDataRootPath;
      if (cachedRoot == null) return; // לא ידוע הנתיב — לא ניתן לכתוב sync
      final file = File(p.join(cachedRoot, 'plugin_crash_guard.json'));
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      file.writeAsStringSync(
        jsonEncode(_serializeState()),
        flush: true,
      );
    } catch (e) {
      debugPrint('PluginCrashGuard: failed to persist (sync) state: $e');
    }
  }

  /// המשתמש לחץ "נסה שוב". מסיר את הסימון לתוסף ספציפי כך שהוא ינסה
  /// להיטען שוב בפעם הבאה ש-WebView ייווצר.
  static Future<void> retry(String pluginId) async {
    await ensureInitialized();
    final removed = _blocked!.remove(pluginId);
    if (removed) await _persist();
  }

  /// המשתמש לחץ "נסה שוב את כולם". מסיר את כל הסימונים.
  static Future<void> retryAll() async {
    await ensureInitialized();
    if (_blocked!.isEmpty) return;
    _blocked!.clear();
    await _persist();
  }

  /// משמש לטסטים בלבד — מאפס את כל ה-state ה-static.
  @visibleForTesting
  static void resetForTesting() {
    _blocked = null;
    _currentAppVersion = null;
    _initFuture = null;
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

  static Future<void> _persist() async {
    try {
      final file = File(await _filePath());
      if (!file.parent.existsSync()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsString(
        jsonEncode(_serializeState()),
        flush: true, // חיוני: צריך flush ל-disk לפני קריסה אפשרית
      );
    } catch (e) {
      debugPrint('PluginCrashGuard: failed to persist state: $e');
    }
  }
}
