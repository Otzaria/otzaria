import 'package:flutter/widgets.dart';
import 'package:otzaria/widgets/lists/jump_aware_item_scroll_controller.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// קו העוגן (חלק מ-0..1 מגובה ה-viewport) שאליו הניווט מיישר את תחילת הקטע,
/// וגם הקו שלפיו נקבע "המיקום הנוכחי" בספר (ההדגשה בסרגל הניווט). שני הצדדים
/// חייבים להשתמש באותו ערך כדי שההדגשה תתאים בדיוק למקום שהניווט מוביל אליו.
const double kReadingAnchorAlignment = 0.05;

/// היישור שבו נפתחת רשימת הקריאה. מעל הפריט הראשון אין תוכן, ולכן קו העוגן
/// אינו בר-השגה שם: הפתיחה מציגה רווח ריק שנעלם בגלילה הראשונה ואינו חוזר.
double initialReadingAlignment(int initialIndex) =>
    initialIndex == 0 ? 0 : kReadingAnchorAlignment;

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
///
/// הנחיתה נמדדת ומתוקנת גם ליעד ללא דיוק תוך-שורתי (ניווט מכותרות/TOC):
/// רה-פריסה תוך כדי האנימציה (טעינה הדרגתית) מסיטה את היעד, ובלי תיקון נשארים במקום.
///
/// [latestSegments] פותר מחדש את היעד כשטעינת רקע מחליפה את הסגמנטים;
/// בלעדיו משתמשים ב-[segments] לאורך כל הגלילה.
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
  List<ReadingSegment> Function()? latestSegments,
}) async {
  if (segments.isEmpty || !scrollController.isAttached) {
    return;
  }

  if (scrollController is JumpAwareItemScrollController) {
    scrollController.beginNavigation();
  }
  var segmentIndex = -1;
  var fraction = 0.0;
  var safeLineIndex = lineIndex;
  // היעד נפתר מול הרשימה העדכנית כי טעינת רקע משנה את מספור הסגמנטים.
  bool resolveTarget() {
    final current = latestSegments?.call() ?? segments;
    if (current.isEmpty) return false;
    safeLineIndex = lineIndex
        .clamp(
          current.first.startLineIndex,
          current.last.sourceLineIndices.last,
        )
        .toInt();
    segmentIndex = segmentIndexForLine(current, safeLineIndex);
    fraction = lineFractionWithinSegment(
      current[segmentIndex],
      safeLineIndex,
      intraLineFraction: intraLineFraction,
    );
    return true;
  }

  if (!resolveTarget()) return;
  if (scrollController is JumpAwareItemScrollController &&
      scrollController.externalScroll != null) {
    await scrollController.scrollTo(
      index: segmentIndex,
      sourceLineIndex: safeLineIndex,
      alignment: alignment,
      duration: duration,
      curve: curve,
    );
    return;
  }

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

  // בלי כלי מדידה אין אפשרות לאמת את הנחיתה — גלילה רגילה בלבד.
  if (scrollOffsetController == null ||
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

  // הסגמנט אינו גלוי — קפיצה ולא גלילה מונפשת: המעבר בין שתי הרשימות של
  // החבילה דורש 2 מסכי גלילה, ונעצר על יעד שגוי כששורות שטרם נטענו בגובה ~0.
  if (_findPosition(positionsListener, segmentIndex) == null) {
    scrollController.jumpTo(index: segmentIndex, alignment: alignment);
    await WidgetsBinding.instance.endOfFrame;
  }

  // דיוק עדין איטרטיבי: viewportExtent הוא קירוב מההקשר הקורא, ולכן צעד
  // יחיד מפספס ביחס הסטייה - מודדים ומתקנים עד שהיעד יושב על קו העוגן.
  var stepDuration = fineDuration;
  var previousDistance = double.infinity;
  var confirming = false;
  // קפיצה אחת אחרי שהרשימה הוחלפה: היעד נפתר מחדש, אך הפריט החדש טרם נבנה.
  var rejumped = false;
  for (var attempt = 0; attempt < 5; attempt++) {
    // הרשימה יורדת מהעץ באמצע האנימציה (מעבר כרטיסיה, סגירתה, העברתה לחלון
    // אחר), או מוחלפת בקורא חיצוני — מדידות ישנות אינן מעידות שהרשימה חיה.
    if (!scrollController.isAttached ||
        (scrollController is JumpAwareItemScrollController &&
            !scrollController.isNativeAttached)) {
      return;
    }
    final previousIndex = segmentIndex;
    if (!resolveTarget()) return;
    if (segmentIndex != previousIndex) {
      // המרחק שנמדד מול הסגמנט הישן אינו רלוונטי אחרי החלפת הרשימה.
      previousDistance = double.infinity;
      confirming = false;
    }
    final measured = _findPosition(positionsListener, segmentIndex);
    if (measured == null) {
      if (rejumped) return;
      rejumped = true;
      scrollController.jumpTo(index: segmentIndex, alignment: alignment);
      await WidgetsBinding.instance.endOfFrame;
      continue;
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
    if (delta.abs() <= viewportExtent * kAnchorLandingEpsilon) {
      // היעד על קו העוגן - מאמתים במסך הבא, כי רה-פריסה (טעינה הדרגתית או
      // החלפת הרשימות של החבילה) מסיטה אותו דווקא אחרי המדידה הזו.
      if (confirming) {
        return;
      }
      confirming = true;
      previousDistance = double.infinity;
      await WidgetsBinding.instance.endOfFrame;
      continue;
    }
    // אין התכנסות (קירוב גובה קיצוני) - עוצרים.
    if (delta.abs() >= previousDistance) {
      return;
    }
    confirming = false;
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
