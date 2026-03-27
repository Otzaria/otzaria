import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';

class IndexingStatusOverlay extends StatefulWidget {
  const IndexingStatusOverlay({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  State<IndexingStatusOverlay> createState() => _IndexingStatusOverlayState();
}

class _IndexingStatusOverlayState extends State<IndexingStatusOverlay> {
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<IndexingBloc, IndexingState>(
      buildWhen: (previous, current) => previous != current,
      builder: (context, state) {
        final isIndexing = state is IndexingInProgress;
        final shouldShowOverlay = isIndexing && state.isCreatingIndex;

        if (!isIndexing && _hidden) {
          _hidden = false;
        }

        if (_hidden || !shouldShowOverlay) {
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
                          horizontal: 20,
                          vertical: 16,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 380),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            textDirection: TextDirection.ltr,
                            children: [
                              SizedBox(
                                width: 64,
                                height: 64,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox.expand(
                                      child: CircularProgressIndicator(
                                        value: progress,
                                        strokeWidth: 6,
                                        backgroundColor:
                                            colorScheme.surfaceContainerHighest,
                                      ),
                                    ),
                                    Text(
                                      percentLabel,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            color: colorScheme.onSurface,
                                            fontWeight: FontWeight.w700,
                                          ),
                                      textDirection: TextDirection.ltr,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
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
                                          .titleMedium
                                          ?.copyWith(
                                            color: colorScheme.onSurface,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'ייתכן איטיות בפעילות התוכנה',
                                      textDirection: TextDirection.rtl,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                            height: 1.25,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'התקדמות: $countLabel',
                                      textDirection: TextDirection.rtl,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
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
                      Positioned(
                        top: 8,
                        right: closeOnRight ? 8 : null,
                        left: closeOnRight ? null : 8,
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
