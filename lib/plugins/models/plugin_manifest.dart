import 'package:otzaria/plugins/models/plugin_startup_contributions.dart';

class PluginManifest {
  /// תבנית של שם אייקון תקין: למשל `'book_24_regular'`, `'calendar_24_filled'`
  /// או שם עם תחילית ספרייה מפורשת — `'fluent:book_24_regular'`.
  static final RegExp toolTabIconNamePattern = RegExp(
    r'^(?:otzaria:|fluent:)?[a-z0-9_]+_24_(regular|filled)$',
  );

  final int schemaVersion;
  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final String homepage;
  final String entrypoint;

  /// קובץ כניסה קליל (ללא UI) לריצת רקע עם הרשאת `app.run_on_startup`.
  /// משמש את ה-host הנסתר במקום [entrypoint] המלא, כדי לא לטעון את דף
  /// הכלים השלם רק כדי לרשום תפריט הקשר / להאזין לאירועים. אם null —
  /// תוסף הרקע נופל ל-[entrypoint] הרגיל.
  final String? backgroundEntrypoint;
  final String? icon;

  /// תוסף ללא ממשק: [entrypoint] הוא קובץ JS שרץ רק במנוע הרקע, ואין לו
  /// כרטיסייה, כניסה בפאנל הכלים או הצמדה לסרגל הניווט.
  final bool headless;
  final String minAppVersion;
  final String? maxAppVersion;
  final String sdkVersion;

  /// דרגת יציבות התוסף כפי שמוצגת בחנות: `stable` / `beta` / `experimental`.
  /// שדה חובה בחנות (נגזר ל-status); כאן אופציונלי עם ברירת מחדל `stable`.
  final String stability;

  final List<String> permissions;
  final bool networkEnabled;
  final List<String> networkAllowlist;
  final String toolTabTitle;
  final int toolTabOrder;
  final bool defaultPinned;

  /// contributes.toolTab.allowMultipleInstances — מאפשר לתוסף לבקש מאוצריא מופע
  /// נוסף של עצמו בכרטיסייה חדשה (`plugin.openSelf` עם `newTab: true`).
  /// ברירת המחדל `false`: תוספים רבים מניחים מופע יחיד, ומופעים של אותו תוסף
  /// חולקים אחסון (`plugin.storage`, `localStorage`).
  final bool allowMultipleInstances;

  /// שם אייקון 24px עבור לשונית הכלים, למשל `'book_24_regular'`.
  ///
  /// נפתר ל-`IconData` קבוע באמצעות `pluginIconFromName` — קודם בספריית
  /// האייקונים של אוצריא ואז ב-FluentUI. אם השם לא נמצא באף אחת מהן, יוצג
  /// אייקון ברירת מחדל (פאזל).
  final String? toolTabIconName;
  final List<String> publishedDataTypes;

  /// מקורות מסד נתונים שהתוסף מצהיר עליהם (מהשדה contributes.databaseSources)
  final List<Map<String, dynamic>> databaseSources;

  /// contributes.autoLinkify — הפיכת כתובות `otzaria://` שנכתבו כטקסט רגיל
  /// בדף התוסף לקישורים לחיצים, כולל תוכן שנוסף אחרי הטעינה.
  final bool autoLinkify;

  /// תרומות עלייה דקלרטיביות (contributes.startup) — מופעלות ע"י Flutter
  /// בעליית התוכנה בלי מנוע JS. דורשות הרשאת `app.startup_contributions`.
  final PluginStartupContributions? startup;

  PluginManifest({
    required this.schemaVersion,
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    required this.homepage,
    required this.entrypoint,
    this.backgroundEntrypoint,
    this.icon,
    this.headless = false,
    required this.minAppVersion,
    this.maxAppVersion,
    required this.sdkVersion,
    this.stability = 'stable',
    required this.permissions,
    required this.networkEnabled,
    required this.networkAllowlist,
    required this.toolTabTitle,
    required this.toolTabOrder,
    required this.defaultPinned,
    this.toolTabIconName,
    required this.publishedDataTypes,
    this.databaseSources = const [],
    this.startup,
    this.autoLinkify = false,
    this.allowMultipleInstances = false,
  });

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    final network = json['network'] as Map<String, dynamic>? ?? {};
    final contributes = json['contributes'] as Map<String, dynamic>? ?? {};
    final toolTab = contributes['toolTab'] as Map<String, dynamic>? ?? {};
    final background = contributes['background'] as Map<String, dynamic>? ?? {};
    // סובלני לטיפוס שגוי — ה-validator מדווח עליו, הטעינה לא נופלת.
    final startupRaw = contributes['startup'];
    final startup = startupRaw is Map
        ? Map<String, dynamic>.from(startupRaw)
        : null;

    return PluginManifest(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
      description: json['description'] as String? ?? '',
      author: json['author'] as String? ?? '',
      homepage: json['homepage'] as String? ?? '',
      entrypoint: json['entrypoint'] as String,
      backgroundEntrypoint: background['entrypoint'] as String?,
      icon: json['icon'] as String?,
      headless: json['headless'] == true,
      minAppVersion: json['minAppVersion'] as String? ?? '0.0.0',
      maxAppVersion: json['maxAppVersion'] as String?,
      sdkVersion: json['sdkVersion'] as String? ?? '1.x',
      stability: json['stability'] as String? ?? 'stable',
      permissions:
          (json['permissions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      networkEnabled: network['enabled'] as bool? ?? false,
      networkAllowlist:
          (network['allowlist'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      toolTabTitle: toolTab['title'] as String? ?? json['name'] as String,
      toolTabOrder: toolTab['order'] as int? ?? 900,
      defaultPinned: toolTab['defaultPinned'] as bool? ?? true,
      allowMultipleInstances:
          toolTab['allowMultipleInstances'] as bool? ?? false,
      toolTabIconName: toolTab['iconName'] as String?,
      publishedDataTypes:
          (contributes['publishedDataTypes'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      databaseSources:
          (contributes['databaseSources'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      startup: startup == null
          ? null
          : PluginStartupContributions.fromJson(startup),
      autoLinkify: contributes['autoLinkify'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'id': id,
      'name': name,
      'version': version,
      'description': description,
      'author': author,
      'homepage': homepage,
      'entrypoint': entrypoint,
      'icon': icon,
      if (headless) 'headless': true,
      'minAppVersion': minAppVersion,
      'maxAppVersion': maxAppVersion,
      'sdkVersion': sdkVersion,
      'stability': stability,
      'permissions': permissions,
      'network': {
        'enabled': networkEnabled,
        'allowlist': networkAllowlist,
      },
      'contributes': {
        'toolTab': {
          'title': toolTabTitle,
          'order': toolTabOrder,
          'defaultPinned': defaultPinned,
          if (allowMultipleInstances) 'allowMultipleInstances': true,
          if (toolTabIconName != null) 'iconName': toolTabIconName,
        },
        'publishedDataTypes': publishedDataTypes,
        'databaseSources': databaseSources,
        if (backgroundEntrypoint != null)
          'background': {'entrypoint': backgroundEntrypoint},
        if (startup != null) 'startup': startup!.toJson(),
        if (autoLinkify) 'autoLinkify': true,
      },
    };
  }
}
