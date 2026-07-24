import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:otzaria/data/book_locator.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/personal_notes/models/personal_note.dart';
import 'package:otzaria/personal_notes/services/personal_notes_service.dart';
import 'package:otzaria/personal_notes/storage/personal_notes_database.dart';

class PersonalNotesRepository {
  final FileSystemData _fileSystem;
  final PersonalNotesService _service;
  final PersonalNotesDatabase _database;

  PersonalNotesRepository({
    FileSystemData? fileSystemData,
    PersonalNotesService? service,
    PersonalNotesDatabase? database,
  }) : _fileSystem = fileSystemData ?? FileSystemData.instance,
       _service = service ?? PersonalNotesService(),
       _database = database ?? PersonalNotesDatabase.instance;

  Future<List<PersonalNote>> loadNotes(
    String bookId, {
    int? categoryId,
  }) async {
    final content = await _loadBookContent(bookId, categoryId: categoryId);
    return _service.loadNotes(bookId: bookId, bookContent: content);
  }

  Future<List<PersonalNote>> addNote({
    required String bookId,
    required int lineNumber,
    required String content,
    required String contentPlain,
    required PersonalNoteContentFormat contentFormat,
    String? selectedText,
    int? selectionColumn,
    int? categoryId,
  }) async {
    final bookContent = await _loadBookContent(bookId, categoryId: categoryId);
    return _service.addNote(
      bookId: bookId,
      bookContent: bookContent,
      lineNumber: lineNumber,
      content: content,
      contentPlain: contentPlain,
      contentFormat: contentFormat,
      selectedText: selectedText,
      selectionColumn: selectionColumn,
    );
  }

  Future<List<PersonalNote>> updateNote({
    required String bookId,
    required String noteId,
    required String content,
    required String contentPlain,
    required PersonalNoteContentFormat contentFormat,
    int? categoryId,
  }) async {
    final bookContent = await _loadBookContent(bookId, categoryId: categoryId);
    return _service.updateNote(
      bookId: bookId,
      bookContent: bookContent,
      noteId: noteId,
      content: content,
      contentPlain: contentPlain,
      contentFormat: contentFormat,
    );
  }

  Future<List<PersonalNote>> deleteNote({
    required String bookId,
    required String noteId,
    int? categoryId,
  }) async {
    final bookContent = await _loadBookContent(bookId, categoryId: categoryId);
    return _service.deleteNote(
      bookId: bookId,
      bookContent: bookContent,
      noteId: noteId,
    );
  }

  Future<List<PersonalNote>> repositionNote({
    required String bookId,
    required String noteId,
    required int lineNumber,
    int? categoryId,
  }) async {
    final bookContent = await _loadBookContent(bookId, categoryId: categoryId);
    return _service.repositionNote(
      bookId: bookId,
      bookContent: bookContent,
      noteId: noteId,
      lineNumber: lineNumber,
    );
  }

  Future<List<BookNotesInfo>> listBooksWithNotes() {
    return _database.listBooksWithNotes();
  }

  Future<String> _loadBookContent(String bookId, {int? categoryId}) async {
    try {
      final location = await BookLocator.locateBook(
        bookId,
        categoryId: categoryId,
      );
      if (location != null) {
        if (location.source == BookSource.database && location.book != null) {
          final dbBook = location.book!;
          if (dbBook.isFileBacked && dbBook.filePath != null) {
            final file = File(dbBook.filePath!);
            if (await file.exists()) {
              return await file.readAsString();
            }
          }

          final fileType = dbBook.fileType ?? 'txt';
          final resolvedCategoryId = location.categoryId;
          final dbText = await SqliteDataProvider.instance.getBookTextFromDb(
            bookId,
            resolvedCategoryId,
            fileType,
          );
          if (dbText != null) {
            return dbText;
          }
        } else if (location.source == BookSource.fileSystem &&
            location.filePath != null) {
          final file = File(location.filePath!);
          if (await file.exists()) {
            return await file.readAsString();
          }
        }
      }

      return await _fileSystem.getBookText(bookId);
    } catch (e) {
      // ספרי PDF (וספרים שנמחקו) מגיעים לכאן דרך חריגה — '' הוא הסיגנל
      // לעיגון-לפי-עמוד ב-_reconcileLocation, ולכן אין rethrow. הלוג מבחין
      // כשל קריאה אמיתי ממצב ה-PDF הלגיטימי.
      debugPrint('[PersonalNotes] book content load failed for "$bookId": $e');
      return '';
    }
  }
}
