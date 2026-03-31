// ignore_for_file: constant_identifier_names

import 'measurement_data.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  measurement_converter_logic.dart
//  lib/tools/measurement/measurement_converter_logic.dart
//
//  לוגיקת המרה טהורה — ללא Flutter / ווידג'טים.
//  כל הפונקציות static, ניתן לקרוא ישירות ממסך ממיר המידות.
// ═════════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────────
//  קבועי יחידות מודרניות
// ─────────────────────────────────────────────────────────────────────────────
const List<String> modernLengthUnits = ['מ"מ', 'ס"מ', 'מטר', 'ק"מ'];
const List<String> modernAreaUnits = ['ס"מ רבוע', 'מ"ר', 'ק"מ רבוע', 'דונם'];
const List<String> modernVolumeUnits = [
  'מ"מ מעוקב',
  'ס"מ מעוקב',
  'סמ"ק',
  'מ"ל',
  'ליטר',
  'מטר מעוקב',
  'קוב',
];
const List<String> modernWeightUnits = ['מ"ג', 'גרם', 'ק"ג', 'טון'];
const List<String> modernTimeUnits = ['שניות', 'חלקים', 'דקות', 'שעות', 'ימים'];

/// יחידות זמן עתיקות בסיסיות (שורה ראשונה)
const List<String> basicAncientTimeUnits = [
  'הילוך אמה',
  'הילוך מיל',
  'הילוך פרסה',
];

/// יחידות זמן עתיקות מורכבות (שורה שנייה)
const List<String> complexAncientTimeUnits = [
  'הילוך ארבע אמות',
  'הילוך מאה אמה',
  'הילוך שלושה רבעי מיל',
  'הילוך ארבעה מילים',
  'הילוך עשרה פרסאות',
];

// ─────────────────────────────────────────────────────────────────────────────
//  MeasurementConverterLogic
// ─────────────────────────────────────────────────────────────────────────────
abstract class MeasurementConverterLogic {
  MeasurementConverterLogic._();

  // ── נירמול שם יחידה ────────────────────────────────────────────────────────
  static String normalizeUnitName(String unit) {
    const normalizationMap = {
      'אצבעות': 'אצבע',
      'טפחים': 'טפח',
      'זרתות': 'זרת',
      'אמות': 'אמה',
      'קנים': 'קנה',
      'מילים': 'מיל',
      'פרסאות': 'פרסה',
      'בית רובע': 'בית רובע',
      'בית קב': 'בית קב',
      'בית סאה': 'בית סאה',
      'בית סאתיים': 'בית סאתיים',
      'בית לתך': 'בית לתך',
      'בית כור': 'בית כור',
      'רביעיות': 'רביעית',
      'לוגים': 'לוג',
      'קבים': 'קב',
      'עשרונות': 'עשרון',
      'הינים': 'הין',
      'סאים': 'סאה',
      'איפות': 'איפה',
      'לתכים': 'לתך',
      'כורים': 'כור',
      'דינרים': 'דינר',
      'שקלים': 'שקל',
      'סלעים': 'סלע',
      'טרטימרים': 'טרטימר',
      'מנים': 'מנה',
      'ככרות': 'כיכר',
      'קנטרים': 'קנטר',
    };
    return normalizationMap[unit] ?? unit;
  }

  // ── גורם המרה ל-base unit ──────────────────────────────────────────────────
  /// מחזיר את ערך היחידה ב-base unit (ס"מ / מ"ר / ס"מ³ / גרם / שניות).
  /// [opinion] — דרוש רק בהמרה בין עתיק ומודרני; ריק כשלא נדרש.
  static double? getFactorToBaseUnit(
    String category,
    String unit,
    String opinion,
  ) {
    final n = normalizeUnitName(unit);

    switch (category) {
      // ── אורך — base: ס"מ ─────────────────────────────────────────────────
      case 'אורך':
        if (modernLengthUnits.contains(unit)) {
          if (unit == 'מ"מ') return 0.1;
          if (unit == 'ס"מ') return 1.0;
          if (unit == 'מטר') return 100.0;
          if (unit == 'ק"מ') return 100000.0;
        } else {
          if (opinion.isEmpty) return null;
          final value = modernLengthFactors[opinion]?[n];
          if (value == null) return null;
          if (['קנה', 'מיל'].contains(n)) return value * 100; // m → cm
          if (['פרסה'].contains(n)) return value * 100000; // km → cm
          return value;
        }
        break;

      // ── שטח — base: מ"ר ─────────────────────────────────────────────────
      case 'שטח':
        if (modernAreaUnits.contains(unit)) {
          if (unit == 'ס"מ רבוע') return 0.0001;
          if (unit == 'מ"ר') return 1.0;
          if (unit == 'ק"מ רבוע') return 1000000.0;
          if (unit == 'דונם') return 1000.0;
        } else {
          if (opinion.isEmpty) return null;
          final value = modernAreaFactors[opinion]?[n];
          if (value == null) return null;
          if (['בית סאתיים', 'בית לתך', 'בית כור'].contains(n) ||
              (opinion == 'חתם סופר' && n == 'בית סאה')) {
            return value * 1000; // dunam → m²
          }
          return value;
        }
        break;

      // ── נפח — base: ס"מ³ ─────────────────────────────────────────────────
      case 'נפח':
        if (modernVolumeUnits.contains(unit)) {
          if (unit == 'מ"מ מעוקב') return 0.001;
          if (unit == 'ס"מ מעוקב') return 1.0;
          if (unit == 'סמ"ק') return 1.0;
          if (unit == 'מ"ל') return 1.0;
          if (unit == 'ליטר') return 1000.0;
          if (unit == 'מטר מעוקב') return 1000000.0;
          if (unit == 'קוב') return 1000000.0;
        } else {
          if (opinion.isEmpty) return null;
          final value = modernVolumeFactors[opinion]?[n];
          if (value == null) return null;
          if (['קב', 'עשרון', 'הין', 'סאה', 'איפה', 'לתך', 'כור'].contains(n)) {
            return value * 1000; // L → cm³
          }
          return value;
        }
        break;

      // ── משקל — base: גרם ─────────────────────────────────────────────────
      case 'משקל':
        if (modernWeightUnits.contains(unit)) {
          if (unit == 'מ"ג') return 0.001;
          if (unit == 'גרם') return 1.0;
          if (unit == 'ק"ג') return 1000.0;
          if (unit == 'טון') return 1000000.0;
        } else {
          if (opinion.isEmpty) return null;
          final value = modernWeightFactors[opinion]?[normalizeUnitName(unit)];
          if (value == null) return null;
          if (['כיכר', 'קנטר'].contains(n)) return value * 1000; // kg → g
          return value;
        }
        break;

      // ── זמן — base: שניות ─────────────────────────────────────────────────
      case 'זמן':
        if (modernTimeUnits.contains(unit)) {
          if (unit == 'שניות') return 1.0;
          if (unit == 'חלקים') return 10.0 / 3.0; // חלק = 3⅓ שניות
          if (unit == 'דקות') return 60.0;
          if (unit == 'שעות') return 3600.0;
          if (unit == 'ימים') return 86400.0;
        } else {
          if (opinion.isEmpty) return null;
          final value = modernTimeFactors[opinion]?[unit];
          if (value == null) return null;
          return value;
        }
        break;
    }
    return null;
  }

