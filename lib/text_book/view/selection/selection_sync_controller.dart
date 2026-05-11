import 'package:flutter/foundation.dart';

/// מסנכרן בחירת טקסט בין כמה אזורי SelectionArea באותו מסך.
///
/// ל-SelectionArea של Flutter אין API ישיר ל"נקה בחירה באזור אחר",
/// לכן כל אזור מאזין לגרסה (`revision`) ומבצע rebuild מקומי כשהבחירה
/// עברה לאזור אחר.
class SelectionSyncController extends ChangeNotifier {
  int _revision = 0;
  Object? _activeOwner;

  int get revision => _revision;
  Object? get activeOwner => _activeOwner;

  void activate(Object owner) {
    if (identical(_activeOwner, owner)) {
      return;
    }

    _activeOwner = owner;
    _revision++;
    notifyListeners();
  }

  void clear(Object owner) {
    if (!identical(_activeOwner, owner)) {
      return;
    }

    _activeOwner = null;
    _revision++;
    notifyListeners();
  }
}
