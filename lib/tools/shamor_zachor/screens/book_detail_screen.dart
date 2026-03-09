import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';

import '../models/book_model.dart';
import '../models/progress_model.dart';

import '../providers/shamor_zachor_data_provider.dart';
import '../providers/shamor_zachor_progress_provider.dart';
import '../widgets/hebrew_utils.dart';
import '../widgets/completion_animation_overlay.dart';
import '../widgets/error_boundary.dart';
import 'package:otzaria/core/ui_snack.dart';

/// Screen for displaying and managing progress for a specific book
class BookDetailScreen extends StatefulWidget {
  final String topLevelCategoryKey;
  final String categoryName;
  final String bookName;
  final int? bookId; // NEW: Book ID from DB
  final BookDetails?
      bookDetails; // Optional: if provided, use it instead of fetching
  final VoidCallback? onBack;

  const BookDetailScreen({
    super.key,
    required this.topLevelCategoryKey,
    required this.categoryName,
    required this.bookName,
    this.bookId, // NEW
    this.bookDetails,
    this.onBack,
  });

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen>
    with AutomaticKeepAliveClientMixin {
  static final Logger _logger = Logger('BookDetailScreen');

  // ריווח וגאטרים — שומרים יישור עמודות וזהות בין כותרת לשורות.
  static const double _gridHPad = 8.0; // ריווח אופקי אחיד
  static const double _chevronReserve = kMinInteractiveDimension;
  static const double _titleGutter = 6.0; // עוד טיפה מרווח מהחץ
  static const double _levelIndent = 16.0; // הזחה לכל רמה
  static const double _rightInset = _gridHPad + _chevronReserve + _titleGutter;
  static const int _titleFlex = 2;
  static const int _gridFlex = 10;

  // סגנון אחיד לכל הכותרות (leaf ו-parent)
  static const TextStyle _headingStyle = TextStyle(
    fontFamily: 'Heebo',
    fontSize: 18,
    fontWeight: FontWeight.w400,
    height: 1.1,
  );

  @override
  bool get wantKeepAlive => true;

  final Map<String, bool> _expandedSections = {};
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

  // Helper functions to use ID if available, otherwise fall back to category+name
  PageProgress _getProgress(
      ShamorZachorProgressProvider provider, int absoluteIndex) {
    if (widget.bookId != null) {
      return provider.getProgressForItemById(widget.bookId!, absoluteIndex);
    }
    // אם אין ID, זה אומר שהספר לא מגיע מה-DB
    // במקרה כזה, נחזיר התקדמות ריקה
    _logger.warning(
        'bookId is null for book ${widget.bookName}, returning empty progress');
    return PageProgress();
  }

  Future<void> _updateProgress(
    ShamorZachorProgressProvider provider,
    int absoluteIndex,
    String columnName,
    bool value,
    BookDetails bookDetails,
  ) async {
    // Debug log
    _logger.info(
        '_updateProgress called: bookId=${widget.bookId}, bookName=${widget.bookName}, absoluteIndex=$absoluteIndex');

    if (widget.bookId != null) {
      await provider.updateProgressById(
        widget.bookId!,
        absoluteIndex,
        columnName,
        value,
        bookDetails,
      );
    } else {
      // אם אין ID, זה אומר שהספר לא מגיע מה-DB
      // במקרה כזה, אנחנו לא יכולים לשמור התקדמות
      _logger.severe(
          'CRITICAL: bookId is null for book ${widget.bookName}! This should not happen for DB books.');
      UiSnack.showError('שגיאה: לא ניתן לשמור התקדמות לספר זה (חסר מזהה)');
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          leading: widget.onBack != null
              ? IconButton(
                  icon: const Icon(FluentIcons.arrow_left_24_regular),
                  onPressed: widget.onBack,
                  tooltip: 'חזרה',
                )
              : null,
          title: Text(widget.bookName),
          actions: [
            Consumer<ShamorZachorProgressProvider>(
              builder: (context, progressProvider, child) {
                final dataProvider = context.read<ShamorZachorDataProvider>();
                // Use provided bookDetails if available, otherwise fetch from provider
                final bookDetails = widget.bookDetails ??
                    dataProvider.getBookDetails(
                      widget.topLevelCategoryKey,
                      widget.bookName,
                    );

                if (bookDetails == null) {
                  _logger
                      .warning('BookDetails not found for ${widget.bookName}');
                  return const SizedBox.shrink();
                }

                // חישוב אחוז ההשלמה
                final learnableItems = bookDetails.learnableItems;
                int totalChecks = 0;
                int completedChecks = 0;

                for (final item in learnableItems) {
                  final progress = _getProgress(
                    progressProvider,
                    item.absoluteIndex,
                  );
                  totalChecks += 4; // 4 עמודות לכל פריט
                  if (progress.learn) completedChecks++;
                  if (progress.review1) completedChecks++;
                  if (progress.review2) completedChecks++;
                  if (progress.review3) completedChecks++;
                }

                final completionPercentage =
                    totalChecks > 0 ? completedChecks / totalChecks : 0.0;

                return Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: completionPercentage,
                          strokeWidth: 3,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        if (completionPercentage >= 1.0)
                          Icon(
                            FluentIcons.checkmark_24_regular,
                            size: 14,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                      ],
                    ),
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

              if (dataProvider.error != null) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(FluentIcons.error_circle_24_regular,
                          size: 64, color: Colors.red),
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

              // Use provided bookDetails if available, otherwise fetch from provider
              final bookDetails = widget.bookDetails ??
                  dataProvider.getBookDetails(
                    widget.topLevelCategoryKey,
                    widget.bookName,
                  );

              if (bookDetails == null) {
                _logger.warning(
                    'BookDetails not found for ${widget.bookName} in category ${widget.topLevelCategoryKey}');
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(FluentIcons.book_24_regular,
                          size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        'פרטי הספר "${widget.bookName}" לא נמצאו',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'קטגוריה: ${widget.topLevelCategoryKey}',
                        style: Theme.of(context).textTheme.bodySmall,
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
      return const Center(child: Text('אין פריטים ללימוד בספר זה'));
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

    // אם אין bookId, נחזיר כותרת ריקה
    if (widget.bookId == null) {
      _logger.warning(
          'bookId is null in _buildHeader for book ${widget.bookName}');
      return const SizedBox.shrink();
    }

    final columnSelectionStates = progressProvider.getColumnSelectionStatesById(
      widget.bookId!,
      bookDetails,
    );

    return Container(
      padding: EdgeInsets.fromLTRB(
          _gridHPad, 8, _gridHPad + _chevronReserve + _titleGutter, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: const SizedBox
                .shrink(), // הסרת הכפילות של שם הספר/סוג תוכן בראש הרשימה
          ),
          Expanded(
            flex: 10,
            child: Row(
              // אין spaceEvenly כדי לשמור פריסה זהה בכל עומק
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
                            if (widget.bookId != null) {
                              await progressProvider
                                  .toggleSelectAllForColumnById(
                                widget.bookId!,
                                bookDetails,
                                columnId,
                                selectAction,
                              );
                            } else {
                              await progressProvider.toggleSelectAllForColumn(
                                widget.topLevelCategoryKey,
                                widget.bookName,
                                bookDetails,
                                columnId,
                                selectAction,
                              );
                            }
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
                              fontSize: 11, color: theme.colorScheme.onSurface),
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
          final item = learnableItems[index];
          final absoluteIndex = item.absoluteIndex;
          final partName = item.partName;

          final showHeader = bookDetails.hasMultipleParts == true &&
              (index == 0 || partName != learnableItems[index - 1].partName) &&
              partName != widget.bookName; // מניעת כפילות של שם הספר בכותרת חלק

          String rowLabel;
          if (bookDetails.isDafType == true) {
            final amudSymbol = (item.amudKey == "b") ? ":" : ".";
            rowLabel =
                "${HebrewUtils.intToGematria(item.pageNumber)}$amudSymbol";
          } else {
            rowLabel = HebrewUtils.intToGematria(item.pageNumber);
          }

          final pageProgress = _getProgress(
            progressProvider,
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
                padding: EdgeInsets.fromLTRB(_gridHPad, 2, _rightInset, 2),
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
                        children: _columnData.map((col) {
                          final columnName = col['id']!;
                          return Expanded(
                            child: Tooltip(
                              message: col['label'],
                              child: Checkbox(
                                visualDensity: VisualDensity.compact,
                                value: pageProgress.getProperty(columnName),
                                onChanged: (val) => _updateProgress(
                                  progressProvider,
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
        childCount: learnableItems.length,
      ),
    );
  }

  Widget _buildNestedItemsSliver(
    BuildContext context,
    BookDetails bookDetails,
    ShamorZachorProgressProvider progressProvider,
  ) {
    final sections = bookDetails.sections ?? const [];

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (ctx, index) {
          final section = sections[index];

          // אם כותרת הסקציה זהה לשם הספר (שכבר מופיע למעלה), נדלג עליה
          // ונציג ישירות את הילדים שלה אם קיימים.
          if (section.title == widget.bookName && section.children.isNotEmpty) {
            return Column(
              children: section.children
                  .map((child) => _buildSectionExpansionTile(
                        context,
                        child,
                        0,
                        bookDetails,
                        progressProvider,
                      ))
                  .toList(),
            );
          }

          return _buildSectionExpansionTile(
            context,
            section,
            0,
            bookDetails,
            progressProvider,
          );
        },
        childCount: sections.length,
      ),
    );
  }

  Widget _buildSectionExpansionTile(
    BuildContext context,
    BookSection section,
    int level,
    BookDetails bookDetails,
    ShamorZachorProgressProvider progressProvider,
  ) {
    final theme = Theme.of(context);
    final isExpanded =
        _expandedSections[section.id] ?? true; // פתוח כברירת־מחדל

    // Leaf
    if (section.children.isEmpty) {
      final leafIndices =
          bookDetails.sectionLeafIndexMap[section.id] ?? const [];
      if (leafIndices.isEmpty) return const SizedBox.shrink();

      final learnable = bookDetails.learnableItems
          .firstWhere((item) => item.absoluteIndex == leafIndices.first);
      final pageProgress = _getProgress(
        progressProvider,
        leafIndices.first,
      );

      final rowBackgroundColor =
          learnable.absoluteIndex % (bookDetails.isDafType == true ? 4 : 2) <
                  (bookDetails.isDafType == true ? 2 : 1)
              ? Colors.transparent
              : theme.colorScheme.primaryContainer.withValues(alpha: 0.15);

      // מציגים leaf בפורמט של שורה רגילה (כמו ב-flat), עם RTL
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          color: rowBackgroundColor,
          padding: EdgeInsets.fromLTRB(_gridHPad, 2, _rightInset, 2),
          child: Row(
            children: [
              Expanded(
                flex: _titleFlex,
                child: Text(
                  learnable.displayLabel ?? learnable.partName,
                  textAlign: TextAlign.right,
                  style: _headingStyle.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
              Expanded(
                flex: _gridFlex,
                child: Row(
                  children: _columnData.map((col) {
                    final columnName = col['id']!;
                    return Expanded(
                      child: Tooltip(
                        message: col['label']!,
                        child: Checkbox(
                          visualDensity: VisualDensity.compact,
                          value: pageProgress.getProperty(columnName),
                          onChanged: (val) => _updateProgress(
                            progressProvider,
                            learnable.absoluteIndex,
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
      );
    }

    // Parent
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Theme(
        data: theme.copyWith(
          // צמצום מרווחי ה-ListTile של ה-ExpansionTile
          listTileTheme: const ListTileThemeData(
            dense: true,
            minVerticalPadding: 0,
            horizontalTitleGap: 0,
            minLeadingWidth: 0,
            contentPadding: EdgeInsets.zero,
          ),
          // צמצום tap-target של Checkbox
          checkboxTheme: const CheckboxThemeData(
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity(horizontal: -4, vertical: -4),
          ),
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
        ),
        child: ExpansionTile(
          key: ValueKey(section.id),
          initiallyExpanded: isExpanded,
          onExpansionChanged: (expanded) {
            setState(() => _expandedSections[section.id] = expanded);
          },
          tilePadding: const EdgeInsetsDirectional.only(
            end: _gridHPad + _titleGutter,
          ),
          childrenPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.trailing,
          title: Directionality(
            textDirection: TextDirection.rtl, // תוכן RTL
            child: Container(
              padding: const EdgeInsets.only(
                  left: _gridHPad, right: _gridHPad, top: 1, bottom: 1),
              child: Row(
                children: [
                  // קודם כותרת, כמו ב־Header
                  Expanded(
                    flex: _titleFlex,
                    child: Padding(
                      // הזחה ביחס ל־RTL מהימין פנימה - רק לכותרת!
                      padding: EdgeInsetsDirectional.only(
                          start: _levelIndent * level),
                      child: Text(
                        section.title,
                        style: _headingStyle.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: _gridFlex,
                    child: Row(
                      children: _columnData.map((col) {
                        final columnId = col['id']!;

                        // אם אין bookId, נחזיר checkbox ריק
                        if (widget.bookId == null) {
                          return Expanded(
                            child: SizedBox(
                              height: 24,
                              child: Center(
                                child: Checkbox(
                                  value: false,
                                  tristate: true,
                                  onChanged: null, // disabled
                                ),
                              ),
                            ),
                          );
                        }

                        final state =
                            progressProvider.getSectionColumnStateById(
                          widget.bookId!,
                          bookDetails,
                          section.id,
                          columnId,
                        );
                        return Expanded(
                          child: SizedBox(
                            height: 24,
                            child: Center(
                              child: Checkbox(
                                value: state,
                                tristate: true,
                                onChanged: (value) async {
                                  // toggleSectionColumn uses the old method internally
                                  // We need to update all items in the section manually
                                  if (widget.bookId != null) {
                                    await progressProvider
                                        .toggleSectionColumnById(
                                      widget.bookId!,
                                      bookDetails,
                                      section.id,
                                      columnId,
                                      value == true,
                                    );
                                  } else {
                                    await progressProvider.toggleSectionColumn(
                                      widget.topLevelCategoryKey,
                                      widget.bookName,
                                      bookDetails,
                                      section.id,
                                      columnId,
                                      value == true,
                                    );
                                  }
                                },
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
          ),
          // אין Padding חיצוני; ההזחה מבוקרת רק בכותרת ובעמודת ה־V
          children: section.children
              .map((child) => _buildSectionExpansionTile(
                    context,
                    child,
                    level + 1,
                    bookDetails,
                    progressProvider,
                  ))
              .toList(),
        ),
      ),
    );
  }
}
