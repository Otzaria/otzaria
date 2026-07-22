import 'package:flutter/widgets.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// קו העוגן (חלק מ-0..1 מגובה ה-viewport) שאליו הניווט מיישר את תחילת הקטע,
/// וגם הקו שלפיו נקבע "המיקום הנוכחי" בספר (ההדגשה בסרגל הניווט). שני הצדדים
/// חייבים להשתמש באותו ערך כדי שההדגשה תתאים בדיוק למקום שהניווט מוביל אליו.
const double kReadingAnchorAlignment = 0.05;

/// קו העוגן לניווט אל תוצאת חיפוש — ממקם את המילה שנמצאה סביב מרכז-עליון
/// התצוגה (ולא בראש), כדי שיהיה הקשר גם מעל המילה. זהה לסרגל התוצאות בחלונית
/// ולפתיחת ספר מהחיפוש הכללי.
const double kSearchResultAnchorAlignment = 0.35;

/// סבילות סיווג סביב קו העוגן. חייבת להיות גדולה מ-[kAnchorLandingEpsilon]
/// (שגיאת נחיתה מותרת) וקטנה מגובה שורת טקסט (~0.025) - אחרת הסיווג מתהפך.
const double _anchorRemnantTolerance = 0.008;

/// סף עצירה לדיוק העדין האיטרטיבי (חלק מה-viewport): מתחת למרחק הזה מהעוגן
/// הניווט נחשב "הגיע". חייב להישאר קטן מ-[_anchorRemnantTolerance].
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

ItemPosition? _findPosition(ItemPositionsListener listener, int segmentIndex) {
  for (final position in listener.itemPositions.value) {
    if (position.index == segmentIndex) {
      return position;
    }
  }
  return null;
}

/// גלילה לשורת מקור [lineIndex] תוך תרגום אוטומטי לסגמנט.
///
/// [intraLineFraction] (0..1) הוא מיקום היעד בתוך השורה (למשל מילת חיפוש בתוך
/// פסקה ארוכה). כשהסגמנט כבר גלוי מתבצעת גלילה יחסית אחת ישירות אל היעד — בלי
/// קפיצה לתחילת הסגמנט ואז תיקון — כדי שלא ייראה "זיגזג" כשמתחילים מתחת ליעד.
Future<void> scrollToSourceLine({
  required ItemScrollController scrollController,
  required ScrollOffsetController? scrollOffsetController,
  required ItemPositionsListener? positionsListener,
  required List<ReadingSegment> segments,
  required int lineIndex,
  required double viewportExtent,
  double alignment = kReadingAnchorAlignment,
  double intraLineFraction = 0,
  Duration duration = const Duration(milliseconds: 250),
  Curve curve = Curves.ease,
}) async {
  if (segments.isEmpty || !scrollController.isAttached) {
    return;
  }

  final safeLineIndex = lineIndex
      .clamp(
        segments.first.startLineIndex,
        segments.last.sourceLineIndices.last,
      )
      .toInt();
  final segmentIndex = segmentIndexForLine(segments, safeLineIndex);
  final segment = segments[segmentIndex];
  final fraction = lineFractionWithinSegment(
    segment,
    safeLineIndex,
    intraLineFraction: intraLineFraction,
  );

  Future<void> scrollToSegment() async {
    if (duration == Duration.zero) {
      scrollController.jumpTo(index: segmentIndex, alignment: alignment);
    } else {
      await scrollController.scrollTo(
        index: segmentIndex,
        alignment: alignment,
        duration: duration,
        curve: curve,
      );
    }
  }

  // ללא דיוק תוך-סגמנט — גלילה רגילה לתחילת הסגמנט.
  if (fraction <= 0 ||
      scrollOffsetController == null ||
      positionsListener == null ||
      viewportExtent <= 0) {
    await scrollToSegment();
    return;
  }

  // משך הגלילה היחסית. `animateScroll` עוטף את `ScrollController.animateTo`,
  // שזורק assert על `Duration.zero`; לכן מצב מיידי מתורגם לדיוק עדין קצר.
  final fineDuration = duration == Duration.zero
      ? const Duration(milliseconds: 120)
      : duration;

  // הסגמנט אינו גלוי — גלילה גסה אליו תחילה.
  if (_findPosition(positionsListener, segmentIndex) == null) {
    await scrollToSegment();
    await WidgetsBinding.instance.endOfFrame;
  }

  // דיוק עדין איטרטיבי: viewportExtent הוא קירוב מההקשר הקורא, ולכן צעד
  // יחיד מפספס ביחס הסטייה - מודדים ומתקנים עד שהיעד יושב על קו העוגן.
  var stepDuration = fineDuration;
  var previousDistance = double.infinity;
  for (var attempt = 0; attempt < 5; attempt++) {
    final measured = _findPosition(positionsListener, segmentIndex);
    if (measured == null) {
      return;
    }
    final extent =
        (measured.itemTrailingEdge - measured.itemLeadingEdge) * viewportExtent;
    if (!extent.isFinite || extent <= 0) {
      return;
    }
    final delta =
        measured.itemLeadingEdge * viewportExtent +
        fraction * extent -
        alignment * viewportExtent;
    // יעד קרוב מספיק, או שאין התכנסות (קירוב גובה קיצוני) - עוצרים.
    if (delta.abs() <= viewportExtent * kAnchorLandingEpsilon ||
        delta.abs() >= previousDistance) {
      return;
    }
    previousDistance = delta.abs();
    await scrollOffsetController.animateScroll(
      offset: delta,
      duration: stepDuration,
      curve: attempt == 0 ? curve : Curves.easeOut,
    );
    await WidgetsBinding.instance.endOfFrame;
    stepDuration = const Duration(milliseconds: 120);
  }
}
