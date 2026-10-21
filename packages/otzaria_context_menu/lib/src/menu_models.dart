import 'package:flutter/material.dart';

class AppMenuEntry<T> {
  final T value;
  final String label;
  final IconData? icon;

  /// צבע קבוע לאייקון, כמו נקודת צבע ליד שם הצבע.
  final Color? iconColor;
  final bool enabled;
  final bool isDestructive;
  final Widget? trailing;

  /// תוכן מותאם להצגה במקום [label] (החיפוש עדיין מתבצע לפי [label]).
  final Widget? labelWidget;

  /// שמור מקום ריק בעמודת סימן ה-✓ גם כשהשורה אינה נבחרת.
  final bool reserveTrailingGap;

  /// רוחב בפיקסלים המוקצה ל-[trailing] בחישוב רוחב התווית.
  /// 0 = ברירת מחדל (iconSize + 8).
  final double trailingReservedWidth;

  /// תת־כותרת להצגה ברכיבים הזקוקים לתיאור נוסף.
  final String? subtitle;

  const AppMenuEntry({
    required this.value,
    required this.label,
    this.icon,
    this.iconColor,
    this.enabled = true,
    this.isDestructive = false,
    this.trailing,
    this.labelWidget,
    this.reserveTrailingGap = false,
    this.trailingReservedWidth = 0,
    this.subtitle,
  });
}

class AppContextMenuIconAction {
  /// כיתוב קצר (מילה אחת) שמוצג מתחת לאייקון. בהיעדרו מוצג [tooltip].
  final String? label;

  /// טקסט הרחבה שמוצג בריחוף על האייקון. null/ריק → אין tooltip.
  final String? tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;

  /// כשמוגדר, האייקון פותח תת-תפריט (עם חץ למטה) במקום פעולה ישירה.
  final List<AppContextMenuSubAction> Function()? submenuBuilder;

  const AppContextMenuIconAction({
    required this.icon,
    this.label,
    this.tooltip,
    this.onTap,
    this.enabled = true,
    this.submenuBuilder,
  });
}

class AppContextMenuColorAction {
  final String id;
  final Color color;
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool selected;

  const AppContextMenuColorAction({
    required this.id,
    required this.color,
    required this.label,
    this.icon,
    this.onTap,
    this.selected = false,
  });
}

class AppContextMenuSubAction {
  final String label;
  final IconData? icon;
  final bool enabled;
  final VoidCallback? onTap;

  const AppContextMenuSubAction({
    required this.label,
    this.icon,
    this.enabled = true,
    this.onTap,
  });
}

class AppContextMenuEntry {
  final Key? key;
  final String? label;
  final Widget? labelWidget;
  final IconData? icon;
  final bool enabled;
  final bool isDivider;
  final bool isDestructive;
  final bool isSelected;
  final bool isHighlighted;
  final VoidCallback? onTap;

  /// בתוך תת-תפריט: הלחיצה לא סוגרת את התפריט, והתת-תפריט נבנה מחדש
  /// מ-[childrenBuilder] של ההורה כדי ש-[isSelected] יתעדכן מיד.
  final bool keepOpen;
  final Widget? trailing;
  // תת-פריטים לתפריט משנה
  final List<AppContextMenuEntry>? children;
  // בנייה עצלה של תת-פריטים לתפריט משנה.
  final List<AppContextMenuEntry> Function()? childrenBuilder;
  // תת-תפריט תגובתי שמתעדכן בזמן אמת (למשל רשימת כרטיסיות פתוחות)
  final Stream<Object?>? childrenRefreshStream;
  // חלונית תצוגה מקדימה צפה שנפתחת ברפרוף על השורה בתפריט.
  final WidgetBuilder? hoverPreviewBuilder;

  /// כשמוגדר, הערך מרונדר כשורה אופקית של כפתורי אייקון בראש התפריט
  /// (סגנון Windows 11) במקום שורת טקסט רגילה.
  final List<AppContextMenuIconAction>? iconRowActions;
  final List<AppContextMenuColorAction>? colorRowActions;

  const AppContextMenuEntry({
    required this.label,
    this.key,
    this.labelWidget,
    this.icon,
    this.enabled = true,
    this.isDestructive = false,
    this.isSelected = false,
    this.isHighlighted = false,
    this.onTap,
    this.keepOpen = false,
    this.trailing,
    this.children,
    this.childrenBuilder,
    this.childrenRefreshStream,
    this.hoverPreviewBuilder,
  }) : iconRowActions = null,
       colorRowActions = null,
       isDivider = false;

  /// שורת כפתורי אייקון בראש התפריט (סגנון Windows 11).
  const AppContextMenuEntry.iconRow(List<AppContextMenuIconAction> actions)
    : assert(actions.length > 0, 'iconRow דורש לפחות פעולה אחת'),
      iconRowActions = actions,
      colorRowActions = null,
      key = null,
      label = null,
      labelWidget = null,
      icon = null,
      enabled = true,
      isDivider = false,
      isDestructive = false,
      isSelected = false,
      isHighlighted = false,
      onTap = null,
      keepOpen = false,
      trailing = null,
      children = null,
      childrenBuilder = null,
      childrenRefreshStream = null,
      hoverPreviewBuilder = null;

  const AppContextMenuEntry.colorRow(List<AppContextMenuColorAction> actions)
    : assert(actions.length > 0, 'colorRow דורש לפחות צבע אחד'),
      colorRowActions = actions,
      iconRowActions = null,
      key = null,
      label = null,
      labelWidget = null,
      icon = null,
      enabled = true,
      isDivider = false,
      isDestructive = false,
      isSelected = false,
      isHighlighted = false,
      onTap = null,
      keepOpen = false,
      trailing = null,
      children = null,
      childrenBuilder = null,
      childrenRefreshStream = null,
      hoverPreviewBuilder = null;

  const AppContextMenuEntry.divider()
    : key = null,
      label = null,
      labelWidget = null,
      icon = null,
      enabled = false,
      isDivider = true,
      isDestructive = false,
      isSelected = false,
      isHighlighted = false,
      onTap = null,
      keepOpen = false,
      trailing = null,
      children = null,
      childrenBuilder = null,
      childrenRefreshStream = null,
      hoverPreviewBuilder = null,
      iconRowActions = null,
      colorRowActions = null;
}

bool hasEnabledAppContextMenuEntries(List<AppContextMenuEntry> entries) {
  return entries.any((entry) => !entry.isDivider && entry.enabled);
}
