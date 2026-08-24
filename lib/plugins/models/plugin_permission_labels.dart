import 'package:flutter/widgets.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_startup_contributions.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';

/// מידע תצוגה עבור הרשאת תוסף — שם עברי, תיאור קצר ואייקון לפי התחום
class PluginPermissionInfo {
  /// שם קצר בעברית (מוצג כותרת)
  final String label;

  /// תיאור מה ההרשאה מאפשרת (מוצג כsubtitle)
  final String description;

  /// אייקון שמזהה את תחום ההרשאה. מצב ההענקה מובע בצבע, לא באייקון.
  final IconData icon;

  const PluginPermissionInfo({
    required this.label,
    required this.description,
    required this.icon,
  });
}

/// האייקון להצגה לצד הרשאה בשני מסכי ההרשאות.
/// הרשאות רגישות מקבלות אזהרה שגוברת על אייקון התחום.
IconData pluginPermissionIcon(
  String permission, {
  required bool isGranted,
  PluginManifest? manifest,
}) {
  final isSensitive =
      permission == pluginRunOnStartupPermission ||
      permission == pluginBackgroundKeepAlivePermission;
  if (isSensitive) {
    return isGranted
        ? FluentIcons.warning_24_filled
        : FluentIcons.warning_24_regular;
  }
  return getPermissionInfo(permission, manifest: manifest).icon;
}

/// מחזיר מידע תצוגה עבור הרשאה בשמה הטכני.
/// אם ההרשאה אינה מוכרת, מחזיר את שמה הטכני עם תיאור גנרי.
PluginPermissionInfo getPermissionInfo(
  String permissionKey, {
  PluginManifest? manifest,
}) {
  if (permissionKey == pluginRunOnStartupPermission && manifest != null) {
    final startup = manifest.startup;
    if (startup != null && !startup.isEmpty) {
      if (!startup.hasBackgroundActivationTrigger) {
        return const PluginPermissionInfo(
          label: 'הפעלה ברקע לפי אירוע',
          icon: FluentIcons.power_24_regular,
          description:
              'לא הוגדר אירוע שמפעיל מנוע רקע, ולכן הרשאה זו אינה בשימוש '
              'בגרסה הנוכחית של התוסף.',
        );
      }
      final reasons = pluginBackgroundActivationReasons(manifest).join(', ');
      return PluginPermissionInfo(
        label: 'הפעלה ברקע לפי אירוע',
        icon: FluentIcons.power_24_regular,
        description:
            'התוסף יפעיל מנוע WebView ברקע כאשר: $reasons. המנוע יכובה אחרי '
            '3 דקות ללא פעילות, אלא אם תאושר גם מניעת הכיבוי.',
      );
    }
  }
  return _permissionLabels[permissionKey] ??
      PluginPermissionInfo(
        label: permissionKey,
        icon: FluentIcons.shield_24_regular,
        description: 'גישה לפונקציונליות: $permissionKey',
      );
}

/// מחזיר תיאור ידידותי של האירועים שעשויים להפעיל את מנוע התוסף ברקע.
List<String> pluginBackgroundActivationReasons(PluginManifest manifest) {
  final startup = manifest.startup;
  if (startup == null || startup.isEmpty) return const ['עליית אוצריא'];

  final reasons = <String>{};
  if (startup.toolbarItems.any(_toolbarItemActivatesBackground)) {
    reasons.add('לחיצה על פקד בשורת העיון');
  }
  if (startup.contextMenuItems.any(_contextMenuItemActivatesBackground)) {
    reasons.add('לחיצה על פריט בתפריט הטקסט');
  }
  for (final topic in startup.activationEvents) {
    if (topic == PluginStartupContributions.startupActivationTopic) {
      reasons.add('עליית אוצריא');
      continue;
    }
    // אירוע ממוקד של ספק חיפוש חיצוני — אין לו הרשאת subscribe ולכן גם
    // לא תווית ברשימת ההרשאות.
    if (topic == 'search.external.requested') {
      reasons.add('בקשת חיפוש ממסך החיפוש המובנה');
      continue;
    }
    reasons.add(
      _permissionLabels['events.subscribe:$topic']?.label ?? 'האירוע $topic',
    );
  }
  return List.unmodifiable(reasons);
}

