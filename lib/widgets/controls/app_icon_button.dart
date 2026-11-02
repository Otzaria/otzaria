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

/// כפתור אייקון בלבד: עטיפה דקה על [IconButton] עם tooltip חובה, גודל
/// מ־`AppTokens.icon*` ומ־[AppDensity], וצורה עגולה (DD-04: כפתור אייקון בלבד
/// נשאר עגול). הריחוף והלחיצה מערכת הנושא.
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
    this.focusNode,
    this.tapTargetSize,
  });

  final Widget icon;

  /// גם השם הנגיש. קיצור מקשים נכתב בסוגריים: "הדפסה (Ctrl+P)".
  final String tooltip;

  /// null = מושבת.
  final VoidCallback? onPressed;
  final AppIconButtonSize size;

  /// כפתור דו־מצבי: הנבחר בצבע `primary` (ברירת המחדל של M3).
  final bool? isSelected;
  final FocusNode? focusNode;

  /// null = לפי ערכת הנושא (48 במובייל). `shrinkWrap` בסרגלים בגובה קבוע,
  /// כמו שורת הכותרת.
  final MaterialTapTargetSize? tapTargetSize;

  @override
  Widget build(BuildContext context) {
    final side = size.extent(compact: AppDensity.of(context).isCompact);
    return IconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
      isSelected: isSelected,
      focusNode: focusNode,
      iconSize: size.iconSize,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: side, height: side),
      style: IconButton.styleFrom(
        shape: const CircleBorder(),
        tapTargetSize: tapTargetSize,
        visualDensity: VisualDensity.standard,
      ),
    );
  }
}
