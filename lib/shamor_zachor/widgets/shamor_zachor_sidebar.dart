import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:provider/provider.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';
import 'package:otzaria/widgets/thin_divider.dart';
import 'package:otzaria/widgets/navigation_tree_tile.dart';
import '../providers/shamor_zachor_data_provider.dart';
import '../models/book_model.dart';

class ShamorZachorSidebar extends StatefulWidget {
  // Updated callback signature to include Top Level Name
  final Function(
          String categoryName, BookCategory category, String topLevelName)
      onCategorySelected;
  final Function(String searchQuery)? onSearchChanged;
  final String? selectedCategoryName;

  const ShamorZachorSidebar({
    super.key,
    required this.onCategorySelected,
    this.onSearchChanged,
    this.selectedCategoryName,
  });

  @override
  State<ShamorZachorSidebar> createState() => _ShamorZachorSidebarState();
}

class _ShamorZachorSidebarState extends State<ShamorZachorSidebar> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Map<String, bool> _expansionState = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
    });
    // Notify parent about search query change
    widget.onSearchChanged?.call(value);
  }

  void _toggleCategory(String categoryPath) {
    setState(() {
      _expansionState[categoryPath] = !(_expansionState[categoryPath] ?? false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          // Search Field
          _buildSearchField(),
          const ThinDivider(),
          // Content Tree
          Expanded(
            child: Consumer<ShamorZachorDataProvider>(
              builder: (context, dataProvider, child) {
                if (dataProvider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (dataProvider.error != null) {
                  return Center(
                    child: Text(
                      'שגיאה בטעינת נתונים',
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  );
                }

                // Always show category tree, search results will be shown in main area
                return _buildCategoryTree(dataProvider);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      alignment: Alignment.center,
      child: RtlTextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'חפש...',
          prefixIcon: const Icon(FluentIcons.search_24_regular),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                  icon: const Icon(FluentIcons.dismiss_24_regular),
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withAlpha(100),
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  Widget _buildCategoryTree(ShamorZachorDataProvider dataProvider) {
    final allCategories = dataProvider.allBookData;
    // Use natural order from DataProvider (already sorted by orderIndex from DB)
    final sortedKeys = allCategories.keys.toList();

    // Create 'All Books' as a parent node wrapper
    final allBooksCategory = BookCategory(
        name: 'כל הספרים',
        books: {},
        subcategories: sortedKeys.map((key) => allCategories[key]!).toList(),
        isCustom: false,
        sourceFile: 'virtual',
        schemaVersion: 1,
        contentType: 'text',
        defaultStartPage: 1);

    final isAllBooksExpanded = _expansionState['all_books_virtual'] ?? true;
    final isAllBooksSelected =
        widget.selectedCategoryName == 'all_books_virtual' ||
            widget.selectedCategoryName == 'כל הספרים';

    return ListView(
      children: [
        // All Books Root Node
        Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NavigationTreeTile.category(
                title: 'כל הספרים',
                level: 0,
                isSelected: isAllBooksSelected,
                isExpanded: isAllBooksExpanded,
                hasChildren: true,
                onTap: () {
                  widget.onCategorySelected(
                      'כל הספרים', allBooksCategory, 'all_books_virtual');
                },
                onToggleExpand: () => _toggleCategory('all_books_virtual'),
              ),
              if (isAllBooksExpanded)
                ...sortedKeys.map((key) {
                  final category = allCategories[key]!;
                  // Start standard recursion from Level 1, passing Key as TopLevelName
                  return _buildCategoryNode(category, category.name, level: 1);
                })
            ])
      ],
    );
  }

  Widget _buildCategoryNode(BookCategory category, String topLevelName,
      {required int level}) {
    final path = category.name;
    // Default: expand first two levels
    final isExpanded = _expansionState[path] ?? level <= 1;
    final hasChildren = category.subcategories?.isNotEmpty == true;
    final isSelected = widget.selectedCategoryName == path ||
        widget.selectedCategoryName == category.name;

    final childrenWidgets = <Widget>[];
    if (isExpanded && hasChildren) {
      if (category.subcategories != null) {
        // Use natural order from DataProvider (already sorted by orderIndex from DB)
        for (final sub in category.subcategories!) {
          // Pass the SAME topLevelName down
          childrenWidgets
              .add(_buildCategoryNode(sub, topLevelName, level: level + 1));
        }
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NavigationTreeTile.category(
          title: category.name,
          level: level,
          isSelected: isSelected,
          isExpanded: isExpanded,
          hasChildren: hasChildren,
          onTap: () {
            widget.onCategorySelected(category.name, category, topLevelName);
          },
          onToggleExpand: () => _toggleCategory(path),
        ),
        if (isExpanded) ...childrenWidgets,
      ],
    );
  }
}
