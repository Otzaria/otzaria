import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/tools/tool_order.dart';
import 'package:otzaria_icons/otzaria_icons.dart';

/// מטא-דאטה לתצוגה של כלי מובנה.
///
/// כולל מזהה, תווית, סדר ואייקונים לתצוגה (רגיל + filled לנבחר).
class BuiltInToolMeta {
  final String toolId;
  final String label;
  final int order;

  /// אייקון Fluent רגיל (לכלי שמשתמש באייקון מהחבילה).
  final IconData? icon;

  /// אייקון Fluent filled — מוצג כשהכלי נבחר בסרגלי הניווט.
  final IconData? iconFilled;

  /// נתיב נכס תמונה (לכלים שמשתמשים בתמונה במקום באייקון, כמו "שמור וזכור").
  final String? imageIcon;

  const BuiltInToolMeta({
    required this.toolId,
    required this.label,
    required this.order,
    this.icon,
    this.iconFilled,
    this.imageIcon,
  });
}

/// קטלוג הכלים המובנים — **מקור סמכותי יחיד** למזהה, תווית, סדר ואייקונים.
///
/// מסך ההגדרות וסרגל הניווט צורכים אותה ישירות. סדר התצוגה בכלים נקבע לפי
/// [BuiltInToolMeta.order].
const List<BuiltInToolMeta> kBuiltInToolsCatalog = [
  BuiltInToolMeta(
    toolId: 'builtin.calendar',
    label: 'לוח שנה',
    order: 10,
    icon: OtzariaIcons.calendar_24_regular,
    iconFilled: OtzariaIcons.calendar_24_filled,
  ),
  BuiltInToolMeta(
    toolId: 'builtin.shamor_zachor',
    label: 'שמור וזכור',
    order: 20,
    imageIcon: 'assets/icon/שמור וזכור שחור ריק.png',
  ),
  BuiltInToolMeta(
    toolId: 'builtin.measurements',
    label: 'מדות ושיעורים',
    order: 30,
    icon: FluentIcons.ruler_24_regular,
    iconFilled: FluentIcons.ruler_24_filled,
  ),
  BuiltInToolMeta(
    toolId: 'builtin.notes',
    label: 'הערות אישיות',
    // order 25 ממקם את "הערות אישיות" צמוד ל"שמור וזכור" (20) — שניהם בקבוצת
    // "תורה שלמדתי". אחרת notes חוצה את קבוצת "דקדוקי סופרים" (measurements=30
    // ... gematria=50) ומפצל את הכותרת שלה לשתיים.
    order: 25,
    icon: FluentIcons.note_24_regular,
    iconFilled: FluentIcons.note_24_filled,
  ),
  BuiltInToolMeta(
    toolId: 'builtin.tikkun_korim',
    label: 'תיקון קוראים',
    order: 40,
    icon: OtzariaIcons.torah_scroll_24_regular,
    iconFilled: OtzariaIcons.torah_scroll_24_regular,
  ),
  BuiltInToolMeta(
    toolId: 'builtin.gematria',
    label: 'גימטריה',
    order: 50,
    icon: FluentIcons.calculator_24_regular,
    iconFilled: FluentIcons.calculator_24_filled,
  ),
  BuiltInToolMeta(
    toolId: 'builtin.aramaic_dictionary',
    label: 'מילון ארמי-עברי',
    order: 60,
    icon: OtzariaIcons.beit_behind_alef_24_regular,
    iconFilled: OtzariaIcons.beit_behind_alef_24_regular,
  ),
  BuiltInToolMeta(
    toolId: 'builtin.acronyms_dictionary',
    label: 'ראשי תיבות',
    order: 70,
    icon: FluentIcons.text_quote_24_regular,
    iconFilled: FluentIcons.text_quote_24_filled,
  ),
  BuiltInToolMeta(
    toolId: 'builtin.biographies',
    label: 'ביוגרפיות',
    order: 80,
    icon: FluentIcons.people_24_regular,
    iconFilled: FluentIcons.people_24_filled,
  ),
];

/// הקטלוג לפי סדר התצוגה שנקבע ב-[BuiltInToolMeta.order] — הבסיס לכל סידור,
/// גם כשלמשתמש אין סדר משלו.
///
/// המיון יציב (insertionSort): שני כלים עם אותו order שומרים על סדר ההצהרה,
/// אחרת הסדר שהמשתמש שמר היה זז בין הרצות.
List<BuiltInToolMeta> get _catalogInDisplayOrder {
  final ordered = [...kBuiltInToolsCatalog];
  insertionSort(ordered, compare: (a, b) => a.order.compareTo(b.order));
  return ordered;
}

/// הכלים המובנים לפי הסדר שהמשתמש קבע ב-[customOrder] (מזהים, לפי הסדר).
///
/// מזהה שאינו בקטלוג מתעלמים ממנו; כלי שאינו ב-[customOrder] (כלי חדש שנוסף
/// בגרסה מאוחרת) נספח בסוף לפי סדר הקטלוג.
List<BuiltInToolMeta> orderedBuiltInTools(List<String> customOrder) {
  final base = _catalogInDisplayOrder;
  if (customOrder.isEmpty) return base;
  final byId = {for (final meta in base) meta.toolId: meta};
  final ordered = <BuiltInToolMeta>[];
  final seen = <String>{};
  for (final toolId in customOrder) {
    final meta = byId[toolId];
    if (meta == null || !seen.add(toolId)) continue;
    ordered.add(meta);
  }
  for (final meta in base) {
    if (!seen.contains(meta.toolId)) ordered.add(meta);
  }
  return ordered;
}

/// סדר מזהי הכלים המובנים לאחר הפלת [sourceId] לפני [targetId] או אחריו.
///
/// [currentOrder] יכול להיות חלקי או ריק — הבסיס תמיד מנורמל לרשימה מלאה,
/// כדי שהסדר שיישמר יכיל את כל הכלים ולא ייווצרו מזהים חסרים.
List<String> reorderedBuiltInToolIds(
  List<String> currentOrder,
  String sourceId,
  String targetId, {
  required bool placeAfter,
}) {
  return reorderIdsAroundTarget(
    orderedBuiltInTools(currentOrder).map((meta) => meta.toolId).toList(),
    sourceId,
    targetId,
    placeAfter: placeAfter,
  );
}
