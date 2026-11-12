import 'package:flutter/widgets.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:otzaria/widgets/lists/jump_aware_item_scroll_controller.dart';
import 'package:otzaria/widgets/smart_text/long_line_chunks.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

export 'package:otzaria/text_book/utils/reading_extent_estimates.dart';

/// קו היישור לניווט ולמדידת מיקום הקריאה, כחלק מגובה התצוגה.
const double kReadingAnchorAlignment = 0.05;

/// הפריט הראשון נפתח בקצה, בלי להוסיף רווח שאי אפשר לחזור אליו בגלילה.
double initialReadingAlignment(int initialIndex) =>
    initialIndex == 0 ? 0 : kReadingAnchorAlignment;

/// טווח המטמון של רשימות הקריאה, במסכים לכל צד. כל קפיצה בונה אותו מחדש,
/// וברירת המחדל של החבילה (2) בונה כחמישה מסכים של פסקאות.
const double kReaderCacheExtentScreens = 1.5;

/// יישור תוצאת חיפוש משאיר הקשר מעל המילה שנמצאה.
const double kSearchResultAnchorAlignment = 0.35;

/// סבילות סיווג סביב קו העוגן. חייבת להיות גדולה מ-[kAnchorLandingEpsilon]
/// (שגיאת נחיתה מותרת) וקטנה מגובה שורת טקסט (~0.025) - אחרת הסיווג מתהפך.
const double _anchorRemnantTolerance = 0.008;

/// סבילות הנחיתה כחלק מהתצוגה; קטנה מסבילות הסיווג של שייר פסקה.
const double kAnchorLandingEpsilon = 0.003;

/// כמה מהקטע (חלק מה-viewport) נמצא ב"אזור הקריאה" - מתחת לקו העוגן.
double _readingZonePresence(double leadingEdge, double trailingEdge) {
  final top = leadingEdge < kReadingAnchorAlignment
      ? kReadingAnchorAlignment
      : leadingEdge;
  final bottom = trailingEdge > 1.0 ? 1.0 : trailingEdge;
  final presence = bottom - top;
  return presence < 0 ? 0 : presence;
}

/// האם קטע ([leadingEdge]..[trailingEdge]) הוא שייר של הסעיף הקודם: מתחיל
/// משמעותית מעל קו העוגן ונגמר בו. קטע שמתחיל בעוגן עצמו הוא יעד הניווט.
bool isRemnantAbovePositionAnchor(double leadingEdge, double trailingEdge) =>
    kReadingAnchorAlignment - leadingEdge > _anchorRemnantTolerance &&
    _readingZonePresence(leadingEdge, trailingEdge) <= _anchorRemnantTolerance;

/// סוגר את חלונית הצד רק אחרי שגלילת [navigation] הסתיימה: סגירה תוך כדי
/// הגלילה מפעילה עיגון-מחדש של הטקסט שמבטל את האנימציה והניווט לא מתבצע.
Future<void> closePaneAfterNavigation({
  required Future<void> navigation,
  required void Function() closePane,
}) async {
  try {
    await navigation;
  } finally {
    closePane();
  }
}

/// פותר נקודה בשורת מקור לאחר פריסת פריט הרשימה ולפני ציורו.
TargetRectResolver readingAnchorTargetRectResolver({
  required ReadingSegments Function() segments,
  required int lineIndex,
  double intraLineFraction = 0,
  MeasuredLineExtent? measure,
  bool Function()? isCurrent,
}) => (item, box) {
  if (!(isCurrent?.call() ?? true)) return null;
  final current = segments();
  if (current.isEmpty) return null;
  final line = lineIndex.clamp(0, current.layout.lineCount - 1);
  if (current.layout.itemForLine(line) != item) return null;
  final within = intraLineFraction.clamp(0.0, 1.0);
  final measured = measure?.call(item, line);
  final fraction = measured == null
      ? lineFractionInItem(current, item, line, intraLineFraction: within)
      : measured.top + within * (measured.bottom - measured.top);
  return Rect.fromLTWH(0, fraction * box.size.height, 0, 0);
};

/// מיישר שורת מקור מדודה; בשורה שנבנית בהדרגה ממתין לגובהה הסופי.
Future<void> scrollToSourceLine({
  required ItemScrollController scrollController,
  required ItemPositionsListener? positionsListener,
  required ReadingSegments segments,
  required int lineIndex,
  double alignment = kReadingAnchorAlignment,
  double intraLineFraction = 0,
  Duration duration = const Duration(milliseconds: 250),
  Curve curve = Curves.ease,
  ReadingSegments Function()? latestSegments,
  bool Function()? isCurrent,
  MeasuredLineExtent? measure,
}) async {
  if (segments.isEmpty ||
      !scrollController.isAttached ||
      !(isCurrent?.call() ?? true)) {
    return;
  }
  ReadingSegments current() => latestSegments?.call() ?? segments;
  final initial = current();
  if (initial.isEmpty) return;
  final line = lineIndex.clamp(0, initial.layout.lineCount - 1);
  final item = initial.layout.itemForLine(line);
  final resolver = readingAnchorTargetRectResolver(
    segments: current,
    lineIndex: lineIndex,
    intraLineFraction: intraLineFraction,
    measure: measure,
    isCurrent: isCurrent,
  );
  final visible =
      positionsListener?.itemPositions.value.any(
        (p) =>
            p.index == item && p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1,
      ) ??
      false;
  Future<void> move() => duration == Duration.zero
      ? scrollController.jumpToAsync(
          index: item,
          alignment: alignment,
          targetRectResolver: resolver,
        )
      : scrollController.scrollTo(
          index: item,
          alignment: alignment,
          duration: duration,
          curve: curve,
          targetRectResolver: resolver,
        );
  final controller = scrollController;
  await (visible && controller is JumpAwareItemScrollController
      ? controller.withoutNotifying(move)
      : move());
  final pixels = scrollController.scrollController;
  if (pixels == null) return;
  if (!await longLinesBuilt(
        scrollController: pixels,
        isCurrent: isCurrent,
      ) ||
      !scrollController.isAttached ||
      !(isCurrent?.call() ?? true)) {
    return;
  }
  final settled = current();
  if (settled.isEmpty) return;
  final settledLine = lineIndex.clamp(0, settled.layout.lineCount - 1);
  Future<void> settle() => scrollController.jumpToAsync(
    index: settled.layout.itemForLine(settledLine),
    alignment: alignment,
    targetRectResolver: resolver,
  );
  await (controller is JumpAwareItemScrollController
      ? controller.withoutNotifying(settle)
      : settle());
}
