import 'package:flutter/material.dart';

/// פלטת הצבעים לסיווג אירועי לוח השנה.
///
/// האירוע שומר אינדקס לפלטה (ולא ערך גולמי), כדי שהצבע בפועל יוכל
/// להתאים לבהירות התצוגה. אינדקס null או מחוץ לטווח = ללא צבע מיוחד.
class CalendarEventColors {
  CalendarEventColors._();

  static const List<({Color color, String name})> palette = [
    (color: Color(0xFFD50000), name: 'אדום'),
    (color: Color(0xFFE67C00), name: 'כתום'),
    (color: Color(0xFFF6BF26), name: 'צהוב'),
    (color: Color(0xFF33B679), name: 'ירוק'),
    (color: Color(0xFF0B8043), name: 'ירוק כהה'),
    (color: Color(0xFF039BE5), name: 'תכלת'),
    (color: Color(0xFF3F51B5), name: 'כחול'),
    (color: Color(0xFF7986CB), name: 'לבנדר'),
    (color: Color(0xFF8E24AA), name: 'סגול'),
    (color: Color(0xFF795548), name: 'חום'),
    (color: Color(0xFF616161), name: 'אפור'),
  ];

  static int get count => palette.length;

  /// מחזיר את צבע ההצגה עבור [index], מותאם לבהירות התצוגה.
  /// מחזיר null עבור אינדקס null או מחוץ לטווח (ללא צבע מיוחד).
  static Color? colorForIndex(int? index, Brightness brightness) {
    if (index == null || index < 0 || index >= palette.length) return null;
    final base = palette[index].color;
    if (brightness == Brightness.dark) {
      final hsl = HSLColor.fromColor(base);
      return hsl
          .withLightness((hsl.lightness + 0.15).clamp(0.0, 1.0))
          .toColor();
    }
    return base;
  }

  /// מחזיר את השם העברי של הצבע עבור [index], או null.
  static String? nameOf(int? index) {
    if (index == null || index < 0 || index >= palette.length) return null;
    return palette[index].name;
  }

  /// תווית תצוגה כשאין צבע מיוחד (index הוא null או מחוץ לטווח).
  static const String noColorLabel = 'ללא צבע';

  /// תווית תצוגה לצבע — שם הגוון, או [noColorLabel] עבור null/מחוץ לטווח.
  static String labelOf(int? index) => nameOf(index) ?? noColorLabel;
}
