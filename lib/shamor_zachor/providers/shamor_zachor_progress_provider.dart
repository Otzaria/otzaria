import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../models/progress_model.dart';
import '../models/book_model.dart';
import '../models/error_model.dart';
import '../services/progress_service.dart';
import '../utils/message_utils.dart';

/// Events emitted when significant progress milestones are reached
enum CompletionEventType {
  bookCompleted,
  reviewCycleCompleted,
}

class CompletionEvent {
  final CompletionEventType type;
  final String? bookName;
  final String? categoryName;
  final int? reviewCycleNumber;

  const CompletionEvent(
    this.type, {
    this.bookName,
    this.categoryName,
    this.reviewCycleNumber,
  });

  @override
  String toString() {
    return 'CompletionEvent(type: $type, book: $bookName, category: $categoryName, review: $reviewCycleNumber)';
  }
}

/// Provider for managing user progress in Shamor Zachor
/// This provider is scoped locally within the ShamorZachorWidget
class ShamorZachorProgressProvider with ChangeNotifier {
  static final Logger _logger = Logger('ShamorZachorProgressProvider');

  final ProgressService _progressService;
  FullProgressMap _fullProgress = {};
  CompletionDatesMap _completionDates = {};

  // NEW: Progress data by book ID
  ProgressMapById _progressById = {};
  CompletionDatesByIdMap _completionDatesById = {};

  final Map<String, BookProgressSummary> _progressSummaryCache = {};
  bool _isLoading = false;
  ShamorZachorError? _error;

  // Column names for progress tracking
  static const String learnColumn = 'learn';
  static const String review1Column = 'review1';
  static const String review2Column = 'review2';
  static const String review3Column = 'review3';
  static const List<String> allColumnNames = [
    learnColumn,
    review1Column,
    review2Column,
    review3Column,
  ];

  // Stream for completion events
  final _completionEventController =
      StreamController<CompletionEvent>.broadcast();
  Stream<CompletionEvent> get completionEvents =>
      _completionEventController.stream;

  /// Check if data is currently loading
  bool get isLoading => _isLoading;

  /// Get current error, if any
  ShamorZachorError? get error => _error;

  /// Check if progress data has been loaded
  bool get hasData => _fullProgress.isNotEmpty;

  String _summaryCacheKey(
    String categoryName,
    String bookName,
    int totalItems,
  ) =>
      '$categoryName::$bookName::$totalItems';

  void _invalidateSummaryCache(
      String categoryName, String bookName, int totalItems) {
    _progressSummaryCache
        .remove(_summaryCacheKey(categoryName, bookName, totalItems));
  }

  void _clearSummaryCache() {
    _progressSummaryCache.clear();
  }

  ShamorZachorProgressProvider({ProgressService? progressService})
      : _progressService = progressService ?? ProgressService() {
    _loadInitialProgress();
  }

  /// Load initial progress data
  Future<void> _loadInitialProgress() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Load old format (for backward compatibility)
      _fullProgress = await _progressService.loadFullProgressData();
      _completionDates = await _progressService.loadCompletionDates();

      // Load new format (by ID)
      _progressById = await _progressService.loadProgressDataById();
      _completionDatesById = await _progressService.loadCompletionDatesById();

