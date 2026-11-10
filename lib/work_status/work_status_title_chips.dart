import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/theme/layout_tokens.dart';
import 'package:otzaria/widgets/controls/status_chip.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';
import 'package:otzaria/work_status/work_status_cubit.dart';
import 'package:otzaria/work_status/work_status_item.dart';

/// גלולת שורת הכותרת לכל עבודה שהכרטיס שלה מצומצם
/// ([WorkStatusState.collapsedItems]); לחיצה פותחת את הכרטיס מחדש.
///
/// בחלון צר ([WindowClass.isCompact]) אין מקום בשורה, ולכן אין גלולות:
/// [WorkStatusOverlay.showCollapsed] מציג שם את הפריט בכרטיס.
class WorkStatusTitleChips extends StatelessWidget {
  const WorkStatusTitleChips({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WorkStatusCubit, WorkStatusState>(
      buildWhen: (previous, current) =>
          !listEquals(previous.collapsedItems, current.collapsedItems),
      builder: (context, state) {
        final items = state.collapsedItems;
        if (items.isEmpty || WindowClass.of(context).isCompact) {
          return const SizedBox.shrink();
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  end: AppTokens.spaceSM,
                ),
                child: _WorkStatusChip(key: ValueKey(item.id), item: item),
              ),
          ],
        );
      },
    );
  }
}

class _WorkStatusChip extends StatelessWidget {
  const _WorkStatusChip({super.key, required this.item});

  final WorkStatusItem item;

  @override
  Widget build(BuildContext context) {
    final onContainer = Theme.of(context).colorScheme.onPrimaryContainer;
    final progress = item.progress?.clamp(0.0, 1.0).toDouble();
    final running = item.kind == WorkStatusKind.running;
    final (icon, tone, status) = switch (item.kind) {
      WorkStatusKind.failed => (
        const Icon(FluentIcons.error_circle_24_regular),
        StatusChipTone.error,
        'נכשל',
      ),
      WorkStatusKind.awaitingInput => (
        const Icon(FluentIcons.question_circle_24_regular),
        StatusChipTone.primary,
        'ממתין',
      ),
      _ => (
        LoadingIndicator.inline(color: onContainer, value: progress),
        StatusChipTone.primary,
        progress == null ? null : '${(progress * 100).floor()}%',
      ),
    };
    final name = item.chipLabel!;
    final label = status == null
        ? name
        : '$name${running ? ' ' : ' · '}$status';
    return StatusChip(
      tone: tone,
      icon: icon,
      label: label,
      tooltip: '${item.title}: ${item.message}. לחץ להצגת הכרטיס',
      onPressed: () => context.read<WorkStatusCubit>().expand(item.id),
    );
  }
}