bool _toolbarItemActivatesBackground(Map<String, dynamic> item) =>
    PluginStartupContributions(
      toolbarItems: [
        item,
      ],
    ).hasBackgroundActivationTrigger;

bool _contextMenuItemActivatesBackground(Map<String, dynamic> item) =>
    PluginStartupContributions(
      contextMenuItems: [
        item,
      ],
    ).hasBackgroundActivationTrigger;

/// האם הרשאה מתחילה מאושרת במסך ההתקנה.
///
/// הרשאות כתיבה לנתוני המשתמש (notes.write, history.write, bookmarks.write)
/// מתחילות מאושרות ומסתמכות על התווית שמפרשת את ההשלכה; רק הרשאות בעלות
/// עלות מתמשכת לתהליך (עלייה/רקע) ורשת במצב מנותק מתחילות כבויות.
bool pluginPermissionDefaultGrant(
  String permission, {
  required bool isOfflineMode,
}) {
  if (permission == pluginRunOnStartupPermission ||
      permission == pluginStartupContributionsPermission ||
      permission == pluginBackgroundKeepAlivePermission) {
    return false;
  }
  return !(isOfflineMode && permission == pluginNetworkAccessPermission);
}

/// מסדר הרשאות רגישות לפני שאר הרשאות המניפסט.
List<String> orderedPluginPermissions(
  List<String> permissions, {
  required bool isOfflineMode,
}) {
  int rank(String permission) => switch (permission) {
    pluginRunOnStartupPermission => 0,
    pluginStartupContributionsPermission => 1,
    pluginBackgroundKeepAlivePermission => 2,
    pluginNetworkAccessPermission when isOfflineMode => 3,
    _ => 4,
  };
  final indexed = permissions.indexed.toList();
  indexed.sort((a, b) {
    final rankComparison = rank(a.$2).compareTo(rank(b.$2));
    return rankComparison != 0 ? rankComparison : a.$1.compareTo(b.$1);
  });
  return indexed.map((entry) => entry.$2).toList(growable: false);
}

