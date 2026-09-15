import 'package:flutter/foundation.dart';
import 'package:otzaria/core/user_state/user_state_list_store.dart';
import 'package:otzaria/utils/file/hive_utils.dart';

/// רשימה טיפוסית של מצב המשתמש (היסטוריה, סימניות, שולחנות) על גבי
/// [UserStateListStore]. `T` צריך `fromJson`/`toJson`.
///
/// ## שני נתיבים, ורק אחד מהם כותב
///
/// [load] סובלני לרשומה פגומה (היא מדולגת). [mutate] הוא נתיב הכתיבה, והוא
/// מחיל את השינוי על הרשימה **הטרייה** מהמסד בתוך טרנזקציה — לא על עותק
/// שבזיכרון.
class UserStateListRepository<T> {
  UserStateListRepository({
    required this.boxName,
    required this.key,
    required this.fromJson,
    required this.toJson,
    UserStateListStore? store,
  }) : _store = store ?? UserStateListStore.instance;

  /// שם המאגר ההיסטורי (Hive box) — נשאר כמזהה הרשימה במסד.
  final String boxName;
  final String key;
  final T Function(Map<String, dynamic>) fromJson;
  final Map<String, dynamic> Function(T) toJson;
  final UserStateListStore _store;

  /// אות שהרשימה הזו שונתה בחלון אחר. כתיבה של החלון הזה אינה מחזירה אות.
  Stream<void> get remoteChanges => _store.changes.where(
    (changed) => changed.box == boxName && changed.key == key,
  );

  /// טוען את הרשימה. כשל קריאה מהמסד מתפשט — "לא ידוע" אינו "ריק", וגיבוי
  /// שנכתב מרשימה ריקה כזו היה מוחק את הנתונים בשחזור.
  Future<List<T>> load() async =>
      _decode(await _store.read(boxName, key)).items;

  /// מחיל [apply] על הרשימה הטרייה ושומר את התוצאה, בטרנזקציה אחת.
  /// מחזיר את מה שנשמר.
  ///
  /// ⚠️ [apply] רץ בתוך הטרנזקציה, ולכן חייב להיות **טהור** ומהיר: לחשב
  /// מהרשימה שקיבל, בלי await ובלי תופעות לוואי.
  Future<List<T>> mutate(List<T> Function(List<T> current) apply) async {
    late List<T> next;
    await _store.mutate(boxName, key, (raw) {
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
      _store.write(boxName, key, items.map(toJson).toList());

  /// "מחק הכול" פירושו הכול, כולל מה שחלון אחר הוסיף בשנייה האחרונה.
  Future<void> clear() => _store.clear(boxName, key);

  _Decoded<T> _decode(List<dynamic> raw) {
    final items = <T>[];
    final undecodable = <dynamic>[];
    for (final entry in raw) {
      try {
        items.add(fromJson(castMap(entry)));
      } catch (e) {
        debugPrint('⚠️ $boxName/$key: skipping undecodable entry: $e');
        undecodable.add(entry);
      }
    }
    return _Decoded(items, undecodable);
  }
}

class _Decoded<T> {
  const _Decoded(this.items, this.undecodable);

  final List<T> items;
  final List<dynamic> undecodable;
}
