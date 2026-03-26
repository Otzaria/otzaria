import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

class IndexingStatusOverlay extends StatefulWidget {
  const IndexingStatusOverlay({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  State<IndexingStatusOverlay> createState() => _IndexingStatusOverlayState();
}

class _IndexingStatusOverlayState extends State<IndexingStatusOverlay> {
  bool _hidden = false;
  bool _delayElapsed = false;
  Timer? _delayTimer;

  @override
  void dispose() {
    _delayTimer?.cancel();
    super.dispose();
  }

  void _startDelayTimer() {
    _delayTimer?.cancel();
    _delayElapsed = false;
    _delayTimer = Timer(const Duration(seconds: 13), () {
      if (mounted) {
        setState(() {
          _delayElapsed = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<IndexingBloc, IndexingState>(
      buildWhen: (previous, current) => previous != current,
      builder: (context, state) {
        final isIndexing = state is IndexingInProgress;

        // אם האינדוקס התחיל - הפעל טיימר
        if (isIndexing && _delayTimer == null) {
          _startDelayTimer();
        }

        // אם האינדוקס נגמר - אפס הכל
        if (!isIndexing) {
          _delayTimer?.cancel();
          _delayTimer = null;
          if (_hidden || _delayElapsed) {
            _hidden = false;
            _delayElapsed = false;
          }
        }

        if (_hidden || !isIndexing || !_delayElapsed) {
          return const SizedBox.shrink();
        }
        final processed = state.booksProcessed ?? 0;
        final total = state.totalBooks ?? 0;
        if (total == 0) {
          return const SizedBox.shrink();
        }

        final colorScheme = Theme.of(context).colorScheme;
        final hasKnownTotal = total > 0;
        final rawProgress = hasKnownTotal ? processed / total : null;
        final progress = rawProgress?.clamp(0.0, 1.0).toDouble();
        final percentLabel =
            progress == null ? '...' : '${(progress * 100).round()}%';
        final countLabel = hasKnownTotal ? '$processed/$total' : '$processed';

        final isRtl = Directionality.of(context) == TextDirection.rtl;
        final isWindows = Theme.of(context).platform == TargetPlatform.windows;
        final alignment = isWindows
            ? Alignment.bottomLeft
            : (isRtl ? Alignment.bottomRight : Alignment.bottomLeft);
        final padding = isWindows
            ? const EdgeInsets.only(bottom: 24, left: 16, right: 0)
            : EdgeInsets.only(
                bottom: 24,
                left: isRtl ? 0 : 16,
                right: isRtl ? 16 : 0,
              );
        // קובע את מיקום האיקס: תמיד באותו צד של החיווי
        final closeOnRight = alignment == Alignment.topRight;

        return Align(
          alignment: alignment,
          child: Padding(
            padding: padding,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: colorScheme.outlineVariant,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withValues(alpha: 0.12),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 330),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            textDirection: TextDirection.ltr,
                            children: [
                              SizedBox(
                                width: 54,
                                height: 54,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox.expand(
                                      child: CircularProgressIndicator(
                                        value: progress,
                                        strokeWidth: 5,
                                        backgroundColor:
                                            colorScheme.surfaceContainerHighest,
                                      ),
                                    ),
                                    Text(
                                      percentLabel,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: colorScheme.onSurface,
                                            fontWeight: FontWeight.w700,
                                          ),
                                      textDirection: TextDirection.ltr,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'התוכנה בתהליך אינדוקס',
                                      textDirection: TextDirection.rtl,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            color: colorScheme.onSurface,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'תיתכן איטיות בפעילות התוכנה',
                                      textDirection: TextDirection.rtl,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            height: 1.25,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'התקדמות: $countLabel',
                                      textDirection: TextDirection.rtl,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // כפתור סגירה
                      Positioned(
                        top: 2,
                        right: closeOnRight ? 2 : null,
                        left: closeOnRight ? null : 2,
                        child: IconButton(
                          icon: Icon(
                            FluentIcons.dismiss_24_regular,
                            size: 16,
                          ),
                          splashRadius: 14,
                          color: colorScheme.onSurfaceVariant,
                          tooltip: 'סגור',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            setState(() {
                              _hidden = true;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
