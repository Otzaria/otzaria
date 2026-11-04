import 'dart:ui' show clampDouble, lerpDouble;

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

/// הפריסה שנמדדה ל-[AppSegmentedControl.twoRowsWhenClipped].
enum _Fit { full, narrow, clipped }

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

  /// הבורר בוחר במדידה את הפריסה הראשונה שבה כל התוויות נכנסות: שורה עם
  /// אייקונים ותוויות מלאות; שורה בלי אייקונים בתוויות הקצרות
  /// ([SegmentOption.shortLabel]); ורק כשגם זו נחתכת — שתי שורות (בארבעה:
  /// 2×2), ובהן אותו סדר בחירה ברוחב הכפול של המקטע. המדידה ב-[TextPainter]
  /// בסגנון התווית ובהגדלת הטקסט, מול רוחב המקטע פחות הריווח שלו
  /// ([segmentPadding]) והאייקון. בלי ההגדרה המקטעים צרים לפי
  /// [narrowBelowSegmentWidth] בלבד, ותווית ארוכה נחתכת ב-ellipsis.
  final bool twoRowsWhenClipped;

  const AppSegmentedControl({
    super.key,
    required this.options,
    required this.currentValue,
    required this.onChanged,
    this.expandToFillWidth = false,
    this.showSelectedIcon = false,
    this.height,
    this.maxLabelLines = 1,
    this.twoRowsWhenClipped = false,
  });

  /// בלי [twoRowsWhenClipped]: מתחת לרוחב הזה למקטע (רוחב הבורר חלקי מספר
  /// המקטעים) המקטע צר: האייקונים יורדים, ו-[SegmentOption.shortLabel] במקום
  /// התווית, כדי שהתווית תיכנס. בטלפון (320–360) נשארו מ"מדויק" שתי אותיות,
  /// ו"חיפוש חכם" נחתך ל"חיפוש ..." (q12 Q8).
  static const double narrowBelowSegmentWidth = 96;

  /// הריווח האופקי של מקטע עם תווית בלבד — גם בציור ([_buttonStyle]) וגם
  /// במדידה של [twoRowsWhenClipped]. אותם ערכים כמו ברירת המחדל של
  /// TextButton, ובהגדלת טקסט הם קטנים כמו שם (×2: ‏8, ‏×3: ‏4).
  static EdgeInsetsGeometry segmentPadding(BuildContext context) {
    final fontSize = _labelStyle(context)?.fontSize ?? 14;
    return ButtonStyleButton.scaledPadding(
      const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceSMD,
        vertical: AppTokens.spaceSM,
      ),
      const EdgeInsets.symmetric(horizontal: AppTokens.spaceSM),
      const EdgeInsets.symmetric(horizontal: AppTokens.spaceXS),
      MediaQuery.textScalerOf(context).scale(fontSize) / 14,
    );
  }

  /// סגנון התווית במקטע: כמו ב-SegmentedButton, מה-theme ואחרת labelLarge.
  static TextStyle? _labelStyle(BuildContext context) {
    final theme = Theme.of(context);
    return theme.segmentedButtonTheme.style?.textStyle?.resolve(
          const <WidgetState>{},
        ) ??
        theme.textTheme.labelLarge;
  }

  /// הריווח האופקי של מקטע עם אייקון: SegmentedButton קובע אותו בעצמו, כמו
  /// ב-TextButton.icon (‏12 ו-16, ובהגדלת טקסט 4 מכל צד), והרווח בין
  /// האייקון לתווית 8, ובהגדלה ×2 ומעלה 4.
  static double _iconSegmentExtra(BuildContext context) {
    final fontSize = _labelStyle(context)?.fontSize ?? 14;
    final scale = MediaQuery.textScalerOf(context).scale(fontSize) / 14;
    final padding = ButtonStyleButton.scaledPadding(
      const EdgeInsetsDirectional.fromSTEB(
        AppTokens.spaceSMD,
        AppTokens.spaceSM,
        AppTokens.spaceMD,
        AppTokens.spaceSM,
      ),
      const EdgeInsets.symmetric(horizontal: AppTokens.spaceXS),
      const EdgeInsets.symmetric(horizontal: AppTokens.spaceXS),
      scale,
    );
    final gap = lerpDouble(
      AppTokens.spaceSM,
      AppTokens.spaceXS,
      clampDouble(scale, 1, 2) - 1,
    )!;
    return padding.resolve(Directionality.of(context)).horizontal + gap;
  }

  /// רוחב האייקון של [o] במקטע: כמו ב-[_buildOptionIcon].
  static double _iconWidth(SegmentOption<Object?> o) =>
      o.icon != null || o.rtlIcon != null
      ? AppTokens.iconSM
      : _missingIconWidth;

  /// מקום ריק לאפשרות בלי אייקון, כשלאחרות יש.
  static const double _missingIconWidth = 18;

  /// הפריסה של [shown] במקטע ברוחב [segmentWidth] ([twoRowsWhenClipped]):
  /// [_Fit.full] כשהתוויות המלאות נכנסות עם האייקונים, [_Fit.narrow] כשרק
  /// הקצרות נכנסות בלי אייקונים, ואחרת [_Fit.clipped].
  _Fit _fitOf(
    BuildContext context,
    List<SegmentOption<T>> shown,
    double segmentWidth,
  ) {
    final hasIcons = options.any((o) => o.icon != null || o.rtlIcon != null);
    final labelOnly = segmentPadding(
      context,
    ).resolve(Directionality.of(context)).horizontal;
    final iconExtra = _iconSegmentExtra(context);
    // הלחצן נותן לתווית DefaultTextStyle חדש מהסגנון הזה, בלי הסגנון שמסביב.
    final style = _labelStyle(context);
    bool fits(String label, double available) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: maxLabelLines,
      )..layout(maxWidth: available < 0 ? 0 : available);
      final clipped =
          painter.didExceedMaxLines ||
          (maxLabelLines == 1 && painter.maxIntrinsicWidth > available);
      painter.dispose();
      return !clipped;
    }

    if (shown.every(
      (o) => fits(
        o.label,
        segmentWidth -
            (hasIcons || showSelectedIcon
                ? iconExtra + _iconWidth(o)
                : labelOnly),
      ),
    )) {
      return _Fit.full;
    }
    // סימן הבחירה (showSelectedIcon) מוצג גם במקטע צר, במקום האייקון.
    final narrow =
        segmentWidth -
        (showSelectedIcon ? iconExtra + AppTokens.iconSM : labelOnly);
    if (shown.every((o) => fits(o.shortLabel ?? o.label, narrow))) {
      return _Fit.narrow;
    }
    return _Fit.clipped;
  }

  List<ButtonSegment<T>> _segments(
    List<SegmentOption<T>> shown, {
    required bool narrow,
  }) {
    final hasIcons =
        !narrow && options.any((o) => o.icon != null || o.rtlIcon != null);
    return shown
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
    return const SizedBox(width: _missingIconWidth);
  }

  static ButtonStyle _buttonStyle(BuildContext context, ColorScheme cs) =>
      ButtonStyle(
        padding: WidgetStatePropertyAll(segmentPadding(context)),
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
      builder: (context, constraints) {
        // ברוחב לא חסום (בתוך Row) הבורר ברוחבו הטבעי, ואינו צר.
        if (!constraints.hasBoundedWidth) {
          return _build(context, cs, isFixed, options, narrow: false);
        }
        final segmentWidth = constraints.maxWidth / options.length;
        if (!twoRowsWhenClipped || options.length <= 2) {
          return _build(
            context,
            cs,
            isFixed,
            options,
            narrow: segmentWidth < narrowBelowSegmentWidth,
          );
        }
        final fit = _fitOf(context, options, segmentWidth);
        if (fit != _Fit.clipped) {
          return _build(
            context,
            cs,
            isFixed,
            options,
            narrow: fit == _Fit.narrow,
          );
        }
        return _buildTwoRows(context, cs, isFixed, constraints.maxWidth);
      },
    );
  }

  /// [twoRowsWhenClipped]: שני בוררים זה מעל זה, באותו סגנון. הנבחר מסומן
  /// בשורה שלו, והשורה השנייה בלי בחירה. החצים עוברים בין המקטעים כמו
  /// בשורה אחת (ובין השורות למעלה ולמטה), ו-Tab בסדר הקריאה.
  Widget _buildTwoRows(
    BuildContext context,
    ColorScheme cs,
    bool isFixed,
    double width,
  ) {
    final perRow = (options.length + 1) ~/ 2;
    final rows = [options.sublist(0, perRow), options.sublist(perRow)];
    // באותה פריסה בשתי השורות: אם צריך, גם כאן התוויות הקצרות בלי אייקונים.
    final narrow = _fitOf(context, options, width / perRow) != _Fit.full;
    return FocusTraversalGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppTokens.spaceSM,
        children: [
          for (final row in rows)
            _build(context, cs, isFixed, row, narrow: narrow),
        ],
      ),
    );
  }

  Widget _build(
    BuildContext context,
    ColorScheme cs,
    bool isFixed,
    List<SegmentOption<T>> shown, {
    required bool narrow,
  }) {
    final split = shown.length != options.length;
    return SegmentedButton<T>(
      segments: _segments(shown, narrow: narrow),
      // בשתי שורות הנבחר נמצא רק באחת מהן, והשנייה בלי בחירה.
      selected: {
        if (!split || shown.any((o) => o.value == currentValue)) currentValue,
      },
      // בשתי שורות השורה בלי הנבחר היא בלי בחירה. בחירה ריקה מגיעה אז רק
      // מלחיצה על הנבחר, והיא לא משנה דבר.
      emptySelectionAllowed: split,
      expandedInsets: expandToFillWidth || split ? EdgeInsets.zero : null,
      onSelectionChanged: (Set<T> selection) {
        if (selection.isNotEmpty) onChanged(selection.first);
      },
      showSelectedIcon: showSelectedIcon,
      selectedIcon: const Icon(
        FluentIcons.checkmark_24_regular,
        size: AppTokens.iconSM,
      ),
      style: isFixed
          ? _buttonStyle(context, cs).copyWith(
              minimumSize: WidgetStateProperty.all(Size(0, height!)),
              maximumSize: WidgetStateProperty.all(
                Size(
                  double.infinity,
                  maxLabelLines > 1 ? double.infinity : height!,
                ),
              ),
            )
          : _buttonStyle(context, cs).copyWith(
              visualDensity: VisualDensity.compact,
            ),
    );
  }
}
