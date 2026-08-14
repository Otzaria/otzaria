import 'package:flutter/foundation.dart';
import 'package:otzaria/models/links.dart';

/// מסנכרן בחירת טקסט בין כמה אזורי SelectionArea באותו מסך.
///
/// ל-SelectionArea של Flutter אין API ישיר ל"נקה בחירה באזור אחר",
/// לכן כל אזור מאזין לגרסה (`revision`) ומבצע rebuild מקומי כשהבחירה
/// עברה לאזור אחר.
///
/// בנוסף לבעלות, ה-controller נושא גם את הטקסט שנבחר (והמפרש שממנו — לצורך
/// כותרות בהעתקה) אצל הבעלים הנוכחי. כך מטפל העתקה במקלדת (Ctrl+C) יכול
/// להעתיק את בחירת המפרשים גם כשה-focus אינו בתוך ה-SelectionArea שלהם —
/// לדוגמה במצב 'מפרשים מתחת' שבו כרטיס המפרשים עטוף ב-SelectionArea נפרד.
class SelectionSyncController extends ChangeNotifier {
  int _revision = 0;
  Object? _activeOwner;
  String? _activeSelectionText;
  Link? _activeSelectionLink;

  int get revision => _revision;
  Object? get activeOwner => _activeOwner;

  /// הטקסט שנבחר אצל הבעלים הנוכחי (null כשאין בחירה פעילה).
  String? get activeSelectionText => _activeSelectionText;

  /// המפרש שממנו נבחר הטקסט — לייחוס הכותרת בהעתקה עם כותרות.
  /// null כשהבחירה אינה שייכת למפרש בודד (או שזהו טקסט ראשי).
  Link? get activeSelectionLink => _activeSelectionLink;

  void activate(
    Object owner, {
    String? selectionText,
    Link? selectionLink,
  }) {
    final changedOwner = !identical(_activeOwner, owner);
    _activeOwner = owner;
    _activeSelectionText = selectionText;
    _activeSelectionLink = selectionLink;
    if (changedOwner) {
      _revision++;
      notifyListeners();
    }
  }

  void clear(Object owner) {
    if (!identical(_activeOwner, owner)) {
      return;
    }

    _activeOwner = null;
    _activeSelectionText = null;
    _activeSelectionLink = null;
    _revision++;
    notifyListeners();
  }
}

/// קובע האם צריך לבנות מחדש את ה-SelectionArea של אזור בתגובה לשינוי בעלות
/// ב-[SelectionSyncController]. הבנייה מחדש מתבצעת על-ידי קידום ערך revision
/// ששימש כ-`ValueKey` של ה-SelectionArea — ולכן היא משחזרת את כל עץ הצאצאים.
///
/// מטרת הבנייה היא לנקות בחירה ויזואלית של ה-SelectionArea שלנו כשאזור אחר
/// תפס בעלות. אם אין לנו בחירה משלנו — אין מה לנקות, ו-rebuild רק יהרוס
/// את עץ הצאצאים שלא לצורך (במצב 'מפרשים מתחת' זה גורם לטעינה מחדש של
/// המפרשים בכל פעם שמנסים לסמן בהם טקסט; ב'צורת הדף' זה גורם לאיפוס
/// סטייט פנימי של הצאצאים).
bool shouldRebuildSelectionAreaOnExternalChange({
  required Object? activeOwner,
  required Object selfOwner,
  required bool hasOwnSelection,
}) {
  if (activeOwner == null) return false;
  if (identical(activeOwner, selfOwner)) return false;
  return hasOwnSelection;
}
