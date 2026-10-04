import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/migration/database/db_capabilities.dart';
import 'package:otzaria/migration/database/line_content_codec.dart';
import 'package:otzaria/migration/models/book.dart' as db_models;
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/database/untrusted_database.dart';

// הזהות נבדקת באותה שאילתה: patch בין הפתרון לקריאה עלול להחליף את הספר.
// בודקים רק title, כי במסד מצורף אין בהכרח categoryId.
const _bookMatches = 'EXISTS (SELECT 1 FROM book WHERE id = ?1 AND title = ?2)';
// סכמה 6 (DbCapabilities.hasSplitLineContent): התוכן ב-line_content לפי אותו id.
String _contentSql(sqlite3.Database db, {required bool blob}) {
  final split = DbCapabilities.probe(db).hasSplitLineContent;
  final column = split ? 'lc.content' : 'l.content';
  final select = blob
      ? "CAST($column AS BLOB), typeof($column) = 'blob'"
      : column;
  return 'SELECT $select FROM line l '
      '${split ? 'LEFT JOIN line_content lc ON lc.id = l.id ' : ''}'
      'WHERE l.bookId = ?1 AND $_bookMatches ORDER BY l.lineIndex';
}

/// הספר שנפתר על ה-UI isolate; קריאה שהמזהה שלה כבר אינו שלו מחזירה null.
typedef BookTextKey = ({int id, String title});

/// בייטי הספר. [rowHasNewline]: שורה מכילה `\n`, ולכן פיצול הבייטים לשורות
/// אינו מחזיר את מספר הרשומות.
typedef BookContentBytes = ({Uint8List bytes, bool rowHasNewline});

/// נקרא כל [_rowsPerCheckpoint] שורות; זריקה ממנו קוטעת את הקריאה.
typedef ReadCheckpoint = Future<void> Function();

const _rowsPerCheckpoint = 4096;

typedef _BookRead<T> =
    Future<T?> Function(
      sqlite3.Database db,
      BookTextKey book, {
      ReadCheckpoint? checkpoint,
    });

/// קריאת תוכן ספר שלם (כל שורות `line`, מאוחות ב-`\n`) מחוץ ל-UI isolate:
/// seforim.db דרך [DbReadWorker], מסד מצורף ב-isolate חד-פעמי.
class BookTextReader {
  BookTextReader._();

  /// קריאות על החיבור הראשי — רק user_books.db, שנכתב על אותו חיבור.
  @visibleForTesting
  static int mainConnectionReads = 0;

  /// הטקסט המלא של [book], או null כשאין לו שורות.
  static Future<String?> text(
    SeforimRepository repository,
    db_models.Book book,
  ) => _load(
    repository,
    book,
    workerMethod: 'bookText',
    fromWorker: (result) => result as String?,
    read: readBookContentText,
  );

  /// כמו [text], כבייטים גולמיים (UTF-8 כפי שמאוחסן) — מסלול האינדוקס.
  static Future<BookContentBytes?> bytes(
    SeforimRepository repository,
    db_models.Book book,
  ) => _load(
    repository,
    book,
    workerMethod: 'bookTextBytes',
    fromWorker: (result) {
      final read = result as TransferableBookContent?;
      if (read == null) return null;
      return (
        bytes: read.data.materialize().asUint8List(),
        rowHasNewline: read.rowHasNewline,
      );
    },
    read: readBookContentBytes,
  );

  static Future<T?> _load<T>(
    SeforimRepository repository,
    db_models.Book book, {
    required String workerMethod,
    required T? Function(Object? result) fromWorker,
    required _BookRead<T> read,
  }) async {
    final BookTextKey key = (id: book.id, title: book.title);
    final database = repository.database;
    if (database.isOfficial) {
      try {
        return fromWorker(
          await DbReadWorker.request(workerMethod, {
            'dbPath': database.path,
            'bookId': key.id,
            'title': key.title,
          }),
        );
      } on DbReadWorkerUnavailable {
        return DbReadWorker.runOnFreshIsolate(
          _readOnTargetTask(database.readOnlyTarget, key, read),
        );
      }
    }
    if (database.isUntrusted) {
      return Isolate.run(_readOnTargetTask(database.readOnlyTarget, key, read));
    }
    mainConnectionReads++;
    return read(await database.database, key);
  }
}

// פונקציה נפרדת: סגירה בתוך _load הייתה לוכדת את ה-repository, שאינו נשלח.
Future<T?> Function() _readOnTargetTask<T>(
  ReadOnlyDbTarget target,
  BookTextKey book,
  _BookRead<T> read,
) => () async {
  final db = openReadOnlyTarget(target);
  try {
    return await read(db, book);
  } finally {
    db.close();
  }
};

const _chunkBytes = 64 * 1024;

