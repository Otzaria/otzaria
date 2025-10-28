import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';
import '../models/book_model.dart';
import '../models/progress_model.dart';
import '../providers/shamor_zachor_progress_provider.dart';
import 'hebrew_utils.dart';

class BookCardWidget extends StatefulWidget {
  static final Logger _logger = Logger('BookCardWidget');

  final String topLevelCategoryKey;
  final String categoryName;
  final String bookName;
  final BookDetails bookDetails;
  final Map<String, PageProgress> bookProgressData;
  final bool isFromTrackingScreen;
  final String? completionDate;
  final bool isInCompletedListContext;

  const BookCardWidget({
    super.key,
    required this.topLevelCategoryKey,
    required this.categoryName,
    required this.bookName,
    required this.bookDetails,
    required this.bookProgressData,
    this.isFromTrackingScreen = false,
    this.completionDate,
    this.isInCompletedListContext = false,
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
      final newLearnProgress = pp
          .getLearnProgressPercentage(
            widget.topLevelCategoryKey,
            widget.bookName,
            widget.bookDetails,
          )
          .clamp(0.0, 1.0);

      final newIsCompleted = pp.isBookCompleted(
        widget.topLevelCategoryKey,
        widget.bookName,
        widget.bookDetails,
      );

      final newCompletedCycles = pp.getNumberOfCompletedCycles(
        widget.topLevelCategoryKey,
        widget.bookName,
        widget.bookDetails,
      );

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
                    const Icon(Icons.check_circle,
                        color: Colors.green, size: 24),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              // Progress / Completion info
              (_isCompleted && widget.completionDate != null)
                  ? _buildCompletionInfo(context, widget.completionDate!)
                  : _buildProgressInfo(context, _learnProgress),
              const SizedBox(height: 12),
              // Additional info
              Row(
                children: [
                  Icon(
                    widget.bookDetails.isDafType ? Icons.book : Icons.article,
                    size: 16,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.bookDetails.totalLearnableItems} ${widget.bookDetails.contentType}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                  ),
                  const Spacer(),
                  if (_completedCycles > 0) ...[
                    Icon(Icons.repeat,
                        size: 16, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      '$_completedCycles מחזורים',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  void _onCardTap(BuildContext context) {
    Navigator.of(context).pushNamed(
      '/book_detail',
      arguments: {
        'topLevelCategoryKey': widget.topLevelCategoryKey,
        'categoryName': widget.categoryName,
        'bookName': widget.bookName,
      },
    );
  }

  Widget _buildCompletionInfo(BuildContext context, String isoDate) {
    final hebrewDate = HebrewUtils.formatHebrewDate(isoDate);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: Colors.green.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(children: [
        const Icon(Icons.celebration, color: Colors.green, size: 20),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('הושלם בהצלחה!',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600)),
              Text(hebrewDate,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.green.shade600)),
            ],
          ),
        ),
      ]),
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
