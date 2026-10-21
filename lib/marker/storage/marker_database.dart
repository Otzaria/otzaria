import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/models/marker_query.dart';
import 'package:otzaria/marker/storage/marker_search_text.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';

/// מסד המרקר: שורה לכל סימון ותגיות בטבלה נפרדת. ⚠️ אין `await` בטרנזקציה:
/// החלונות חולקים thread אחד, ונעילה שנתפסה לפני `await` חוסמת את כולם.
class MarkerDatabase {
  static const int schemaVersion = 2;
  static const String textRangeAnchorType = 'text-range-v1';
  static const String pdfRangeAnchorType = 'pdf-text-range-v1';
  static const String _tagSeparator = '\u001F';

  MarkerDatabase._();

  /// [path] — כשהמסד הוא קובץ, קריאות ארוכות רצות ב-isolate מולו.
  @visibleForTesting
  MarkerDatabase.withDatabase(Database db, {String? path})
    : _database = _prepare(db),
      _path = path == null ? null : Future.value(path);

  static final MarkerDatabase instance = MarkerDatabase._();

  Database? _database;
  Future<Database>? _opening;

  /// גדל בכל סגירה, כדי שפתיחה שהתחילה לפניה לא תשאיר חיבור יתום.
  int _epoch = 0;

  /// הנתיב נפתר פעם אחת: הפתרון כותב קובץ בדיקה בתיקייה בכל קריאה.
  Future<String>? _path;

  Future<String> get _resolvedPath =>
      _path ??= AppPaths.resolveNotesDbPath('marker.db');

  /// מסד שנכתב בגרסה חדשה יותר של התוכנה: קוראים, אבל לא כותבים.
  bool get _newerSchema {
    final db = _database;
    return db != null &&
        (firstIntValue(db.select('PRAGMA user_version')) ?? 0) > schemaVersion;
  }

  Future<Database> get database async {
    final open = _database;
    if (open != null) return open;
    await _waitForMove();
    return _database ??
        await (_opening ??= _open().whenComplete(() => _opening = null));
  }

  /// העברת הספרייה. המסד נסגר אחרי שהכתיבות שברקע הסתיימו; כתיבה חדשה
  /// נכשלת מיד — אחרת סימון היה נשמר בקובץ הישן שעומד להימחק — וקריאה
  /// ממתינה לסיום.
  String? _moveRequestId;
  Completer<void>? _moveReleased;

  /// קריאה אינה ממתינה לנצח אם החלון שהעביר נסגר באמצע: אחרי זמן זה היא
  /// נפתחת שוב (קריאה אינה מאבדת דבר), והכתיבה עדיין חסומה.
  static const Duration _moveWaitLimit = Duration(seconds: 30);

  /// כתיבות ב-isolate שעדיין רצות.
  final Set<Future<Object?>> _pendingWrites = {};

  Future<void> lockForStorageMove(String requestId) async {
    _moveRequestId = requestId;
    _moveReleased ??= Completer<void>();
    // ייבוא ארוך שכבר רץ מסיים (או נכשל) לפני שהקובץ מועתק.
    while (_pendingWrites.isNotEmpty) {
      await Future.wait(_pendingWrites.toList(), eagerError: false).catchError(
        (Object _) => const <Object?>[],
      );
    }
    close();
  }

  void releaseStorageMove(String requestId) {
    if (_moveRequestId != requestId) return;
    _moveRequestId = null;
    // חיבור שנפתח בזמן הנעילה מצביע על המיקום הישן.
    close();
    final released = _moveReleased;
    _moveReleased = null;
    if (released != null && !released.isCompleted) released.complete();
  }

  Future<void> _waitForMove() async {
    final moving = _moveReleased;
    if (moving == null) return;
    await moving.future.timeout(_moveWaitLimit, onTimeout: () {});
  }

  void _checkNotMoving() {
    if (_moveRequestId != null) throw const MarkerStorageMovingException();
  }

  /// המסד, רק אם כבר נפתח.
  Database? get openDatabase => _database;

