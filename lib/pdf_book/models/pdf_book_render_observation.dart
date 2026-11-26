/// תמונת מצב לקריאה בלבד של השכבות שבבעלות מסך הספר.
///
/// מוכנות המציג לבדה אינה מוכנות הספר: צילום של הכפולה הקודמת יכול עדיין
/// לכסות אותו בזמן דפדוף. אין כאן קריאת פיקסלים או מדידת הצגה על ה-GPU.
class PdfBookRenderObservation {
  const PdfBookRenderObservation({
    required this.visible,
    required this.bookView,
    required this.layoutReady,
    required this.viewerState,
    required this.visiblePages,
    required this.hasTransitionOverlay,
    required this.pageTurnActive,
    required this.animationRunning,
    required this.queuedTurns,
  });

  final bool visible;
  final bool bookView;
  final bool layoutReady;
  final String viewerState;
  final List<int> visiblePages;
  final bool hasTransitionOverlay;
  final bool pageTurnActive;
  final bool animationRunning;
  final int queuedTurns;

  /// כפולת היעד הגלויה כבר מצוירת במציג, וכל שכבות המעבר הוסרו.
  bool finalImageReadyFor(int pageNumber) =>
      visible &&
      bookView &&
      layoutReady &&
      viewerState == 'ready' &&
      visiblePages.contains(pageNumber) &&
      !hasTransitionOverlay &&
      !pageTurnActive &&
      !animationRunning &&
      queuedTurns == 0;

  Map<String, Object?> toJson() => {
    'visible': visible,
    'bookView': bookView,
    'layoutReady': layoutReady,
    'viewerState': viewerState,
    'visiblePages': visiblePages,
    'hasTransitionOverlay': hasTransitionOverlay,
    'pageTurnActive': pageTurnActive,
    'animationRunning': animationRunning,
    'queuedTurns': queuedTurns,
    'readinessEndpoint': 'liveViewerAfterTransitionLayersRemoved',
    'gpuPresentation': 'notMeasured',
  };
}
