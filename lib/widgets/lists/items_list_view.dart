import 'package:otzaria/widgets/lists/list_icon_badge.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/widgets/misc/app_context_menu.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/feedback/scrollable_positioned_list_scrollbar.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/lists/list_search_match.dart';
import 'package:positioned_sliver_list/positioned_list.dart';

/// שורה ברשימה המוצגת: כותרת קבוצה או פריט. הרשימה משוטחת כדי לאפשר
/// וירטואליזציה — נבנות רק השורות הנראות.
class _ListRow {
  final String? headerTitle;
  final MapEntry<int, dynamic>? entry;
  final bool isFirstInGroup;
  final bool isLastInGroup;

  const _ListRow.header(this.headerTitle)
    : entry = null,
      isFirstInGroup = false,
      isLastInGroup = false;

  const _ListRow.item(
    MapEntry<int, dynamic> this.entry, {
    required this.isFirstInGroup,
    required this.isLastInGroup,
  }) : headerTitle = null;

  bool get isHeader => entry == null;
}

class ItemsListView extends StatefulWidget {
  final List<dynamic> items;
  final Function(BuildContext, dynamic, int originalIndex) onItemTap;
  final Function(BuildContext, int originalIndex) onDelete;
  final Function(BuildContext) onClearAll;

  /// כשמסופק, מתווסף לתפריט ההקשר פריט "ערוך תיאור".
  final Function(BuildContext, dynamic item, int originalIndex)? onEdit;
  final String hintText;
  final String emptyText;
  final String notFoundText;
  final String clearAllText;

  /// אייקון שדה החיפוש ומצבי הריק — ממוקד לפי מה שמסתנן ברשימה.
  final IconData searchIcon;

  final Widget? Function(dynamic item)? leadingIconBuilder;
  final String? Function(dynamic item)? subtitleBuilder;
  final String? Function(dynamic item)? subtitleTooltipBuilder;
  final String Function(dynamic item)? searchKeyBuilder;

  /// כותרת הספר בלבד — כתיב חלופי אינו חל על מיקום פנימי או חיפוש שמור.
  final String? Function(dynamic item)? searchTitleBuilder;
  final bool Function(dynamic item)? additionalFilter;

  /// כינויים נוספים שהחיפוש מתאים להם (מנורמלים כמו באיתור מקורות).
  /// null — עוד לא זמינים, וינוסו שוב בהקלדה הבאה.
  final List<String>? Function(dynamic item)? searchAliasesBuilder;

  /// false — בזמן חיפוש התוצאות מוצגות לפי דרגת ההתאמה בלי כותרות קבוצה.
  final bool groupWhileSearching;

  /// כשמסופק, מוצג בצד שדה החיפוש באותה שורה (למשל כפתור מיון).
  final Widget? searchFieldTrailing;

  /// FocusNode חיצוני לשדה החיפוש — מאפשר למשתמש החיצוני לקרוא
  /// [requestFocus] לאחר פעולה (סינון, מיון) ולהחזיר את הפוקוס לחיפוש.
  final FocusNode? searchFocusNode;

  /// כשמסופק, מחזיר את הכותרת הראשית של הפריט. ברירת מחדל — `item.book.title`.
  /// תן callback כדי לתמוך בפריטים שאינם בנויים סביב `book`.
  final String Function(dynamic item)? titleBuilder;

  /// כשמסופק ומחזיר span שאינו null — הכותרת מרונדרת כ-[Text.rich] לעיצוב
  /// מובחן של חלקיה; אחרת נופל ל-[titleBuilder].
  final InlineSpan? Function(dynamic item)? titleSpanBuilder;

  /// כשמסופק, הפריטים יקובצו לפי המפתח המוחזר.
  /// מפתח null מטופל כמחרוזת ריקה.
  final String? Function(dynamic item)? groupKeyBuilder;

  /// מחזיר את כותרת הקבוצה לפי הפריט הראשון בה.
  /// null = ללא כותרת עבור אותה קבוצה.
  final String? Function(dynamic firstItemInGroup)? groupTitleBuilder;

