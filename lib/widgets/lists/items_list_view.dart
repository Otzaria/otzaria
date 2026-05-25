import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

class ItemsListView extends StatefulWidget {
  final List<dynamic> items;
  final Function(BuildContext, dynamic, int originalIndex) onItemTap;
  final Function(BuildContext, int originalIndex) onDelete;
  final Function(BuildContext) onClearAll;
  final String hintText;
  final String emptyText;
  final String notFoundText;
  final String clearAllText;
  final Widget? Function(dynamic item)? leadingIconBuilder;
  final String? Function(dynamic item)? subtitleBuilder;
  final String? Function(dynamic item)? subtitleTooltipBuilder;
  final String Function(dynamic item)? searchKeyBuilder;
  final bool Function(dynamic item)? additionalFilter;

  /// כשמסופק, מחזיר את הכותרת הראשית של הפריט. ברירת מחדל — `item.book.title`.
  /// תן callback כדי לתמוך בפריטים שאינם בנויים סביב `book`.
  final String Function(dynamic item)? titleBuilder;

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
    required this.hintText,
    required this.emptyText,
    required this.notFoundText,
    required this.clearAllText,
    this.leadingIconBuilder,
    this.subtitleBuilder,
    this.subtitleTooltipBuilder,
    this.searchKeyBuilder,
    this.additionalFilter,
    this.groupKeyBuilder,
    this.groupTitleBuilder,
    this.itemSortComparator,
    this.titleBuilder,
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
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  /// קאש לרשימה הממוינת — חישוב המיון (O(n log n)) רץ רק כשהקלט משתנה,
  /// לא בכל הקלדה בשדה החיפוש (שעושה רק filter על הקאש).
  List<dynamic>? _cachedItemsForSort;
  Comparator<dynamic>? _cachedComparator;
  List<MapEntry<int, dynamic>>? _cachedSortedEntries;

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
      style: const TextStyle(fontSize: 16),
      textDirection: TextDirection.rtl,
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
        borderRadius: BorderRadius.circular(14),
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
    int originalIndex,
  ) {
    final subtitle = widget.subtitleBuilder?.call(item);
    final subtitleTooltip = widget.subtitleTooltipBuilder?.call(item);

    return InkWell(
      onTap: () => widget.onItemTap(context, item, originalIndex),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            if (widget.leadingIconBuilder?.call(item) case final leadingIcon?)
              Padding(
                padding: const EdgeInsets.only(left: 12.0),
                child: leadingIcon,
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.titleBuilder?.call(item) ??
                        item.book.title as String,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                  if (subtitle != null)
                    _buildInlineSubtitle(context, subtitle, subtitleTooltip),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(FluentIcons.delete_24_regular),
              tooltip: 'מחק',
              onPressed: () => widget.onDelete(context, originalIndex),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(
    BuildContext context,
    List<MapEntry<int, dynamic>> entries,
  ) {
    return AppCard.section(
      children: [
        for (final entry in entries)
          _buildItemRow(context, entry.value, entry.key),
      ],
    );
  }

  Widget _buildGroupedList(
    BuildContext context,
    List<MapEntry<int, dynamic>> filteredEntries,
  ) {
    final theme = Theme.of(context);

    // קיבוץ תוך שמירה על סדר ההופעה הראשון
    final groups = <String, List<MapEntry<int, dynamic>>>{};
    for (final entry in filteredEntries) {
      final key = widget.groupKeyBuilder!(entry.value) ?? '';
      (groups[key] ??= []).add(entry);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        for (final group in groups.entries) ...[
          Builder(
            builder: (context) {
              final title =
                  widget.groupTitleBuilder?.call(group.value.first.value);
              if (title == null || title.isEmpty) {
                return const SizedBox(height: 12);
              }
              return Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 8),
                child: Text(
                  title,
                  textDirection: TextDirection.rtl,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              );
            },
          ),
          _buildGroupCard(context, group.value),
        ],
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final additionalFilter = widget.additionalFilter;
    final hasAnyMatching = additionalFilter == null
        ? widget.items.isNotEmpty
        : widget.items.any(additionalFilter);
    if (!hasAnyMatching) {
      return Center(
        child: Text(
          widget.emptyText,
          textDirection: TextDirection.rtl,
        ),
      );
    }

    // המיון מבוצע פעם אחת על widget.items (מקושש), והסינון רץ מעליו
    // בכל הקלדה — O(n) במקום O(n log n) על כל תו.
    final sortedEntries = _getSortedEntries();
    final lowerQuery = _searchQuery.toLowerCase();
    final displayEntries = sortedEntries.where((entry) {
      final item = entry.value;
      if (widget.additionalFilter != null && !widget.additionalFilter!(item)) {
        return false;
      }
      if (lowerQuery.isEmpty) return true;
      final searchText =
          widget.searchKeyBuilder?.call(item) ?? item.ref?.toString() ?? '';
      return searchText.toLowerCase().contains(lowerQuery);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: OtzariaSearchField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            hintText: widget.hintText,
            onClear: () {
              setState(() {
                _searchQuery = '';
              });
            },
          ),
        ),
        Expanded(
          child: displayEntries.isEmpty
              ? Center(
                  child: Text(
                    widget.notFoundText,
                    textDirection: TextDirection.rtl,
                  ),
                )
              : widget.groupKeyBuilder != null
                  ? _buildGroupedList(context, displayEntries)
                  : ListView.builder(
                      itemCount: displayEntries.length,
                      itemBuilder: (context, index) {
                        final entry = displayEntries[index];
                        return _buildItemRow(
                          context,
                          entry.value,
                          entry.key,
                        );
                      },
                    ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: NeutralActionButton(
            text: widget.clearAllText,
            onPressed: () => widget.onClearAll(context),
          ),
        ),
      ],
    );
  }
}
