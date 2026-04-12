import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/localization/app_localizations.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/widgets/otzaria_search_field.dart';

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
  });

  @override
  State<ItemsListView> createState() => _ItemsListViewState();
}

class _ItemsListViewState extends State<ItemsListView> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });

    // Auto-focus the search field when the screen opens
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
    if (widget.items.isEmpty) {
      return Center(
        child: Text(
          context.trLiteral(widget.emptyText),
          textDirection:
              context.isEnglishMode ? TextDirection.ltr : TextDirection.rtl,
        ),
      );
    }

    // Filter items based on search query
    final filteredItems = _searchQuery.isEmpty
        ? widget.items
        : widget.items
            .where((item) =>
                item.ref.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: OtzariaSearchField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            hintText: context.trLiteral(widget.hintText),
            onClear: () {
              setState(() {
                _searchQuery = '';
              });
            },
          ),
        ),
        Expanded(
          child: filteredItems.isEmpty
              ? Center(
                  child: Text(
                    context.trLiteral(widget.notFoundText),
                    textDirection: context.isEnglishMode
                        ? TextDirection.ltr
                        : TextDirection.rtl,
                  ),
                )
              : ListView.builder(
                  itemCount: filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = filteredItems[index];
                    final originalIndex = widget.items.indexOf(item);
                    final centerText = widget.subtitleBuilder?.call(item);
                    final centerTooltip =
                        widget.subtitleTooltipBuilder?.call(item);
                    return InkWell(
                      onTap: () =>
                          widget.onItemTap(context, item, originalIndex),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 12.0),
                        child: Row(
                          children: [
                            if (widget.leadingIconBuilder?.call(item) != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 12.0),
                                child: widget.leadingIconBuilder!.call(item),
                              ),
                            Expanded(
                              child: Text(
                                item.ref,
                                style: const TextStyle(fontSize: 16),
                                textDirection: TextDirection.rtl,
                              ),
                            ),
                            if (centerText != null)
                              Tooltip(
                                message: centerTooltip == null
                                    ? ''
                                    : context.trLiteral(centerTooltip),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16.0),
                                  child: Text(
                                    context.trLiteral(centerText),
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.6),
                                    ),
                                    textDirection: context.isEnglishMode
                                        ? TextDirection.ltr
                                        : TextDirection.rtl,
                                  ),
                                ),
                              ),
                            IconButton(
                              icon: const Icon(FluentIcons.delete_24_regular),
                              tooltip: context.trLiteral('מחק'),
                              onPressed: () =>
                                  widget.onDelete(context, originalIndex),
                            ),
                          ],
                        ),
                      ),
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
