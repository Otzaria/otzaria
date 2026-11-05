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

/// מתי הכפתור מוצג בשדה.
enum PluginSearchFieldActionVisibility {
  always,

  /// רק כשיש טקסט בשדה, כמו כפתור הניקוי.
  nonEmptyText;

  static PluginSearchFieldActionVisibility? fromName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// מה לחיצה על הכפתור עושה.
enum PluginSearchFieldActionMode {
  /// פותחת סשן ושולחת לתוסף `search.fieldAction.invoked`.
  session,

  /// מחליפה מחזורית את מקור הספרים באיתור הספרים (רק בשדה `library`):
  /// הכול, ספרי התוסף בלבד, ספרי הספרייה בלבד. בלי אירוע ובלי סשן.
  providerBooksFilter;

  static PluginSearchFieldActionMode? fromName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
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

  /// אורך מרבי של [pluginOnlyLabel] ו-[libraryOnlyLabel]: תווית קצרה בתוך
  /// שדה חיפוש.
  static const int maxFilterLabelLength = 24;

  final String id;
  final String title;
  final String? icon;
  final String? activeIcon;

  /// ב-[PluginSearchFieldActionMode.providerBooksFilter]: האייקון במצב
  /// "ספרי הספרייה בלבד". בלעדיו משמש [icon].
  final String? libraryOnlyIcon;

  /// ב-[PluginSearchFieldActionMode.providerBooksFilter]: התווית שליד האייקון
  /// במצב "ספרי התוסף בלבד" (למשל "רק בר אילן"). בלעדיה: "רק התוסף".
  final String? pluginOnlyLabel;

  /// ב-[PluginSearchFieldActionMode.providerBooksFilter]: התווית במצב "ספרי
  /// הספרייה בלבד" (למשל "רק אוצריא"). בלעדיה: "רק הספרייה".
  final String? libraryOnlyLabel;
  final Set<PluginSearchField> fields;
  final PluginSearchFieldActionVisibility visibleWhen;
  final PluginSearchFieldActionMode mode;

  const PluginSearchFieldAction({
    required this.id,
    required this.title,
    required this.fields,
    this.icon,
    this.activeIcon,
    this.libraryOnlyIcon,
    this.pluginOnlyLabel,
    this.libraryOnlyLabel,
    this.visibleWhen = PluginSearchFieldActionVisibility.always,
    this.mode = PluginSearchFieldActionMode.session,
  });

  bool showsIn(PluginSearchField field) => fields.contains(field);

  bool get showOnlyWithText =>
      visibleWhen == PluginSearchFieldActionVisibility.nonEmptyText;

  bool get isProviderBooksFilter =>
      mode == PluginSearchFieldActionMode.providerBooksFilter;

  /// האם הכפתור מוצג בשדה שהטקסט שלו [text].
  bool isVisibleFor(String text) => !showOnlyWithText || text.isNotEmpty;

  /// [fields] חסר = כל השדות הנתמכים. ערך לא מוכר מדולג, כדי שתוסף שנכתב
  /// לגרסה חדשה עם שדה נוסף ימשיך לעבוד בגרסה ישנה יותר.
  factory PluginSearchFieldAction.fromPayload(Map<String, dynamic> payload) {
    const allowedFields = {
      'id',
      'title',
      'icon',
      'activeIcon',
      'libraryOnlyIcon',
      'pluginOnlyLabel',
      'libraryOnlyLabel',
      'fields',
      'visibleWhen',
      'mode',
    };
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
    final libraryOnlyIcon = payload['libraryOnlyIcon'] == null
        ? null
        : _text(
            payload['libraryOnlyIcon'],
            field: 'libraryOnlyIcon',
            maxLength: 128,
          );
    final pluginOnlyLabel = payload['pluginOnlyLabel'] == null
        ? null
        : _label(payload['pluginOnlyLabel'], field: 'pluginOnlyLabel');
    final libraryOnlyLabel = payload['libraryOnlyLabel'] == null
        ? null
        : _label(payload['libraryOnlyLabel'], field: 'libraryOnlyLabel');
    final rawVisibleWhen = payload['visibleWhen'];
    final visibleWhen = rawVisibleWhen == null
        ? PluginSearchFieldActionVisibility.always
        : rawVisibleWhen is String
        ? PluginSearchFieldActionVisibility.fromName(rawVisibleWhen)
        : null;
    if (visibleWhen == null) {
      throw const PluginSearchFieldActionException(
        'visibleWhen must be "always" or "nonEmptyText"',
      );
    }
    final rawMode = payload['mode'];
    final mode = rawMode == null
        ? PluginSearchFieldActionMode.session
        : rawMode is String
        ? PluginSearchFieldActionMode.fromName(rawMode)
        : null;
    if (mode == null) {
      throw const PluginSearchFieldActionException(
        'mode must be "session" or "providerBooksFilter"',
      );
    }
    final isFilter = mode == PluginSearchFieldActionMode.providerBooksFilter;
    if (libraryOnlyIcon != null && !isFilter) {
      throw const PluginSearchFieldActionException(
        'libraryOnlyIcon requires mode providerBooksFilter',
      );
    }
    if ((pluginOnlyLabel != null || libraryOnlyLabel != null) && !isFilter) {
      throw const PluginSearchFieldActionException(
        'pluginOnlyLabel and libraryOnlyLabel require mode providerBooksFilter',
      );
    }

    final rawFields = payload['fields'];
    Set<PluginSearchField> fields;
    if (rawFields == null) {
      fields = isFilter
          ? {PluginSearchField.library}
          : PluginSearchField.values.toSet();
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
    if (isFilter &&
        (fields.length != 1 || !fields.contains(PluginSearchField.library))) {
      throw const PluginSearchFieldActionException(
        'mode providerBooksFilter is valid only for the library field',
      );
    }
    return PluginSearchFieldAction(
      id: id,
      title: title,
      icon: icon,
      activeIcon: activeIcon,
      libraryOnlyIcon: libraryOnlyIcon,
      pluginOnlyLabel: pluginOnlyLabel,
      libraryOnlyLabel: libraryOnlyLabel,
      fields: Set.unmodifiable(fields),
      visibleWhen: visibleWhen,
      mode: mode,
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

  /// תווית מוצגת: טקסט, לא ריק ולא רווחים בלבד, עד [maxFilterLabelLength].
  static String _label(Object? value, {required String field}) {
    final text = _text(value, field: field, maxLength: maxFilterLabelLength);
    if (text.trim().isEmpty) {
      throw PluginSearchFieldActionException('$field must not be blank');
    }
    return text;
  }
}

class PluginSearchFieldActionException implements Exception {
  final String message;

  const PluginSearchFieldActionException(this.message);

  @override
  String toString() => message;
}
