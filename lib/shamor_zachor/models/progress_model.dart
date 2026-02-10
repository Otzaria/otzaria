/// Represents the progress for a single page/item
/// Includes initial learning and up to 3 reviews
class PageProgress {
  bool learn;
  bool review1;
  bool review2;
  bool review3;

  PageProgress({
    this.learn = false,
    this.review1 = false,
    this.review2 = false,
    this.review3 = false,
  });

  /// Convert to JSON for storage
  Map<String, bool> toJson() => {
        'learn': learn,
        'review1': review1,
        'review2': review2,
        'review3': review3,
      };

  /// Create from JSON data
  factory PageProgress.fromJson(Map<String, dynamic> json) {
    return PageProgress(
      learn: json['learn'] ?? false,
      review1: json['review1'] ?? false,
      review2: json['review2'] ?? false,
      review3: json['review3'] ?? false,
    );
  }

  /// Check if no progress has been made
  bool get isEmpty => !learn && !review1 && !review2 && !review3;

  /// Check if all learning and reviews are complete
  bool get isComplete => learn && review1 && review2 && review3;

  /// Get the number of completed items (learn + reviews)
  int get completedCount {
    int count = 0;
    if (learn) count++;
    if (review1) count++;
    if (review2) count++;
    if (review3) count++;
    return count;
  }

  /// Get progress as a percentage (0.0 to 1.0)
  double get progressPercentage => completedCount / 4.0;

  /// Set a specific property by name
  void setProperty(String propertyName, bool value) {
    switch (propertyName) {
      case 'learn':
        learn = value;
        break;
      case 'review1':
        review1 = value;
        break;
      case 'review2':
        review2 = value;
        break;
      case 'review3':
        review3 = value;
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
  }) {
    return PageProgress(
      learn: learn ?? this.learn,
      review1: review1 ?? this.review1,
      review2: review2 ?? this.review2,
      review3: review3 ?? this.review3,
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
          review3 == other.review3;

  @override
  int get hashCode =>
      learn.hashCode ^ review1.hashCode ^ review2.hashCode ^ review3.hashCode;

  @override
  String toString() {
    return 'PageProgress(learn: $learn, review1: $review1, review2: $review2, review3: $review3)';
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
