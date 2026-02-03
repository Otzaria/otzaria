import 'dart:io';

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
  })  : _fileSystem = fileSystemData ?? FileSystemData.instance,
        _service = service ?? PersonalNotesService(),
        _database = database ?? PersonalNotesDatabase.instance;

  Future<List<PersonalNote>> loadNotes(String bookId) async {
    final content = await _loadBookContent(bookId);
    return _service.loadNotes(bookId: bookId, bookContent: content);
  }

  Future<List<PersonalNote>> addNote({
    required String bookId,
    required int lineNumber,
    required String content,
    required String contentPlain,
    required PersonalNoteContentFormat contentFormat,
    String? selectedText,
  }) async {
    final bookContent = await _loadBookContent(bookId);
    return _service.addNote(
      bookId: bookId,
      bookContent: bookContent,
      lineNumber: lineNumber,
      content: content,
      contentPlain: contentPlain,
      contentFormat: contentFormat,
      selectedText: selectedText,
    );
  }

  Future<List<PersonalNote>> updateNote({
    required String bookId,
    required String noteId,
    required String content,
    required String contentPlain,
    required PersonalNoteContentFormat contentFormat,
  }) async {
    final bookContent = await _loadBookContent(bookId);
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
  }) async {
    final bookContent = await _loadBookContent(bookId);
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
  }) async {
    final bookContent = await _loadBookContent(bookId);
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

  Future<String> _loadBookContent(String bookId) async {
    try {
      final location = await BookLocator.locateBook(bookId);
      if (location != null) {
        if (location.source == BookSource.database && location.book != null) {
          final dbBook = location.book!;
          if (dbBook.isContentExternal && dbBook.filePath != null) {
            final file = File(dbBook.filePath!);
            if (await file.exists()) {
              return await file.readAsString();
            }
          }

          final fileType = dbBook.fileType ?? 'txt';
          final categoryId = location.categoryId;
          final dbText = await SqliteDataProvider.instance.getBookTextFromDb(
            bookId,
            categoryId,
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
    } catch (_) {
      return '';
    }
  }
}