/// מיפוי מלא של כל ההרשאות התקפות לשם ותיאור בעברית
const Map<String, PluginPermissionInfo> _permissionLabels = {
  // ===== מידע על האפליקציה =====
  'app.info.read': PluginPermissionInfo(
    label: 'מידע אפליקציה',
    icon: FluentIcons.info_24_regular,
    description: 'קריאת מידע כללי על האפליקציה: גרסה, פלטפורמה, ערכת נושא',
  ),
  'app.user_email.read': PluginPermissionInfo(
    label: 'כתובת מייל',
    icon: FluentIcons.mail_24_regular,
    description: 'גישה לכתובת המייל של המשתמש, לשימוש בדיווח שגיאות בלבד',
  ),
  'app.open_url': PluginPermissionInfo(
    label: 'פתיחת קישורים בדפדפן',
    icon: FluentIcons.globe_24_regular,
    description:
        'פתיחת כתובות אינטרנט (http/https) בדפדפן ברירת המחדל של מערכת ההפעלה',
  ),
  'app.run_on_startup': PluginPermissionInfo(
    label: 'טעינה אוטומטית ברקע',
    icon: FluentIcons.power_24_regular,
    description:
        'תוסף מדור קודם ייטען עם עליית אוצריא ויישאר פעיל כל עוד התוכנה פתוחה.',
  ),
  'app.background_keep_alive': PluginPermissionInfo(
    label: 'מניעת כיבוי מנוע הרקע',
    icon: FluentIcons.hourglass_24_regular,
    description:
        'התוסף מבקש להשאיר את מנוע ה-WebView פעיל ללא הגבלת זמן. הדבר מגדיל '
        'את צריכת הזיכרון והמעבד; אשר רק לתוסף מהימן שחייב להאזין ברציפות.',
  ),
  'app.startup_contributions': PluginPermissionInfo(
    label: 'הוספת רכיבים לתוכנה',
    icon: FluentIcons.puzzle_piece_24_regular,
    description:
        'מאפשר לתוסף להוסיף פקדים, פריטי תפריט ונתונים שמנוהלים בידי אוצריא. '
        'פעולות מובנות עשויות להתבצע בלי לפתוח את דף התוסף.',
  ),

  // ===== ספרייה =====
  'library.books.read': PluginPermissionInfo(
    label: 'רשימת ספרים',
    icon: FluentIcons.library_24_regular,
    description: 'חיפוש וצפייה ברשימת כל הספרים בספרייה',
  ),
  'library.content.read': PluginPermissionInfo(
    label: 'תוכן ספרים',
    icon: OtzariaIcons.book_24_regular,
    description: 'קריאת תוכן הספרים מהספרייה',
  ),
  'library.links.read': PluginPermissionInfo(
    label: 'מפרשים וקישורים',
    icon: FluentIcons.link_24_regular,
    description:
        'צפייה ברשימת המפרשים של ספר ובקישורים בין הספרים, בלי תוכן הספרים',
  ),

  // ===== חיפוש =====
  'search.fulltext.read': PluginPermissionInfo(
    label: 'חיפוש טקסט מלא',
    icon: OtzariaIcons.search_in_the_library_24_regular,
    description: 'ביצוע חיפושי טקסט ברחבי כל הספרייה',
  ),
  'search.dialog': PluginPermissionInfo(
    label: 'רכיבים בחלון החיפוש',
    icon: FluentIcons.search_24_regular,
    description: 'הוספת שורות סטטיות לדיאלוג החיפוש, ללא הפעלת קוד התוסף ברקע',
  ),

  // ===== קורא =====
  'reader.open': PluginPermissionInfo(
    label: 'פתיחת ספרים',
    icon: OtzariaIcons.otzaria_icon_2_page_24_regular,
    description: 'פתיחת ספרים בקורא האפליקציה',
  ),

  'reader.context_menu': PluginPermissionInfo(
    label: 'פריטים בתפריט הטקסט',
    icon: FluentIcons.text_bullet_list_square_24_regular,
    description:
        'הוספת פריטים לתפריט ההקשר של הטקסט. בלחיצה עליהם התוסף מקבל את '
        'הטקסט שסימנת',
  ),
  'reader.toolbar': PluginPermissionInfo(
    label: 'פקדים בשורת העיון',
    icon: FluentIcons.app_title_24_regular,
    description: 'הוספת לחצנים ותפריטים לשורת הפקדים של מסך העיון',
  ),
  'reader.highlight': PluginPermissionInfo(
    label: 'הדגשות בטקסט',
    icon: FluentIcons.highlight_24_regular,
    description:
        'הוספה, שינוי ומחיקה של הדגשות צבעוניות בטקסט הספר. אינה משנה את '
        'תוכן הספר',
  ),

  // ===== ניווט =====
  'navigation.write': PluginPermissionInfo(
    label: 'ניווט במסכים',
    icon: FluentIcons.navigation_24_regular,
    description: 'מעבר בין מסכים שונים באפליקציה',
  ),
  'plugin.open_other': PluginPermissionInfo(
    label: 'פתיחת תוסף אחר',
    icon: FluentIcons.apps_list_24_regular,
    description:
        'פתיחת דף של תוסף אחר שמותקן אצלך, כולל הפעלת הקוד שלו. התוסף הנפתח '
        'פועל בהרשאות שלו בלבד',
  ),

  // ===== הערות אישיות =====
  'notes.read': PluginPermissionInfo(
    label: 'צפייה בהערות',
    icon: FluentIcons.note_24_regular,
    description: 'קריאה וצפייה בהערות האישיות שלך',
  ),
  'notes.write': PluginPermissionInfo(
    label: 'עריכת הערות',
    icon: FluentIcons.note_edit_24_regular,
    description: 'יצירה, עריכה ומחיקה של הערות אישיות',
  ),

  // ===== לוח שנה =====
  'calendar.read': PluginPermissionInfo(
    label: 'לוח שנה עברי',
    icon: OtzariaIcons.calendar_24_regular,
    description: 'גישה ללוח השנה העברי, זמנים הלכתיים ואירועים',
  ),

  // ===== הגדרות =====
  'settings.read': PluginPermissionInfo(
    label: 'הגדרות האפליקציה',
    icon: FluentIcons.settings_24_regular,
    description: 'קריאת הגדרות האפליקציה (רק הגדרות שאושרו לתוספים)',
  ),

  // ===== ממשק משתמש =====
  'ui.feedback': PluginPermissionInfo(
    label: 'הודעות ודיאלוגים',
    icon: FluentIcons.chat_24_regular,
    description: 'הצגת הודעות, דיאלוגים ועדכונים בממשק המשתמש',
  ),
  'ui.create_shortcut': PluginPermissionInfo(
    label: 'יצירת קיצור דרך',
    icon: FluentIcons.desktop_24_regular,
    description: 'יצירת קיצור דרך בשולחן העבודה או בתפריט ההתחל (לאחר אישור)',
  ),

  // ===== קבצים אישיים =====
  'fs.user_files.read': PluginPermissionInfo(
    label: 'קבצים אישיים',
    icon: FluentIcons.document_24_regular,
    description:
        'בחירה וקריאה של קבצים שתבחר במפורש בדיאלוג — לא גישה חופשית לדיסק',
  ),
  'fs.user_files.write': PluginPermissionInfo(
    label: 'שמירה לקבצים אישיים',
    icon: FluentIcons.save_24_regular,
    description:
        'שמירה לקובץ שתבחר בדיאלוג, או יצירת קובץ חדש דרך „שמור בשם” — '
        'לא כתיבה חופשית לדיסק',
  ),
  'fs.folder_access': PluginPermissionInfo(
    label: 'גישה לתיקייה שתבחר',
    icon: FluentIcons.folder_24_regular,
    description:
        'בחירת תיקייה בדיאלוג מערכת ועבודה על קבצים בתוכה (חילוץ ומחיקה). '
        'הגישה מוגבלת לתיקיות שאישרת בדיאלוג בלבד',
  ),

  // ===== אחסון תוסף =====
  'plugin.storage.read': PluginPermissionInfo(
    label: 'אחסון מקומי — קריאה',
    icon: FluentIcons.database_24_regular,
    description: 'קריאת נתונים שהתוסף שמר בעבר על המכשיר',
  ),
  'plugin.storage.write': PluginPermissionInfo(
    label: 'אחסון מקומי — כתיבה',
    icon: FluentIcons.save_24_regular,
    description: 'שמירת נתוני התוסף על המכשיר',
  ),

  // ===== פרסום נתונים =====
  'published_data.write': PluginPermissionInfo(
    label: 'שיתוף נתונים עם האפליקציה',
    icon: FluentIcons.share_24_regular,
    description:
        'פרסום נתונים מהתוסף לחלקים אחרים באפליקציה (כגון אירועי לוח שנה)',
  ),

  // ===== רשת =====
  'network.access': PluginPermissionInfo(
    label: 'גישה לאינטרנט',
    icon: FluentIcons.globe_24_regular,
    description: 'שליחה וקבלה של מידע מרשת האינטרנט',
  ),
  'network.localhost': PluginPermissionInfo(
    label: 'גישה לשירותים מקומיים',
    icon: FluentIcons.plug_connected_24_regular,
    description:
        'התחברות לשירותים שרצים על המחשב שלך (localhost), כגון מודל שפה מקומי (Ollama / LM Studio). אינה מאפשרת גישה לאינטרנט.',
  ),

  // ===== משוב ומיילים =====
  'feedback.send_email': PluginPermissionInfo(
    label: 'שליחת מייל',
    icon: FluentIcons.send_24_regular,
    description: 'שליחת משוב ודיווחים לכתובת מייל שהתוסף מגדיר',
  ),

  // ===== היסטוריית קריאה =====
  'history.read': PluginPermissionInfo(
    label: 'היסטוריית קריאה — צפייה',
    icon: FluentIcons.history_24_regular,
    description: 'צפייה בהיסטוריית הקריאה והחיפושים שלך',
  ),
  'history.write': PluginPermissionInfo(
    label: 'היסטוריית קריאה — עריכה',
    icon: FluentIcons.history_dismiss_24_regular,
    description: 'מחיקה ועריכה של היסטוריית הקריאה',
  ),

  // ===== סימניות =====
  'bookmarks.read': PluginPermissionInfo(
    label: 'סימניות — צפייה',
    icon: OtzariaIcons.book_star_24_regular,
    description: 'קריאת רשימת הסימניות שלך, כולל שמות הספרים והמיקומים בהם',
  ),
  'bookmarks.write': PluginPermissionInfo(
    label: 'סימניות — הוספה ומחיקה',
    icon: FluentIcons.bookmark_off_24_regular,
    description:
        'הוספת סימניות חדשות וגם מחיקה של סימניות קיימות שיצרת. מחיקה היא '
        'סופית — אין שחזור.',
  ),

  // ===== כלי עזר =====
  'tools.read': PluginPermissionInfo(
    label: 'כלי עזר מובנים',
    icon: FluentIcons.toolbox_24_regular,
    description:
        'שימוש בכלי הגימטריה והמילון של אוצריא. נתוני עזר של התוכנה בלבד, '
        'ללא גישה לנתונים שלך',
  ),

  // ===== מסד נתונים =====
  'database.read': PluginPermissionInfo(
    label: 'קריאת מסד נתונים',
    icon: FluentIcons.database_24_regular,
    description: 'קריאת נתונים ממקורות SQLite שהאפליקציה מאשרת לתוסף',
  ),

  // ===== התראות =====
  'notifications.send': PluginPermissionInfo(
    label: 'הודעות מובנות',
    icon: FluentIcons.alert_24_regular,
    description: 'הצגת הודעות פופ-אפ בתוך האפליקציה',
  ),
  'notifications.system': PluginPermissionInfo(
    label: 'התראות מערכת',
    icon: FluentIcons.alert_urgent_24_regular,
    description: 'שליחת התראות למערכת ההפעלה (גם כשהאפליקציה סגורה)',
  ),

  // ===== אירועים =====
  'events.subscribe:navigation.changed': PluginPermissionInfo(
    label: 'אירועי ניווט',
    icon: FluentIcons.navigation_24_regular,
    description: 'קבלת עדכון בכל פעם שמשתמש עובר בין מסכים',
  ),
  'events.subscribe:reader.current_book_changed': PluginPermissionInfo(
    label: 'אירועי פתיחת ספר',
    icon: OtzariaIcons.otzaria_icon_2_page_24_regular,
    description: 'קבלת עדכון בכל פעם שנפתח ספר חדש בקורא',
  ),
  'events.subscribe:reader.current_ref_changed': PluginPermissionInfo(
    label: 'אירועי שינוי מיקום',
    icon: FluentIcons.location_24_regular,
    description: 'קבלת עדכון בכל פעם שמיקום הקריאה משתנה (דף, פרק, סעיף)',
  ),
  'events.subscribe:theme.changed': PluginPermissionInfo(
    label: 'אירועי ערכת נושא',
    icon: FluentIcons.color_24_regular,
    description: 'קבלת עדכון בכל פעם שמשתמש מחליף ערכת נושא',
  ),
  'events.subscribe:settings.changed': PluginPermissionInfo(
    label: 'אירועי הגדרות',
    icon: FluentIcons.settings_24_regular,
    description: 'קבלת עדכון בכל פעם שמשתמש משנה הגדרה',
  ),
  'events.subscribe:calendar.date_changed': PluginPermissionInfo(
    label: 'אירועי שינוי תאריך',
    icon: OtzariaIcons.calendar_24_regular,
    description: 'קבלת עדכון בכל פעם שמשתמש מחליף תאריך בלוח השנה',
  ),
  'events.subscribe:calendar.city_changed': PluginPermissionInfo(
    label: 'אירועי שינוי עיר',
    icon: FluentIcons.location_24_regular,
    description: 'קבלת עדכון בכל פעם שמשתמש מחליף את העיר הנבחרת בלוח השנה',
  ),
  'events.subscribe:workspace.changed': PluginPermissionInfo(
    label: 'אירועי סביבת עבודה',
    icon: FluentIcons.apps_24_regular,
    description: 'קבלת עדכון בכל פעם שמשתמש מחליף סביבת עבודה',
  ),
  'events.subscribe:plugin.permissions_changed': PluginPermissionInfo(
    label: 'אירועי שינוי הרשאות',
    icon: FluentIcons.shield_24_regular,
    description: 'קבלת עדכון בכל פעם שהרשאות התוסף משתנות',
  ),
  'events.subscribe:reader.sectionContentChanged': PluginPermissionInfo(
    label: 'אירועי שינוי תוכן בקורא',
    icon: OtzariaIcons.text_continuous_24_regular,
    description: 'קבלת עדכון כאשר נוסח של סעיף או אופן ההצגה שלו משתנים בקורא',
  ),
  'events.subscribe:reader.selection_changed': PluginPermissionInfo(
    label: 'אירועי סימון טקסט',
    icon: FluentIcons.select_all_on_24_regular,
    description: 'קבלת עדכון בכל פעם שהטקסט המסומן בקורא משתנה',
  ),
};
