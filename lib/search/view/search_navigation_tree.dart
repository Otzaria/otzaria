import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/utils/search_catalogue_order_helper.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// עץ ניווט תוצאות החיפוש בעיצוב מסך הספרייה ([library_browser.dart]),
/// בנוי מ-[NavTreeTile]. העץ משוטח לרשימת שורות ומרונדר ב-ListView.builder
/// (בנייה עצלה) — כמו במסך הספרייה, למניעת קיפאון בגלילה ובסינון.
///
/// נשלט (controlled): כל הנתונים והפעולות מוזרקים; הרכיב חסר-state.
class SearchNavigationTree extends StatelessWidget {
  final Library library;
  final Map<String, int> facetCounts;

  /// ה-facets הפעילים כרגע (לסימון בחירה).
  final Iterable<String> selectedFacets;

  /// מצב הפתיחה של כל קטגוריה לפי נתיב.
  final Map<String, bool> expansion;

  /// טקסט סינון הרשימה. באורך ≥ 2 מוצגת רשימת ספרים שטוחה במקום העץ.
  final String filterQuery;

  final bool isLoading;
  final bool hasResults;

  /// בחירת facet יחיד (לחיצה רגילה) / הוספה-הסרה (Ctrl+לחיצה).
  final void Function(String facet) onSetFacet;
  final void Function(String facet) onToggleFacet;
  final void Function(String path) onToggleExpand;
  final bool Function() isMultiSelectPressed;

  /// ניקוי כל הסינון (קטגוריות + ממדים) — מכפתור "נקה סינון" שבכותרת השורש.
  final VoidCallback onClearAll;

  const SearchNavigationTree({
    super.key,
    required this.library,
    required this.facetCounts,
    required this.selectedFacets,
    required this.expansion,
    required this.filterQuery,
    required this.isLoading,
    required this.hasResults,
    required this.onSetFacet,
    required this.onToggleFacet,
    required this.onToggleExpand,
    required this.isMultiSelectPressed,
    required this.onClearAll,
  });

  static const double _iconBoxSize = 26;
  static const double _iconSize = 14;

  bool _isSelected(String facet) => selectedFacets.contains(facet);

  bool get _categoryFilterActive =>
      FacetHelper.categoryFacetsOf(selectedFacets).any((f) => f != '/');

  @override
  Widget build(BuildContext context) {
    if (filterQuery.length >= 2) {
      return _buildFilteredBookList(context);
    }
    // שיטוח לרשימת שורות + ListView.builder (בנייה עצלה) — כמו במסך הספרייה.
    // בנייה מוקדמת של כל העץ (ExpandableCard לכל קטגוריה) הקפיאה את הגלילה
    // ואת הרינדור-מחדש בכל שינוי סינון.
    final rows = _flattenRows();
    return ListView.builder(
      // שוליים אופקיים — הכרטיסים לא נוגעים בקצה החלונית, וקו הגלילה יושב
      // ברווח שנוצר (ולא על התוכן).
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: rows.length,
      itemBuilder: (context, index) => _buildFlatRow(context, rows[index]),
    );
  }

  // ── שיטוח העץ ───────────────────────────────────────────────────────────────

  List<_FlatRow> _flattenRows() {
    final rows = <_FlatRow>[];
    rows.add(_FlatRow.rootHeader(facetCounts[library.path] ?? 0));
    _flattenChildren(library, 0, rows);
    _markGroupBoundaries(rows);
    return rows;
  }

  /// כותרת השורש: כשיש סינון ממד פעיל (ספרי יסוד/תקופה/מחבר) מוצג שמו במקום
  /// 'ספריית אוצריא'.
  String _rootTitle() {
    final dims = FacetHelper.dimensionFacetsOf(selectedFacets).toList();
    if (dims.isEmpty) return 'ספריית אוצריא';
    return dims.map(_dimensionLabel).join(', ');
  }

  bool get _anyFilterActive =>
      _categoryFilterActive ||
      FacetHelper.dimensionFacetsOf(selectedFacets).isNotEmpty;

