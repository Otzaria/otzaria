import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_density.dart';
import 'package:otzaria/theme/app_tokens.dart';

/// גודל האייקון של [AppIconButton], מסולם `AppTokens.icon*`.
enum AppIconButtonSize {
  /// פעולת שורה, שורת כותרת, כפתור בתוך שדה.
  small(AppTokens.iconSM),

  /// כותרת חלונית.
  medium(AppTokens.iconMD),

  /// ברירת המחדל של M3: סגירת דיאלוג, פעולה בכרטיס.
  large(AppTokens.iconLG);

  const AppIconButtonSize(this.iconSize);

  final double iconSize;

  /// צלע הכפתור: האייקון ועוד 8 מכל צד, ו־6 בצפיפות קומפקטית. אזור המגע
  /// לפי `materialTapTargetSize` של ערכת הנושא (48 במובייל).
  double extent({required bool compact}) => iconSize + (compact ? 12 : 16);
}

/// הרקע של [AppIconButton] כשיש לו רקע גלוי. הצורה זהה גם בלי רקע: מלבן עם
/// פינות `AppTokens.radius` (DD-04, ההכרעה מ־19.11).
enum AppIconButtonFill {
  /// גוון הערכה (`secondaryContainer`), כמו `IconButton.filledTonal`: פעולה
  /// בולטת בתוך מסך, או מצב פעיל.
  tonal,

  /// משטח נייטרלי (`surfaceContainerHighest`): כפתור צף, או מתג כבוי.
  neutral,
}

/// כפתור אייקון בלבד: עטיפה דקה על [IconButton] עם tooltip חובה, גודל
/// מ־`AppTokens.icon*` ומ־[AppDensity], וצורת מלבן עם פינות 8 (DD-04: שום
/// כפתור אייקון אינו עגול). הריחוף והלחיצה מערכת הנושא.
///
/// עם רקע ([fill], או [backgroundColor] מפורש) הצורה אינה משתנה: אותו מלבן
/// עם פינות 8, רק עם צבע מילוי.
///
/// [icon] הוא בדרך כלל `Icon` בלי `size`; הגודל מגיע מ־[size].
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = AppIconButtonSize.large,
    this.isSelected,
    this.selectedIcon,
    this.focusNode,
    this.tapTargetSize,
    this.fill,
    this.backgroundColor,
    this.foregroundColor,
    this.extent,
  });

  final Widget icon;

  /// גם השם הנגיש. קיצור מקשים נכתב בסוגריים: "הדפסה (Ctrl+P)".
  final String tooltip;

  /// null = מושבת.
  final VoidCallback? onPressed;
  final AppIconButtonSize size;

  /// כפתור דו־מצבי: הנבחר בצבע `primary` (ברירת המחדל של M3).
  final bool? isSelected;

  /// האייקון במצב [isSelected]. null = אותו [icon].
  final Widget? selectedIcon;
  final FocusNode? focusNode;

  /// null = לפי ערכת הנושא (48 במובייל). `shrinkWrap` בסרגלים בגובה קבוע,
  /// כמו שורת הכותרת.
  final MaterialTapTargetSize? tapTargetSize;

  /// רקע גלוי מאחורי האייקון. null = בלי רקע.
  final AppIconButtonFill? fill;

  /// צבע רקע מפורש, כשהצבע מגיע מבחוץ (צבע של כלי, סימון נבחר בסרגל).
  /// גובר על [fill].
  final Color? backgroundColor;

  /// צבע האייקון. null = לפי [fill], ובלי [fill] לפי ערכת הנושא.
  final Color? foregroundColor;

  /// צלע הכפתור כשהיא נקבעת מבחוץ (למשל שדה חיפוש בצפיפות שלו). null = לפי
  /// [size] והצפיפות.
  final double? extent;

  @override
  Widget build(BuildContext context) {
    final side =
        extent ?? size.extent(compact: AppDensity.of(context).isCompact);
    final cs = Theme.of(context).colorScheme;
    final background =
        backgroundColor ??
        switch (fill) {
          AppIconButtonFill.tonal => cs.secondaryContainer,
          AppIconButtonFill.neutral => cs.surfaceContainerHighest,
          null => null,
        };
    final foreground =
        foregroundColor ??
        switch (fill) {
          AppIconButtonFill.tonal => cs.onSecondaryContainer,
          AppIconButtonFill.neutral => cs.onSurface,
          null => null,
        };
    return IconButton(
      icon: icon,
      selectedIcon: selectedIcon,
      tooltip: tooltip,
      onPressed: onPressed,
      isSelected: isSelected,
      focusNode: focusNode,
      iconSize: size.iconSize,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: side, height: side),
      style: IconButton.styleFrom(
        shape: AppTokens.roundedShape,
        backgroundColor: background,
        foregroundColor: foreground,
        tapTargetSize: tapTargetSize,
        visualDensity: VisualDensity.standard,
      ),
    );
  }
}
