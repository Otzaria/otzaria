import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/widgets/layout/app_card.dart';
import '../models/book_model.dart';
import '../providers/shamor_zachor_progress_provider.dart';

class BookCardWidget extends StatefulWidget {
  static final Logger _logger = Logger('BookCardWidget');

  final String topLevelCategoryKey;
  final String categoryName;
  final String bookName;
  final BookDetails bookDetails;
  final bool isInCompletedListContext;
  final VoidCallback? onDelete;
  final VoidCallback? onTap; // Override default navigation

  const BookCardWidget({
    super.key,
    required this.topLevelCategoryKey,
    required this.categoryName,
    required this.bookName,
    required this.bookDetails,
    this.isInCompletedListContext = false,
    this.onDelete,
    this.onTap,
  });

  @override
  State<BookCardWidget> createState() => _BookCardWidgetState();
}

class _BookCardWidgetState extends State<BookCardWidget> {
  static final Logger _logger = BookCardWidget._logger;
  static const List<String> _cycles = [
    'learn',
    'review1',
    'review2',
    'review3',
  ];
  final FocusNode _focusNode = FocusNode();

  double _learnProgress = 0.0;
  bool _isCompleted = false;
  List<double> _cycleProgress = const [0.0, 0.0, 0.0, 0.0];
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
      final cycleTotals = List<int>.filled(_cycles.length, 0);
      final cycleCompleted = List<int>.filled(_cycles.length, 0);

      final bookId = widget.bookDetails.id;
      if (bookId == null) {
        return;
      }

      for (final item in widget.bookDetails.learnableItems) {
        final progress = pp.getProgressForItemById(
          bookId,
          item.absoluteIndex,
        );

        for (int index = 0; index < _cycles.length; index++) {
          cycleTotals[index]++;
          if (progress.getProperty(_cycles[index])) {
            cycleCompleted[index]++;
          }
        }
      }

      final newCycleProgress = List<double>.generate(
        _cycles.length,
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
          !_sameProgress(_cycleProgress, newCycleProgress)) {
        setState(() {
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

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Card(
          child: Center(
              child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.0))));
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
        radius: AppTokens.radiusMD,
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
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.rtl,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _BookMetaChip(
                                icon: FluentIcons.folder_24_regular,
                                text: widget.bookDetails.categoryPath ??
                                    widget.categoryName,
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer,
                                foregroundColor: Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer,
                              ),
                              if (_isCompleted)
                                _BookMetaChip(
                                  icon: FluentIcons.checkmark_circle_24_regular,
                                  text: 'הושלם',
                                  backgroundColor:
                                      Theme.of(context).colorScheme.primary,
                                  foregroundColor:
                                      Theme.of(context).colorScheme.onPrimary,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (widget.onDelete != null) ...[
                      const SizedBox(width: 8),
                      ToolbarActionButton(
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
        'categoryName': widget.categoryName,
        'bookName': widget.bookName,
      },
    );
  }

  /// בניית תצוגת מחזורים מרובים
  Widget _buildCyclesProgressInfo(BuildContext context) {
    if (_progressProvider == null) {
      return _buildProgressInfo(context, 0.0);
    }

    // בניית תצוגה - מציג מחזור אם הוא התחיל או אם המחזור הקודם הושלם
    final visibleIndices = [
      for (int i = 0; i < _cycleProgress.length; i++)
        if (i == 0 || _cycleProgress[i] > 0.0 || _cycleProgress[i - 1] >= 1.0)
          i,
    ];

    return Row(
      children: [
        for (int j = 0; j < visibleIndices.length; j++) ...[
          if (j > 0) const SizedBox(width: 4),
          Expanded(
            child: _buildCycleIndicator(
              context,
              visibleIndices[j] + 1,
              _cycleProgress[visibleIndices[j]],
              _cycleProgress[visibleIndices[j]] >= 1.0,
            ),
          ),
        ],
      ],
    );
  }

  /// בניית אינדיקטור למחזור בודד
  Widget _buildCycleIndicator(
    BuildContext context,
    int cycleNumber,
    double progress,
    bool isCompleted,
  ) {
    // המרת מספר מחזור לטקסט עברי
    String getCycleName(int num) {
      switch (num) {
        case 1:
          return 'מחזור ראשון';
        case 2:
          return 'מחזור שני';
        case 3:
          return 'מחזור שלישי';
        case 4:
          return 'מחזור רביעי';
        default:
          return 'מחזור $num';
      }
    }

    final cs = Theme.of(context).colorScheme;

    if (isCompleted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.checkmark_24_regular,
              color: cs.onSurface,
              size: 16,
            ),
            const SizedBox(height: 1),
            Text(
              getCycleName(cycleNumber),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 8,
                    color: cs.onSurface,
                  ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    final totalItems = widget.bookDetails.totalLearnableItems;
    final completedItems = (progress * totalItems).round();
    final progressPercentage = (progress * 100).round();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: cs.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            getCycleName(cycleNumber),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 9,
                ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 3,
              value: progress,
              backgroundColor: cs.onSurface.withValues(alpha: 0.08),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            '$progressPercentage% • $completedItems/$totalItems',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 8,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressInfo(BuildContext context, double learnProgress) {
    final totalItems = widget.bookDetails.totalLearnableItems;
    final completedItems = (learnProgress * totalItems).round();
    final progressPercentage = (learnProgress * 100).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: learnProgress.isFinite ? learnProgress : 0.0,
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.08),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('$progressPercentage%',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Flexible(
            child: Text('$completedItems מתוך $totalItems',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7)),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          if (learnProgress > 0)
            Flexible(
              child: Text(
                _getProgressStatusText(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ]),
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foregroundColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontSize: 11,
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
