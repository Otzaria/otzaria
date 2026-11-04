import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';

/// אפשרות יחידה ב-[AppSegmentedControl]
///
/// [icon] — אייקון סטטי, לא מתהפך ב-RTL.
/// [rtlIcon] — אייקון כיווני, מוצג דרך [RtlIcon] ומתהפך ב-RTL לפי הרישום
/// ב-`lib/widgets/misc/rtl_icon.dart`.
class SegmentOption<T> {
  final T value;
  final String label;
  final IconData? icon;
  final IconData? rtlIcon;

  /// הסבר שמוצג בריחוף; ברירת המחדל היא התווית המלאה.
  final String? tooltip;

  /// התווית במקטע צר ([AppSegmentedControl.narrowBelowSegmentWidth]), כשהמלאה
  /// לא נכנסת. המלאה נשארת ב-tooltip.
  final String? shortLabel;

  /// מפתח לתווית — נקודת האחיזה של בדיקות, כי מקטע אינו מקבל מפתח.
  final Key? labelKey;

  /// תת-כותרת המשויכת לאפשרות זו — נלקחת אוטומטית ע"י
  /// [SettingsSegmentedTile] כשלא סופק subtitle מפורש.
  final String? subtitle;

  const SegmentOption({
    required this.value,
    required this.label,
    this.icon,
    this.rtlIcon,
    this.tooltip,
    this.shortLabel,
    this.labelKey,
    this.subtitle,
  }) : assert(
         icon == null || rtlIcon == null,
         'העבר icon או rtlIcon — לא שניהם יחד',
       );
}

/// פקד סגמנטד גנרי לשימוש בסרגלי כלים ובהגדרות.
///
/// [height] — גובה קבוע בפיקסלים (ברירת מחדל: null = compact density לסרגלי כלים).
/// [expandToFillWidth] — מלא את כל הרוחב הזמין.
///
/// דוגמה:
/// ```dart
/// AppSegmentedControl<String>(
///   options: const [
///     SegmentOption(value: 'all', label: 'הכל', icon: FluentIcons.library_24_regular),
///     SegmentOption(value: 'done', label: 'הושלם', icon: FluentIcons.checkmark_circle_24_regular),
///   ],
///   currentValue: _filter,
///   onChanged: (v) => setState(() => _filter = v),
/// )
/// ```
class AppSegmentedControl<T> extends StatelessWidget {
  final List<SegmentOption<T>> options;
  final T currentValue;
  final ValueChanged<T> onChanged;
  final bool expandToFillWidth;
  final bool showSelectedIcon;
  final double? height;

  /// Lines a label may wrap to before it is cut with an ellipsis. Above 1,
  /// [height] is a minimum and the control grows when a label wraps.
  final int maxLabelLines;

  /// לחיצה על המקטע הנבחר קוראת ל-[onChanged] עם הערך שלו. לבורר שמסמן ערך
  /// שנקבע אוטומטית, כדי שאפשר יהיה לקבוע אותו בלחיצה אחת.
  final bool reselectable;

  const AppSegmentedControl({
    super.key,
    required this.options,
    required this.currentValue,
    required this.onChanged,
    this.expandToFillWidth = false,
    this.showSelectedIcon = false,
    this.height,
    this.maxLabelLines = 1,
    this.reselectable = false,
  });

  /// מתחת לרוחב הזה למקטע (רוחב הבורר חלקי מספר המקטעים) המקטע צר: האייקונים
  /// יורדים, ו-[SegmentOption.shortLabel] במקום התווית, כדי שהתווית תיכנס.
  /// בטלפון (320–360) נשארו מ"מדויק" שתי אותיות, ו"חיפוש חכם" נחתך ל"חיפוש
  /// ..." (q12 Q8).
  static const double narrowBelowSegmentWidth = 96;

  List<ButtonSegment<T>> _segments({required bool narrow}) {
    final hasIcons =
        !narrow && options.any((o) => o.icon != null || o.rtlIcon != null);
    return options
        .map(
          (o) => ButtonSegment<T>(
            value: o.value,
            // בלי FittedBox: בתוך לחצן הוא פורס את הטקסט ברוחב מילה אחת,
            // ואז maxLines חותך אותו למילה הראשונה.
            label: Text(
              narrow ? o.shortLabel ?? o.label : o.label,
              key: o.labelKey,
              maxLines: maxLabelLines,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
            icon: hasIcons ? _buildOptionIcon(o) : null,
            // תווית ארוכה נחתכת ב-ellipsis; הטולטיפ מציג אותה במלואה.
            tooltip: o.tooltip ?? o.label,
          ),
        )
        .toList();
  }

  Widget _buildOptionIcon(SegmentOption<T> o) {
    if (o.rtlIcon != null) return RtlIcon(o.rtlIcon!, size: AppTokens.iconSM);
    if (o.icon != null) return Icon(o.icon, size: AppTokens.iconSM);
    return const SizedBox(width: 18);
  }

  static ButtonStyle _buttonStyle(ColorScheme cs) => ButtonStyle(
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return cs.onSecondaryContainer;
      }
      return cs.onSurfaceVariant;
    }),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) {
        return cs.secondaryContainer;
      }
      return cs.surface;
    }),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: AppTokens.borderRadiusAll,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isFixed = height != null;

    return LayoutBuilder(
      builder: (context, constraints) => _build(
        cs,
        isFixed,
        // ברוחב לא חסום (בתוך Row) הבורר ברוחבו הטבעי, ואינו צר.
        narrow:
            constraints.hasBoundedWidth &&
            constraints.maxWidth / options.length < narrowBelowSegmentWidth,
      ),
    );
  }

  Widget _build(ColorScheme cs, bool isFixed, {required bool narrow}) {
    return SegmentedButton<T>(
      segments: _segments(narrow: narrow),
      selected: {currentValue},
      expandedInsets: expandToFillWidth ? EdgeInsets.zero : null,
      // SegmentedButton מדווח על לחיצה במקטע הנבחר רק כשמותרת בחירה ריקה, ואז
      // כבחירה ריקה; הבורר נשאר מסומן, והלחיצה היא הערך הנוכחי.
      emptySelectionAllowed: reselectable,
      onSelectionChanged: (Set<T> selection) {
        if (selection.isNotEmpty) {
          onChanged(selection.first);
        } else if (reselectable) {
          onChanged(currentValue);
        }
      },
      showSelectedIcon: showSelectedIcon,
      selectedIcon: const Icon(
        FluentIcons.checkmark_24_regular,
        size: AppTokens.iconSM,
      ),
      style: isFixed
          ? _buttonStyle(cs).copyWith(
              minimumSize: WidgetStateProperty.all(Size(0, height!)),
              maximumSize: WidgetStateProperty.all(
                Size(
                  double.infinity,
                  maxLabelLines > 1 ? double.infinity : height!,
                ),
              ),
            )
          : _buttonStyle(cs).copyWith(
              visualDensity: VisualDensity.compact,
            ),
    );
  }
}
