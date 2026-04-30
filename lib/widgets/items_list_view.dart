import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

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
  });

  @override
  State<ItemsListView> createState() => _ItemsListViewState();
}

class _ItemsListViewState extends State<ItemsListView> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  late List<String> _lowerCasedRefs;

  @override
  void initState() {
    super.initState();
    _lowerCasedRefs = widget.items.map((item) => (item.ref as String).toLowerCase()).toList();
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
  void didUpdateWidget(ItemsListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.items, widget.items)) {
      _lowerCasedRefs = widget.items.map((item) => (item.ref as String).toLowerCase()).toList();
    }
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
    List<int> filteredIndices;
    if (_searchQuery.isEmpty) {
      filteredIndices = List.generate(widget.items.length, (i) => i);
    } else {
      final queryLower = _searchQuery.toLowerCase();
      filteredIndices = [
        for (int i = 0; i < widget.items.length; i++)
          if (_lowerCasedRefs[i].contains(queryLower)) i,
      ];
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
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
          child: filteredIndices.isEmpty
              ? Center(child: Text(widget.notFoundText))
              : ListView.builder(
                  itemCount: filteredIndices.length,
                  itemBuilder: (context, index) {
                    final originalIndex = filteredIndices[index];
                    final item = widget.items[originalIndex];
                    return ListTile(
                      leading: widget.leadingIconBuilder?.call(item),
                      title: Text(item.ref),
                      onTap: () =>
                          widget.onItemTap(context, item, originalIndex),
                      trailing: IconButton(
                        icon: const Icon(FluentIcons.delete_24_regular),
                        onPressed: () =>
                            widget.onDelete(context, originalIndex),
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
