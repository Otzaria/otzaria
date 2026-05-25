import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// כרטיס תוכן מרכזי עם צבע ופינות מעוגלות אחידים.
///
/// שני קונסטרקטורים:
/// - [AppCard] — כרטיס עם ילד יחיד; תומך ב-[onTap], [selected], [animateSize].
/// - [AppCard.section] — מקטע עם מספר שורות; מוסיף אוטומטית רווח 1.5px בין שורות.
class AppCard extends StatelessWidget {
  /// כרטיס עם ילד יחיד.
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.focusNode,
    this.margin,
    this.padding,
    this.radius,
    this.selected = false,
    this.animate = true,
    this.animationDelay,
    this.animateSize = false,
  }) : children = null;

  /// כרטיס מקטע עם מספר שורות — רווח 1.5px בין שורות.
  const AppCard.section({
    super.key,
    required this.children,
    this.margin,
    this.padding,
    this.radius,
    this.selected = false,
    this.animate = true,
    this.animationDelay,
    this.animateSize = false,
  })  : child = null,
        onTap = null,
        focusNode = null;

  final Widget? child;
  final List<Widget>? children;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  /// ברירת מחדל: [AppTokens.radiusXL]
  final double? radius;

  /// מוסיף overlay של secondaryContainer מעל הכרטיס
  final bool selected;

  /// אנימציית כניסה (FadeIn + SlideIn) — יופעל בשלב ד׳
  final bool animate;

  /// עיכוב לאנימציית כניסה — לשימוש ברשימות לפי אינדקס
  final Duration? animationDelay;

  /// עוטף ב-[AnimatedSize] לאנימציית שינוי גובה חלק
  final bool animateSize;

  /// Divider חיצוני בצבע עקבי עם המפריד הפנימי של [AppCard.section].
  ///
  /// לשימוש כשתוכן מורחב (AnimatedSize וכד') צריך להיראות כחלק מהכרטיס.
  static Widget sectionDivider(BuildContext context) => Divider(
        height: 1,
        thickness: 1.5,
        indent: 0,
        endIndent: 0,
        color: AppSurfaces.cardRowDivider(context),
      );

  @override
  Widget build(BuildContext context) {
    Widget card = children != null ? _buildSection(context) : _buildSingle(context);

    if (animateSize) {
      card = AnimatedSize(
        duration: Durations.medium2,
        curve: Curves.easeInOut,
        child: card,
      );
    }

    if (margin != null) {
      card = Padding(padding: margin!, child: card);
    }

    return card;
  }

  Widget _buildSingle(BuildContext context) {
    final resolvedRadius = BorderRadius.circular(radius ?? AppTokens.radiusXL);
    Widget content = child!;

    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }

    if (selected) {
      content = _withSelected(context, content);
    }

    if (onTap != null) {
      return Material(
        color: AppSurfaces.card(context),
        surfaceTintColor: Colors.transparent,
        borderRadius: resolvedRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          focusNode: focusNode,
          mouseCursor: SystemMouseCursors.click,
          child: content,
        ),
      );
    }

    return ClipRRect(
      borderRadius: resolvedRadius,
      child: ColoredBox(
        color: AppSurfaces.card(context),
        child: content,
      ),
    );
  }

  Widget _buildSection(BuildContext context) {
    final resolvedRadius = BorderRadius.circular(radius ?? AppTokens.radiusXL);
    final cardColor = AppSurfaces.card(context);

    Widget wrapChild(Widget w) {
      if (padding != null) w = Padding(padding: padding!, child: w);
      if (selected) w = _withSelected(context, w);
      return ColoredBox(color: cardColor, child: w);
    }

    return ClipRRect(
      borderRadius: resolvedRadius,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < children!.length; i++) ...[
            wrapChild(children![i]),
            if (i < children!.length - 1) const SizedBox(height: 1.5),
          ],
        ],
      ),
    );
  }

  Widget _withSelected(BuildContext context, Widget w) => ColoredBox(
        color: Theme.of(context)
            .colorScheme
            .secondaryContainer
            .withValues(alpha: 0.3),
        child: w,
      );
}