  /// כל שורות העץ (קטגוריות+ספרים) הן כרטיס אחד רציף: פינות מעוגלות רק
  /// בקצה העליון/התחתון, ומפריד בין כל השורות (כולל בין תיקיות עליונות).
  /// השורש וכרטיסי הממדים נשארים מחוץ לכרטיס (רקע החלונית).
  void _markGroupBoundaries(List<_FlatRow> rows) {
    int? first;
    int? last;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].level < 1) continue;
      first ??= i;
      last = i;
    }
    if (first != null) {
      rows[first].isGroupStart = true;
      rows[last!].isGroupEnd = true;
    }
  }

  void _flattenChildren(Category category, int level, List<_FlatRow> rows) {
    for (final sub in _sortedSubCategories(category)) {
      final count = facetCounts[sub.path] ?? 0;
      if (count == 0) continue;
      final isExpanded = expansion[sub.path] ?? false;
      rows.add(_FlatRow.category(sub, level + 1, count, isExpanded));
      if (isExpanded) _flattenChildren(sub, level + 1, rows);
    }
    for (final book in _uniqueBooks(category.books)) {
      final facet = FacetHelper.buildBookFacet(category.path, book);
      final count = facetCounts[facet] ?? 0;
      if (count == 0) continue;
      rows.add(_FlatRow.book(book, facet, count, level + 1));
    }
  }

  List<Category> _sortedSubCategories(Category category) {
    final subs = category.subCategories.toList();
    if (category is Library) {
      subs.sort(
        (a, b) => SearchCatalogueOrderHelper.topCategoryOrder(
          a,
        ).compareTo(SearchCatalogueOrderHelper.topCategoryOrder(b)),
      );
    } else {
      subs.sort(
        (a, b) => SearchCatalogueOrderHelper.normalizeOrder(
          a.order,
        ).compareTo(SearchCatalogueOrderHelper.normalizeOrder(b.order)),
      );
    }
    return subs;
  }

  Widget _buildFlatRow(BuildContext context, _FlatRow row) {
    switch (row.kind) {
      case _FlatRowKind.rootHeader:
        // השורש — כותרת על רקע החלונית (בלי כרטיס/קופסת-אייקון). כשיש סינון
        // ממד מוצג שמו במקום 'ספריית אוצריא', וכפתור "נקה סינון" מנקה הכל.
        return NavTreeHeader(
          title: _rootTitle(),
          isSelected: !_anyFilterActive,
          onTap: () => onSetFacet('/'),
          onClearFilter: _anyFilterActive ? onClearAll : null,
        );
      case _FlatRowKind.category:
        return _wrapInGroupCard(
          context,
          row,
          KeyedSubtree(
            key: ValueKey(row.category!.path),
            // level-1: תיקיות עליונות מתחילות ב-0 (השורש הוא כותרת, לא רמה).
            child: _buildCategoryHeader(
              context,
              row.category!,
              row.level - 1,
              row.count,
              isExpanded: row.isExpanded,
            ),
          ),
        );
      case _FlatRowKind.book:
        return _wrapInGroupCard(
          context,
          row,
          KeyedSubtree(
            key: ObjectKey(row.book),
            child: _buildBook(
              context,
              row.book!,
              row.facet!,
              row.count,
              row.level - 1,
              card: false,
            ),
          ),
        );
    }
  }

  Widget _wrapInGroupCard(BuildContext context, _FlatRow row, Widget child) {
    return NavTreeGroupCard(
      isGroupStart: row.isGroupStart,
      isGroupEnd: row.isGroupEnd,
      child: child,
    );
  }

  // ── עיצוב משותף ───────────────────────────────────────────────────────────

  Widget _bookIconBox(ColorScheme cs, Book book) {
    final logoAsset = externalCatalogLogoAsset(book);
    final Widget child = logoAsset != null
        ? Image.asset(
            logoAsset,
            width: _iconSize,
            height: _iconSize,
            fit: BoxFit.contain,
          )
        : Icon(
            book is PdfBook
                ? FluentIcons.document_pdf_24_regular
                : book is DocxBook || book.fileType == 'docx'
                ? FluentIcons.document_edit_24_regular
                : FluentIcons.document_text_24_regular,
            color: cs.onSecondaryContainer,
            size: _iconSize,
          );
    return Container(
      width: _iconBoxSize,
      height: _iconBoxSize,
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Center(child: child),
    );
  }

  // ── קטגוריות ──────────────────────────────────────────────────────────────

  Widget _buildCategoryHeader(
    BuildContext context,
    Category category,
    int level,
    int count, {
    required bool isExpanded,
  }) {
    final Widget? loadingTrailing = count == -1
        ? const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          )
        : null;

    return NavTreeTile.category(
      title: category.title,
      level: level,
      isSelected: _isSelected(category.path),
      isExpanded: isExpanded,
      hasChildren: true,
      count: count == -1 ? null : count,
      trailing: loadingTrailing,
      onTap: () => isMultiSelectPressed()
          ? onToggleFacet(category.path)
          : onSetFacet(category.path),
      onToggleExpand: () => onToggleExpand(category.path),
    );
  }

  String _dimensionLabel(String facet) {
    if (facet == FacetHelper.baseDimensionFacet) return 'ספרי יסוד';
    if (facet.startsWith(FacetHelper.eraDimensionPrefix)) {
      return facet.substring(FacetHelper.eraDimensionPrefix.length);
    }
    if (facet.startsWith(FacetHelper.authorDimensionPrefix)) {
      return facet.substring(FacetHelper.authorDimensionPrefix.length);
    }
    return facet;
  }

  // ── ספרים ─────────────────────────────────────────────────────────────────

  Widget _buildBook(
    BuildContext context,
    Book book,
    String facet,
    int count,
    int level, {
    bool card = true,
  }) {
    final cs = Theme.of(context).colorScheme;

    final tile = NavTreeTile.book(
      title: book.title,
      level: level,
      subtitle: book.author,
      isSelected: _isSelected(facet),
      count: count == -1 ? null : count,
      leading: _bookIconBox(cs, book),
      onTap: () =>
          isMultiSelectPressed() ? onToggleFacet(facet) : onSetFacet(facet),
    );

    // בעץ המקובץ הכרטיס מסופק ע"י _wrapInGroupCard; ברשימת הסינון השטוחה
    // כל ספר הוא כרטיס בפני עצמו.
    if (!card) return tile;
    return AppCard(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: EdgeInsets.zero,
      child: tile,
    );
  }

  // ── רשימת סינון שטוחה ───────────────────────────────────────────────────────

  Widget _buildFilteredBookList(BuildContext context) {
    final query = filterQuery.toLowerCase();
    final books = _allBooks(
      library,
    ).where((b) => b.title.toLowerCase().contains(query)).toList();

    if (isLoading && !hasResults) {
      return const Center(child: CircularProgressIndicator());
    }
    if (books.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('לא נמצאו ספרים'),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        final facet = FacetHelper.buildBookFacet(
          FacetHelper.resolveCategoryPath(book),
          book,
        );
        final count = facetCounts[facet] ?? 0;
        return _buildBook(context, book, facet, count, 0);
      },
    );
  }

  // ── עזרי traversal ──────────────────────────────────────────────────────────

  List<Book> _uniqueBooks(List<Book> books) {
    final unique = <String, Book>{};
    for (final book in books) {
      unique[_dedupKey(book)] ??= book;
    }
    final list = unique.values.toList();
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  List<Book> _allBooks(Category root) {
    final all = <Book>[];
    void collect(Category cat) {
      all.addAll(_uniqueBooks(cat.books));
      final subs = cat.subCategories.toList();
      if (cat is Library) {
        subs.sort(
          (a, b) => SearchCatalogueOrderHelper.topCategoryOrder(
            a,
          ).compareTo(SearchCatalogueOrderHelper.topCategoryOrder(b)),
        );
      } else {
        subs.sort(
          (a, b) => SearchCatalogueOrderHelper.normalizeOrder(
            a.order,
          ).compareTo(SearchCatalogueOrderHelper.normalizeOrder(b.order)),
        );
      }
      for (final sub in subs) {
        collect(sub);
      }
    }

    collect(root);
    return all;
  }

  String _dedupKey(Book book) {
    final externalKey = book.externalLibraryId;
    if (externalKey != null && externalKey.isNotEmpty) {
      return 'ext:$externalKey';
    }
    final idKey = book.id;
    if (idKey != null) return 'id:$idKey';
    final categoryKey = book.categoryId?.toString() ?? book.categoryPath ?? '';
    return '${book.title.trim()}|$categoryKey';
  }
}

