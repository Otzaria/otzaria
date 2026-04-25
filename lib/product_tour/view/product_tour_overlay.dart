import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/product_tour/bloc/product_tour_state.dart';
import 'package:otzaria/product_tour/data/product_tour_specs.dart';
import 'package:otzaria/product_tour/models/product_tour_models.dart';
import 'package:otzaria/product_tour/services/product_tour_registry.dart';

/// שכבת ה-UI של הסיור הראשי והטיפים החיים.
class ProductTourOverlay extends StatelessWidget {
  final ProductTourState state;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onDismiss;
  final VoidCallback onFinish;

  const ProductTourOverlay({
    super.key,
    required this.state,
    required this.onNext,
    required this.onPrevious,
    required this.onDismiss,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    if (!state.hasActiveOverlay) {
      return const SizedBox.shrink();
    }

    if (state.hasActiveIntroTour) {
      return _IntroTourOverlay(
        state: state,
        onNext: onNext,
        onPrevious: onPrevious,
        onDismiss: onDismiss,
        onFinish: onFinish,
      );
    }

    return _LiveTipOverlay(
      tip: liveTipSpecById(state.activeLiveTipId!),
      onDismiss: onDismiss,
    );
  }
}

class _IntroTourOverlay extends StatelessWidget {
  final ProductTourState state;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onDismiss;
  final VoidCallback onFinish;

