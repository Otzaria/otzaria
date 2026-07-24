import 'dart:convert';
import 'package:otzaria/plugins/models/plugin_manifest.dart';

class InstalledPlugin {
  final String pluginId;
  final String name;
  final String version;
  final String installPath;
  final String entrypointPath;
  final String? iconPath;
  final bool enabled;
  final bool pinned;
  final bool pinnedToNavRail;

  /// האם התוסף מוצג במסך הכלים. ברירת מחדל: true.
  /// בניגוד ל-[enabled] שמשבית את הריצה, שדה זה רק שולט בהצגה בלשונית כלים —
  /// הסרגל וה-side panel אינם מושפעים.
  final bool showInTools;

  /// האם המשתמש אישר בפועל לתוסף להופיע לפני כלים מובנים במסך "כלים".
  ///
  /// זהו מתג התקנה/עדכון שנשמר על ההתקנה עצמה. גם אם התוסף מבקש את היכולת
  /// במניפסט, המשתמש יכול לכבות אותה. אם המניפסט לא ביקש את היכולת, הערך
  /// הזה לבדו לא מספיק כדי להפעיל אותה.
  final bool allowOrderBeforeBuiltInsGranted;

  /// האם הרשאת גישה לרשת (`network.access`) הוענקה בפועל על-ידי המשתמש.
  /// שונה מ-[requiresNetwork] שמשקף את ההצהרה במניפסט בלבד.
  final bool networkAccessGranted;

  /// האם הרשאת טעינה בעלייה (`app.run_on_startup`) הוענקה בפועל.
  final bool runOnStartupGranted;
  final PluginManifest manifest;
  final DateTime installedAt;
  final DateTime updatedAt;
  final String sourceType;
  final String? devRootPath;

  /// סדר מותאם אישית שנקבע ע"י המשתמש (גרירה ושחרור). `null` = להשתמש
  /// בסדר ברירת המחדל מתוך המניפסט ([PluginManifest.toolTabOrder]).
  ///
  /// הערכים נשמרים כאינדקסים פשוטים (0,1,2...) ומומרים בתצוגה לטווח
  /// גבוה שמונע התנגשות מספרית עם סדרי הכלים המובנים — ראו
  /// [effectiveToolTabOrder] ו-[userOrderToolTabOffset].
  final int? userOrder;

  /// בסיס הסדר עבור תוספים בעלי [userOrder]. ערך גבוה מספיק כדי שכל הכלים
  /// המובנים (`builtin.*`, סדרים 10-100) יישארו בטווח מספרי נפרד.
  static const int userOrderToolTabOffset = 1000;

  /// הסדר האפקטיבי שבו יוצג התוסף ברשימת הכלים. אם המשתמש קבע סדר ידני
  /// משתמשים בו (עם [userOrderToolTabOffset] כדי לשמור על טווח נפרד מהכלים
  /// המובנים); אחרת משתמשים בערך מהמניפסט.
  ///
  /// ההחלטה האם תוסף רשאי בכלל להופיע לפני כלים מובנים נקבעת בנפרד ע"י
  /// [PluginManifest.allowOrderBeforeBuiltIns] במסך "כלים".
  int get effectiveToolTabOrder => userOrder != null
      ? userOrderToolTabOffset + userOrder!
      : manifest.toolTabOrder;

  /// האם התוסף רשאי בפועל להקדים כלים מובנים במסך "כלים".
  bool get allowsOrderBeforeBuiltIns =>
      manifest.allowOrderBeforeBuiltIns && allowOrderBeforeBuiltInsGranted;

  /// נתיב קובץ הכניסה לריצת רקע (`app.run_on_startup`). אם התוסף הצהיר על
  /// background.entrypoint קליל (ללא UI) משתמשים בו; אחרת נופלים לקובץ הכניסה
  /// הרגיל, כך שתוספי רקע קיימים ממשיכים לעבוד ללא שינוי.
  String get backgroundEntrypointPath =>
      manifest.backgroundEntrypoint ?? entrypointPath;

  bool get isLocalhostDev => sourceType == 'localhost_dev';
  bool get isDevelopment => sourceType == 'development' || isLocalhostDev;
  String get resolvedRootPath =>
      sourceType == 'development' ? devRootPath! : installPath;

  /// האם התוסף מצהיר על שימוש ברשת. תוסף כזה מוסתר מהממשק במצב 'מנותק'
  /// (`SettingsState.isOfflineMode`) רק אם [networkAccessGranted] דלוק.
  bool get requiresNetwork => manifest.networkEnabled;

  /// האם להסתיר/לחסום את התוסף במצב 'מנותק'. אם המשתמש כיבה את הרשאת הרשת
  /// התוסף אינו ניגש לרשת, ולכן חייב להישאר זמין ולהיפתח גם במצב מנותק.
  bool get blockedInOfflineMode => requiresNetwork && networkAccessGranted;

