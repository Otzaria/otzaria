import 'package:flutter/widgets.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_network_allowlist.dart';
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
              'לא הוגדר אירוע שמפעיל את התוסף ברקע, ולכן ההרשאה הזאת אינה '
              'בשימוש בגרסה הנוכחית של התוסף.',
        );
      }
      final reasons = pluginBackgroundActivationReasons(manifest).join(', ');
      return PluginPermissionInfo(
        label: 'הפעלה ברקע לפי אירוע',
        icon: FluentIcons.power_24_regular,
        description:
            'התוסף יפעל ברקע, בלי שתראה אותו, כאשר: $reasons. הוא ייכבה אחרי '
            '3 דקות ללא פעילות, אלא אם תאשר גם את מניעת הכיבוי.',
      );
    }
  }
  if (permissionKey == pluginGeolocationPermission && manifest != null) {
    final base = _permissionLabels[permissionKey]!;
    if (manifest.networkEnabled) {
      final servers = _networkServersSentence(manifest);
      return PluginPermissionInfo(
        label: base.label,
        icon: base.icon,
        description:
            '${base.description}. התוסף מצהיר על גישה לאינטרנט, ולכן אם תאשר '
            'גם אותה הוא יוכל לשלוח את המיקום $servers',
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

/// כמה שרתים מוצגים באזהרת המיקום לפני „ועוד N”.
const int _maxListedServers = 4;

/// ההמשך של משפט האזהרה: לאילו שרתים התוסף יכול לשלוח, לפי
/// `network.allowlist`. כתובות מקומיות אינן נחשבות — הן לא יוצאות מהמחשב.
/// כשאין שם שרת בר-הצגה (כתובת ללא סכימה, למשל) המשפט נשאר כללי, כדי
/// שהאזהרה לא תיעלם בגלל פורמט.
String _networkServersSentence(PluginManifest manifest) {
  final hosts = <String>{};
  for (final entry in manifest.networkAllowlist) {
    final host = Uri.tryParse(entry.trim())?.host ?? '';
    if (host.isNotEmpty && !isLoopbackHost(host)) hosts.add(host);
  }
  if (hosts.isEmpty) return 'לשרתים באינטרנט';
  final shown = hosts.take(_maxListedServers).join(', ');
  final more = hosts.length - _maxListedServers;
  return more > 0 ? 'לשרתים: $shown ועוד $more' : 'לשרתים: $shown';
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
  if (startup.libraryBooks.isNotEmpty) {
    reasons.add('בחירת ספר של התוסף במסך הספרייה');
  }
  if (startup.searchFieldActions.isNotEmpty) {
    reasons.add('לחיצה על כפתור התוסף בשדה חיפוש');
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
      toolbarItems: [item],
    ).hasBackgroundActivationTrigger;

bool _contextMenuItemActivatesBackground(Map<String, dynamic> item) =>
    PluginStartupContributions(
      contextMenuItems: [item],
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
      permission == pluginBackgroundKeepAlivePermission ||
      permission == pluginClipboardReadPermission ||
      permission == pluginGeolocationPermission) {
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
    pluginClipboardReadPermission => 4,
    pluginGeolocationPermission => 5,
    _ => 6,
  };
  final indexed = permissions.indexed.toList();
  indexed.sort((a, b) {
    final rankComparison = rank(a.$2).compareTo(rank(b.$2));
    return rankComparison != 0 ? rankComparison : a.$1.compareTo(b.$1);
  });
  return indexed.map((entry) => entry.$2).toList(growable: false);
}

/// מיפוי מלא של כל ההרשאות התקפות לשם ותיאור בעברית. התיאורים כתובים למשתמש
/// רגיל: מה התוסף יכול לעשות, בלי מונחים טכניים.
const Map<String, PluginPermissionInfo> _permissionLabels = {
  // ===== מידע על האפליקציה =====
  'app.info.read': PluginPermissionInfo(
    label: 'מידע אפליקציה',
    icon: FluentIcons.info_24_regular,
    description:
        'התוסף יכול לראות איזו גרסה של אוצריא מותקנת אצלך, באיזו מערכת '
        'הפעלה היא רצה ואיזו ערכת נושא (צבעים) בחרת',
  ),
  'app.user_email.read': PluginPermissionInfo(
    label: 'כתובת מייל',
    icon: FluentIcons.mail_24_regular,
    description:
        'התוסף יכול לראות את כתובת המייל שהזנת באוצריא. היא מיועדת למילוי '
        'אוטומטי בדיווח על תקלה',
  ),
  'app.open_url': PluginPermissionInfo(
    label: 'פתיחת קישורים בדפדפן',
    icon: FluentIcons.open_24_regular,
    description: 'התוסף יכול לפתוח כתובת של אתר באינטרנט בדפדפן שלך',
  ),
  'app.run_on_startup': PluginPermissionInfo(
    label: 'טעינה אוטומטית ברקע',
    icon: FluentIcons.power_24_regular,
    description:
        'תוסף מדור קודם: ייטען מיד כשאוצריא נפתחת וימשיך לפעול ברקע כל עוד '
        'היא פתוחה, גם כשלא פתחת אותו',
  ),
  'app.background_keep_alive': PluginPermissionInfo(
    label: 'מניעת כיבוי התוסף ברקע',
    icon: FluentIcons.hourglass_24_regular,
    description:
        'התוסף יישאר פעיל ברקע בלי הגבלת זמן, גם כשאינך משתמש בו. זה מגדיל '
        'את השימוש בזיכרון ובמעבד של המחשב ועלול להאט אותו. אשר רק לתוסף '
        'שאתה סומך עליו ושחייב להאזין כל הזמן',
  ),
  'app.startup_contributions': PluginPermissionInfo(
    label: 'הוספת רכיבים לתוכנה',
    icon: FluentIcons.puzzle_piece_24_regular,
    description:
        'התוסף יכול להוסיף לאוצריא כפתורים, פריטי תפריט ומידע, שמוצגים כבר '
        'כשהתוכנה נפתחת. אוצריא היא שמפעילה אותם, ולכן חלק מהפעולות יתבצעו '
        'בלי לפתוח את דף התוסף',
  ),
  'app.shortcuts': PluginPermissionInfo(
    label: 'קיצורי מקלדת',
    icon: FluentIcons.keyboard_24_regular,
    description:
        'התוסף יכול להציע קיצורי מקלדת שמפעילים פקודות שלו. אפשר לראות ולשנות '
        'אותם במסך הגדרות קיצורי המקשים',
  ),

  // ===== ספרייה =====
  'library.books.read': PluginPermissionInfo(
    label: 'רשימת ספרים',
    icon: FluentIcons.library_24_regular,
    description:
        'התוסף יכול לחפש בספרייה ולראות את רשימת הספרים: שמות, מחברים '
        'וקטגוריות. הוא אינו קורא את הטקסט של הספרים',
  ),
  'library.content.read': PluginPermissionInfo(
    label: 'תוכן ספרים',
    icon: OtzariaIcons.book_24_regular,
    description: 'התוסף יכול לקרוא את הטקסט של הספרים בספרייה',
  ),
  'library.links.read': PluginPermissionInfo(
    label: 'מפרשים וקישורים',
    icon: OtzariaIcons.link_24_regular,
    description:
        'התוסף יכול לראות אילו מפרשים יש לכל ספר ואילו ספרים מקושרים זה לזה. '
        'הוא אינו רואה את הטקסט של הספרים עצמם',
  ),
  'library.books.provide': PluginPermissionInfo(
    label: 'ספרים בחיפוש הספרייה',
    icon: OtzariaIcons.library_add_24_regular,
    description:
        'התוסף יכול להוסיף ספרים משלו לרשימה שמופיעה כשמחפשים ספר במסך '
        'הספרייה. כשתלחץ על ספר כזה, התוסף הוא שיפתח אותו ולא אוצריא',
  ),
  'library.refresh': PluginPermissionInfo(
    label: 'רענון הספרים האישיים',
    icon: OtzariaIcons.library_refresh_24_regular,
    description:
        'התוסף יכול לבקש מאוצריא לסרוק שוב את התיקיות של הספרים האישיים שלך '
        'ולרענן את הספרייה, כדי שספרים שהוא הוסיף יופיעו. הוא אינו בוחר '
        'אילו תיקיות ייסרקו',
  ),

  // ===== חיפוש =====
  'search.fulltext.read': PluginPermissionInfo(
    label: 'חיפוש טקסט מלא',
    icon: OtzariaIcons.search_in_library_24_regular,
    description:
        'התוסף יכול להריץ חיפוש בתוך הטקסט של כל הספרים ולקבל את התוצאות',
  ),
  'search.dialog': PluginPermissionInfo(
    label: 'רכיבים בחלון החיפוש',
    icon: FluentIcons.checkbox_checked_24_regular,
    description:
        'התוסף יכול להוסיף לחלון החיפוש אפשרויות לסימון, כמו "חפש גם באתר '
        'חיצוני". אם סימנת אפשרות כזאת והפעלת חיפוש, התוסף יקבל את מילות '
        'החיפוש וההגדרות שלו, ויוכל להציג תוצאות משלו או להיפתח כדי לחפש. '
        'הסימון נשמר לחיפוש הבא רק אם התוסף ביקש זאת',
  ),
  pluginSearchFieldActionsPermission: PluginPermissionInfo(
    label: 'כפתורים בשדות החיפוש',
    icon: FluentIcons.text_field_24_regular,
    description:
        'התוסף יכול להוסיף כפתור בתוך שדות חיפוש, למשל להקלדה בדיבור. '
        'הכפתור יכול להיראות רק כשיש טקסט בשדה. כשתלחץ עליו התוסף יקבל את '
        'הטקסט שבשדה ואת מצב החיפוש שלך (בחיפוש טקסט מלא: ההגדרות שבחרת; '
        'באיתור ספרים: הקטגוריה הפתוחה), ויוכל לכתוב לשדה עד שתקליד בו '
        'בעצמך. באיתור ספרים כפתור כזה יכול גם לסנן את הרשימה: ספרי התוסף '
        'בלבד, ספרי הספרייה בלבד או הכול',
  ),

  // ===== קורא =====
  'reader.open': PluginPermissionInfo(
    label: 'פתיחת ספרים וניהול כרטיסיות',
    icon: OtzariaIcons.otzaria_icon_2_page_24_regular,
    description:
        'התוסף יכול לפתוח ספרים בקורא, לעבור בין הכרטיסיות הפתוחות ולסגור '
        'אותן, כולל כרטיסיות של כלים ושל תוספים אחרים. הוא אינו משנה את '
        'הטקסט של הספרים',
  ),
  'reader.context_menu': PluginPermissionInfo(
    label: 'פריטים בתפריט הטקסט',
    icon: FluentIcons.text_bullet_list_square_24_regular,
    description:
        'התוסף יכול להוסיף פריטים לתפריט שנפתח בלחיצה ימנית על טקסט. כשתלחץ '
        'על פריט כזה התוסף יקבל את הטקסט שסימנת',
  ),
  'reader.toolbar': PluginPermissionInfo(
    label: 'פקדים בשורת העיון',
    icon: FluentIcons.app_title_24_regular,
    description:
        'התוסף יכול להוסיף כפתורים ותפריטים לשורת הכלים שבמסך העיון בספר',
  ),
  'reader.local_edit': PluginPermissionInfo(
    label: 'תיקונים מקומיים בטקסט',
    icon: OtzariaIcons.book_edit_24_regular,
    description:
        'התוסף יכול לתקן טקסט בספר שפתוח אצלך, ורק אצלך במחשב. התיקונים '
        'נשמרים בנפרד, והספר עצמו ומאגר הספרייה אינם משתנים',
  ),
  'reader.highlight': PluginPermissionInfo(
    label: 'הדגשות בטקסט',
    icon: FluentIcons.highlight_24_regular,
    description:
        'התוסף יכול להוסיף, לשנות ולמחוק הדגשות צבעוניות בטקסט של הספר. '
        'הטקסט עצמו אינו משתנה',
  ),

  // ===== ניווט =====
  pluginNewTabPagePermission: PluginPermissionInfo(
    label: "כפתור לשונית חדשה (+)",
    icon: FluentIcons.add_24_regular,
    description:
        'דף התוסף ייפתח כשתלחץ על כפתור ה-"+" לפתיחת כרטיסייה חדשה. רק תוסף '
        'אחד יכול לקבל הרשאה זו',
  ),
  'navigation.write': PluginPermissionInfo(
    label: 'ניווט במסכים',
    icon: FluentIcons.navigation_24_regular,
    description:
        'התוסף יכול להעביר אותך בין המסכים של אוצריא, כמו הספרייה, העיון '
        'וההגדרות',
  ),
  'plugin.open_other': PluginPermissionInfo(
    label: 'פתיחת תוסף אחר',
    icon: FluentIcons.apps_list_24_regular,
    description:
        'התוסף יכול לפתוח דף של תוסף אחר שמותקן אצלך, והתוסף שנפתח יתחיל '
        'לפעול. הוא פועל רק לפי ההרשאות שלו עצמו',
  ),

  // ===== שולחנות עבודה =====
  'workspace.read': PluginPermissionInfo(
    label: 'שולחנות עבודה — צפייה',
    icon: FluentIcons.tab_desktop_multiple_24_regular,
    description:
        'התוסף יכול לראות את רשימת שולחנות העבודה שלך: השמות שנתת להם וכמה '
        'כרטיסיות פתוחות בכל אחד. שם של שולחן עבודה עשוי לרמז על מה שאתה '
        'לומד',
  ),
  'workspace.manage': PluginPermissionInfo(
    label: 'שולחנות עבודה — יצירה ומעבר',
    icon: FluentIcons.window_new_24_regular,
    description:
        'התוסף יכול ליצור שולחן עבודה חדש ולעבור בין שולחנות. במעבר, כל '
        'הכרטיסיות הפתוחות מוחלפות (הן נשמרות בשולחן שיצאת ממנו). התוסף '
        'אינו יכול למחוק שולחן או לשנות את שמו',
  ),

  // ===== הערות אישיות =====
  'notes.read': PluginPermissionInfo(
    label: 'צפייה בהערות',
    icon: FluentIcons.note_24_regular,
    description: 'התוסף יכול לקרוא את ההערות האישיות שכתבת',
  ),
  'notes.write': PluginPermissionInfo(
    label: 'עריכת הערות',
    icon: FluentIcons.note_edit_24_regular,
    description:
        'התוסף יכול ליצור הערות אישיות חדשות, לערוך הערות קיימות ולמחוק אותן',
  ),

  // ===== לוח שנה =====
  'calendar.read': PluginPermissionInfo(
    label: 'לוח שנה עברי',
    icon: OtzariaIcons.calendar_24_regular,
    description:
        'התוסף יכול להשתמש בלוח השנה העברי: תאריכים, זמני היום (זמנים '
        'הלכתיים) ואירועים',
  ),

  // ===== הגדרות =====
  'settings.read': PluginPermissionInfo(
    label: 'הגדרות האפליקציה',
    icon: FluentIcons.settings_24_regular,
    description:
        'התוסף יכול לראות חלק מההגדרות של אוצריא, רק את אלה שאוצריא מתירה '
        'לתוספים לראות',
  ),

  // ===== ממשק משתמש =====
  'ui.feedback': PluginPermissionInfo(
    label: 'הודעות ודיאלוגים',
    icon: FluentIcons.chat_24_regular,
    description: 'התוסף יכול להציג לך הודעות וחלונות קטנים בתוך אוצריא',
  ),
  'ui.create_shortcut': PluginPermissionInfo(
    label: 'יצירת קיצור דרך',
    icon: FluentIcons.desktop_24_regular,
    description:
        'התוסף יכול ליצור קיצור דרך אליו בשולחן העבודה או בתפריט התחל, '
        'אחרי שתאשר',
  ),

  // ===== גופנים =====
  'fonts.local.read': PluginPermissionInfo(
    label: 'רשימת הגופנים המותקנים',
    icon: FluentIcons.text_font_24_regular,
    description:
        'התוסף יכול לראות את רשימת הגופנים (סוגי האותיות) שמותקנים במחשב '
        'שלך, ולהציג כל גופן בצורתו האמיתית, למשל בבורר גופנים. הוא אינו '
        'רואה קבצים אחרים ואינו יכול לכתוב למחשב',
  ),

  // ===== מיקום =====
  'device.geolocation': PluginPermissionInfo(
    label: 'מיקום המכשיר',
    icon: FluentIcons.my_location_24_regular,
    description:
        'התוסף יכול לבקש את מיקומך המשוער, למשל כדי לחשב כיוון או זמנים '
        'לפי המקום שבו אתה נמצא. המערכת עשויה לבקש אישור נוסף לכך. בלי '
        'ההרשאה אפשר להמשיך לבחור מקום ידנית',
  ),

  // ===== לוח העתקה =====
  'clipboard.read': PluginPermissionInfo(
    label: 'קריאת לוח ההעתקה',
    icon: FluentIcons.clipboard_paste_24_regular,
    description:
        'התוסף יכול לקרוא את מה שהעתקת במחשב, גם אם העתקת מתוכנה אחרת, '
        'למשל סיסמה. נדרש לכפתור "הדבק" שבתוסף. הדבקה במקשים Ctrl+V עובדת '
        'גם בלי ההרשאה',
  ),

  // ===== קבצים אישיים =====
  'fs.user_files.read': PluginPermissionInfo(
    label: 'קבצים אישיים',
    icon: FluentIcons.document_24_regular,
    description:
        'התוסף יכול לפתוח ולקרוא קבצים שתבחר בחלון בחירת קובץ. הוא אינו '
        'יכול לגשת לקבצים אחרים במחשב',
  ),
  'fs.user_files.write': PluginPermissionInfo(
    label: 'שמירה לקבצים אישיים',
    icon: FluentIcons.document_save_24_regular,
    description:
        'התוסף יכול לשמור לקובץ שתבחר, או ליצור קובץ חדש דרך "שמירה בשם". '
        'הוא אינו יכול לכתוב לשום מקום אחר במחשב',
  ),
  'fs.folder_access': PluginPermissionInfo(
    label: 'גישה לתיקייה שתבחר',
    icon: FluentIcons.folder_24_regular,
    description:
        'התוסף יכול לעבוד עם קבצים בתוך תיקייה שתבחר: לחלץ אליה קבצים '
        'ולמחוק מתוכה. הוא אינו יכול לגשת לתיקיות אחרות',
  ),

  // ===== אחסון תוסף =====
  'plugin.storage.read': PluginPermissionInfo(
    label: 'אחסון מקומי — קריאה',
    icon: FluentIcons.storage_24_regular,
    description:
        'התוסף יכול לקרוא נתונים שהוא שמר בעבר במחשב שלך, כמו הגדרות שלו',
  ),
  'plugin.storage.write': PluginPermissionInfo(
    label: 'אחסון מקומי — כתיבה',
    icon: FluentIcons.save_24_regular,
    description:
        'התוסף יכול לשמור נתונים משלו במחשב שלך, כדי לזכור אותם בפעם הבאה',
  ),

  // ===== פרסום נתונים =====
  'published_data.write': PluginPermissionInfo(
    label: 'שיתוף נתונים עם האפליקציה',
    icon: FluentIcons.share_24_regular,
    description:
        'התוסף יכול להעביר מידע לחלקים אחרים של אוצריא, למשל אירועים '
        'שיוצגו בלוח השנה',
  ),

  // ===== רשת =====
  'network.access': PluginPermissionInfo(
    label: 'גישה לאינטרנט',
    icon: FluentIcons.globe_24_regular,
    description:
        'התוסף יכול להתחבר לאתרים ולשרתים באינטרנט, לשלוח אליהם מידע '
        'ולקבל מהם מידע',
  ),
  'network.localhost': PluginPermissionInfo(
    label: 'גישה לשירותים מקומיים',
    icon: FluentIcons.plug_connected_24_regular,
    description:
        'התוסף יכול לדבר עם תוכנות שרצות במחשב שלך עצמו, למשל מודל בינה '
        'מלאכותית שהתקנת. ההרשאה הזאת אינה מאפשרת גישה לאינטרנט',
  ),

  // ===== משוב ומיילים =====
  'feedback.send_email': PluginPermissionInfo(
    label: 'שליחת מייל',
    icon: FluentIcons.send_24_regular,
    description: 'התוסף יכול לשלוח משוב ודיווחים בדוא"ל לכתובת שהתוסף קבע',
  ),

  // ===== היסטוריית קריאה =====
  'history.read': PluginPermissionInfo(
    label: 'היסטוריית קריאה — צפייה',
    icon: FluentIcons.history_24_regular,
    description: 'התוסף יכול לראות את היסטוריית הקריאה והחיפושים שלך',
  ),
  'history.write': PluginPermissionInfo(
    label: 'היסטוריית קריאה — עריכה',
    icon: FluentIcons.history_dismiss_24_regular,
    description: 'התוסף יכול למחוק ולשנות את היסטוריית הקריאה שלך',
  ),

  // ===== סימניות =====
  'bookmarks.read': PluginPermissionInfo(
    label: 'סימניות — צפייה',
    icon: OtzariaIcons.book_star_24_regular,
    description:
        'התוסף יכול לראות את רשימת הסימניות שלך, כולל שמות הספרים והמקומות '
        'שסימנת בהם',
  ),
  'bookmarks.write': PluginPermissionInfo(
    label: 'סימניות — הוספה ומחיקה',
    icon: FluentIcons.bookmark_add_24_regular,
    description:
        'התוסף יכול להוסיף סימניות חדשות וגם למחוק סימניות קיימות שיצרת. '
        'מחיקה היא סופית ואין דרך לשחזר',
  ),

  // ===== כלי עזר =====
  'tools.read': PluginPermissionInfo(
    label: 'כלי עזר מובנים',
    icon: FluentIcons.toolbox_24_regular,
    description:
        'התוסף יכול להשתמש בכלי העזר של אוצריא, כמו גימטריה ומילונים. '
        'הכלים האלה אינם נותנים גישה לנתונים האישיים שלך',
  ),

  // ===== מסד נתונים =====
  'database.read': PluginPermissionInfo(
    label: 'קריאת מאגרי מידע',
    icon: FluentIcons.database_search_24_regular,
    description:
        'התוסף יכול לקרוא מידע ממאגרי מידע שאוצריא מתירה לו, כמו מאגר שהוא '
        'עצמו הביא. הוא אינו יכול לשנות אותם ואינו רואה מאגרים אחרים',
  ),

  // ===== התראות =====
  'notifications.send': PluginPermissionInfo(
    label: 'הודעות מובנות',
    icon: FluentIcons.alert_24_regular,
    description: 'התוסף יכול להציג הודעות קטנות בתוך אוצריא',
  ),
  'notifications.system': PluginPermissionInfo(
    label: 'התראות מערכת',
    icon: FluentIcons.alert_urgent_24_regular,
    description:
        'התוסף יכול לשלוח התראות של מערכת ההפעלה, שמופיעות גם כשחלון אוצריא '
        'ממוזער',
  ),

  // ===== אירועים =====
  'events.subscribe:navigation.changed': PluginPermissionInfo(
    label: 'אירועי ניווט',
    icon: FluentIcons.navigation_24_regular,
    description: 'התוסף יקבל עדכון בכל פעם שאתה עובר בין מסכים',
  ),
  'events.subscribe:reader.current_book_changed': PluginPermissionInfo(
    label: 'אירועי פתיחת ספר',
    icon: OtzariaIcons.otzaria_icon_2_page_24_regular,
    description: 'התוסף יקבל עדכון בכל פעם שנפתח ספר חדש בקורא',
  ),
  'events.subscribe:reader.current_ref_changed': PluginPermissionInfo(
    label: 'אירועי שינוי מיקום',
    icon: FluentIcons.location_24_regular,
    description: 'התוסף יקבל עדכון בכל פעם שמקום הקריאה משתנה (דף, פרק, סעיף)',
  ),
  'events.subscribe:theme.changed': PluginPermissionInfo(
    label: 'אירועי ערכת נושא',
    icon: FluentIcons.color_24_regular,
    description: 'התוסף יקבל עדכון בכל פעם שאתה מחליף ערכת נושא',
  ),
  'events.subscribe:settings.changed': PluginPermissionInfo(
    label: 'אירועי הגדרות',
    icon: FluentIcons.settings_24_regular,
    description: 'התוסף יקבל עדכון בכל פעם שאתה משנה הגדרה',
  ),
  'events.subscribe:calendar.date_changed': PluginPermissionInfo(
    label: 'אירועי שינוי תאריך',
    icon: OtzariaIcons.calendar_24_regular,
    description: 'התוסף יקבל עדכון בכל פעם שאתה מחליף תאריך בלוח השנה',
  ),
  'events.subscribe:calendar.city_changed': PluginPermissionInfo(
    label: 'אירועי שינוי עיר',
    icon: FluentIcons.location_24_regular,
    description: 'התוסף יקבל עדכון בכל פעם שאתה מחליף את העיר שנבחרה בלוח השנה',
  ),
  'events.subscribe:workspace.changed': PluginPermissionInfo(
    label: 'אירועי סביבת עבודה',
    icon: FluentIcons.apps_24_regular,
    description: 'התוסף יקבל עדכון בכל פעם שאתה מחליף שולחן עבודה',
  ),
  'events.subscribe:plugin.permissions_changed': PluginPermissionInfo(
    label: 'אירועי שינוי הרשאות',
    icon: FluentIcons.shield_24_regular,
    description: 'התוסף יקבל עדכון בכל פעם שההרשאות שלו משתנות',
  ),
  'events.subscribe:reader.sectionContentChanged': PluginPermissionInfo(
    label: 'אירועי שינוי תוכן בקורא',
    icon: OtzariaIcons.text_continuous_rtl_24_regular,
    description:
        'התוסף יקבל עדכון כשהנוסח של סעיף או צורת ההצגה שלו משתנים בקורא',
  ),
  'events.subscribe:reader.selection_changed': PluginPermissionInfo(
    label: 'אירועי סימון טקסט',
    icon: FluentIcons.select_all_on_24_regular,
    description: 'התוסף יקבל עדכון בכל פעם שהטקסט המסומן בקורא משתנה',
  ),
};
