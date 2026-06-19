/// עמודת מעקב בטבלת ההתקדמות (לימוד / חזרה / מפרש).
///
/// [id] מזהה יציב שלפיו נשמרת ההתקדמות; [label] השם המוצג, ניתן לעריכה.
class ProgressColumn {
  final String id;
  final String label;

  const ProgressColumn({required this.id, required this.label});

  factory ProgressColumn.fromJson(Map<String, dynamic> json) => ProgressColumn(
        id: json['id'] as String,
        label: json['label'] as String,
      );

  Map<String, dynamic> toJson() => {'id': id, 'label': label};

  ProgressColumn copyWith({String? label}) =>
      ProgressColumn(id: id, label: label ?? this.label);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProgressColumn &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          label == other.label;

  @override
  int get hashCode => id.hashCode ^ label.hashCode;

  @override
  String toString() => 'ProgressColumn(id: $id, label: $label)';
}

/// עמודות ברירת המחדל לספר ללא הגדרה מותאמת.
/// המזהים תואמים לנתונים ההיסטוריים (learn/review1/2/3) לשמירת תאימות אחורה.
const List<ProgressColumn> kDefaultProgressColumns = [
  ProgressColumn(id: 'learn', label: 'לימוד'),
  ProgressColumn(id: 'review1', label: 'חזרה 1'),
  ProgressColumn(id: 'review2', label: 'חזרה 2'),
  ProgressColumn(id: 'review3', label: 'חזרה 3'),
];

/// Represents the progress for a single page/item.
///
/// ההתקדמות נשמרת כמפה דינמית של מזהה-עמודה → סומן, כדי לתמוך במספר עמודות
/// משתנה ובשמות מותאמים. רק עמודות מסומנות נשמרות במפה.
class PageProgress {
  final Map<String, bool> _done;

  PageProgress({
    bool learn = false,
    bool review1 = false,
    bool review2 = false,
    bool review3 = false,
  }) : _done = {
          if (learn) 'learn': true,
          if (review1) 'review1': true,
          if (review2) 'review2': true,
          if (review3) 'review3': true,
        };

  PageProgress._fromMap(this._done);

  /// Convert to JSON for storage (only checked columns are stored)
  Map<String, bool> toJson() => Map<String, bool>.from(_done);

  /// Create from JSON data (any column id → bool)
  factory PageProgress.fromJson(Map<String, dynamic> json) {
    final done = <String, bool>{};
    json.forEach((key, value) {
      if (value == true) done[key] = true;
    });
    return PageProgress._fromMap(done);
  }

  // Getters לתאימות אחורה עם העמודות ההיסטוריות
  bool get learn => _done['learn'] ?? false;
  bool get review1 => _done['review1'] ?? false;
  bool get review2 => _done['review2'] ?? false;
  bool get review3 => _done['review3'] ?? false;

  /// Check if no progress has been made
  bool get isEmpty => _done.isEmpty;

  /// מספר העמודות המסומנות בפריט זה
  int get completedCount => _done.length;

  /// תאימות אחורה: הושלם לפי עמודות ברירת המחדל
  bool get isComplete => learn && review1 && review2 && review3;

  /// האם כל העמודות שברשימה מסומנות בפריט זה
  bool isCompleteFor(List<String> columnIds) =>
      columnIds.isNotEmpty && columnIds.every((id) => _done[id] == true);

  /// כמה מבין העמודות שברשימה מסומנות בפריט זה
  int completedCountFor(List<String> columnIds) =>
      columnIds.where((id) => _done[id] == true).length;

  /// Set a specific column by id
  void setProperty(String columnId, bool value) {
    if (value) {
      _done[columnId] = true;
    } else {
      _done.remove(columnId);
    }
  }

  /// Get a specific column by id
  bool getProperty(String columnId) => _done[columnId] ?? false;

  /// מסיר עמודה מההתקדמות (בעת מחיקת עמודה מהספר)
  void removeColumn(String columnId) => _done.remove(columnId);

  /// Create a copy with modified values
  PageProgress copyWith({
    bool? learn,
    bool? review1,
    bool? review2,
    bool? review3,
  }) {
    final next = Map<String, bool>.from(_done);
    void apply(String id, bool? value) {
      if (value == null) return;
      if (value) {
        next[id] = true;
      } else {
        next.remove(id);
      }
    }

    apply('learn', learn);
    apply('review1', review1);
    apply('review2', review2);
    apply('review3', review3);
    return PageProgress._fromMap(next);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PageProgress || runtimeType != other.runtimeType) {
      return false;
    }
    if (_done.length != other._done.length) return false;
    for (final entry in _done.entries) {
      if (other._done[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    int hash = 0;
    for (final entry in _done.entries) {
      hash ^= entry.key.hashCode ^ entry.value.hashCode;
    }
    return hash;
  }

  @override
  String toString() => 'PageProgress($_done)';
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
