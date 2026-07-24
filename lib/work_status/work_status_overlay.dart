import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/work_status/work_status_item.dart';

class WorkStatusOverlay extends StatelessWidget {
  const WorkStatusOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WorkStatusCubit, WorkStatusState>(
      builder: (context, state) {
        if (!state.hasActiveItems || state.isDismissed) {
          return const SizedBox.shrink();
        }

        final items = state.orderedItems;
        final colorScheme = Theme.of(context).colorScheme;
        final isWindows = Theme.of(context).platform == TargetPlatform.windows;
        final alignment = isWindows
            ? Alignment.bottomLeft
            : Alignment.bottomRight;
        final padding = isWindows
            ? const EdgeInsets.only(bottom: 24, left: 16)
            : const EdgeInsets.only(bottom: 24, right: 16);
        final closeOnRight = alignment == Alignment.topRight;

        return Align(
          alignment: alignment,
          child: Padding(
            padding: padding,
            child: Material(
              color: Colors.transparent,
              borderRadius: AppTokens.borderRadiusAll,
              clipBehavior: Clip.antiAlias,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.96),
                  borderRadius: AppTokens.borderRadiusAll,
                  border: Border.all(color: colorScheme.outlineVariant),
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
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _PrimaryItemRow(item: items.first),
                            if (items.length > 1) ...[
                              const SizedBox(height: 10),
                              Divider(
                                height: 1,
                                color: colorScheme.surfaceContainerHighest,
                              ),
                              const SizedBox(height: 8),
                              for (final item in items.skip(1))
                                _SecondaryItemRow(item: item),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: closeOnRight ? 8 : null,
                      left: closeOnRight ? null : 8,
                      child: IconButton(
                        icon: const Icon(
                          FluentIcons.dismiss_24_regular,
                          size: 16,
                        ),
                        color: colorScheme.onSurfaceVariant,
                        tooltip: 'סגור',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () =>
                            context.read<WorkStatusCubit>().dismiss(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PrimaryItemRow extends StatelessWidget {
  const _PrimaryItemRow({required this.item});
  final WorkStatusItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = item.progress?.clamp(0.0, 1.0).toDouble();
    final percentLabel = progress == null
        ? '...'
        : '${(progress * 100).round()}%';

    return InkWell(
      onTap: item.onTap,
      borderRadius: AppTokens.borderRadiusAll,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        textDirection: TextDirection.ltr,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: item.kind == WorkStatusKind.failed
                ? Icon(
                    FluentIcons.error_circle_24_regular,
                    size: 44,
                    color: colorScheme.error,
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 6,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                        ),
                      ),
                      Text(
                        percentLabel,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
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
                  item.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.25,
                  ),
                ),
                if (item.detail != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.detail!,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondaryItemRow extends StatelessWidget {
  const _SecondaryItemRow({required this.item});
  final WorkStatusItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = item.progress?.clamp(0.0, 1.0).toDouble();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: AppTokens.borderRadiusAll,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: item.kind == WorkStatusKind.failed
                  ? Icon(
                      FluentIcons.error_circle_24_regular,
                      size: 18,
                      color: colorScheme.error,
                    )
                  : CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 3,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '${item.title}: ${item.message}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
