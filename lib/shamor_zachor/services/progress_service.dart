import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logging/logging.dart';

import '../models/progress_model.dart';
import '../models/book_model.dart';
import '../models/error_model.dart';

/// Service for managing user progress data with optimized storage
class ProgressService {
  static final Logger _logger = Logger('ProgressService');

  // Storage key prefix to avoid conflicts with main app
  static const String _keyPrefix = 'sz:';
  static const String _progressDataKey = '${_keyPrefix}progress_data';
  static const String _completionDatesKey = '${_keyPrefix}completion_dates';
  static const String _lastAccessedKey = '${_keyPrefix}last_accessed';

  // Debouncing for batch saves
  Timer? _saveTimer;
  final Duration _saveDelay = const Duration(milliseconds: 500);
  final Map<String, dynamic> _pendingChanges = {};

  SharedPreferences? _prefs;

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
      if (progress.learn &&
          progress.review1 &&
          progress.review2 &&
          progress.review3) {
        completedItems++;
      } else if (!progress.isEmpty) {
        inProgressItems++;
      }
    }

    bool isActiveReview = false;
    if (totalItems > 0 && completedItems == totalItems) {
      final review1Progress =
          getReviewCompletedPagesCount(bookProgress, 1) / totalItems;
      final review2Progress =
          getReviewCompletedPagesCount(bookProgress, 2) / totalItems;
      final review3Progress =
          getReviewCompletedPagesCount(bookProgress, 3) / totalItems;

      final review1Active = review1Progress > 0 && review1Progress < 1.0;
      final review2Active = review1Progress == 1.0 &&
          review2Progress > 0 &&
          review2Progress < 1.0;
      final review3Active = review1Progress == 1.0 &&
          review2Progress == 1.0 &&
          review3Progress > 0 &&
          review3Progress < 1.0;

      isActiveReview = review1Active || review2Active || review3Active;
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
      default:
        throw ArgumentError('Invalid review number: $reviewNumber');
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

      _pendingChanges.clear();
      _saveTimer?.cancel();

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
      final jsonString = prefs.getString('${_keyPrefix}progress_by_id');

      if (jsonString == null || jsonString.isEmpty) {
        return {};
      }

      final Map<String, dynamic> decoded = json.decode(jsonString);
      final ProgressMapById progressMap = {};

      decoded.forEach((bookIdKey, bookValue) {
        final bookId = int.parse(bookIdKey);
        if (bookValue is Map) {
          progressMap[bookId] = {};
          bookValue.forEach((itemIndexKey, itemProgressValue) {
            if (itemProgressValue is Map) {
              try {
                progressMap[bookId]![itemIndexKey] = PageProgress.fromJson(
                    Map<String, dynamic>.from(itemProgressValue));
              } catch (e) {
                _logger.warning(
                    'Invalid progress data for book $bookId/$itemIndexKey: $e');
              }
            }
          });
        }
      });

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

  /// Save progress data by book ID
  Future<void> saveProgressDataById(ProgressMapById data) async {
    try {
      final prefs = await _getPrefs();

      // המרה ידנית ל-JSON כי PageProgress לא ממיר אוטומטית
      final Map<String, dynamic> jsonData = {};
      data.forEach((bookId, progressMap) {
        final Map<String, dynamic> bookProgressJson = {};
        progressMap.forEach((itemIndex, pageProgress) {
          bookProgressJson[itemIndex] = pageProgress.toJson();
        });
        jsonData[bookId.toString()] = bookProgressJson;
      });

      final jsonString = json.encode(jsonData);
      await prefs.setString('${_keyPrefix}progress_by_id', jsonString);
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
      final jsonString = json.encode(dates);
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

  /// Dispose resources
  void dispose() {
    _saveTimer?.cancel();
    _pendingChanges.clear();
  }
}
