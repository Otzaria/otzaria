import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/layout/centered_scrollable_state.dart';

/// ווידג'ט מרכזי ואחיד למצבי ריק (Empty State / אין תוצאות) בכל רחבי האפליקציה.
///
/// תומך בארבעת הפרמטרים העיצוביים:
/// 1. סמל ([icon] או [customIcon])
/// 2. כותרת ראשית ([title])
/// 3. מלל עזר/הסבר אופציונלי ([message])
/// 4. כפתור או קבוצת כפתורי פעולה ([action] / [actions])
///
/// כולל תמיכה במצב קומפקטי ([isCompact]) המותאם לחלוניות צדדיות צרות (מפרשים, קישורים, הערות, ניווט).
class OtzariaEmptyState extends StatelessWidget {
  final IconData? icon;
  final Widget? customIcon;
  final String title;
  final String? message;

  /// תוכן חופשי בין ההודעה לכפתורים (למשל תיבת פירוט או רשימת צעדים).
  final Widget? body;
  final Widget? action;
  final List<Widget>? actions;
  final bool isCompact;
  final EdgeInsetsGeometry? padding;

  /// האם לעטוף את התוכן במעטפת גלילה ממורכזת ([CenteredScrollableState]).
  /// כברירת מחדל `true`. יש לכבות (`false`) כאשר הרכיב מוצג בתוך אזור
  /// שכבר מנהל גלילה בעצמו — כגון [SliverFillRemaining] או [CustomScrollView],
  /// כדי למנוע גלילה כפולה וקריסת חישוב ממדים אינטרינסיים ב-LayoutBuilder.
  final bool scrollable;

  final bool _large;

  const OtzariaEmptyState({
    super.key,
    this.icon,
    this.customIcon,
    required this.title,
    this.message,
    this.body,
    this.action,
    this.actions,
    this.isCompact = false,
    this.padding,
    this.scrollable = true,
  }) : _large = false,
       assert(
         icon == null || customIcon == null,
         'Cannot provide both icon and customIcon',
       ),
       assert(
         action == null || actions == null,
         'Cannot provide both action and actions',
       );

  /// מצב ריק של מסך שלם (ספרייה ריקה, אינדקס חסר), DD-31d: אייקון 64,
  /// headlineSmall, bodyLarge, רוחב עד 420, ו־[actions] ברוחב מלא זו מתחת לזו.
  const OtzariaEmptyState.large({
    super.key,
    this.icon,
    this.customIcon,
    required this.title,
    this.message,
    this.body,
    this.actions,
    this.padding,
    this.scrollable = true,
  }) : action = null,
       isCompact = false,
       _large = true,
       assert(
         icon == null || customIcon == null,
         'Cannot provide both icon and customIcon',
       );

  static const double _largeIconSize = 64;
  static const double _largeMaxWidth = 420;

  @override
  Widget build(BuildContext context) {
    if (_large) return _buildLarge(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final Widget? iconWidget =
        customIcon ??
        (icon != null
            ? Icon(
                icon,
                size: isCompact ? 36 : 56,
                color: cs.onSurfaceVariant,
              )
            : null);

    final titleStyle =
        (isCompact ? theme.textTheme.bodyMedium : theme.textTheme.titleMedium)
            ?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface);

    final messageStyle =
        (isCompact ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)
            ?.copyWith(color: cs.onSurfaceVariant);

    final effectiveActions = actions ?? (action != null ? [action!] : null);

    final effectivePadding =
        padding ??
        (isCompact
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
            : const EdgeInsets.all(AppTokens.spaceLG));

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (iconWidget != null) ...[
          iconWidget,
          SizedBox(height: isCompact ? AppTokens.spaceSM : AppTokens.spaceMD),
        ],
        Text(
          title,
          style: titleStyle,
          textAlign: TextAlign.center,
        ),
        if (message != null) ...[
          SizedBox(height: isCompact ? 4 : AppTokens.spaceSM),
          Text(
            message!,
            style: messageStyle,
            textAlign: TextAlign.center,
          ),
        ],
        if (body != null) ...[
          SizedBox(height: isCompact ? AppTokens.spaceSM : AppTokens.spaceMD),
          body!,
        ],
        if (effectiveActions != null && effectiveActions.isNotEmpty) ...[
          SizedBox(height: isCompact ? AppTokens.spaceMD : AppTokens.spaceLG),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppTokens.spaceSM,
            runSpacing: AppTokens.spaceSM,
            children: effectiveActions,
          ),
        ],
      ],
    );

    if (!scrollable) {
      return Center(
        child: Padding(
          padding: effectivePadding,
          child: content,
        ),
      );
    }

    return CenteredScrollableState(
      padding: effectivePadding,
      child: content,
    );
  }

  Widget _buildLarge(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final iconWidget =
        customIcon ??
        (icon != null
            ? Icon(icon, size: _largeIconSize, color: cs.onSurfaceVariant)
            : null);
    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _largeMaxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (iconWidget != null) ...[
            iconWidget,
            const SizedBox(height: AppTokens.spaceMD),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: cs.onSurface,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: AppTokens.spaceSM),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (body != null) ...[
            const SizedBox(height: AppTokens.spaceMD),
            body!,
          ],
          if (actions != null && actions!.isNotEmpty) ...[
            const SizedBox(height: AppTokens.spaceLG),
            for (final (i, action) in actions!.indexed) ...[
              if (i > 0) const SizedBox(height: AppTokens.spaceSM),
              SizedBox(width: double.infinity, child: action),
            ],
          ],
        ],
      ),
    );
    final effectivePadding = padding ?? const EdgeInsets.all(AppTokens.spaceLG);
    if (!scrollable) {
      return Center(
        child: Padding(padding: effectivePadding, child: content),
      );
    }
    return CenteredScrollableState(padding: effectivePadding, child: content);
  }
}
