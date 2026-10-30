import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import '../models/book_model.dart';
import '../models/progress_model.dart';
import '../providers/shamor_zachor_progress_provider.dart';

class BookCardWidget extends StatefulWidget {
  static final Logger _logger = Logger('BookCardWidget');

  final String topLevelCategoryKey;
  final String categoryName;
  final String bookName;
  final BookDetails bookDetails;
  final VoidCallback? onDelete;
  final VoidCallback? onTap; // Override default navigation

  const BookCardWidget({
    super.key,
    required this.topLevelCategoryKey,
    required this.categoryName,
    required this.bookName,
    required this.bookDetails,
    this.onDelete,
    this.onTap,
  });

  @override
  State<BookCardWidget> createState() => _BookCardWidgetState();
}

class _BookCardWidgetState extends State<BookCardWidget> {
  static final Logger _logger = BookCardWidget._logger;
  final FocusNode _focusNode = FocusNode();

  List<ProgressColumn> _columns = kDefaultProgressColumns;
  double _learnProgress = 0.0;
  bool _isCompleted = false;
  List<double> _cycleProgress = const [];
  bool _isInitialized = false;

  ShamorZachorProgressProvider? _progressProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newProvider = context.read<ShamorZachorProgressProvider>();
    if (_progressProvider != newProvider) {
      _progressProvider?.removeListener(_recomputeFromProvider);
      _progressProvider = newProvider;
      _progressProvider?.addListener(_recomputeFromProvider);

      if (!_isInitialized) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _recomputeFromProvider();
            setState(() {
              _isInitialized = true;
            });
          }
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant BookCardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.topLevelCategoryKey != widget.topLevelCategoryKey ||
        oldWidget.bookName != widget.bookName ||
        oldWidget.bookDetails != widget.bookDetails) {
      _recomputeFromProvider();
    }
  }

  @override
  void dispose() {
    _progressProvider?.removeListener(_recomputeFromProvider);
    _focusNode.dispose();
    super.dispose();
  }

  void _recomputeFromProvider() {
    if (!mounted || _progressProvider == null) return;

    try {
      final pp = _progressProvider!;

      final double newLearnProgress;
      final bool newIsCompleted;

      final bookId = widget.bookDetails.id;
      if (bookId == null) {
        return;
      }

      final columns = pp.getColumnsForBook(bookId);
      final cycleTotals = List<int>.filled(columns.length, 0);
      final cycleCompleted = List<int>.filled(columns.length, 0);

      for (final item in widget.bookDetails.learnableItems) {
        final progress = pp.getProgressForItemById(
          bookId,
          item.absoluteIndex,
        );

        for (int index = 0; index < columns.length; index++) {
          cycleTotals[index]++;
          if (progress.getProperty(columns[index].id)) {
            cycleCompleted[index]++;
          }
        }
      }

      final newCycleProgress = List<double>.generate(
        columns.length,
        (index) => cycleTotals[index] == 0
            ? 0.0
            : cycleCompleted[index] / cycleTotals[index],
        growable: false,
      );

      newLearnProgress = pp
          .getLearnProgressPercentageById(
            bookId,
            widget.bookDetails,
          )
          .clamp(0.0, 1.0);

      newIsCompleted = pp.isBookCompletedById(
        bookId,
        widget.bookDetails,
      );

      if (newLearnProgress != _learnProgress ||
          newIsCompleted != _isCompleted ||
          !_sameProgress(_cycleProgress, newCycleProgress) ||
          !_sameColumns(_columns, columns)) {
        setState(() {
          _columns = columns;
          _learnProgress = newLearnProgress;
          _isCompleted = newIsCompleted;
          _cycleProgress = newCycleProgress;
        });
      }
    } catch (e, st) {
      _logger.severe('Recompute failed for book: ${widget.bookName}', e, st);
    }
  }

  bool _sameProgress(List<double> left, List<double> right) {
    if (left.length != right.length) {
      return false;
    }

    for (int index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }

    return true;
  }

  bool _sameColumns(List<ProgressColumn> left, List<ProgressColumn> right) {
    if (left.length != right.length) return false;
    for (int index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const AppCard(
        child: LoadingIndicator(size: 24, strokeWidth: 2),
      );
    }

    return FocusableActionDetector(
      focusNode: _focusNode,
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _onCardTap(context);
            return null;
          },
        ),
      },
      child: AppCard(
        margin: const EdgeInsets.symmetric(vertical: 4),
        onTap: () => _onCardTap(context),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.bookName,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _BookMetaChip(
                                icon: FluentIcons.folder_24_regular,
                                text:
                                    widget.bookDetails.categoryPath ??
                                    widget.categoryName,
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.secondaryContainer,
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.onSecondaryContainer,
                              ),
                              if (_isCompleted)
                                _BookMetaChip(
                                  icon: FluentIcons.checkmark_circle_24_regular,
                                  text: 'הושלם',
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  foregroundColor: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (widget.onDelete != null) ...[
                      const SizedBox(width: 8),
                      BarButton.icon(
                        tooltip: 'הסר ספר',
                        icon: FluentIcons.delete_24_regular,
                        onPressed: widget.onDelete!,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                // Progress / Completion info - מחזורים מרובים
                _buildCyclesProgressInfo(context),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onCardTap(BuildContext context) {
    if (widget.onTap != null) {
      widget.onTap!();
      return;
    }
    Navigator.of(context).pushNamed(
      '/book_detail',
      arguments: {
        'topLevelCategoryKey': widget.topLevelCategoryKey,
        'bookName': widget.bookName,
      },
    );
  }

  /// טבעת לכל מחזור שהתחיל, או שהמחזור שלפניו הושלם, ומתחתיה פירוט המחזור
  /// הנוכחי. הטבעות חולקות את הרוחב שווה בשווה, כך שגם ארבעה מחזורים נכנסים
  /// בכרטיס צר.
  Widget _buildCyclesProgressInfo(BuildContext context) {
    if (_progressProvider == null) {
      return _buildProgressInfo(context, 0.0);
    }

    final visibleIndices = [
      for (int i = 0; i < _cycleProgress.length; i++)
        if (i == 0 || _cycleProgress[i] > 0.0 || _cycleProgress[i - 1] >= 1.0)
          i,
    ];
    final currentIndex = visibleIndices.cast<int?>().lastWhere(
      (i) => _cycleProgress[i!] < 1.0,
      orElse: () => null,
    );

    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final index in visibleIndices)
              Expanded(
                child: _CycleRing(
                  label: index < _columns.length
                      ? _columns[index].label
                      : 'מחזור ${index + 1}',
                  progress: _cycleProgress[index],
                ),
              ),
          ],
        ),
        if (currentIndex != null) ...[
          const SizedBox(height: AppTokens.spaceSM),
          Text(
            '${(_cycleProgress[currentIndex] * widget.bookDetails.totalLearnableItems).round()}'
            ' מתוך ${widget.bookDetails.totalLearnableItems}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppTokens.fontSM,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildProgressInfo(BuildContext context, double learnProgress) {
    final totalItems = widget.bookDetails.totalLearnableItems;
    final completedItems = (learnProgress * totalItems).round();
    final progressPercentage = (learnProgress * 100).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: AppTokens.borderRadiusAll,
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: learnProgress.isFinite ? learnProgress : 0.0,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.08),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$progressPercentage%',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Flexible(
              child: Text(
                '$completedItems מתוך $totalItems',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            if (learnProgress > 0)
              Flexible(
                child: Text(
                  _getProgressStatusText(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _getProgressStatusText() {
    try {
      final pp = _progressProvider;
      final bookId = widget.bookDetails.id;
      if (pp == null || bookId == null) {
        return 'לימוד פעיל';
      }
      final summary = pp.getBookProgressSummarySyncById(
        bookId,
        widget.topLevelCategoryKey,
        widget.bookName,
        widget.bookDetails,
      );
      return summary.statusText;
    } catch (e, st) {
      _logger.warning('getBookProgressSummarySyncById failed', e, st);
      return 'לימוד פעיל';
    }
  }
}

/// צ'יפ מטא-דאטה לכרטיס ספר
class _BookMetaChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color backgroundColor;
  final Color foregroundColor;

  const _BookMetaChip({
    required this.icon,
    required this.text,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foregroundColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: AppTokens.fontSM,
                color: foregroundColor,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// טבעת התקדמות למחזור: אחוז בתוך הטבעת, או וי כשהמחזור הושלם, ושמו מתחתיה.
class _CycleRing extends StatelessWidget {
  final String label;
  final double progress;

  const _CycleRing({required this.label, required this.progress});

  static const double _size = 38;

  /// מתחת לרוחב הזה שם מחזור שהושלם אינו מוצג מתחת לטבעת, כדי שארבע
  /// טבעות יישארו קריאות בכרטיס צר; השם נשאר בטולטיפ.
  static const double _labelMinWidth = 52;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final completed = progress >= 1.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth < _size + 4
            ? constraints.maxWidth - 4
            : _size;
        final showLabel = !completed || constraints.maxWidth >= _labelMinWidth;
        return Tooltip(
          message: label,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: size,
                height: size,
                child: completed
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          FluentIcons.checkmark_24_regular,
                          size: 20,
                          color: cs.onPrimaryContainer,
                        ),
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 4,
                            backgroundColor: cs.onSurface.withValues(
                              alpha: 0.08,
                            ),
                          ),
                          Center(
                            child: Text(
                              '${(progress * 100).round()}%',
                              style: TextStyle(
                                fontSize: AppTokens.fontSM - 2,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              if (showLabel) ...[
                const SizedBox(height: AppTokens.spaceXS),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: AppTokens.fontSM,
                      color: completed ? cs.onSurfaceVariant : cs.onSurface,
                      fontWeight: completed
                          ? FontWeight.normal
                          : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