  // ── המרה ראשית ──────────────────────────────────────────────────────────────
  /// מחשב את התוצאה ומחזיר אותה כ-String מפורמט, או null אם הנתונים חסרים.
  /// מחזיר `'נא לבחור שיטה'` כשחסרה שיטה.
  static String? convertMeasurement({
    required String category,
    required String fromUnit,
    required String toUnit,
    required double input,
    required String? opinion,
    required List<String> modernUnitsForCategory,
  }) {
    final fromIsAncient = !modernUnitsForCategory.contains(fromUnit);
    final toIsAncient = !modernUnitsForCategory.contains(toUnit);
    double result;

    // Case 1: עתיק → עתיק (לא דורש שיטה)
    if (fromIsAncient && toIsAncient) {
      double? factor;
      switch (category) {
        case 'אורך':
          factor = lengthConversionFactors[fromUnit]?[toUnit];
          break;
        case 'שטח':
          factor = areaConversionFactors[fromUnit]?[toUnit];
          break;
        case 'נפח':
          factor = volumeConversionFactors[fromUnit]?[toUnit];
          break;
        case 'משקל':
          factor = weightConversionFactors[fromUnit]?[toUnit];
          break;
        case 'זמן':
          factor = timeConversionFactors[fromUnit]?[toUnit];
          break;
      }
      if (factor == null) return null;
      result = input * factor;

      // Case 2: מודרני → מודרני (לא דורש שיטה)
    } else if (!fromIsAncient && !toIsAncient) {
      final factorFrom = getFactorToBaseUnit(category, fromUnit, '');
      final factorTo = getFactorToBaseUnit(category, toUnit, '');
      if (factorFrom == null || factorTo == null) return null;
      result = input * factorFrom / factorTo;

      // Case 3: עתיק ↔ מודרני (דורש שיטה)
    } else {
      if (opinion == null || opinion.isEmpty) return 'נא לבחור שיטה';
      final factorFrom = getFactorToBaseUnit(category, fromUnit, opinion);
      if (factorFrom == null) return null;
      final factorTo = getFactorToBaseUnit(category, toUnit, opinion);
      if (factorTo == null) return null;
      result = input * factorFrom / factorTo;
    }

    if (result.isNaN || result.isInfinite) return null;
    // הצגה עד 4 ספרות, ללא אפסים מיותרים
    return result
        .toStringAsFixed(4)
        .replaceAll(RegExp(r'([.]*0+)(?!.*\d)'), '');
  }

  // ── האם להציג בורר שיטה? ───────────────────────────────────────────────────
  static bool shouldShowOpinionSelector({
    required String category,
    required String? fromUnit,
    required String? toUnit,
    required Map<String, List<String>> modernUnitsMap,
    required Map<String, List<String>> opinionsMap,
  }) {
    if (!opinionsMap.containsKey(category) || opinionsMap[category]!.isEmpty) {
      return false;
    }
    final moderns = modernUnitsMap[category] ?? [];
    final isFromModern = moderns.contains(fromUnit);
    final isToModern = moderns.contains(toUnit);
    return (isFromModern || isToModern) && !(isFromModern && isToModern);
  }

  // ── יחידות מודרניות לפי קטגוריה ────────────────────────────────────────────
  static List<String> getModernUnitsForCategory(String category) {
    switch (category) {
      case 'אורך':
        return modernLengthUnits;
      case 'שטח':
        return modernAreaUnits;
      case 'נפח':
        return modernVolumeUnits;
      case 'משקל':
        return modernWeightUnits;
      case 'זמן':
        return modernTimeUnits;
      default:
        return [];
    }
  }
}
