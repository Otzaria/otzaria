import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';
import '../models/book_model.dart';
import '../models/progress_model.dart';
import '../providers/shamor_zachor_progress_provider.dart';

class BookCardWidget extends StatefulWidget {
  static final Logger _logger = Logger('BookCardWidget');

  final String topLevelCategoryKey;
  final String categoryName;
  final String bookName;
  final BookDetails bookDetails;
  final Map<String, PageProgress> bookProgressData;
  final String? completionDate;
  final bool isInCompletedListContext;
  final VoidCallback? onDelete;
  final VoidCallback? onTap; // Override default navigation

  const BookCardWidget({
    super.key,
    required this.topLevelCategoryKey,
    required this.categoryName,
    required this.bookName,
    required this.bookDetails,
    required this.bookProgressData,
    this.completionDate,
    this.isInCompletedListContext = false,
    this.onDelete,
    this.onTap,
  });

  @override
  State<BookCardWidget> createState() => _BookCardWidgetState();
}

class _BookCardWidgetState extends State<BookCardWidget> {
  static final Logger _logger = BookCardWidget._logger;

  double _learnProgress = 0.0;
  bool _isCompleted = false;
  int _completedCycles = 0;
  bool _isInitialized = false;

  ShamorZachorProgressProvider? _progressProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newProvider = context.watch<ShamorZachorProgressProvider>();
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
  void dispose() {
    _progressProvider?.removeListener(_recomputeFromProvider);
    super.dispose();
  }

  void _recomputeFromProvider() {
    if (!mounted) return;

    try {
      final pp = _progressProvider!;

      // השתמש בפונקציות מבוססות ID אם יש ID, אחרת חזור לשיטה הישנה
      final double newLearnProgress;
      final bool newIsCompleted;
      final int newCompletedCycles;

      if (widget.bookDetails.id != null) {
        newLearnProgress = pp
            .getLearnProgressPercentageById(
              widget.bookDetails.id!,
              widget.bookDetails,
            )
            .clamp(0.0, 1.0);

        newIsCompleted = pp.isBookCompletedById(
          widget.bookDetails.id!,
          widget.bookDetails,
        );

        newCompletedCycles = pp.getNumberOfCompletedCyclesById(
          widget.bookDetails.id!,
          widget.bookDetails,
        );
      } else {
        // Fallback לשיטה הישנה
        newLearnProgress = pp
            .getLearnProgressPercentage(
              widget.topLevelCategoryKey,
              widget.bookName,
              widget.bookDetails,
            )
            .clamp(0.0, 1.0);

        newIsCompleted = pp.isBookCompleted(
          widget.topLevelCategoryKey,
          widget.bookName,
          widget.bookDetails,
        );

        newCompletedCycles = pp.getNumberOfCompletedCycles(
          widget.topLevelCategoryKey,
          widget.bookName,
          widget.bookDetails,
        );
      }

      if (newLearnProgress != _learnProgress ||
          newIsCompleted != _isCompleted ||
          newCompletedCycles != _completedCycles) {
        setState(() {
          _learnProgress = newLearnProgress;
          _isCompleted = newIsCompleted;
          _completedCycles = newCompletedCycles;
        });
      }
    } catch (e, st) {
      _logger.severe('Recompute failed for book: ${widget.bookName}', e, st);
    }
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

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
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
                                ?.copyWith(fontWeight: FontWeight.bold),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.bookDetails.categoryPath ??
                                widget.categoryName,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.7),
                                    ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (_isCompleted) ...[
                      const SizedBox(width: 8),
                      const Icon(FluentIcons.checkmark_circle_24_regular,
                          color: Colors.green, size: 24),
                    ],
                    if (widget.onDelete != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(FluentIcons.delete_24_regular),
                        tooltip: 'הסר ספר',
                        onPressed: widget.onDelete,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                // Progress / Completion info - מחזורים מרובים
                _buildCyclesProgressInfo(context),
                const SizedBox(height: 12),
                // Additional info
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

  /// בניית תצוגת מחזורים מרובים
  Widget _buildCyclesProgressInfo(BuildContext context) {
    if (_progressProvider == null) {
      return _buildProgressInfo(context, 0.0);
    }

    // חישוב התקדמות לכל מחזור
    final cycles = ['learn', 'review1', 'review2', 'review3'];
    final cycleProgress = <double>[];

    for (final cycle in cycles) {
      int completed = 0;
      int total = 0;
      for (final item in widget.bookDetails.learnableItems) {
        // השתמש בפונקציות מבוססות ID אם יש ID
        final PageProgress progress;
        if (widget.bookDetails.id != null) {
          progress = _progressProvider!.getProgressForItemById(
            widget.bookDetails.id!,
            item.absoluteIndex,
          );
        } else {
          progress = _progressProvider!.getProgressForItem(
            widget.topLevelCategoryKey,
            widget.bookName,
            item.absoluteIndex,
          );
        }
        total++;
        if (progress.getProperty(cycle)) completed++;
      }
      cycleProgress.add(total > 0 ? completed / total : 0.0);
    }

    // בניית תצוגה - מציג מחזור אם הוא התחיל או אם המחזור הקודם הושלם
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < cycles.length; i++)
            if (i == 0 || cycleProgress[i] > 0.0 || cycleProgress[i - 1] >= 1.0)
              Padding(
                padding: EdgeInsets.only(right: i > 0 ? 5 : 0),
                child: _buildCycleIndicator(
                  context,
                  i + 1,
                  cycleProgress[i],
                  cycleProgress[i] >= 1.0,
                ),
              ),
        ],
      ),
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

    if (isCompleted) {
      return Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green, width: 2),
        ),
        child: const Icon(FluentIcons.checkmark_24_regular,
            color: Colors.green, size: 28),
      );
    }

    final totalItems = widget.bookDetails.totalLearnableItems;
    final completedItems = (progress * totalItems).round();
    final progressPercentage = (progress * 100).round();

    return Container(
      width: 100,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            getCycleName(cycleNumber),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 5,
              value: progress,
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.08),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$progressPercentage% • $completedItems/$totalItems',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7),
                ),
          ),
        ],
      ),
    );
  }

  String _getProgressStatusText() {
    try {
      if (_progressProvider == null) {
        return 'לימוד פעיל';
      }
      final summary = _progressProvider!.getBookProgressSummarySync(
        widget.topLevelCategoryKey,
        widget.bookName,
        widget.bookDetails,
      );
      return summary.statusText;
    } catch (e, st) {
      _logger.warning('getBookProgressSummarySync failed', e, st);
      return 'לימוד פעיל';
    }
  }
}
