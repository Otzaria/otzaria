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

  /// שדה טקסט עם עיטור ערכת הנושא ותווית.
  static const form = OtzariaSearchActionSize._(40, 22, 22);

  static OtzariaSearchActionSize of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<OtzariaSearchActionScope>()
          ?.size ??
      form;
}

/// קובע את [OtzariaSearchActionSize] לכפתורים שמתחתיו.
class OtzariaSearchActionScope extends InheritedWidget {
  final OtzariaSearchActionSize size;

  const OtzariaSearchActionScope({
    super.key,
    required this.size,
    required super.child,
  });

  @override
  bool updateShouldNotify(OtzariaSearchActionScope oldWidget) =>
      size != oldWidget.size;
}

/// כפתור אייקון בתוך שדה חיפוש: גודל מהשדה, tooltip חובה.
///
/// [selected] — מצב דלוק של כפתור מתג, באותו רקע כמו [BarButton] נבחר.
/// [busy] — ספינר במקום האייקון; הכפתור נשאר לחיץ.
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

  const OtzariaSearchFieldButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.busy = false,
    this.color,
    this.clearGlyph = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = OtzariaSearchActionSize.of(context);
    final iconSize = clearGlyph ? size.clearIcon : size.icon;
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
}
