import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logging/logging.dart';

import '../models/tracked_book_model.dart';
import '../config/built_in_books_config.dart';

/// Service for managing custom tracked books
///
/// This service handles:
/// - Adding/removing custom books to tracking
/// - Persisting the list of tracked books
/// - Checking if a book is already tracked
class CustomBooksService {
  static final Logger _logger = Logger('CustomBooksService');
  static const String _storageKey = 'shamor_zachor_custom_books';

  final SharedPreferences _prefs;
  List<TrackedBook> _customBooks = [];

  CustomBooksService(this._prefs);

  /// Initialize and load custom books from storage
  Future<void> init() async {
    await _loadCustomBooks();
  }

  /// Load custom books from SharedPreferences
  Future<void> _loadCustomBooks() async {
    try {
      final jsonString = _prefs.getString(_storageKey);
      if (jsonString == null || jsonString.isEmpty) {
        _customBooks = [];
        return;
      }

      final List<dynamic> jsonList = jsonDecode(jsonString);
      final loadedBooks = jsonList
          .map((json) => TrackedBook.fromJson(json as Map<String, dynamic>))
          .toList();

      bool hadBuiltIns = false;
      _customBooks = [];
      for (final book in loadedBooks) {
        if (book.isBuiltIn) {
          hadBuiltIns = true;
          _logger.fine(
              'Ignoring persisted built-in book during load: ${book.bookId}');
          continue;
        }
        _customBooks.add(book);
      }

      if (hadBuiltIns) {
        await _saveCustomBooks();
        _logger.info('Removed ${loadedBooks.length - _customBooks.length} '
            'built-in books from persisted custom list');
      }

      _logger.info('Loaded ${_customBooks.length} custom books');
    } catch (e, stackTrace) {
      _logger.severe('Failed to load custom books', e, stackTrace);
      _customBooks = [];
    }
  }

  /// Save custom books to SharedPreferences
  Future<void> _saveCustomBooks() async {
    try {
      final jsonList = _customBooks.map((book) => book.toJson()).toList();
      final jsonString = jsonEncode(jsonList);
      await _prefs.setString(_storageKey, jsonString);
      _logger.info('Saved ${_customBooks.length} custom books');
    } catch (e, stackTrace) {
      _logger.severe('Failed to save custom books', e, stackTrace);
      rethrow;
    }
  }

  /// Get all custom (non-built-in) tracked books
  List<TrackedBook> getCustomBooks() {
    return _customBooks.where((book) => !book.isBuiltIn).toList();
  }

  /// Get all tracked books (both built-in and custom)
  Future<List<TrackedBook>> getAllTrackedBooks() async {
    return List.unmodifiable(_customBooks);
  }

  /// Add a book to tracking
  Future<void> addBook(TrackedBook book) async {
    if (book.isBuiltIn) {
      _logger.fine('Skipping persistence for built-in book: ${book.bookId}');
      return;
    }

    // Check if already exists
    final existingIndex =
        _customBooks.indexWhere((b) => b.bookId == book.bookId);

    if (existingIndex >= 0) {
      // Update existing book
      _customBooks[existingIndex] = book;
      _logger.info('Updated existing tracked book: ${book.bookId}');
    } else {
      // Add new book
      _customBooks.add(book);
      _logger.info('Added new tracked book: ${book.bookId}');
    }

    await _saveCustomBooks();
  }

  /// Remove a book from tracking
  Future<void> removeBook(String bookId) async {
    final removedCount = _customBooks.length;
    _customBooks.removeWhere((book) => book.bookId == bookId);

    if (_customBooks.length < removedCount) {
      await _saveCustomBooks();
      _logger.info('Removed tracked book: $bookId');
    } else {
      _logger.warning('Attempted to remove non-existent book: $bookId');
    }
  }

  /// Check if a book is tracked (either built-in or custom)
  bool isBookTracked(String bookId) {
    return _customBooks.any((book) => book.bookId == bookId);
  }

  /// Check if a book is tracked by its name and category
  bool isBookTrackedByName(String categoryName, String bookName) {
    final bookId = '$categoryName:$bookName';
    return isBookTracked(bookId);
  }

  /// Get a tracked book by ID
  TrackedBook? getTrackedBook(String bookId) {
    try {
      return _customBooks.firstWhere((book) => book.bookId == bookId);
    } catch (e) {
      return null;
    }
  }

  /// Get a tracked book by name and category
  TrackedBook? getTrackedBookByName(String categoryName, String bookName) {
    final bookId = '$categoryName:$bookName';
    return getTrackedBook(bookId);
  }

  /// Check if a book is built-in (based on configuration)
  bool isBuiltInBook(String categoryName, String bookName) {
    return BuiltInBooksConfig.isBuiltInBook(categoryName, bookName);
  }

  /// Update a tracked book
  Future<void> updateBook(TrackedBook book) async {
    final index = _customBooks.indexWhere((b) => b.bookId == book.bookId);

    if (index >= 0) {
      _customBooks[index] = book;
      await _saveCustomBooks();
      _logger.info('Updated tracked book: ${book.bookId}');
    } else {
      _logger.warning('Attempted to update non-existent book: ${book.bookId}');
      throw ArgumentError('Book not found: ${book.bookId}');
    }
  }

  /// Clear all custom books (keep built-in books)
  Future<void> clearCustomBooks() async {
    final beforeCount = _customBooks.length;
    _customBooks.removeWhere((book) => !book.isBuiltIn);

    if (_customBooks.length != beforeCount) {
      await _saveCustomBooks();
      _logger.info('Cleared custom books');
    }
  }

  /// Clear all books (including built-in)
  Future<void> clearAllBooks() async {
    _customBooks.clear();
    await _saveCustomBooks();
    _logger.info('Cleared all tracked books');
  }

  /// Get statistics
  Map<String, int> getStatistics() {
    final customCount = _customBooks.where((b) => !b.isBuiltIn).length;
    final builtInCount = _customBooks.where((b) => b.isBuiltIn).length;

    return {
      'total': _customBooks.length,
      'custom': customCount,
      'builtIn': builtInCount,
    };
  }

  /// Reload from storage
  Future<void> reload() async {
    await _loadCustomBooks();
  }
}
