/// Represents the progress for a single page/item.
/// Includes initial learning and up to 5 reviews with completion timestamps.
const int shamorZachorMaxReviewCycles = 5;

class PageProgress {
  bool learn;
  bool review1;
  bool review2;
  bool review3;
  bool review4;
  bool review5;
  DateTime? learnCompletedAt;
  DateTime? review1CompletedAt;
  DateTime? review2CompletedAt;
  DateTime? review3CompletedAt;
  DateTime? review4CompletedAt;
  DateTime? review5CompletedAt;

  PageProgress({
    this.learn = false,
    this.review1 = false,
    this.review2 = false,
    this.review3 = false,
    this.review4 = false,
    this.review5 = false,
    this.learnCompletedAt,
    this.review1CompletedAt,
    this.review2CompletedAt,
    this.review3CompletedAt,
    this.review4CompletedAt,
    this.review5CompletedAt,
  });

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() => {
        'learn': learn,
        'review1': review1,
        'review2': review2,
        'review3': review3,
        'review4': review4,
        'review5': review5,
        if (learnCompletedAt != null)
          'learnCompletedAt': learnCompletedAt!.toIso8601String(),
        if (review1CompletedAt != null)
          'review1CompletedAt': review1CompletedAt!.toIso8601String(),
        if (review2CompletedAt != null)
          'review2CompletedAt': review2CompletedAt!.toIso8601String(),
        if (review3CompletedAt != null)
          'review3CompletedAt': review3CompletedAt!.toIso8601String(),
        if (review4CompletedAt != null)
          'review4CompletedAt': review4CompletedAt!.toIso8601String(),
        if (review5CompletedAt != null)
          'review5CompletedAt': review5CompletedAt!.toIso8601String(),
      };

