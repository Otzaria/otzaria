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
  'library.resolveBooks': 'library.books.read',
  'library.listRecentBooks': 'library.books.read',
  'library.getTree': 'library.books.read',
  'library.getBookContent': 'library.content.read',
  'library.getBookToc': 'library.content.read',
  'library.listBookAltStructures': 'library.content.read',
  'library.getBookAltToc': 'library.content.read',
  'library.getLinkContent': 'library.content.read',
  'library.getCommentators': pluginLinksReadPermission,
  'library.getLinks': pluginLinksReadPermission,
  'library.getLinkTargetsSummary': pluginLinksReadPermission,

  // app.*
  'app.getUserEmail': 'app.user_email.read',
  'app.openUrl': 'app.open_url',
  'app.getInfo': 'app.info.read',
  'app.getTheme': 'app.info.read',
  'app.getLocale': 'app.info.read',
  'app.getGrantedPermissions': 'app.info.read',
  'app.getConnectivity': 'app.info.read',

  // feedback.*
  'feedback.sendEmail': 'feedback.send_email',

  // shortcut.*
  'shortcut.create': 'ui.create_shortcut',

  // ui.* (בחירת תיקייה)
  'ui.pickFolder': 'fs.folder_access',

  // fs.* (user-selected files)
  'fs.pickUserFile': 'fs.user_files.read',
  'fs.resolveFileUrl': 'fs.user_files.read',
  'fs.readTextFile': 'fs.user_files.read',
  'fs.revokeFile': 'fs.user_files.read',
  'fs.beginBinaryWrite': 'fs.user_files.write',
  'fs.commitUserFileWrite': 'fs.user_files.write',
  'fs.abortBinaryWrite': 'fs.user_files.write',

  // history.*
  'history.list': 'history.read',
  'history.listSearches': 'history.read',
  'history.clear': 'history.write',
  'history.remove': 'history.write',

  // bookmarks.*
  'bookmarks.list': pluginBookmarksReadPermission,
  'bookmarks.add': pluginBookmarksWritePermission,
  'bookmarks.remove': pluginBookmarksWritePermission,

  // tools.*
  'tools.gematria': pluginToolsReadPermission,
  'tools.dictionary': pluginToolsReadPermission,

  // notifications.*
  'notifications.showInApp': 'notifications.send',
  'notifications.sendSystem': 'notifications.system',
  'notifications.scheduleSystem': 'notifications.system',
  'notifications.cancel': 'notifications.system',
  'notifications.cancelAll': 'notifications.system',
  'notifications.checkPermissions': 'notifications.system',
  'notifications.requestPermissions': 'notifications.system',

  // plugin.*
  'plugin.openSelf': 'navigation.write',
  'plugin.openOther': pluginOpenOtherPermission,

  // reader.* (new APIs)
  'reader.addContextMenuItem': 'reader.context_menu',
  'reader.removeContextMenuItem': 'reader.context_menu',
  'reader.updateContextMenuItem': 'reader.context_menu',
  'reader.addToolbarItem': 'reader.toolbar',
  'reader.removeToolbarItem': 'reader.toolbar',
  'reader.updateToolbarItem': 'reader.toolbar',
  'reader.findTextOccurrences': 'reader.open',
  'reader.getSectionTextMap': 'reader.open',
  'reader.setHighlight': 'reader.highlight',
  'reader.updateHighlight': 'reader.highlight',
  'reader.getHighlights': 'reader.highlight',
  'reader.revealHighlight': 'reader.highlight',
  'reader.clearHighlight': 'reader.highlight',
  'reader.clearAllHighlights': 'reader.highlight',
  'reader.getActiveCommentators': 'reader.open',
  'reader.setActiveCommentators': 'reader.open',
  'reader.scrollToSection': 'reader.open',
  'reader.getHighlightCapabilities': 'reader.open',
};

/// קריאת רשימת הסימניות של המשתמש. נפרדת מהכתיבה, בעקבות התקדים של
/// `notes.read`/`notes.write`.
const pluginBookmarksReadPermission = 'bookmarks.read';

/// הוספה ומחיקה של סימניות.
const pluginBookmarksWritePermission = 'bookmarks.write';

/// קריאת כלי העזר המובנים (גימטריה, מילון) — נתוני עזר של התוכנה, ללא
/// גישה לנתוני המשתמש.
const pluginToolsReadPermission = 'tools.read';