  /// המסד אם הקובץ קיים, בלי ליצור אותו: מי שעוד לא סימן דבר אינו מקבל
  /// קובץ חדש וחיבור פתוח רק מפתיחת ספר.
  Future<Database?> get existingDatabase async {
    await _waitForMove();
    final open = _database ?? await _opening;
    if (open != null) return open;
    if (await _existingPath() == null) return null;
    return database;
  }

  Future<String?> _existingPath() async {
    final path = await _resolvedPath;
    return await File(path).exists() ? path : null;
  }

  Future<Database> _open() async {
    while (true) {
      final epoch = _epoch;
      final path = await _resolvedPath;
      // נסגר בזמן ההמתנה, אולי בגלל העברת התיקייה: פותחים בנתיב החדש.
      if (epoch != _epoch) {
        await _waitForMove();
        continue;
      }
      final raw = openWritableDatabase(path, 'MarkerDatabase');
      try {
        return _database = _prepare(raw);
      } catch (_) {
        raw.close();
        rethrow;
      }
    }
  }

  /// קריאה ארוכה ב-isolate עם חיבור משלה, כדי לא לעכב את ה-thread שכל
  /// החלונות חולקים. [body] חייבת להיות פונקציה סטטית; null כשאין מסד.
  Future<R?> readInBackground<A, R>(
    R Function(MarkerDatabase reader, Database db, A arg) body,
    A arg,
  ) async {
    final open = await existingDatabase;
    if (open == null) return null;
    if (_path == null) return body(this, open, arg);
    // החיבור הראשי כבר עדכן את הסכמה, וה-isolate קורא מסד מעודכן.
    return _readIn(await _resolvedPath, body, arg);
  }

  static Future<R> _readIn<A, R>(
    String path,
    R Function(MarkerDatabase reader, Database db, A arg) body,
    A arg,
  ) => Isolate.run(() {
    final db = sqlite3.open(path, mode: OpenMode.readWrite);
    try {
      db.execute('PRAGMA busy_timeout=5000');
      db.execute('BEGIN');
      try {
        return body(MarkerDatabase._(), db, arg);
      } finally {
        db.execute('COMMIT');
      }
    } finally {
      db.close();
    }
  });

  /// כתיבה ארוכה (ייבוא, שחזור) בטרנזקציה אחת ב-isolate עם חיבור משלה,
  /// כדי שהחלונות לא ייתקעו. [body] חייבת להיות פונקציה סטטית.
  Future<R> writeInBackground<A, R>(
    R Function(MarkerDatabase writer, Database db, A arg) body,
    A arg,
  ) async {
    _checkNotMoving();
    final db = await database;
    _checkNotMoving();
    if (_newerSchema) throw const MarkerNewerSchemaException();
    if (_path == null) return _immediate(db, () => body(this, db, arg));
    final write = _writeIn(await _resolvedPath, body, arg);
    _pendingWrites.add(write);
    try {
      return await write;
    } finally {
      _pendingWrites.remove(write);
    }
  }

  static Future<R> _writeIn<A, R>(
    String path,
    R Function(MarkerDatabase writer, Database db, A arg) body,
    A arg,
  ) => Isolate.run(() {
    final writer = sqlite3.open(path, mode: OpenMode.readWrite);
    try {
      writer.execute('PRAGMA busy_timeout=5000');
      return _immediate(writer, () => body(MarkerDatabase._(), writer, arg));
    } finally {
      writer.close();
    }
  });

