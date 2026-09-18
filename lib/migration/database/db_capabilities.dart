import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/migration/database/sqlite3_utils.dart';

/// הטבלאות המוכרות של מסד בפורמט seforim.db. רק אלה נבדקות ונקראות;
/// טבלה אחרת במסד (למשל של תוסף) אינה נחשבת יכולת.
const Set<String> kKnownSeforimTables = {
  'category',
  'category_closure',
  'book',
  'source',
  'author',
  'book_author',
  'topic',
  'book_topic',
  'pub_place',
  'book_pub_place',
  'pub_date',
  'book_pub_date',
  'generation',
  'book_generation',
  'book_base_text',
  'line',
  'line_ref',
  'line_dh',
  'tocText',
  'tocEntry',
  'line_toc',
  'connection_type',
  'link',
  'link_anchor',
  'link_range',
  'link_coverage',
  'link_suppressed_side',
  'book_has_links',
  'book_acronym',
  'alt_toc_structure',
  'alt_toc_entry',
  'line_alt_toc',
  'default_commentator',
  'default_targum',
  'book_version',
  'version_line',
  'schema_meta',
  'db_meta',
};

/// מפת היכולות של מסד בפורמט seforim.db: אילו מהטבלאות המוכרות קיימות,
/// ובאילו עמודות. אף טבלה אינה חובה — תכונה שטבלתה חסרה מחזירה ריק.
///
/// ערכים פשוטים בלבד, כך שניתן להעביר את המופע ל-isolate.
class DbCapabilities {
  const DbCapabilities._(this._tables, this._columns, this._indexes);

  /// מסד ריק — אין אף טבלה.
  static const DbCapabilities none = DbCapabilities._({}, {}, {});

  final Set<String> _tables;
  final Map<String, Set<String>> _columns;
  final Set<String> _indexes;

  static final Map<String, (int, DbCapabilities)> _byPath = {};

  /// האם הטבלה [table] קיימת כטבלה אמיתית (לא VIEW ולא טבלה וירטואלית).
  bool has(String table) => _tables.contains(table.toLowerCase());

  /// האם לטבלה [table] יש עמודה [column].
  bool hasColumn(String table, String column) =>
      _columns[table.toLowerCase()]?.contains(column.toLowerCase()) ?? false;

  /// האם האינדקס [index] קיים.
  bool hasIndex(String index) => _indexes.contains(index.toLowerCase());

  /// ביטוי SELECT לעמודה: שמה כשהיא קיימת, אחרת [fallback] בשם זהה.
  String column(
    String table,
    String column, {
    String fallback = 'NULL',
    String? qualifier,
  }) {
    if (hasColumn(table, column)) {
      return qualifier == null ? column : '$qualifier.$column AS $column';
    }
    return '$fallback AS $column';
  }

  /// מתאים שאילתת ספרים קבועה למסד: בלי טבלאות מחברים מסיר את צירוף המחבר
  /// (`ba`/`a`), ובלי `book.orderIndex` מציב NULL במקומו.
  String adaptBookQuery(String query) {
    var adapted = query;
    if (!hasAuthors) {
      adapted = adapted
          .replaceAll(_authorJoinPattern, '')
          .replaceAll('a.name', 'NULL');
    }
    if (!hasColumn('book', 'orderIndex')) {
      adapted = adapted.replaceAll(_bookOrderPattern, 'NULL');
    }
    return adapted;
  }

  static final _authorJoinPattern = RegExp(
    r'LEFT JOIN book_author ba ON [^\n]+\s+LEFT JOIN author a ON [^\n]+',
  );
  static final _bookOrderPattern = RegExp(r'(?<!AS )\b(\w+\.)?orderIndex\b');

  bool get hasBooks => has('book');
  bool get hasLines => hasBooks && has('line');
  bool get hasCategories => has('category');

  /// ספרים משויכים לקטגוריות. בלי טבלת קטגוריות ערכי `book.categoryId`
  /// חסרי משמעות, וכל הספרים נחשבים תחת שורש יחיד (categoryId = 0).
  bool get hasBookCategories =>
      hasCategories && hasColumn('book', 'categoryId');
  bool get hasBookHeDesc => hasColumn('book', 'heDesc');
  bool get hasToc => hasLines && has('tocEntry') && has('tocText');
  bool get hasTocEntryLineIndex => hasColumn('tocEntry', 'lineIndex');
  bool get hasLineToc => hasToc && has('line_toc');

