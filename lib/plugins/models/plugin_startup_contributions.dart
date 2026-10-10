import 'package:otzaria/plugins/models/plugin_when_condition.dart';

/// תרומות עלייה דקלרטיביות של תוסף (`contributes.startup` במניפסט).
///
/// נקראות ומופעלות ע"י Flutter בלי להרים מנוע JS. דורשות את ההרשאה
/// `app.startup_contributions`, וכל קטגוריה כפופה גם להרשאת התחום שלה
/// (`reader.toolbar` / `reader.context_menu` / `search.dialog` /
/// `search.field_actions` / `published_data.write` / `library.books.provide`).
class PluginStartupContributions {
  /// נושא הפעלה מדומה ב-[activationEvents]: מרים את מופע הרקע של התוסף
  /// זמן קצר אחרי שעליית התוכנה הסתיימה (ולא כחלק ממנה).
  static const String startupActivationTopic = 'app.startup';

  /// פריטי שורת פקדים — באותה סכימה של `reader.addToolbarItem`.
  final List<Map<String, dynamic>> toolbarItems;

  /// פריטי תפריט הקשר — באותה סכימה של `reader.addContextMenuItem`.
  final List<Map<String, dynamic>> contextMenuItems;

  /// קיצורי מקלדת שהתוסף מצהיר עליהם — באותה סכימה של `app.registerShortcut`.
  /// קיצור יכול להפעיל פקודה חופשית (`command`) או פעולת תפריט הקשר
  /// (`contextMenuItemId`). דורשים את הרשאת `app.shortcuts`.
  final List<Map<String, dynamic>> shortcuts;

  /// רשומות `publishedData` לזריעה: `{type, key, payload, scope?}`.
  /// המפתח נשמר עם קידומת `manifest:` — רשומות אלו בבעלות המניפסט.
  final List<Map<String, dynamic>> publishedData;

  /// תכניות חישוב שה-Host מריץ ללא מנוע JavaScript.
  final List<Map<String, dynamic>> programs;

  /// שורות סטטיות שמוצגות בתחתית דיאלוג החיפוש.
  final List<Map<String, dynamic>> searchDialogItems;

  /// כפתורי פעולה בתוך שדות חיפוש (ראו PluginSearchFieldAction).
  final List<Map<String, dynamic>> searchFieldActions;

  /// קונפיגורציות מהדורות מקבילות חיצוניות — טבלת מיפוי של מקור נתונים
  /// מוכרז שמקשרת מזהי ספק חיצוני לספרי אוצריא (ראו
  /// PluginExternalEditionsRegistry).
  final List<Map<String, dynamic>> externalEditions;

  /// ספקי ספרים שמתווספים לאיתור הספרים במסך הספרייה (ראו
  /// PluginLibraryBooksRegistry).
  final List<Map<String, dynamic>> libraryBooks;

  /// נושאי אירועים שמעירים את מופע הרקע של התוסף בעצלנות (בלי מנוע חי
  /// עד שאירוע כזה קורה בפועל), או [startupActivationTopic].
  final List<String> activationEvents;

  /// תנאי `when` פר-נושא הפעלה — נושא בלי רשומה כאן מעיר תמיד.
  final Map<String, PluginWhenCondition> activationConditions;

  /// האם התוסף מבקש להשאיר מופע רקע עצל פעיל ללא כיבוי אוטומטי.
  /// הבקשה חלה רק אם המשתמש אישר את ההרשאה המתאימה.
  final bool keepAlive;

  const PluginStartupContributions({
    this.toolbarItems = const [],
    this.contextMenuItems = const [],
    this.shortcuts = const [],
    this.publishedData = const [],
    this.programs = const [],
    this.searchDialogItems = const [],
    this.searchFieldActions = const [],
    this.externalEditions = const [],
    this.libraryBooks = const [],
    this.activationEvents = const [],
    this.activationConditions = const {},
    this.keepAlive = false,
  });

  bool get isEmpty =>
      toolbarItems.isEmpty &&
      contextMenuItems.isEmpty &&
      shortcuts.isEmpty &&
      publishedData.isEmpty &&
      programs.isEmpty &&
      searchDialogItems.isEmpty &&
      searchFieldActions.isEmpty &&
      externalEditions.isEmpty &&
      libraryBooks.isEmpty &&
      activationEvents.isEmpty;

  /// האם קיימת פעולה שבאמת עשויה להרים את מנוע הרקע. לחיצה על ספר של ספק
  /// נמסרת לתוסף, ולכן גם היא כזו.
  bool get hasBackgroundActivationTrigger =>
      hasInitialActivationTrigger || libraryBooks.isNotEmpty;

