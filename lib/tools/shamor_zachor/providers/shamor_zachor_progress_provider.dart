import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../models/progress_model.dart';
import '../models/book_model.dart';
import '../models/error_model.dart';
import '../services/progress_service.dart';

/// Events emitted when significant progress milestones are reached
enum CompletionEventType {
  bookCompleted,
  reviewCycleCompleted,
}

class CompletionEvent {
  final CompletionEventType type;
  final int? bookId;
  final int? reviewCycleNumber;

  const CompletionEvent(
    this.type, {
    this.bookId,
    this.reviewCycleNumber,
  });

  @override
  String toString() {
    return 'CompletionEvent(type: $type, bookId: $bookId, review: $reviewCycleNumber)';
  }
}

/// Provider for managing user progress in Shamor Zachor.
/// All progress is keyed by book ID.
class ShamorZachorProgressProvider with ChangeNotifier {
  static final Logger _logger = Logger('ShamorZachorProgressProvider');

  final ProgressService _progressService;

  ProgressMapById _progressById = {};
  CompletionDatesByIdMap _completionDatesById = {};

  /// הגדרות העמודות המותאמות לכל ספר (bookId → רשימת עמודות)
  Map<int, List<ProgressColumn>> _columnsByBookId = {};

  final Map<int, BookProgressSummary> _progressSummaryCache = {};
  bool _isLoading = false;
  ShamorZachorError? _error;

  /// מספר העמודות המרבי שניתן להגדיר לספר
  static const int maxColumns = 8;

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

  /// העמודות המוגדרות לספר; אם אין הגדרה מותאמת - עמודות ברירת המחדל
  List<ProgressColumn> getColumnsForBook(int bookId) =>
      _columnsByBookId[bookId] ?? kDefaultProgressColumns;

  List<String> _columnIdsForBook(int bookId) =>
      getColumnsForBook(bookId).map((c) => c.id).toList();

  /// משנה את שם העמודה (ה-id והמעקב נשמרים)
  Future<void> renameColumn(
    int bookId,
    String columnId,
    String newLabel,
  ) async {
    final trimmed = newLabel.trim();
    if (trimmed.isEmpty) return;
    final columns = List<ProgressColumn>.from(getColumnsForBook(bookId));
    final index = columns.indexWhere((c) => c.id == columnId);
    if (index == -1) return;
    columns[index] = columns[index].copyWith(label: trimmed);
    await _persistColumns(bookId, columns);
  }

