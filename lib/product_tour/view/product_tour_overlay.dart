import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/product_tour/bloc/product_tour_state.dart';
import 'package:otzaria/product_tour/data/product_tour_specs.dart';
import 'package:otzaria/product_tour/models/product_tour_models.dart';
import 'package:otzaria/product_tour/services/product_tour_registry.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

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
    final cardWidth = math.min(420.0, mediaSize.width - 32);
    final cardLeft = _resolveHorizontalOffset(
      viewportWidth: mediaSize.width,
      targetRect: targetRect,
    );
    final cardTop = _resolveVerticalOffset(
      viewportHeight: mediaSize.height,
      targetRect: targetRect,
    );
    final isLastStep = state.activeIntroStepIndex == kIntroTourSteps.length - 1;

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
                          blurRadius: 16,
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
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: cardWidth,
                ),
                child: Card(
                  elevation: 12,
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'שלב ${state.activeIntroStepIndex! + 1} מתוך ${kIntroTourSteps.length}',
                                textDirection: TextDirection.rtl,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ),
                            IconButton(
                              onPressed: onDismiss,
                              icon: const Icon(
                                FluentIcons.dismiss_24_regular,
                              ),
                              tooltip: 'סגור',
                            ),
                          ],
                        ),
                        Text(
                          step.title,
                          textDirection: TextDirection.rtl,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          step.description,
                          textDirection: TextDirection.rtl,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            if (state.activeIntroStepIndex! > 0)
                              Expanded(
                                child: NeutralActionButton(
                                  text: 'חזור',
                                  onPressed: onPrevious,
                                ),
                              ),
                            if (state.activeIntroStepIndex! > 0)
                              const SizedBox(width: 12),
                            Expanded(
                              child: RecommendedActionButton(
                                text: isLastStep ? 'סיום' : 'הבא',
                                onPressed: isLastStep ? onFinish : onNext,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
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
                      child: RecommendedActionButton(
                        text: 'הבנתי',
                        onPressed: onDismiss,
                      ),
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
}) {
  final cardWidth = math.min(420.0, viewportWidth - 32);
  if (targetRect == null) {
    return math.max(16, (viewportWidth - cardWidth) / 2);
  }

  return ((targetRect.center.dx - (cardWidth / 2))
          .clamp(16.0, viewportWidth - cardWidth - 16))
      .toDouble();
}

double _resolveVerticalOffset({
  required double viewportHeight,
  required Rect? targetRect,
}) {
  const fallbackTop = 80.0;
  const cardHeightEstimate = 230.0;
  if (targetRect == null) {
    return fallbackTop;
  }

  final showAbove = targetRect.center.dy > (viewportHeight / 2);
  if (showAbove) {
    return math.max(16, targetRect.top - cardHeightEstimate - 16);
  }

  return math.min(
    viewportHeight - cardHeightEstimate - 16,
    targetRect.bottom + 16,
  );
}
