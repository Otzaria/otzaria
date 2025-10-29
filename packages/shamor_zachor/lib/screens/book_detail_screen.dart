import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';

import '../models/book_model.dart';
import '../models/progress_model.dart';
import '../providers/shamor_zachor_data_provider.dart';
import '../providers/shamor_zachor_progress_provider.dart';
import '../widgets/hebrew_utils.dart';
import '../widgets/completion_animation_overlay.dart';
import '../widgets/error_boundary.dart';

/// Screen for displaying and managing progress for a specific book
class BookDetailScreen extends StatefulWidget {
  final String topLevelCategoryKey;
  final String categoryName;
  final String bookName;

  const BookDetailScreen({
    super.key,
    required this.topLevelCategoryKey,
    required this.categoryName,
    required this.bookName,
  });

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen>
    with AutomaticKeepAliveClientMixin {
  static final Logger _logger = Logger('BookDetailScreen');

  @override
  bool get wantKeepAlive => true;

  StreamSubscription<CompletionEvent>? _completionSubscription;

  final List<Map<String, String>> _columnData = [
    {'id': 'learn', 'label': 'לימוד'},
    {'id': 'review1', 'label': 'חזרה 1'},
    {'id': 'review2', 'label': 'חזרה 2'},
    {'id': 'review3', 'label': 'חזרה 3'},
  ];

  @override
  void initState() {
    super.initState();
    _logger.info('Initializing BookDetailScreen for ${widget.bookName}');

    final progressProvider = context.read<ShamorZachorProgressProvider>();
    _completionSubscription = progressProvider.completionEvents.listen((event) {
      if (!mounted) return;

      if (event.type == CompletionEventType.bookCompleted) {
        CompletionAnimationOverlay.show(
            context, "אשריך! תזכה ללמוד ספרים אחרים ולסיימם!");
      } else if (event.type == CompletionEventType.reviewCycleCompleted) {
        CompletionAnimationOverlay.show(
            context, "מזל טוב! הלומד וחוזר כזורע וקוצר!");
      }
    });
  }

  @override
  void dispose() {
    _completionSubscription?.cancel();
    _logger.fine('Disposing BookDetailScreen');
    super.dispose();
  }

  Future<bool> _showWarningDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("אזהרה"),
          content:
              const Text("פעולה זו תשנה את כל הסימונים בעמודה זו. האם להמשיך?"),
          actions: <Widget>[
            TextButton(
              child: const Text("לא"),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text("כן"),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.bookName),
          actions: [
            Consumer<ShamorZachorProgressProvider>(
              builder: (context, progressProvider, child) {
                final dataProvider = context.read<ShamorZachorDataProvider>();
                final bookDetails = dataProvider.getBookDetails(
                  widget.topLevelCategoryKey,
                  widget.bookName,
                );

                if (bookDetails == null) return const SizedBox.shrink();

                final isCompleted = progressProvider.isBookCompleted(
                  widget.topLevelCategoryKey,
                  widget.bookName,
                  bookDetails,
                );

                return Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Icon(
                    isCompleted ? Icons.check_circle : Icons.circle_outlined,
                    color: isCompleted
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                  ),
                );
              },
            ),
          ],
        ),
        body: ErrorBoundary(
          child:
              Consumer2<ShamorZachorDataProvider, ShamorZachorProgressProvider>(
            builder: (context, dataProvider, progressProvider, child) {
              // Show loading state
              if (dataProvider.isLoading || progressProvider.isLoading) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('טוען פרטי ספר...'),
                    ],
                  ),
                );
              }

              // Show error state
              if (dataProvider.error != null) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        dataProvider.error!.userFriendlyMessage,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      if (dataProvider.error!.suggestedAction != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          dataProvider.error!.suggestedAction!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (dataProvider.error!.isRecoverable)
                        ElevatedButton(
                          onPressed: () => dataProvider.retry(),
                          child: const Text('נסה שוב'),
                        ),
                    ],
                  ),
                );
              }

              final bookDetails = dataProvider.getBookDetails(
                widget.topLevelCategoryKey,
                widget.bookName,
              );

              if (bookDetails == null) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.book_outlined,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'פרטי הספר "${widget.bookName}" לא נמצאו',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                );
              }

              return _buildBookContent(context, bookDetails, progressProvider);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBookContent(
    BuildContext context,
    BookDetails bookDetails,
    ShamorZachorProgressProvider progressProvider,
  ) {
    final learnableItems = bookDetails.learnableItems;

    if (learnableItems.isEmpty) {
      return const Center(
        child: Text('אין פריטים ללימוד בספר זה'),
      );
    }

    final hasNested = bookDetails.sections != null &&
        bookDetails.sections!.isNotEmpty &&
        bookDetails.hasNestedSections;

    final sliverList = hasNested
        ? _buildNestedItemsSliver(context, bookDetails, progressProvider)
        : _buildFlatItemsSliver(context, bookDetails, progressProvider);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: _buildHeader(context, bookDetails, progressProvider),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(12.0),
          sliver: sliverList,
        ),
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context,
    dynamic bookDetails,
    ShamorZachorProgressProvider progressProvider,
  ) {
    final theme = Theme.of(context);
    final columnSelectionStates = progressProvider.getColumnSelectionStates(
      widget.topLevelCategoryKey,
      widget.bookName,
      bookDetails,
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              bookDetails.contentType ?? 'תוכן',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 10,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _columnData.map((col) {
                final columnId = col['id']!;
                final columnLabel = col['label']!;
                final bool? checkboxValue = columnSelectionStates[columnId];

                return Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        visualDensity: VisualDensity.compact,
                        value: checkboxValue,
                        onChanged: (bool? newValue) async {
                          final bool selectAction = newValue == true;
                          final confirmed = await _showWarningDialog();
                          if (confirmed && mounted) {
                            await progressProvider.toggleSelectAllForColumn(
                              widget.topLevelCategoryKey,
                              widget.bookName,
                              bookDetails,
                              columnId,
                              selectAction,
                            );
                          }
                        },
                        tristate: true,
                        activeColor: theme.primaryColor,
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          columnLabel,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlatItemsSliver(
    BuildContext context,
    BookDetails bookDetails,
    ShamorZachorProgressProvider progressProvider,
  ) {
    final theme = Theme.of(context);
    final learnableItems = bookDetails.learnableItems;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (ctx, index) {
          // ... כל הקוד שהיה לך בתוך itemBuilder נשאר זהה לחלוטין ...
          final item = learnableItems[index];
          final absoluteIndex = item.absoluteIndex ?? index;
          final partName = item.partName ?? '';

          bool showHeader = bookDetails.hasMultipleParts == true &&
              (index == 0 ||
                  partName != (learnableItems[index - 1].partName ?? ''));

          String rowLabel;
          if (bookDetails.isDafType == true) {
            final amudSymbol = (item.amudKey == "b") ? ":" : ".";
            rowLabel =
                "${HebrewUtils.intToGematria(item.pageNumber ?? 1)}$amudSymbol";
          } else {
            rowLabel = HebrewUtils.intToGematria(item.pageNumber ?? index + 1);
          }

          final pageProgress = progressProvider.getProgressForItem(
            widget.topLevelCategoryKey,
            widget.bookName,
            absoluteIndex,
          );

          final rowBackgroundColor =
              index % (bookDetails.isDafType == true ? 4 : 2) <
                      (bookDetails.isDafType == true ? 2 : 1)
                  ? Colors.transparent
                  : theme.colorScheme.primaryContainer.withValues(alpha: 0.15);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showHeader && partName.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  margin: const EdgeInsets.only(top: 16.0, bottom: 4.0),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    partName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              Container(
                color: rowBackgroundColor,
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        rowLabel,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontFamily: 'Heebo',
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 10,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: _columnData.map((col) {
                          final columnName = col['id']!;
                          return Expanded(
                            child: Tooltip(
                              message: col['label']!,
                              child: Checkbox(
                                visualDensity: VisualDensity.compact,
                                value: pageProgress.getProperty(columnName),
                                onChanged: (val) =>
                                    progressProvider.updateProgress(
                                  widget.topLevelCategoryKey,
                                  widget.bookName,
                                  absoluteIndex,
                                  columnName,
                                  val ?? false,
                                  bookDetails,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
        childCount:
            learnableItems.length, // חשוב להגיד ל-SliverList כמה פריטים יש
      ),
    );
  }

  Widget _buildNestedItemsSliver(
    BuildContext context,
    BookDetails bookDetails,
    ShamorZachorProgressProvider progressProvider,
  ) {
    final theme = Theme.of(context);
    final rows = _buildSectionRows(bookDetails);

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (ctx, index) {
          final row = rows[index];
          if (row.isLeaf) {
            if (row.leafIndex == null) {
              return const SizedBox.shrink();
            }
            final learnable = bookDetails.learnableItems
                .firstWhere((item) => item.absoluteIndex == row.leafIndex);
            final pageProgress = progressProvider.getProgressForItem(
              widget.topLevelCategoryKey,
              widget.bookName,
              row.leafIndex!,
            );

            return _buildLeafRow(
              context,
              theme,
              row,
              learnable,
              pageProgress,
              bookDetails,
              progressProvider,
            );
          } else {
            return _buildGroupRow(
              context,
              theme,
              row,
              bookDetails,
              progressProvider,
            );
          }
        },
        childCount: rows.length,
      ),
    );
  }

  Widget _buildGroupRow(
    BuildContext context,
    ThemeData theme,
    _SectionRowData row,
    BookDetails bookDetails,
    ShamorZachorProgressProvider progressProvider,
  ) {
    final padding = EdgeInsetsDirectional.only(start: row.level * 16.0);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Padding(
              padding: padding,
              child: Text(
                row.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 10,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _columnData.map((col) {
                final columnId = col['id']!;
                final state = progressProvider.getSectionColumnState(
                  widget.topLevelCategoryKey,
                  widget.bookName,
                  bookDetails,
                  row.sectionId,
                  columnId,
                );

                return Expanded(
                  child: Checkbox(
                    value: state,
                    tristate: true,
                    onChanged: (value) => progressProvider.toggleSectionColumn(
                      widget.topLevelCategoryKey,
                      widget.bookName,
                      bookDetails,
                      row.sectionId,
                      columnId,
                      value == true,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeafRow(
    BuildContext context,
    ThemeData theme,
    _SectionRowData row,
    LearnableItem learnable,
    PageProgress pageProgress,
    BookDetails bookDetails,
    ShamorZachorProgressProvider progressProvider,
  ) {
    final padding = EdgeInsetsDirectional.only(start: row.level * 16.0);
    final rowLabel = learnable.displayLabel ?? learnable.partName;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Padding(
              padding: padding,
              child: Text(
                rowLabel,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          Expanded(
            flex: 10,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _columnData.map((col) {
                final columnName = col['id']!;
                return Expanded(
                  child: Tooltip(
                    message: col['label']!,
                    child: Checkbox(
                      visualDensity: VisualDensity.compact,
                      value: pageProgress.getProperty(columnName),
                      onChanged: (val) => progressProvider.updateProgress(
                        widget.topLevelCategoryKey,
                        widget.bookName,
                        row.leafIndex!,
                        columnName,
                        val ?? false,
                        bookDetails,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  List<_SectionRowData> _buildSectionRows(BookDetails bookDetails) {
    final List<_SectionRowData> rows = [];

    void traverse(BookSection section, int level) {
      final isLeaf = section.children.isEmpty;
      final leafIndices = bookDetails.sectionLeafIndexMap[section.id] ?? const [];

      rows.add(_SectionRowData(
        sectionId: section.id,
        title: section.title,
        level: level,
        isLeaf: isLeaf,
        leafIndex: isLeaf && leafIndices.isNotEmpty ? leafIndices.first : null,
      ));

      for (final child in section.children) {
        traverse(child, level + 1);
      }
    }

    for (final section in bookDetails.sections ?? const []) {
      traverse(section, 0);
    }

    return rows;
  }
}

class _SectionRowData {
  final String sectionId;
  final String title;
  final int level;
  final bool isLeaf;
  final int? leafIndex;

  const _SectionRowData({
    required this.sectionId,
    required this.title,
    required this.level,
    required this.isLeaf,
    this.leafIndex,
  });
}
