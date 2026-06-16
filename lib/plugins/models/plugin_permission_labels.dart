/// מידע תצוגה עבור הרשאת תוסף — שם עברי ותיאור קצר
class PluginPermissionInfo {
  /// שם קצר בעברית (מוצג כותרת)
  final String label;

  /// תיאור מה ההרשאה מאפשרת (מוצג כsubtitle)
  final String description;

  const PluginPermissionInfo({required this.label, required this.description});
}

/// מחזיר מידע תצוגה עבור הרשאה בשמה הטכני.
/// אם ההרשאה אינה מוכרת, מחזיר את שמה הטכני עם תיאור גנרי.
PluginPermissionInfo getPermissionInfo(String permissionKey) {
  return _permissionLabels[permissionKey] ??
      PluginPermissionInfo(
        label: permissionKey,
        description: 'גישה לפונקציונליות: $permissionKey',
      );
}

/// מיפוי מלא של כל ההרשאות התקפות לשם ותיאור בעברית
const Map<String, PluginPermissionInfo> _permissionLabels = {
  // ===== מידע על האפליקציה =====
  'app.info.read': PluginPermissionInfo(
    label: 'מידע אפליקציה',
    description: 'קריאת מידע כללי על האפליקציה: גרסה, פלטפורמה, ערכת נושא',
  ),
  'app.user_email.read': PluginPermissionInfo(
    label: 'כתובת מייל',
    description: 'גישה לכתובת המייל של המשתמש, לשימוש בדיווח שגיאות בלבד',
  ),
  'app.run_on_startup': PluginPermissionInfo(
    label: 'טעינה אוטומטית עם עליית האפליקציה',
    description:
        'התוסף ייטען ויפעל ברקע מיד עם עליית אוצריא, גם בלי להיכנס למסך "כלים". מומלץ רק לתוספים שצריכים לעקוב אחרי אירועים או לתזמן פעולות.',
  ),

  // ===== ספרייה =====
  'library.books.read': PluginPermissionInfo(
    label: 'רשימת ספרים',
    description: 'חיפוש וצפייה ברשימת כל הספרים בספרייה',
  ),
  'library.content.read': PluginPermissionInfo(
    label: 'תוכן ספרים',
    description: 'קריאת תוכן הספרים מהספרייה',
  ),

  // ===== חיפוש =====
  'search.fulltext.read': PluginPermissionInfo(
    label: 'חיפוש טקסט מלא',
    description: 'ביצוע חיפושי טקסט ברחבי כל הספרייה',
  ),

  // ===== קורא =====
  'reader.open': PluginPermissionInfo(
    label: 'פתיחת ספרים',
    description: 'פתיחת ספרים בקורא האפליקציה',
  ),

  // ===== ניווט =====
  'navigation.write': PluginPermissionInfo(
    label: 'ניווט במסכים',
    description: 'מעבר בין מסכים שונים באפליקציה',
  ),

  // ===== הערות אישיות =====
  'notes.read': PluginPermissionInfo(
    label: 'צפייה בהערות',
    description: 'קריאה וצפייה בהערות האישיות שלך',
  ),
  'notes.write': PluginPermissionInfo(
    label: 'עריכת הערות',
    description: 'יצירה, עריכה ומחיקה של הערות אישיות',
  ),

  // ===== לוח שנה =====
  'calendar.read': PluginPermissionInfo(
    label: 'לוח שנה עברי',
    description: 'גישה ללוח השנה העברי, זמנים הלכתיים ואירועים',
  ),

  // ===== הגדרות =====
  'settings.read': PluginPermissionInfo(
    label: 'הגדרות האפליקציה',
    description: 'קריאת הגדרות האפליקציה (רק הגדרות שאושרו לתוספים)',
  ),

  // ===== ממשק משתמש =====
  'ui.feedback': PluginPermissionInfo(
    label: 'הודעות ודיאלוגים',
    description: 'הצגת הודעות, דיאלוגים ועדכונים בממשק המשתמש',
  ),
  'ui.create_shortcut': PluginPermissionInfo(
    label: 'יצירת קיצור דרך',
    description: 'יצירת קיצור דרך בשולחן העבודה או בתפריט ההתחל (לאחר אישור)',
  ),

  // ===== אחסון תוסף =====
  'plugin.storage.read': PluginPermissionInfo(
    label: 'אחסון מקומי — קריאה',
    description: 'קריאת נתונים שהתוסף שמר בעבר על המכשיר',
  ),
  'plugin.storage.write': PluginPermissionInfo(
    label: 'אחסון מקומי — כתיבה',
    description: 'שמירת נתוני התוסף על המכשיר',
  ),

  // ===== פרסום נתונים =====
  'published_data.write': PluginPermissionInfo(
    label: 'שיתוף נתונים עם האפליקציה',
    description:
        'פרסום נתונים מהתוסף לחלקים אחרים באפליקציה (כגון אירועי לוח שנה)',
  ),

  // ===== רשת =====
  'network.access': PluginPermissionInfo(
    label: 'גישה לאינטרנט',
    description: 'שליחה וקבלה של מידע מרשת האינטרנט',
  ),

  // ===== משוב ומיילים =====
  'feedback.send_email': PluginPermissionInfo(
    label: 'שליחת מייל',
    description: 'שליחת משוב ודיווחים לכתובת מייל שהתוסף מגדיר',
  ),

  // ===== היסטוריית קריאה =====
  'history.read': PluginPermissionInfo(
    label: 'היסטוריית קריאה — צפייה',
    description: 'צפייה בהיסטוריית הקריאה והחיפושים שלך',
  ),
  'history.write': PluginPermissionInfo(
    label: 'היסטוריית קריאה — עריכה',
    description: 'מחיקה ועריכה של היסטוריית הקריאה',
  ),

  // ===== מסד נתונים =====
  'database.read': PluginPermissionInfo(
    label: 'קריאת מסד נתונים',
    description: 'קריאת נתונים ממקורות SQLite שהאפליקציה מאשרת לתוסף',
  ),

  // ===== התראות =====
  'notifications.send': PluginPermissionInfo(
    label: 'הודעות מובנות',
    description: 'הצגת הודעות פופ-אפ בתוך האפליקציה',
  ),
  'notifications.system': PluginPermissionInfo(
    label: 'התראות מערכת',
    description: 'שליחת התראות למערכת ההפעלה (גם כשהאפליקציה סגורה)',
  ),

  // ===== אירועים =====
  'events.subscribe:navigation.changed': PluginPermissionInfo(
    label: 'אירועי ניווט',
    description: 'קבלת עדכון בכל פעם שמשתמש עובר בין מסכים',
  ),
  'events.subscribe:reader.current_book_changed': PluginPermissionInfo(
    label: 'אירועי פתיחת ספר',
    description: 'קבלת עדכון בכל פעם שנפתח ספר חדש בקורא',
  ),
  'events.subscribe:reader.current_ref_changed': PluginPermissionInfo(
    label: 'אירועי שינוי מיקום',
    description: 'קבלת עדכון בכל פעם שמיקום הקריאה משתנה (דף, פרק, סעיף)',
  ),
  'events.subscribe:theme.changed': PluginPermissionInfo(
    label: 'אירועי ערכת נושא',
    description: 'קבלת עדכון בכל פעם שמשתמש מחליף ערכת נושא',
  ),
  'events.subscribe:settings.changed': PluginPermissionInfo(
    label: 'אירועי הגדרות',
    description: 'קבלת עדכון בכל פעם שמשתמש משנה הגדרה',
  ),
  'events.subscribe:calendar.date_changed': PluginPermissionInfo(
    label: 'אירועי שינוי תאריך',
    description: 'קבלת עדכון בכל פעם שמשתמש מחליף תאריך בלוח השנה',
  ),
  'events.subscribe:workspace.changed': PluginPermissionInfo(
    label: 'אירועי סביבת עבודה',
    description: 'קבלת עדכון בכל פעם שמשתמש מחליף סביבת עבודה',
  ),
  'events.subscribe:plugin.permissions_changed': PluginPermissionInfo(
    label: 'אירועי שינוי הרשאות',
    description: 'קבלת עדכון בכל פעם שהרשאות התוסף משתנות',
  ),
};