  const _IntroTourOverlay({
    required this.state,
    required this.onNext,
    required this.onPrevious,
    required this.onDismiss,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final step = kIntroTourSteps[state.activeIntroStepIndex!];
    final targetRect = ProductTourRegistry.instance.rectFor(step.targetId);
    final mediaSize = MediaQuery.sizeOf(context);
    final cardWidth = math.min(360.0, mediaSize.width - 24);
    final cardLeft = _resolveHorizontalOffset(
      viewportWidth: mediaSize.width,
      targetRect: targetRect,
      cardWidth: cardWidth,
    );
    final cardTop = _resolveVerticalOffset(
      viewportHeight: mediaSize.height,
      targetRect: targetRect,
      cardHeightEstimate: step.tip == null ? 228.0 : 284.0,
    );

    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: CustomPaint(
                  painter: _BackdropPainter(
                    color: Theme.of(context)
                        .colorScheme
                        .scrim
                        .withValues(alpha: 0.68),
                    targetRect: targetRect,
                  ),
                ),
              ),
            ),
            if (targetRect != null)
              Positioned.fromRect(
                rect: targetRect.inflate(8),
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.18),
                          blurRadius: 18,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              left: cardLeft,
              top: cardTop,
              child: SizedBox(
                width: cardWidth,
                child: _IntroTourCard(
                  step: step,
                  stepIndex: state.activeIntroStepIndex!,
                  totalSteps: kIntroTourSteps.length,
                  onNext: onNext,
                  onPrevious: onPrevious,
                  onFinish: onFinish,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroTourCard extends StatelessWidget {
  final TourStepSpec step;
  final int stepIndex;
  final int totalSteps;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onFinish;

  const _IntroTourCard({
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.onNext,
    required this.onPrevious,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isFirstStep = stepIndex == 0;
    final isLastStep = stepIndex == totalSteps - 1;

    return Material(
      color: colorScheme.secondaryContainer,
      elevation: 18,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(22),
        topRight: Radius.circular(22),
        bottomLeft: Radius.circular(22),
        bottomRight: Radius.circular(8),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(22),
            topRight: Radius.circular(22),
            bottomLeft: Radius.circular(22),
            bottomRight: Radius.circular(8),
          ),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.85),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    FluentIcons.info_24_regular,
                    size: 18,
                    color: colorScheme.onSecondaryContainer,
                  ),
                  const Spacer(),
                  _CornerFinishButton(
                    onTap: onFinish,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                step.title,
                textDirection: TextDirection.rtl,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSecondaryContainer,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                step.description,
                textDirection: TextDirection.rtl,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                      height: 1.35,
                    ),
              ),
              if (step.tip != null) ...[
                const SizedBox(height: 12),
                _StepTipBanner(text: step.tip!),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  _ArrowNavButton(
                    icon: FluentIcons.chevron_left_24_regular,
                    tooltip: 'הקודם',
                    enabled: !isFirstStep,
                    onTap: onPrevious,
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${stepIndex + 1}/$totalSteps',
                        textDirection: TextDirection.ltr,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                  _ArrowNavButton(
                    icon: isLastStep
                        ? FluentIcons.checkmark_24_regular
                        : FluentIcons.chevron_right_24_regular,
                    tooltip: isLastStep ? 'סיום' : 'הבא',
                    enabled: true,
                    onTap: isLastStep ? onFinish : onNext,
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

class _CornerFinishButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CornerFinishButton({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surface.withValues(alpha: 0.24),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            'סיום',
            textDirection: TextDirection.rtl,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ),
    );
  }
}

class _StepTipBanner extends StatelessWidget {
  final String text;

  const _StepTipBanner({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'טיפ',
              textDirection: TextDirection.rtl,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.tertiary,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              text,
              textDirection: TextDirection.rtl,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                    height: 1.3,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArrowNavButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  const _ArrowNavButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor = enabled
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.5);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: enabled
            ? colorScheme.surface.withValues(alpha: 0.28)
            : colorScheme.surface.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(
              icon,
              size: 18,
              color: foregroundColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveTipOverlay extends StatelessWidget {
  final LiveTipSpec tip;
  final VoidCallback onDismiss;

  const _LiveTipOverlay({
    required this.tip,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final targetRect = ProductTourRegistry.instance.rectFor(tip.targetId);
    final mediaSize = MediaQuery.sizeOf(context);
    final cardWidth = math.min(360.0, mediaSize.width - 32);
    final left = targetRect == null
        ? mediaSize.width - cardWidth - 16
        : ((targetRect.right - cardWidth)
                .clamp(16.0, mediaSize.width - cardWidth - 16))
            .toDouble();
    final top = targetRect == null
        ? 88.0
        : ((targetRect.bottom + 12).clamp(16.0, mediaSize.height - 180))
            .toDouble();

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: Material(
              elevation: 10,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: cardWidth,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.8),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tip.title,
                            textDirection: TextDirection.rtl,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                        IconButton(
                          onPressed: onDismiss,
                          icon: const Icon(FluentIcons.dismiss_24_regular),
                          tooltip: 'סגור',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tip.description,
                      textDirection: TextDirection.rtl,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: _CornerFinishButton(onTap: onDismiss),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  final Color color;
  final Rect? targetRect;

  const _BackdropPainter({
    required this.color,
    required this.targetRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()..addRect(Offset.zero & size);

    if (targetRect != null) {
      path.fillType = PathFillType.evenOdd;
      path.addRRect(
        RRect.fromRectAndRadius(
          targetRect!.inflate(10),
          const Radius.circular(18),
        ),
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.targetRect != targetRect;
  }
}

double _resolveHorizontalOffset({
  required double viewportWidth,
  required Rect? targetRect,
  required double cardWidth,
}) {
  if (targetRect == null) {
    return math.max(12.0, (viewportWidth - cardWidth) / 2);
  }

  return ((targetRect.center.dx - (cardWidth / 2))
          .clamp(12.0, viewportWidth - cardWidth - 12.0))
      .toDouble();
}

double _resolveVerticalOffset({
  required double viewportHeight,
  required Rect? targetRect,
  required double cardHeightEstimate,
}) {
  const fallbackTop = 76.0;
  if (targetRect == null) {
    return fallbackTop;
  }

  final showAbove = targetRect.center.dy > (viewportHeight / 2);
  if (showAbove) {
    return math.max(16.0, targetRect.top - cardHeightEstimate - 16.0);
  }

  return math.min(
    viewportHeight - cardHeightEstimate - 16.0,
    targetRect.bottom + 16.0,
  );
}
