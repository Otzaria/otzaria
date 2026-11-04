// lib/widgets/dialogs/app_dialog_header.dart
// כותרת משותפת לדיאלוגים מורכבים: פס צבוע, תג אייקון עגול, שם ותיאור קצר.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/theme/layout_tokens.dart';
import 'package:otzaria/widgets/controls/app_icon_button.dart';

/// גוון תג האייקון בכותרת. [error] שמור למצבי תקלה וסיכון.
enum AppDialogHeaderTone { primary, error }

/// כותרת דיאלוג בצורה אחידה: אייקון מסומל, שם, שורת משנה אופציונלית וכפתור
/// סגירה. משמשת את דיאלוגי הדיווח, ההקרסה והרשימות, כדי שכולם ייראו כחלק
/// מאותה מערכת.
class AppDialogHeader extends StatelessWidget {
  const AppDialogHeader({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.tone = AppDialogHeaderTone.primary,
    this.onClose,
    this.closeEnabled = true,
    this.showClose = true,
    this.closeTooltip,
    this.compact = false,
    this.titleMaxLines,
    this.subtitleMaxLines,
    this.fitTitle = false,
  });

  /// null = בלי תג אייקון (כותרת טקסט בלבד, באותה רצועה).
  final IconData? icon;
  final String title;

  /// שורה קטנה מתחת לשם: תיאור המקרה, שם הספר וכד'.
  final String? subtitle;

  /// פקדים בתחילת הרצועה, לפני התג. בחלון צר הם יורדים לשורה משלהם מתחת
  /// לכותרת, כדי לא לדחוק אותה.
  final Widget? leading;

  /// ווידג'ט בין הטקסט לכפתור הסגירה, למשל מונה.
  final Widget? trailing;

  final AppDialogHeaderTone tone;

  /// ברירת מחדל: [Navigator.maybePop], כמו Escape, כדי שיעבור בשומר השינויים
  /// של הדיאלוג. [closeEnabled] false משבית את הכפתור, למשל בזמן שליחה.
  final VoidCallback? onClose;
  final bool closeEnabled;

  /// false = בלי כפתור סגירה, למשל בדיאלוג התקדמות שאי אפשר לסגור.
  final bool showClose;

  /// טקסט הרמז של כפתור הסגירה; null = "סגור" בשפת הממשק.
  final String? closeTooltip;

  /// ריפוד אנכי קטן יותר, לכותרות שאינן מחזיקות תיאור ארוך.
  final bool compact;

  /// מגביל כותרת ארוכה ומציג את הטקסט המלא ברמז; null ללא הגבלה.
  final int? titleMaxLines;

  /// null = בלי הגבלה. כותרות עם שם ספר ארוך מגבילות לשורה אחת.
  final int? subtitleMaxLines;

  /// הכותרת בשורה אחת שמצטמצמת לרוחב הזמין, במקום לשבור שורה.
  final bool fitTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final vertical = compact ? AppTokens.spaceSM : AppTokens.spaceMD;
    // ברוחב טלפון ה-trailing (מונה, שם צבע) היה מצמצם את הכותרת לרוחב של אות
    // אחת; שם הוא יורד לשורה משלו מתחת לכותרת. נמדד לפי המסך ולא לפי
    // LayoutBuilder, כי AlertDialog מודד רוחב פנימי.
    final compactWindow = WindowClass.of(context).isCompact;
    final stackTrailing = trailing != null && compactWindow;
    final stackLeading = leading != null && compactWindow;
    return Container(
      // קו עדין בתחתית הרצועה: מפריד בינה לבין גוף הדיאלוג.
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: AppSurfaces.regionBorder(context) ?? cs.outlineVariant,
          ),
        ),
      ),
      padding: EdgeInsetsDirectional.fromSTEB(
        AppTokens.spaceLG,
        vertical,
        AppTokens.spaceSM,
        vertical,
      ),
      child: _withStackedLeading(
        stackLeading,
        Row(
          children: [
            if (leading != null && !stackLeading) ...[
              leading!,
              const SizedBox(width: AppTokens.spaceMD),
            ],
            if (icon != null) ...[
              AppDialogIconBadge(icon: icon!, tone: tone),
              const SizedBox(width: AppTokens.spaceMD),
            ] else
              const SizedBox(width: AppTokens.spaceSM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (fitTitle)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          title,
                          maxLines: 1,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                    )
                  else if (titleMaxLines != null)
                    Tooltip(
                      message: title,
                      child: Text(
                        title,
                        maxLines: titleMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge,
                      ),
                    )
                  else
                    Text(title, style: theme.textTheme.titleLarge),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: subtitleMaxLines,
                      overflow: subtitleMaxLines == null
                          ? null
                          : TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (stackTrailing) ...[
                    const SizedBox(height: AppTokens.spaceXS),
                    trailing!,
                  ],
                ],
              ),
            ),
            if (trailing != null && !stackTrailing) ...[
              const SizedBox(width: AppTokens.spaceSM),
              trailing!,
            ],
            if (showClose)
              AppIconButton(
                icon: const Icon(FluentIcons.dismiss_24_regular),
                tooltip: closeTooltip ?? context.settingsText('סגור'),
                onPressed: closeEnabled
                    ? (onClose ?? () => Navigator.of(context).maybePop())
                    : null,
              )
            else
              const SizedBox(width: AppTokens.spaceSM),
          ],
        ),
      ),
    );
  }

  Widget _withStackedLeading(bool stack, Widget row) {
    if (!stack) return row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        Padding(
          padding: const EdgeInsets.only(top: AppTokens.spaceSM),
          child: leading!,
        ),
      ],
    );
  }
}

/// תג האייקון העגול של כותרות הדיאלוגים.
class AppDialogIconBadge extends StatelessWidget {
  const AppDialogIconBadge({
    super.key,
    required this.icon,
    this.tone = AppDialogHeaderTone.primary,
  });

  final IconData icon;
  final AppDialogHeaderTone tone;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isError = tone == AppDialogHeaderTone.error;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isError ? cs.errorContainer : cs.primaryContainer,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Icon(
        icon,
        size: AppTokens.iconMD,
        color: isError ? cs.onErrorContainer : cs.onPrimaryContainer,
      ),
    );
  }
}

/// כותרת של דיאלוג פשוט (AlertDialog): אותו סגנון כמו [AppDialogHeader],
/// עם תג אייקון כשיש משמעות לאייקון — למשל אזהרה.
class AppDialogTitle extends StatelessWidget {
  const AppDialogTitle(
    this.title, {
    super.key,
    this.icon,
    this.tone = AppDialogHeaderTone.primary,
    this.textDirection,
  });

  final String title;
  final IconData? icon;
  final AppDialogHeaderTone tone;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      title,
      textDirection: textDirection,
      style: Theme.of(context).textTheme.titleLarge,
    );
    if (icon == null) return text;
    return Row(
      children: [
        AppDialogIconBadge(icon: icon!, tone: tone),
        const SizedBox(width: AppTokens.spaceMD),
        Expanded(child: text),
      ],
    );
  }
}
