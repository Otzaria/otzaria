import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/work_status/work_status_item.dart';
import 'package:otzaria/theme/app_shadows.dart';

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
        // עבודה יחידה נשארת בתצוגה המלאה; כמה עבודות מוצגות בשורות אחידות.
        final isSingle = items.length == 1;

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
                  boxShadow: AppShadows.floating(colorScheme),
                ),
                child: Stack(
                  children: [
                    Padding(
                      // בשורות האחידות המרווח בצד כפתור הסגירה מוגדל כדי שלא יכסה את החץ.
                      padding: isSingle
                          ? const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            )
                          : EdgeInsets.fromLTRB(
                              closeOnRight ? 16 : 32,
                              12,
                              closeOnRight ? 32 : 16,
                              12,
                            ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 380),
                        child: isSingle
                            ? _PrimaryItemRow(item: items.single)
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final (index, item)
                                      in items.indexed) ...[
                                    if (index > 0)
                                      Divider(
                                        height: 13,
                                        color:
                                            colorScheme.surfaceContainerHighest,
                                      ),
                                    _WorkItemRow(
                                      key: ValueKey(item.id),
                                      item: item,
                                    ),
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
        : '${(progress * 100).floor()}%';

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
                : item.kind == WorkStatusKind.awaitingInput
                ? Icon(
                    FluentIcons.question_circle_24_regular,
                    size: 44,
                    color: colorScheme.primary,
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
                if (item.actions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    children: [
                      for (final action in item.actions)
                        _ItemActionButton(action: action),
                    ],
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

/// שורת עבודה אחידה: כותרת, הודעה ומד התקדמות; פירוט ופעולות בהרחבה.
class _WorkItemRow extends StatefulWidget {
  const _WorkItemRow({super.key, required this.item});
  final WorkStatusItem item;

  @override
  State<_WorkItemRow> createState() => _WorkItemRowState();
}

class _WorkItemRowState extends State<_WorkItemRow> {
  late bool _expanded = _expandedByDefault(widget.item);

  // בפריט שנכשל או ממתין להחלטה, ההנחיה והלחצנים הם עיקר החיווי.
  static bool _expandedByDefault(WorkStatusItem item) =>
      item.kind != WorkStatusKind.running;

  @override
  void didUpdateWidget(_WorkItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.kind != widget.item.kind) {
      _expanded = _expandedByDefault(widget.item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isRunning = item.kind == WorkStatusKind.running;
    final progress = item.progress?.clamp(0.0, 1.0).toDouble();
    final canExpand = item.detail != null || item.actions.isNotEmpty;

    return InkWell(
      onTap: item.onTap,
      borderRadius: AppTokens.borderRadiusAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (item.kind == WorkStatusKind.failed)
                  _LeadingIcon(
                    icon: FluentIcons.error_circle_24_regular,
                    color: colorScheme.error,
                  )
                else if (item.kind == WorkStatusKind.awaitingInput)
                  _LeadingIcon(
                    icon: FluentIcons.question_circle_24_regular,
                    color: colorScheme.primary,
                  ),
                Expanded(
                  child: Text(
                    item.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isRunning && progress != null)
                  Text(
                    '${(progress * 100).floor()}%',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                if (canExpand)
                  IconButton(
                    icon: Icon(
                      _expanded
                          ? FluentIcons.chevron_up_24_regular
                          : FluentIcons.chevron_down_24_regular,
                      size: 16,
                    ),
                    color: colorScheme.onSurfaceVariant,
                    tooltip: _expanded ? 'כווץ' : 'הרחב',
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() => _expanded = !_expanded),
                  )
                else
                  // שומר את מקום החץ כדי שהאחוזים יתיישרו בין השורות.
                  const SizedBox(width: 24),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              item.message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: _expanded ? null : 1,
              overflow: _expanded ? null : TextOverflow.ellipsis,
            ),
            if (isRunning) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: colorScheme.surfaceContainerHighest,
                borderRadius: AppTokens.borderRadiusAll,
              ),
            ],
            if (_expanded && item.detail != null) ...[
              const SizedBox(height: 6),
              Text(
                item.detail!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (_expanded && item.actions.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                children: [
                  for (final action in item.actions)
                    _ItemActionButton(action: action),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Icon(icon, size: AppTokens.iconSM, color: color),
    );
  }
}

class _ItemActionButton extends StatelessWidget {
  const _ItemActionButton({required this.action});
  final WorkStatusAction action;

  @override
  Widget build(BuildContext context) {
    final button = action.emphasized
        ? ActionButton.neutral(
            text: action.label,
            icon: action.icon,
            onPressed: action.onPressed,
          )
        : ActionButton.ghost(
            text: action.label,
            icon: action.icon,
            onPressed: action.onPressed,
          );
    final tooltip = action.tooltip;
    if (tooltip == null) return button;
    return Tooltip(message: tooltip, child: button);
  }
}
