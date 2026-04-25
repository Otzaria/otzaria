import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logging/logging.dart';

import '../models/progress_model.dart';
import '../models/book_model.dart';
import '../models/error_model.dart';
import '../models/planning_model.dart';

/// Service for managing user progress data with optimized storage
class ProgressService {
  static final Logger _logger = Logger('ProgressService');

  // Storage key prefix to avoid conflicts with main app
  static const String _keyPrefix = 'sz:';
  static const String _progressDataKey = '${_keyPrefix}progress_data';
  static const String _completionDatesKey = '${_keyPrefix}completion_dates';
  static const String _lastAccessedKey = '${_keyPrefix}last_accessed';
  static const String _reviewScheduleKey = '${_keyPrefix}review_schedule';
  static const String _progressByIdLegacyKey = '${_keyPrefix}progress_by_id';
  static const String _progressByIdBookKeyPrefix =
      '${_keyPrefix}progress_by_id:';

  // Debouncing for batch saves
  Timer? _saveTimer;
  Timer? _saveByIdTimer;
  final Duration _saveDelay = const Duration(milliseconds: 500);
  final Map<String, dynamic> _pendingChanges = {};
  final Map<String, dynamic> _pendingChangesById = {};

  SharedPreferences? _prefs;

  // Legacy -> current category names used by old Shamor Zachor data.
  static const Map<String, String> _legacyCategoryAliases = {
    'תנך': 'תנ"ך',
    'ש"ס': 'תלמוד בבלי',
    'ירושלמי': 'תלמוד ירושלמי',
  };

