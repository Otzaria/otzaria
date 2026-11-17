/// מהירות שחרור (בעמודים לוגיים: פיקסלים/שנייה) שמעליה ההחלקה נחשבת הנפה
/// ומעבירה טאב גם לפני מחצית הדרך.
const double kTabSwipeFlingVelocity = 250.0;

/// מרחק הגרירה המינימלי (בפיקסלים לוגיים) כדי שהנפה תעביר טאב.
const double kTabSwipeFlingMinDistance = 48.0;

/// הטאב שעליו מתיישבים בסוף מחוות החלקה.
///
/// [page] - העמוד השבור בשחרור
/// [anchorIndex] - הטאב הנבחר בתחילת המחווה
/// [draggedPages] - התזוזה שהגרירה עצמה הפעילה, בעמודים
/// [pageVelocity] - מהירות השחרור, חיובית לכיוון אינדקס גבוה יותר
/// [tabCount] - מספר הטאבים
/// [viewportExtent] - רוחב העמוד בפיקסלים לוגיים
/// [crossAxisDistance] - התזוזה האנכית של המחווה, בפיקסלים לוגיים
int tabSwipeSettleIndex({
  required double page,
  required int anchorIndex,
  required double draggedPages,
  required double pageVelocity,
  required int tabCount,
  required double viewportExtent,
  double crossAxisDistance = 0,
}) {
  final draggedDistance = (draggedPages * viewportExtent).abs();
  int target;
  if (crossAxisDistance > draggedDistance) {
    // רוב המחווה אנכית: גלילה שהתחילה בסטייה אופקית.
    target = anchorIndex;
  } else if (pageVelocity.abs() < kTabSwipeFlingVelocity) {
    target = page.round();
  } else if (draggedDistance < kTabSwipeFlingMinDistance) {
    target = anchorIndex;
  } else {
    // נמדד מהטאב הנבחר ולא מהתצוגה: מחווה שהתחילה באמצע אנימציית
    // ההתיישבות הקודמת אחרת נוחתת שוב על אותו טאב.
    final fromAnchor = anchorIndex + draggedPages;
    target = pageVelocity > 0 ? fromAnchor.floor() + 1 : fromAnchor.ceil() - 1;
  }
  return target.clamp(0, tabCount - 1);
}