  /// Create from JSON data
  factory PageProgress.fromJson(Map<String, dynamic> json) {
    return PageProgress(
      learn: json['learn'] ?? false,
      review1: json['review1'] ?? false,
      review2: json['review2'] ?? false,
      review3: json['review3'] ?? false,
      review4: json['review4'] ?? false,
      review5: json['review5'] ?? false,
      learnCompletedAt: _parseDateTime(json['learnCompletedAt']),
      review1CompletedAt: _parseDateTime(json['review1CompletedAt']),
      review2CompletedAt: _parseDateTime(json['review2CompletedAt']),
      review3CompletedAt: _parseDateTime(json['review3CompletedAt']),
      review4CompletedAt: _parseDateTime(json['review4CompletedAt']),
      review5CompletedAt: _parseDateTime(json['review5CompletedAt']),
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  /// Check if no progress has been made
  bool get isEmpty =>
      !learn && !review1 && !review2 && !review3 && !review4 && !review5;

  /// Check if all learning and reviews are complete
  bool get isComplete =>
      learn && review1 && review2 && review3 && review4 && review5;

  /// Get the number of completed items (learn + reviews)
  int get completedCount {
    int count = 0;
    if (learn) count++;
    if (review1) count++;
    if (review2) count++;
    if (review3) count++;
    if (review4) count++;
    if (review5) count++;
    return count;
  }

  /// Get progress as a percentage (0.0 to 1.0)
  double get progressPercentage =>
      completedCount / (shamorZachorMaxReviewCycles + 1);

  /// Set a specific property by name
  void setProperty(
    String propertyName,
    bool value, {
    DateTime? completedAt,
  }) {
    switch (propertyName) {
      case 'learn':
        learn = value;
        learnCompletedAt =
            value ? (completedAt ?? learnCompletedAt ?? DateTime.now()) : null;
        break;
      case 'review1':
        review1 = value;
        review1CompletedAt = value
            ? (completedAt ?? review1CompletedAt ?? DateTime.now())
            : null;
        break;
      case 'review2':
        review2 = value;
        review2CompletedAt = value
            ? (completedAt ?? review2CompletedAt ?? DateTime.now())
            : null;
        break;
      case 'review3':
        review3 = value;
        review3CompletedAt = value
            ? (completedAt ?? review3CompletedAt ?? DateTime.now())
            : null;
        break;
      case 'review4':
        review4 = value;
        review4CompletedAt = value
            ? (completedAt ?? review4CompletedAt ?? DateTime.now())
            : null;
        break;
      case 'review5':
        review5 = value;
        review5CompletedAt = value
            ? (completedAt ?? review5CompletedAt ?? DateTime.now())
            : null;
        break;
      default:
        throw ArgumentError('Unknown property: $propertyName');
    }
  }

  /// Get a specific property by name
  bool getProperty(String propertyName) {
    switch (propertyName) {
      case 'learn':
        return learn;
      case 'review1':
        return review1;
      case 'review2':
        return review2;
      case 'review3':
        return review3;
      case 'review4':
        return review4;
      case 'review5':
        return review5;
      default:
        throw ArgumentError('Unknown property: $propertyName');
    }
  }

  /// Get completion time for a specific property.
  DateTime? getCompletedAtForProperty(String propertyName) {
    switch (propertyName) {
      case 'learn':
        return learnCompletedAt;
      case 'review1':
        return review1CompletedAt;
      case 'review2':
        return review2CompletedAt;
      case 'review3':
        return review3CompletedAt;
      case 'review4':
        return review4CompletedAt;
      case 'review5':
        return review5CompletedAt;
      default:
        throw ArgumentError('Unknown property: $propertyName');
    }
  }

  /// Create a copy with modified values
  PageProgress copyWith({
    bool? learn,
    bool? review1,
    bool? review2,
    bool? review3,
    bool? review4,
    bool? review5,
    DateTime? learnCompletedAt,
    DateTime? review1CompletedAt,
    DateTime? review2CompletedAt,
    DateTime? review3CompletedAt,
    DateTime? review4CompletedAt,
    DateTime? review5CompletedAt,
  }) {
    return PageProgress(
      learn: learn ?? this.learn,
      review1: review1 ?? this.review1,
      review2: review2 ?? this.review2,
      review3: review3 ?? this.review3,
      review4: review4 ?? this.review4,
      review5: review5 ?? this.review5,
      learnCompletedAt: learnCompletedAt ?? this.learnCompletedAt,
      review1CompletedAt: review1CompletedAt ?? this.review1CompletedAt,
      review2CompletedAt: review2CompletedAt ?? this.review2CompletedAt,
      review3CompletedAt: review3CompletedAt ?? this.review3CompletedAt,
      review4CompletedAt: review4CompletedAt ?? this.review4CompletedAt,
      review5CompletedAt: review5CompletedAt ?? this.review5CompletedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PageProgress &&
          runtimeType == other.runtimeType &&
          learn == other.learn &&
          review1 == other.review1 &&
          review2 == other.review2 &&
          review3 == other.review3 &&
          review4 == other.review4 &&
          review5 == other.review5 &&
          learnCompletedAt == other.learnCompletedAt &&
          review1CompletedAt == other.review1CompletedAt &&
          review2CompletedAt == other.review2CompletedAt &&
          review3CompletedAt == other.review3CompletedAt &&
          review4CompletedAt == other.review4CompletedAt &&
          review5CompletedAt == other.review5CompletedAt;

  @override
  int get hashCode => Object.hash(
        learn,
        review1,
        review2,
        review3,
        review4,
        review5,
        learnCompletedAt,
        review1CompletedAt,
        review2CompletedAt,
        review3CompletedAt,
        review4CompletedAt,
        review5CompletedAt,
      );

  @override
  String toString() {
    return 'PageProgress(learn: $learn, review1: $review1, review2: $review2, '
        'review3: $review3, review4: $review4, review5: $review5)';
  }
}

/// Type definitions for complex progress data structures

/// NEW: Progress map by book ID: BookId -> ItemIndex -> Progress
typedef ProgressMapById = Map<int, Map<String, PageProgress>>;

/// OLD (deprecated): Full progress map: Category -> Book -> Page/Item -> Progress
/// This will be removed in a future version
typedef FullProgressMap = Map<String, Map<String, Map<String, PageProgress>>>;

/// NEW: Completion dates by book ID: BookId -> Completion Date (Hebrew)
typedef CompletionDatesByIdMap = Map<int, String>;

/// OLD (deprecated): Completion dates map: Category -> Book -> Completion Date (Hebrew)
/// This will be removed in a future version
typedef CompletionDatesMap = Map<String, Map<String, String>>;

/// Book progress summary for display purposes
class BookProgressSummary {
  final String categoryName;
  final String bookName;
  final int totalItems;
  final int completedItems;
  final int inProgressItems;
  final String? completionDate;
  final DateTime? lastAccessed;
  final bool isActiveReview;

  const BookProgressSummary({
    required this.categoryName,
    required this.bookName,
    required this.totalItems,
    required this.completedItems,
    required this.inProgressItems,
    this.completionDate,
    this.lastAccessed,
    this.isActiveReview = false,
  });

  /// Get progress as a percentage (0.0 to 1.0)
  double get progressPercentage =>
      totalItems > 0 ? completedItems / totalItems : 0.0;

  /// Check if the book is completed
  bool get isCompleted => completedItems == totalItems && totalItems > 0;

  /// Check if the book has any progress
  bool get hasProgress => completedItems > 0 || inProgressItems > 0;

  /// Get status text for display based on current cycle
  String getStatusText(int currentCycle) {
    if (totalItems <= 0) {
      return 'לימוד פעיל';
    }

    final progress = progressPercentage;

    // הודעות לפי אחוז ההשלמה
    if (progress == 0.0) {
      return 'עדיין לא התחלת!';
    } else if (progress < 0.15) {
      return 'התחלה מצוינת!';
    } else if (progress < 0.30) {
      return 'התחלה מצוינת!';
    } else if (progress < 0.50) {
      return 'שליש הדרך כבר הושלם!';
    } else if (progress < 0.60) {
      return 'חצי הדרך מאחוריך!';
    } else if (progress < 0.75) {
      return 'רוב הדרך כבר מאחוריך!';
    } else if (progress < 1.0) {
      return 'הסוף כבר באופק!';
    } else {
      // 100% - הודעה לפי מחזור
      switch (currentCycle) {
        case 1:
          return 'סיימת מחזור ראשון בהצלחה!';
        case 2:
          return 'סיימת מחזור שני בהצלחה!';
        case 3:
          return 'סיימת מחזור שלישי בהצלחה!';
        case 4:
          return 'סיימת מחזור רביעי בהצלחה!';
        default:
          return 'הושלם בהצלחה!';
      }
    }
  }

  /// Get status text for display (backward compatibility)
  String get statusText => getStatusText(1);

  /// Create a modified copy of this summary.
  BookProgressSummary copyWith({
    int? totalItems,
    int? completedItems,
    int? inProgressItems,
    String? completionDate,
    DateTime? lastAccessed,
    bool? isActiveReview,
  }) {
    return BookProgressSummary(
      categoryName: categoryName,
      bookName: bookName,
      totalItems: totalItems ?? this.totalItems,
      completedItems: completedItems ?? this.completedItems,
      inProgressItems: inProgressItems ?? this.inProgressItems,
      completionDate: completionDate ?? this.completionDate,
      lastAccessed: lastAccessed ?? this.lastAccessed,
      isActiveReview: isActiveReview ?? this.isActiveReview,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookProgressSummary &&
          runtimeType == other.runtimeType &&
          categoryName == other.categoryName &&
          bookName == other.bookName &&
          totalItems == other.totalItems &&
          completedItems == other.completedItems &&
          inProgressItems == other.inProgressItems &&
          completionDate == other.completionDate &&
          lastAccessed == other.lastAccessed &&
          isActiveReview == other.isActiveReview;

  @override
  int get hashCode =>
      categoryName.hashCode ^
      bookName.hashCode ^
      totalItems.hashCode ^
      completedItems.hashCode ^
      inProgressItems.hashCode ^
      completionDate.hashCode ^
      lastAccessed.hashCode ^
      isActiveReview.hashCode;

  @override
  String toString() {
    return 'BookProgressSummary(categoryName: $categoryName, bookName: $bookName, '
        'progress: $completedItems/$totalItems, activeReview: $isActiveReview, '
        'status: $statusText)';
  }
}
