import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:sqlite3/sqlite3.dart';

/// סכמת ה-DB ה*נוכחית* — אחרי שכל המיגרציות רצו. נטענת ידנית בטסטים כי
/// אנחנו רוצים DB in-memory בלי לעבור דרך FS / singleton.
const String _currentCreateTable = '''
  CREATE TABLE plugin_installation (
    plugin_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    version TEXT NOT NULL,
    install_path TEXT NOT NULL,
    entrypoint_path TEXT NOT NULL,
    icon_path TEXT,
    enabled INTEGER NOT NULL,
    pinned INTEGER NOT NULL DEFAULT 1,
    pinned_to_nav_rail INTEGER NOT NULL DEFAULT 0,
    manifest_json TEXT NOT NULL,
    installed_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    source_type TEXT NOT NULL DEFAULT 'packaged',
    dev_root_path TEXT,
    user_order INTEGER
  )
''';

const String _originalUpdatedAt = '2026-01-01T00:00:00.000Z';

void _seed(Database db, String pluginId, {int? userOrder}) {
  db.execute(
    'INSERT INTO plugin_installation (plugin_id, name, version, install_path, '
    'entrypoint_path, enabled, pinned, manifest_json, installed_at, '
    'updated_at, user_order) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      pluginId,
      'name-$pluginId',
      '1.0.0',
      '/x/$pluginId',
      'index.html',
      1,
      1,
      '{}',
      _originalUpdatedAt,
      _originalUpdatedAt,
      userOrder,
    ],
  );
}

int? _readUserOrder(Database db, String pluginId) {
  final rows = db.select(
    'SELECT user_order FROM plugin_installation WHERE plugin_id = ?',
    [pluginId],
  );
  return rows.first['user_order'] as int?;
}

String _readUpdatedAt(Database db, String pluginId) {
  final rows = db.select(
    'SELECT updated_at FROM plugin_installation WHERE plugin_id = ?',
    [pluginId],
  );
  return rows.first['updated_at'] as String;
}

