/// מהירות שחרור (בעמודים לוגיים: פיקסלים/שנייה) שמעליה ההחלקה נחשבת הנפה
/// ומעבירה טאב גם לפני מחצית הדרך.
const double kTabSwipeFlingVelocity = 250.0;

/// הטאב שעליו מתיישבים בסוף מחוות החלקה.
///
/// [page] - העמוד השבור בשחרור
/// [anchorIndex] - הטאב הנבחר בתחילת המחווה
/// [draggedPages] - התזוזה שהגרירה עצמה הפעילה, בעמודים
/// [pageVelocity] - מהירות השחרור, חיובית לכיוון אינדקס גבוה יותר
/// [tabCount] - מספר הטאבים
int tabSwipeSettleIndex({
  required double page,
  required int anchorIndex,
  required double draggedPages,
  required double pageVelocity,
  required int tabCount,
}) {
  int target;
  if (pageVelocity.abs() >= kTabSwipeFlingVelocity) {
    // נמדד מהטאב הנבחר ולא מהתצוגה: מחווה שהתחילה באמצע אנימציית
    // ההתיישבות הקודמת אחרת נוחתת שוב על אותו טאב.
    final fromAnchor = anchorIndex + draggedPages;
    target = pageVelocity > 0 ? fromAnchor.floor() + 1 : fromAnchor.ceil() - 1;
  } else {
    target = page.round();
  }
  return target.clamp(0, tabCount - 1);
}
