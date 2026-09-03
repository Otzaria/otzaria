import 'package:flutter/material.dart';

/// האם הפוקוס הראשי יושב בשדה טקסט. צומת הפוקוס של TextField נקשר
/// לווידג'ט Focus פנימי — בדיקת `context.widget` לבדה מחזירה false גם
/// כשמקלידים בשדה, ואז Backspace סווג כ"מחוץ לשדה" ומחק את כל
/// החיפוש (issue #1061) — לכן נבדק גם EditableText כאב-קדמון.
bool isEditableTextFocusTarget() {
  final focusContext = FocusManager.instance.primaryFocus?.context;
  if (focusContext == null) return false;
  final focusedWidget = focusContext.widget;
  if (focusedWidget is EditableText || focusedWidget is TextField) return true;
  return focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
}
