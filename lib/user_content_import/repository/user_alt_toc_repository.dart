import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/models/alt_toc_entry.dart';
import 'package:otzaria/migration/models/alt_toc_structure.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/utils/inline_section_markers.dart'
    show parashaHeadingLabel;

typedef UserAltTocRow = ({
  int id,
  int? parentId,
  int level,
  int? lineIndex,
  String text,
});

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
          key: row['key'] == 'פרשות' ? 'Parasha' : row['key'] as String,
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
  Future<List<UserAltTocRow>> entriesWithLineIndex(int structureId) async {
    final db = await _db.database;
    return db
        .select(
          'SELECT id, parentId, level, lineIndex, text FROM user_alt_toc_entry '
          'WHERE structureId = ? ORDER BY id',
          [structureId],
        )
        .map(_entryRow)
        .toList();
  }

  /// ערכי כל המבנים החלופיים של הספר לפי סדר הייבוא.
  Future<List<UserAltTocRow>> entriesForBook(int bookId) async {
    final db = await _db.database;
    return db
        .select(
          'SELECT e.id, e.parentId, e.level, e.lineIndex, e.text '
          'FROM user_alt_toc_entry e '
          'JOIN user_alt_toc_structure s ON s.id = e.structureId '
          'WHERE s.bookId = ? ORDER BY e.id',
          [bookId],
        )
        .map(_entryRow)
        .toList();
  }

  static UserAltTocRow _entryRow(sqlite3.Row row) => (
    id: row['id'] as int,
    parentId: row['parentId'] as int?,
    level: row['level'] as int,
    lineIndex: row['lineIndex'] as int?,
    text: row['text'] as String,
  );

  /// לכותרת-אב ללא שורה, מחזיר את שורת הצאצא הראשון לפי סדר הייבוא.
  static Map<int, int> navigationLines(List<UserAltTocRow> rows) {
    final lines = <int, int>{};
    // הייבוא שומר כל אב לפני ילדיו. מעבר מהסוף משאיר לצדם את הצאצא הראשון.
    for (final row in rows.reversed) {
      final line = row.lineIndex ?? lines[row.id];
      if (line == null) continue;
      lines[row.id] = line;
      final parent = row.parentId;
      if (parent != null) lines[parent] = line;
    }
    return lines;
  }

  /// הקישור לשורת הכותרת. לכותרת-אב בלי שורה — שורת הצאצא הראשון שיש לו.
  Future<List<Link>> linksForEntry(int structureId, int entryId) async {
    final all = await entriesWithLineIndex(structureId);
    final entry = all.where((row) => row.id == entryId).firstOrNull;
    if (entry == null) return const [];
    final lineIndex = entry.lineIndex ?? navigationLines(all)[entryId];
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

  /// סימני החלוקה (עלי סימנים/סעיפים) והכותרות המוזרקות של הספר: כותרות
  /// הנושא כמות שהן, וכותרות הפרשה בצורת "פרשת…".
  Future<
    ({Map<int, String> markers, List<({int lineIndex, String label})> headings})
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
    final rows = db.select(
      'SELECT s.key, e.id, e.parentId, e.level, e.lineIndex, e.text '
      'FROM user_alt_toc_structure s '
      'JOIN user_alt_toc_entry e ON e.structureId = s.id '
      "WHERE s.bookId = ? AND ((s.key = 'Topic' AND e.lineIndex IS NOT NULL) "
      "OR s.key IN ('Parasha', 'פרשות')) ORDER BY e.id",
      [bookId],
    );
    final lines = navigationLines(rows.map(_entryRow).toList());
    final ordered = <({int lineIndex, int level, String label})>[];
    for (final row in rows) {
      final isTopic = row['key'] == 'Topic';
      if (!isTopic && row['parentId'] != null) continue;
      final lineIndex = lines[row['id']];
      if (lineIndex == null) continue;
      final text = row['text'] as String;
      final label = isTopic ? text : parashaHeadingLabel(text);
      if (label != null) {
        ordered.add((
          lineIndex: lineIndex,
          level: row['level'] as int,
          label: label,
        ));
      }
    }
    ordered.sort((a, b) {
      final byLine = a.lineIndex.compareTo(b.lineIndex);
      return byLine != 0 ? byLine : a.level.compareTo(b.level);
    });
    return (
      markers: markers,
      headings: [
        for (final row in ordered) (lineIndex: row.lineIndex, label: row.label),
      ],
    );
  }
}
