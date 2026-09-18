import 'dart:io';

import 'package:otzaria/external_catalog/responsa/native/responsa_hebrew.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_tree_reader.dart';
import 'package:sqlite3/sqlite3.dart';

/// גרסת הסכמה של `responsa_catalog.db`.
const int responsaCatalogSchemaVersion = 1;

/// ספר אחד כפי שהסיווג מזהה אותו.
class ResponsaBookRow {
  final String title;
  final String refPath;
  final String? category;
  final int treeParam;
  final int level;

  const ResponsaBookRow({
    required this.title,
    required this.refPath,
    required this.category,
    required this.treeParam,
    required this.level,
  });

  List<String> get ancestors {
    final parts = refPath.split(ResponsaTreeReader.pathSeparator);
    return parts.sublist(0, parts.length - 1);
  }

  String get parentPath => ancestors.join(ResponsaTreeReader.pathSeparator);
}

class ResponsaCatalogBuildResult {
  final int books;
  final int scannedNodes;
  final Duration elapsed;
  final Map<String, int> idMatching;

  const ResponsaCatalogBuildResult({
    required this.books,
    required this.scannedNodes,
    required this.elapsed,
    required this.idMatching,
  });
}

class ResponsaCatalogBuildException implements Exception {
  final String message;
  const ResponsaCatalogBuildException(this.message);

  @override
  String toString() => message;
}

/// בניית קטלוג פרויקט השו"ת מתוך עץ הקטלוג של התוכנה.
///
/// שלושה דברים שהבנייה **לא** עושה, וכל אחד מהם מכוון:
///
/// * אינה שומרת את ההיררכיה המלאה. 1.25M צמתים הם כ-475MB, והם נדרשים
///   רק כדי לזהות את הספרים; הפתיחה נעשית לפי הפניה טקסטואלית.
/// * אינה יוצרת FTS5. הטבלה היא כ-8.5K שורות — קטנה מקטלוג היברובוקס
///   שאוצריא כבר טוענת לזיכרון.
/// * אינה גוזרת מזהה מ-hash של הנתיב. נמדד ש-81% בלבד מהנתיבים שורדים
///   מעבר בין מהדורות, ולכן המזהה מקומי ומתמשך, והתאמה רב-שלבית
///   משמרת אותו בבנייה מחדש.
class ResponsaCatalogBuilder {
  ResponsaCatalogBuilder._();

  /// מקטע = יחידת תוכן בתוך ספר. שני סימנים בלתי-תלויים: מישור ה-param
  /// ושם היחידה. די באחד מהם — נצפו מקטעים ששמם חריג ומקטעים במישור חריג.
  static const int _sectionPlaneBits = 0x1000 | 0x2000;

  static final RegExp _sectionName = RegExp(
    r'^(פרק|פסוק|דף|סימן|סעיף|הלכה|משנה|עמוד|שער|פרשה|אות|מאמר|שורש|מצוה'
    r"|הקדמ|פתיחה|תוכן|מפתח|ברייתא|נוסחא|סי'|עמ'|חלק [א-ת]'?$)",
  );

  /// מילים שפותחות כותרת של יחידה בתוך חיבור, לא של חיבור עצמאי.
  ///
  /// כותרת כזו יכולה להיות ייחודית בקטלוג ועדיין **לא** ייחודית למנתח
  /// ההפניות: `כלל יא` נפתח כ-`כלל ב סימן יא`. לכן היא מקבלת אב אחד
  /// לפחות בכפייה.
  static final RegExp _genericLead = RegExp(
    r'''^["'׳״(\[]*(כלל|נתיב|שנה|מערכת|ערך|שורש|לאוין|עשין|חלק|שער|מאמר'''
    r'|סימן|פרק|פרשת|מסכת|הלכות|דרוש|אות|תשובה|מצוה)\b',
  );

  static bool isSection(String name, int param) =>
      ((param >> 16) & _sectionPlaneBits) != 0 || _sectionName.hasMatch(name);

