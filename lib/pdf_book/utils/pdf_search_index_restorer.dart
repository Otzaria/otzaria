/// משחזר את אינדקס ההתאמה שנשמר עם הטאב — פעם אחת, בחיפוש הראשון אחרי הפתיחה.
/// בחיפוש חדש המיקום של השאילתה הקודמת אינו מצביע על ההתאמות החדשות.
class PdfSearchIndexRestorer {
  PdfSearchIndexRestorer(this._pending);

  int? _pending;
  int? _session;

  /// החיפוש נבנה מחדש (טעינה חוזרת של המסמך) — ה-session הבא הוא הראשון.
  void resetSession() => _session = null;

  /// מחזיר את האינדקס שיש לנווט אליו עכשיו, או null.
  int? onSearcherUpdate({
    required int session,
    required bool isSearching,
    required int matchCount,
  }) {
    final pending = _pending;
    if (pending == null) return null;
    _session ??= session;
    if (session != _session) {
      _pending = null;
      return null;
    }
    // הסריקה מתחילה מהעמוד הנוכחי וגולשת, ולכן האינדקס סופי רק בסיומה.
    if (isSearching) return null;
    _pending = null;
    return pending < matchCount ? pending : null;
  }
}
