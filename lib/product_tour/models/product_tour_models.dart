import 'package:equatable/equatable.dart';

/// סטטוס הסיור הראשי כפי שנשמר למשתמש.
enum ProductTourStatus {
  unseen,
  dismissed,
  completed,
}

/// מזהי היעדים שאליהם ניתן לעגן שלבים וטיפים.
enum TourTargetId {
  librarySearch,
  findRefField,
  searchDialogField,
  readingTabsBar,
  readingViewMode,
  readingContent,
}

/// מזהי הטיפים החיים במערכת.
enum LiveTipId {
  sideBySideSuggestion,
  dictionaryContextMenuHint,
  commentaryHint,
}

/// סוגי אינטראקציות שהמערכת אוספת לצורך הדרכה חיה.
enum TourInteractionType {
  libraryReady,
  currentTabChanged,
  openedTextBook,
  sideBySideEnabled,
  textSelected,
  dictionaryUsed,
  commentaryAvailable,
  commentaryUsed,
}

/// הגדרת שלב אחד בסיור ההיכרות.
class TourStepSpec extends Equatable {
  final String id;
  final TourTargetId targetId;
  final String title;
  final String description;

  const TourStepSpec({
    required this.id,
    required this.targetId,
    required this.title,
    required this.description,
  });

  @override
  List<Object?> get props => [id, targetId, title, description];
}

/// הגדרת טיפ חי אחד.
class LiveTipSpec extends Equatable {
  final LiveTipId id;
  final TourTargetId targetId;
  final String title;
  final String description;

  const LiveTipSpec({
    required this.id,
    required this.targetId,
    required this.title,
    required this.description,
  });

  @override
  List<Object?> get props => [id, targetId, title, description];
}

/// אינטראקציה בודדת של המשתמש לצורך זיהוי טיפים חיים.
class TourInteraction extends Equatable {
  final TourInteractionType type;
  final DateTime timestamp;
  final String? primaryValue;
  final String? secondaryValue;

  TourInteraction({
    required this.type,
    DateTime? timestamp,
    this.primaryValue,
    this.secondaryValue,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  List<Object?> get props => [
        type,
        timestamp.millisecondsSinceEpoch,
        primaryValue,
        secondaryValue,
      ];
}
