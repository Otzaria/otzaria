/// שדות החיפוש שבהם תוסף יכול להוסיף כפתור פעולה. השם (`name`) הוא המזהה
/// במניפסט ובאירועים.
enum PluginSearchField {
  /// שדה החיפוש בטקסט המלא של הספרייה (דיאלוג/טאב החיפוש).
  fullText,

  /// איתור ספר או מחבר במסך הספרייה.
  library,

  /// חיפוש בתוך ספר פתוח (טקסט או PDF).
  inBook,

  /// שדה "איתור מקור".
  findRef;

  static PluginSearchField? fromName(String name) {
    for (final field in values) {
      if (field.name == name) return field;
    }
    return null;
  }
}

/// כפתור פעולה שתוסף מצהיר עליו בתוך שדות חיפוש
/// (`contributes.startup.searchFieldActions`).
///
/// אוצריא מציירת את הכפתור מהמניפסט בלבד; לחיצה פותחת "סשן" שבו התוסף
/// רשאי לכתוב טקסט לשדה (ראו PluginSearchFieldSessionService).
class PluginSearchFieldAction {
  static const int maxActionsPerPlugin = 2;

  final String id;
  final String title;
  final String? icon;
  final String? activeIcon;
  final Set<PluginSearchField> fields;

  const PluginSearchFieldAction({
    required this.id,
    required this.title,
    required this.fields,
    this.icon,
    this.activeIcon,
  });

  bool showsIn(PluginSearchField field) => fields.contains(field);

  /// [fields] חסר = כל השדות הנתמכים. ערך לא מוכר מדולג, כדי שתוסף שנכתב
  /// לגרסה חדשה עם שדה נוסף ימשיך לעבוד בגרסה ישנה יותר.
  factory PluginSearchFieldAction.fromPayload(Map<String, dynamic> payload) {
    const allowedFields = {'id', 'title', 'icon', 'activeIcon', 'fields'};
    if (payload.keys.any((key) => !allowedFields.contains(key))) {
      throw const PluginSearchFieldActionException(
        'unknown search field action field',
      );
    }
    final id = _text(payload['id'], field: 'id', maxLength: 64);
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(id)) {
      throw const PluginSearchFieldActionException(
        'search field action id is invalid',
      );
    }
    final title = _text(payload['title'], field: 'title', maxLength: 120);
    final icon = payload['icon'] == null
        ? null
        : _text(payload['icon'], field: 'icon', maxLength: 128);
    final activeIcon = payload['activeIcon'] == null
        ? null
        : _text(payload['activeIcon'], field: 'activeIcon', maxLength: 128);

    final rawFields = payload['fields'];
    Set<PluginSearchField> fields;
    if (rawFields == null) {
      fields = PluginSearchField.values.toSet();
    } else {
      if (rawFields is! List ||
          rawFields.isEmpty ||
          rawFields.any((value) => value is! String)) {
        throw const PluginSearchFieldActionException(
          'fields must be a non-empty string list',
        );
      }
      fields = {
        for (final name in rawFields.cast<String>())
          ?PluginSearchField.fromName(name),
      };
    }
    return PluginSearchFieldAction(
      id: id,
      title: title,
      icon: icon,
      activeIcon: activeIcon,
      fields: Set.unmodifiable(fields),
    );
  }

  /// שמות ב-[payload] `fields` שהגרסה הנוכחית אינה מכירה — לאזהרת אריזה.
  static List<String> unknownFieldNames(Map<String, dynamic> payload) {
    final raw = payload['fields'];
    if (raw is! List) return const [];
    return [
      for (final name in raw.whereType<String>())
        if (PluginSearchField.fromName(name) == null) name,
    ];
  }

  static String _text(
    Object? value, {
    required String field,
    required int maxLength,
  }) {
    if (value is! String ||
        value.isEmpty ||
        value.length > maxLength ||
        RegExp(r'[\u0000-\u001F\u007F]').hasMatch(value)) {
      throw PluginSearchFieldActionException(
        '$field is required and must be text',
      );
    }
    return value;
  }
}

class PluginSearchFieldActionException implements Exception {
  final String message;

  const PluginSearchFieldActionException(this.message);

  @override
  String toString() => message;
}
