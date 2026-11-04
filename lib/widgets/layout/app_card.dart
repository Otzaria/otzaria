import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// גוון הרקע של [AppCard]. הטקסט והאייקונים בתוכו מקבלים את צבע ה־on התואם.
enum AppCardTone {
  /// רקע הכרטיס של האזור ([AppSurfaces.card]).
  normal,

  /// הדגשה: `primaryContainer`.
  primary,

  /// שגיאה: `errorContainer`.
  error,

  /// כרטיס שיושב בתוך כרטיס אחר (למשל בתוך SettingsCard): `surfaceContainerHigh`,
  /// כדי שיובחן מהמשטח שסביבו. הטקסט נשאר בצבעי ברירת המחדל.
  inset,
}

/// כרטיס תוכן מרכזי עם צבע ופינות מעוגלות אחידים, ומסגרת `outlineVariant`
/// בלי צל (DD-12).
///
/// שני קונסטרקטורים:
/// - [AppCard] — כרטיס עם ילד יחיד; תומך ב-[onTap], ב-[selected], ב-[active]
///   וב-[tone].
/// - [AppCard.section] — מקטע עם מספר שורות; מוסיף אוטומטית רווח 1.5px בין שורות.
class AppCard extends StatelessWidget {
  /// כרטיס עם ילד יחיד.
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.focusNode,
    this.onFocusChange,
    this.requestFocusOnTap = false,
    this.margin,
    this.padding,
    this.selected = false,
    this.active = false,
    this.tone = AppCardTone.normal,
  }) : children = null;

  /// כרטיס מקטע עם מספר שורות — רווח 1.5px בין שורות.
  const AppCard.section({super.key, required this.children})
    : child = null,
      onTap = null,
      focusNode = null,
      onFocusChange = null,
      requestFocusOnTap = false,
      margin = null,
      padding = null,
      selected = false,
      active = false,
      tone = AppCardTone.normal;

  /// הרווח הקבוע בין שורות במקטע כרטיס.
  static const double sectionSpacing = 1.5;

  /// צורת הכרטיס: פינות 8 ומסגרת `outlineVariant`, וב-[active] מסגרת
  /// הבחירה ([AppSurfaces.multiSelectedBorder], 1.5). [selectedBorder] —
  /// המסגרת של כרטיס נבחר ([AppSurfaces.selectedBorder], רק ב"לבן" בבהיר).
  static ShapeBorder shape(
    ColorScheme cs, {
    bool active = false,
    Color? selectedBorder,
  }) => RoundedRectangleBorder(
    borderRadius: AppTokens.borderRadiusAll,
    side: active
        ? BorderSide(
            color: AppSurfaces.multiSelectedBorder(cs),
            width: AppTokens.multiSelectedBorderWidth,
          )
        : BorderSide(
            color: selectedBorder ?? cs.outlineVariant,
            width: AppTokens.borderThin,
          ),
  );

  final Widget? child;
  final List<Widget>? children;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;

  /// לחיצת עכבר ממקדת את הכרטיס (כמו בסייר), כדי שהמקלדת תמשיך ממנו.
  final bool requestFocusOnTap;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  /// רקע [AppSurfaces.selectedRow] במקום רקע הטון. נצבע על ה-Material, כדי
  /// שהריחוף והלחיצה של הכרטיס יצוירו מעליו. ב"לבן" בבהיר גם המסגרת
  /// מתחלפת לקו הבחירה ([AppSurfaces.selectedBorder]).
  final bool selected;

  /// הפריט הפעיל ברשת כרטיסים (למשל שולחן העבודה הנוכחי): מסגרת הבחירה
  /// במקום `outlineVariant`, כדי ש"פעיל" לא יסומן רק בצבע (DD-06).
  final bool active;

  final AppCardTone tone;

  /// Divider חיצוני בצבע עקבי עם המפריד הפנימי של [AppCard.section].
  ///
  /// לשימוש כשתוכן פנימי מורחב צריך להיראות כחלק מהכרטיס.
  static Widget sectionDivider(BuildContext context) => Divider(
    height: 1,
    thickness: sectionSpacing,
    indent: 0,
    endIndent: 0,
    color: AppSurfaces.cardRowDivider(context),
  );

  @override
  Widget build(BuildContext context) {
    Widget card = children != null
        ? _buildSection(context)
        : _buildSingle(context);

    if (margin != null) {
      card = Padding(padding: margin!, child: card);
    }

    return card;
  }

  Widget _buildSingle(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cardShape = shape(
      cs,
      active: active,
      selectedBorder: selected ? AppSurfaces.selectedBorder(context) : null,
    );
    final (Color toneColor, Color? onColor) = switch (tone) {
      AppCardTone.normal => (AppSurfaces.card(context), null),
      AppCardTone.primary => (cs.primaryContainer, cs.onPrimaryContainer),
      AppCardTone.error => (cs.errorContainer, cs.onErrorContainer),
      AppCardTone.inset => (cs.surfaceContainerHigh, null),
    };
    final color = selected ? AppSurfaces.selectedRow(cs) : toneColor;
    Widget content = child!;
    if (onColor != null) {
      content = IconTheme.merge(
        data: IconThemeData(color: onColor),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: onColor),
          child: content,
        ),
      );
    }

    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }

    if (onTap != null) {
      late FocusNode cardFocusNode;
      if (requestFocusOnTap) {
        final tappable = content;
        // ה-Builder יושב בתוך ה-InkWell, ולכן Focus.of מחזיר את צומת הכרטיס.
        content = Builder(
          builder: (cardContext) {
            cardFocusNode = Focus.of(cardContext);
            return tappable;
          },
        );
      }
      return Material(
        color: color,
        surfaceTintColor: Colors.transparent,
        shape: cardShape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onTapUp: requestFocusOnTap
              ? (_) => cardFocusNode.requestFocus()
              : null,
          focusNode: focusNode,
          onFocusChange: onFocusChange,
          mouseCursor: SystemMouseCursors.click,
          hoverDuration: Durations.medium1,
          child: content,
        ),
      );
    }

    return Material(
      color: color,
      shape: cardShape,
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }

  Widget _buildSection(BuildContext context) {
    final resolvedRadius = AppTokens.borderRadiusAll;
    final cardColor = AppSurfaces.card(context);

    Widget wrapChild(Widget w) {
      // Material per-row so ListTile ink/hover paint correctly,
      // and the transparent SizedBox gap shows the background behind the card.
      return Material(color: cardColor, child: w);
    }

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < children!.length; i++) ...[
          wrapChild(children![i]),
          if (i < children!.length - 1) const SizedBox(height: sectionSpacing),
        ],
      ],
    );

    // המסגרת מעל השורות, כדי שרקע השורות לא יכסה אותה.
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: ShapeDecoration(
        shape: shape(Theme.of(context).colorScheme),
      ),
      child: ClipRRect(borderRadius: resolvedRadius, child: content),
    );
  }
}