  /// כשמסופק, הפריטים ימוינו לפי הפונקציה הזו לפני קיבוץ והצגה.
  /// האינדקס המקורי (originalIndex) נשמר גם אחרי מיון.
  final Comparator<dynamic>? itemSortComparator;

  const ItemsListView({
    super.key,
    required this.items,
    required this.onItemTap,
    required this.onDelete,
    required this.onClearAll,
    this.onEdit,
    required this.hintText,
    required this.emptyText,
    required this.notFoundText,
    required this.clearAllText,
    this.searchIcon = OtzariaIcons.search_24_regular,
    this.leadingIconBuilder,
    this.subtitleBuilder,
    this.subtitleTooltipBuilder,
    this.searchKeyBuilder,
    this.searchTitleBuilder,
    this.additionalFilter,
    this.searchAliasesBuilder,
    this.groupWhileSearching = true,
    this.searchFieldTrailing,
    this.searchFocusNode,
    this.groupKeyBuilder,
    this.groupTitleBuilder,
    this.itemSortComparator,
    this.titleBuilder,
    this.titleSpanBuilder,
  });

  /// כותרת המיקום בתוך הספר — חותך את שם הספר מ-ref.
  /// fallback: "תחילת הספר" (index 0), "עמוד X" (PDF), "פסקה X" (טקסט).
  static String? locationSubtitle(dynamic item) {
    final ref = item.ref as String;
    final bookTitle = item.book.title as String;

    String location;
    if (ref == bookTitle) {
      location = '';
    } else if (ref.startsWith('$bookTitle, ')) {
      location = ref.substring('$bookTitle, '.length);
    } else if (ref.startsWith('$bookTitle ')) {
      location = ref.substring('$bookTitle '.length);
    } else {
      location = ref;
    }

    if (location.isEmpty) {
      if (item.index as int == 0) return 'תחילת הספר';
      if (item.book is PdfBook) return 'עמוד ${item.index as int}';
      return 'פסקה ${item.index as int}';
    }
    return location;
  }

  @override
  State<ItemsListView> createState() => _ItemsListViewState();
}

