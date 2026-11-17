import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:otzaria/attached_libraries/repository/attached_library_registry.dart';
import 'package:otzaria/data/book_identity.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/database/sqlite3_utils.dart'
    show withTransaction;
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';
import 'package:sqlite3/sqlite3.dart';

/// חותם התוכן שהמסד מחזיק לכל ספר (`book.contentHash`, סכמה 7) — נצרב באינדקס
/// כ-sourceHash ומושווה אליו כדי לגלות שינוי בלי לקרוא את טקסט הספר.
class BookSourceHashes {
  BookSourceHashes(this._official, this._attached);

  static final BookSourceHashes none = BookSourceHashes(const {}, const {});

  final Map<int, BigInt>? _official;
  final Map<String, Map<int, BigInt>?> _attached;

  /// null כשהמסד אינו מחזיק חותם לספר (מסד ישן, ספר אישי, או 0 = לא ידוע).
  BigInt? forSource(BookSource source, int id) {
    final hashes = switch (source) {
      OfficialBookSource() => _official,
      AttachedBookSource(:final slug) => _attached[slug],
      UserBookSource() => null,
    };
    final hash = hashes?[id];
    return hash == null || hash == BigInt.zero ? null : hash;
  }

  /// האם למסד של [source] יש עמודת חותם — אחרת אין טעם לחפש בו.
  bool covers(BookSource source) => switch (source) {
    OfficialBookSource() => _official != null,
    AttachedBookSource(:final slug) => _attached[slug] != null,
    UserBookSource() => false,
  };

  /// חותם מסד שייך רק לספר טקסט שזהות האינדוקס שלו מפנה לשורת המסד.
  static int? sourceBookId(Book book) {
    final id = book.id;
    if (book is! TextBook || id == null) return null;
    if (book.filePath?.trim().isNotEmpty ?? false) return null;
    final key = BookIdentity.indexedFilePath(book);
    final fromDb = switch (book.source) {
      OfficialBookSource() => key == BookIdentity.officialBookKey(id),
      AttachedBookSource(:final slug) =>
        key == BookIdentity.attachedBookKey(slug, id),
      UserBookSource() => false,
    };
    return fromDb ? id : null;
  }

  /// קורא את החותמים מ-seforim.db ומהמסדים המצורפים ב-[attachedSlugs].
  static Future<BookSourceHashes> load({
    Iterable<String> attachedSlugs = const [],
  }) => _load(null, {for (final slug in attachedSlugs) slug: null});

  /// קורא חותמים לספרים מועמדים בלבד, לפי המקור ומזהה השורה שלהם.
  static Future<BookSourceHashes> loadForBooks(Iterable<Book> books) {
    final official = <int>{};
    final attached = <String, Set<int>>{};
    for (final book in books) {
      final id = sourceBookId(book);
      if (id == null) continue;
      switch (book.source) {
        case OfficialBookSource():
          official.add(id);
        case AttachedBookSource(:final slug):
          (attached[slug] ??= {}).add(id);
        case UserBookSource():
          break;
      }
    }
    return _load(official, attached);
  }

  static Future<BookSourceHashes> _load(
    Set<int>? officialIds,
    Map<String, Set<int>?> attachedIds,
  ) async {
    final official = officialIds?.isEmpty == true
        ? null
        : await _read(SqliteDataProvider.instance.repository, officialIds);
    final attached = <String, Map<int, BigInt>?>{};
    for (final entry in attachedIds.entries) {
      final slug = entry.key;
      try {
        attached[slug] = await _read(
          await AttachedLibraryRegistry.instance.repositoryFor(slug),
          entry.value,
        );
      } catch (e) {
        debugPrint('⚠️ פתיחת המסד המצורף $slug לחותמי תוכן נכשלה: $e');
      }
    }
    return BookSourceHashes(official, attached);
  }

  static Future<Map<int, BigInt>?> _read(
    SeforimRepository? repository,
    Set<int>? ids,
  ) async {
    if (repository == null) return null;
    try {
      final capabilities = await repository.database.capabilities;
      if (!capabilities.hasColumn('book', 'contentHash')) return null;
      final path = repository.database.path;
      return await Isolate.run(() => _readHashes(path, ids));
    } catch (e) {
      debugPrint('⚠️ קריאת חותמי התוכן מהמסד נכשלה: $e');
      return null;
    }
  }

  static const _selectHashes = 'SELECT id, contentHash FROM book';
  static const _batchSize = 500;

  static Map<int, BigInt> _readHashes(String path, Set<int>? ids) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      return readHashesFromDatabase(db, ids);
    } finally {
      db.close();
    }
  }

  @visibleForTesting
  static Map<int, BigInt> readHashesFromDatabase(Database db, Set<int>? ids) {
    final hashes = <int, BigInt>{};
    if (ids == null) {
      _addRows(db.select(_selectHashes), hashes);
      return hashes;
    }

    void readCandidates() {
      if (ids.length > _batchSize &&
          db.select('SELECT 1 FROM book LIMIT 1 OFFSET ?', [
            ids.length * 2 - 1,
          ]).isEmpty) {
        // בקבוצה צפופה, סריקה אחת זולה ממאות או אלפי חיפושי מפתח.
        _addRows(db.select(_selectHashes), hashes, filter: ids);
        return;
      }
      final orderedIds = ids.toList();
      for (var start = 0; start < orderedIds.length; start += _batchSize) {
        final batch = orderedIds.skip(start).take(_batchSize).toList();
        final parameters = List.filled(batch.length, '?').join(', ');
        _addRows(
          db.select('$_selectHashes WHERE id IN ($parameters)', batch),
          hashes,
        );
      }
    }

    if (ids.length > _batchSize) {
      // בדיקת הצפיפות וכל המקטעים צריכים לקרוא מאותה תמונת מצב.
      withTransaction(db, readCandidates);
    } else {
      readCandidates();
    }
    return hashes;
  }

  static void _addRows(
    ResultSet rows,
    Map<int, BigInt> hashes, {
    Set<int>? filter,
  }) {
    for (final row in rows) {
      final id = row['id'] as int;
      if (filter == null || filter.contains(id)) {
        hashes[id] = toUnsigned(row['contentHash'] as int);
      }
    }
  }

  /// SQLite שומר את החותם כ-i64; המנוע מקבל u64 — אותה המרה בשני הכיוונים.
  @visibleForTesting
  static BigInt toUnsigned(int value) => BigInt.from(value).toUnsigned(64);
}
