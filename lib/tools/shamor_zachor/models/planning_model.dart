import 'book_model.dart';
import 'progress_model.dart';

class ReviewScheduleSettings {
  static const String popularPresetId = 'popular';
  static const String customPresetId = 'custom';
  static const List<int> popularIntervals = [1, 8, 38, 128, 364];

  final String presetId;
  final List<int> intervalsInDays;

  const ReviewScheduleSettings({
    required this.presetId,
    required this.intervalsInDays,
  });

  factory ReviewScheduleSettings.defaultSettings() {
    return const ReviewScheduleSettings(
      presetId: popularPresetId,
      intervalsInDays: popularIntervals,
    );
  }

  factory ReviewScheduleSettings.fromJson(Map<String, dynamic> json) {
    final rawIntervals = json['intervalsInDays'];
    final parsedIntervals = rawIntervals is List
        ? rawIntervals
            .map((value) => int.tryParse(value.toString()) ?? 0)
            .where((value) => value > 0)
            .toList(growable: false)
        : const <int>[];

    if (parsedIntervals.length != shamorZachorMaxReviewCycles) {
      return ReviewScheduleSettings.defaultSettings();
    }

    return ReviewScheduleSettings(
      presetId: json['presetId'] as String? ?? popularPresetId,
      intervalsInDays: parsedIntervals,
    );
  }

  Map<String, dynamic> toJson() => {
        'presetId': presetId,
        'intervalsInDays': intervalsInDays,
      };

  bool get isCustom => presetId == customPresetId;

  String get description => intervalsInDays.join(', ');
}

class ReviewBookRecommendation {
  final int bookId;
  final String bookName;
  final String topLevelCategoryKey;
  final BookDetails bookDetails;
  final int stageNumber;
  final int dueItemsCount;
  final int overdueItemsCount;
  final DateTime earliestDueDate;
  final DateTime? lastCompletedAt;

  const ReviewBookRecommendation({
    required this.bookId,
    required this.bookName,
    required this.topLevelCategoryKey,
    required this.bookDetails,
    required this.stageNumber,
    required this.dueItemsCount,
    required this.overdueItemsCount,
    required this.earliestDueDate,
    this.lastCompletedAt,
  });

  bool get isOverdue => overdueItemsCount > 0;
}

class LearningActivityRecord {
  final int bookId;
  final String bookName;
  final String topLevelCategoryKey;
  final String itemLabel;
  final String stageKey;
  final DateTime completedAt;

  const LearningActivityRecord({
    required this.bookId,
    required this.bookName,
    required this.topLevelCategoryKey,
    required this.itemLabel,
    required this.stageKey,
    required this.completedAt,
  });
}

enum StudyPlanMode {
  fixed,
  automatic,
}

class StudyPlanDayEntry {
  final DateTime date;
  final int units;

  const StudyPlanDayEntry({
    required this.date,
    required this.units,
  });
}

class StudyPlanComputation {
  final int totalUnits;
  final int scheduledUnits;
  final int dailyUnits;
  final bool reachesTargetDate;
  final DateTime projectedCompletionDate;
  final List<StudyPlanDayEntry> entries;

  const StudyPlanComputation({
    required this.totalUnits,
    required this.scheduledUnits,
    required this.dailyUnits,
    required this.reachesTargetDate,
    required this.projectedCompletionDate,
    required this.entries,
  });
}
