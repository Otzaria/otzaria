import 'dart:async';
import 'dart:convert';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:logging/logging.dart';

import '../models/progress_model.dart';
import '../models/book_model.dart';
import '../models/error_model.dart';

/// Service for managing user progress data with optimized storage.
/// All progress is keyed by book ID.
class ProgressService {
  static final Logger _logger = Logger('ProgressService');

  static const String _keyPrefix = 'sz:';
  static const String _progressByIdKey = '${_keyPrefix}progress_by_id';
  static const String _completionDatesByIdKey =
      '${_keyPrefix}completion_dates_by_id';
  static const String _lastAccessedKey = '${_keyPrefix}last_accessed';
  static const String _bookColumnsKey = '${_keyPrefix}book_columns';

  /// טוען את הגדרות העמודות המותאמות לכל ספר (bookId → רשימת עמודות).
  /// ספר שאינו מופיע יקבל את עמודות ברירת המחדל בשכבת ה-Provider.
  Future<Map<int, List<ProgressColumn>>> loadColumnsByBookId() async {
    try {
      final jsonString = Settings.getValue<String>(_bookColumnsKey);
      if (jsonString == null || jsonString.isEmpty) return {};

      final Map<String, dynamic> decoded = json.decode(jsonString);
      final result = <int, List<ProgressColumn>>{};
      decoded.forEach((bookIdKey, value) {
        if (value is List) {
          result[int.parse(bookIdKey)] = value
              .whereType<Map>()
              .map((e) => ProgressColumn.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      });
      return result;
    } catch (e, stackTrace) {
      _logger.warning('Failed to load book columns', e, stackTrace);
      return {};
    }
  }

  /// שומר את הגדרות העמודות המותאמות לכל ספר.
  Future<void> saveColumnsByBookId(
    Map<int, List<ProgressColumn>> columnsByBookId,
  ) async {
    try {
      final jsonData = columnsByBookId.map(
        (bookId, columns) => MapEntry(
          bookId.toString(),
          columns.map((c) => c.toJson()).toList(),
        ),
      );
      await Settings.setValue<String>(_bookColumnsKey, json.encode(jsonData));
    } catch (e, stackTrace) {
      throw ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        type: ShamorZachorErrorType.storageUnavailable,
        customMessage: 'Failed to save book columns',
      );
    }
  }

  /// Load progress data by book ID
  Future<ProgressMapById> loadProgressDataById() async {
    try {
      final jsonString = Settings.getValue<String>(_progressByIdKey);

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
                  Map<String, dynamic>.from(itemProgressValue),
                );
              } catch (e) {
                _logger.warning(
                  'Invalid progress data for book $bookId/$itemIndexKey: $e',
                );
              }
            }
          });
        }
      });

      _logger.fine(
        'Loaded progress data for ${progressMap.length} books by ID',
      );
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
      final Map<String, dynamic> jsonData = {};
      data.forEach((bookId, progressMap) {
        final Map<String, dynamic> bookProgressJson = {};
        progressMap.forEach((itemIndex, pageProgress) {
          bookProgressJson[itemIndex] = pageProgress.toJson();
        });
        jsonData[bookId.toString()] = bookProgressJson;
      });

      final jsonString = json.encode(jsonData);
      await Settings.setValue<String>(_progressByIdKey, jsonString);
      await _updateLastAccessed();
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
      final jsonString = Settings.getValue<String>(_completionDatesByIdKey);

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

      _logger.fine(
        'Loaded completion dates for ${datesMap.length} books by ID',
      );
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
      await saveCompletionDatesById(dates);
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
      final jsonString = json.encode(
        dates.map((k, v) => MapEntry(k.toString(), v)),
      );
      await Settings.setValue<String>(_completionDatesByIdKey, jsonString);
    } catch (e, stackTrace) {
      throw ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to save completion dates by ID',
      );
    }
  }

  /// Build a book progress summary from in-memory progress data.
  ///
  /// [columns] רשימת מזהי העמודות של הספר. פריט נחשב "הושלם" כשכל העמודות
  /// מסומנות בו; ספר "במחזור פעיל" כשעמודה אחת הושלמה ואחרת בתהליך חלקי.
  BookProgressSummary buildBookProgressSummary(
    String categoryName,
    String bookName,
    BookDetails bookDetails,
    Map<String, PageProgress> bookProgress, {
    String? completionDate,
    DateTime? lastAccessed,
    required List<String> columns,
  }) {
    final totalItems = bookDetails.totalLearnableItems;
    int completedItems = 0;
    int inProgressItems = 0;

    for (final progress in bookProgress.values) {
      if (progress.isCompleteFor(columns)) {
        completedItems++;
      } else if (!progress.isEmpty) {
        inProgressItems++;
      }
    }

    bool isActiveReview = false;
    if (totalItems > 0 && columns.length > 1) {
      int fullyDoneColumns = 0;
      bool anyPartialColumn = false;
      for (final columnId in columns) {
        final count = getColumnCompletedCount(bookProgress, columnId);
        if (count >= totalItems) {
          fullyDoneColumns++;
        } else if (count > 0) {
          anyPartialColumn = true;
        }
      }
      isActiveReview = fullyDoneColumns >= 1 && anyPartialColumn;
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

  /// סופר כמה פריטים מסומנים בעמודה נתונה
  static int getColumnCompletedCount(
    Map<String, PageProgress> bookProgress,
    String columnId,
  ) {
    return bookProgress.values
        .where((progress) => progress.getProperty(columnId))
        .length;
  }

  /// Update last accessed timestamp
  Future<void> _updateLastAccessed() async {
    try {
      await Settings.setValue<String>(
        _lastAccessedKey,
        DateTime.now().toIso8601String(),
      );
    } catch (e) {
      _logger.fine('Failed to update last accessed: $e');
    }
  }

  /// Export all progress data
  Future<String> exportProgressData() async {
    try {
      final progressJsonString = Settings.getValue<String>(_progressByIdKey);
      final completionDatesJsonString = Settings.getValue<String>(
        _completionDatesByIdKey,
      );
      final bookColumnsJsonString = Settings.getValue<String>(_bookColumnsKey);

      final Map<String, String?> dataToExport = {
        'progress_by_id': progressJsonString,
        'completion_dates_by_id': completionDatesJsonString,
        'book_columns': bookColumnsJsonString,
        'export_timestamp': DateTime.now().toIso8601String(),
        'schema_version': '3',
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
      final Map<String, dynamic> decodedData = json.decode(jsonData);

      final String? progressByIdString =
          decodedData['progress_by_id'] as String?;
      final String? completionDatesByIdString =
          decodedData['completion_dates_by_id'] as String?;
      final String? bookColumnsString = decodedData['book_columns'] as String?;

      await Settings.setValue<String>(
        _progressByIdKey,
        progressByIdString ?? '{}',
      );
      await Settings.setValue<String>(
        _completionDatesByIdKey,
        completionDatesByIdString ?? '{}',
      );
      await Settings.setValue<String>(
        _bookColumnsKey,
        bookColumnsString ?? '{}',
      );

      _logger.info('Successfully imported progress data');
      return true;
    } catch (e, stackTrace) {
      _logger.severe('Failed to import progress data: $e\n$stackTrace');

      try {
        await Settings.setValue<String>(_progressByIdKey, '{}');
        await Settings.setValue<String>(_completionDatesByIdKey, '{}');
      } catch (resetError) {
        _logger.severe(
          'Failed to reset progress data after import failure: $resetError',
        );
      }

      return false;
    }
  }

  /// Clear all progress data
  Future<void> clearAllProgress() async {
    try {
      await Settings.setValue<String?>(_progressByIdKey, null);
      await Settings.setValue<String?>(_completionDatesByIdKey, null);
      await Settings.setValue<String?>(_bookColumnsKey, null);
      await Settings.setValue<String?>(_lastAccessedKey, null);

      _logger.info('Cleared all progress data');
    } catch (e, stackTrace) {
      throw ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to clear progress data',
      );
    }
  }

  void dispose() {}
}