  /// רשימת המבנים החלופיים בלבד, בלי הערכים והשורות שלהם.
  bool get hasAltTocStructures => hasBooks && has('alt_toc_structure');
  bool get hasAltToc =>
      hasLines &&
      has('alt_toc_structure') &&
      has('alt_toc_entry') &&
      has('tocText');
  bool get hasLineAltToc => hasAltToc && has('line_alt_toc');

  /// קישורים דורשים גם את סוגי החיבור ואת השורות שהם מצביעים עליהן.
  bool get hasLinks => hasLines && has('link') && has('connection_type');
  bool get hasLinkAnchors => hasLinks && has('link_anchor');

  /// שתי טבלאות הטווח נשלחות יחד; אחת בלי השנייה אינה שמישה.
  bool get hasLinkRanges =>
      hasLinks && has('link_range') && has('link_coverage');
  bool get hasLinkSuppressedSide => hasLinks && has('link_suppressed_side');
  bool get hasLinkBaseProvenance => hasColumn('link', 'baseProvenance');

  /// מהדורות: book_version בלי version_line (או להפך) אינה שמישה.
  bool get hasBookVersions =>
      hasBooks && has('book_version') && has('version_line');
  bool get hasLineRef => hasLines && has('line_ref');
  bool get hasLineDhDisplay => hasBooks && hasColumn('line_dh', 'dhDisplay');
  bool get hasLineBookIndex => hasIndex('idx_line_book_index');
  bool get hasAuthors => hasBooks && has('author') && has('book_author');
  bool get hasTopics => hasBooks && has('topic') && has('book_topic');
  bool get hasPubPlaces =>
      hasBooks && has('pub_place') && has('book_pub_place');
  bool get hasPubDates => hasBooks && has('pub_date') && has('book_pub_date');
  bool get hasGenerations =>
      hasBooks && has('generation') && has('book_generation');
  bool get hasAcronyms => hasBooks && has('book_acronym');
  bool get hasDefaultCommentators => hasBooks && has('default_commentator');
  bool get hasDefaultTargums => hasBooks && has('default_targum');
  bool get hasCategoryClosure => hasCategories && has('category_closure');

  /// בודק את [db] מחדש: שתי שאילתות סכמה, בלי קריאת נתונים.
  static DbCapabilities probe(sqlite3.Database db) {
    final known = {for (final t in kKnownSeforimTables) t.toLowerCase()};
    final tables = <String>{};
    final indexes = <String>{};
    final rows = db.select(
      "SELECT type, name, sql FROM sqlite_master WHERE type IN ('table', 'index')",
    );
    for (final row in rows) {
      final name = (row['name'] as String?)?.toLowerCase();
      if (name == null) continue;
      if (row['type'] == 'index') {
        indexes.add(name);
        continue;
      }
      final sql = (row['sql'] as String?)?.trimLeft().toUpperCase() ?? '';
      // טבלה וירטואלית תלויה במודול חיצוני, ואינה נחשבת טבלה מוכרת.
      if (sql.startsWith('CREATE VIRTUAL')) continue;
      if (known.contains(name)) tables.add(name);
    }

    final columns = <String, Set<String>>{};
    if (tables.isNotEmpty) {
      final query = tables
          .map((t) => "SELECT '$t' AS t, name FROM pragma_table_info('$t')")
          .join(' UNION ALL ');
      for (final row in db.select(query)) {
        final name = row['name'] as String?;
        if (name == null) continue;
        columns
            .putIfAbsent(row['t'] as String, () => <String>{})
            .add(name.toLowerCase());
      }
    }
    return DbCapabilities._(tables, columns, indexes);
  }

  /// היכולות של המסד ב-[path]; [db] הוא חיבור פתוח לאותו קובץ.
  /// schema_version עולה בכל DDL מכל חיבור, כך שטבלה שנוצרה אחרי הפתיחה נקלטת.
  static DbCapabilities forDatabase(String path, sqlite3.Database db) {
    final schemaVersion =
        firstIntValue(db.select('PRAGMA schema_version')) ?? -1;
    final cached = _byPath[path];
    if (cached != null && cached.$1 == schemaVersion) return cached.$2;
    final capabilities = probe(db);
    _byPath[path] = (schemaVersion, capabilities);
    return capabilities;
  }

  /// מוחק את המטמון של [path] — חובה כשהקובץ נסגר או מוחלף.
  static void invalidate(String path) => _byPath.remove(path);
}
