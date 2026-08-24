import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:sqlite3/sqlite3.dart';

/// הטבלה בלבד — DB in-memory בלי לעבור דרך ה-singleton וה-FS.
const String _createKvTable = '''
  CREATE TABLE plugin_kv_store (
    plugin_id TEXT NOT NULL,
    namespace TEXT NOT NULL,
    key TEXT NOT NULL,
    value_json TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    PRIMARY KEY (plugin_id, namespace, key)
  )
''';

void _seed(
  Database db,
  String pluginId,
  String namespace,
  String key,
  String value,
) {
  db.execute(
    'INSERT INTO plugin_kv_store (plugin_id, namespace, key, value_json, '
    'updated_at) VALUES (?, ?, ?, ?, ?)',
    [pluginId, namespace, key, value, '2026-01-01T00:00:00.000Z'],
  );
}

void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory();
    db.execute(_createKvTable);
  });

  tearDown(() => db.close());

  test('מחזיר את המפתחות הקיימים ומדלג על חסרים', () {
    _seed(db, 'p1', 'default', 'a', '1');
    _seed(db, 'p1', 'default', 'b', '"שבת"');

    final values = PluginSystemDatabase.selectKVMany(db, 'p1', 'default', [
      'a',
      'b',
      'missing',
    ]);

    expect(values, {'a': '1', 'b': '"שבת"'});
  });

  test('מבודד לפי תוסף ולפי namespace', () {
    _seed(db, 'p1', 'default', 'a', '1');
    _seed(db, 'p2', 'default', 'a', '2');
    _seed(db, 'p1', 'other', 'a', '3');

    expect(
      PluginSystemDatabase.selectKVMany(db, 'p1', 'default', ['a']),
      {'a': '1'},
    );
  });

  test('רשימה ריקה אינה מריצה שאילתה', () {
    expect(
      PluginSystemDatabase.selectKVMany(db, 'p1', 'default', const []),
      isEmpty,
    );
  });

  test('חורג מגודל האצווה — נטען באצוות ולא מאבד מפתחות', () {
    const total = PluginSystemDatabase.maxKVBulkKeys * 2 + 50;
    for (var i = 0; i < total; i++) {
      _seed(db, 'p1', 'default', 'k$i', '$i');
    }

    final values = PluginSystemDatabase.selectKVMany(db, 'p1', 'default', [
      for (var i = 0; i < total; i++) 'k$i',
    ]);

    expect(values, hasLength(total));
    expect(values['k0'], '0');
    expect(values['k${total - 1}'], '${total - 1}');
  });
}