  static Database _prepare(Database db) {
    final version = firstIntValue(db.select('PRAGMA user_version')) ?? 0;
    if (version > schemaVersion) {
      // מסד מגרסה חדשה יותר: לא נוגעים בסכמה, כדי לא להרוס נתונים.
      debugPrint('MarkerDatabase: schema $version is newer than supported');
      return db;
    }
    // גרסה תקינה עם טבלה חסרה (מסד חלקי) מושלמת; הבדיקה היא קריאה בלבד.
    if (version < 1 || !_hasAllTables(db)) {
      _immediate(db, () {
        db.execute('''
          CREATE TABLE IF NOT EXISTS marker_highlights (
            id TEXT PRIMARY KEY,
            book_title TEXT NOT NULL,
            book_uid TEXT,
            section_start INTEGER NOT NULL,
            section_end INTEGER NOT NULL,
            anchor_type TEXT NOT NULL,
            segments_json TEXT NOT NULL,
            text TEXT NOT NULL,
            ref TEXT,
            color_id TEXT NOT NULL,
            color_hex TEXT NOT NULL,
            note_content TEXT,
            note_plain TEXT NOT NULL DEFAULT '',
            note_format TEXT,
            favorite INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL,
            search_text TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            version INTEGER NOT NULL DEFAULT 1
          )
        ''');
        db.execute('''
          CREATE TABLE IF NOT EXISTS marker_highlight_tags (
            highlight_id TEXT NOT NULL,
            tag TEXT NOT NULL,
            tag_key TEXT NOT NULL,
            position INTEGER NOT NULL,
            PRIMARY KEY (highlight_id, tag_key)
          )
        ''');
        db.execute(
          'CREATE INDEX IF NOT EXISTS idx_marker_book '
          'ON marker_highlights(book_title, section_start)',
        );
        _createIndexesV2(db);
        db.execute(
          'CREATE INDEX IF NOT EXISTS idx_marker_tag_key '
          'ON marker_highlight_tags(tag_key)',
        );
        // כל הדגשה של התוסף הישן שיובאה, גם אם נמחקה מאז: העותק שהתוסף עדיין
        // מצייר שייך עכשיו למרקר ואינו מוצג.
        db.execute('''
          CREATE TABLE IF NOT EXISTS marker_imported_legacy (
            legacy_id TEXT PRIMARY KEY,
            book_title TEXT NOT NULL
          )
        ''');
        db.execute(
          'CREATE INDEX IF NOT EXISTS idx_marker_legacy_book '
          'ON marker_imported_legacy(book_title)',
        );
        if (version < 1) db.execute('PRAGMA user_version = $schemaVersion');
      });
    }
    if (version == 1) {
      // 1 → 2: אינדקס ה-uid כולל את הפסקה, לחיפוש סימון קיים באותו מקום,
      // ואינדקס התאריך כולל את המזהה שהמיון נעזר בו. החיפוש מאחד עכשיו
      // את צורות השם וסימני פיסוק טיפוגרפיים.
      _immediate(db, () {
        // חלון אחר אולי השלים את המעבר בזמן שזה המתין לנעילה.
        if ((firstIntValue(db.select('PRAGMA user_version')) ?? 0) >= 2) {
          return;
        }
        db.execute('DROP INDEX IF EXISTS idx_marker_book_uid');
        db.execute('DROP INDEX IF EXISTS idx_marker_created');
        _createIndexesV2(db);
        _reindexSearch(db);
        db.execute('PRAGMA user_version = 2');
      });
    }
    return db;
  }

