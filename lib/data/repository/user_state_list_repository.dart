import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/user_state/user_state_list_store.dart';
import 'package:otzaria/utils/file/hive_utils.dart';

/// רשימה טיפוסית של מצב המשתמש (היסטוריה, סימניות, שולחנות) על גבי
/// [UserStateListStore]. `T` צריך `fromJson`/`toJson`.
///
/// ## שני נתיבים, ורק אחד מהם כותב
///
/// [load] סובלני לרשומה פגומה (היא מדולגת). [mutate] הוא נתיב הכתיבה, והוא
/// מחיל את השינוי על הרשימה **הטרייה** מהמסד — לא על עותק שבזיכרון.
class UserStateListRepository<T> {
  UserStateListRepository({
    required this.boxName,
    required this.key,
    required this.fromJson,
    required this.toJson,
    this.decodeInBackground = false,
    UserStateListStore? store,
  }) : _store = store ?? UserStateListStore.instance;

  /// שם המאגר ההיסטורי (Hive box) — נשאר כמזהה הרשימה במסד.
  final String boxName;
  final String key;
  final T Function(Map<String, dynamic>) fromJson;
  final Map<String, dynamic> Function(T) toJson;

  /// ה-JSON של רשימה גדולה מפוענח תמיד ב-isolate; כש-true גם [fromJson] רץ שם,
  /// ולכן רק כשהוא מייצר נתונים טהורים — טאב משחזר bloc-ים, ואסור לבנות אותם ב-isolate אחר.
  final bool decodeInBackground;
  final UserStateListStore _store;

  // מעל הסף, בבדיקת widget הטעינה מסתיימת רק בתוך tester.runAsync (Isolate.run).
  static const int _backgroundDecodeMinLength = 64 * 1024;

  /// מזהה הכותב: כל חלון מחזיק מופע משלו, וכך מסנן רק את הכתיבות שלו.
  final Object _origin = Object();

  /// אות שהרשימה הזו שונתה בחלון אחר. כתיבה של המופע הזה אינה מחזירה אות.
  Stream<void> get remoteChanges => _store.changes.where(
    (changed) =>
        changed.box == boxName &&
        changed.key == key &&
        !identical(changed.origin, _origin),
  );

  /// טוען את הרשימה. כשל קריאה מהמסד מתפשט — "לא ידוע" אינו "ריק", וגיבוי
  /// שנכתב מרשימה ריקה כזו היה מוחק את הנתונים בשחזור.
  Future<List<T>> load() async {
    final payload = await _store.readPayload(boxName, key);
    if (payload == null || payload.length < _backgroundDecodeMinLength) {
      return _decode(UserStateListStore.decodePayload(payload)).items;
    }
    if (decodeInBackground) {
      return _decodeInIsolate(payload, fromJson, '$boxName/$key');
    }
    return _decode(await _parseInIsolate(payload)).items;
  }

  static Future<List<dynamic>> _parseInIsolate(String payload) =>
      Isolate.run(() => UserStateListStore.decodePayload(payload));

  // static: closure במתודת מופע הייתה לוכדת את this, שאינו נשלח ל-isolate.
  static Future<List<T>> _decodeInIsolate<T>(
    String payload,
    T Function(Map<String, dynamic>) fromJson,
    String label,
  ) => Isolate.run(
    () => _decodeEntries(
      UserStateListStore.decodePayload(payload),
      fromJson,
      label,
    ).items,
  );

  /// מחיל [apply] על הרשימה הטרייה ושומר את התוצאה אטומית. מחזיר את מה שנשמר.
  ///
  /// [apply] רץ פעם אחת, באופן סינכרוני, מול הרשימה שבטרנזקציית הכתיבה.
  Future<List<T>> mutate(List<T> Function(List<T> current) apply) async {
    late List<T> next;
    await _store.mutate(boxName, key, origin: _origin, (raw) {
      final decoded = _decode(raw);
      next = apply(decoded.items);
      // ⚠️ רשומות שלא נפענחו נשמרות. הן אינן מוצגות, אבל כתיבה שמשמיטה
      // אותן מוחקת נתונים של המשתמש בגלל באג פענוח — וזה בדיוק מה שאסור.
      return [...next.map(toJson), ...decoded.undecodable];
    });
    return next;
  }

  /// כתיבת הרשימה במלואה, בלי מיזוג.
  ///
  /// ⚠️ **דריסה מוחלטת.** מוצדק בשחזור מגיבוי בלבד — שם הכוונה היא בדיוק
  /// להחליף את מה שיש. לכל שינוי אחר השתמש ב-[mutate].
  Future<void> overwrite(List<T> items) =>
      _store.write(boxName, key, items.map(toJson).toList(), origin: _origin);

  /// "מחק הכול" פירושו הכול, כולל מה שחלון אחר הוסיף בשנייה האחרונה.
  Future<void> clear() => _store.clear(boxName, key, origin: _origin);

  _Decoded<T> _decode(List<dynamic> raw) =>
      _decodeEntries(raw, fromJson, '$boxName/$key');
}

_Decoded<T> _decodeEntries<T>(
  List<dynamic> raw,
  T Function(Map<String, dynamic>) fromJson,
  String label,
) {
  final items = <T>[];
  final undecodable = <dynamic>[];
  for (final entry in raw) {
    try {
      items.add(fromJson(castMap(entry)));
    } catch (e) {
      debugPrint('⚠️ $label: skipping undecodable entry: $e');
      undecodable.add(entry);
    }
  }
  return _Decoded(items, undecodable);
}

class _Decoded<T> {
  const _Decoded(this.items, this.undecodable);

  final List<T> items;
  final List<dynamic> undecodable;
}
