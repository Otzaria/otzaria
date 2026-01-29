import 'package:flutter/material.dart';

/// מנהל מצב בחירת טקסט זמני (Selection-only mode)
/// מאפשר בחירת טקסט לצורך העתקה בלבד, ללא עריכה
class TextSelectionManager extends ChangeNotifier {
  /// נקודת העיגון לבחירה (anchor point)
  int? _anchorIndex;

  /// האם נמצאים במצב בחירה זמני
  bool _isInSelectionMode = false;

  /// האם הבחירה הנוכחית נוצרה על ידי double-click
  bool _isDoubleClickSelection = false;

  int? get anchorIndex => _anchorIndex;
  bool get isInSelectionMode => _isInSelectionMode;
  bool get isDoubleClickSelection => _isDoubleClickSelection;

  /// קביעת anchor point (נקודת התחלה לבחירה)
  void setAnchor(int index) {
    _anchorIndex = index;
    _isInSelectionMode = true;
    _isDoubleClickSelection = false;
    notifyListeners();
  }

  /// כניסה למצב בחירה עם double-click
  void enterDoubleClickMode(int index) {
    _anchorIndex = index;
    _isInSelectionMode = true;
    _isDoubleClickSelection = true;
    notifyListeners();
  }

  /// יציאה ממצב בחירה
  void exitSelectionMode() {
    _anchorIndex = null;
    _isInSelectionMode = false;
    _isDoubleClickSelection = false;
    notifyListeners();
  }

  /// בדיקה אם יש anchor פעיל
  bool hasAnchor() => _anchorIndex != null;

  /// איפוס מלא
  void reset() {
    _anchorIndex = null;
    _isInSelectionMode = false;
    _isDoubleClickSelection = false;
    notifyListeners();
  }
}

/// Intent לבחירת פסקה (double-click)
class SelectParagraphIntent extends Intent {
  const SelectParagraphIntent();
}

/// Intent לבחירת טווח עם Shift+Click
class SelectRangeIntent extends Intent {
  const SelectRangeIntent();
}

/// Intent לניקוי בחירה
class ClearSelectionIntent extends Intent {
  const ClearSelectionIntent();
}
