import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';

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
      return Center(child: Text(widget.emptyText));
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
          child: RtlTextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              hintText: widget.hintText,
              prefixIcon: const Icon(FluentIcons.search_24_regular),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(FluentIcons.dismiss_24_regular),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
            ),
          ),
        ),
        Expanded(
          child: filteredItems.isEmpty
              ? Center(child: Text(widget.notFoundText))
              : ListView.builder(
                  itemCount: filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = filteredItems[index];
                    final originalIndex = widget.items.indexOf(item);
                    final centerText = widget.subtitleBuilder?.call(item);
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
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0),
                                child: Text(
                                  centerText,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                  textDirection: TextDirection.rtl,
                                ),
                              ),
                            IconButton(
                              icon: const Icon(FluentIcons.delete_24_regular),
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
          child: ElevatedButton(
            onPressed: () => widget.onClearAll(context),
            child: Text(widget.clearAllText),
          ),
        ),
      ],
    );
  }
}
