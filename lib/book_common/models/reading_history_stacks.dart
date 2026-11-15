/// שמירת מחסניות החזרה/קדימה של קורא, עם הטאב ועם רשומת היסטוריית הקריאה.
library;

/// מספר היעדים שנשמרים בכל כיוון; בזיכרון הקורא מחזיק יותר.
const int kPersistedReadingHistoryDepth = 20;

typedef ReadingHistoryStacks<T> = ({List<T> back, List<T> forward});

/// null כשאין לאן לחזור; [at] מחזיר את המיקום בעת השמירה, ונקרא רק כשיש היסטוריה.
Map<String, Object>? encodeReadingHistory<T extends Object>({
  required List<T> back,
  required List<T> forward,
  required T? Function() at,
  required Object Function(T value) encode,
}) {
  if (back.isEmpty && forward.isEmpty) return null;
  final current = at();
  List<Object> recent(List<T> stack) => [
    for (final value in stack.skip(
      stack.length > kPersistedReadingHistoryDepth
          ? stack.length - kPersistedReadingHistoryDepth
          : 0,
    ))
      encode(value),
  ];
  return {
    'back': recent(back),
    'forward': recent(forward),
    if (current != null) 'at': encode(current),
  };
}

/// [asNewJump] — הספר נפתח ביעד אחר מהמיקום השמור: המיקום השמור הופך לנקודת
/// חזרה ומסלול הקדימה מתבטל, כמו בכל קפיצה.
ReadingHistoryStacks<T>? decodeReadingHistory<T extends Object>(
  Object? json,
  T? Function(Object? value) decode, {
  bool asNewJump = false,
}) {
  if (json is! Map) return null;
  List<T> stack(Object? raw) {
    if (raw is! List) return <T>[];
    final values = <T>[for (final value in raw) ?decode(value)];
    return values.length > kPersistedReadingHistoryDepth
        ? values.sublist(values.length - kPersistedReadingHistoryDepth)
        : values;
  }

  final back = stack(json['back']);
  if (!asNewJump) return (back: back, forward: stack(json['forward']));
  final at = decode(json['at']);
  if (at != null && back.lastOrNull != at) back.add(at);
  return (back: back, forward: <T>[]);
}