  /// מזהה ספרים מתוך זרם הצמתים.
  ///
  /// ספר = הצומת הגבוה ביותר שתוכנו מקטעים: יש לו ילד שהוא מקטע, והוא
  /// עצמו אינו מקטע. כלל מבני ולא היוריסטיקת-רמה, כי עומק הספר משתנה
  /// בין ענפים — `בראשית` ברמה 1 ו-`משנה > שבת` ברמה 2, ושניהם ספרים.
  static List<ResponsaBookRow> classify(Iterable<ResponsaTreeNode> nodes) {
    final books = <ResponsaBookRow>[];
    final stack = <({ResponsaTreeNode node, bool hasSectionChild})>[];

    void closeTo(int level) {
      while (stack.isNotEmpty && stack.last.node.level >= level) {
        final entry = stack.removeLast();
        final node = entry.node;
        if (node.level == 0 || !entry.hasSectionChild) continue;
        if (isSection(node.name, node.param)) continue;
        books.add(
          ResponsaBookRow(
            title: node.name,
            refPath: node.path,
            category: node.path.split(ResponsaTreeReader.pathSeparator).first,
            treeParam: node.param,
            level: node.level,
          ),
        );
      }
    }

    for (final node in nodes) {
      closeTo(node.level);
      if (stack.isNotEmpty && isSection(node.name, node.param)) {
        final last = stack.removeLast();
        stack.add((node: last.node, hasSectionChild: true));
      }
      stack.add((node: node, hasSectionChild: false));
    }
    closeTo(0);
    while (stack.isNotEmpty) {
      final entry = stack.removeLast();
      final node = entry.node;
      if (node.level == 0 || !entry.hasSectionChild) continue;
      if (isSection(node.name, node.param)) continue;
      books.add(
        ResponsaBookRow(
          title: node.name,
          refPath: node.path,
          category: node.path.split(ResponsaTreeReader.pathSeparator).first,
          treeParam: node.param,
          level: node.level,
        ),
      );
    }
    return books;
  }

  /// ההפניה הקצרה ביותר שעדיין חד-משמעית, לכל ספר.
  ///
  /// הכותרת לבדה אינה מספיקה: שם גנרי מחזיר מאות תוצאות שהראשונה בהן
  /// ספר אחר. מוסיפים אבות אחד-אחד עד לייחודיות בקטלוג. זהו **קירוב**
  /// לחד-משמעיות של מנתח ההפניות, ולכן הפתיחה בזמן אמת מאמתת את כותרת
  /// החלון שנפתח.
  static List<String> buildOpenRefs(List<ResponsaBookRow> books) {
    final openRefs = List<String>.filled(books.length, '');
    final minimumDepth = [
      for (final book in books)
        _genericLead.hasMatch(book.title.trim()) ? 1 : 0,
    ];
    var remaining = List<int>.generate(books.length, (i) => i);
    var depth = 0;

    while (remaining.isNotEmpty) {
      final candidates = <String, List<int>>{};
      for (final index in remaining) {
        final reference = _referenceAt(
          books[index],
          depth > minimumDepth[index] ? depth : minimumDepth[index],
        );
        candidates.putIfAbsent(reference, () => []).add(index);
      }
      final still = <int>[];
      for (final entry in candidates.entries) {
        if (entry.value.length == 1 &&
            depth >= minimumDepth[entry.value.single]) {
          openRefs[entry.value.single] = entry.key;
        } else {
          still.addAll(entry.value);
        }
      }
      if (still.isEmpty) break;
      final deepest = still
          .map((i) => books[i].ancestors.length)
          .reduce((a, b) => a > b ? a : b);
      if (depth > deepest) {
        // אף אב נוסף אינו מפריד — הנתיב המלא הוא הטוב ביותר שיש.
        for (final index in still) {
          openRefs[index] = _referenceAt(books[index], depth);
        }
        break;
      }
      remaining = still;
      depth++;
    }

    for (var i = 0; i < openRefs.length; i++) {
      if (openRefs[i].isEmpty) openRefs[i] = books[i].title;
    }
    return openRefs;
  }

  static String _referenceAt(ResponsaBookRow book, int depth) {
    if (depth <= 0) return book.title;
    final ancestors = book.ancestors;
    final take = depth > ancestors.length ? ancestors.length : depth;
    return [
      ...ancestors.sublist(ancestors.length - take),
      book.title,
    ].join(' ');
  }

  static String normalizedPath(String refPath) => refPath
      .split(ResponsaTreeReader.pathSeparator)
      .map(ResponsaHebrew.spellingKey)
      .join(ResponsaTreeReader.pathSeparator);