/// הרשאה לקריאת מפת הקישורים של הספרייה — המפרשים על ספר, קישורי טווח השורות
/// וסיכום היעדים. נפרדת מ-`library.content.read` כי היא חושפת מבנה בלבד.
const pluginLinksReadPermission = 'library.links.read';

/// הרשאה לפתיחת דף של תוסף **אחר** (`plugin.openOther`). נפרדת מ-navigation.write
/// כי היא מפעילה את ה-WebView של תוסף שלישי, ולא רק מזיזה את המשתמש בין מסכים.
const pluginOpenOtherPermission = 'plugin.open_other';

/// הרשאה להפעלת מנוע התוסף ברקע ללא פתיחת הדף שלו.
/// בתוסף דקלרטיבי ההפעלה נעשית רק בעקבות אירוע.
// TODO(0.9.98): להסיר את מסלול הטעינה-בעלייה של תוספי רקע — ההרשאה נשארת
// כשער להפעלה עצלה (contributes.startup); למחוק אז גם את סעיף "ריצת רקע —
// מיושן" ומדריך המעבר ב-API_REFERENCE.md.
const pluginRunOnStartupPermission = 'app.run_on_startup';

/// הרשאה לביטול הכיבוי האוטומטי של מנוע רקע שהופעל בעצלתיים.
/// תקפה רק כאשר `contributes.startup.keepAlive` הוצהר במניפסט.
const pluginBackgroundKeepAlivePermission = 'app.background_keep_alive';

/// שם ההרשאה לתרומות עלייה דקלרטיביות (`contributes.startup` במניפסט):
/// פקדים, פריטי תפריט הקשר ונתונים שנטענים ע"י Flutter בלי מנוע JS,
/// והפעלה עצלה של מופע הרקע בלחיצה/אירוע. ברירת המחדל כבויה.
const pluginStartupContributionsPermission = 'app.startup_contributions';

/// שם ההרשאה לגישה לאינטרנט. מטופלת בנפרד בממשק: במצב 'מנותק' היא מתחילה
/// כבויה במסך ההתקנה, ותוסף שהמשתמש כיבה בו הרשאה זו ממשיך להופיע גם במצב 'מנותק'.
const pluginNetworkAccessPermission = 'network.access';

/// הרשאת בחירת תיקייה (`ui.pickFolder`) — פוצלה מ-ui.feedback כי התיקייה
/// שנבחרת היא גבול ההסכמה של פעולות הקבצים (fs.extractZip / fs.deleteFile).
const pluginFolderAccessPermission = 'fs.folder_access';

/// הרשאות בסיס — מוענקות לכל תוסף אוטומטית, בלי הצהרה במניפסט ובלי הצגה
/// למשתמש. הצהרה קיימת נסבלת לתאימות לאחור (הוולידטור רק ממליץ להסירה).
const pluginBaselinePermissions = <String>{
  'plugin.storage.read',
  'plugin.storage.write',
  'app.info.read',
  'ui.feedback',
  'notifications.send',
  'events.subscribe:theme.changed',
};

/// הרשאה חדשה (key) שהצהרה ותיקה (value) נחשבת כמכסה אותה —
/// ui.pickFolder ישב היסטורית תחת ui.feedback.
const pluginLegacyPermissionAliases = <String, String>{
  pluginFolderAccessPermission: 'ui.feedback',
};

/// ההרשאות שמוצגות למשתמש ונשמרות כהחלטות: הרשאות המניפסט ללא הרשאות הבסיס.
List<String> effectiveManifestPermissions(List<String> manifestPermissions) {
  final result = <String>[];
  for (final permission in manifestPermissions) {
    if (pluginBaselinePermissions.contains(permission)) continue;
    if (!result.contains(permission)) result.add(permission);
  }
  return result;
}

/// מאחד את הרשאות הבסיס לרשימת הרשאות מוענקות — ל-boot payload,
/// ל-app.getGrantedPermissions ולאירוע plugin.permissions_changed.
List<String> withBaselinePermissions(Iterable<String> granted) {
  return {...granted, ...pluginBaselinePermissions}.toList()..sort();
}