  static void _createIndexesV2(Database db) {
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_marker_uid_section '
      'ON marker_highlights(book_uid, section_start) WHERE book_uid IS NOT NULL',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_marker_created_id '
      'ON marker_highlights(created_at, id)',
    );
  }

  static const List<String> _tables = [
    'marker_highlights',
    'marker_highlight_tags',
    'marker_imported_legacy',
  ];

  static bool _hasAllTables(Database db) =>
      firstIntValue(
        db.select(
          "SELECT count(*) FROM sqlite_master WHERE type = 'table' "
          'AND name IN (${List.filled(_tables.length, '?').join(', ')})',
          _tables,
        ),
      ) ==
      _tables.length;

  /// `BEGIN IMMEDIATE` תופס את נעילת הכתיבה מראש, כך שקריאה בתוך הגוף רואה
  /// מצב שאף חלון אחר לא ישנה עד ה-COMMIT.
  static T _immediate<T>(Database db, T Function() body) {
    db.execute('BEGIN IMMEDIATE');
    try {
      final result = body();
      db.execute('COMMIT');
      return result;
    } catch (_) {
      try {
        db.execute('ROLLBACK');
      } catch (_) {
        // הכשל המקורי הוא שמעניין.
      }
      rethrow;
    }
  }

  /// מריץ [body] בטרנזקציה אחת. [body] חייב להיות סינכרוני.
  /// כתיבה שאפשר לוותר עליה (עיגון מחדש שיחושב שוב בציור הבא): כשהמסד
  /// נעול בכתיבה ארוכה בחלון אחר, מוותרים מיד במקום לעצור את כל החלונות.
  /// false — לא נכתב.
  Future<bool> tryTransaction(void Function(Database db) body) async {
    _checkNotMoving();
    final db = await database;
    _checkNotMoving();
    if (_newerSchema) throw const MarkerNewerSchemaException();
    db.execute('PRAGMA busy_timeout=0');
    try {
      _immediate(db, () => body(db));
      return true;
    } on SqliteException catch (error) {
      if (error.resultCode == 5) return false; // SQLITE_BUSY
      rethrow;
    } finally {
      db.execute('PRAGMA busy_timeout=5000');
    }
  }

  Future<T> transaction<T>(T Function(Database db) body) async {
    _checkNotMoving();
    final db = await database;
    _checkNotMoving();
    if (_newerSchema) throw const MarkerNewerSchemaException();
    return _immediate(db, () => body(db));
  }

  void close() {
    _epoch++;
    _path = null;
    final db = _database;
    if (db == null) return;
    _database = null;
    closeWithCheckpoint(db);
  }

  // ===== קריאה =====

  static const _columns =
      'id, book_title, book_uid, segments_json, text, ref, color_id, '
      'color_hex, note_content, note_plain, note_format, favorite, anchor_type, '
      'created_at, updated_at, version, '
      "(SELECT group_concat(tag, '$_tagSeparator') FROM "
      '(SELECT tag FROM marker_highlight_tags t '
      'WHERE t.highlight_id = h.id ORDER BY position)) AS tags';

  /// סימוני הספר, לפי uid או לפי הכותרת (סימון בלי uid). [span] מצמצם
  /// לסימונים שמתחילים ונגמרים בדיוק בפסקאות האלה; סימון של ספר אחר באותה
  /// כותרת מסונן על ידי הקורא.
  List<MarkerHighlight> loadBook(
    Database db, {
    required String bookTitle,
    String? bookUid,
    ({int first, int last})? span,
    bool pdf = false,
  }) {
    final at = span == null ? '' : ' AND section_start = ?';
    final book = bookUid == null
        ? 'book_title = ?$at'
        : '((book_title = ?$at) OR (book_uid = ?$at))';
    return _decodeRows(
      db.select(
        'SELECT $_columns FROM marker_highlights h '
        'WHERE $book AND anchor_type = ?'
        '${span == null ? '' : ' AND section_end = ?'} '
        'ORDER BY section_start, created_at',
        [
          bookTitle,
          ?span?.first,
          if (bookUid != null) ...[bookUid, ?span?.first],
          pdf ? pdfRangeAnchorType : textRangeAnchorType,
          ?span?.last,
        ],
      ),
    );
  }

  /// כמה סימונים יש לספר — זול, מהאינדקס.
  int countBook(
    Database db, {
    required String bookTitle,
    String? bookUid,
    bool pdf = false,
  }) =>
      firstIntValue(
        db.select(
          'SELECT count(*) FROM marker_highlights '
          'WHERE ${bookUid == null ? 'book_title = ?' : '(book_title = ? OR book_uid = ?)'} '
          'AND anchor_type = ?',
          [bookTitle, ?bookUid, pdf ? pdfRangeAnchorType : textRangeAnchorType],
        ),
      ) ??
      0;

  List<MarkerHighlight> getMany(Database db, Iterable<String> ids) {
    final list = ids.toSet().toList();
    final result = <MarkerHighlight>[];
    for (var i = 0; i < list.length; i += 500) {
      final chunk = list.sublist(i, (i + 500).clamp(0, list.length));
      final marks = List.filled(chunk.length, '?').join(',');
      result.addAll(
        _decodeRows(
          db.select(
            'SELECT $_columns FROM marker_highlights h WHERE id IN ($marks)',
            chunk,
          ),
        ),
      );
    }
    return result;
  }

  MarkerHighlight? get(Database db, String id) {
    final found = getMany(db, [id]);
    return found.isEmpty ? null : found.single;
  }

  /// עמוד של סימונים לפי [query]. [colorOrder] — סדר הצבעים בפלטה, למיון
  /// ולקיבוץ לפי צבע.
  List<MarkerHighlight> query(
    Database db,
    MarkerQuery query, {
    required int offset,
    required int limit,
    List<String> colorOrder = const [],
  }) {
    final where = _where(query);
    final colorRank = _colorRank(colorOrder);
    final orderBy = [
      switch (query.group) {
        MarkerGroup.none => null,
        // ספר הטקסט לפני ספר ה-PDF שבאותה כותרת, כמו ברשימת הספרים.
        MarkerGroup.book =>
          "book_title, anchor_type = '$pdfRangeAnchorType', section_start",
        MarkerGroup.color => colorRank.sql,
        MarkerGroup.date => null,
      },
      switch (query.sort) {
        MarkerSort.newest => 'created_at DESC, id DESC',
        MarkerSort.oldest => 'created_at ASC, id',
        MarkerSort.book =>
          "book_title, anchor_type = '$pdfRangeAnchorType', "
              'section_start, created_at, id',
        MarkerSort.color => '${colorRank.sql}, created_at DESC, id DESC',
        MarkerSort.favorites => 'favorite DESC, created_at DESC, id DESC',
      },
    ].whereType<String>().join(', ');
    // מיון לפי תאריך כבר מקבץ לפי יום; עמודה כפולה במיון הייתה מונעת
    // מהמסד להשתמש באינדקס (created_at, id) ומחייבת למיין את כל הטבלה.
    final byDate =
        query.sort == MarkerSort.newest || query.sort == MarkerSort.oldest;
    final dateFirst = query.group == MarkerGroup.date && !byDate
        ? 'created_at DESC, '
        : '';
    return _decodeRows(
      db.select(
        'SELECT $_columns FROM marker_highlights h ${where.sql} '
        'ORDER BY $dateFirst$orderBy LIMIT ? OFFSET ?',
        [
          ...where.args,
          if (query.group == MarkerGroup.color ||
              query.sort == MarkerSort.color)
            ...colorRank.args,
          if (query.group == MarkerGroup.color &&
              query.sort == MarkerSort.color)
            ...colorRank.args,
          limit,
          offset,
        ],
      ),
    );
  }

  /// ספירות למסנני המהירות בשלוש שאילתות: כל מסנן מצב נספר בתוך שאר
  /// המסננים (כולל הצבע), וכל צבע נספר בתוך שאר המסננים (כולל המצב).
  MarkerCounts counts(Database db, MarkerQuery query) {
    final statusScope = _where(query.copyWith(status: MarkerStatusFilter.all));
    final row = db
        .select(
          'SELECT COUNT(*) AS c, '
          'COALESCE(SUM(favorite = 1), 0) AS favorites, '
          "COALESCE(SUM(note_plain <> ''), 0) AS noted, "
          'COALESCE(SUM(EXISTS (SELECT 1 FROM marker_highlight_tags t '
          'WHERE t.highlight_id = h.id)), 0) AS tagged, '
          "COALESCE(SUM(status <> 'active'), 0) AS repair "
          'FROM marker_highlights h ${statusScope.sql}',
          statusScope.args,
        )
        .first;
    final colorScope = _where(query.copyWith(colorId: () => null));
    final byColor = <String, int>{
      for (final color in db.select(
        'SELECT color_id, COUNT(*) AS c FROM marker_highlights h '
        '${colorScope.sql} GROUP BY color_id',
        colorScope.args,
      ))
        color['color_id'] as String: color['c'] as int,
    };
    final favorites = row['favorites'] as int;
    final noted = row['noted'] as int;
    final tagged = row['tagged'] as int;
    final repair = row['repair'] as int;
    return MarkerCounts(
      total: countAll(db),
      matching: switch (query.status) {
        MarkerStatusFilter.all => row['c'] as int,
        MarkerStatusFilter.favorites => favorites,
        MarkerStatusFilter.noted => noted,
        MarkerStatusFilter.tagged => tagged,
        MarkerStatusFilter.needsRepair => repair,
      },
      favorites: favorites,
      noted: noted,
      tagged: tagged,
      needsRepair: repair,
      byColor: byColor,
    );
  }

  List<MarkerBookCount> books(Database db) => [
    for (final row in db.select(
      'SELECT book_title, anchor_type = ? AS pdf, COUNT(*) AS c '
      'FROM marker_highlights GROUP BY book_title, anchor_type '
      'ORDER BY book_title, pdf',
      [pdfRangeAnchorType],
    ))
      (
        title: row['book_title'] as String,
        pdf: row['pdf'] == 1,
        count: row['c'] as int,
      ),
  ];

  List<({String tag, int count})> tags(Database db) => [
    for (final row in db.select(
      'SELECT MIN(tag) AS tag, COUNT(*) AS c FROM marker_highlight_tags '
      'GROUP BY tag_key ORDER BY tag_key',
    ))
      (tag: row['tag'] as String, count: row['c'] as int),
  ];

  /// הסימונים שיש להם התגית שהמפתח המנורמל שלה [tagKey].
  List<String> idsWithTag(Database db, String tagKey) => [
    for (final row in db.select(
      'SELECT highlight_id FROM marker_highlight_tags WHERE tag_key = ?',
      [tagKey],
    ))
      row['highlight_id'] as String,
  ];

  void recordImportedLegacy(Database db, MarkerHighlight highlight) {
    recordLegacyIds(db, [
      for (final segment in highlight.segments)
        if (segment.legacyId case final id?)
          (id: id, book: highlight.bookTitle),
    ]);
  }

  void recordLegacyIds(Database db, Iterable<MarkerLegacyRef> ids) {
    for (final entry in ids) {
      db.execute(
        'INSERT OR IGNORE INTO marker_imported_legacy (legacy_id, book_title) '
        'VALUES (?, ?)',
        [entry.id, entry.book],
      );
    }
  }

  Set<String> existingIds(Database db, Iterable<String> ids) {
    final list = ids.toSet().toList();
    final result = <String>{};
    for (var i = 0; i < list.length; i += 500) {
      final chunk = list.sublist(i, (i + 500).clamp(0, list.length));
      final marks = List.filled(chunk.length, '?').join(',');
      for (final row in db.select(
        'SELECT id FROM marker_highlights WHERE id IN ($marks)',
        chunk,
      )) {
        result.add(row['id'] as String);
      }
    }
    return result;
  }

  int countAll(Database db) =>
      db.select('SELECT COUNT(*) AS c FROM marker_highlights').first['c']
          as int;

  /// כל הסימונים, לגיבוי, בסדר יצירה.
  List<MarkerHighlight> all(Database db) => _decodeRows(
    db.select(
      'SELECT $_columns FROM marker_highlights h ORDER BY created_at, id',
    ),
  );

  /// כל מזהי התוסף הישן שיובאו, גם של סימונים שנמחקו מאז.
  List<MarkerLegacyRef> allImportedLegacy(Database db) => [
    for (final row in db.select(
      'SELECT legacy_id, book_title FROM marker_imported_legacy '
      'ORDER BY book_title, legacy_id',
    ))
      (id: row['legacy_id'] as String, book: row['book_title'] as String),
  ];

  // ===== כתיבה (יש לקרוא מתוך [transaction]) =====

  void upsert(Database db, MarkerHighlight highlight) {
    db.execute(
      '''
      INSERT INTO marker_highlights (
        id, book_title, book_uid, section_start, section_end, anchor_type,
        segments_json, text, ref, color_id, color_hex, note_content,
        note_plain, note_format, favorite, status, search_text, created_at,
        updated_at, version
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        book_title = excluded.book_title,
        book_uid = excluded.book_uid,
        section_start = excluded.section_start,
        section_end = excluded.section_end,
        anchor_type = excluded.anchor_type,
        segments_json = excluded.segments_json,
        text = excluded.text,
        ref = excluded.ref,
        color_id = excluded.color_id,
        color_hex = excluded.color_hex,
        note_content = excluded.note_content,
        note_plain = excluded.note_plain,
        note_format = excluded.note_format,
        favorite = excluded.favorite,
        status = excluded.status,
        search_text = excluded.search_text,
        updated_at = excluded.updated_at,
        version = excluded.version
      ''',
      [
        highlight.id,
        highlight.bookTitle,
        highlight.bookUid,
        highlight.sectionStart,
        highlight.sectionEnd,
        highlight.pdf ? pdfRangeAnchorType : textRangeAnchorType,
        jsonEncode([for (final s in highlight.segments) s.toJson()]),
        highlight.text,
        highlight.ref,
        highlight.colorId,
        highlight.colorHex,
        highlight.note?.content,
        highlight.note?.plain ?? '',
        highlight.note?.format.name,
        highlight.favorite ? 1 : 0,
        highlight.status.wireName,
        _searchText(highlight),
        highlight.createdAt.toUtc().millisecondsSinceEpoch,
        highlight.updatedAt.toUtc().millisecondsSinceEpoch,
        highlight.version,
      ],
    );
    db.execute('DELETE FROM marker_highlight_tags WHERE highlight_id = ?', [
      highlight.id,
    ]);
    for (var i = 0; i < highlight.tags.length; i++) {
      final tag = highlight.tags[i];
      db.execute(
        'INSERT OR IGNORE INTO marker_highlight_tags '
        '(highlight_id, tag, tag_key, position) VALUES (?, ?, ?, ?)',
        [highlight.id, tag, MarkerHighlight.tagKey(tag), i],
      );
    }
  }

  /// עדכון העוגנים בלבד, בלי לגעת ב-[MarkerHighlight.version] — עיגון מחדש
  /// אינו עריכה של המשתמש.
  void updateSegments(
    Database db,
    String id,
    List<MarkerSegment> segments,
    MarkerAnchorStatus status, {
    int? version,
  }) {
    db.execute(
      'UPDATE marker_highlights SET segments_json = ?, status = ? '
      'WHERE id = ?${version == null ? '' : ' AND version = ?'}',
      [
        jsonEncode([for (final s in segments) s.toJson()]),
        status.wireName,
        id,
        ?version,
      ],
    );
  }

  int delete(Database db, Iterable<String> ids) {
    var deleted = 0;
    for (final id in ids.toSet()) {
      db.execute('DELETE FROM marker_highlight_tags WHERE highlight_id = ?', [
        id,
      ]);
      db.execute('DELETE FROM marker_highlights WHERE id = ?', [id]);
      deleted += db.updatedRows;
    }
    return deleted;
  }

  // ===== פענוח =====

  List<MarkerHighlight> _decodeRows(ResultSet rows) {
    final result = <MarkerHighlight>[];
    for (final row in rows) {
      final highlight = _decode(row);
      if (highlight != null) result.add(highlight);
    }
    return result;
  }

  MarkerHighlight? _decode(Row row) {
    try {
      return _decodeRow(row);
    } on Object catch (error) {
      if (error is! FormatException && error is! TypeError) rethrow;
      // נכתב רק על ידינו; שורה פגומה היא שינוי ידני או נזק בדיסק.
      debugPrint('MarkerDatabase: skipped highlight ${row['id']}: $error');
      return null;
    }
  }

  MarkerHighlight _decodeRow(Row row) {
    final id = row['id'] as String;
    final decoded = jsonDecode(row['segments_json'] as String);
    if (decoded is! List || decoded.isEmpty) {
      throw const FormatException('no segments');
    }
    final segments = [
      for (final entry in decoded)
        MarkerSegment.fromJson(Map<String, dynamic>.from(entry as Map)),
    ];
    final noteContent = row['note_content'] as String?;
    final notePlain = row['note_plain'] as String? ?? '';
    final noteFormat = row['note_format'] as String?;
    final tags = row['tags'] as String?;
    return MarkerHighlight(
      id: id,
      bookTitle: row['book_title'] as String,
      bookUid: row['book_uid'] as String?,
      segments: segments,
      pdf: row['anchor_type'] == pdfRangeAnchorType,
      text: row['text'] as String,
      ref: row['ref'] as String?,
      colorId: row['color_id'] as String,
      colorHex: row['color_hex'] as String,
      note: noteContent == null
          ? null
          : MarkerNote(
              content: noteContent,
              plain: notePlain,
              format: noteFormat == PersonalNoteContentFormat.plain.name
                  ? PersonalNoteContentFormat.plain
                  : PersonalNoteContentFormat.quillDelta,
            ),
      tags: tags == null || tags.isEmpty ? const [] : tags.split(_tagSeparator),
      favorite: (row['favorite'] as int) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row['created_at'] as int,
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at'] as int,
        isUtc: true,
      ),
      version: row['version'] as int,
    );
  }

  static String _searchText(MarkerHighlight highlight) => _searchTextOf([
    highlight.text,
    highlight.note?.plain ?? '',
    ...highlight.tags,
    highlight.bookTitle,
    highlight.ref ?? '',
  ]);

  static String _searchTextOf(List<String> fields) =>
      normalizeMarkerSearchText(fields.join(' '));

  /// מחשב מחדש את טקסט החיפוש של כל הסימונים, אחרי שהנרמול השתנה.
  static void _reindexSearch(Database db) {
    final update = db.prepare(
      'UPDATE marker_highlights SET search_text = ? WHERE id = ?',
    );
    try {
      for (final row in db.select(
        'SELECT id, text, note_plain, book_title, ref, '
        "(SELECT group_concat(tag, ' ') FROM marker_highlight_tags t "
        'WHERE t.highlight_id = h.id) AS tags FROM marker_highlights h',
      )) {
        update.execute([
          _searchTextOf([
            row['text'] as String,
            row['note_plain'] as String,
            row['tags'] as String? ?? '',
            row['book_title'] as String,
            row['ref'] as String? ?? '',
          ]),
          row['id'],
        ]);
      }
    } finally {
      update.close();
    }
  }

  static ({String sql, List<Object?> args}) _where(MarkerQuery query) {
    final clauses = <String>[];
    final args = <Object?>[];
    for (final pattern in markerSearchPatterns(query.search)) {
      clauses.add(r"search_text LIKE ? ESCAPE '\'");
      args.add(pattern);
    }
    if (query.bookTitle != null) {
      clauses.add('book_title = ? AND anchor_type = ?');
      args.addAll([
        query.bookTitle,
        query.bookPdf ? pdfRangeAnchorType : textRangeAnchorType,
      ]);
    }
    if (query.colorId != null) {
      clauses.add('color_id = ?');
      args.add(query.colorId);
    }
    if (query.tag != null) {
      clauses.add(
        'EXISTS (SELECT 1 FROM marker_highlight_tags t '
        'WHERE t.highlight_id = h.id AND t.tag_key = ?)',
      );
      args.add(MarkerHighlight.tagKey(query.tag!));
    }
    switch (query.status) {
      case MarkerStatusFilter.all:
        break;
      case MarkerStatusFilter.favorites:
        clauses.add('favorite = 1');
      case MarkerStatusFilter.noted:
        clauses.add("note_plain <> ''");
      case MarkerStatusFilter.tagged:
        clauses.add(
          'EXISTS (SELECT 1 FROM marker_highlight_tags t '
          'WHERE t.highlight_id = h.id)',
        );
      case MarkerStatusFilter.needsRepair:
        clauses.add("status <> 'active'");
    }
    return (
      sql: clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}',
      args: args,
    );
  }

  static ({String sql, List<Object?> args}) _colorRank(List<String> order) {
    if (order.isEmpty) return (sql: 'color_id', args: const []);
    final cases = List.filled(order.length, 'WHEN ? THEN ?');
    return (
      sql: 'CASE color_id ${cases.join(' ')} ELSE ${order.length} END',
      args: [
        for (var i = 0; i < order.length; i++) ...[order[i], i],
      ],
    );
  }
}

/// המסד נכתב בגרסה חדשה יותר של התוכנה, וכתיבה אליו עלולה להרוס נתונים.
class MarkerNewerSchemaException implements Exception {
  const MarkerNewerSchemaException();
}

/// הספרייה עוברת מקום בחלון אחר, ובינתיים אין כתיבה.
class MarkerStorageMovingException implements Exception {
  const MarkerStorageMovingException();
}