enum _FlatRowKind { rootHeader, category, book }

/// שורה משוטחת אחת ברשימת הניווט (לבנייה עצלה ב-ListView.builder).
/// [isGroupStart]/[isGroupEnd] מסמנים גבולות קבוצה עליונה — לעיצוב הכרטיס
/// המקובץ (פינות מעוגלות בקצוות ומפריד בין שורות), כמו במסך הספרייה.
class _FlatRow {
  final _FlatRowKind kind;
  final Category? category;
  final Book? book;
  final String? facet;
  final int level;
  final int count;
  final bool isExpanded;
  bool isGroupStart = false;
  bool isGroupEnd = false;

  _FlatRow._({
    required this.kind,
    this.category,
    this.book,
    this.facet,
    this.level = 0,
    this.count = 0,
    this.isExpanded = false,
  });

  _FlatRow.rootHeader(int count)
    : this._(kind: _FlatRowKind.rootHeader, count: count);

  _FlatRow.category(Category category, int level, int count, bool isExpanded)
    : this._(
        kind: _FlatRowKind.category,
        category: category,
        level: level,
        count: count,
        isExpanded: isExpanded,
      );

  _FlatRow.book(Book book, String facet, int count, int level)
    : this._(
        kind: _FlatRowKind.book,
        book: book,
        facet: facet,
        count: count,
        level: level,
      );
}
