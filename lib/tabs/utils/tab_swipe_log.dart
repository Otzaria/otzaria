/// ההחלקות האחרונות בין טאבים, לדיווח על התוכנה.
///
/// נשמרות לפי הבעלים (ה-TabsBloc של החלון), כי כל חלונות ה-Dart חולקים isolate.
abstract final class TabSwipeLog {
  static final Expando<List<Map<String, Object?>>> _byOwner = Expando();
  static const int _maxEntries = 5;

  static void add(Object owner, Map<String, Object?> swipe) {
    final entries = _byOwner[owner] ??= [];
    if (entries.length == _maxEntries) entries.removeAt(0);
    entries.add(swipe);
  }

  static List<Map<String, Object?>> of(Object owner) =>
      List.unmodifiable(_byOwner[owner] ?? const <Map<String, Object?>>[]);
}
