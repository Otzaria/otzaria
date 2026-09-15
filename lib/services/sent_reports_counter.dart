import 'package:flutter/foundation.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/core/user_state/user_state_list_store.dart';

/// מונה כל הדיווחים שנשלחו, בנפרד מההיסטוריה שנחתכת למספר קבוע של רשומות.
///
/// הספירה היא תצוגה בלבד: כשל בה נרשם ביומן ואינו מכשיל את שמירת הדיווח.
class SentReportsCounter {
  SentReportsCounter({
    required this.boxName,
    this.key = defaultKey,
    UserStateDatabase? database,
  }) : _lists = database == null
           ? UserStateListStore.instance
           : UserStateListStore(database: database),
       _memory = null;

  /// מונה בזיכרון, לבדיקות שאין בהן מסד.
  @visibleForTesting
  SentReportsCounter.inMemory([int initial = 0])
    : boxName = '',
      key = defaultKey,
      _lists = null,
      _memory = _MemoryValue(initial);

  static const String defaultKey = 'sent_reports_total';

  final String boxName;
  final String key;
  final UserStateListStore? _lists;
  final _MemoryValue? _memory;

  /// הערך השמור, או 0 כשאין ערך או שהקריאה נכשלה.
  Future<int> read() async {
    final memory = _memory;
    if (memory != null) return memory.value;
    try {
      return _valueOf(await _lists!.read(boxName, key));
    } catch (e) {
      debugPrint('SentReportsCounter.read($boxName) failed: $e');
      return 0;
    }
  }

  /// מקדם את המונה. [floor] הוא גודל ההיסטוריה לפני ההוספה: מתקין שעוד לא
  /// היה לו מונה מתחיל ממנו ולא מאפס.
  Future<void> increment({required int floor}) =>
      _update((current) => (current > floor ? current : floor) + 1);

  /// מעלה את המונה ל-[value] לפחות (שחזור מגיבוי).
  Future<void> raiseTo(int value) =>
      _update((current) => current > value ? current : value);

  Future<void> reset() => _update((_) => 0);

  /// read-modify-write בטרנזקציה אחת, כדי ששני חלונות לא יאבדו ספירה.
  Future<void> _update(int Function(int current) apply) async {
    final memory = _memory;
    if (memory != null) {
      memory.value = apply(memory.value);
      return;
    }
    try {
      await _lists!.mutate(boxName, key, (list) => [apply(_valueOf(list))]);
    } catch (e) {
      debugPrint('SentReportsCounter.write($boxName) failed: $e');
    }
  }

  static int _valueOf(List<dynamic> list) =>
      list.isNotEmpty && list.first is int ? list.first as int : 0;
}

class _MemoryValue {
  _MemoryValue(this.value);
  int value;
}
