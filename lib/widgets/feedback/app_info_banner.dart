import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// הטון של [AppInfoBanner] (DD-24).
enum AppInfoBannerTone {
  /// מידע והמלצה. על רקע נייטרלי, והאייקון בצבע הערכה: בערכות שבהן
  /// primaryContainer קרוב לגוון האזהרה, מידע ואזהרה נבדלים.
  info,

  /// דורש תשומת לב, מטוקני האזהרה.
  warning,

  /// תקלה, או מצב שהפעולה אינה אפשרית בו.
  error,

  /// הושלם. בגוון החום הנייטרלי (secondaryContainer), לא בירוק.
  success,

  /// מצב מיוחד שאינו מידע רגיל ואינו אזהרה: סשן תיקון של תוסף, הצעת תיקון
  /// פריסה. בצבע המשלים של הערכה (tertiaryContainer).
  tertiary,
}

/// באנר הודעה בתוך המסך: אייקון, כותרת אופציונלית והודעה, על רקע הטון.
class AppInfoBanner extends StatelessWidget {
  final String message;

  /// במקום [message], להודעה שחלק ממנה מודגש או לחיץ (`AppInlineLink.styleOf`).
  final InlineSpan? messageSpan;
  final String? title;

  /// בלעדיו — אייקון ברירת המחדל של הטון.
  final IconData? icon;
  final AppInfoBannerTone tone;

  /// ממורכז את הכותרת וההודעה בתוך הבאנר. האייקון נשאר בצד ההתחלה.
  final bool centerText;

  /// שורות נוספות מתחת להודעה, כל אחת ב-`Text` משלה ובאותו סגנון.
  final List<String> extraLines;

  /// הודעה בשורה אחת, נחתכת בשלוש נקודות. null = בלי הגבלה.
  final int? messageMaxLines;

  /// בסוף הבאנר, אחרי ההודעה: כפתורי פעולה או רמז מקשים.
  final Widget? trailing;

  /// כשנתון, כל הבאנר לחיץ וניתן לפוקוס מקלדת.
  final VoidCallback? onTap;
  final FocusNode? focusNode;

  const AppInfoBanner({
    super.key,
    required this.message,
    this.title,
    this.icon,
    this.tone = AppInfoBannerTone.info,
    this.centerText = false,
    this.extraLines = const [],
    this.messageMaxLines,
    this.trailing,
    this.onTap,
    this.focusNode,
  }) : messageSpan = null;

  /// הודעה עם קטע מודגש או לחיץ: [message] הוא `TextSpan`.
  const AppInfoBanner.rich({
    super.key,
    required InlineSpan message,
    this.title,
    this.icon,
    this.tone = AppInfoBannerTone.info,
    this.centerText = false,
    this.messageMaxLines,
    this.trailing,
    this.onTap,
    this.focusNode,
  }) : messageSpan = message,
       message = '',
       extraLines = const [];

  static const double _iconSize = 18;

  /// רקע, טקסט ואייקון של כל טון.
  static ({Color background, Color foreground, Color icon}) colorsOf(
    BuildContext context,
    AppInfoBannerTone tone,
  ) {
    final cs = Theme.of(context).colorScheme;
    return switch (tone) {
      AppInfoBannerTone.info => (
        background: cs.surfaceContainerHighest,
        foreground: cs.onSurface,
        icon: cs.primary,
      ),
      AppInfoBannerTone.warning => (
        background: AppSurfaces.warningContainer(context),
        foreground: AppSurfaces.onWarningContainer(context),
        icon: AppSurfaces.warning(context),
      ),
      AppInfoBannerTone.error => (
        background: cs.errorContainer,
        foreground: cs.onErrorContainer,
        icon: cs.onErrorContainer,
      ),
      AppInfoBannerTone.success => (
        background: cs.secondaryContainer,
        foreground: cs.onSecondaryContainer,
        icon: cs.onSecondaryContainer,
      ),
      AppInfoBannerTone.tertiary => (
        background: cs.tertiaryContainer,
        foreground: cs.onTertiaryContainer,
        icon: cs.onTertiaryContainer,
      ),
    };
  }

  static IconData _defaultIcon(AppInfoBannerTone tone) => switch (tone) {
    AppInfoBannerTone.info => FluentIcons.info_24_regular,
    AppInfoBannerTone.warning => FluentIcons.warning_24_regular,
    AppInfoBannerTone.error => FluentIcons.error_circle_24_regular,
    AppInfoBannerTone.success => FluentIcons.checkmark_circle_24_regular,
    AppInfoBannerTone.tertiary => FluentIcons.info_24_regular,
  };

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context, tone);
    final textTheme = Theme.of(context).textTheme;
    final messageStyle = textTheme.bodyMedium?.copyWith(
      color: colors.foreground,
    );
    final textAlign = centerText ? TextAlign.center : null;
    final overflow = messageMaxLines == null ? null : TextOverflow.ellipsis;
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceSMD,
        vertical: AppTokens.spaceSM + AppTokens.space2XS,
      ),
      child: Row(
        crossAxisAlignment: trailing == null
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Icon(icon ?? _defaultIcon(tone), size: _iconSize, color: colors.icon),
          const SizedBox(width: AppTokens.spaceSM),
          Expanded(
            child: Column(
              crossAxisAlignment: centerText
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    textAlign: textAlign,
                    style: textTheme.titleSmall?.copyWith(
                      color: colors.foreground,
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceXS),
                ],
                if (messageSpan != null)
                  Text.rich(
                    messageSpan!,
                    textAlign: textAlign,
                    maxLines: messageMaxLines,
                    overflow: overflow,
                    style: messageStyle,
                  )
                else
                  Text(
                    message,
                    textAlign: textAlign,
                    maxLines: messageMaxLines,
                    overflow: overflow,
                    style: messageStyle,
                  ),
                for (final line in extraLines)
                  Text(line, textAlign: textAlign, style: messageStyle),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppTokens.spaceSM),
            trailing!,
          ],
        ],
      ),
    );
    // באנר לחיץ מצייר את הרקע ב-Material, כדי שאפקט הלחיצה והפוקוס יופיע מעליו.
    if (onTap != null) {
      return Material(
        color: colors.background,
        borderRadius: AppTokens.borderRadiusAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, focusNode: focusNode, child: content),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: content,
    );
  }
}
