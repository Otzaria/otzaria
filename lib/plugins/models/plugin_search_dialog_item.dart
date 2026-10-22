import 'package:otzaria/plugins/models/plugin_when_condition.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_query_builder.dart';

/// שורת חיפוש סטטית שתוסף מצהיר עליה ב־`contributes.startup`.
///
/// אוצריא בונה את השורה ישירות מהמניפסט; אין לה callback או קוד תוסף.
class PluginSearchDialogItem {
  static const int maxItemsPerPlugin = 4;
  static const int maxDisabledOptionsPerMode = 20;

  final String id;
  final String title;
  final bool defaultValue;
  final bool openPluginOnSubmit;

  /// כשמוגדר, סימון השורה אינו פותח את התוסף אלא מציג בטאב החיפוש המובנה
  /// מדור תוצאות מהספק החיצוני הזה (התוסף חייב להירשם אליו עם
  /// registerExternalSearchProvider). סותר את [openPluginOnSubmit].
  final String? resultsProvider;

  /// כותרת מדור התוצאות בטאב החיפוש; ברירת המחדל היא [title].
  final String resultsTitle;

  /// כשמוגדר, טאב חיפוש שהסתיים מציג כפתור בכותרת הזו, ולחיצה מעבירה לתוסף
  /// את אותו חיפוש — כמו שליחה עם השורה מסומנת. דורש [openPluginOnSubmit].
  final String? resultsAction;

  final Set<SearchMode> visibleInModes;
  final Map<SearchMode, Set<String>> disabledSearchOptionIds;

  /// תנאי הצגה על ערכי הגדרות/אחסון — null = מוצג תמיד.
  final PluginWhenCondition? when;

  const PluginSearchDialogItem({
    required this.id,
    required this.title,
    required this.defaultValue,
    required this.openPluginOnSubmit,
    this.resultsProvider,
    String? resultsTitle,
    this.resultsAction,
    required this.visibleInModes,
    required this.disabledSearchOptionIds,
    this.when,
  }) : resultsTitle = resultsTitle ?? title;

  bool isVisibleIn(SearchMode mode) => visibleInModes.contains(mode);

  Set<String> disabledOptionsFor(SearchMode mode) =>
      disabledSearchOptionIds[mode] ?? const {};

  factory PluginSearchDialogItem.fromPayload(Map<String, dynamic> payload) {
    const allowedFields = {
      'id',
      'type',
      'title',
      'defaultValue',
      'openPluginOnSubmit',
      'resultsProvider',
      'resultsTitle',
      'resultsAction',
      'visibleInModes',
      'disabledSearchOptions',
      'when',
    };
    final unknownFields = payload.keys
        .where((key) => !allowedFields.contains(key))
        .toList();
    if (unknownFields.isNotEmpty) {
      throw const PluginSearchDialogItemException(
        'unknown search dialog item field',
      );
    }

    final id = _requiredText(payload['id'], field: 'id', maxLength: 128);
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(id)) {
      throw const PluginSearchDialogItemException(
        'search dialog item id is invalid',
      );
    }
    if (payload['type'] != 'checkbox') {
      throw const PluginSearchDialogItemException(
        'only checkbox search dialog items are supported',
      );
    }
    final title = _requiredText(
      payload['title'],
      field: 'title',
      maxLength: 120,
    );
    final defaultValue = payload['defaultValue'];
    if (defaultValue != null && defaultValue is! bool) {
      throw const PluginSearchDialogItemException(
        'defaultValue must be a bool',
      );
    }
    final openPluginOnSubmit = payload['openPluginOnSubmit'];
    if (openPluginOnSubmit != null && openPluginOnSubmit is! bool) {
      throw const PluginSearchDialogItemException(
        'openPluginOnSubmit must be a bool',
      );
    }
    final resultsProvider = payload['resultsProvider'];
    if (resultsProvider != null &&
        (resultsProvider is! String ||
            !RegExp(r'^[a-z0-9._-]{1,64}$').hasMatch(resultsProvider))) {
      throw const PluginSearchDialogItemException(
        'resultsProvider must be a short lowercase identifier',
      );
    }
    if (resultsProvider != null && openPluginOnSubmit == true) {
      throw const PluginSearchDialogItemException(
        'resultsProvider and openPluginOnSubmit are mutually exclusive',
      );
    }
    final resultsTitle = payload['resultsTitle'] == null
        ? null
        : _requiredText(
            payload['resultsTitle'],
            field: 'resultsTitle',
            maxLength: 120,
          );
    if (resultsTitle != null && resultsProvider == null) {
      throw const PluginSearchDialogItemException(
        'resultsTitle requires resultsProvider',
      );
    }
    final resultsAction = payload['resultsAction'] == null
        ? null
        : _requiredText(
            payload['resultsAction'],
            field: 'resultsAction',
            maxLength: 120,
          );
    if (resultsAction != null && openPluginOnSubmit != true) {
      throw const PluginSearchDialogItemException(
        'resultsAction requires openPluginOnSubmit',
      );
    }

