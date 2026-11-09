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
}

/// באנר הודעה בתוך המסך: אייקון, כותרת אופציונלית והודעה, על רקע הטון.
class AppInfoBanner extends StatelessWidget {
  final String message;
  final String? title;

  /// בלעדיו — אייקון ברירת המחדל של הטון.
  final IconData? icon;
  final AppInfoBannerTone tone;

  const AppInfoBanner({
    super.key,
    required this.message,
    this.title,
    this.icon,
    this.tone = AppInfoBannerTone.info,
  });

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
    };
  }

  static IconData _defaultIcon(AppInfoBannerTone tone) => switch (tone) {
    AppInfoBannerTone.info => FluentIcons.info_24_regular,
    AppInfoBannerTone.warning => FluentIcons.warning_24_regular,
    AppInfoBannerTone.error => FluentIcons.error_circle_24_regular,
    AppInfoBannerTone.success => FluentIcons.checkmark_circle_24_regular,
  };

  @override
  Widget build(BuildContext context) {
    final colors = colorsOf(context, tone);
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceSMD,
          vertical: AppTokens.spaceSM + AppTokens.space2XS,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon ?? _defaultIcon(tone),
              size: _iconSize,
              color: colors.icon,
            ),
            const SizedBox(width: AppTokens.spaceSM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(
                      title!,
                      style: textTheme.titleSmall?.copyWith(
                        color: colors.foreground,
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceXS),
                  ],
                  Text(
                    message,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.foreground,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
