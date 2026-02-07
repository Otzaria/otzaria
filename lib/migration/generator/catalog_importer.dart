import 'dart:io';
import 'package:csv/csv.dart';
import 'package:logging/logging.dart';
import 'package:otzaria/migration/core/models/author.dart';
import 'package:otzaria/migration/core/models/book.dart';
import 'package:otzaria/migration/core/models/pub_date.dart';
import 'package:otzaria/migration/core/models/pub_place.dart';
import 'package:otzaria/migration/core/models/topic.dart';
import 'package:otzaria/migration/dao/repository/seforim_repository.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class CatalogImporter {
  static final _log = Logger('CatalogImporter');
  final SeforimRepository repository;
  final String sourceDirectory;
  final void Function(double progress, String message)? onProgress;

  // Cache for external category IDs
  final Map<String, int> _externalCategoryCache = {};

  CatalogImporter({
    required this.repository,
    required this.sourceDirectory,
    this.onProgress,
  });

  Future<void> importExternalCatalogs() async {
    _log.info('Starting import of external catalogs...');
    onProgress?.call(0, 'מתחיל יבוא קטלוגים חיצוניים...');

    // Process Otzar HaChochma
    try {
      final otzarSourceId =
          await repository.insertSource('Otzar HaChochma', -2);
      await _importOtzarBooks(otzarSourceId);
    } catch (e, stackTrace) {
      _log.severe('Error importing Otzar HaChochma books', e, stackTrace);
    }

    // Process HebrewBooks
    try {
      final hbSourceId = await repository.insertSource('HebrewBooks', -3);
      await _importHebrewBooks(hbSourceId);
    } catch (e, stackTrace) {
      _log.severe('Error importing HebrewBooks', e, stackTrace);
    }

    onProgress?.call(1, 'סיום יבוא קטלוגים חיצוניים');
  }

  Future<void> _importOtzarBooks(int sourceId) async {
    final file = File(path.join(
        sourceDirectory, 'אוצריא', 'אודות התוכנה', 'otzar_books.csv'));
    if (!await file.exists()) {
      _log.warning('otzar_books.csv not found');
      return;
    }

    _log.info('Importing Otzar HaChochma books...');
    // Read file using stream to handle large files efficiently
    // However, for CSV parsing, it's safer to read the whole content if not strictly line-based
    // But since these are large catalogs, line-based is likely.
    // For now, to keep it robust, we read string but optimize the DB part.

    final content = await file.readAsString();
    final eol = content.contains('\r\n') ? '\r\n' : '\n';
    final rows = CsvToListConverter().convert(content, eol: eol);

    if (rows.isEmpty) return;

    // 1. Pre-fetch existing external IDs to avoid N queries
    final existingExternalIds = await _getExistingExternalIds(sourceId);

    final db = await repository.database.database;
    await db.transaction((txn) async {
      final batchSize = 500;
      final pendingBooks = <Book>[];

      // Get category ID once
      final catId = await _getOrCreateExternalCategory(txn, 'אוצר החוכמה');

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.length < 2) continue;

        try {
          final externalId = row[0].toString();
          if (existingExternalIds.contains(externalId)) continue;

          final title = row[1].toString().trim();
          final authorStr = row.length > 2 ? row[2].toString().trim() : '';
          final placeStr = row.length > 3 ? row[3].toString().trim() : '';
          final yearStr = row.length > 4 ? row[4].toString().trim() : '';
          final topicsStr = row.length > 5 ? row[5].toString().trim() : '';
          final link = row.last.toString().trim();

          final authors = _parseAuthors(authorStr);
          final pubPlaces =
              placeStr.isNotEmpty ? [PubPlace(name: placeStr)] : <PubPlace>[];
          final pubDates =
              yearStr.isNotEmpty ? [PubDate(date: yearStr)] : <PubDate>[];
          final topics = _parseTopics(topicsStr);

          final book = Book(
              id: await repository.getNextNegativeBookId(),
              categoryId: catId,
              sourceId: sourceId,
              title: title,
              authors: authors,
              pubPlaces: pubPlaces,
              pubDates: pubDates,
              topics: topics,
              order: 999.0,
              isBaseBook: false,
              isContentExternal: true,
              filePath: link,
              fileType: 'url',
              externalLibraryId: externalId);

          pendingBooks.add(book);
          existingExternalIds.add(
              externalId); // Add to set to handle duplicates within the file itself if any

          if (pendingBooks.length >= batchSize) {
            await _flushPendingBooks(txn, pendingBooks);
            pendingBooks.clear();
            onProgress?.call(
                i / rows.length, 'מעבד אוצר החוכמה: $i/${rows.length}');
          }
        } catch (e) {
          _log.warning('Error processing row $i in otzar_books.csv', e);
        }
      }

      // Commit remaining
      if (pendingBooks.isNotEmpty) {
        await _flushPendingBooks(txn, pendingBooks);
      }
    });
  }

  Future<void> _importHebrewBooks(int sourceId) async {
    final file = File(path.join(
        sourceDirectory, 'אוצריא', 'אודות התוכנה', 'hebrew_books.csv'));
    if (!await file.exists()) {
      _log.warning('hebrew_books.csv not found');
      return;
    }

    _log.info('Importing HebrewBooks...');
    final content = await file.readAsString();
    final eol = content.contains('\r\n') ? '\r\n' : '\n';
    final rows = CsvToListConverter().convert(content, eol: eol);

    if (rows.isEmpty) return;

    // 1. Pre-fetch existing external IDs
    final existingExternalIds = await _getExistingExternalIds(sourceId);

    final db = await repository.database.database;
    await db.transaction((txn) async {
      final batchSize = 500;
      final pendingBooks = <Book>[];

      final catId = await _getOrCreateExternalCategory(txn, 'HebrewBooks');

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.length < 2) continue;

        try {
          final externalId = row[0].toString();
          if (existingExternalIds.contains(externalId)) continue;

          final title = row[1].toString().trim();
          final authorStr = row.length > 2 ? row[2].toString().trim() : '';
          final placeStr = row.length > 3 ? row[3].toString().trim() : '';
          final yearStr = row.length > 4 ? row[4].toString().trim() : '';
          final topicsStr = row.length > 15 ? row[15].toString().trim() : '';

          final link = 'https://hebrewbooks.org/$externalId';

          final authors = _parseAuthors(authorStr);
          final pubPlaces =
              placeStr.isNotEmpty ? [PubPlace(name: placeStr)] : <PubPlace>[];
          final pubDates =
              yearStr.isNotEmpty ? [PubDate(date: yearStr)] : <PubDate>[];
          final topics = _parseTopics(topicsStr);

          final book = Book(
              id: await repository.getNextNegativeBookId(),
              categoryId: catId,
              sourceId: sourceId,
              title: title,
              authors: authors,
              pubPlaces: pubPlaces,
              pubDates: pubDates,
              topics: topics,
              order: 999.0,
              isBaseBook: false,
              isContentExternal: true,
              filePath: link,
              fileType: 'url',
              externalLibraryId: externalId);

          pendingBooks.add(book);
          existingExternalIds.add(externalId);

          if (pendingBooks.length >= batchSize) {
            await _flushPendingBooks(txn, pendingBooks);
            pendingBooks.clear();
            onProgress?.call(
                i / rows.length, 'מעבד HebrewBooks: $i/${rows.length}');
          }
        } catch (e) {
          _log.warning('Error processing row $i in hebrew_books.csv', e);
        }
      }

      if (pendingBooks.isNotEmpty) {
        await _flushPendingBooks(txn, pendingBooks);
      }
    });
  }

  Future<Set<String>> _getExistingExternalIds(int sourceId) async {
    final db = await repository.database.database;
    final result = await db.rawQuery(
        'SELECT externalId FROM book WHERE sourceId = ? AND externalId IS NOT NULL',
        [sourceId]);
    return result.map((row) => row['externalId'] as String).toSet();
  }

  Future<void> _flushPendingBooks(Transaction txn, List<Book> books) async {
    if (books.isEmpty) return;

    final bookPlaceholders = books
        .map((_) => '(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)')
        .join(',');
    final bookValues = books
        .expand((b) => [
              b.id,
              b.categoryId,
              b.sourceId,
              b.title,
              b.heShortDesc,
              b.order,
              b.isBaseBook ? 1 : 0,
              b.isContentExternal ? 1 : 0,
              b.notesContent,
              b.filePath,
              b.fileType,
              b.fileSize,
              b.lastModified,
              b.externalLibraryId,
            ])
        .toList();

    await txn.rawInsert('''
         INSERT INTO book (
             id, categoryId, sourceId, title, heShortDesc, order_index, 
             isBaseBook, isContentExternal, notesContent, filePath, fileType, 
             fileSize, lastModified, externalLibraryId
         ) VALUES $bookPlaceholders
      ''', bookValues);

    // Helper to prepare junction inserts
    Future<void> insertJunction(String table, String colTwo,
        List<({int bookId, String val})> pairs) async {
      if (pairs.isEmpty) return;
      final placeholders = pairs.map((_) => '(?, ?)').join(',');
      final values = pairs.expand((p) => [p.bookId, p.val]).toList();
      await txn.rawInsert(
          'INSERT INTO $table (bookId, $colTwo) VALUES $placeholders', values);
    }

    final authorPairs = <({int bookId, String val})>[];
    final placePairs = <({int bookId, String val})>[];
    final datePairs = <({int bookId, String val})>[];
    final topicPairs = <({int bookId, String val})>[];

    for (final book in books) {
      for (final a in book.authors) {
        authorPairs.add((bookId: book.id, val: a.name));
      }
      for (final p in book.pubPlaces) {
        placePairs.add((bookId: book.id, val: p.name));
      }
      for (final d in book.pubDates) {
        datePairs.add((bookId: book.id, val: d.date));
      }
      for (final t in book.topics) {
        topicPairs.add((bookId: book.id, val: t.name));
      }
    }

    await insertJunction('book_author', 'author', authorPairs);
    await insertJunction('book_pub_place', 'pubPlace', placePairs);
    await insertJunction('book_pub_date', 'pubDate', datePairs);
    await insertJunction('book_topic', 'topic', topicPairs);
  }

  List<Author> _parseAuthors(String str) {
    if (str.isEmpty) return [];
    return str
        .split(RegExp(r' - |,'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((e) => Author(name: e))
        .toList();
  }

  List<Topic> _parseTopics(String str) {
    if (str.isEmpty) return [];
    return str
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((e) => Topic(name: e))
        .toList();
  }

  Future<int> _getOrCreateExternalCategory(Transaction txn, String name) async {
    if (_externalCategoryCache.containsKey(name)) {
      return _externalCategoryCache[name]!;
    }

    final rootTitle = 'ספריות חיצוניות';

    // Find root
    var res = await txn.query('category',
        where: 'title = ? AND parentId IS NULL',
        whereArgs: [rootTitle],
        limit: 1);

    int rootId;
    if (res.isNotEmpty) {
      rootId = res.first['id'] as int;
    } else {
      // Categories are few, so we insert them directly.
      rootId = await txn.insert(
          'category', {'title': rootTitle, 'level': 0, 'parentId': null});
    }

    // Find sub
    res = await txn.query('category',
        where: 'title = ? AND parentId = ?',
        whereArgs: [name, rootId],
        limit: 1);

    int subId;
    if (res.isNotEmpty) {
      subId = res.first['id'] as int;
    } else {
      subId = await txn
          .insert('category', {'title': name, 'parentId': rootId, 'level': 1});
    }

    _externalCategoryCache[name] = subId;
    return subId;
  }
}