  /// משייך `external_key` לכל ספר, תוך שימור מזהים קיימים.
  ///
  /// ההתאמה רב-שלבית ולפי סדר ביטחון יורד, וכל שלב דורש חד-ערכיות
  /// **בשני הצדדים**. התאמה עמומה = ספר חדש: שיוך מזהה ישן על סמך
  /// התאמה חלשה גרוע מלהקצות חדש, כי הוא מעביר סימניות והיסטוריה
  /// לספר אחר.
  static ({List<String> keys, Map<String, int> stats}) assignExternalKeys(
    List<ResponsaBookRow> books,
    List<({String key, String refPath, int? treeParam})> existing,
  ) {
    final assigned = List<String?>.filled(books.length, null);
    final stats = {'exact': 0, 'normalized': 0, 'parentParam': 0, 'new': 0};
    final taken = <String>{};
    var unmatched = List<int>.generate(books.length, (i) => i);

    if (existing.isNotEmpty) {
      final stages =
          <
            (
              String,
              String Function(ResponsaBookRow),
              String Function(({String key, String refPath, int? treeParam})),
            )
          >[
            ('exact', (b) => b.refPath, (e) => e.refPath),
            (
              'normalized',
              (b) => normalizedPath(b.refPath),
              (e) => normalizedPath(e.refPath),
            ),
            (
              'parentParam',
              (b) => '${normalizedPath(b.parentPath)}|${b.treeParam}',
              (e) =>
                  '${normalizedPath(_parentOf(e.refPath))}|${e.treeParam ?? -1}',
            ),
          ];

      for (final (name, bookKey, existingKey) in stages) {
        final available = existing.where((e) => !taken.contains(e.key));
        final index = _uniqueIndex(available, existingKey);
        final newIndex = _uniqueIndex(unmatched, (i) => bookKey(books[i]));
        final still = <int>[];
        for (final position in unmatched) {
          final key = bookKey(books[position]);
          final match = index[key];
          if (match == null || newIndex[key] != position) {
            still.add(position);
            continue;
          }
          assigned[position] = match.key;
          taken.add(match.key);
          stats[name] = stats[name]! + 1;
        }
        unmatched = still;
      }
    }

    var next =
        1 +
        existing
            .map((e) => int.tryParse(e.key) ?? 0)
            .fold<int>(0, (a, b) => a > b ? a : b);
    for (final position in unmatched) {
      while (taken.contains('$next')) {
        next++;
      }
      assigned[position] = '$next';
      taken.add('$next');
      stats['new'] = stats['new']! + 1;
      next++;
    }

    return (keys: [for (final key in assigned) key!], stats: stats);
  }

  static String _parentOf(String refPath) {
    final parts = refPath.split(ResponsaTreeReader.pathSeparator);
    return parts
        .sublist(0, parts.length - 1)
        .join(
          ResponsaTreeReader.pathSeparator,
        );
  }

  static Map<String, T> _uniqueIndex<T>(
    Iterable<T> items,
    String Function(T) keyOf,
  ) {
    final index = <String, T>{};
    final duplicated = <String>{};
    for (final item in items) {
      final key = keyOf(item);
      if (index.containsKey(key)) {
        duplicated.add(key);
      } else {
        index[key] = item;
      }
    }
    for (final key in duplicated) {
      index.remove(key);
    }
    return index;
  }

  // ------------------------------------------------------ כתיבה אטומית

