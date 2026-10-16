import 'dart:collection';

import 'package:otzaria_search_engine/otzaria_search_engine.dart';

/// שאילתה שהמשתמש עטף ב-`/…/` והמנוע מקבל כביטוי רגולרי. הסיווג כולו
/// במנוע ([parseUserRegex]); שאילתה שהוא דוחה מחופשת כטקסט רגיל.
abstract final class UserRegexQuery {
  static const int _cacheSize = 16;
  static final LinkedHashMap<String, UserRegexPlan?> _plans = LinkedHashMap();
  static final LinkedHashMap<String, UserRegexMatcher?> _matchers =
      LinkedHashMap();

  /// מסנן זול לפני קריאת המנוע: רק שאילתה עטופה בלוכסנים יכולה להיות רג'קס.
  /// לוכסן פנימי צמוד לרווח (`/תורה/ /משה/`) הוא כמה מילים עטופות, לא רג'קס.
  static bool _isWrapped(String trimmed) =>
      trimmed.length > 2 &&
      trimmed.startsWith('/') &&
      trimmed.endsWith('/') &&
      !_innerSlashBySpace.hasMatch(trimmed.substring(1, trimmed.length - 1));

  static final _innerSlashBySpace = RegExp(r'\s/|/\s');

  /// תוכנית החיפוש של [raw], או null כשאינה רג'קס תקין.
  static UserRegexPlan? plan(String raw) {
    final trimmed = raw.trim();
    if (!_isWrapped(trimmed)) return null;
    return _cached(_plans, trimmed, () {
      final plan = parseUserRegex(raw: trimmed);
      return plan.kind == UserRegexKind.invalid ? null : plan;
    });
  }

  static bool isValid(String raw) => plan(raw) != null;

  /// המתאם של [raw] לטקסט הספר, או null כשאינה רג'קס תקין.
  static UserRegexMatcher? matcher(String raw) {
    final trimmed = raw.trim();
    if (!isValid(trimmed)) return null;
    return _cached(
      _matchers,
      trimmed,
      () => prepareUserRegexMatcher(raw: trimmed),
    );
  }

  static T? _cached<T>(
    LinkedHashMap<String, T?> cache,
    String key,
    T? Function() create,
  ) {
    if (cache.containsKey(key)) {
      final value = cache.remove(key);
      cache[key] = value;
      return value;
    }
    final value = create();
    cache[key] = value;
    while (cache.length > _cacheSize) {
      cache.remove(cache.keys.first);
    }
    return value;
  }
}
