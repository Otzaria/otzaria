// לתחזוקת הסיור המודרך ראו: docs/guided_tour_developer_guide.md

import 'package:equatable/equatable.dart';

enum TourSpotlightArea {
  center,
  fullScreen,
  navigation,
  librarySearch,
  libraryCategories,
  bookCard,
  findRef,
  reading,
  tabs,
  tableOfContents,
  commentators,
  bookmark,
  bookSearch,
  readingSettings,
  print,
  searchDialog,
  tools,
  settings,
  designSettings,
  emptyLibrary,
}

/// קיצור המקלדת שממלא את ה-placeholder `{shortcut}` שב-[TourStep.body].
/// הקיצור נפתר בעת הציור ולא בעת בניית השלב, כדי ש-[TourStep.body] יישאר
/// מחרוזת קבועה — כלומר מפתח תרגום.
enum TourShortcutHint {
  none,

  /// כל שש תוויות הניווט, כל אחת עם הקיצור שלה.
  mainNavigation,
  findRef,
  reading,
  search,
  tools,
  settings,
}

enum TourStepAction {
  none,
  openLibrary,
  openLibraryHome,
  openLibraryBookPreview,
  openFindRef,
  openReading,
  openSearch,
  openTools,
  openSettings,
  openDesignSettings,
}

class TourStep extends Equatable {
  final String id;
  final String title;
  final String body;
  final TourSpotlightArea area;
  final TourStepAction action;
  final bool isDialog;
  final TourShortcutHint shortcut;

  const TourStep({
    required this.id,
    required this.title,
    required this.body,
    required this.area,
    this.action = TourStepAction.none,
    this.isDialog = false,
    this.shortcut = TourShortcutHint.none,
  });

  @override
  List<Object?> get props => [
    id,
    title,
    body,
    area,
    action,
    isDialog,
    shortcut,
  ];
}
