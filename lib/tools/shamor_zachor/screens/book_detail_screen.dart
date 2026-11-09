import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';
import 'package:otzaria/widgets/feedback/otzaria_error_state.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';

import '../models/book_model.dart';
import '../models/progress_model.dart';

import '../providers/shamor_zachor_data_provider.dart';
import '../providers/shamor_zachor_progress_provider.dart';
import '../widgets/hebrew_utils.dart';
import '../widgets/completion_animation_overlay.dart';
import '../widgets/mark_range_dialog.dart';
import '../widgets/error_boundary.dart';
import 'package:otzaria/core/messages/tools_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';
import 'package:otzaria/widgets/feedback/app_info_banner.dart';
import 'package:otzaria/widgets/layout/app_card.dart';
import 'package:otzaria/widgets/lists/tree_section_header.dart';

/// Screen for displaying and managing progress for a specific book
class BookDetailScreen extends StatefulWidget {
  final String topLevelCategoryKey;
  final String bookName;
  final int? bookId;
  final BookDetails? bookDetails;
  final VoidCallback? onBack;

  const BookDetailScreen({
    super.key,
    required this.topLevelCategoryKey,
    required this.bookName,
    this.bookId,
    this.bookDetails,
    this.onBack,
  });

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

/// רוחב תא מינימלי שבו מוצג מתחת לתאריך העברי גם הלועזי.
const double _kGregorianDateMinWidth = 96;

class _BookDetailScreenState extends State<BookDetailScreen>
    with AutomaticKeepAliveClientMixin {
  static final Logger _logger = Logger('BookDetailScreen');

  // ריווח וגאטרים — שומרים יישור עמודות וזהות בין כותרת לשורות.
  static const double _gridHPad = 8.0; // ריווח אופקי אחיד
  static const double _chevronReserve = kMinInteractiveDimension;
  static const double _titleGutter = 6.0; // עוד טיפה מרווח מהחץ
  static const double _levelIndent = 16.0; // הזחה לכל רמה
  static const double _rightInset = _gridHPad + _chevronReserve + _titleGutter;
  static const int _gridFlex = 10;

  /// Width of the title column against [_gridFlex]; wider in a narrow window,
  /// where a sixth of the width cut every title short.
  int _titleFlex = 3;
  static const double _narrowWidth = 560;

  // סגנון אחיד לכל הכותרות (leaf ו-parent)
  static const TextStyle _headingStyle = TextStyle(
    fontSize: AppTokens.fontLG,
    fontWeight: FontWeight.w400,
    height: 1.1,
  );

  @override
  bool get wantKeepAlive => true;

  final Map<String, bool> _expandedSections = {};
  StreamSubscription<CompletionEvent>? _completionSubscription;

  /// העמודות המוגדרות לספר זה (נטענות מה-Provider, ברירת מחדל אם אין הגדרה)
  List<ProgressColumn> _columnsOf(ShamorZachorProgressProvider pp) =>
      widget.bookId != null
      ? pp.getColumnsForBook(widget.bookId!)
      : kDefaultProgressColumns;

  @override
  void initState() {
    super.initState();
    _logger.info('Initializing BookDetailScreen for ${widget.bookName}');
    final progressProvider = context.read<ShamorZachorProgressProvider>();
    _completionSubscription = progressProvider.completionEvents.listen((event) {
      if (!mounted) return;
      if (event.type == CompletionEventType.bookCompleted) {
        CompletionAnimationOverlay.show(
          context,
          "אשריך! תזכה ללמוד ספרים אחרים ולסיימם!",
        );
      } else if (event.type == CompletionEventType.reviewCycleCompleted) {
        CompletionAnimationOverlay.show(
          context,
          "מזל טוב! הלומד וחוזר כזורע וקוצר!",
        );
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
    final result = await showWarningDialog(
      context: context,
      title: 'אזהרה',
      content: 'פעולה זו תשנה את כל הסימונים בעמודה זו. האם להמשיך?',
      cancelText: 'לא',
      confirmText: 'כן',
    );
    return result ?? false;
  }

  // Helper functions to use ID if available, otherwise fall back to category+name
  PageProgress _getProgress(
    ShamorZachorProgressProvider provider,
    int absoluteIndex,
  ) {
    if (widget.bookId != null) {
      return provider.getProgressForItemById(widget.bookId!, absoluteIndex);
    }
    // אם אין ID, זה אומר שהספר לא מגיע מה-DB
    // במקרה כזה, נחזיר התקדמות ריקה
    _logger.warning(
      'bookId is null for book ${widget.bookName}, returning empty progress',
    );
    return PageProgress();
  }

  BookDetails? _currentBookDetails(ShamorZachorDataProvider provider) {
    final bookId = widget.bookId ?? widget.bookDetails?.id;
    return bookId != null
        ? provider.getBookById(bookId)?.$1
        : widget.bookDetails ??
              provider.getBookDetails(
                widget.topLevelCategoryKey,
                widget.bookName,
              );
  }

  bool _isCurrentBook(BookDetails bookDetails) =>
      mounted &&
      identical(
        bookDetails,
        _currentBookDetails(context.read<ShamorZachorDataProvider>()),
      );

  Future<void> _updateProgress(
    ShamorZachorProgressProvider provider,
    int absoluteIndex,
    String columnName,
    bool value,
    BookDetails bookDetails,
  ) async {
    if (!_isCurrentBook(bookDetails)) return;
    _logger.info(
      '_updateProgress called: bookId=${widget.bookId}, bookName=${widget.bookName}, absoluteIndex=$absoluteIndex',
    );

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
        'CRITICAL: bookId is null for book ${widget.bookName}! This should not happen for DB books.',
      );
      UiSnack.showError(ToolsMessages.progressSaveMissingId);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ErrorBoundary(
      child: Consumer2<ShamorZachorDataProvider, ShamorZachorProgressProvider>(
        builder: (context, dataProvider, progressProvider, child) {
          if (dataProvider.isLoading || progressProvider.isLoading) {
            return const LoadingIndicator();
          }

          if (dataProvider.error != null) {
            final error = dataProvider.error!;
            return OtzariaErrorState(
              title: error.userFriendlyMessage,
              details: error.suggestedAction,
              actions: [
                if (error.isRecoverable)
                  ActionButton.recommended(
                    text: 'נסה שוב',
                    icon: FluentIcons.arrow_clockwise_24_regular,
                    onPressed: () => dataProvider.retry(),
                  ),
              ],
            );
          }

          final bookDetails = _currentBookDetails(dataProvider);

          if (bookDetails == null) {
            _logger.warning(
              'BookDetails not found for ${widget.bookName} in category ${widget.topLevelCategoryKey}',
            );
            return OtzariaEmptyState(
              icon: OtzariaIcons.book_24_regular,
              title: 'פרטי הספר "${widget.bookName}" לא נמצאו',
              message: 'קטגוריה: ${widget.topLevelCategoryKey}',
            );
          }

          return _buildBookContent(context, bookDetails, progressProvider);
        },
      ),
    );
  }

  Widget _buildBookContent(
    BuildContext context,
    BookDetails bookDetails,
    ShamorZachorProgressProvider progressProvider,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _titleFlex = constraints.maxWidth < _narrowWidth ? 4 : 3;
        return _buildBookBody(context, bookDetails, progressProvider);
      },
    );
  }

  Widget _buildBookBody(
    BuildContext context,
    BookDetails bookDetails,
    ShamorZachorProgressProvider progressProvider,
  ) {
    final learnableItems = bookDetails.learnableItems;

    if (learnableItems.isEmpty) {
      return const OtzariaEmptyState(
        icon: OtzariaIcons.book_24_regular,
        title: 'אין פריטים ללימוד בספר זה',
      );
    }

    final hasNested =
        bookDetails.sections != null &&
        bookDetails.sections!.isNotEmpty &&
        bookDetails.hasNestedSections;

    final sliverList = hasNested
        ? _buildNestedItemsSliver(context, bookDetails, progressProvider)
        : _buildFlatItemsSliver(context, bookDetails, progressProvider);

    final theme = Theme.of(context);
    final completionPct = _calculateCompletionPercentage(
      bookDetails,
      progressProvider,
    );

    final cs = theme.colorScheme;
    final completionRaw = widget.bookId == null
        ? null
        : progressProvider.getCompletionDateSyncById(widget.bookId!);
    final bookCompletionDate = completionRaw == null
        ? null
        : DateTime.tryParse(completionRaw);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: LayoutConstraints.panelContentMaxWidth,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMD),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── כותרת הספר ────────────────────────────────────────────────
              Row(
                children: [
                  if (widget.onBack != null) ...[
                    SecondaryIconButton(
                      icon: FluentIcons.arrow_left_24_regular,
                      onPressed: widget.onBack!,
                      tooltip: 'חזרה',
                    ),
                    const SizedBox(width: AppTokens.spaceMD),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.bookName,
                          style: TextStyle(
                            fontSize: AppTokens.fontXL + 2,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                        if (bookDetails.categoryPath != null)
                          Text(
                            bookDetails.categoryPath!,
                            style: TextStyle(
                              fontSize: AppTokens.fontSM,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppTokens.spaceMD),
                  Tooltip(
                    message: 'התקדמות כוללת',
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CircularProgressIndicator(
                            value: completionPct,
                            strokeWidth: 4,
                            backgroundColor: cs.onSurface.withValues(
                              alpha: 0.08,
                            ),
                          ),
                          Center(
                            child: completionPct >= 1.0
                                ? Icon(
                                    FluentIcons.checkmark_24_regular,
                                    size: 20,
                                    color: cs.primary,
                                  )
                                : Text(
                                    '${(completionPct * 100).round()}%',
                                    style: TextStyle(
                                      fontSize: AppTokens.fontSM - 1,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.spaceMD),
              // ── טבלת הסימונים: כותרות העמודות נשארות גלויות בגלילה ───────
              Expanded(
                child: AppCard(
                  child: Column(
                    children: [
                      _buildHeader(context, bookDetails, progressProvider),
                      Expanded(
                        child: CustomScrollView(
                          slivers: [
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppTokens.spaceSM,
                              ),
                              sliver: sliverList,
                            ),
                          ],
                        ),
                      ),
                      if (bookCompletionDate != null)
                        _buildCompletionFooter(bookCompletionDate),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// שורת סיום בתחתית הטבלה: מתי הושלם הלימוד.
  Widget _buildCompletionFooter(DateTime completedAt) {
    return Padding(
      padding: const EdgeInsets.all(AppTokens.spaceSM),
      child: AppInfoBanner(
        tone: AppInfoBannerTone.success,
        icon: FluentIcons.checkmark_24_regular,
        message: 'הושלם ${HebrewUtils.fullDate(completedAt)}',
      ),
    );
  }

  double _calculateCompletionPercentage(
    BookDetails bookDetails,
    ShamorZachorProgressProvider progressProvider,
  ) {
    final columns = _columnsOf(progressProvider);
    if (columns.isEmpty) return 0.0;

    int totalChecks = 0;
    int completedChecks = 0;

    for (final item in bookDetails.learnableItems) {
      final progress = _getProgress(progressProvider, item.absoluteIndex);
      for (final column in columns) {
        totalChecks++;
        if (progress.getProperty(column.id)) completedChecks++;
      }
    }

    return totalChecks > 0 ? completedChecks / totalChecks : 0.0;
  }

  Widget _buildHeader(
    BuildContext context,
    BookDetails bookDetails,
    ShamorZachorProgressProvider progressProvider,
  ) {
    final theme = Theme.of(context);

    // אם אין bookId, נחזיר כותרת ריקה
    if (widget.bookId == null) {
      _logger.warning(
        'bookId is null in _buildHeader for book ${widget.bookName}',
      );
      return const SizedBox.shrink();
    }

    final columns = _columnsOf(progressProvider);
    final columnSelectionStates = progressProvider.getColumnSelectionStatesById(
      widget.bookId!,
      bookDetails,
    );

    return Container(
      padding: EdgeInsets.fromLTRB(
        _gridHPad + 12,
        AppTokens.spaceSM,
        _gridHPad + _chevronReserve + _titleGutter + 12,
        AppTokens.spaceSM,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.5,
        ),
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: _titleFlex,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: columns.length < ShamorZachorProgressProvider.maxColumns
                  ? IconButton.filledTonal(
                      tooltip: 'הוסף עמודה',
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        shape: AppTokens.roundedShape,
                      ),
                      icon: const Icon(FluentIcons.add_24_regular),
                      onPressed: () => _addColumn(progressProvider),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          Expanded(
            flex: _gridFlex,
            child: Row(
              // אין spaceEvenly כדי לשמור פריסה זהה בכל עומק
              // start: a date line under one label must not shift its checkbox
              crossAxisAlignment: CrossAxisAlignment.start,
              children: columns.map((col) {
                final columnId = col.id;
                final bool? checkboxValue = columnSelectionStates[columnId];
                final completedAt = checkboxValue == true
                    ? progressProvider.getColumnCompletionDate(
                        widget.bookId!,
                        columnId,
                      )
                    : null;

                return Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Checkbox(
                        visualDensity: VisualDensity.compact,
                        value: checkboxValue,
                        onChanged: (bool? newValue) async {
                          final bool selectAction = newValue == true;
                          final confirmed = await _showWarningDialog();
                          if (confirmed &&
                              _isCurrentBook(bookDetails) &&
                              widget.bookId != null) {
                            await progressProvider.toggleSelectAllForColumnById(
                              widget.bookId!,
                              bookDetails,
                              columnId,
                              selectAction,
                            );
                          }
                        },
                        tristate: true,
                        activeColor: theme.colorScheme.primary,
                      ),
                      _buildColumnHeaderLabel(
                        progressProvider,
                        bookDetails,
                        col,
                        columns.length,
                      ),
                      if (completedAt != null)
                        _buildColumnCompletionDate(theme, completedAt),
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

  /// מתי הושלמה העמודה, מתחת לשמה: התאריך העברי, ובתא רחב גם הלועזי. בתא
  /// שהתאריך המלא לא נכנס בו — יום וחודש בלי שנה; המלא תמיד ב-tooltip.
  Widget _buildColumnCompletionDate(ThemeData theme, DateTime completedAt) {
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final hebrew = HebrewUtils.hebrewDate(completedAt);
    return Tooltip(
      message: 'הושלם ${HebrewUtils.fullDate(completedAt)}',
      child: Padding(
        // Keeps neighbouring dates apart when narrow cells shrink them.
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceXS),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final painter = TextPainter(
              text: TextSpan(text: hebrew, style: style),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 1,
            )..layout();
            final fits = painter.width <= constraints.maxWidth;
            painter.dispose();
            // FittedBox רק כגיבוי, כשגם התאריך הקצר לא נכנס.
            return FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fits ? hebrew : HebrewUtils.hebrewDayMonth(completedAt),
                    style: style,
                  ),
                  if (constraints.maxWidth >= _kGregorianDateMinWidth)
                    Text(HebrewUtils.gregorianDate(completedAt), style: style),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// כותרת עמודה לחיצה - פותחת תפריט לשינוי שם או הסרת העמודה
  Widget _buildColumnHeaderLabel(
    ShamorZachorProgressProvider progressProvider,
    BookDetails bookDetails,
    ProgressColumn column,
    int columnCount,
  ) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'אפשרויות עמודה',
      child: AppPopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'range') {
            _markRange(progressProvider, bookDetails, column);
          } else if (value == 'rename') {
            _renameColumn(progressProvider, column);
          } else if (value == 'remove') {
            _removeColumn(progressProvider, column);
          }
        },
        entries: [
          const AppMenuEntry(
            value: 'range',
            label: 'סימון טווח',
            icon: FluentIcons.checkbox_checked_24_regular,
          ),
          const AppMenuEntry(
            value: 'rename',
            label: 'שנה שם',
            icon: FluentIcons.rename_24_regular,
          ),
          if (columnCount > 1)
            const AppMenuEntry(
              value: 'remove',
              label: 'הסר עמודה',
              icon: FluentIcons.delete_24_regular,
            ),
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  column.label,
                  style: TextStyle(
                    fontSize: AppTokens.fontSM,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              FluentIcons.chevron_down_24_regular,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addColumn(ShamorZachorProgressProvider progressProvider) async {
    if (widget.bookId == null) return;
    final name = await showInputDialog(
      context: context,
      title: 'הוספת עמודה',
      labelText: 'שם העמודה',
      confirmText: 'הוסף',
    );
    if (name == null || name.isEmpty) return;
    await progressProvider.addColumn(widget.bookId!, name);
  }

  Future<void> _markRange(
    ShamorZachorProgressProvider progressProvider,
    BookDetails bookDetails,
    ProgressColumn column,
  ) async {
    if (widget.bookId == null) return;
    final selection = await showMarkRangeDialog(
      context: context,
      bookDetails: bookDetails,
      columnLabel: column.label,
    );
    if (selection == null || !_isCurrentBook(bookDetails)) return;
    await progressProvider.toggleRangeForColumnById(
      widget.bookId!,
      bookDetails,
      column.id,
      selection.fromIndex,
      selection.toIndex,
      selection.value,
    );
  }

  Future<void> _renameColumn(
    ShamorZachorProgressProvider progressProvider,
    ProgressColumn column,
  ) async {
    if (widget.bookId == null) return;
    final name = await showInputDialog(
      context: context,
      title: 'שינוי שם עמודה',
      labelText: 'שם העמודה',
      initialValue: column.label,
    );
    if (name == null || name.isEmpty) return;
    await progressProvider.renameColumn(widget.bookId!, column.id, name);
  }

  Future<void> _removeColumn(
    ShamorZachorProgressProvider progressProvider,
    ProgressColumn column,
  ) async {
    if (widget.bookId == null) return;
    final confirmed = await showWarningDialog(
      context: context,
      title: 'הסרת עמודה',
      content: 'האם להסיר את העמודה "${column.label}"?',
      subtitle: 'הסימונים שנשמרו בעמודה זו יימחקו',
      cancelText: 'ביטול',
      confirmText: 'הסר',
    );
    if (confirmed != true) return;
    await progressProvider.removeColumn(widget.bookId!, column.id);
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

          final showHeader =
              bookDetails.hasMultipleParts == true &&
              (index == 0 || partName != learnableItems[index - 1].partName) &&
              partName != widget.bookName; // מניעת כפילות של שם הספר בכותרת חלק

          final rowLabel = HebrewUtils.pageLabel(
            item.pageNumber,
            item.amudKey,
            bookDetails.isDafType,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showHeader && partName.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  margin: const EdgeInsets.fromLTRB(
                    AppTokens.spaceSM,
                    AppTokens.spaceMD,
                    AppTokens.spaceSM,
                    AppTokens.spaceXS,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: AppTokens.borderRadiusAll,
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
                color: _rowColor(theme, bookDetails, absoluteIndex),
                padding: EdgeInsets.fromLTRB(_gridHPad, 2, _rightInset, 2),
                child: Row(
                  children: [
                    Expanded(
                      flex: _titleFlex,
                      child: Text(
                        rowLabel,
                        style: TextStyle(
                          fontSize: AppTokens.fontLG,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: _gridFlex,
                      child: _buildItemCheckboxes(
                        progressProvider,
                        bookDetails,
                        absoluteIndex,
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

  /// פסים מתחלפים: בספר דפים — זוג עמודים (עמוד א+ב) לכל פס.
  Color _rowColor(ThemeData theme, BookDetails bookDetails, int index) {
    final band = bookDetails.isDafType == true ? 2 : 1;
    return index % (2 * band) < band
        ? Colors.transparent
        : theme.colorScheme.primaryContainer.withValues(alpha: 0.25);
  }

  Widget _buildItemCheckboxes(
    ShamorZachorProgressProvider progressProvider,
    BookDetails bookDetails,
    int absoluteIndex, {
    bool shrinkTapTarget = false,
  }) {
    final pageProgress = _getProgress(progressProvider, absoluteIndex);
    return Row(
      children: _columnsOf(progressProvider).map((col) {
        final columnName = col.id;
        return Expanded(
          child: Tooltip(
            message: col.label,
            child: Checkbox(
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: shrinkTapTarget
                  ? MaterialTapTargetSize.shrinkWrap
                  : null,
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
    );
  }

  Widget _buildNestedItemsSliver(
    BuildContext context,
    BookDetails bookDetails,
    ShamorZachorProgressProvider progressProvider,
  ) {
    // רשימה שטוחה של השורות הגלויות, כדי שה-SliverList יבנה רק את מה שעל המסך.
    final rows = <(BookSection, int)>[];
    void addRow(BookSection section, int level) {
      rows.add((section, level));
      if (_expandedSections[section.id] ?? true) {
        for (final child in section.children) {
          addRow(child, level + 1);
        }
      }
    }

    for (final section in bookDetails.sections ?? const <BookSection>[]) {
      // כותרת זהה לשם הספר (שכבר מופיע למעלה) — מציגים ישירות את ילדיה.
      final skip =
          section.title == widget.bookName && section.children.isNotEmpty;
      for (final top in skip ? section.children : [section]) {
        addRow(top, 0);
      }
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (ctx, index) => _buildSectionExpansionTile(
          context,
          rows[index].$1,
          rows[index].$2,
          bookDetails,
          progressProvider,
        ),
        childCount: rows.length,
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

      final learnable = bookDetails.learnableItems[leafIndices.first];

      // מציגים leaf בפורמט של שורה רגילה (כמו ב-flat), עם RTL
      return Container(
        color: _rowColor(theme, bookDetails, learnable.absoluteIndex),
        padding: EdgeInsets.fromLTRB(_gridHPad, 2, _rightInset, 2),
        child: Row(
          children: [
            Expanded(
              flex: _titleFlex,
              child: Text(
                learnable.displayLabel ?? learnable.partName,
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
              child: _buildItemCheckboxes(
                progressProvider,
                bookDetails,
                learnable.absoluteIndex,
                shrinkTapTarget: level > 0,
              ),
            ),
          ],
        ),
      );
    }

    // Parent: TreeSectionHeader במקום ExpansionTile עם Theme מקומי (q10 Q8d).
    // השורה כולה פותחת וסוגרת, החץ יושב ברוחב שההלכות משאירות ריק בתחילתן,
    // ולכן העמודות מיושרות. התיבות בצפיפות של שורת הלכה מקוננת.
    // Material ולא ColoredBox, כדי שהדיו של השורה ייצבע מעל הגוון.
    return Material(
      color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.4),
      child: TreeSectionHeader(
        key: ValueKey(section.id),
        isExpanded: isExpanded,
        onToggle: () =>
            setState(() => _expandedSections[section.id] = !isExpanded),
        leadingExtent: _chevronReserve + _titleGutter,
        padding: const EdgeInsets.symmetric(
          horizontal: _gridHPad,
          vertical: AppTokens.space2XS,
        ),
        child: Row(
          children: [
            Expanded(
              flex: _titleFlex,
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  start: _levelIndent * level,
                ),
                child: Text(
                  section.title,
                  style: _headingStyle.copyWith(
                    fontWeight: FontWeight.w700,
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
                children: _columnsOf(progressProvider).map((col) {
                  final bookId = widget.bookId;
                  final state = bookId == null
                      ? false
                      : progressProvider.getSectionColumnStateById(
                          bookId,
                          bookDetails,
                          section.id,
                          col.id,
                        );
                  return Expanded(
                    child: Tooltip(
                      message: col.label,
                      child: Checkbox(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        value: state,
                        tristate: true,
                        // בלי bookId אין לאן לשמור, ולכן התיבה מושבתת.
                        onChanged: bookId == null
                            ? null
                            : (value) async {
                                if (!_isCurrentBook(bookDetails)) return;
                                await progressProvider.toggleSectionColumnById(
                                  bookId,
                                  bookDetails,
                                  section.id,
                                  col.id,
                                  value == true,
                                );
                              },
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
}
