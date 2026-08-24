import 'package:otzaria/settings/engine/settings_repository.dart';

/// המקור היחיד לקביעה אילו הגדרות תוכנה תוסף רשאי לקרוא — משמש גם את
/// `settings.get` בגשר וגם את הערכת תנאי `when` ללא מנוע.
///
/// **המדיניות היא blocklist:** כל הגדרה שאינה חסומה כאן קריאה לתוסף שקיבל את
/// ההרשאה `settings.read`. הכלל הופך מ-allowlist ב-0.9.97, כדי שהעדפת תצוגה
/// חדשה לא תדרוש רליס של אוצריא כדי שתוסף יוכל לקרוא אותה.
///
/// חסומים: סודות ואסימונים, נתיבים במערכת הקבצים, פרטים מזהים (מייל), ותוכן
/// אישי שיש לו הרשאה נפרדת משלו או שאין לו הרשאה בכלל (סימניות, כרטיסיות
/// פתוחות, סביבות עבודה, אירועי לוח שנה, התקדמות לימוד).
class PluginSettingsAccessPolicy {
  const PluginSettingsAccessPolicy._();

  /// חלקי-מפתח שחוסמים כל מפתח שמכיל אותם. זהו העיקר בהגנה: הגדרה **חדשה**
  /// שנושאת סוד או נתיב חסומה מלידתה, בלי שמישהו יזכור להוסיף אותה לרשימה.
  static const Set<String> blockedSubstrings = {
    'password',
    'secret',
    'credential',
    'token',
    'api-key',
    'apikey',
    // נתיב במערכת הקבצים חושף את שם המשתמש ואת מבנה הדיסק, ואינו נחוץ לתוסף —
    // הגישה לקבצים עוברת דרך המרחב הפרטי או דרך `ui.pickFolder`.
    'path',
    'folder',
    'root',
    'email',
    'client-id',
  };

  /// משפחות מפתחות שחסומות בשלמותן.
  static const Set<String> blockedPrefixes = {
    // חשבון Google של המשתמש: סודות, מזהי לוחות ותאריכי סנכרון.
    'key-google-calendar',
    // אירועי לוח השנה של המשתמש — נקראים דרך `calendar.getEvents` עם ההרשאה
    // `calendar.read`, ולא בדלת האחורית של settings.
    'key-calendar-event',
    'key-protected-mode',
    // "שמור וזכור": ספרים במעקב והתקדמות הלימוד של המשתמש.
    'sz:',
    // הגדרות צורת הדף פר-ספר ופר-קטגוריה: שם הספר הוא חלק מהמפתח, ולכן
    // מניית המפתחות חושפת אילו ספרים המשתמש למד. ‎page_shape_global_visibility_‎
    // אינו כאן — הוא העדפת תצוגה גלובלית בלי זהות ספר.
    'page_shape_book_',
    'page_shape_highlight_',
    'page_shape_visibility_',
    'page_shape_use_book_settings_',
    'page_shape_view_mode_',
    'page_shape_category_',
    // מפתח קיצור פר-תוסף: קריאתו הייתה מונה את התוספים המותקנים האחרים —
    // יכולת שאין לה API ואין לה הרשאה.
    'key-shortcut-open-plugin-',
  };

  /// תוכן אישי שאינו נתפס ע"י חלק-מפתח. המפתחות מוגדרים כ-private במאגרים
  /// שלהם, ולכן מופיעים כאן כליטרלים.
  static const Set<String> blockedKeys = {
    'key-bookmarks',
    'key-tabs',
    'key-current-tab',
    'key-workspaces',
    'key-current-workspace',
    'key-current-workspace-id',
    'key-saved-alternative-words',
    'key-plugin-search-selections',
    SettingsRepository.keyCustomFolders,
    SettingsRepository.keyErrorReportSenderEmail,
  };

  static bool isBlocked(String key) {
    final normalized = key.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    if (blockedKeys.contains(normalized)) return true;
    for (final prefix in blockedPrefixes) {
      if (normalized.startsWith(prefix)) return true;
    }
    for (final part in blockedSubstrings) {
      if (normalized.contains(part)) return true;
    }
    return false;
  }

  static bool isReadable(String key) => !isBlocked(key);
}
