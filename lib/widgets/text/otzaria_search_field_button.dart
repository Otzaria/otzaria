// lib/widgets/text/otzaria_search_field_button.dart

import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// מידות כפתור פעולה בשדה חיפוש. [OtzariaSearchField] קובע אותן לכפתורים
/// שבתוכו לפי הצפיפות שלו; מחוץ לו (שדה טופס עם תווית) — [form].
@immutable
class OtzariaSearchActionSize {
  /// צלע ריבוע הלחיצה.
  final double button;
  final double icon;

  /// ה-X של כפתור הניקוי, קטן מ-[icon] כי הגליף שלו כבד.
  final double clearIcon;

  const OtzariaSearchActionSize._(this.button, this.icon, this.clearIcon);

  /// [OtzariaSearchField] צר (36).
  static const slim = OtzariaSearchActionSize._(26, 16, 15);

  /// [OtzariaSearchField] רגיל (48).
  static const regular = OtzariaSearchActionSize._(32, 20, 18);

  /// שדה טקסט עם עיטור ערכת הנושא ותווית. האייקון בגודל ממשק רגיל (DD-03),
  /// וה-X כמוהו: בריבוע 40 אין צורך להקטין אותו.
  static const form = OtzariaSearchActionSize._(
    40,
    AppTokens.iconMD,
    AppTokens.iconMD,
  );

  static OtzariaSearchActionSize of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<OtzariaSearchActionScope>()
          ?.size ??
      form;
}

/// קובע את [OtzariaSearchActionSize] לכפתורים שמתחתיו.
class OtzariaSearchActionScope extends InheritedWidget {
  final OtzariaSearchActionSize size;

  /// כמה רוחב נוסף מותר לתוויות של [OtzariaSearchFieldButton.label] בלי
  /// לצמצם את תיבת הקלט מתחת לרוחב שמיש. 0 = אין מקום: אייקון בלבד.
  final double labelBudget;

  const OtzariaSearchActionScope({
    super.key,
    required this.size,
    this.labelBudget = 0,
    required super.child,
  });

  /// מחוץ לשדה חיפוש אין מגבלה.
  static double labelBudgetOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<OtzariaSearchActionScope>()
          ?.labelBudget ??
      double.infinity;

  @override
  bool updateShouldNotify(OtzariaSearchActionScope oldWidget) =>
      size != oldWidget.size || labelBudget != oldWidget.labelBudget;
}

/// כפתור אייקון בתוך שדה חיפוש: גודל מהשדה, tooltip חובה.
///
/// [selected] — מצב דלוק של כפתור מתג, באותו רקע כמו [BarButton] נבחר.
/// [busy] — ספינר במקום האייקון; הכפתור נשאר לחיץ.
/// [label] — תווית קצרה ליד האייקון, בצורת צ'יפ (q9 שאלה 14, q10 שאלה 23), כשיש לה מקום בשדה.
class OtzariaSearchFieldButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final bool busy;

  /// צבע האייקון כשהכפתור אינו [selected]. null = onSurfaceVariant.
  final Color? color;

  /// [clearIcon] של המידות במקום [icon].
  final bool clearGlyph;

  /// מוצגת רק אם הכפתור עם התווית נכנס ב־[OtzariaSearchActionScope.labelBudget];
  /// אחרת הכפתור הוא אייקון בלבד, ו־[tooltip] אומר את אותו הדבר.
  final String? label;

  /// סגנון התווית: כמו צ'יפ, labelMedium (12).
  static TextStyle? labelStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelMedium;
  static const double _labelPadding = AppTokens.spaceSM;
  static const double _labelGap = AppTokens.spaceXS;

  /// כמה הכפתור רחב יותר עם [label] מאשר בלעדיה.
  static double labelExtraWidth(
    BuildContext context,
    String label,
    OtzariaSearchActionSize size,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: DefaultTextStyle.of(context).style.merge(labelStyle(context)),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return _labelPadding * 2 + size.icon + _labelGap + width - size.button;
  }

  const OtzariaSearchFieldButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.busy = false,
    this.color,
    this.clearGlyph = false,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = OtzariaSearchActionSize.of(context);
    final iconSize = clearGlyph ? size.clearIcon : size.icon;
    final label = this.label;
    if (label != null &&
        !busy &&
        labelExtraWidth(context, label, size) <=
            OtzariaSearchActionScope.labelBudgetOf(context)) {
      return _buildLabeled(context, cs, size, label);
    }
    return SizedBox.square(
      dimension: size.button,
      child: IconButton(
        icon: busy
            ? SizedBox.square(
                dimension: iconSize * 0.8,
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: iconSize),
        tooltip: tooltip,
        isSelected: selected,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        color: selected
            ? cs.onSecondaryContainer
            : (color ?? cs.onSurfaceVariant),
        style: selected
            ? IconButton.styleFrom(
                backgroundColor: AppSurfaces.barButtonSelected(cs),
                shape: AppTokens.roundedShape,
              )
            : null,
      ),
    );
  }

  // בצורה ובגודל של צ'יפ: פינות 8 ו-labelMedium (q10 שאלה 23).
  Widget _buildLabeled(
    BuildContext context,
    ColorScheme cs,
    OtzariaSearchActionSize size,
    String label,
  ) {
    final fg = selected
        ? cs.onSecondaryContainer
        : (color ?? cs.onSurfaceVariant);
    const shape = AppTokens.roundedShape;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        container: true,
        child: SizedBox(
          height: size.button,
          child: Material(
            color: selected
                ? AppSurfaces.barButtonSelected(cs)
                : Colors.transparent,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              customBorder: shape,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _labelPadding),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: size.icon, color: fg),
                    const SizedBox(width: _labelGap),
                    Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: labelStyle(context)?.copyWith(color: fg),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
