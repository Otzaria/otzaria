import 'package:flutter/material.dart';

/// מודל המייצג הדגשה צבעונית של שורה בטקסט, שנוצרה על ידי פלאגין.
/// תומך גם בהדגשת שורה שלמה (ללא start/end) וגם בהדגשה מדויקת ברמת תו (עם start ו-end).
class PluginHighlight {
  final String bookId;
  final int index;
  final String? color; // CSS color string, e.g. "#FFFF00"
  final String? label;
  final String pluginId;
  final int? start; // תו התחלה בתוך השורה (אופציונלי — להדגשה מדויקת)
  final int? end; // תו סיום בתוך השורה (אופציונלי — להדגשה מדויקת)

  const PluginHighlight({
    required this.bookId,
    required this.index,
    this.color,
    this.label,
    required this.pluginId,
    this.start,
    this.end,
  });

  /// מחזיר true כאשר זו הדגשה מדויקת ברמת תו (גם start וגם end קיימים).
  bool get isInline => start != null && end != null;

  Map<String, dynamic> toJson() {
    return {
      'bookId': bookId,
      'index': index,
      'pluginId': pluginId,
      if (color != null) 'color': color,
      if (label != null) 'label': label,
      if (start != null) 'start': start,
      if (end != null) 'end': end,
    };
  }
}

/// פרסר CSS color string ל-Flutter [Color].
/// תומך ב-#rgb, #rrggbb, #rrggbbaa ובשמות צבעים בסיסיים.
Color? parseCssColor(String? value) {
  if (value == null) return null;
  final v = value.toLowerCase().trim();
  switch (v) {
    case 'red':
      return const Color(0xFFFF0000);
    case 'blue':
      return const Color(0xFF0000FF);
    case 'yellow':
      return const Color(0xFFFFFF00);
    case 'green':
      return const Color(0xFF008000);
    case 'black':
      return const Color(0xFF000000);
    case 'white':
      return const Color(0xFFFFFFFF);
    case 'orange':
      return const Color(0xFFFFA500);
    case 'purple':
      return const Color(0xFF800080);
    case 'pink':
      return const Color(0xFFFFC0CB);
    case 'cyan':
      return const Color(0xFF00FFFF);
  }
  if (v.startsWith('#')) {
    var hex = v.substring(1);
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length == 6) {
      final n = int.tryParse(hex, radix: 16);
      if (n != null) return Color(0xFF000000 | n);
    }
    if (hex.length == 8) {
      // CSS format: RRGGBBAA — Flutter Color expects AARRGGBB
      final reordered = '${hex.substring(6, 8)}${hex.substring(0, 6)}';
      final n = int.tryParse(reordered, radix: 16);
      if (n != null) return Color(n);
    }
  }
  return null;
}
