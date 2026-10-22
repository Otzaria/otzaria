import 'package:flutter/material.dart';

/// צבעי ברירת המחדל של המרקר וגווני עורך הצבעים. סימון שומר מזהה צבע, ולכן
/// שינוי כאן אינו משנה פלטה שהמשתמש כבר שמר.
class MarkerColors {
  MarkerColors._();

  static const List<({String id, String label, Color color, bool enabled})>
  defaults = [
    (id: 'yellow', label: 'צהוב', color: Color(0xFFF1E784), enabled: true),
    (id: 'green', label: 'ירוק', color: Color(0xFF8BCF8D), enabled: true),
    (id: 'blue', label: 'כחול', color: Color(0xFF88BDE9), enabled: true),
    (id: 'red', label: 'אדום', color: Color(0xFFF37E75), enabled: true),
    (id: 'orange', label: 'כתום', color: Color(0xFFF0BD72), enabled: true),
    (id: 'purple', label: 'סגול', color: Color(0xFFE297F0), enabled: false),
  ];

  static const List<Color> presets = [
    Color(0xFFB7DDBB),
    Color(0xFFFFD08A),
    Color(0xFFFFE27A),
    Color(0xFFFFF3A6),
    Color(0xFFB8D8F0),
    Color(0xFFD8B4E2),
    Color(0xFFF3B6C8),
    Color(0xFFC9C2F5),
  ];

  static const double defaultOpacity = 0.65;

  /// מילוי בהיר מתחת לטקסט בהיר במצב כהה מוריד ניגודיות, ולכן הוא מעומעם.
  static double fillOpacity(double opacity, Brightness brightness) =>
      brightness == Brightness.dark ? opacity * darkFillFactor : opacity;

  /// העמעום של [fillOpacity] במצב כהה.
  static const double darkFillFactor = 0.6;
}
