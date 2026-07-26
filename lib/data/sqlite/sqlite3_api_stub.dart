import 'package:sqlite3/common.dart';

export 'package:sqlite3/common.dart';

/// המקבילות של הטיפוסים הנייטיביים מ-`package:sqlite3/sqlite3.dart`, כך
/// שקוד משותף שמייבא את [sqlite3_api.dart] מתקמפל גם בלי dart:ffi.
typedef Database = CommonDatabase;
typedef PreparedStatement = CommonPreparedStatement;

class _UnsupportedSqlite3 implements CommonSqlite3 {
  const _UnsupportedSqlite3();

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('SQLite נייטיבי אינו זמין בפלטפורמה זו');
}

const CommonSqlite3 sqlite3 = _UnsupportedSqlite3();