      _logger.info(
          'Successfully loaded progress: ${_fullProgress.length} categories (old), ${_progressById.length} books (new)');
    } catch (e, stackTrace) {
      if (e is ShamorZachorError) {
        _error = e;
      } else {
        _error = ShamorZachorError.fromException(
          e,
          stackTrace: stackTrace,
          customMessage: 'Failed to load progress data',
        );
      }
      _logger.severe(
          'Error loading progress: ${_error!.message}', e, stackTrace);
    }

    _clearSummaryCache();
    _isLoading = false;
    notifyListeners();
  }

  /// Get progress data for a specific book
  Map<String, PageProgress> getProgressForBook(
      String categoryName, String bookName) {
    return _fullProgress[categoryName]?[bookName] ?? {};
  }

  /// Get progress data for a specific book by ID
  Map<String, PageProgress> getProgressForBookById(int bookId) {
    final progress = _progressById[bookId] ?? {};
    _logger.info(
        'getProgressForBookById($bookId): returning ${progress.length} items. _progressById has ${_progressById.length} books total. Keys: ${_progressById.keys.toList()}');
    return progress;
  }

  /// Get progress for a specific item
  PageProgress getProgressForItem(
      String categoryName, String bookName, int absoluteIndex) {
    return _fullProgress[categoryName]?[bookName]?[absoluteIndex.toString()] ??
        PageProgress();
  }

  /// Update progress for a single item
  Future<void> updateProgress(
    String categoryName,
    String bookName,
    int absoluteIndex,
    String columnName,
    bool value,
    BookDetails bookDetails, {
    bool isBulkUpdate = false,
  }) async {
    try {
      final itemIndexKey = absoluteIndex.toString();

      // בדיקה: אם מנסים לסמן חזרה, צריך שהלימוד הקודם יהיה מסומן
      if (value && !isBulkUpdate) {
        final currentProgress =
            getProgressForItem(categoryName, bookName, absoluteIndex);

        // אם מנסים לסמן review1, צריך שlearn יהיה מסומן
        if (columnName == 'review1' && !currentProgress.learn) {
          UiSnack.show('יש לסמן תחילה את הלימוד הראשוני');
          return;
        }
        // אם מנסים לסמן review2, צריך שlearn ו-review1 יהיו מסומנים
        else if (columnName == 'review2' &&
            (!currentProgress.learn || !currentProgress.review1)) {
          if (!currentProgress.learn) {
            UiSnack.show('יש לסמן תחילה את הלימוד הראשוני');
          } else {
            UiSnack.show('יש לסמן תחילה את החזרה הראשונה');
          }
          return;
        }
        // אם מנסים לסמן review3, צריך שכל המחזורים הקודמים יהיו מסומנים
        else if (columnName == 'review3' &&
            (!currentProgress.learn ||
                !currentProgress.review1 ||
                !currentProgress.review2)) {
          if (!currentProgress.learn) {
            UiSnack.show('יש לסמן תחילה את הלימוד הראשוני');
          } else if (!currentProgress.review1) {
            UiSnack.show('יש לסמן תחילה את החזרה הראשונה');
          } else {
            UiSnack.show('יש לסמן תחילה את החזרה השנייה');
          }
          return;
        }
      }

      // Save to storage (with debouncing)
      await _progressService.saveProgress(
        categoryName,
        bookName,
        itemIndexKey,
        columnName,
        value,
      );

      // Update local state
      _fullProgress.putIfAbsent(categoryName, () => {});
      _fullProgress[categoryName]!.putIfAbsent(bookName, () => {});
      _fullProgress[categoryName]![bookName]!
          .putIfAbsent(itemIndexKey, () => PageProgress());

      final pageProgress =
          _fullProgress[categoryName]![bookName]![itemIndexKey]!;
      pageProgress.setProperty(columnName, value);

      // Clean up empty entries
      if (pageProgress.isEmpty) {
        _fullProgress[categoryName]![bookName]!.remove(itemIndexKey);
        if (_fullProgress[categoryName]![bookName]!.isEmpty) {
          _fullProgress[categoryName]!.remove(bookName);
          if (_fullProgress[categoryName]!.isEmpty) {
            _fullProgress.remove(categoryName);
          }
        }
      }

      _invalidateSummaryCache(
          categoryName, bookName, bookDetails.totalLearnableItems);

      // Handle completion events (only for non-bulk updates)
      if (value && !isBulkUpdate) {
        await _handleCompletionEvents(
            categoryName, bookName, columnName, bookDetails);
      }

      if (!isBulkUpdate) {
        notifyListeners();
      }
    } catch (e, stackTrace) {
      _error = ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to update progress',
      );
      _logger.severe(
          'Error updating progress: ${_error!.message}', e, stackTrace);
      notifyListeners();
    }
  }

  /// Handle completion events when progress is updated
  Future<void> _handleCompletionEvents(
    String categoryName,
    String bookName,
    String columnName,
    BookDetails bookDetails,
  ) async {
    _invalidateSummaryCache(
        categoryName, bookName, bookDetails.totalLearnableItems);

    if (columnName == learnColumn) {
      final wasAlreadyCompleted =
          getCompletionDateSync(categoryName, bookName) != null;
      final isNowComplete =
          isBookCompleted(categoryName, bookName, bookDetails);

      if (isNowComplete && !wasAlreadyCompleted) {
        await _progressService.saveCompletionDate(categoryName, bookName);
        _completionDates = await _progressService.loadCompletionDates();
        _invalidateSummaryCache(
            categoryName, bookName, bookDetails.totalLearnableItems);

        _completionEventController.add(CompletionEvent(
          CompletionEventType.bookCompleted,
          bookName: bookName,
          categoryName: categoryName,
        ));
      }
    } else if (columnName.startsWith('review')) {
      int? reviewCycleNumber;
      switch (columnName) {
        case review1Column:
          reviewCycleNumber = 1;
          break;
        case review2Column:
          reviewCycleNumber = 2;
          break;
        case review3Column:
          reviewCycleNumber = 3;
          break;
      }

      if (reviewCycleNumber != null) {
        final cycleJustCompleted = _isReviewCycleCompleted(
          categoryName,
          bookName,
          reviewCycleNumber,
          bookDetails,
        );

        if (cycleJustCompleted) {
          _invalidateSummaryCache(
              categoryName, bookName, bookDetails.totalLearnableItems);
          _completionEventController.add(CompletionEvent(
            CompletionEventType.reviewCycleCompleted,
            bookName: bookName,
            categoryName: categoryName,
            reviewCycleNumber: reviewCycleNumber,
          ));
        }
      }
    }
  }

  /// Toggle selection for all items in a column (bulk operation)
  Future<void> toggleSelectAllForColumn(
    String categoryName,
    String bookName,
    BookDetails bookDetails,
    String columnName,
    bool select,
  ) async {
    if (!allColumnNames.contains(columnName)) {
      _logger.warning('Invalid column name: $columnName');
      return;
    }

    try {
      _logger.info(
          'Bulk ${select ? 'selecting' : 'deselecting'} $columnName for $bookName');

      // Update all items
      for (final item in bookDetails.learnableItems) {
        await updateProgress(
          categoryName,
          bookName,
          item.absoluteIndex,
          columnName,
          select,
          bookDetails,
          isBulkUpdate: true,
        );
      }

      // Handle completion for learn column
      if (select && columnName == learnColumn) {
        final wasAlreadyCompleted =
            getCompletionDateSync(categoryName, bookName) != null;
        final isNowComplete =
            isBookCompleted(categoryName, bookName, bookDetails);

        if (isNowComplete && !wasAlreadyCompleted) {
          await _progressService.saveCompletionDate(categoryName, bookName);
          _completionDates = await _progressService.loadCompletionDates();
        }
      }

      notifyListeners();
    } catch (e, stackTrace) {
      _error = ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to bulk update column',
      );
      _logger.severe('Error in bulk update: ${_error!.message}', e, stackTrace);
      notifyListeners();
    }
  }

  /// Toggle selection for a specific section (group of items)
  Future<void> toggleSectionColumn(
    String categoryName,
    String bookName,
    BookDetails bookDetails,
    String sectionId,
    String columnName,
    bool select,
  ) async {
    final indices = bookDetails.sectionLeafIndexMap[sectionId] ?? const [];
    if (indices.isEmpty) {
      _logger.fine('No leaf indices found for section $sectionId');
      return;
    }

    try {
      for (final index in indices) {
        await updateProgress(
          categoryName,
          bookName,
          index,
          columnName,
          select,
          bookDetails,
          isBulkUpdate: true,
        );
      }

      if (select && columnName == learnColumn) {
        final wasAlreadyCompleted =
            getCompletionDateSync(categoryName, bookName) != null;
        final isNowComplete =
            isBookCompleted(categoryName, bookName, bookDetails);

        if (isNowComplete && !wasAlreadyCompleted) {
          await _progressService.saveCompletionDate(categoryName, bookName);
          _completionDates = await _progressService.loadCompletionDates();
        }
      }

      notifyListeners();
    } catch (e, stackTrace) {
      _error = ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to update section progress',
      );
      _logger.severe(
          'Error updating section: ${_error!.message}', e, stackTrace);
      notifyListeners();
    }
  }

  /// Get completion date for a book (synchronous)
  String? getCompletionDateSync(String categoryName, String bookName) {
    return _completionDates[categoryName]?[bookName];
  }

  /// Get completion date for a book by ID (synchronous)
  String? getCompletionDateSyncById(int bookId) {
    return _completionDatesById[bookId];
  }

  /// Clear all progress for a specific book
  Future<void> clearBookProgress(
    String categoryName,
    String bookName,
    BookDetails bookDetails,
  ) async {
    try {
      await _progressService.saveAllBookAsLearned(
        categoryName,
        bookName,
        bookDetails,
        false,
      );

      _fullProgress[categoryName]?.remove(bookName);
      if (_fullProgress[categoryName]?.isEmpty ?? false) {
        _fullProgress.remove(categoryName);
      }

      _completionDates[categoryName]?.remove(bookName);
      if (_completionDates[categoryName]?.isEmpty ?? false) {
        _completionDates.remove(categoryName);
      }

      notifyListeners();
    } catch (e, stackTrace) {
      _error = ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to clear book progress',
      );
      _logger.severe(
          'Error clearing progress: ${_error!.message}', e, stackTrace);
      notifyListeners();
    }
  }

  /// Get tristate selection state for a section and column
  bool? getSectionColumnState(
    String categoryName,
    String bookName,
    BookDetails bookDetails,
    String sectionId,
    String columnName,
  ) {
    final indices = bookDetails.sectionLeafIndexMap[sectionId] ?? const [];
    if (indices.isEmpty) {
      return false;
    }

    bool anySelected = false;
    bool anyUnselected = false;

    for (final index in indices) {
      final progress = getProgressForItem(categoryName, bookName, index);
      final value = progress.getProperty(columnName);
      if (value) {
        anySelected = true;
      } else {
        anyUnselected = true;
      }
      if (anySelected && anyUnselected) {
        return null; // partial
      }
    }

    if (anySelected) {
      return true;
    }
    return false;
  }

  /// Check if a book is completed (all items learned)
  bool isBookCompleted(
      String categoryName, String bookName, BookDetails bookDetails) {
    final bookProgress = getProgressForBook(categoryName, bookName);
    final totalTargetItems = bookDetails.totalLearnableItems;
    if (totalTargetItems == 0) return false;

    final learnedItemsCount =
        ProgressService.getCompletedPagesCount(bookProgress);
    return learnedItemsCount >= totalTargetItems;
  }

  /// Check if a review cycle is completed
  bool _isReviewCycleCompleted(
    String categoryName,
    String bookName,
    int reviewCycleNumber,
    BookDetails bookDetails,
  ) {
    final bookProgress = getProgressForBook(categoryName, bookName);
    final totalItems = bookDetails.totalLearnableItems;
    if (totalItems == 0 || bookProgress.isEmpty) return false;

    final completedItemsInCycle = ProgressService.getReviewCompletedPagesCount(
      bookProgress,
      reviewCycleNumber,
    );

    return completedItemsInCycle >= totalItems;
  }

  /// Get column selection states (all/none/partial)
  Map<String, bool?> getColumnSelectionStates(
    String categoryName,
    String bookName,
    BookDetails? bookDetails,
  ) {
    final columnStates = <String, bool?>{
      learnColumn: null,
      review1Column: null,
      review2Column: null,
      review3Column: null,
    };

    if (bookDetails == null) return columnStates;

    final bookProgress = _fullProgress[categoryName]?[bookName];
    final totalItems = bookDetails.totalLearnableItems;

    if (totalItems == 0) {
      columnStates.updateAll((key, value) => false);
      return columnStates;
    }

    for (final currentColumnName in allColumnNames) {
      int itemsChecked = 0;
      if (bookProgress != null) {
        for (final item in bookDetails.learnableItems) {
          final itemProgress = bookProgress[item.absoluteIndex.toString()];
          if (itemProgress?.getProperty(currentColumnName) ?? false) {
            itemsChecked++;
          }
        }
      }

      if (itemsChecked == 0) {
        columnStates[currentColumnName] = false;
      } else if (itemsChecked == totalItems) {
        columnStates[currentColumnName] = true;
      } else {
        columnStates[currentColumnName] = null; // Partial selection
      }
    }

    return columnStates;
  }

  /// Get progress percentage for learning
  double getLearnProgressPercentage(
      String categoryName, String bookName, BookDetails bookDetails) {
    final bookProgress = getProgressForBook(categoryName, bookName);
    final totalTargetItems = bookDetails.totalLearnableItems;
    if (totalTargetItems == 0) return 0.0;

    final learnedPagesCount =
        ProgressService.getCompletedPagesCount(bookProgress);
    return learnedPagesCount / totalTargetItems;
  }

  /// Get progress percentage for a specific review
  double getReviewProgressPercentage(
    String categoryName,
    String bookName,
    BookDetails bookDetails,
    int reviewNumber,
  ) {
    final bookProgress = getProgressForBook(categoryName, bookName);
    final totalTargetItems = bookDetails.totalLearnableItems;
    if (totalTargetItems == 0) return 0.0;

    final reviewPagesCount = ProgressService.getReviewCompletedPagesCount(
      bookProgress,
      reviewNumber,
    );
    return reviewPagesCount / totalTargetItems;
  }

  /// Get number of completed cycles (learn + reviews)
  int getNumberOfCompletedCycles(
      String categoryName, String bookName, BookDetails bookDetails) {
    final bookProgress = getProgressForBook(categoryName, bookName);
    final totalTargetItems = bookDetails.totalLearnableItems;
    if (totalTargetItems == 0) return 0;

    int cycles = 0;

    if (ProgressService.getCompletedPagesCount(bookProgress) >=
        totalTargetItems) {
      cycles++;
    }
    for (int i = 1; i <= 3; i++) {
      if (ProgressService.getReviewCompletedPagesCount(bookProgress, i) >=
          totalTargetItems) {
        cycles++;
      }
    }

    return cycles;
  }

  /// Check if book is in active review (completed but not all reviews done)
  /// Check if book is considered in progress
  bool isBookConsideredInProgress(
      String categoryName, String bookName, BookDetails bookDetails) {
    final bookProgressData = getProgressForBook(categoryName, bookName);
    if (bookProgressData.isEmpty) {
      return false;
    }

    final learnProgress =
        getLearnProgressPercentage(categoryName, bookName, bookDetails);
    if (learnProgress > 0 && learnProgress < 1.0) return true;

    // Check review progress
    for (int i = 1; i <= 3; i++) {
      final reviewProgress =
          getReviewProgressPercentage(categoryName, bookName, bookDetails, i);
      if (reviewProgress > 0 && reviewProgress < 1.0) return true;
    }

    return false;
  }

  /// Get book progress summary (synchronous)
  BookProgressSummary getBookProgressSummarySync(
    String categoryName,
    String bookName,
    BookDetails bookDetails,
  ) {
    final totalItems = bookDetails.totalLearnableItems;
    final cacheKey = _summaryCacheKey(categoryName, bookName, totalItems);
    final cached = _progressSummaryCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final bookProgress = getProgressForBook(categoryName, bookName);
    final completionDate = getCompletionDateSync(categoryName, bookName);
    final summary = _progressService.buildBookProgressSummary(
      categoryName,
      bookName,
      bookDetails,
      bookProgress,
      completionDate: completionDate,
    );
    _progressSummaryCache[cacheKey] = summary;
    return summary;
  }

  /// Get book progress summary
  Future<BookProgressSummary> getBookProgressSummary(
    String categoryName,
    String bookName,
    BookDetails bookDetails,
  ) async {
    final totalItems = bookDetails.totalLearnableItems;
    final cacheKey = _summaryCacheKey(categoryName, bookName, totalItems);

    try {
      final serviceSummary = await _progressService.getBookProgressSummary(
        categoryName,
        bookName,
        bookDetails,
      );
      final localSummary =
          getBookProgressSummarySync(categoryName, bookName, bookDetails);
      final mergedSummary = serviceSummary.copyWith(
        totalItems: localSummary.totalItems,
        completedItems: localSummary.completedItems,
        inProgressItems: localSummary.inProgressItems,
        completionDate: localSummary.completionDate,
        isActiveReview: localSummary.isActiveReview,
      );
      _progressSummaryCache[cacheKey] = mergedSummary;
      return mergedSummary;
    } catch (e, stackTrace) {
      _logger.warning(
        'Failed to get progress summary for $categoryName/$bookName: $e\n$stackTrace',
      );

      // Fallback to local calculation
      final summary = getBookProgressSummarySync(
        categoryName,
        bookName,
        bookDetails,
      );
      _progressSummaryCache[cacheKey] = summary;
      return summary;
    }
  }

  /// Get all tracked books with progress
  List<Map<String, dynamic>> getTrackedBooks(
      Map<String, BookCategory> allBookData) {
    final tracked = <Map<String, dynamic>>[];
    final processedBookKeys = <String>{};

    // Process progress data
    _fullProgress.forEach((topLevelCategoryKey, booksProgressMap) {
      final topLevelCategoryObject = allBookData[topLevelCategoryKey];
      if (topLevelCategoryObject == null) return;

      booksProgressMap.forEach((bookNameFromProgress, progressDataForBook) {
        final searchResult =
            topLevelCategoryObject.findBookRecursive(bookNameFromProgress);
        if (searchResult != null) {
          final uniqueKey =
              '$topLevelCategoryKey-${searchResult.categoryName}-$bookNameFromProgress';
          if (!processedBookKeys.contains(uniqueKey)) {
            final entry = <String, dynamic>{
              'topLevelCategoryKey': topLevelCategoryKey,
              'displayCategoryName': searchResult.categoryName,
              'bookName': bookNameFromProgress,
              'bookDetails': searchResult.bookDetails,
              'bookProgressData': progressDataForBook,
            };

            final completionDate = getCompletionDateSync(
              topLevelCategoryKey,
              bookNameFromProgress,
            );
            if (completionDate != null) {
              entry['completionDate'] = completionDate;
            }

            tracked.add(entry);
            processedBookKeys.add(uniqueKey);
          }
        }
      });
    });

    // Process completion dates
    _completionDates.forEach((topLevelCategoryKey, booksCompletionMap) {
      final topLevelCategoryObject = allBookData[topLevelCategoryKey];
      if (topLevelCategoryObject == null) return;

      booksCompletionMap.forEach((bookNameFromCompletion, completionDate) {
        final searchResult =
            topLevelCategoryObject.findBookRecursive(bookNameFromCompletion);
        if (searchResult != null) {
          final uniqueKey =
              '$topLevelCategoryKey-${searchResult.categoryName}-$bookNameFromCompletion';

          if (!processedBookKeys.contains(uniqueKey)) {
            tracked.add({
              'topLevelCategoryKey': topLevelCategoryKey,
              'displayCategoryName': searchResult.categoryName,
              'bookName': bookNameFromCompletion,
              'bookDetails': searchResult.bookDetails,
              'bookProgressData': getProgressForBook(
                  topLevelCategoryKey, bookNameFromCompletion),
              'completionDate': completionDate,
            });
            processedBookKeys.add(uniqueKey);
          } else {
            // Add completion date to existing entry
            final existingEntry = tracked.firstWhere((item) =>
                item['topLevelCategoryKey'] == topLevelCategoryKey &&
                item['displayCategoryName'] == searchResult.categoryName &&
                item['bookName'] == bookNameFromCompletion);
            existingEntry['completionDate'] = completionDate;
          }
        }
      });
    });

    return tracked;
  }

  (List<Map<String, dynamic>>, List<Map<String, dynamic>>)
      getCategorizedTrackedBooks(
    Map<String, BookCategory> allBookData,
  ) {
    final trackedItems = getTrackedBooks(allBookData);
    return _categorizeTrackedItems(trackedItems);
  }

  (List<Map<String, dynamic>>, List<Map<String, dynamic>>)
      _categorizeTrackedItems(
    List<Map<String, dynamic>> trackedItems,
  ) {
    final inProgressItems = <Map<String, dynamic>>[];
    final completedItems = <Map<String, dynamic>>[];
    final processedBooks = <String>{};

    for (final item in trackedItems) {
      final topLevelCategoryKey = item['topLevelCategoryKey'] as String;
      final bookName = item['bookName'] as String;
      final bookDetails = item['bookDetails'] as BookDetails;

      final uniqueKey = '$topLevelCategoryKey:$bookName';
      if (!processedBooks.add(uniqueKey)) {
        continue;
      }

      final bookProgressData =
          (item['bookProgressData'] as Map<String, PageProgress>?) ??
              getProgressForBook(topLevelCategoryKey, bookName);

      final cardData = <String, dynamic>{
        'topLevelCategoryKey': topLevelCategoryKey,
        'displayCategoryName': item['displayCategoryName'],
        'bookName': bookName,
        'bookDetails': bookDetails,
        'bookProgressData': bookProgressData,
        'completionDate': item['completionDate'],
      };

      final isCompleted = isBookCompleted(
        topLevelCategoryKey,
        bookName,
        bookDetails,
      );

      final isInProgress = isBookConsideredInProgress(
        topLevelCategoryKey,
        bookName,
        bookDetails,
      );

      if (isCompleted) {
        completedItems.add(cardData);
      } else if (isInProgress) {
        inProgressItems.add(cardData);
      }
    }

    completedItems.sort((a, b) {
      final dateA = a['completionDate'] as String?;
      final dateB = b['completionDate'] as String?;

      if (dateA == null && dateB == null) return 0;
      if (dateA == null) return 1;
      if (dateB == null) return -1;

      final parsedA = DateTime.tryParse(dateA);
      final parsedB = DateTime.tryParse(dateB);

      if (parsedA == null && parsedB == null) {
        _logger.warning('Failed to parse completion dates: $dateA, $dateB');
        return dateB.compareTo(dateA);
      }
      if (parsedA == null) {
        _logger.warning('Failed to parse completion date: $dateA');
        return 1;
      }
      if (parsedB == null) {
        _logger.warning('Failed to parse completion date: $dateB');
        return -1;
      }
      return parsedB.compareTo(parsedA);
    });

    inProgressItems.sort((a, b) {
      final progressA = getLearnProgressPercentage(
        a['topLevelCategoryKey'] as String,
        a['bookName'] as String,
        a['bookDetails'] as BookDetails,
      );
      final progressB = getLearnProgressPercentage(
        b['topLevelCategoryKey'] as String,
        b['bookName'] as String,
        b['bookDetails'] as BookDetails,
      );
      return progressB.compareTo(progressA);
    });

    return (inProgressItems, completedItems);
  }

  /// Export progress data
  Future<String?> exportProgressData() async {
    try {
      return await _progressService.exportProgressData();
    } catch (e, stackTrace) {
      _error = ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to export progress data',
      );
      _logger.severe(
          'Error exporting progress: ${_error!.message}', e, stackTrace);
      notifyListeners();
      return null;
    }
  }

  /// Import progress data
  Future<bool> importProgressData(String jsonData) async {
    try {
      final success = await _progressService.importProgressData(jsonData);
      if (success) {
        await _loadInitialProgress();
      }
      return success;
    } catch (e, stackTrace) {
      _error = ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to import progress data',
      );
      _logger.severe(
          'Error importing progress: ${_error!.message}', e, stackTrace);
      notifyListeners();
      return false;
    }
  }

  /// Clear all progress data
  Future<void> clearAllProgress() async {
    try {
      await _progressService.clearAllProgress();
      _fullProgress.clear();
      _completionDates.clear();
      _clearSummaryCache();
      notifyListeners();
    } catch (e, stackTrace) {
      _error = ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to clear progress data',
      );
      _logger.severe(
          'Error clearing progress: ${_error!.message}', e, stackTrace);
      notifyListeners();
    }
  }

  /// Clear error state
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ============================================================================
  // NEW: Functions that work with book ID
  // ============================================================================

  /// Get progress for a specific item by book ID
  PageProgress getProgressForItemById(int bookId, int absoluteIndex) {
    return _progressById[bookId]?[absoluteIndex.toString()] ?? PageProgress();
  }

  /// Update progress for a single item by book ID
  Future<void> updateProgressById(
    int bookId,
    int absoluteIndex,
    String columnName,
    bool value,
    BookDetails bookDetails,
  ) async {
    try {
      _logger.info(
          'updateProgressById called: bookId=$bookId, absoluteIndex=$absoluteIndex, columnName=$columnName, value=$value');

      final itemIndexKey = absoluteIndex.toString();

      // בדיקה: אם מנסים לסמן חזרה, צריך שהלימוד הקודם יהיה מסומן
      if (value) {
        final currentProgress = getProgressForItemById(bookId, absoluteIndex);

        // אם מנסים לסמן review1, צריך שlearn יהיה מסומן
        if (columnName == 'review1' && !currentProgress.learn) {
          UiSnack.show('יש לסמן תחילה את הלימוד הראשוני');
          return;
        }
        // אם מנסים לסמן review2, צריך שlearn ו-review1 יהיו מסומנים
        else if (columnName == 'review2' &&
            (!currentProgress.learn || !currentProgress.review1)) {
          if (!currentProgress.learn) {
            UiSnack.show('יש לסמן תחילה את הלימוד הראשוני');
          } else {
            UiSnack.show('יש לסמן תחילה את החזרה הראשונה');
          }
          return;
        }
        // אם מנסים לסמן review3, צריך שכל המחזורים הקודמים יהיו מסומנים
        else if (columnName == 'review3' &&
            (!currentProgress.learn ||
                !currentProgress.review1 ||
                !currentProgress.review2)) {
          if (!currentProgress.learn) {
            UiSnack.show('יש לסמן תחילה את הלימוד הראשוני');
          } else if (!currentProgress.review1) {
            UiSnack.show('יש לסמן תחילה את החזרה הראשונה');
          } else {
            UiSnack.show('יש לסמן תחילה את החזרה השנייה');
          }
          return;
        }
      }

      // Update local state
      _progressById.putIfAbsent(bookId, () => {});
      _progressById[bookId]!.putIfAbsent(itemIndexKey, () => PageProgress());

      final pageProgress = _progressById[bookId]![itemIndexKey]!;
      pageProgress.setProperty(columnName, value);

      // Clean up empty entries
      if (pageProgress.isEmpty) {
        _progressById[bookId]!.remove(itemIndexKey);
        if (_progressById[bookId]!.isEmpty) {
          _progressById.remove(bookId);
        }
      }

      _logger.info('Saving progress to storage...');
      // Save to storage
      await _progressService.saveProgressDataById(_progressById);
      _logger.info('Progress saved successfully');

      // Handle completion events
      if (value && columnName == learnColumn) {
        final isComplete = _isBookCompletedById(bookId, bookDetails);
        if (isComplete) {
          final hebrewDate = _getHebrewDate();
          await _progressService.saveCompletionDateById(bookId, hebrewDate);
          _completionDatesById =
              await _progressService.loadCompletionDatesById();
        }
      }

      notifyListeners();
      _logger.info('updateProgressById completed successfully');
    } catch (e, stackTrace) {
      _logger.severe('Error in updateProgressById: $e', e, stackTrace);
      _error = ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to update progress by ID',
      );
      _logger.severe(
          'Error updating progress by ID: ${_error!.message}', e, stackTrace);
      notifyListeners();
    }
  }

  /// Check if a book is completed by ID
  bool _isBookCompletedById(int bookId, BookDetails bookDetails) {
    final bookProgress = _progressById[bookId];
    if (bookProgress == null || bookProgress.isEmpty) return false;

    for (final item in bookDetails.learnableItems) {
      final progress = bookProgress[item.absoluteIndex.toString()];
      if (progress == null || !progress.learn) {
        return false;
      }
    }
    return true;
  }

  /// Get column selection states by book ID (all/none/partial)
  Map<String, bool?> getColumnSelectionStatesById(
    int bookId,
    BookDetails? bookDetails,
  ) {
    final columnStates = <String, bool?>{
      learnColumn: null,
      review1Column: null,
      review2Column: null,
      review3Column: null,
    };

    if (bookDetails == null) return columnStates;

    final bookProgress = _progressById[bookId];
    final totalItems = bookDetails.totalLearnableItems;

    if (totalItems == 0) {
      columnStates.updateAll((key, value) => false);
      return columnStates;
    }

    for (final currentColumnName in allColumnNames) {
      int itemsChecked = 0;
      if (bookProgress != null) {
        for (final item in bookDetails.learnableItems) {
          final itemProgress = bookProgress[item.absoluteIndex.toString()];
          if (itemProgress?.getProperty(currentColumnName) ?? false) {
            itemsChecked++;
          }
        }
      }

      if (itemsChecked == 0) {
        columnStates[currentColumnName] = false;
      } else if (itemsChecked == totalItems) {
        columnStates[currentColumnName] = true;
      } else {
        columnStates[currentColumnName] = null; // Partial selection
      }
    }

    return columnStates;
  }

  /// Toggle select all for a column by book ID
  Future<void> toggleSelectAllForColumnById(
    int bookId,
    BookDetails bookDetails,
    String columnName,
    bool selectAll,
  ) async {
    try {
      _progressById[bookId] ??= {};
      final bookProgress = _progressById[bookId]!;

      for (final item in bookDetails.learnableItems) {
        final key = item.absoluteIndex.toString();
        bookProgress[key] ??= PageProgress();
        bookProgress[key]!.setProperty(columnName, selectAll);
      }

      await _progressService.saveProgressDataById(_progressById);
      notifyListeners();
    } catch (e, stackTrace) {
      _logger.severe(
          'Error toggling select all for column by ID', e, stackTrace);
      _error = ShamorZachorError(
        type: ShamorZachorErrorType.unknown,
        message: 'Failed to toggle select all for column',
        originalError: e,
        stackTrace: stackTrace,
      );
      notifyListeners();
    }
  }

  /// Get section column state by book ID (all/none/partial)
  bool? getSectionColumnStateById(
    int bookId,
    BookDetails bookDetails,
    String sectionId,
    String columnName,
  ) {
    final leafIndices = bookDetails.sectionLeafIndexMap[sectionId];
    if (leafIndices == null || leafIndices.isEmpty) return false;

    final bookProgress = _progressById[bookId];
    if (bookProgress == null) return false;

    int checkedCount = 0;
    for (final index in leafIndices) {
      final progress = bookProgress[index.toString()];
      if (progress?.getProperty(columnName) ?? false) {
        checkedCount++;
      }
    }

    if (checkedCount == 0) return false;
    if (checkedCount == leafIndices.length) return true;
    return null; // Partial
  }

  /// Toggle section column by book ID
  Future<void> toggleSectionColumnById(
    int bookId,
    BookDetails bookDetails,
    String sectionId,
    String columnName,
    bool selectAll,
  ) async {
    try {
      final leafIndices = bookDetails.sectionLeafIndexMap[sectionId];
      if (leafIndices == null || leafIndices.isEmpty) return;

      _progressById[bookId] ??= {};
      final bookProgress = _progressById[bookId]!;

      for (final index in leafIndices) {
        final key = index.toString();
        bookProgress[key] ??= PageProgress();
        bookProgress[key]!.setProperty(columnName, selectAll);
      }

      await _progressService.saveProgressDataById(_progressById);
      notifyListeners();
    } catch (e, stackTrace) {
      _logger.severe('Error toggling section column by ID', e, stackTrace);
      _error = ShamorZachorError(
        type: ShamorZachorErrorType.unknown,
        message: 'Failed to toggle section column',
        originalError: e,
        stackTrace: stackTrace,
      );
      notifyListeners();
    }
  }

  /// Get learn progress percentage by book ID
  double getLearnProgressPercentageById(int bookId, BookDetails bookDetails) {
    final bookProgress = _progressById[bookId];
    final totalTargetItems = bookDetails.totalLearnableItems;
    if (totalTargetItems == 0 || bookProgress == null) return 0.0;

    final learnedPagesCount =
        ProgressService.getCompletedPagesCount(bookProgress);
    return learnedPagesCount / totalTargetItems;
  }

  /// Get review progress percentage by book ID
  double getReviewProgressPercentageById(
    int bookId,
    BookDetails bookDetails,
    int reviewNumber,
  ) {
    final bookProgress = _progressById[bookId];
    final totalTargetItems = bookDetails.totalLearnableItems;
    if (totalTargetItems == 0 || bookProgress == null) return 0.0;

    final reviewPagesCount = ProgressService.getReviewCompletedPagesCount(
      bookProgress,
      reviewNumber,
    );
    return reviewPagesCount / totalTargetItems;
  }

  /// Check if book is completed by ID
  bool isBookCompletedById(int bookId, BookDetails bookDetails) {
    final bookProgress = _progressById[bookId];
    if (bookProgress == null) return false;

    final totalTargetItems = bookDetails.totalLearnableItems;
    if (totalTargetItems == 0) return false;

    final learnedItemsCount =
        ProgressService.getCompletedPagesCount(bookProgress);
    return learnedItemsCount >= totalTargetItems;
  }

  /// Get number of completed cycles by book ID
  int getNumberOfCompletedCyclesById(int bookId, BookDetails bookDetails) {
    final bookProgress = _progressById[bookId];
    final totalTargetItems = bookDetails.totalLearnableItems;
    if (totalTargetItems == 0 || bookProgress == null) return 0;

    int cycles = 0;

    if (ProgressService.getCompletedPagesCount(bookProgress) >=
        totalTargetItems) {
      cycles++;
    }
    for (int i = 1; i <= 3; i++) {
      if (ProgressService.getReviewCompletedPagesCount(bookProgress, i) >=
          totalTargetItems) {
        cycles++;
      }
    }

    return cycles;
  }

  /// Get Hebrew date string
  String _getHebrewDate() {
    return DateTime.now().toIso8601String();
  }

  @override
  void dispose() {
    _logger.fine('Disposing ShamorZachorProgressProvider');
    _completionEventController.close();
    _progressService.dispose();
    super.dispose();
  }
}
