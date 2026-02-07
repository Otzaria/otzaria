import 'package:sqflite/sqflite.dart';
import '../../core/models/book.dart';
import '../sqflite/query_loader.dart';
import 'database.dart';

// Simple model for book_has_links table entries
class BookHasLinksEntry {
  final int bookId;
  final bool hasSourceLinks;
  final bool hasTargetLinks;

  const BookHasLinksEntry({
    required this.bookId,
    required this.hasSourceLinks,
    required this.hasTargetLinks,
  });

  factory BookHasLinksEntry.fromMap(Map<String, dynamic> map) {
    return BookHasLinksEntry(
      bookId: map['bookId'] as int,
      hasSourceLinks: (map['hasSourceLinks'] as int) == 1,
      hasTargetLinks: (map['hasTargetLinks'] as int) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'bookId': bookId,
      'hasSourceLinks': hasSourceLinks ? 1 : 0,
      'hasTargetLinks': hasTargetLinks ? 1 : 0,
    };
  }
}

class BookHasLinksDao {
  final MyDatabase _db;
  late final Map<String, String> _queries;

  BookHasLinksDao(this._db) {
    _queries = QueryLoader.loadQueries('BookHasLinksQueries.sq');
  }

  Future<Database> get database => _db.database;

  Future<BookHasLinksEntry?> getBookHasLinksByBookId(int bookId) async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectByBookId']!, [bookId]);
    if (result.isEmpty) return null;
    return BookHasLinksEntry.fromMap(result.first);
  }

  Future<List<Book>> getBooksWithSourceLinks() async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectBooksWithSourceLinks']!);
    return result.map((row) => Book.fromJson(row)).toList();
  }

  Future<List<Book>> getBooksWithTargetLinks() async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectBooksWithTargetLinks']!);
    return result.map((row) => Book.fromJson(row)).toList();
  }

  Future<List<Book>> getBooksWithAnyLinks() async {
    final db = await database;
    final result = await db.rawQuery(_queries['selectBooksWithAnyLinks']!);
    return result.map((row) => Book.fromJson(row)).toList();
  }

  Future<int> countBooksWithSourceLinks() async {
    final db = await database;
    final result = await db.rawQuery(_queries['countBooksWithSourceLinks']!);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countBooksWithTargetLinks() async {
    final db = await database;
    final result = await db.rawQuery(_queries['countBooksWithTargetLinks']!);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countBooksWithAnyLinks() async {
    final db = await database;
    final result = await db.rawQuery(_queries['countBooksWithAnyLinks']!);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> upsertBookHasLinks(
      int bookId, bool hasSourceLinks, bool hasTargetLinks) async {
    final db = await database;
    return await db.rawInsert(_queries['upsert']!,
        [bookId, hasSourceLinks ? 1 : 0, hasTargetLinks ? 1 : 0]);
  }

  Future<int> updateSourceLinks(int bookId, bool hasSourceLinks) async {
    final db = await database;
    return await db.rawUpdate(
        _queries['updateSourceLinks']!, [hasSourceLinks ? 1 : 0, bookId]);
  }

  Future<int> updateTargetLinks(int bookId, bool hasTargetLinks) async {
    final db = await database;
    return await db.rawUpdate(
        _queries['updateTargetLinks']!, [hasTargetLinks ? 1 : 0, bookId]);
  }

  Future<int> updateBothLinkTypes(
      int bookId, bool hasSourceLinks, bool hasTargetLinks) async {
    final db = await database;
    return await db.rawUpdate(_queries['updateBothLinkTypes']!,
        [hasSourceLinks ? 1 : 0, hasTargetLinks ? 1 : 0, bookId]);
  }

  Future<int> insertBookHasLinks(
      int bookId, bool hasSourceLinks, bool hasTargetLinks) async {
    final db = await database;
    return await db.rawInsert(_queries['insert']!,
        [bookId, hasSourceLinks ? 1 : 0, hasTargetLinks ? 1 : 0]);
  }

  Future<int> deleteBookHasLinks(int bookId) async {
    final db = await database;
    return await db.rawDelete(_queries['delete']!, [bookId]);
  }
}
