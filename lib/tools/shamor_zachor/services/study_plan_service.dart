import '../models/book_model.dart';
import '../models/planning_model.dart';
import '../models/progress_model.dart';

class StudyPlanService {
  static List<ReviewBookRecommendation> buildReviewRecommendations({
    required Iterable<int> bookIds,
    required Map<String, PageProgress> Function(int bookId) progressForBook,
    required (BookDetails, String, String)? Function(int bookId) resolveBook,
    required ReviewScheduleSettings reviewSchedule,
    DateTime? referenceDate,
  }) {
    final currentDate = _dateOnly(referenceDate ?? DateTime.now());
    final recommendations = <ReviewBookRecommendation>[];

    for (final bookId in bookIds) {
      final resolvedBook = resolveBook(bookId);
      if (resolvedBook == null) {
        continue;
      }

      final (bookDetails, bookName, topLevelCategoryKey) = resolvedBook;
      final progressMap = progressForBook(bookId);
      if (progressMap.isEmpty) {
        continue;
      }

      final recommendation = _buildRecommendationForBook(
        bookId: bookId,
        bookName: bookName,
        topLevelCategoryKey: topLevelCategoryKey,
        bookDetails: bookDetails,
        progressMap: progressMap,
        reviewSchedule: reviewSchedule,
        currentDate: currentDate,
      );

      if (recommendation != null) {
        recommendations.add(recommendation);
      }
    }

    recommendations.sort((left, right) {
      final dueDateComparison =
          left.earliestDueDate.compareTo(right.earliestDueDate);
      if (dueDateComparison != 0) {
        return dueDateComparison;
      }
      return right.dueItemsCount.compareTo(left.dueItemsCount);
    });

    return recommendations;
  }

  static List<LearningActivityRecord> buildActivityRecords({
    required Iterable<int> bookIds,
    required Map<String, PageProgress> Function(int bookId) progressForBook,
    required (BookDetails, String, String)? Function(int bookId) resolveBook,
  }) {
    final records = <LearningActivityRecord>[];

    for (final bookId in bookIds) {
      final resolvedBook = resolveBook(bookId);
      if (resolvedBook == null) {
        continue;
      }

      final (bookDetails, bookName, topLevelCategoryKey) = resolvedBook;
      final progressMap = progressForBook(bookId);

      for (final item in bookDetails.learnableItems) {
        final progress = progressMap[item.absoluteIndex.toString()];
        if (progress == null) {
          continue;
        }

        for (final stageKey in _stageKeys) {
          if (!progress.getProperty(stageKey)) {
            continue;
          }

          final completedAt = progress.getCompletedAtForProperty(stageKey);
          if (completedAt == null) {
            continue;
          }

          records.add(
            LearningActivityRecord(
              bookId: bookId,
              bookName: bookName,
              topLevelCategoryKey: topLevelCategoryKey,
              itemLabel: _formatItemLabel(bookDetails, item),
              stageKey: stageKey,
              completedAt: completedAt,
            ),
          );
        }
      }
    }

    records.sort((left, right) => right.completedAt.compareTo(left.completedAt));
    return records;
  }

  static StudyPlanComputation buildStudyPlan({
    required int totalUnits,
    required DateTime startDate,
    required DateTime endDate,
    required StudyPlanMode mode,
    int fixedUnitsPerDay = 1,
  }) {
    final normalizedStart = _dateOnly(startDate);
    final normalizedEnd = _dateOnly(endDate);
    final effectiveEnd =
        normalizedEnd.isBefore(normalizedStart) ? normalizedStart : normalizedEnd;

    if (totalUnits <= 0) {
      return StudyPlanComputation(
        totalUnits: 0,
        scheduledUnits: 0,
        dailyUnits: 0,
        reachesTargetDate: true,
        projectedCompletionDate: normalizedStart,
        entries: const [],
      );
    }

    final dayCount = effectiveEnd.difference(normalizedStart).inDays + 1;

    if (mode == StudyPlanMode.fixed) {
      final unitsPerDay = fixedUnitsPerDay <= 0 ? 1 : fixedUnitsPerDay;
      final entries = <StudyPlanDayEntry>[];
      var remainingUnits = totalUnits;

      for (int dayIndex = 0; dayIndex < dayCount; dayIndex++) {
        if (remainingUnits <= 0) {
          break;
        }

        final unitsForDay =
            remainingUnits < unitsPerDay ? remainingUnits : unitsPerDay;
        entries.add(
          StudyPlanDayEntry(
            date: normalizedStart.add(Duration(days: dayIndex)),
            units: unitsForDay,
          ),
        );
        remainingUnits -= unitsForDay;
      }

      final requiredDays = (totalUnits / unitsPerDay).ceil();
      return StudyPlanComputation(
        totalUnits: totalUnits,
        scheduledUnits: entries.fold(0, (sum, entry) => sum + entry.units),
        dailyUnits: unitsPerDay,
        reachesTargetDate: totalUnits <= unitsPerDay * dayCount,
        projectedCompletionDate:
            normalizedStart.add(Duration(days: requiredDays - 1)),
        entries: entries,
      );
    }

    final baseUnits = totalUnits ~/ dayCount;
    final remainder = totalUnits % dayCount;
    final entries = <StudyPlanDayEntry>[];

    for (int dayIndex = 0; dayIndex < dayCount; dayIndex++) {
      final unitsForDay = baseUnits + (dayIndex < remainder ? 1 : 0);
      if (unitsForDay <= 0) {
        continue;
      }
      entries.add(
        StudyPlanDayEntry(
          date: normalizedStart.add(Duration(days: dayIndex)),
          units: unitsForDay,
        ),
      );
    }

    return StudyPlanComputation(
      totalUnits: totalUnits,
      scheduledUnits: totalUnits,
      dailyUnits: (totalUnits / dayCount).ceil(),
      reachesTargetDate: true,
      projectedCompletionDate: effectiveEnd,
      entries: entries,
    );
  }

