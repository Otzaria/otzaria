// לתחזוקת כרטיסי הסיור המודרך ראו: docs/guided_tour_developer_guide.md

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/tour/models/tour_shortcuts.dart';
import 'package:otzaria/tour/models/tour_step.dart';
import 'package:otzaria/tour/widgets/tour_progress_dots.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

class TourTooltipCard extends StatelessWidget {
  /// הטקסט העברי, שהוא גם מפתח התרגום.
  final String title;
  final String body;
  final TourShortcutHint shortcut;
  final int currentIndex;
  final int totalSteps;
  final bool isLastStep;
  final bool isWelcomeStep;
  final bool isRestartEntry;
  final bool isAutoPlaying;
  final bool isDialog;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback onToggleAutoPlay;
  final ValueChanged<int>? onDotTap;

  const TourTooltipCard({
    super.key,
    required this.title,
    required this.body,
    this.shortcut = TourShortcutHint.none,
    required this.currentIndex,
    required this.totalSteps,
    required this.isLastStep,
    required this.isWelcomeStep,
    this.isRestartEntry = false,
    this.isAutoPlaying = false,
    this.isDialog = false,
    required this.onNext,
    required this.onSkip,
    required this.onToggleAutoPlay,
    this.onDotTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final shortcutText = tourShortcutText(context, shortcut);

    return Material(
      color: colorScheme.secondaryContainer,
      elevation: 18,
      shape: RoundedRectangleBorder(
        borderRadius: AppTokens.borderRadiusAll,
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.85),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430, minWidth: 300),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withValues(alpha: 0.28),
                      borderRadius: AppTokens.borderRadiusAll,
                    ),
                    child: Icon(
                      isLastStep
                          ? FluentIcons.checkmark_circle_24_regular
                          : FluentIcons.sparkle_24_regular,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.settingsText(title),
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                context.settingsText(
                  body,
                  args: shortcutText == null
                      ? null
                      : {'shortcut': shortcutText},
                ),
                style: textTheme.bodyLarge?.copyWith(
                  height: 1.45,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 18),
              if (currentIndex >= 0)
                TourProgressDots(
                  currentIndex: currentIndex,
                  total: totalSteps,
                  onDotTap: onDotTap,
                ),
              const SizedBox(height: 18),
              Row(
                children: [
                  if (!isLastStep)
                    ActionButton.neutral(
                      icon: FluentIcons.dismiss_24_regular,
                      text: context.settingsText(
                        isRestartEntry
                            ? 'ביטול'
                            : isWelcomeStep
                            ? 'דלג — אגלה לבד'
                            : 'דלג על הסיור',
                      ),
                      onPressed: onSkip,
                    )
                  else
                    const SizedBox.shrink(),
                  const Spacer(),
                  if (!isLastStep && !isWelcomeStep && !isRestartEntry) ...[
                    Tooltip(
                      message: context.settingsText(
                        isAutoPlaying
                            ? 'עצור הצגה אוטומטית'
                            : 'הצגה אוטומטית — מעבר אוטומטי בין השלבים כל 4 שניות',
                      ),
                      child: FilledButton.tonal(
                        onPressed: onToggleAutoPlay,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          padding: EdgeInsets.zero,
                        ),
                        child: Icon(
                          isAutoPlaying
                              ? FluentIcons.pause_circle_24_regular
                              : FluentIcons.play_circle_24_regular,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  _TourNextButton(
                    icon: isLastStep
                        ? FluentIcons.checkmark_24_regular
                        : FluentIcons.arrow_left_24_regular,
                    text: context.settingsText(
                      isLastStep
                          ? 'סגור'
                          : isRestartEntry
                          ? 'אני מוכן'
                          : isWelcomeStep
                          ? 'בוא נתחיל'
                          : 'הבא',
                    ),
                    onPressed: onNext,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TourNextButton extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onPressed;

  const _TourNextButton({
    required this.icon,
    required this.text,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
          ),
          const SizedBox(width: 8),
          RtlIcon(icon),
        ],
      ),
    );
  }
}