  InstalledPlugin({
    required this.pluginId,
    required this.name,
    required this.version,
    required this.installPath,
    required this.entrypointPath,
    this.iconPath,
    required this.enabled,
    required this.pinned,
    this.pinnedToNavRail = false,
    this.showInTools = true,
    bool? allowOrderBeforeBuiltInsGranted,
    this.networkAccessGranted = false,
    this.runOnStartupGranted = false,
    required this.manifest,
    required this.installedAt,
    required this.updatedAt,
    this.sourceType = 'packaged',
    this.devRootPath,
    this.userOrder,
  }) : allowOrderBeforeBuiltInsGranted =
           allowOrderBeforeBuiltInsGranted ?? manifest.allowOrderBeforeBuiltIns;

  factory InstalledPlugin.fromDbMap(Map<String, dynamic> map) {
    final manifest = PluginManifest.fromJson(
      jsonDecode(map['manifest_json'] as String),
    );
    return InstalledPlugin(
      pluginId: map['plugin_id'] as String,
      name: map['name'] as String,
      version: map['version'] as String,
      installPath: map['install_path'] as String,
      entrypointPath: map['entrypoint_path'] as String,
      iconPath: map['icon_path'] as String?,
      enabled: (map['enabled'] as int) != 0,
      pinned: (map['pinned'] as int) != 0,
      pinnedToNavRail: ((map['pinned_to_nav_rail'] as int?) ?? 0) != 0,
      showInTools: ((map['hidden_from_tools'] as int?) ?? 0) == 0,
      allowOrderBeforeBuiltInsGranted:
          ((map['allow_order_before_built_ins_granted'] as int?) ??
              (manifest.allowOrderBeforeBuiltIns ? 1 : 0)) !=
          0,
      networkAccessGranted: ((map['network_access_granted'] as int?) ?? 0) != 0,
      runOnStartupGranted: ((map['run_on_startup_granted'] as int?) ?? 0) != 0,
      manifest: manifest,
      installedAt: DateTime.parse(map['installed_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      sourceType: map['source_type'] as String? ?? 'packaged',
      devRootPath: map['dev_root_path'] as String?,
      userOrder: map['user_order'] as int?,
    );
  }

  Map<String, dynamic> toDbMap() {
    return {
      'plugin_id': pluginId,
      'name': name,
      'version': version,
      'install_path': installPath,
      'entrypoint_path': entrypointPath,
      'icon_path': iconPath,
      'enabled': enabled ? 1 : 0,
      'pinned': pinned ? 1 : 0,
      'pinned_to_nav_rail': pinnedToNavRail ? 1 : 0,
      'hidden_from_tools': showInTools ? 0 : 1,
      'allow_order_before_built_ins_granted': allowOrderBeforeBuiltInsGranted
          ? 1
          : 0,
      'manifest_json': jsonEncode(manifest.toJson()),
      'installed_at': installedAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'source_type': sourceType,
      'dev_root_path': devRootPath,
      'user_order': userOrder,
    };
  }

  InstalledPlugin copyWith({
    String? pluginId,
    String? name,
    String? version,
    String? installPath,
    String? entrypointPath,
    String? iconPath,
    bool? enabled,
    bool? pinned,
    bool? pinnedToNavRail,
    bool? showInTools,
    bool? allowOrderBeforeBuiltInsGranted,
    bool? networkAccessGranted,
    bool? runOnStartupGranted,
    PluginManifest? manifest,
    DateTime? installedAt,
    DateTime? updatedAt,
    String? sourceType,
    String? devRootPath,
    bool clearDevRootPath = false,
    int? userOrder,
    bool clearUserOrder = false,
  }) {
    return InstalledPlugin(
      pluginId: pluginId ?? this.pluginId,
      name: name ?? this.name,
      version: version ?? this.version,
      installPath: installPath ?? this.installPath,
      entrypointPath: entrypointPath ?? this.entrypointPath,
      iconPath: iconPath ?? this.iconPath,
      enabled: enabled ?? this.enabled,
      pinned: pinned ?? this.pinned,
      pinnedToNavRail: pinnedToNavRail ?? this.pinnedToNavRail,
      showInTools: showInTools ?? this.showInTools,
      allowOrderBeforeBuiltInsGranted:
          allowOrderBeforeBuiltInsGranted ??
          this.allowOrderBeforeBuiltInsGranted,
      networkAccessGranted: networkAccessGranted ?? this.networkAccessGranted,
      runOnStartupGranted: runOnStartupGranted ?? this.runOnStartupGranted,
      manifest: manifest ?? this.manifest,
      installedAt: installedAt ?? this.installedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sourceType: sourceType ?? this.sourceType,
      devRootPath: clearDevRootPath ? null : (devRootPath ?? this.devRootPath),
      userOrder: clearUserOrder ? null : (userOrder ?? this.userOrder),
    );
  }
}

/// סינון תוספים לפי מצב 'מנותק' של אוצריא — תוסף שדורש אינטרנט מוסתר מהממשק
/// במצב 'מנותק' רק אם הרשאת הרשת שלו הוענקה בפועל; אם המשתמש כיבה אותה
/// התוסף אינו ניגש לרשת, ולכן ממשיך להופיע.
extension OfflineModePluginFilter on List<InstalledPlugin> {
  List<InstalledPlugin> filterForOfflineMode(bool isOfflineMode) {
    if (!isOfflineMode) return this;
    return where((p) => !p.blockedInOfflineMode).toList();
  }
}
