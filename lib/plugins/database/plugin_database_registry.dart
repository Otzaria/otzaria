import 'plugin_database_source.dart';

/// Registry מרכזי של מקורות נתונים SQLite הזמינים לתוספים.
///
/// **רישום מקורות (אחריות האפליקציה):**
/// רישום מקורות הוא wire-up ברמת האפליקציה — לא חלק מה-API עצמו.
/// יש לקרוא ל-[register] בזמן אתחול האפליקציה, לדוגמה ב-`main.dart`:
///
/// ```dart
/// PluginDatabaseRegistry.instance.register(PluginDatabaseSource(
///   sourceId: 'my_source',
///   label: 'שם לתצוגה',
///   databasePath: '/path/to/my_source.db',
///   policy: PluginDatabasePolicy(
///     tables: {'items', 'strings'},
///     columnsByTable: {
///       'items': {'id', 'name_text_id'},
///       'strings': {'id', 'value'},
///     },
///     allowedJoins: [
///       PluginJoinRule(tableA: 'items', columnA: 'name_text_id',
///                      tableB: 'strings', columnB: 'id'),
///     ],
///   ),
/// ));
/// ```
///
/// המקורות המובנים בפועל נרשמים ב-`plugin_database_bootstrap.dart` — הוא
/// המקור היחיד לסכימות ולמגבלות שלהם.
///
/// תוספים לא יכולים לגשת ישירות ל-registry — גישתם מתווכת דרך ה-service.
class PluginDatabaseRegistry {
  static final PluginDatabaseRegistry instance = PluginDatabaseRegistry._();
  PluginDatabaseRegistry._();

  final Map<String, PluginDatabaseSource> _sources = {};

  /// רישום מקור נתונים חדש
  void register(PluginDatabaseSource source) {
    _sources[source.sourceId] = source;
  }

  /// קבלת מקור לפי ID, או null אם לא קיים
  PluginDatabaseSource? getSource(String sourceId) => _sources[sourceId];

  /// רשימת כל המקורות הרשומים
  List<PluginDatabaseSource> getAllSources() => _sources.values.toList();

  /// בדיקה אם מקור רשום
  bool hasSource(String sourceId) => _sources.containsKey(sourceId);
}
