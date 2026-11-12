/// מנוע הריצה של מופע תוסף אחד. זהות האובייקט היא זהות המנוע: ה-dispatcher
/// משווה ב-[identical] כדי לזהות שהמופע הוחלף בזמן await.
abstract interface class PluginRuntime {
  /// מריץ [source] בדף. התוצאה אינה מוחזרת; ה-timeout באחריות הקורא.
  Future<void> evaluate(String source);

  /// משגר את [topic] ומחזיר `true` אם הדף אישר קבלה, `'no-bridge'` או
  /// `'no-page-world'` כשאין בו דף חי, וכל ערך אחר כשהאישור לא הגיע.
  Future<Object?> dispatchEventWithAck(String topic, String detailJson);

  /// השעיה מקפיאה את הדף עצמו, ולכן אירוע שאחרי החייאה דורש אישור מסירה.
  bool get freezesWhenSuspended;

  /// משעה או מחייה את הדף. false — [isCurrent] נכשל, או שבהשעיה המופע הוצג
  /// בינתיים ([isShown]). כשל של המנוע נזרק.
  Future<bool> setSuspended(
    bool suspended, {
    required bool Function() isCurrent,
    required bool Function() isShown,
  });

  /// מבטל השעיה שהתבקשה ועדיין לא אושרה.
  Future<void> cancelPendingSuspend();

  Future<void> reload();

  /// מחליף את הדף בדף ריק, כדי שהסקריפטים ייעצרו לפני פירוק.
  Future<void> unload();

  /// מעביר את פוקוס המקלדת לדף. מחזיר האם הבקשה הועברה.
  Future<bool> requestKeyboardFocus({required bool trustPageFocus});
}