  static ReviewBookRecommendation? _buildRecommendationForBook({
    required int bookId,
    required String bookName,
    required String topLevelCategoryKey,
    required BookDetails bookDetails,
    required Map<String, PageProgress> progressMap,
    required ReviewScheduleSettings reviewSchedule,
    required DateTime currentDate,
  }) {
    ReviewBookRecommendation? currentRecommendation;

    for (final item in bookDetails.learnableItems) {
      final progress = progressMap[item.absoluteIndex.toString()];
      if (progress == null) {
        continue;
      }

      final pendingStage = _pendingStageFor(progress);
      if (pendingStage == null) {
        continue;
      }

      final completedAt =
          progress.getCompletedAtForProperty(pendingStage.previousStageKey);
      if (completedAt == null) {
        continue;
      }

      final dueDate = _dateOnly(
        completedAt.add(
          Duration(
            days: reviewSchedule
                .intervalsInDays[pendingStage.stageNumber - 1],
          ),
        ),
      );

      if (dueDate.isAfter(currentDate)) {
        continue;
      }

      final isSameStage = currentRecommendation == null ||
          currentRecommendation.stageNumber == pendingStage.stageNumber;
      if (!isSameStage) {
        continue;
      }

      final overdueItemsCount = dueDate.isBefore(currentDate) ? 1 : 0;
      if (currentRecommendation == null) {
        currentRecommendation = ReviewBookRecommendation(
          bookId: bookId,
          bookName: bookName,
          topLevelCategoryKey: topLevelCategoryKey,
          bookDetails: bookDetails,
          stageNumber: pendingStage.stageNumber,
          dueItemsCount: 1,
          overdueItemsCount: overdueItemsCount,
          earliestDueDate: dueDate,
          lastCompletedAt: completedAt,
        );
        continue;
      }

      currentRecommendation = ReviewBookRecommendation(
        bookId: currentRecommendation.bookId,
        bookName: currentRecommendation.bookName,
        topLevelCategoryKey: currentRecommendation.topLevelCategoryKey,
        bookDetails: currentRecommendation.bookDetails,
        stageNumber: currentRecommendation.stageNumber,
        dueItemsCount: currentRecommendation.dueItemsCount + 1,
        overdueItemsCount:
            currentRecommendation.overdueItemsCount + overdueItemsCount,
        earliestDueDate: dueDate.isBefore(currentRecommendation.earliestDueDate)
            ? dueDate
            : currentRecommendation.earliestDueDate,
        lastCompletedAt: currentRecommendation.lastCompletedAt == null ||
                completedAt.isAfter(currentRecommendation.lastCompletedAt!)
            ? completedAt
            : currentRecommendation.lastCompletedAt,
      );
    }

    return currentRecommendation;
  }

  static _PendingStage? _pendingStageFor(PageProgress progress) {
    if (progress.learn && !progress.review1) {
      return const _PendingStage(stageNumber: 1, previousStageKey: 'learn');
    }
    if (progress.review1 && !progress.review2) {
      return const _PendingStage(stageNumber: 2, previousStageKey: 'review1');
    }
    if (progress.review2 && !progress.review3) {
      return const _PendingStage(stageNumber: 3, previousStageKey: 'review2');
    }
    if (progress.review3 && !progress.review4) {
      return const _PendingStage(stageNumber: 4, previousStageKey: 'review3');
    }
    if (progress.review4 && !progress.review5) {
      return const _PendingStage(stageNumber: 5, previousStageKey: 'review4');
    }

    return null;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _formatItemLabel(BookDetails bookDetails, LearnableItem item) {
    if (item.displayLabel != null && item.displayLabel!.trim().isNotEmpty) {
      return item.displayLabel!;
    }

    if (bookDetails.isDafType) {
      final amud = item.amudKey == 'b' ? 'עמוד ב' : 'עמוד א';
      return 'דף ${item.pageNumber} $amud';
    }

    return 'יחידה ${item.pageNumber}';
  }
}

const List<String> _stageKeys = [
  'learn',
  'review1',
  'review2',
  'review3',
  'review4',
  'review5',
];

class _PendingStage {
  final int stageNumber;
  final String previousStageKey;

  const _PendingStage({
    required this.stageNumber,
    required this.previousStageKey,
  });
}