  /// כמו [hasBackgroundActivationTrigger], בלי ספרי ספק: הם מופיעים רק
  /// אחרי שהתוסף כבר רץ ושלח אותם, ולכן אינם יכולים להפעיל אותו לראשונה.
  bool get hasInitialActivationTrigger =>
      activationEvents.isNotEmpty ||
      searchFieldActions.isNotEmpty ||
      toolbarItems.any(_toolbarItemActivatesBackground) ||
      contextMenuItems.any(_contextMenuItemActivatesBackground);

  static bool _toolbarItemActivatesBackground(Map<String, dynamic> item) {
    if (item.containsKey('binding') ||
        item.containsKey('action') ||
        item.containsKey('childrenBinding')) {
      return false;
    }
    final type = item['type'];
    if (type == 'menu' || type == 'split') {
      final children = item['children'];
      final childActivates =
          children is List &&
          children.whereType<Map>().any(
            (child) => _toolbarItemActivatesBackground(
              Map<String, dynamic>.from(child),
            ),
          );
      // בלחצן מפוצל גם הפעולה הראשית עצמה מגיעה למנוע התוסף.
      return childActivates || (type == 'split' && item['openPlugin'] != true);
    }
    return item['openPlugin'] != true;
  }

  static bool _contextMenuItemActivatesBackground(Map<String, dynamic> item) {
    switch (item['type']) {
      case 'separator':
        return false;
      case 'submenu':
        final children = item['children'];
        return children is List &&
            children.whereType<Map>().any(
              (child) => _contextMenuItemActivatesBackground(
                Map<String, dynamic>.from(child),
              ),
            );
      case 'color-row':
        return true;
      default:
        if (item.containsKey('action')) return false;
        return item['openPlugin'] != true;
    }
  }

  /// פרסינג סובלני: ערכים בטיפוס שגוי מדולגים ולא מפילים את טעינת המניפסט.
  /// הדיווח למפתח על טיפוס שגוי הוא באחריות ה-validator (אריזה/התקנה).
  factory PluginStartupContributions.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> mapList(String field) {
      final value = json[field];
      if (value is! List) return const [];
      return [
        for (final entry in value)
          if (entry is Map) Map<String, dynamic>.from(entry),
      ];
    }

    final events = json['activationEvents'];
    final topics = <String>[];
    final conditions = <String, PluginWhenCondition>{};
    if (events is List) {
      for (final entry in events) {
        if (entry is String) {
          topics.add(entry);
          continue;
        }
        if (entry is! Map) continue;
        // מפתח לא מוכר (למשל "wen") נדחה — אחרת התנאי היה נעלם בשקט.
        if (entry.keys.any((key) => key != 'topic' && key != 'when')) continue;
        final topic = entry['topic'];
        if (topic is! String || topic.isEmpty) continue;
        final rawWhen = entry['when'];
        if (rawWhen != null) {
          try {
            conditions[topic] = PluginWhenCondition.fromJson(rawWhen);
          } on PluginWhenConditionException {
            continue;
          }
        }
        topics.add(topic);
      }
    }
    return PluginStartupContributions(
      toolbarItems: mapList('toolbarItems'),
      contextMenuItems: mapList('contextMenuItems'),
      shortcuts: mapList('shortcuts'),
      publishedData: mapList('publishedData'),
      programs: mapList('programs'),
      searchDialogItems: mapList('searchDialogItems'),
      searchFieldActions: mapList('searchFieldActions'),
      externalEditions: mapList('externalEditions'),
      libraryBooks: mapList('libraryBooks'),
      activationEvents: topics,
      activationConditions: Map.unmodifiable(conditions),
      keepAlive: json['keepAlive'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    if (toolbarItems.isNotEmpty) 'toolbarItems': toolbarItems,
    if (contextMenuItems.isNotEmpty) 'contextMenuItems': contextMenuItems,
    if (shortcuts.isNotEmpty) 'shortcuts': shortcuts,
    if (publishedData.isNotEmpty) 'publishedData': publishedData,
    if (programs.isNotEmpty) 'programs': programs,
    if (searchDialogItems.isNotEmpty) 'searchDialogItems': searchDialogItems,
    if (searchFieldActions.isNotEmpty) 'searchFieldActions': searchFieldActions,
    if (externalEditions.isNotEmpty) 'externalEditions': externalEditions,
    if (libraryBooks.isNotEmpty) 'libraryBooks': libraryBooks,
    if (activationEvents.isNotEmpty)
      'activationEvents': [
        for (final topic in activationEvents)
          if (activationConditions[topic] case final condition?)
            {'topic': topic, 'when': condition.toJson()}
          else
            topic,
      ],
    if (keepAlive) 'keepAlive': true,
  };
}