class _ItemsListViewState extends State<ItemsListView> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _internalSearchFocusNode = FocusNode();
  FocusNode get _searchFocusNode =>
      widget.searchFocusNode ?? _internalSearchFocusNode;
  String _searchQuery = '';

  int _focusedOriginalIndex = -1;
  List<MapEntry<int, dynamic>> _displayEntries = [];
  List<_ListRow> _displayRows = const [];
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();

  /// קאש לרשימה הממוינת — חישוב המיון (O(n log n)) רץ רק כשהקלט משתנה,
  /// לא בכל הקלדה בשדה החיפוש (שעושה רק filter על הקאש).
  List<dynamic>? _cachedItemsForSort;
  Comparator<dynamic>? _cachedComparator;
  List<MapEntry<int, dynamic>>? _cachedSortedEntries;

  /// מפתחות מוכנים לפי האינדקס המקורי; נרמול חוזר רק כשהטקסט או הכינויים משתנים.
  List<dynamic>? _searchKeysItems;
  List<ListSearchKey?> _searchKeys = const [];

  List<MapEntry<int, dynamic>> _getSortedEntries() {
    final comparator = widget.itemSortComparator;
    if (identical(_cachedItemsForSort, widget.items) &&
        identical(_cachedComparator, comparator)) {
      return _cachedSortedEntries!;
    }
    final entries = widget.items.asMap().entries.toList();
    if (comparator != null) {
      entries.sort((a, b) => comparator(a.value, b.value));
    }
    _cachedItemsForSort = widget.items;
    _cachedComparator = comparator;
    _cachedSortedEntries = entries;
    return entries;
  }

  Widget _buildInlineSubtitle(
    BuildContext context,
    String text,
    String? tooltip,
  ) {
    final cs = Theme.of(context).colorScheme;

    final subtitleWidget = Text(
      text,
      style: TextStyle(
        fontSize: AppTokens.fontMD,
        color: cs.onSurfaceVariant,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    final tooltipMessage = tooltip?.trim();
    if (tooltipMessage == null || tooltipMessage.isEmpty) {
      return subtitleWidget;
    }

    return Tooltip(
      message: tooltipMessage,
      waitDuration: const Duration(milliseconds: 250),
      showDuration: const Duration(seconds: 4),
      preferBelow: false,
      verticalOffset: 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      constraints: const BoxConstraints(maxWidth: 360),
      textStyle: TextStyle(
        fontSize: 13,
        height: 1.4,
        color: cs.onSurface,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: AppTokens.borderRadiusAll,
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.55),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: subtitleWidget,
    );
  }

  Widget _buildItemRow(
    BuildContext context,
    dynamic item,
    int originalIndex, {
    bool isKeyboardFocused = false,
  }) {
    final subtitle = widget.subtitleBuilder?.call(item);
    final subtitleTooltip = widget.subtitleTooltipBuilder?.call(item);
    final titleSpan = widget.titleSpanBuilder?.call(item);
    final cs = Theme.of(context).colorScheme;
    final titleStyle = TextStyle(
      fontSize: AppTokens.fontLG,
      fontWeight: FontWeight.bold,
      color: cs.primary,
    );

    Widget content = InkWell(
      onTap: () => widget.onItemTap(context, item, originalIndex),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMD,
          vertical: AppTokens.spaceMD - 4,
        ),
        child: Row(
          children: [
            if (widget.leadingIconBuilder?.call(item) case final leadingIcon?)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  end: AppTokens.spaceMD,
                ),
                child: ListIconBadge(icon: leadingIcon),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (titleSpan != null)
                    Text.rich(titleSpan, style: titleStyle)
                  else
                    Text(
                      widget.titleBuilder?.call(item) ??
                          item.book.title as String,
                      style: titleStyle,
                    ),
                  if (subtitle != null)
                    _buildInlineSubtitle(context, subtitle, subtitleTooltip),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                FluentIcons.delete_24_regular,
                color: cs.onSurfaceVariant,
              ),
              tooltip: 'מחק',
              onPressed: () => widget.onDelete(context, originalIndex),
            ),
          ],
        ),
      ),
    );

    if (isKeyboardFocused) {
      content = ColoredBox(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: content,
      );
    }

    final onEdit = widget.onEdit;
    if (onEdit == null) {
      return content;
    }

    return AppContextMenuRegion(
      menuBuilder: (menuContext, _) => [
        AppContextMenuEntry(
          label: 'ערוך תיאור',
          icon: FluentIcons.edit_24_regular,
          onTap: () => onEdit(menuContext, item, originalIndex),
        ),
        AppContextMenuEntry(
          label: 'מחק',
          icon: FluentIcons.delete_24_regular,
          isDestructive: true,
          onTap: () => widget.onDelete(menuContext, originalIndex),
        ),
      ],
      child: content,
    );
  }

  /// משטח את הפריטים (עם כותרות קבוצה אם יש) לרשימת שורות לצורך
  /// וירטואליזציה. הקיבוץ שומר על סדר ההופעה הראשון.
  List<_ListRow> _buildDisplayRows(
    List<MapEntry<int, dynamic>> entries, {
    required bool grouped,
  }) {
    List<List<MapEntry<int, dynamic>>> groups;
    if (!grouped) {
      groups = [entries];
    } else {
      final grouped = <String, List<MapEntry<int, dynamic>>>{};
      for (final entry in entries) {
        final key = widget.groupKeyBuilder!(entry.value) ?? '';
        (grouped[key] ??= []).add(entry);
      }
      groups = grouped.values.toList();
    }

    final rows = <_ListRow>[];
    for (final group in groups) {
      if (grouped) {
        rows.add(
          _ListRow.header(
            widget.groupTitleBuilder?.call(group.first.value),
          ),
        );
      }
      for (var i = 0; i < group.length; i++) {
        rows.add(
          _ListRow.item(
            group[i],
            isFirstInGroup: i == 0,
            isLastInGroup: i == group.length - 1,
          ),
        );
      }
    }
    return rows;
  }

  Widget _buildHeaderRow(BuildContext context, String? title) {
    if (title == null || title.isEmpty) {
      return const SizedBox(height: 12);
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        top: AppTokens.spaceMD,
        bottom: AppTokens.spaceSM,
      ),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  /// שורת פריט בסגנון [AppCard.section]: רקע כרטיס, פינות מעוגלות בקצות
  /// הקבוצה ורווח [AppCard.sectionSpacing] בין שורות — נבנית שורה-שורה כדי
  /// שהרשימה תישאר וירטואלית.
  Widget _buildCardRow(BuildContext context, _ListRow row) {
    final entry = row.entry!;
    Widget content = Material(
      color: AppSurfaces.card(context),
      child: _buildItemRow(
        context,
        entry.value,
        entry.key,
        isKeyboardFocused: entry.key == _focusedOriginalIndex,
      ),
    );

    const radius = Radius.circular(AppTokens.radius);
    content = ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: row.isFirstInGroup ? radius : Radius.zero,
        bottom: row.isLastInGroup ? radius : Radius.zero,
      ),
      child: content,
    );

    if (!row.isLastInGroup) {
      content = Padding(
        padding: const EdgeInsets.only(bottom: AppCard.sectionSpacing),
        child: content,
      );
    }
    return content;
  }

  Widget _buildRowsList(BuildContext context, List<_ListRow> rows) {
    return ScrollablePositionedListScrollbar(
      scrollController: _itemScrollController,
      itemCount: rows.length,
      child: ScrollablePositionedList.builder(
        itemScrollController: _itemScrollController,
        itemPositionsListener: _itemPositionsListener,
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          return row.isHeader
              ? _buildHeaderRow(context, row.headerTitle)
              : _buildCardRow(context, row);
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
        _focusedOriginalIndex = -1;
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _moveFocusDown() {
    if (_displayEntries.isEmpty) return;
    setState(() {
      if (_focusedOriginalIndex == -1) {
        _focusedOriginalIndex = _displayEntries.first.key;
      } else {
        final idx = _displayEntries.indexWhere(
          (e) => e.key == _focusedOriginalIndex,
        );
        if (idx >= 0 && idx < _displayEntries.length - 1) {
          _focusedOriginalIndex = _displayEntries[idx + 1].key;
        }
      }
    });
    _ensureFocusedVisible();
  }

  void _moveFocusUp() {
    if (_focusedOriginalIndex == -1) return;
    final idx = _displayEntries.indexWhere(
      (e) => e.key == _focusedOriginalIndex,
    );
    setState(() {
      if (idx <= 0) {
        _focusedOriginalIndex = -1;
      } else {
        _focusedOriginalIndex = _displayEntries[idx - 1].key;
      }
    });
    if (idx > 0) _ensureFocusedVisible();
  }

  void _activateFocusedItem(BuildContext context) {
    if (_focusedOriginalIndex == -1) return;
    final matches = _displayEntries.where(
      (e) => e.key == _focusedOriginalIndex,
    );
    if (matches.isEmpty) return;
    final entry = matches.first;
    widget.onItemTap(context, entry.value, entry.key);
  }

  void _ensureFocusedVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_itemScrollController.isAttached) return;
      final rowIndex = _displayRows.indexWhere(
        (row) => !row.isHeader && row.entry!.key == _focusedOriginalIndex,
      );
      if (rowIndex == -1) return;
      // אם השורה כבר נראית במלואה — אין מה לגלול.
      for (final position in _itemPositionsListener.itemPositions.value) {
        if (position.index == rowIndex &&
            position.itemLeadingEdge >= 0.0 &&
            position.itemTrailingEdge <= 1.0) {
          return;
        }
      }
      _itemScrollController.scrollTo(
        index: rowIndex,
        alignment: 0.4,
        duration: const Duration(milliseconds: 150),
      );
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _internalSearchFocusNode.dispose();
    super.dispose();
  }

  /// הפריטים התואמים לחיפוש, לפי דרגת ההתאמה ובתוך דרגה — לפי הסדר הממוין.
  List<MapEntry<int, dynamic>> _rankedEntries(
    List<MapEntry<int, dynamic>> sortedEntries,
    bool Function(dynamic item)? additionalFilter,
  ) {
    if (!identical(_searchKeysItems, widget.items)) {
      _searchKeysItems = widget.items;
      _searchKeys = List<ListSearchKey?>.filled(widget.items.length, null);
    }
    final query = ListSearchQuery(_searchQuery);
    final aliasesBuilder = widget.searchAliasesBuilder;
    final buckets = List.generate(
      listSearchRankCount,
      (_) => <MapEntry<int, dynamic>>[],
    );
    for (var i = 0; i < sortedEntries.length; i++) {
      final entry = sortedEntries[i];
      final item = entry.value;
      if (additionalFilter != null && !additionalFilter(item)) continue;
      final raw =
          widget.searchKeyBuilder?.call(item) ?? item.ref?.toString() ?? '';
      final title = widget.searchTitleBuilder?.call(item);
      var key = _searchKeys[entry.key];
      if (key == null || key.raw != raw || key.bookTitle != title) {
        key = _searchKeys[entry.key] = ListSearchKey(raw, bookTitle: title);
      }
      key.setAliases(aliasesBuilder?.call(item));
      final rank = listSearchRank(query, key);
      if (rank != null) buckets[rank].add(entry);
    }
    return [for (final bucket in buckets) ...bucket];
  }

  @override
  Widget build(BuildContext context) {
    final additionalFilter = widget.additionalFilter;
    final hasAnyMatching = additionalFilter == null
        ? widget.items.isNotEmpty
        : widget.items.any(additionalFilter);
    if (!hasAnyMatching) {
      return OtzariaEmptyState(
        icon: widget.searchIcon,
        title: widget.emptyText,
      );
    }

    // המיון מבוצע פעם אחת על widget.items (מקושש), והסינון רץ מעליו
    // בכל הקלדה — O(n) במקום O(n log n) על כל תו.
    final sortedEntries = _getSortedEntries();
    final displayEntries = _searchQuery.isEmpty
        ? [
            for (final entry in sortedEntries)
              if (additionalFilter == null || additionalFilter(entry.value))
                entry,
          ]
        : _rankedEntries(sortedEntries, additionalFilter);

    _displayRows = _buildDisplayRows(
      displayEntries,
      grouped:
          widget.groupKeyBuilder != null &&
          (widget.groupWhileSearching || _searchQuery.isEmpty),
    );
    // החצים ו-Enter עוברים על הסדר החזותי, שהקיבוץ עשוי לשנות.
    _displayEntries = [
      for (final row in _displayRows)
        if (!row.isHeader) row.entry!,
    ];
    if (_focusedOriginalIndex != -1 &&
        !displayEntries.any((e) => e.key == _focusedOriginalIndex)) {
      _focusedOriginalIndex = -1;
    }

    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _moveFocusDown();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _moveFocusUp();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter &&
            _focusedOriginalIndex != -1) {
          _activateFocusedItem(context);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Builder(
              builder: (context) {
                final searchField = OtzariaSearchField(
                  controller: _searchController,
                  icon: widget.searchIcon,
                  focusNode: _searchFocusNode,
                  hintText: widget.hintText,
                  onClear: () {
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                );
                if (widget.searchFieldTrailing == null) return searchField;
                return Row(
                  children: [
                    Expanded(child: searchField),
                    widget.searchFieldTrailing!,
                  ],
                );
              },
            ),
          ),
          Expanded(
            child: displayEntries.isEmpty
                ? OtzariaEmptyState(
                    isCompact: true,
                    icon: widget.searchIcon,
                    title: widget.notFoundText,
                  )
                : _buildRowsList(context, _displayRows),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ActionButton.neutral(
              text: widget.clearAllText,
              onPressed: () => widget.onClearAll(context),
            ),
          ),
        ],
      ),
    );
  }
}
