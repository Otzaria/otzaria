/// ריכוז כל ההודעות למשתמש של ריבוי החלונות.
///
/// כל טקסט שמוצג למשתמש בפתיחת חלון, בהעברת כרטיסיה בין חלונות ובגרירה
/// ביניהם מוגדר כאן בלבד — אין לכתוב מחרוזות כאלה בקבצי הפיצ'רים.
abstract class WindowMessages {
  // ── העברת כרטיסיה בין חלונות ───────────────────────────────────────────

  static const String cannotTransferTab =
      'לא ניתן להעביר את הכרטיסייה הזו לחלון אחר.';

  static const String transferFailed = 'העברת הכרטיסייה לחלון נכשלה.';

  /// היעד לא ענה בזמן. הכרטיסיה **לא** הוסרה כאן, אך ייתכן שנקלטה גם שם.
  static const String transferUnconfirmed =
      'החלון היעד לא השיב בזמן. הכרטיסייה נשארה כאן — בדוק אם היא נפתחה גם שם.';

  // ── פתיחת חלון ─────────────────────────────────────────────────────────

  static const String openWindowFailed = 'פתיחת החלון נכשלה.';

  static String windowLimitReached(int max) =>
      'אפשר לפתוח עד $max חלונות. סגור חלון כדי לפתוח חדש.';

  static const String workspaceOpenInOtherWindow =
      'שולחן העבודה הזה פתוח גם בחלון אחר. שינויים בו עלולים לדרוס זה את זה.';

  /// כרטיסיית חלון אחר בתת-התפריט "העבר לחלון קיים".
  static String peerWithTabs(String title, int tabCount) => switch (tabCount) {
    1 => '$title (כרטיסייה אחת)',
    2 => '$title (שתי כרטיסיות)',
    _ => '$title ($tabCount כרטיסיות)',
  };
}
