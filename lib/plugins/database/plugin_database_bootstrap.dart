import 'package:path/path.dart' as p;
import 'package:otzaria/core/app_paths.dart';
import 'plugin_database_registry.dart';
import 'plugin_database_source.dart';

/// אתחול מקורות נתונים SQLite לתוספים.
///
/// קוראת לפונקציה זו פעם אחת בזמן אתחול האפליקציה (מ-`initialize()` ב-main.dart).
/// היא רושמת את כל מסדי הנתונים שהאפליקציה מציעה לתוספים.
///
/// מקורות שקובץ ה-DB שלהם לא קיים — נרשמים עם הנתיב אך יסומנו כ-unavailable
/// בתגובה ל-`database.listSources`. אין crash.
Future<void> initPluginDatabaseSources() async {
  final libraryPath = await AppPaths.getLibraryPath();

  _registerTalmudSynopsis(libraryPath);
}

void _registerTalmudSynopsis(String libraryPath) {
  final dbPath = p.join(libraryPath, 'talmud_synopsis_pooled.db');

  // נרשם תמיד — ה-service יבדוק בזמן ריצה אם הקובץ קיים (available: true/false)
  PluginDatabaseRegistry.instance.register(
    PluginDatabaseSource(
      sourceId: 'talmud_synopsis',
      label: 'עדי נוסח בבלי',
      databasePath: dbPath,
      readOnly: true,
      policy: PluginDatabasePolicy(
        tables: {
          'tractates',
          'pages',
          'witnesses',
          'alignments',
          'readings',
          'strings',
          'page_witnesses',
        },
        columnsByTable: {
          'tractates': {'id', 'sort_order', 'name_text_id'},
          'pages': {'id', 'tractate_id', 'sort_order', 'name_text_id'},
          'witnesses': {'id', 'name_text_id'},
          'alignments': {
            'id',
            'page_id',
            'kind',
            'sequence_number',
            'reference_text_id',
          },
          'readings': {'alignment_id', 'witness_id', 'text_text_id'},
          'strings': {'id', 'value'},
          'page_witnesses': {'page_id', 'kind', 'column_index', 'witness_id'},
        },
        allowedJoins: [
          PluginJoinRule(
            tableA: 'tractates',
            columnA: 'id',
            tableB: 'pages',
            columnB: 'tractate_id',
          ),
          PluginJoinRule(
            tableA: 'tractates',
            columnA: 'name_text_id',
            tableB: 'strings',
            columnB: 'id',
          ),
          PluginJoinRule(
            tableA: 'pages',
            columnA: 'name_text_id',
            tableB: 'strings',
            columnB: 'id',
          ),
          PluginJoinRule(
            tableA: 'pages',
            columnA: 'id',
            tableB: 'alignments',
            columnB: 'page_id',
          ),
          PluginJoinRule(
            tableA: 'alignments',
            columnA: 'reference_text_id',
            tableB: 'strings',
            columnB: 'id',
          ),
          PluginJoinRule(
            tableA: 'alignments',
            columnA: 'id',
            tableB: 'readings',
            columnB: 'alignment_id',
          ),
          PluginJoinRule(
            tableA: 'witnesses',
            columnA: 'id',
            tableB: 'readings',
            columnB: 'witness_id',
          ),
          PluginJoinRule(
            tableA: 'witnesses',
            columnA: 'name_text_id',
            tableB: 'strings',
            columnB: 'id',
          ),
          PluginJoinRule(
            tableA: 'readings',
            columnA: 'text_text_id',
            tableB: 'strings',
            columnB: 'id',
          ),
          PluginJoinRule(
            tableA: 'pages',
            columnA: 'id',
            tableB: 'page_witnesses',
            columnB: 'page_id',
          ),
          PluginJoinRule(
            tableA: 'witnesses',
            columnA: 'id',
            tableB: 'page_witnesses',
            columnB: 'witness_id',
          ),
        ],
        maxJoins: 8,
      ),
    ),
  );
}
