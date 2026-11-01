/// אילו ספרים מוצגים באיתור הספרים כשכפתור `providerBooksFilter` של תוסף
/// קיים בשדה.
enum PluginLibraryBooksSource {
  all,
  pluginOnly,
  libraryOnly;

  /// הלחיצה הבאה: הכול ← ספרי התוסף ← ספרי הספרייה ← הכול.
  PluginLibraryBooksSource get next => switch (this) {
    all => pluginOnly,
    pluginOnly => libraryOnly,
    libraryOnly => all,
  };
}

/// המצב הפעיל של הכפתור: [pluginId] הוא התוסף שהכפתור שלו נלחץ אחרון, ו-null
/// כש-[source] הוא [PluginLibraryBooksSource.all].
class PluginLibraryBooksFilter {
  static const all = PluginLibraryBooksFilter._(
    null,
    PluginLibraryBooksSource.all,
  );

  final String? pluginId;
  final PluginLibraryBooksSource source;

  const PluginLibraryBooksFilter._(this.pluginId, this.source);

  /// המצב אחרי לחיצה על הכפתור של [pluginId]. כפתור של תוסף אחר מתחיל
  /// מחזור חדש ממצב "הכול".
  PluginLibraryBooksFilter pressedBy(String pluginId) {
    final current = this.pluginId == pluginId
        ? source
        : PluginLibraryBooksSource.all;
    final next = current.next;
    return next == PluginLibraryBooksSource.all
        ? all
        : PluginLibraryBooksFilter._(pluginId, next);
  }

  /// המצב שכפתור של [pluginId] מציג.
  PluginLibraryBooksSource sourceFor(String pluginId) =>
      this.pluginId == pluginId ? source : PluginLibraryBooksSource.all;

  @override
  bool operator ==(Object other) =>
      other is PluginLibraryBooksFilter &&
      other.pluginId == pluginId &&
      other.source == source;

  @override
  int get hashCode => Object.hash(pluginId, source);
}
