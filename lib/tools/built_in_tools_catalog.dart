import 'package:flutter/widgets.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// מטא-דאטה לתצוגה של כלי מובנה.
///
/// אינו כולל את [pageBuilder] של ה-`BuiltInToolDescriptor` המלא — רק מזהה,
/// תווית, סדר, ואייקונים לתצוגה (רגיל + filled לנבחר).
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
/// `ToolsScreen` בונה את ה-`BuiltInToolDescriptor` המלאים מרשימה זו ומוסיף רק
/// את ה-`pageBuilder` (שתלוי במצב המסך). מסך ההגדרות וסרגל הניווט צורכים אותה
/// ישירות. סדר התצוגה בכלים נקבע לפי [BuiltInToolMeta.order].
const List<BuiltInToolMeta> kBuiltInToolsCatalog = [
  BuiltInToolMeta(
    toolId: 'builtin.calendar',
    label: 'לוח שנה',
    order: 10,
    icon: FluentIcons.calendar_24_regular,
    iconFilled: FluentIcons.calendar_24_filled,
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
    icon: FluentIcons.translate_24_regular,
    iconFilled: FluentIcons.translate_24_filled,
  ),
  BuiltInToolMeta(
    toolId: 'builtin.acronyms_dictionary',
    label: 'ראשי תיבות',
    order: 70,
    icon: FluentIcons.text_quote_24_regular,
    iconFilled: FluentIcons.text_quote_24_filled,
  ),
];
