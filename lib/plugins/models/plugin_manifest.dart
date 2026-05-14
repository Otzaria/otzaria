class PluginManifest {
  /// תבנית של שם אייקון תקין: למשל `'book_24_regular'` או `'calendar_24_filled'`.
  static final RegExp toolTabIconNamePattern =
      RegExp(r'^[a-z0-9_]+_24_(regular|filled)$');

  final int schemaVersion;
  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final String homepage;
  final String entrypoint;
  final String? icon;
  final String minAppVersion;
  final String? maxAppVersion;
  final String sdkVersion;
  final List<String> permissions;
  final bool networkEnabled;
  final List<String> networkAllowlist;
  final String toolTabTitle;
  final int toolTabOrder;
  final bool defaultPinned;

  /// שם אייקון FluentUI 24px עבור לשונית הכלים, למשל `'book_24_regular'`.
  ///
  /// נפתר ל-`IconData` קבוע באמצעות `fluentIconFromName`, מה שמאפשר ל-Flutter
  /// לבצע tree-shaking של פונט האייקונים ב-Release. אם השם לא נמצא במפה
  /// הסטטית, יוצג אייקון ברירת מחדל (פאזל).
  final String? toolTabIconName;
  final List<String> publishedDataTypes;

  /// מקורות מסד נתונים שהתוסף מצהיר עליהם (מהשדה contributes.databaseSources)
  final List<Map<String, dynamic>> databaseSources;

  PluginManifest({
    required this.schemaVersion,
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    required this.homepage,
    required this.entrypoint,
    this.icon,
    required this.minAppVersion,
    this.maxAppVersion,
    required this.sdkVersion,
    required this.permissions,
    required this.networkEnabled,
    required this.networkAllowlist,
    required this.toolTabTitle,
    required this.toolTabOrder,
    required this.defaultPinned,
    this.toolTabIconName,
    required this.publishedDataTypes,
    this.databaseSources = const [],
  });

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    final network = json['network'] as Map<String, dynamic>? ?? {};
    final contributes = json['contributes'] as Map<String, dynamic>? ?? {};
    final toolTab = contributes['toolTab'] as Map<String, dynamic>? ?? {};

    return PluginManifest(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
      description: json['description'] as String? ?? '',
      author: json['author'] as String? ?? '',
      homepage: json['homepage'] as String? ?? '',
      entrypoint: json['entrypoint'] as String,
      icon: json['icon'] as String?,
      minAppVersion: json['minAppVersion'] as String? ?? '0.0.0',
      maxAppVersion: json['maxAppVersion'] as String?,
      sdkVersion: json['sdkVersion'] as String? ?? '1.x',
      permissions: (json['permissions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      networkEnabled: network['enabled'] as bool? ?? false,
      networkAllowlist: (network['allowlist'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      toolTabTitle: toolTab['title'] as String? ?? json['name'] as String,
      toolTabOrder: toolTab['order'] as int? ?? 900,
      defaultPinned: toolTab['defaultPinned'] as bool? ?? true,
      toolTabIconName: toolTab['iconName'] as String?,
      publishedDataTypes: (contributes['publishedDataTypes'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      databaseSources:
          (contributes['databaseSources'] as List<dynamic>?)
                  ?.map((e) => Map<String, dynamic>.from(e as Map))
                  .toList() ??
              [],
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
      'minAppVersion': minAppVersion,
      'maxAppVersion': maxAppVersion,
      'sdkVersion': sdkVersion,
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
          if (toolTabIconName != null) 'iconName': toolTabIconName,
        },
        'publishedDataTypes': publishedDataTypes,
        'databaseSources': databaseSources,
      }
    };
  }
}