    final visibleInModes = _parseModes(
      payload['visibleInModes'],
      field: 'visibleInModes',
      fallback: SearchMode.values.toSet(),
    );
    final disabledSearchOptionIds = _parseDisabledOptions(
      payload['disabledSearchOptions'],
    );

    PluginWhenCondition? when;
    if (payload['when'] != null) {
      try {
        when = PluginWhenCondition.fromJson(payload['when']);
      } on PluginWhenConditionException catch (error) {
        throw PluginSearchDialogItemException('when is invalid: $error');
      }
    }

    return PluginSearchDialogItem(
      id: id,
      when: when,
      title: title,
      defaultValue: defaultValue as bool? ?? false,
      openPluginOnSubmit: openPluginOnSubmit as bool? ?? false,
      resultsProvider: resultsProvider as String?,
      resultsTitle: resultsTitle,
      resultsAction: resultsAction,
      visibleInModes: Set.unmodifiable(visibleInModes),
      disabledSearchOptionIds: Map.unmodifiable({
        for (final entry in disabledSearchOptionIds.entries)
          entry.key: Set.unmodifiable(entry.value),
      }),
    );
  }

  static String _requiredText(
    Object? value, {
    required String field,
    required int maxLength,
  }) {
    if (value is! String ||
        value.isEmpty ||
        value.length > maxLength ||
        RegExp(r'[\u0000-\u001F\u007F]').hasMatch(value)) {
      throw PluginSearchDialogItemException(
        '$field is required and must be text',
      );
    }
    return value;
  }

  static Set<SearchMode> _parseModes(
    Object? raw, {
    required String field,
    required Set<SearchMode> fallback,
  }) {
    if (raw == null) return fallback;
    if (raw is! List || raw.isEmpty || raw.any((value) => value is! String)) {
      throw PluginSearchDialogItemException(
        '$field must be a non-empty string list',
      );
    }
    final modes = <SearchMode>{};
    for (final value in raw.cast<String>()) {
      final matching = SearchMode.values.where(
        (candidate) => candidate.name == value,
      );
      if (matching.isEmpty) {
        throw PluginSearchDialogItemException(
          '$field contains an unsupported mode',
        );
      }
      modes.add(matching.single);
    }
    if (modes.length != raw.length) {
      throw PluginSearchDialogItemException('$field contains a duplicate mode');
    }
    return modes;
  }

  static Map<SearchMode, Set<String>> _parseDisabledOptions(Object? raw) {
    if (raw == null) return const {};
    if (raw is! Map) {
      throw const PluginSearchDialogItemException(
        'disabledSearchOptions must be an object',
      );
    }
    final result = <SearchMode, Set<String>>{};
    for (final entry in raw.entries) {
      if (entry.key is! String ||
          entry.value is! List ||
          (entry.value as List).any((value) => value is! String)) {
        throw const PluginSearchDialogItemException(
          'disabledSearchOptions must map modes to string lists',
        );
      }
      final matching = SearchMode.values.where(
        (candidate) => candidate.name == entry.key,
      );
      if (matching.isEmpty) {
        throw const PluginSearchDialogItemException(
          'disabledSearchOptions contains an unsupported mode',
        );
      }
      final ids = (entry.value as List).cast<String>();
      if (ids.length > maxDisabledOptionsPerMode ||
          ids.toSet().length != ids.length ||
          ids.any(
            (id) => !SearchQueryBuilder.isPluginControllableOptionId(id),
          )) {
        throw const PluginSearchDialogItemException(
          'disabledSearchOptions contains an invalid option id',
        );
      }
      result[matching.single] = ids.toSet();
    }
    return result;
  }
}

class PluginSearchDialogItemException implements Exception {
  final String message;

  const PluginSearchDialogItemException(this.message);

  @override
  String toString() => message;
}
