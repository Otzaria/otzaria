import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import '../query_loader.dart';
import 'database.dart';

/// גישה ל-`line_ref` — אינדקס ההפניות הקנוני `(bookId, refKeyHash) → lineIndex`.
///
/// הטבלה נבנית בבונה ה-DB, ולכן חסרה במסדים שנבנו לפניה; [isAvailable] מאפשר
/// לקורא ליפול חזרה למסלול ה-TOC במקום לסרוק.
/// שורה מועמדת מהאינדקס, עם ה-heRef שלה לאימות ההתאמה.
typedef LineRefCandidate = ({
  int bookId,
  int lineIndex,
  int lineId,
  String? heRef,
});

class LineRefDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  LineRefDao(this._db) {
    _queries = QueryLoader.loadQueries('LineRefQueries.sq');
  }

  Future<sqlite3.Database> get database => _db.database;

  /// האם המסד הנוכחי מכיל את טבלת האינדקס.
  Future<bool> isAvailable() async => (await _db.capabilities).hasLineRef;

  /// המועמדים למפתח [refKeyHash] בכל אחד מ-[bookIds] — שאילתה מאוגדת אחת,
  /// כדי שהקלדה מול כמה ספרים מועמדים לא תייצר רצף פניות. ה-heRef מוחזר כדי
  /// שהקורא יאמת את ההתאמה ולא יסתמך על ה-hash לבדו.
  Future<List<LineRefCandidate>> candidatesForBooks(
    List<int> bookIds,
    int refKeyHash,
  ) async {
    if (bookIds.isEmpty || !await isAvailable()) return const [];
    final db = await database;
    final ids = bookIds.join(',');
    return db
        .select(
          'SELECT lr.bookId, lr.lineIndex, l.id AS lineId, l.heRef '
          'FROM line_ref lr '
          'JOIN line l ON l.bookId = lr.bookId AND l.lineIndex = lr.lineIndex '
          'WHERE lr.refKeyHash = ? AND lr.bookId IN ($ids) '
          'ORDER BY lr.bookId, lr.lineIndex',
          [refKeyHash],
        )
        .map(
          (row) => (
            bookId: row['bookId'] as int,
            lineIndex: row['lineIndex'] as int,
            lineId: row['lineId'] as int,
            heRef: row['heRef'] as String?,
          ),
        )
        .toList();
  }

  Future<void> insert(int bookId, int refKeyHash, int lineIndex) async {
    final db = await database;
    db.execute(_queries['insert']!, [bookId, refKeyHash, lineIndex]);
  }

  Future<void> deleteByBookId(int bookId) async {
    final db = await database;
    db.execute(_queries['deleteByBookId']!, [bookId]);
  }
}
