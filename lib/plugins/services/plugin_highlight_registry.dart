import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/models/plugin_highlight.dart';

/// Registry גלובלי לשמירת highlights מפלאגינים, לפי bookId.
///
/// כל adapter כותב לכאן עם כל שינוי (set/clear), וה-viewers
/// מאזינים לשינויים דרך [ValueListenable].
class PluginHighlightRegistry {
  PluginHighlightRegistry._();
  static final PluginHighlightRegistry instance = PluginHighlightRegistry._();

  // bookId → key → PluginHighlight
  final Map<String, Map<String, PluginHighlight>> _data = {};

  // bookId → notifier
  final Map<String, ValueNotifier<List<PluginHighlight>>> _notifiers = {};

  /// מחזיר [ValueListenable] לרשימת ה-highlights של ספר מסוים.
  /// ה-viewer יכול לעטוף אותו ב-[ValueListenableBuilder].
  ValueListenable<List<PluginHighlight>> notifierFor(String bookId) {
    return _notifiers.putIfAbsent(
      bookId,
      () => ValueNotifier<List<PluginHighlight>>(const []),
    );
  }

  /// מחזיר snapshot נוכחי של ה-highlights לספר, ממוין לפי index ואחר כך start.
  List<PluginHighlight> highlightsFor(String bookId) {
    final list = _data[bookId]?.values.toList();
    if (list == null) return const [];
    list.sort((a, b) {
      final cmp = a.index.compareTo(b.index);
      if (cmp != 0) return cmp;
      return (a.start ?? 0).compareTo(b.start ?? 0);
    });
    return list;
  }

  /// עדכון highlight יחיד (set).
  void put(String bookId, String key, PluginHighlight highlight) {
    _data.putIfAbsent(bookId, () => {})[key] = highlight;
    _notify(bookId);
  }

  /// הסרת key ספציפי.
  void remove(String bookId, String key) {
    _data[bookId]?.remove(key);
    _notify(bookId);
  }

  /// הסרת כל ה-highlights לאינדקס נתון (broad clear).
  void removeForIndex(String bookId, int index) {
    final map = _data[bookId];
    if (map == null) return;
    map.removeWhere((k, _) => k == '$index' || k.startsWith('$index:'));
    _notify(bookId);
  }

  /// מחיקת כל ה-highlights של ספר.
  void clearBook(String bookId) {
    _data.remove(bookId);
    _notify(bookId);
  }

  /// מחיקת כל ה-highlights מכל הספרים.
  void clearAll() {
    final books = _data.keys.toList();
    _data.clear();
    for (final bookId in books) {
      _notify(bookId);
    }
  }

  void _notify(String bookId) {
    final notifier = _notifiers[bookId];
    if (notifier != null) {
      notifier.value = _data[bookId]?.values.toList() ?? const [];
    }
  }
}