  /// מוסיף עמודת מעקב חדשה לספר
  Future<void> addColumn(int bookId, String label) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return;
    final columns = List<ProgressColumn>.from(getColumnsForBook(bookId));
    if (columns.length >= maxColumns) return;
    final id = 'col_${DateTime.now().microsecondsSinceEpoch}';
    columns.add(ProgressColumn(id: id, label: trimmed));
    await _persistColumns(bookId, columns);
  }

  /// מסיר עמודת מעקב מהספר (חייבת להישאר לפחות עמודה אחת) ומנקה את הסימונים שלה
  Future<void> removeColumn(int bookId, String columnId) async {
    final columns = List<ProgressColumn>.from(getColumnsForBook(bookId));
    if (columns.length <= 1) return;
    columns.removeWhere((c) => c.id == columnId);

    final bookProgress = _progressById[bookId];
    if (bookProgress != null) {
      for (final progress in bookProgress.values) {
        progress.removeColumn(columnId);
      }
      bookProgress.removeWhere((_, progress) => progress.isEmpty);
      if (bookProgress.isEmpty) _progressById.remove(bookId);
      await _progressService.saveProgressDataById(_progressById);
    }
    await _persistColumns(bookId, columns);
  }

  Future<void> _persistColumns(int bookId, List<ProgressColumn> columns) async {
    _columnsByBookId[bookId] = columns;
    await _progressService.saveColumnsByBookId(_columnsByBookId);
    _invalidateSummaryCache(bookId);
    notifyListeners();
  }

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
  bool get hasData => _progressById.isNotEmpty;

  void _invalidateSummaryCache(int bookId) {
    _progressSummaryCache.remove(bookId);
  }

  void _clearSummaryCache() {
    _progressSummaryCache.clear();
  }

  ShamorZachorProgressProvider({
    ProgressService? progressService,
  }) : _progressService = progressService ?? ProgressService();

  /// Ensures data is loaded - call this when the widget is first displayed.
  /// Idempotent: only loads once.
  Future<void> ensureLoaded() async {
    if (_isLoading || hasData || _error != null) {
      return;
    }
    await _loadInitialProgress();
  }

  /// Retry loading after a previous failure.
  Future<void> retry() async {
    if (_isLoading) {
      return;
    }

    _error = null;
    await _loadInitialProgress();
  }

  /// Load initial progress data
  Future<void> _loadInitialProgress() async {
    if (_isLoading) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _progressById = await _progressService.loadProgressDataById();
      _completionDatesById = await _progressService.loadCompletionDatesById();
      _columnsByBookId = await _progressService.loadColumnsByBookId();

      _logger.info(
        'Successfully loaded progress: ${_progressById.length} books',
      );
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
        'Error loading progress: ${_error!.message}',
        e,
        stackTrace,
      );
    }

    _clearSummaryCache();
    _isLoading = false;
    notifyListeners();
  }

  /// Get progress data for a specific book by ID
  Map<String, PageProgress> getProgressForBookById(int bookId) {
    return _progressById[bookId] ?? {};
  }

  /// Get progress for a specific item by book ID
  PageProgress getProgressForItemById(int bookId, int absoluteIndex) {
    return _progressById[bookId]?[absoluteIndex.toString()] ?? PageProgress();
  }

  /// Get completion date for a book by ID (synchronous)
  String? getCompletionDateSyncById(int bookId) {
    return _completionDatesById[bookId];
  }

  /// Update progress for a single item by book ID
  Future<void> updateProgressById(
    int bookId,
    int absoluteIndex,
    String columnName,
    bool value,
    BookDetails bookDetails, {
    bool isBulkUpdate = false,
  }) async {
    try {
      final itemIndexKey = absoluteIndex.toString();

      // Make sure data is loaded before mutating - prevents accidental wipes
      if (_progressById.isEmpty && !_isLoading) {
        _progressById = await _progressService.loadProgressDataById();
      }

      _progressById.putIfAbsent(bookId, () => {});
      _progressById[bookId]!.putIfAbsent(itemIndexKey, () => PageProgress());

      final pageProgress = _progressById[bookId]![itemIndexKey]!;
      pageProgress.setProperty(columnName, value);

      if (pageProgress.isEmpty) {
        _progressById[bookId]!.remove(itemIndexKey);
        if (_progressById[bookId]!.isEmpty) {
          _progressById.remove(bookId);
        }
      }

      await _progressService.saveProgressDataById(_progressById);

      _invalidateSummaryCache(bookId);

      if (value && !isBulkUpdate) {
        await _handleCompletionEventsById(bookId, columnName, bookDetails);
      }

      if (!isBulkUpdate) {
        notifyListeners();
      }
    } catch (e, stackTrace) {
      _logger.severe('Error in updateProgressById: $e', e, stackTrace);
      _error = ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to update progress by ID',
      );
      notifyListeners();
    }
  }

  /// Handle completion events when progress is updated (by ID)
  ///
  /// העמודות עצמאיות: סימון של כל עמודה עשוי להשלים מחזור (העמודה כולה)
  /// או את הספר כולו (כל העמודות).
  Future<void> _handleCompletionEventsById(
    int bookId,
    String columnName,
    BookDetails bookDetails,
  ) async {
    _invalidateSummaryCache(bookId);

    // השלמת הספר כולו (כל העמודות בכל הפריטים)
    final wasAlreadyCompleted = getCompletionDateSyncById(bookId) != null;
    final isNowComplete = isBookCompletedById(bookId, bookDetails);

    if (isNowComplete && !wasAlreadyCompleted) {
      await _progressService.saveCompletionDateById(
        bookId,
        DateTime.now().toIso8601String(),
      );
      _completionDatesById = await _progressService.loadCompletionDatesById();
      _invalidateSummaryCache(bookId);

      _completionEventController.add(
        CompletionEvent(
          CompletionEventType.bookCompleted,
          bookId: bookId,
        ),
      );
    }

    // השלמת מחזור (עמודה שלמה) - מספר המחזור הוא מיקום העמודה ברשימה
    final columns = _columnIdsForBook(bookId);
    final columnIndex = columns.indexOf(columnName);
    if (columnIndex != -1 &&
        _isColumnCompleteById(bookId, columnName, bookDetails)) {
      _invalidateSummaryCache(bookId);
      _completionEventController.add(
        CompletionEvent(
          CompletionEventType.reviewCycleCompleted,
          bookId: bookId,
          reviewCycleNumber: columnIndex + 1,
        ),
      );
    }
  }

  /// Toggle select all for a column by book ID
  Future<void> toggleSelectAllForColumnById(
    int bookId,
    BookDetails bookDetails,
    String columnName,
    bool selectAll,
  ) async {
    if (!_columnIdsForBook(bookId).contains(columnName)) {
      _logger.warning('Invalid column name: $columnName');
      return;
    }

    try {
      _progressById[bookId] ??= {};
      final bookProgress = _progressById[bookId]!;

      for (final item in bookDetails.learnableItems) {
        final key = item.absoluteIndex.toString();
        bookProgress[key] ??= PageProgress();
        bookProgress[key]!.setProperty(columnName, selectAll);
      }

      await _progressService.saveProgressDataById(_progressById);
      _invalidateSummaryCache(bookId);

      if (selectAll) {
        final wasAlreadyCompleted = getCompletionDateSyncById(bookId) != null;
        final isNowComplete = isBookCompletedById(bookId, bookDetails);

        if (isNowComplete && !wasAlreadyCompleted) {
          await _progressService.saveCompletionDateById(
            bookId,
            DateTime.now().toIso8601String(),
          );
          _completionDatesById = await _progressService
              .loadCompletionDatesById();
        }
      }

      notifyListeners();
    } catch (e, stackTrace) {
      _logger.severe(
        'Error toggling select all for column by ID',
        e,
        stackTrace,
      );
      _error = ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to bulk update column',
      );
      notifyListeners();
    }
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
      _invalidateSummaryCache(bookId);

      if (selectAll) {
        final wasAlreadyCompleted = getCompletionDateSyncById(bookId) != null;
        final isNowComplete = isBookCompletedById(bookId, bookDetails);

        if (isNowComplete && !wasAlreadyCompleted) {
          await _progressService.saveCompletionDateById(
            bookId,
            DateTime.now().toIso8601String(),
          );
          _completionDatesById = await _progressService
              .loadCompletionDatesById();
        }
      }

      notifyListeners();
    } catch (e, stackTrace) {
      _logger.severe('Error toggling section column by ID', e, stackTrace);
      _error = ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to update section progress',
      );
      notifyListeners();
    }
  }

  /// Clear all progress for a specific book by ID
  Future<void> clearBookProgressById(
    int bookId, {
    BookDetails? bookDetails,
  }) async {
    try {
      _progressById.remove(bookId);
      _completionDatesById.remove(bookId);

      await _progressService.saveProgressDataById(_progressById);
      await _progressService.saveCompletionDatesById(_completionDatesById);

      _invalidateSummaryCache(bookId);

      notifyListeners();
    } catch (e, stackTrace) {
      _error = ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to clear book progress by ID',
      );
      _logger.severe(
        'Error clearing progress by ID: ${_error!.message}',
        e,
        stackTrace,
      );
      notifyListeners();
    }
  }

  /// Get column selection states by book ID (all/none/partial)
  Map<String, bool?> getColumnSelectionStatesById(
    int bookId,
    BookDetails? bookDetails,
  ) {
    final columnIds = _columnIdsForBook(bookId);
    final columnStates = <String, bool?>{for (final id in columnIds) id: null};

    if (bookDetails == null) return columnStates;

    final bookProgress = _progressById[bookId];
    final totalItems = bookDetails.totalLearnableItems;

    if (totalItems == 0) {
      columnStates.updateAll((key, value) => false);
      return columnStates;
    }

    for (final currentColumnName in columnIds) {
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
        columnStates[currentColumnName] = null;
      }
    }

    return columnStates;
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
    return null;
  }

  /// אחוז ההשלמה של עמודה נתונה בספר (0.0 עד 1.0)
  double getColumnProgressPercentageById(
    int bookId,
    BookDetails bookDetails,
    String columnId,
  ) {
    final bookProgress = _progressById[bookId];
    final totalTargetItems = bookDetails.totalLearnableItems;
    if (totalTargetItems == 0 || bookProgress == null) return 0.0;

    final count = ProgressService.getColumnCompletedCount(
      bookProgress,
      columnId,
    );
    return count / totalTargetItems;
  }

  /// תאימות אחורה: אחוז ההשלמה של העמודה הראשונה בספר
  double getLearnProgressPercentageById(int bookId, BookDetails bookDetails) {
    final columns = _columnIdsForBook(bookId);
    if (columns.isEmpty) return 0.0;
    return getColumnProgressPercentageById(bookId, bookDetails, columns.first);
  }

  /// Check if book is completed by ID - כל העמודות מסומנות בכל הפריטים
  bool isBookCompletedById(int bookId, BookDetails bookDetails) {
    final bookProgress = _progressById[bookId];
    if (bookProgress == null) return false;

    final totalTargetItems = bookDetails.totalLearnableItems;
    if (totalTargetItems == 0) return false;

    for (final columnId in _columnIdsForBook(bookId)) {
      if (ProgressService.getColumnCompletedCount(bookProgress, columnId) <
          totalTargetItems) {
        return false;
      }
    }
    return true;
  }

  /// בודק אם עמודה נתונה הושלמה (מסומנת בכל הפריטים)
  bool _isColumnCompleteById(
    int bookId,
    String columnId,
    BookDetails bookDetails,
  ) {
    final bookProgress = _progressById[bookId];
    final totalItems = bookDetails.totalLearnableItems;
    if (totalItems == 0 || bookProgress == null || bookProgress.isEmpty) {
      return false;
    }
    return ProgressService.getColumnCompletedCount(bookProgress, columnId) >=
        totalItems;
  }

  /// Check if book is considered in progress by ID - יש סימון כלשהו אך לא הושלם
  bool isBookConsideredInProgressById(int bookId, BookDetails bookDetails) {
    final bookProgress = _progressById[bookId];
    if (bookProgress == null || bookProgress.isEmpty) {
      return false;
    }
    if (isBookCompletedById(bookId, bookDetails)) return false;
    return bookProgress.values.any((progress) => !progress.isEmpty);
  }

  /// Get number of completed cycles (columns) by book ID
  int getNumberOfCompletedCyclesById(int bookId, BookDetails bookDetails) {
    final bookProgress = _progressById[bookId];
    final totalTargetItems = bookDetails.totalLearnableItems;
    if (totalTargetItems == 0 || bookProgress == null) return 0;

    int cycles = 0;
    for (final columnId in _columnIdsForBook(bookId)) {
      if (ProgressService.getColumnCompletedCount(bookProgress, columnId) >=
          totalTargetItems) {
        cycles++;
      }
    }
    return cycles;
  }

  /// Get book progress summary by ID (synchronous)
  BookProgressSummary getBookProgressSummarySyncById(
    int bookId,
    String categoryName,
    String bookName,
    BookDetails bookDetails,
  ) {
    final cached = _progressSummaryCache[bookId];
    if (cached != null &&
        cached.totalItems == bookDetails.totalLearnableItems) {
      return cached;
    }

    final bookProgress = getProgressForBookById(bookId);
    final completionDate = getCompletionDateSyncById(bookId);
    final summary = _progressService.buildBookProgressSummary(
      categoryName,
      bookName,
      bookDetails,
      bookProgress,
      completionDate: completionDate,
      columns: _columnIdsForBook(bookId),
    );
    _progressSummaryCache[bookId] = summary;
    return summary;
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
        'Error exporting progress: ${_error!.message}',
        e,
        stackTrace,
      );
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
        'Error importing progress: ${_error!.message}',
        e,
        stackTrace,
      );
      notifyListeners();
      return false;
    }
  }

  /// Clear all progress data
  Future<void> clearAllProgress() async {
    try {
      await _progressService.clearAllProgress();
      _progressById.clear();
      _completionDatesById.clear();
      _columnsByBookId.clear();
      _clearSummaryCache();
      notifyListeners();
    } catch (e, stackTrace) {
      _error = ShamorZachorError.fromException(
        e,
        stackTrace: stackTrace,
        customMessage: 'Failed to clear progress data',
      );
      _logger.severe(
        'Error clearing progress: ${_error!.message}',
        e,
        stackTrace,
      );
      notifyListeners();
    }
  }

  /// Clear error state
  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _logger.fine('Disposing ShamorZachorProgressProvider');
    _completionEventController.close();
    _progressService.dispose();
    super.dispose();
  }
}
