import 'package:flutter/foundation.dart';
import 'package:otzaria/book_common/selection/commentary_selection.dart';
import 'package:otzaria/models/links.dart';

/// מסנכרן בחירת טקסט בין כמה אזורי SelectionArea באותו מסך: רק אזור אחד
/// מחזיק בחירה בכל רגע, והשאר מנקים את שלהם כשהבעלות עוברת.
class SelectionSyncController extends ChangeNotifier {
  Object? _activeOwner;
  String? _activeSelectionText;
  Link? _activeSelectionLink;
  Future<CommentaryCopyGuard?> Function()? _activeCopyGuard;

  Object? get activeOwner => _activeOwner;
  String? get activeSelectionText => _activeSelectionText;
  Link? get activeSelectionLink => _activeSelectionLink;

  /// הגבלת ההעתקה של בחירה שאין לה [activeSelectionLink] יחיד.
  Future<CommentaryCopyGuard?> Function()? get activeCopyGuard =>
      _activeCopyGuard;

  void activate(
    Object owner, {
    String? selectionText,
    Link? selectionLink,
    Future<CommentaryCopyGuard?> Function()? copyGuard,
  }) {
    final changedOwner = !identical(_activeOwner, owner);
    _activeOwner = owner;
    _activeSelectionText = selectionText;
    _activeSelectionLink = selectionLink;
    _activeCopyGuard = copyGuard;
    if (!changedOwner) {
      return;
    }

    notifyListeners();
  }

  void clear(Object owner) {
    if (!identical(_activeOwner, owner)) {
      return;
    }

    _activeOwner = null;
    _activeSelectionText = null;
    _activeSelectionLink = null;
    _activeCopyGuard = null;
    notifyListeners();
  }
}

/// קובע האם אזור צריך לנקות את הבחירה שלו כשאזור אחר תפס בעלות.
///
/// הניקוי חייב להתבצע דרך `SelectableRegionState.clearSelection()`. ניקוי
/// על-ידי החלפת מפתח ה-SelectionArea הורס את עץ הצאצאים, ובמצב 'מפרשים מתחת'
/// (שבו רשימת המפרשים מקוננת בתוך אזור הטקסט הראשי) הוא מוחק את הבחירה
/// שהמשתמש זה עתה סימן במפרש — והעתקה יוצאת ריקה (issue #674).
bool shouldClearSelectionOnExternalChange({
  required Object? activeOwner,
  required Object selfOwner,
  required bool hasOwnSelection,
}) {
  if (activeOwner == null) return false;
  if (identical(activeOwner, selfOwner)) return false;
  return hasOwnSelection;
}