/// שורות [book] מאוחות ב-`\n`, כרצף חוצצים; null כשאין לו שורות.
/// תוכן NULL נקרא כשורה ריקה.
Future<({List<Uint8List> chunks, bool rowHasNewline})?> _readJoinedChunks(
  sqlite3.Database db,
  BookTextKey book, {
  bool stripRowBom = false,
  bool detectRowNewline = false,
  ReadCheckpoint? checkpoint,
}) async {
  final codec = LineContentCodec.of(db);
  final statement = db.prepare(_contentSql(db, blob: true));
  try {
    final raw = statement.raw
      ..bindInt64(1, book.id)
      ..bindText(2, book.title);
    final chunks = <Uint8List>[];
    var chunk = Uint8List(0);
    var used = 0;
    var rows = 0;
    var rowHasNewline = false;
    while (raw.step()) {
      // לפי סוג האחסון, כמו LineDao: BLOB שאינו מתפענח נדחה ולא עובר כטקסט.
      final text = raw.columnInt64(1) != 0
          ? codec.bytes(raw.columnBlob(0))
          : null;
      final size = (rows > 0 ? 1 : 0) + (text?.length ?? raw.columnBytes(0));
      if (used + size > chunk.length) {
        if (used > 0) chunks.add(_usedChunk(chunk, used));
        chunk = Uint8List(size > _chunkBytes ~/ 2 ? size : _chunkBytes);
        used = 0;
      }
      if (rows > 0) chunk[used++] = 0x0A;
      final start = used;
      if (text != null) {
        chunk.setAll(used, text);
        used += text.length;
      } else {
        used += raw.columnBlobInto(0, chunk, used);
      }
      if (detectRowNewline && !rowHasNewline) {
        rowHasNewline = Uint8List.sublistView(
          chunk,
          start,
          used,
        ).contains(0x0A);
      }
      // utf8.decode משמיט BOM בתחילת כל שורה; בחוצץ אחד — רק בשורה הראשונה.
      if (stripRowBom && rows > 0 && _startsWithBom(chunk, start, used)) {
        chunk.setRange(start, used - 3, chunk, start + 3);
        used -= 3;
      }
      rows++;
      if (checkpoint != null && rows % _rowsPerCheckpoint == 0) {
        await checkpoint();
      }
    }
    if (rows == 0) return null;
    if (used > 0) chunks.add(_usedChunk(chunk, used));
    return (chunks: chunks, rowHasNewline: rowHasNewline);
  } finally {
    statement.close();
  }
}

Uint8List _usedChunk(Uint8List chunk, int used) {
  // view משאיר את כל החוצץ בחיים; חוצץ דליל נשמר בהקצאה מדויקת.
  if (used * 4 < chunk.length * 3) return chunk.sublist(0, used);
  return Uint8List.sublistView(chunk, 0, used);
}

bool _startsWithBom(Uint8List bytes, int start, int end) =>
    end - start >= 3 &&
    bytes[start] == 0xEF &&
    bytes[start + 1] == 0xBB &&
    bytes[start + 2] == 0xBF;

Uint8List _concat(List<Uint8List> chunks) {
  var total = 0;
  for (final chunk in chunks) {
    total += chunk.length;
  }
  final joined = Uint8List(total);
  var offset = 0;
  for (final chunk in chunks) {
    joined.setAll(offset, chunk);
    offset += chunk.length;
  }
  return joined;
}

/// תוכן [book] כבייטים מאוחים ב-`\n`, או null כשאין לו שורות.
Future<BookContentBytes?> readBookContentBytes(
  sqlite3.Database db,
  BookTextKey book, {
  ReadCheckpoint? checkpoint,
}) async {
  final read = await _readJoinedChunks(
    db,
    book,
    detectRowNewline: true,
    checkpoint: checkpoint,
  );
  if (read == null) return null;
  return (bytes: _concat(read.chunks), rowHasNewline: read.rowHasNewline);
}

/// [BookContentBytes] כחוצץ שעובר ל-isolate אחר בלי העתקה נוספת.
typedef TransferableBookContent = ({
  TransferableTypedData data,
  bool rowHasNewline,
});

/// כמו [readBookContentBytes], כחוצץ שעובר ל-isolate אחר בלי העתקה נוספת.
Future<TransferableBookContent?> readBookContentTransferable(
  sqlite3.Database db,
  BookTextKey book, {
  ReadCheckpoint? checkpoint,
}) async {
  final read = await _readJoinedChunks(
    db,
    book,
    detectRowNewline: true,
    checkpoint: checkpoint,
  );
  if (read == null) return null;
  return (
    data: TransferableTypedData.fromList(read.chunks),
    rowHasNewline: read.rowHasNewline,
  );
}

/// הטקסט המלא של [book] — זהה ל-`join('\n')` של תוכן השורות.
Future<String?> readBookContentText(
  sqlite3.Database db,
  BookTextKey book, {
  ReadCheckpoint? checkpoint,
}) async {
  // CAST AS BLOB מחזיר את קידוד המסד; פענוח חוצץ אחד נכון רק ב-UTF-8.
  final encoding = db.select('PRAGMA encoding').first.values.first;
  if (encoding != 'UTF-8') {
    final rows = db.select(_contentSql(db, blob: false), [book.id, book.title]);
    if (rows.isEmpty) return null;
    final codec = LineContentCodec.of(db);
    return rows.map((row) => codec.text(row.values.first) ?? '').join('\n');
  }
  final read = await _readJoinedChunks(
    db,
    book,
    stripRowBom: true,
    checkpoint: checkpoint,
  );
  return read == null ? null : utf8.decode(_concat(read.chunks));
}