const pluginValidPermissions = <String>[
  // ===== מידע על האפליקציה =====
  /// גישה למידע כללי על האפליקציה (גרסה, פלטפורמה, ערכת נושא)
  'app.info.read',

  /// גישה למייל המשתמש (לדיווח שגיאות)
  'app.user_email.read',

  /// פתיחת קישור (http/https) בדפדפן ברירת המחדל של מערכת ההפעלה
  'app.open_url',

  /// הפעלת מנוע התוסף ברקע לפי אירוע, בלי לפתוח את דף התוסף.
  /// ברירת מחדל: כבויה; לתוסף מדור קודם זהו שער טעינה בעלייה.
  pluginRunOnStartupPermission,

  /// השארת מנוע רקע עצל פעיל מעבר לחלון חוסר הפעילות הרגיל.
  pluginBackgroundKeepAlivePermission,

  /// תרומות עלייה דקלרטיביות (contributes.startup) — פקדים, תפריטי הקשר
  /// ונתונים שנקראים ע"י Flutter בעלייה, בלי להריץ קוד של התוסף.
  pluginStartupContributionsPermission,

  // ===== ספרייה =====
  /// חיפוש וקריאת רשימת ספרים
  'library.books.read',

  /// קריאת תוכן ספרים
  'library.content.read',

  /// קריאת מפרשים וקישורים של ספר (מבנה בלבד, ללא תוכן)
  pluginLinksReadPermission,

  // ===== חיפוש =====
  /// ביצוע חיפוש טקסט מלא
  'search.fulltext.read',

  /// הוספת שורות סטטיות לדיאלוג החיפוש.
  'search.dialog',

  // ===== קורא =====
  /// פתיחת ספרים במצב קריאה
  'reader.open',

  /// הוספת פריטים לתפריט ההקשר של הקורא
  'reader.context_menu',

  /// הוספת לחצנים ותפריטים לשורת הפקדים של מסך העיון
  'reader.toolbar',

  /// הוספה וניהול של הדגשות צבעוניות בטקסט
  'reader.highlight',

  // ===== ניווט =====
  /// מעבר בין מסכים באפליקציה
  'navigation.write',

  /// פתיחת דף של תוסף אחר המותקן אצל המשתמש
  pluginOpenOtherPermission,

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

  // ===== קבצים אישיים =====
  /// בחירה וקריאה של קבצים אישיים שהמשתמש בוחר במפורש (PDF/טקסט וכו').
  /// הגישה מוגבלת לקבצים שהמשתמש בחר בדיאלוג — לא לנתיב חופשי בדיסק.
  'fs.user_files.read',

  /// כתיבה לקובץ שהמשתמש בחר, או שמירה לקובץ חדש דרך דיאלוג „שמור בשם”.
  /// אין לתוסף דרך להזין נתיב: היעד הוא תמיד קובץ שהמשתמש בחר בדיאלוג —
  /// או בפתיחה עם `access: 'readwrite'`, או בשמירה עצמה.
  'fs.user_files.write',

  /// בחירת תיקייה בדיאלוג מערכת ועבודה על קבצים בתוכה (חילוץ/מחיקה).
  pluginFolderAccessPermission,

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

  /// גישה לשירותים מקומיים על המחשב (loopback: localhost / 127.0.0.1),
  /// למשל מודל שפה מקומי (Ollama / LM Studio). נפרדת מ-network.access —
  /// אינה מתירה גישה לאינטרנט, ולהפך.
  'network.localhost',

  // ===== משוב ומיילים =====
  /// שליחת משוב/דיווחים למייל מותאם אישית
  'feedback.send_email',

  // ===== היסטוריית קריאה =====
  /// קריאת היסטוריית קריאה וחיפושים
  'history.read',

  /// מחיקה ועריכת היסטוריית קריאה
  'history.write',

  // ===== סימניות =====
  /// קריאת רשימת הסימניות
  pluginBookmarksReadPermission,

  /// הוספה ומחיקה של סימניות
  pluginBookmarksWritePermission,

  // ===== כלי עזר =====
  /// שימוש בכלי העזר המובנים (גימטריה, מילון)
  pluginToolsReadPermission,

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

  /// הרשמה לאירועי שינוי העיר הנבחרת בלוח השנה
  'events.subscribe:calendar.city_changed',

  /// הרשמה לאירועי שינוי סביבת עבודה
  'events.subscribe:workspace.changed',

  /// הרשמה לאירועי שינוי הרשאות התוסף
  'events.subscribe:plugin.permissions_changed',

  /// הרשמה לאירועי סימון טקסט בקורא
  'events.subscribe:reader.selection_changed',
  'events.subscribe:reader.sectionContentChanged',
];
