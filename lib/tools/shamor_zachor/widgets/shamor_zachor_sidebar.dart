import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import '../providers/shamor_zachor_data_provider.dart';
import '../models/book_model.dart';

class ShamorZachorSidebar extends StatefulWidget {
  // Updated callback signature to include Top Level Name
  final Function(
    String categoryName,
    BookCategory category,
    String topLevelName,
  )
  onCategorySelected;
  final String? selectedCategoryName;

  const ShamorZachorSidebar({
    super.key,
    required this.onCategorySelected,
    this.selectedCategoryName,
  });

  @override
  State<ShamorZachorSidebar> createState() => _ShamorZachorSidebarState();
}

class _ShamorZachorSidebarState extends State<ShamorZachorSidebar> {
  final Map<String, bool> _expansionState = {};

  void _toggleCategory(String categoryPath) {
    setState(() {
      _expansionState[categoryPath] = !(_expansionState[categoryPath] ?? false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ShamorZachorDataProvider>(
      builder: (context, dataProvider, child) {
        if (dataProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (dataProvider.error != null) {
          return Center(
            child: Text(
              'שגיאה בטעינת נתונים',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          );
        }

        // Always show category tree, search results will be shown in main area
        return _buildCategoryTree(dataProvider);
      },
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
      defaultStartPage: 1,
    );

    final isAllBooksSelected =
        widget.selectedCategoryName == 'all_books_virtual' ||
        widget.selectedCategoryName == 'כל הספרים';

    void selectAll() => widget.onCategorySelected(
      'כל הספרים',
      allBooksCategory,
      'all_books_virtual',
    );

    // שיטוח לרשימת שורות + ListView.builder (בנייה עצלה) — עצי שמור-וזכור
    // דינמיים ועלולים להיות ארוכים; בנייה מוקדמת של כל העץ הייתה מכבידה.
    final rows = <_ShamorNavRow>[_ShamorNavRow.root(isAllBooksSelected)];
    for (final key in sortedKeys) {
      final top = allCategories[key]!;
      _flattenCategory(top, top.name, 1, rows);
    }
    // כל הקטגוריות הן כרטיס אחד רציף (מעוגל בקצוות, מפריד בין השורות).
    // השורש נשאר מחוץ לכרטיס (רקע החלונית).
    int? firstGrouped;
    int? lastGrouped;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].isRoot) continue;
      firstGrouped ??= i;
      lastGrouped = i;
    }
    if (firstGrouped != null) {
      rows[firstGrouped].isGroupStart = true;
      rows[lastGrouped!].isGroupEnd = true;
    }

    return ListView.builder(
      // שוליים אופקיים — הכרטיסים לא נוגעים בקצה, וקו הגלילה ברווח.
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: rows.length,
      itemBuilder: (context, index) =>
          _buildNavRow(context, rows[index], selectAll),
    );
  }

  void _flattenCategory(
    BookCategory category,
    String topLevelName,
    int level,
    List<_ShamorNavRow> rows,
  ) {
    rows.add(_ShamorNavRow.category(category, level, topLevelName));
    final isExpanded = _expansionState[category.name] ?? false;
    if (isExpanded && category.subcategories != null) {
      for (final sub in category.subcategories!) {
        _flattenCategory(sub, topLevelName, level + 1, rows);
      }
    }
  }

  Widget _buildNavRow(
    BuildContext context,
    _ShamorNavRow row,
    VoidCallback onClearToAll,
  ) {
    if (row.isRoot) {
      // שורש "כל הספרים" — כותרת על רקע החלונית (בלי כרטיס/קופסת-אייקון).
      return NavTreeHeader(
        title: 'כל הספרים',
        isSelected: row.isSelected,
        // "נקה סינון" לצד השורש כשנבחרה קטגוריה ספציפית (כמו בחיפוש).
        onClearFilter: row.isSelected ? null : onClearToAll,
        onTap: onClearToAll,
      );
    }

    final category = row.category!;
    final path = category.name;
    final isExpanded = _expansionState[path] ?? false;
    final hasChildren = category.subcategories?.isNotEmpty == true;
    final isSelected =
        widget.selectedCategoryName == path ||
        widget.selectedCategoryName == category.name;

    return NavTreeGroupCard(
      isGroupStart: row.isGroupStart,
      isGroupEnd: row.isGroupEnd,
      child: KeyedSubtree(
        key: ValueKey('$path@${row.level}'),
        child: NavTreeTile.category(
          title: category.name,
          // level-1: תיקיות עליונות מתחילות ב-0 (השורש הוא כותרת).
          level: row.level - 1,
          isSelected: isSelected,
          isExpanded: isExpanded,
          hasChildren: hasChildren,
          onTap: () {
            widget.onCategorySelected(
              category.name,
              category,
              row.topLevelName,
            );
          },
          onToggleExpand: () => _toggleCategory(path),
        ),
      ),
    );
  }
}

/// שורה משוטחת בעץ הניווט של שמור-וזכור (לבנייה עצלה ב-ListView.builder).
class _ShamorNavRow {
  final BookCategory? category;
  final int level;
  final String topLevelName;
  final bool isRoot;
  final bool isSelected;
  bool isGroupStart = false;
  bool isGroupEnd = false;

  _ShamorNavRow.root(this.isSelected)
    : category = null,
      level = 0,
      topLevelName = '',
      isRoot = true;

  _ShamorNavRow.category(this.category, this.level, this.topLevelName)
    : isRoot = false,
      isSelected = false;
}
