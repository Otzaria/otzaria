import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/models/alt_toc_entry.dart';
import 'package:otzaria/migration/models/alt_toc_structure.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/links.dart';

/// קריאת הכותרות החלופיות ('כותרות') של ספרים אישיים מ-user_books.db,
/// באותם מודלים שהלשונית מקבלת מהספרייה הרשמית.
class UserAltTocRepository {
  final MyDatabase _db;

  UserAltTocRepository(this._db);

  /// מזהה הספר ב-user_books.db: לפי נתיב הקובץ כשידוע, אחרת לפי כותרת
  /// (וקטגוריה, אם צוינה).
  Future<int?> bookId({
    required String title,
    int? categoryId,
    String? filePath,
  }) async {
    final db = await _db.database;
    if (filePath != null) {
      final rows = db.select('SELECT id FROM book WHERE filePath = ? LIMIT 1', [
        filePath,
      ]);
      if (rows.isNotEmpty) return rows.first['id'] as int;
    }
    final rows = db.select(
      'SELECT id FROM book WHERE title = ?1 '
      'AND (?2 IS NULL OR categoryId = ?2) LIMIT 1',
      [title, categoryId],
    );
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  Future<List<AltTocStructure>> structures(int bookId) async {
    final db = await _db.database;
    return [
      for (final row in db.select(
        'SELECT id, bookId, key, heTitle FROM user_alt_toc_structure '
        'WHERE bookId = ? ORDER BY position, id',
        [bookId],
      ))
        AltTocStructure(
          id: row['id'] as int,
          bookId: row['bookId'] as int,
          key: row['key'] as String,
          title: row['heTitle'] as String,
          heTitle: row['heTitle'] as String,
          source: BookSource.user,
        ),
    ];
  }

  Future<List<AltTocEntry>> entries(int structureId) async {
    final db = await _db.database;
    return [
      for (final row in db.select(
        'SELECT * FROM user_alt_toc_entry WHERE structureId = ? ORDER BY id',
        [structureId],
      ))
        AltTocEntry(
          id: row['id'] as int,
          structureId: structureId,
          parentId: row['parentId'] as int?,
          textId: 0,
          level: row['level'] as int,
          isLastChild: row['isLastChild'] == 1,
          hasChildren: row['hasChildren'] == 1,
          text: row['text'] as String,
        ),
    ];
  }

  /// הערכים עם השורה שלהם (null לכותרת-אב בלי שורה), בסדר הקובץ.
  Future<
    List<({int id, int? parentId, int level, int? lineIndex, String text})>
  >
  entriesWithLineIndex(int structureId) async {
    final db = await _db.database;
    return [
      for (final row in db.select(
        'SELECT id, parentId, level, lineIndex, text FROM user_alt_toc_entry '
        'WHERE structureId = ? ORDER BY id',
        [structureId],
      ))
        (
          id: row['id'] as int,
          parentId: row['parentId'] as int?,
          level: row['level'] as int,
          lineIndex: row['lineIndex'] as int?,
          text: row['text'] as String,
        ),
    ];
  }

  Future<List<({int lineIndex, String text})>> lineIndices(
    int structureId,
  ) async {
    final db = await _db.database;
    return [
      for (final row in db.select(
        'SELECT lineIndex, text FROM user_alt_toc_entry '
        'WHERE structureId = ? AND lineIndex IS NOT NULL ORDER BY lineIndex, id',
        [structureId],
      ))
        (lineIndex: row['lineIndex'] as int, text: row['text'] as String),
    ];
  }

  /// הקישור לשורת הכותרת. לכותרת-אב בלי שורה — שורת הצאצא הראשון שיש לו.
  Future<List<Link>> linksForEntry(int structureId, int entryId) async {
    final all = await entriesWithLineIndex(structureId);
    final byId = {for (final e in all) e.id: e};
    final entry = byId[entryId];
    if (entry == null) return const [];

    int? lineIndex = entry.lineIndex;
    if (lineIndex == null) {
      for (final candidate in all) {
        if (candidate.lineIndex != null &&
            _isDescendant(candidate.id, entryId, byId)) {
          lineIndex = candidate.lineIndex;
          break;
        }
      }
    }
    if (lineIndex == null) return const [];

    final db = await _db.database;
    final rows = db.select(
      'SELECT b.title, b.categoryId FROM user_alt_toc_structure s '
      'JOIN book b ON b.id = s.bookId WHERE s.id = ? LIMIT 1',
      [structureId],
    );
    if (rows.isEmpty) return const [];
    final title = rows.first['title'] as String;
    return [
      Link(
        heRef: entry.text,
        index1: 0,
        path2: title,
        index2: lineIndex + 1,
        connectionType: 'alt_toc',
        targetCategoryId: rows.first['categoryId'] as int?,
        targetSource: BookSource.user,
      ),
    ];
  }

  /// הכותרת שבתחומה נמצאת [lineIndex]: האחרונה שנפתחת בה או לפניה, והעמוקה
  /// מביניהן כשכמה נפתחות באותה שורה.
  Future<int?> entryForLine(int structureId, int lineIndex) async {
    final db = await _db.database;
    final rows = db.select(
      'SELECT id FROM user_alt_toc_entry '
      'WHERE structureId = ? AND lineIndex IS NOT NULL AND lineIndex <= ? '
      'ORDER BY lineIndex DESC, level DESC, id DESC LIMIT 1',
      [structureId, lineIndex],
    );
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  /// סימני החלוקה (עלי סימנים/סעיפים) וכותרות הנושא הגולמיות של הספר.
  Future<
    ({
      Map<int, String> markers,
      List<({int lineIndex, String label})> headings,
    })
  >
  inlineSectionRows(int bookId) async {
    final db = await _db.database;
    final markers = <int, String>{};
    for (final row in db.select(
      'SELECT e.lineIndex, e.text FROM user_alt_toc_structure s '
      'JOIN user_alt_toc_entry e ON e.structureId = s.id '
      "WHERE s.bookId = ? AND s.key IN ('Simanim', 'Seifim') "
      'AND e.hasChildren = 0 AND e.lineIndex IS NOT NULL',
      [bookId],
    )) {
      markers[row['lineIndex'] as int] = row['text'] as String;
    }
    final headings = [
      for (final row in db.select(
        'SELECT e.lineIndex, e.text FROM user_alt_toc_structure s '
        'JOIN user_alt_toc_entry e ON e.structureId = s.id '
        "WHERE s.bookId = ? AND s.key = 'Topic' AND e.lineIndex IS NOT NULL "
        'ORDER BY e.lineIndex, e.level',
        [bookId],
      ))
        (lineIndex: row['lineIndex'] as int, label: row['text'] as String),
    ];
    return (markers: markers, headings: headings);
  }

  static bool _isDescendant(
    int id,
    int ancestorId,
    Map<int, ({int id, int? parentId, int level, int? lineIndex, String text})>
    byId,
  ) {
    var current = byId[id]?.parentId;
    while (current != null) {
      if (current == ancestorId) return true;
      current = byId[current]?.parentId;
    }
    return false;
  }
}
