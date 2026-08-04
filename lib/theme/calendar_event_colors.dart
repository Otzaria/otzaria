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
    (color: Color(0xFFE67C73), name: 'ורוד'),
    (color: Color(0xFFF4511E), name: 'כתום אדמדם'),
  ];

  static const Map<String, int> _googleColorIdToIndex = {
    '1': 7,
    '2': 3,
    '3': 8,
    '4': 11,
    '5': 2,
    '6': 12,
    '7': 5,
    '8': 10,
    '9': 6,
    '10': 4,
    '11': 0,
  };

  static const Map<int, String> _indexToGoogleColorId = {
    0: '11',
    1: '6',
    2: '5',
    3: '2',
    4: '10',
    5: '7',
    6: '9',
    7: '1',
    8: '3',
    9: '8',
    10: '8',
    11: '4',
    12: '6',
  };

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

  /// ממיר מזהה צבע של אירוע Google לאינדקס הצבע המקביל בלוח.
  static int? indexForGoogleColorId(String? colorId) =>
      _googleColorIdToIndex[colorId];

  /// מתאים צבע ששבץ Google ביומן לצבע הקרוב ביותר בפלטה המקומית.
  static int? indexForGoogleColorHex(String? color) {
    final value = color?.trim();
    if (value == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
      return null;
    }
    final source = int.parse(value.substring(1), radix: 16);
    final red = (source >> 16) & 0xFF;
    final green = (source >> 8) & 0xFF;
    final blue = source & 0xFF;
    var closest = 0;
    var smallestDistance = double.infinity;
    for (var index = 0; index < palette.length; index++) {
      final candidate = palette[index].color;
      final candidateRed = (candidate.r * 255).round();
      final candidateGreen = (candidate.g * 255).round();
      final candidateBlue = (candidate.b * 255).round();
      final distance =
          (candidateRed - red) * (candidateRed - red) +
          (candidateGreen - green) * (candidateGreen - green) +
          (candidateBlue - blue) * (candidateBlue - blue);
      if (distance < smallestDistance) {
        smallestDistance = distance.toDouble();
        closest = index;
      }
    }
    return closest;
  }

  /// ממיר אינדקס צבע בלוח למזהה צבע של אירוע Google.
  static String? googleColorIdForIndex(int? index) {
    return index == null ? null : _indexToGoogleColorId[index];
  }
}
