/// מיפוי משמות שיטות API לשמות ההרשאות הנדרשות - לשימוש בהודעות שגיאה מועילות
const Map<String, String> apiCallToPermissionHint = {
  // database.*
  'database.listSources': 'database.read',
  'database.describeSource': 'database.read',
  'database.query': 'database.read',
  'database.batchQuery': 'database.read',

  // library.*
  'library.findBooks': 'library.books.read',
  'library.getBookMetadata': 'library.books.read',
  'library.listRecentBooks': 'library.books.read',
  'library.getTree': 'library.books.read',
  'library.getBookContent': 'library.content.read',
  'library.getBookToc': 'library.content.read',

  // app.*
  'app.getUserEmail': 'app.user_email.read',
  'app.getInfo': 'app.info.read',
  'app.getTheme': 'app.info.read',
  'app.getLocale': 'app.info.read',
  'app.getGrantedPermissions': 'app.info.read',

  // feedback.*
  'feedback.sendEmail': 'feedback.send_email',

  // shortcut.*
  'shortcut.create': 'ui.create_shortcut',

  // history.*
  'history.list': 'history.read',
  'history.listSearches': 'history.read',
  'history.clear': 'history.write',
  'history.remove': 'history.write',

  // notifications.*
  'notifications.showInApp': 'notifications.send',
  'notifications.sendSystem': 'notifications.system',
  'notifications.scheduleSystem': 'notifications.system',
  'notifications.cancel': 'notifications.system',
  'notifications.cancelAll': 'notifications.system',
  'notifications.checkPermissions': 'notifications.system',
  'notifications.requestPermissions': 'notifications.system',

  // reader.* (new APIs)
  'reader.addContextMenuItem': 'reader.context_menu',
  'reader.removeContextMenuItem': 'reader.context_menu',
  'reader.setHighlight': 'reader.highlight',
  'reader.getHighlights': 'reader.highlight',
  'reader.clearHighlight': 'reader.highlight',
  'reader.clearAllHighlights': 'reader.highlight',
};

/// רשימת כל ההרשאות התקפות שתוסף יכול לבקש
///
/// הרשאות אלו מאפשרות לתוספים לגשת לפונקציונליות שונות של אוצריא.
/// כל הרשאה חייבת להיות מוגדרת ב-manifest.json של התוסף.
/// שם ההרשאה לטעינת התוסף ברקע עם עליית האפליקציה.
///
/// הרשאה זו רגישה במיוחד: כאשר היא מוענקת, התוסף ירוץ בכל פעם
/// שאוצריא נטענת, גם בלי שהמשתמש נכנס למסך "כלים". מטופלת בנפרד
/// בממשק (ברירת מחדל: כבויה, בולטת חזותית במסך ההתקנה).
const pluginRunOnStartupPermission = 'app.run_on_startup';

const pluginValidPermissions = <String>[
  // ===== מידע על האפליקציה =====
  /// גישה למידע כללי על האפליקציה (גרסה, פלטפורמה, ערכת נושא)
  'app.info.read',

  /// גישה למייל המשתמש (לדיווח שגיאות)
  'app.user_email.read',

  /// טעינת התוסף ברקע עם עליית האפליקציה (גם בלי לפתוח את מסך "כלים").
  /// ברירת מחדל: כבויה — מאחר שזו הרשאה רגישה שמרחיבה את משך הריצה של התוסף.
  pluginRunOnStartupPermission,

  // ===== ספרייה =====
  /// חיפוש וקריאת רשימת ספרים
  'library.books.read',

  /// קריאת תוכן ספרים
  'library.content.read',

  // ===== חיפוש =====
  /// ביצוע חיפוש טקסט מלא
  'search.fulltext.read',

  // ===== קורא =====
  /// פתיחת ספרים במצב קריאה
  'reader.open',

  /// הוספת פריטים לתפריט ההקשר של הקורא
  'reader.context_menu',

  /// הוספה וניהול של הדגשות צבעוניות בטקסט
  'reader.highlight',

  // ===== ניווט =====
  /// מעבר בין מסכים באפליקציה
  'navigation.write',

  // ===== הערות אישיות =====
  /// קריאת הערות אישיות
  'notes.read',

  /// כתיבה ועריכת הערות אישיות
  'notes.write',

  // ===== לוח שנה =====
  /// גישה ללוח השנה העברי, זמנים הלכתיים ואירועים
  'calendar.read',

  // ===== הגדרות =====
  /// קריאת הגדרות האפליקציה (רק מרשימה מאושרת)
  'settings.read',

  // ===== ממשק משתמש =====
  /// הצגת הודעות ודיאלוגים למשתמש
  'ui.feedback',

  /// יצירת קיצור דרך (deep-link) בשולחן העבודה / תפריט ההתחל
  'ui.create_shortcut',

  // ===== אחסון תוסף =====
  /// קריאה מאחסון מפתח-ערך של התוסף
  'plugin.storage.read',

  /// כתיבה לאחסון מפתח-ערך של התוסף
  'plugin.storage.write',

  // ===== פרסום נתונים =====
  /// פרסום נתונים מהתוסף לאפליקציה (למשל אירועי לוח שנה)
  'published_data.write',

  // ===== רשת =====
  /// גישה לאינטרנט (לתוספים שצריכים לטעון משאבים חיצוניים)
  'network.access',

  // ===== משוב ומיילים =====
  /// שליחת משוב/דיווחים למייל מותאם אישית
  'feedback.send_email',

  // ===== היסטוריית קריאה =====
  /// קריאת היסטוריית קריאה וחיפושים
  'history.read',

  /// מחיקה ועריכת היסטוריית קריאה
  'history.write',

  // ===== מסד נתונים =====
  /// קריאת נתונים ממקורות SQLite שהאפליקציה מאשרת לתוסף
  'database.read',

  // ===== התראות =====
  /// הצגת התראות בתוך האפליקציה (UiSnack)
  'notifications.send',

  /// שליחת התראות למערכת ההפעלה
  'notifications.system',

  // ===== אירועים (Events) =====
  /// הרשמה לאירועי שינוי ניווט
  'events.subscribe:navigation.changed',

  /// הרשמה לאירועי שינוי ספר נוכחי
  'events.subscribe:reader.current_book_changed',

  /// הרשמה לאירועי שינוי מיקום בקורא
  'events.subscribe:reader.current_ref_changed',

  /// הרשמה לאירועי שינוי ערכת נושא
  'events.subscribe:theme.changed',

  /// הרשמה לאירועי שינוי הגדרות
  'events.subscribe:settings.changed',

  /// הרשמה לאירועי שינוי תאריך בלוח השנה
  'events.subscribe:calendar.date_changed',

  /// הרשמה לאירועי שינוי סביבת עבודה
  'events.subscribe:workspace.changed',

  /// הרשמה לאירועי שינוי הרשאות התוסף
  'events.subscribe:plugin.permissions_changed',

  /// הרשמה לאירועי סימון טקסט בקורא
  'events.subscribe:reader.selection_changed',
];