  /// Get SharedPreferences instance with error handling
  Future<SharedPreferences> _getPrefs() async {
    if (_prefs != null) return _prefs!;

    try {
      _prefs = await SharedPreferences.getInstance();
      return _prefs!;
    } catch (e, stackTrace) {
      throw ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        type: ShamorZachorErrorType.storageUnavailable,
        customMessage: 'Failed to access local storage',
      );
    }
  }

  /// Load full progress data from storage
  Future<FullProgressMap> loadFullProgressData() async {
    try {
      final prefs = await _getPrefs();
      final jsonString = prefs.getString(_progressDataKey);

      if (jsonString == null || jsonString.isEmpty) {
        return {};
      }

      final Map<String, dynamic> decodedOuter = json.decode(jsonString);
      final FullProgressMap progressMap = {};

      decodedOuter.forEach((categoryKey, categoryValue) {
        if (categoryValue is Map) {
          progressMap[categoryKey] = {};
          categoryValue.forEach((bookKey, bookValue) {
            if (bookValue is Map) {
              progressMap[categoryKey]![bookKey] = {};
              bookValue.forEach((itemIndexKey, itemProgressValue) {
                if (itemProgressValue is Map) {
                  try {
                    progressMap[categoryKey]![bookKey]![itemIndexKey] =
                        PageProgress.fromJson(
                            Map<String, dynamic>.from(itemProgressValue));
                  } catch (e) {
                    _logger.warning(
                        'Invalid progress data for $categoryKey/$bookKey/$itemIndexKey: $e');
                  }
                }
              });
            }
          });
        }
      });

      _logger.fine('Loaded progress data for ${progressMap.length} categories');
      return progressMap;
    } catch (e, stackTrace) {
      if (e is ShamorZachorError) rethrow;

      _logger.severe('Failed to load progress data: $e');
      throw ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        type: ShamorZachorErrorType.parseError,
        customMessage: 'Failed to load progress data',
      );
    }
  }

  /// Save full progress data to storage
  Future<void> _saveFullProgressData(FullProgressMap data) async {
    try {
      final prefs = await _getPrefs();
      final jsonString = json.encode(data);
      await prefs.setString(_progressDataKey, jsonString);
      _logger.fine('Saved progress data for ${data.length} categories');
    } catch (e, stackTrace) {
      throw ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        type: ShamorZachorErrorType.storageUnavailable,
        customMessage: 'Failed to save progress data',
      );
    }
  }

  /// Save progress for a single item with debouncing
  Future<void> saveProgress(
    String categoryName,
    String bookName,
    String itemIndexKey,
    String columnName,
    bool value,
  ) async {
    try {
      // Add to pending changes
      final changeKey = '$categoryName:$bookName:$itemIndexKey:$columnName';
      _pendingChanges[changeKey] = {
        'categoryName': categoryName,
        'bookName': bookName,
        'itemIndexKey': itemIndexKey,
        'columnName': columnName,
        'value': value,
      };

      // Cancel existing timer and start new one
      _saveTimer?.cancel();
      _saveTimer = Timer(_saveDelay, _processPendingChanges);
    } catch (e, stackTrace) {
      throw ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to save progress',
      );
    }
  }

  /// Process all pending changes in a batch
  Future<void> _processPendingChanges() async {
    if (_pendingChanges.isEmpty) return;

    try {
      final fullData = await loadFullProgressData();
      final changes = Map<String, dynamic>.from(_pendingChanges);
      _pendingChanges.clear();

      for (final change in changes.values) {
        final categoryName = change['categoryName'] as String;
        final bookName = change['bookName'] as String;
        final itemIndexKey = change['itemIndexKey'] as String;
        final columnName = change['columnName'] as String;
        final value = change['value'] as bool;

        fullData.putIfAbsent(categoryName, () => {});
        fullData[categoryName]!.putIfAbsent(bookName, () => {});
        fullData[categoryName]![bookName]!
            .putIfAbsent(itemIndexKey, () => PageProgress());

        final currentItemProgress =
            fullData[categoryName]![bookName]![itemIndexKey]!;
        currentItemProgress.setProperty(columnName, value);

        // Clean up empty entries
        if (currentItemProgress.isEmpty) {
          fullData[categoryName]![bookName]!.remove(itemIndexKey);
          if (fullData[categoryName]![bookName]!.isEmpty) {
            fullData[categoryName]!.remove(bookName);
            if (fullData[categoryName]!.isEmpty) {
              fullData.remove(categoryName);
            }
          }
        }
      }

      await _saveFullProgressData(fullData);
      await _updateLastAccessed();
    } catch (e) {
      _logger.severe('Failed to process pending changes: $e');
      rethrow;
    }
  }

  /// Save all items in a book as learned (bulk operation)
  Future<void> saveAllBookAsLearned(
    String categoryName,
    String bookName,
    BookDetails bookDetails,
    bool markAsLearned,
  ) async {
    try {
      // Force process any pending changes first
      await _processPendingChanges();

      final fullData = await loadFullProgressData();

      if (!markAsLearned) {
        // Remove all progress for this book
        if (fullData.containsKey(categoryName) &&
            fullData[categoryName]!.containsKey(bookName)) {
          fullData[categoryName]!.remove(bookName);
          if (fullData[categoryName]!.isEmpty) {
            fullData.remove(categoryName);
          }
        }
      } else {
        // Mark all items as learned
        fullData.putIfAbsent(categoryName, () => {});
        fullData[categoryName]!.putIfAbsent(bookName, () => {});
        final currentBookProgress = fullData[categoryName]![bookName]!;

        final learnableItems = bookDetails.learnableItems;
        for (final item in learnableItems) {
          final itemIndexKey = item.absoluteIndex.toString();
          currentBookProgress.putIfAbsent(itemIndexKey, () => PageProgress());
          currentBookProgress[itemIndexKey]!.learn = true;
        }

        await saveCompletionDate(categoryName, bookName);
      }

      await _saveFullProgressData(fullData);
      await _updateLastAccessed();
      _logger.info(
          'Bulk updated $bookName in $categoryName (learned: $markAsLearned)');
    } catch (e, stackTrace) {
      throw ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to bulk update book progress',
      );
    }
  }

  /// Load completion dates
  Future<CompletionDatesMap> loadCompletionDates() async {
    try {
      final prefs = await _getPrefs();
      final jsonString = prefs.getString(_completionDatesKey);

      if (jsonString == null || jsonString.isEmpty) return {};

      final Map<String, dynamic> decoded = json.decode(jsonString);
      final CompletionDatesMap datesMap = {};

      decoded.forEach((categoryKey, categoryValue) {
        if (categoryValue is Map) {
          datesMap[categoryKey] = Map<String, String>.from(categoryValue
              .map((key, value) => MapEntry(key.toString(), value.toString())));
        }
      });

      return datesMap;
    } catch (e, stackTrace) {
      _logger.warning('Failed to load completion dates: $e\n$stackTrace');
      return {};
    }
  }

  /// Save completion dates
  Future<void> _saveCompletionDates(CompletionDatesMap dates) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setString(_completionDatesKey, json.encode(dates));
    } catch (e, stackTrace) {
      throw ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        type: ShamorZachorErrorType.storageUnavailable,
        customMessage: 'Failed to save completion dates',
      );
    }
  }

  /// Save completion date for a book
  Future<void> saveCompletionDate(String categoryName, String bookName) async {
    try {
      final allDates = await loadCompletionDates();
      allDates.putIfAbsent(categoryName, () => {});

      if (!allDates[categoryName]!.containsKey(bookName)) {
        allDates[categoryName]![bookName] = DateTime.now().toIso8601String();
        await _saveCompletionDates(allDates);
      }
    } catch (e) {
      _logger.warning(
          'Failed to save completion date for $categoryName/$bookName: $e');
      // Don't throw - completion dates are not critical
    }
  }

  /// Get completion date for a book
  Future<String?> getCompletionDate(
      String categoryName, String bookName) async {
    try {
      final allDates = await loadCompletionDates();
      return allDates[categoryName]?[bookName];
    } catch (e) {
      _logger.warning(
          'Failed to get completion date for $categoryName/$bookName: $e');
      return null;
    }
  }

  /// Update last accessed timestamp
  Future<void> _updateLastAccessed() async {
    try {
      final prefs = await _getPrefs();
      await prefs.setString(_lastAccessedKey, DateTime.now().toIso8601String());
    } catch (e) {
      _logger.fine('Failed to update last accessed: $e');
      // Don't throw - this is not critical
    }
  }

  /// Get book progress summary
  Future<BookProgressSummary> getBookProgressSummary(
    String categoryName,
    String bookName,
    BookDetails bookDetails,
  ) async {
    try {
      final fullData = await loadFullProgressData();
      final bookProgress = fullData[categoryName]?[bookName] ?? {};
      final completionDate = await getCompletionDate(categoryName, bookName);

      return buildBookProgressSummary(
        categoryName,
        bookName,
        bookDetails,
        bookProgress,
        completionDate: completionDate,
      );
    } catch (e, stackTrace) {
      throw ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to get book progress summary',
      );
    }
  }

  /// Build a book progress summary from in-memory progress data.
  BookProgressSummary buildBookProgressSummary(
    String categoryName,
    String bookName,
    BookDetails bookDetails,
    Map<String, PageProgress> bookProgress, {
    String? completionDate,
    DateTime? lastAccessed,
  }) {
    final totalItems = bookDetails.totalLearnableItems;
    int completedItems = 0;
    int inProgressItems = 0;

    for (final progress in bookProgress.values) {
      if (progress.isComplete) {
        completedItems++;
      } else if (!progress.isEmpty) {
        inProgressItems++;
      }
    }

    bool isActiveReview = false;
    if (totalItems > 0 && completedItems == totalItems) {
      var previousReviewCompleted = true;
      for (int reviewNumber = 1;
          reviewNumber <= shamorZachorMaxReviewCycles;
          reviewNumber++) {
        final reviewProgress =
            getReviewCompletedPagesCount(bookProgress, reviewNumber) /
                totalItems;
        final isCurrentReviewActive = previousReviewCompleted &&
            reviewProgress > 0 &&
            reviewProgress < 1.0;
        if (isCurrentReviewActive) {
          isActiveReview = true;
          break;
        }
        previousReviewCompleted =
            previousReviewCompleted && reviewProgress == 1.0;
      }
    }

    return BookProgressSummary(
      categoryName: categoryName,
      bookName: bookName,
      totalItems: totalItems,
      completedItems: completedItems,
      inProgressItems: inProgressItems,
      completionDate: completionDate,
      lastAccessed: lastAccessed,
      isActiveReview: isActiveReview,
    );
  }

  /// Static helper methods for progress calculations
  static int getCompletedPagesCount(Map<String, PageProgress> bookProgress) {
    return bookProgress.values.where((progress) => progress.learn).length;
  }

  static int getReviewCompletedPagesCount(
    Map<String, PageProgress> bookProgress,
    int reviewNumber,
  ) {
    switch (reviewNumber) {
      case 1:
        return bookProgress.values.where((progress) => progress.review1).length;
      case 2:
        return bookProgress.values.where((progress) => progress.review2).length;
      case 3:
        return bookProgress.values.where((progress) => progress.review3).length;
      case 4:
        return bookProgress.values.where((progress) => progress.review4).length;
      case 5:
        return bookProgress.values.where((progress) => progress.review5).length;
      default:
        throw ArgumentError('Invalid review number: $reviewNumber');
    }
  }

  Future<ReviewScheduleSettings> loadReviewScheduleSettings() async {
    try {
      final prefs = await _getPrefs();
      final jsonString = prefs.getString(_reviewScheduleKey);
      if (jsonString == null || jsonString.isEmpty) {
        return ReviewScheduleSettings.defaultSettings();
      }

      final decoded = json.decode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        return ReviewScheduleSettings.defaultSettings();
      }

      return ReviewScheduleSettings.fromJson(decoded);
    } catch (e, stackTrace) {
      throw ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        type: ShamorZachorErrorType.parseError,
        customMessage: 'Failed to load review schedule settings',
      );
    }
  }

  Future<void> saveReviewScheduleSettings(
    ReviewScheduleSettings settings,
  ) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setString(_reviewScheduleKey, json.encode(settings.toJson()));
    } catch (e, stackTrace) {
      throw ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        type: ShamorZachorErrorType.storageUnavailable,
        customMessage: 'Failed to save review schedule settings',
      );
    }
  }

  /// Export all progress data
  Future<String> exportProgressData() async {
    try {
      final prefs = await _getPrefs();
      final progressJsonString = prefs.getString(_progressDataKey);
      final completionDatesJsonString = prefs.getString(_completionDatesKey);

      final Map<String, String?> dataToExport = {
        'progress_data': progressJsonString,
        'completion_dates': completionDatesJsonString,
        'export_timestamp': DateTime.now().toIso8601String(),
        'schema_version': '1',
      };

      return json.encode(dataToExport);
    } catch (e, stackTrace) {
      throw ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to export progress data',
      );
    }
  }

  /// Import progress data
  Future<bool> importProgressData(String jsonData) async {
    try {
      final prefs = await _getPrefs();
      final Map<String, dynamic> decodedData = json.decode(jsonData);

      final String? progressDataString =
          decodedData['progress_data'] as String?;
      final String? completionDatesString =
          decodedData['completion_dates'] as String?;

      await prefs.setString(_progressDataKey, progressDataString ?? '{}');
      await prefs.setString(_completionDatesKey, completionDatesString ?? '{}');

      _logger.info('Successfully imported progress data');
      return true;
    } catch (e, stackTrace) {
      _logger.severe('Failed to import progress data: $e\n$stackTrace');

      // Reset to empty state on import failure
      try {
        final prefs = await _getPrefs();
        await prefs.setString(_progressDataKey, '{}');
        await prefs.setString(_completionDatesKey, '{}');
      } catch (resetError) {
        _logger.severe(
            'Failed to reset progress data after import failure: $resetError');
      }

      return false;
    }
  }

  /// Clear all progress data
  Future<void> clearAllProgress() async {
    try {
      final prefs = await _getPrefs();
      await prefs.remove(_progressDataKey);
      await prefs.remove(_completionDatesKey);
      await prefs.remove(_lastAccessedKey);
      await prefs.remove(_progressByIdLegacyKey);
      final bookKeys = prefs
          .getKeys()
          .where((key) => key.startsWith(_progressByIdBookKeyPrefix))
          .toList();
      for (final key in bookKeys) {
        await prefs.remove(key);
      }

      _pendingChanges.clear();
      _saveTimer?.cancel();
      _pendingChangesById.clear();
      _saveByIdTimer?.cancel();

      _logger.info('Cleared all progress data');
    } catch (e, stackTrace) {
      throw ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to clear progress data',
      );
    }
  }

  // ============================================================================
  // NEW: Functions that work with book ID instead of category+name
  // ============================================================================

  /// Load progress data by book ID
  Future<ProgressMapById> loadProgressDataById() async {
    try {
      final prefs = await _getPrefs();
      final ProgressMapById progressMap = {};
      final jsonString = prefs.getString(_progressByIdLegacyKey);

      if (jsonString != null && jsonString.isNotEmpty) {
        final Map<String, dynamic> decoded = json.decode(jsonString);
        decoded.forEach((bookIdKey, bookValue) {
          final bookId = int.parse(bookIdKey);
          if (bookValue is Map) {
            progressMap[bookId] = _decodeBookProgress(bookId, bookValue);
          }
        });
      }

      for (final key in prefs.getKeys()) {
        if (!key.startsWith(_progressByIdBookKeyPrefix)) {
          continue;
        }

        final bookIdText = key.substring(_progressByIdBookKeyPrefix.length);
        final bookId = int.tryParse(bookIdText);
        final bookJson = prefs.getString(key);
        if (bookId == null || bookJson == null || bookJson.isEmpty) {
          continue;
        }

        final decodedBook = json.decode(bookJson);
        if (decodedBook is Map) {
          progressMap[bookId] = _decodeBookProgress(bookId, decodedBook);
        }
      }

      if (jsonString != null && jsonString.isNotEmpty) {
        for (final entry in progressMap.entries) {
          await _saveBookProgressById(entry.key, entry.value);
        }
        await prefs.remove(_progressByIdLegacyKey);
      }

      for (final change in _pendingChangesById.values) {
        final bookId = change['bookId'] as int;
        final itemIndexKey = change['itemIndexKey'] as String;
        final columnName = change['columnName'] as String;
        final value = change['value'] as bool;
        final bookProgress = progressMap.putIfAbsent(
          bookId,
          () => <String, PageProgress>{},
        );
        bookProgress.putIfAbsent(itemIndexKey, () => PageProgress());
        final pageProgress = bookProgress[itemIndexKey]!;
        pageProgress.setProperty(columnName, value);
        if (pageProgress.isEmpty) {
          bookProgress.remove(itemIndexKey);
          if (bookProgress.isEmpty) {
            progressMap.remove(bookId);
          }
        }
      }

      _logger
          .fine('Loaded progress data for ${progressMap.length} books by ID');
      return progressMap;
    } catch (e, stackTrace) {
      if (e is ShamorZachorError) rethrow;

      _logger.severe('Failed to load progress data by ID: $e');
      throw ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        type: ShamorZachorErrorType.parseError,
        customMessage: 'Failed to load progress data by ID',
      );
    }
  }

  /// Save progress data by book ID.
  Future<void> saveProgressDataById(ProgressMapById data) async {
    try {
      await _processPendingChangesById();
      final prefs = await _getPrefs();

      final existingBookKeys = prefs
          .getKeys()
          .where((key) => key.startsWith(_progressByIdBookKeyPrefix))
          .toList();
      for (final key in existingBookKeys) {
        await prefs.remove(key);
      }

      for (final entry in data.entries) {
        await _saveBookProgressById(entry.key, entry.value);
      }

      await prefs.remove(_progressByIdLegacyKey);
      _logger.fine('Saved progress data for ${data.length} books by ID');
    } catch (e, stackTrace) {
      throw ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        type: ShamorZachorErrorType.storageUnavailable,
        customMessage: 'Failed to save progress data by ID',
      );
    }
  }

  /// Save progress for a single item by book ID with debouncing.
  Future<void> saveProgressById(
    int bookId,
    String itemIndexKey,
    String columnName,
    bool value,
  ) async {
    try {
      final changeKey = '$bookId:$itemIndexKey:$columnName';
      _pendingChangesById[changeKey] = {
        'bookId': bookId,
        'itemIndexKey': itemIndexKey,
        'columnName': columnName,
        'value': value,
      };

      _saveByIdTimer?.cancel();
      _saveByIdTimer = Timer(_saveDelay, _processPendingChangesById);
    } catch (e, stackTrace) {
      throw ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to save progress by ID',
      );
    }
  }

  /// Save all progress for one book ID without touching other books.
  Future<void> saveBookProgressById(
    int bookId,
    Map<String, PageProgress> bookProgress,
  ) async {
    await _processPendingChangesById();
    await _saveBookProgressById(bookId, bookProgress);
  }

  Future<void> _processPendingChangesById() async {
    if (_pendingChangesById.isEmpty) return;

    try {
      final changes = Map<String, dynamic>.from(_pendingChangesById);
      _pendingChangesById.clear();

      final changesByBook = <int, List<Map<String, dynamic>>>{};
      for (final change in changes.values) {
        final bookId = change['bookId'] as int;
        changesByBook.putIfAbsent(bookId, () => <Map<String, dynamic>>[]);
        changesByBook[bookId]!.add(Map<String, dynamic>.from(change));
      }

      for (final entry in changesByBook.entries) {
        final bookId = entry.key;
        final bookProgress = await _loadBookProgressById(bookId);

        for (final change in entry.value) {
          final itemIndexKey = change['itemIndexKey'] as String;
          final columnName = change['columnName'] as String;
          final value = change['value'] as bool;

          bookProgress.putIfAbsent(itemIndexKey, () => PageProgress());
          final currentItemProgress = bookProgress[itemIndexKey]!;
          currentItemProgress.setProperty(columnName, value);
          if (currentItemProgress.isEmpty) {
            bookProgress.remove(itemIndexKey);
          }
        }

        await _saveBookProgressById(bookId, bookProgress);
      }
    } catch (e) {
      _logger.severe('Failed to process pending ID changes: $e');
      rethrow;
    }
  }

  Future<Map<String, PageProgress>> _loadBookProgressById(int bookId) async {
    final prefs = await _getPrefs();
    final bookJson = prefs.getString('$_progressByIdBookKeyPrefix$bookId');
    if (bookJson != null && bookJson.isNotEmpty) {
      final decodedBook = json.decode(bookJson);
      if (decodedBook is Map) {
        return _decodeBookProgress(bookId, decodedBook);
      }
    }

    final legacyJson = prefs.getString(_progressByIdLegacyKey);
    if (legacyJson == null || legacyJson.isEmpty) {
      return <String, PageProgress>{};
    }

    final decoded = json.decode(legacyJson);
    if (decoded is! Map) {
      return <String, PageProgress>{};
    }

    final legacyBook = decoded[bookId.toString()];
    if (legacyBook is Map) {
      return _decodeBookProgress(bookId, legacyBook);
    }

    return <String, PageProgress>{};
  }

  Future<void> _saveBookProgressById(
    int bookId,
    Map<String, PageProgress> bookProgress,
  ) async {
    final prefs = await _getPrefs();
    final key = '$_progressByIdBookKeyPrefix$bookId';

    if (bookProgress.isEmpty) {
      await prefs.remove(key);
      return;
    }

    final Map<String, dynamic> bookProgressJson = {};
    bookProgress.forEach((itemIndex, pageProgress) {
      if (!pageProgress.isEmpty) {
        bookProgressJson[itemIndex] = pageProgress.toJson();
      }
    });

    if (bookProgressJson.isEmpty) {
      await prefs.remove(key);
      return;
    }

    await prefs.setString(key, json.encode(bookProgressJson));
  }

  Map<String, PageProgress> _decodeBookProgress(
    int bookId,
    Map<dynamic, dynamic> bookValue,
  ) {
    final bookProgress = <String, PageProgress>{};
    bookValue.forEach((itemIndexKey, itemProgressValue) {
      if (itemProgressValue is Map) {
        try {
          bookProgress[itemIndexKey.toString()] = PageProgress.fromJson(
            Map<String, dynamic>.from(itemProgressValue),
          );
        } catch (e) {
          _logger.warning(
              'Invalid progress data for book $bookId/$itemIndexKey: $e');
        }
      }
    });
    return bookProgress;
  }

  /// Load completion dates by book ID
  Future<CompletionDatesByIdMap> loadCompletionDatesById() async {
    try {
      final prefs = await _getPrefs();
      final jsonString = prefs.getString('${_keyPrefix}completion_dates_by_id');

      if (jsonString == null || jsonString.isEmpty) {
        return {};
      }

      final Map<String, dynamic> decoded = json.decode(jsonString);
      final CompletionDatesByIdMap datesMap = {};

      decoded.forEach((bookIdKey, dateValue) {
        final bookId = int.parse(bookIdKey);
        if (dateValue is String) {
          datesMap[bookId] = dateValue;
        }
      });

      _logger
          .fine('Loaded completion dates for ${datesMap.length} books by ID');
      return datesMap;
    } catch (e, stackTrace) {
      _logger.severe('Failed to load completion dates by ID: $e');
      throw ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        type: ShamorZachorErrorType.parseError,
        customMessage: 'Failed to load completion dates by ID',
      );
    }
  }

  /// Save completion date for a book by ID
  Future<void> saveCompletionDateById(int bookId, String date) async {
    try {
      final dates = await loadCompletionDatesById();
      dates[bookId] = date;

      final prefs = await _getPrefs();
      final jsonString =
          json.encode(dates.map((k, v) => MapEntry(k.toString(), v)));
      await prefs.setString('${_keyPrefix}completion_dates_by_id', jsonString);

      _logger.fine('Saved completion date for book $bookId');
    } catch (e, stackTrace) {
      throw ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to save completion date by ID',
      );
    }
  }

  /// Save all completion dates by book ID
  Future<void> saveCompletionDatesById(CompletionDatesByIdMap dates) async {
    try {
      final prefs = await _getPrefs();
      final jsonString =
          json.encode(dates.map((k, v) => MapEntry(k.toString(), v)));
      await prefs.setString('${_keyPrefix}completion_dates_by_id', jsonString);
    } catch (e, stackTrace) {
      throw ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to save completion dates by ID',
      );
    }
  }

  List<String> _categoryCandidates(String categoryName) {
    final trimmed = categoryName.trim();
    final candidates = <String>{trimmed};

    final normalized = _legacyCategoryAliases[trimmed];
    if (normalized != null) {
      candidates.add(normalized);
    }

    for (final alias in _legacyCategoryAliases.entries) {
      if (alias.value == trimmed) {
        candidates.add(alias.key);
      }
    }

    return candidates.toList();
  }

  Future<int?> _findBookIdWithCategoryAliases(
    Future<int?> Function(String categoryName, String bookName)
        findBookIdByName,
    String categoryName,
    String bookName,
  ) async {
    for (final candidateCategory in _categoryCandidates(categoryName)) {
      final bookId = await findBookIdByName(candidateCategory, bookName);
      if (bookId != null) {
        return bookId;
      }
    }
    return null;
  }

  /// Migrate old progress data (category+name based) to new format (ID based)
  /// This is a one-time migration that runs automatically on first load
  Future<bool> migrateOldProgressToNewFormat({
    required Future<int?> Function(String categoryName, String bookName)
        findBookIdByName,
  }) async {
    try {
      final prefs = await _getPrefs();

      // Check if migration already completed
      final migrationCompleted =
          prefs.getBool('${_keyPrefix}migration_completed') ?? false;
      if (migrationCompleted) {
        _logger.fine('Migration already completed, skipping');
        return true;
      }

      _logger.info('Starting migration from old to new progress format...');

      // Load old format data
      final oldProgress = await loadFullProgressData();
      final oldCompletionDates = await loadCompletionDates();

      if (oldProgress.isEmpty && oldCompletionDates.isEmpty) {
        _logger.info('No old data to migrate');
        await prefs.setBool('${_keyPrefix}migration_completed', true);
        return true;
      }

      // Load existing new format data (in case of partial migration)
      final newProgress = await loadProgressDataById();
      final newCompletionDates = await loadCompletionDatesById();

      int migratedBooks = 0;
      int failedBooks = 0;
      final List<String> failedBooksList = [];

      // Migrate progress data
      for (final categoryEntry in oldProgress.entries) {
        final categoryName = categoryEntry.key;
        final booksMap = categoryEntry.value;

        for (final bookEntry in booksMap.entries) {
          final bookName = bookEntry.key;
          final progressData = bookEntry.value;

          try {
            // Find book ID in database
            final bookId = await _findBookIdWithCategoryAliases(
              findBookIdByName,
              categoryName,
              bookName,
            );

            if (bookId == null) {
              _logger.warning(
                  'Could not find book ID for: $categoryName / $bookName');
              failedBooks++;
              failedBooksList.add('$categoryName / $bookName');
              continue;
            }

            // Check if already migrated
            if (newProgress.containsKey(bookId) &&
                newProgress[bookId]!.isNotEmpty) {
              _logger.fine('Book $bookName (ID: $bookId) already migrated');
              continue;
            }

            // Migrate progress data
            newProgress[bookId] = progressData;
            migratedBooks++;

            _logger.fine(
                'Migrated progress for: $bookName (ID: $bookId) - ${progressData.length} items');
          } catch (e) {
            _logger.warning('Failed to migrate book: $bookName', e);
            failedBooks++;
            failedBooksList.add('$categoryName / $bookName');
          }
        }
      }

      // Migrate completion dates
      for (final categoryEntry in oldCompletionDates.entries) {
        final categoryName = categoryEntry.key;
        final booksMap = categoryEntry.value;

        for (final bookEntry in booksMap.entries) {
          final bookName = bookEntry.key;
          final completionDate = bookEntry.value;

          try {
            final bookId = await _findBookIdWithCategoryAliases(
              findBookIdByName,
              categoryName,
              bookName,
            );

            if (bookId == null) {
              continue; // Already logged in progress migration
            }

            // Check if already migrated
            if (newCompletionDates.containsKey(bookId)) {
              continue;
            }

            // Migrate completion date
            newCompletionDates[bookId] = completionDate;

            _logger
                .fine('Migrated completion date for: $bookName (ID: $bookId)');
          } catch (e) {
            _logger.warning(
                'Failed to migrate completion date for: $bookName', e);
          }
        }
      }

      // Save migrated data
      await saveProgressDataById(newProgress);
      await prefs.setString(
          '${_keyPrefix}completion_dates_by_id',
          json.encode(
              newCompletionDates.map((k, v) => MapEntry(k.toString(), v))));

      // Mark migration as completed
      await prefs.setBool('${_keyPrefix}migration_completed', true);

      _logger.info(
          'Migration completed: $migratedBooks books migrated, $failedBooks failed');

      if (failedBooksList.isNotEmpty) {
        _logger
            .warning('Failed to migrate books: ${failedBooksList.join(", ")}');
      }

      return true;
    } catch (e, stackTrace) {
      _logger.severe('Migration failed', e, stackTrace);
      throw ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to migrate progress data',
      );
    }
  }

  /// Reset migration flag (for testing purposes)
  Future<void> resetMigrationFlag() async {
    try {
      final prefs = await _getPrefs();
      await prefs.remove('${_keyPrefix}migration_completed');
      _logger.info('Migration flag reset');
    } catch (e) {
      _logger.warning('Failed to reset migration flag', e);
    }
  }

  /// Dispose resources
  void dispose() {
    _saveTimer?.cancel();
    _pendingChanges.clear();
    _saveByIdTimer?.cancel();
    _pendingChangesById.clear();
  }
}
