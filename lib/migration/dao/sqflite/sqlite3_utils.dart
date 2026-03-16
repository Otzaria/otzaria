import 'package:sqlite3/sqlite3.dart';

/// Converts a sqlite3 [ResultSet] to a list of dynamic maps.
extension ResultSetExt on ResultSet {
  List<Map<String, dynamic>> toMapList() =>
      map((row) => Map<String, dynamic>.from(row)).toList();
}

/// Returns the first integer value from a single-column [ResultSet], or null.
int? firstIntValue(ResultSet result) {
  if (result.isEmpty) return null;
  final value = result.first.values.first;
  if (value == null) return null;
  return value as int;
}

/// Runs [fn] inside an explicit SQLite transaction.
/// Commits on success, rolls back on error.
void withTransaction(Database db, void Function() fn) {
  db.execute('BEGIN');
  try {
    fn();
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}