  /// בונה קטלוג חדש ומחליף את הקיים **רק אחרי** שהוא נמצא תקין.
  ///
  /// הבנייה נכתבת ל-`<target>.building`; הקטלוג הפעיל נשאר על כנו עד
  /// שהחדש עובר בדיקת שלמות, ספירה ושאילתות smoke. בנייה שנכשלה
  /// משאירה את הישן.
  static ResponsaCatalogBuildResult build({
    required List<ResponsaTreeNode> nodes,
    required ResponsaFingerprint fingerprint,
    required String targetPath,
  }) {
    final watch = Stopwatch()..start();
    final books = classify(nodes);
    if (books.isEmpty) {
      throw const ResponsaCatalogBuildException(
        'לא זוהה אף ספר — הקטלוג לא יוחלף',
      );
    }

    final openRefs = buildOpenRefs(books);
    final assignment = assignExternalKeys(books, _readExisting(targetPath));

    final buildingPath = '$targetPath.building';
    final building = File(buildingPath);
    if (building.existsSync()) building.deleteSync();
    Directory(File(targetPath).parent.path).createSync(recursive: true);

    final db = sqlite3.open(buildingPath);
    try {
      db.execute('PRAGMA journal_mode=OFF');
      db.execute('PRAGMA synchronous=OFF');
      db.execute('''
        CREATE TABLE books (
          book_pk        INTEGER PRIMARY KEY,
          external_key   TEXT    NOT NULL UNIQUE,
          title          TEXT    NOT NULL,
          norm_title     TEXT    NOT NULL,
          ref_path       TEXT    NOT NULL,
          open_ref       TEXT    NOT NULL,
          volume         TEXT,
          category       TEXT,
          topics         TEXT,
          tree_param     INTEGER,
          source_version INTEGER NOT NULL
        )
      ''');
      db.execute(
        'CREATE TABLE db_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );

      final insert = db.prepare(
        'INSERT INTO books(external_key, title, norm_title, ref_path, open_ref,'
        ' volume, category, topics, tree_param, source_version)'
        ' VALUES(?,?,?,?,?,?,?,?,?,?)',
      );
      db.execute('BEGIN');
      for (var i = 0; i < books.length; i++) {
        final book = books[i];
        insert.execute([
          assignment.keys[i],
          book.title,
          ResponsaHebrew.normalize(book.title),
          book.refPath,
          openRefs[i],
          // volume ו-topics נשארים ריקים: אין להם מקור בהתקנה, ואין
          // להמציא ערכים.
          null,
          book.category,
          null,
          book.treeParam,
          fingerprint.version ?? 0,
        ]);
      }
      db.execute('COMMIT');
      insert.close();

      db.execute(
        'CREATE INDEX idx_books_norm_title ON books(norm_title)',
      );
      db.execute('CREATE INDEX idx_books_ref_path ON books(ref_path)');
      db.execute('CREATE INDEX idx_books_category ON books(category)');

      final meta = {
        ...fingerprint.toMeta(),
        'catalog_schema_version': '$responsaCatalogSchemaVersion',
        'catalog_build_time': DateTime.now().toIso8601String(),
        'catalog_node_count': '${nodes.length}',
      };
      final metaInsert = db.prepare(
        'INSERT OR REPLACE INTO db_meta(key, value) VALUES(?, ?)',
      );
      for (final entry in meta.entries) {
        metaInsert.execute([entry.key, entry.value]);
      }
      metaInsert.close();

      _validate(db, books.length);
    } finally {
      db.close();
    }

    _swap(buildingPath, targetPath);
    return ResponsaCatalogBuildResult(
      books: books.length,
      scannedNodes: nodes.length,
      elapsed: watch.elapsed,
      idMatching: assignment.stats,
    );
  }

  static List<({String key, String refPath, int? treeParam})> _readExisting(
    String targetPath,
  ) {
    if (!File(targetPath).existsSync()) return const [];
    try {
      final db = sqlite3.open(targetPath, mode: OpenMode.readOnly);
      try {
        return [
          for (final row in db.select(
            'SELECT external_key, ref_path, tree_param FROM books',
          ))
            (
              key: row['external_key'].toString(),
              refPath: row['ref_path'].toString(),
              treeParam: row['tree_param'] as int?,
            ),
        ];
      } finally {
        db.close();
      }
    } catch (_) {
      return const [];
    }
  }

  static void _validate(Database db, int expected) {
    final integrity = db.select('PRAGMA integrity_check').first.values.first;
    if (integrity != 'ok') {
      throw ResponsaCatalogBuildException('בדיקת שלמות נכשלה: $integrity');
    }

    final count =
        (db.select('SELECT count(*) AS n FROM books').first['n'] as num)
            .toInt();
    if (count != expected) {
      throw ResponsaCatalogBuildException(
        'נכתבו $count ספרים במקום $expected',
      );
    }

    final distinct =
        (db
                    .select(
                      'SELECT count(DISTINCT external_key) AS n FROM books',
                    )
                    .first['n']
                as num)
            .toInt();
    if (distinct != count) {
      throw const ResponsaCatalogBuildException('קיימים external_key כפולים');
    }

    final empty =
        (db
                    .select(
                      "SELECT count(*) AS n FROM books"
                      " WHERE title = '' OR open_ref = ''",
                    )
                    .first['n']
                as num)
            .toInt();
    if (empty > 0) {
      throw ResponsaCatalogBuildException(
        '$empty ספרים ללא כותרת או ללא הפניית פתיחה',
      );
    }
  }

  static void _swap(String buildingPath, String targetPath) {
    final target = File(targetPath);
    final backup = File('$targetPath.previous');
    if (target.existsSync()) {
      if (backup.existsSync()) backup.deleteSync();
      target.renameSync(backup.path);
    }
    File(buildingPath).renameSync(targetPath);
    if (backup.existsSync()) backup.deleteSync();
  }
}