void main() {
  group('PluginSystemDatabase.applyUserOrderUpdates', () {
    late Database db;

    setUp(() {
      db = sqlite3.openInMemory();
      db.execute(_currentCreateTable);
    });

    tearDown(() {
      db.close();
    });

    test('writes the new user_order value for the given plugin', () {
      _seed(db, 'a');
      _seed(db, 'b');

      PluginSystemDatabase.applyUserOrderUpdates(db, {'a': 0, 'b': 1});

      expect(_readUserOrder(db, 'a'), 0);
      expect(_readUserOrder(db, 'b'), 1);
    });

    test('overwrites a previous user_order value', () {
      _seed(db, 'a', userOrder: 5);

      PluginSystemDatabase.applyUserOrderUpdates(db, {'a': 2});

      expect(_readUserOrder(db, 'a'), 2);
    });

    test('does NOT touch updated_at — this is the core fix preventing the '
        'IndexedStack/WebView dispose crash on reorder', () {
      _seed(db, 'a');
      _seed(db, 'b');

      PluginSystemDatabase.applyUserOrderUpdates(db, {'a': 0, 'b': 1});

      expect(
        _readUpdatedAt(db, 'a'),
        _originalUpdatedAt,
        reason:
            'reorder must NOT bump updated_at — see comments in '
            'PluginSystemDatabase.updatePluginsUserOrder',
      );
      expect(_readUpdatedAt(db, 'b'), _originalUpdatedAt);
    });

    test('empty ordering is a no-op (does not begin a transaction)', () {
      _seed(db, 'a', userOrder: 5);

      expect(
        () => PluginSystemDatabase.applyUserOrderUpdates(db, {}),
        returnsNormally,
      );

      expect(
        _readUserOrder(db, 'a'),
        5,
        reason: 'pre-existing user_order must be untouched',
      );
    });

    test('silently ignores plugin_ids that do not exist in the DB', () {
      _seed(db, 'a');

      // ה-UPDATE לא יתפוס שורות — אבל לא אמור לזרוק.
      expect(
        () => PluginSystemDatabase.applyUserOrderUpdates(db, {
          'a': 0,
          'ghost': 1,
        }),
        returnsNormally,
      );

      expect(_readUserOrder(db, 'a'), 0);
      // 'ghost' לא קיים, אז אין מה לקרוא.
      final ghost = db.select(
        'SELECT 1 FROM plugin_installation WHERE plugin_id = ?',
        ['ghost'],
      );
      expect(ghost.isEmpty, isTrue);
    });

    test('rolls back when a single statement fails — partial writes never '
        'leak through', () {
      _seed(db, 'a', userOrder: 100);
      _seed(db, 'b', userOrder: 200);

      // נחבל ב-SQL כדי לאלץ כשל באמצע ה-transaction: ננתק את הטבלה אחרי
      // העדכון הראשון. כדי לעשות זאת בלי לשנות את applyUserOrderUpdates,
      // נגרום לכשל ע"י ordering שבו ההודעה השנייה היא סוג שלא מתאים
      // לעמודה — נשתמש בטריגר שזורק.
      db.execute('''
        CREATE TRIGGER reject_b BEFORE UPDATE OF user_order ON plugin_installation
        WHEN NEW.plugin_id = 'b'
        BEGIN
          SELECT RAISE(ABORT, 'forced-fail');
        END
      ''');

      expect(
        () => PluginSystemDatabase.applyUserOrderUpdates(db, {'a': 0, 'b': 1}),
        throwsA(anything),
      );

      // ה-rollback צריך להחזיר את 'a' לערך המקורי 100, לא לערך שנכתב באמצע.
      expect(
        _readUserOrder(db, 'a'),
        100,
        reason: 'rollback must undo the partial write to a',
      );
      expect(_readUserOrder(db, 'b'), 200);
    });

    test(
      'handles arbitrary integer values (including negatives and large)',
      () {
        _seed(db, 'a');
        _seed(db, 'b');

        PluginSystemDatabase.applyUserOrderUpdates(db, {
          'a': -1,
          'b': 2147483647, // INT32 max
        });

        expect(_readUserOrder(db, 'a'), -1);
        expect(_readUserOrder(db, 'b'), 2147483647);
      },
    );

    test('works inside an outer transaction (uses SAVEPOINT, not '
        'BEGIN TRANSACTION) — SQLite does not allow nested BEGIN', () {
      _seed(db, 'a');
      _seed(db, 'b');

      // טרנזקציה חיצונית — סימולציה של caller שעוטף את ה-update בעצמו.
      db.execute('BEGIN TRANSACTION');
      try {
        PluginSystemDatabase.applyUserOrderUpdates(db, {'a': 0, 'b': 1});
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }

      expect(_readUserOrder(db, 'a'), 0);
      expect(_readUserOrder(db, 'b'), 1);
    });

    test('rollback inside an outer transaction leaves the outer transaction '
        'intact — caller can still commit/rollback its own scope', () {
      _seed(db, 'a', userOrder: 100);
      _seed(db, 'b', userOrder: 200);

      // טריגר שיכשיל את העדכון של 'b' (אבל לא של 'a').
      db.execute('''
        CREATE TRIGGER reject_b BEFORE UPDATE OF user_order ON plugin_installation
        WHEN NEW.plugin_id = 'b'
        BEGIN
          SELECT RAISE(ABORT, 'forced-fail');
        END
      ''');

      db.execute('BEGIN TRANSACTION');
      var innerFailed = false;
      try {
        PluginSystemDatabase.applyUserOrderUpdates(db, {'a': 0, 'b': 1});
      } catch (_) {
        innerFailed = true;
      }
      // למרות שה-savepoint התגלגל אחורה, הטרנזקציה החיצונית עדיין פעילה
      // ויכולה לעשות commit. ה-commit הזה צריך להצליח (לא לזרוק).
      expect(
        () => db.execute('COMMIT'),
        returnsNormally,
        reason:
            'outer transaction must still be live after inner SAVEPOINT '
            'rollback',
      );

      expect(innerFailed, isTrue);
      // a חזר ל-100 כי ה-savepoint התגלגל אחורה.
      expect(_readUserOrder(db, 'a'), 100);
      expect(_readUserOrder(db, 'b'), 200);
    });
  });
}
