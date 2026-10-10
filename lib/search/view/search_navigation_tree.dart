import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/utils/search_catalogue_order_helper.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/utils/ui/book_format_icon.dart';

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

  /// [isExpanded] הוא המצב האפקטיבי של הקטגוריה כרגע (כולל פתיחה אוטומטית
  /// של ענף הבחירה) — בלעדיו הלחיצה הראשונה על החץ לא הייתה מכווצת.
  final void Function(String path, bool isExpanded) onToggleExpand;
  final bool Function() isMultiSelectPressed;

  /// ניקוי כל הסינון (קטגוריות + ממדים) — מכפתור "נקה סינון" שבכותרת השורש.
  final VoidCallback onClearAll;

  /// קטגוריות-על סינתטיות שאינן חלק מהספרייה (למשל "עוד מהיברובוקס" של
  /// ספק תוצאות חיצוני), מוצגות אחרי הקטגוריות האמיתיות — או לפניהן, לפי
  /// [extraCategoriesFirst]. לחיצה מסננת דרך אותם callbacks של קטגוריה/ספר
  /// רגילים.
  final List<SearchTreeExtraCategory> extraRootCategories;

  /// הגדרת "תוצאות מ<מקור> קודמות": הקטגוריות הסינתטיות מוצגות בראש העץ
  /// (מיד אחרי כותרת השורש) במקום בסופו.
  final bool extraCategoriesFirst;

  /// פעולה נוספת בכותרת השורש, ליד אייקון החיפוש (למשל סינון לפי מאפיין).
  final Widget? rootHeaderAction;

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
    this.extraRootCategories = const [],
    this.extraCategoriesFirst = false,
    this.rootHeaderAction,
  });

  static const double _iconBoxSize = 26;
  static const double _iconSize = 14;

  bool _isSelected(String facet) => selectedFacets.contains(facet);

  /// נתיבי הקטגוריות/ספרים המסוננים כרגע (בלי השורש ובלי ממדים).
  List<String> _selectedPaths() => FacetHelper.categoryFacetsOf(
    selectedFacets,
  ).where((f) => f != '/').toList();

  /// האם [path] הוא אב-קדמון של סינון פעיל. ענף כזה נפתח כברירת מחדל ומוצג
  /// גם בספירה 0 — אחרת הסינון הפעיל נעלם מהעץ ואין דרך לבטלו.
  static bool _leadsToSelection(String path, List<String> selectedPaths) =>
      selectedPaths.any((facet) => facet.startsWith('$path/'));

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
    return NavTreeFocusGroup(
      child: ListView.builder(
        padding: kNavTreeListPadding,
        itemCount: rows.length,
        itemBuilder: (context, index) =>
            _buildFlatRow(context, rows[index], rows),
      ),
    );
  }

  // ── שיטוח העץ ───────────────────────────────────────────────────────────────

  List<_FlatRow> _flattenRows() {
    final rows = <_FlatRow>[];
    final selectedPaths = _selectedPaths();
    rows.add(_FlatRow.rootHeader(facetCounts[library.path] ?? 0));
    // "תוצאות מ<מקור> קודמות" — הדלי החיצוני עליון; אחרת בסוף העץ.
    if (extraCategoriesFirst) _appendExtraRows(rows, selectedPaths);
    _flattenChildren(library, 0, rows, selectedPaths);
    if (!extraCategoriesFirst) _appendExtraRows(rows, selectedPaths);
    _markGroupBoundaries(rows);
    return rows;
  }

  void _appendExtraRows(List<_FlatRow> rows, List<String> selectedPaths) {
    for (final extra in extraRootCategories) {
      // ספרי הקטגוריה הסינתטית מגיעים מהספק, ולא מהספרייה — לכן חץ ההרחבה
      // כאן תלוי ברשימה שהוא צירף, ולא ב-facetCounts.
      final hasChildren = extra.books.isNotEmpty;
      final leadsToSelection = _leadsToSelection(extra.facet, selectedPaths);
      // כמו בענפי הספרייה: שורה שהיא הסינון הפעיל (או דרך אליו) נשארת גלויה
      // גם בספירה 0 — אחרת הסינון אינו מיוצג בעץ ואין דרך לבטלו. ספר נבחר
      // שכבר אינו ברשימת הספק משאיר את הדלי עצמו, בלי שורה משלו.
      if (extra.count == 0 && !_isSelected(extra.facet) && !leadsToSelection) {
        continue;
      }
      final isExpanded =
          hasChildren && (expansion[extra.facet] ?? leadsToSelection);
      rows.add(
        _FlatRow.extraCategory(
          extra.title,
          extra.facet,
          extra.count,
          isExpanded,
          hasChildren,
        ),
      );
      if (!isExpanded) continue;
      for (final book in extra.books) {
        rows.add(_FlatRow.extraBook(book.title, book.facet, book.hits));
      }
    }
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

  void _flattenChildren(
    Category category,
    int level,
    List<_FlatRow> rows,
    List<String> selectedPaths,
  ) {
    for (final sub in _sortedSubCategories(category)) {
      final count = facetCounts[sub.path] ?? 0;
      final leadsToSelection = _leadsToSelection(sub.path, selectedPaths);
      if (count == 0 && !leadsToSelection && !_isSelected(sub.path)) continue;
      // ספירה שמקורה רק בספק חיצוני (היברובוקס) יכולה לשבת על קטגוריה שאין
      // תחתיה שום שורה נראית — הענף העמוק אינו בקטלוג המקומי, או שהספר אינו
      // ספר ספרייה. בלי ילדים נראים אין חץ הרחבה; הלחיצה על השורה עצמה
      // מסננת ומציגה את התוצאות.
      final hasChildren = _hasVisibleChildren(sub, selectedPaths);
      final isExpanded =
          hasChildren && (expansion[sub.path] ?? leadsToSelection);
      rows.add(
        _FlatRow.category(sub, level + 1, count, isExpanded, hasChildren),
      );
      if (isExpanded) _flattenChildren(sub, level + 1, rows, selectedPaths);
    }
    for (final book in _uniqueBooks(category.books)) {
      final facet = FacetHelper.buildBookFacet(category.path, book);
      final count = facetCounts[facet] ?? 0;
      if (count == 0 && !_isSelected(facet)) continue;
      rows.add(_FlatRow.book(book, facet, count, level + 1));
    }
  }

  /// האם לקטגוריה יש לפחות שורה נראית אחת מתחתיה — אותם תנאים בדיוק
  /// שבהם [_flattenChildren] מרנדר ילד (קטגוריה או ספר).
  bool _hasVisibleChildren(Category category, List<String> selectedPaths) {
    for (final sub in category.subCategories) {
      final count = facetCounts[sub.path] ?? 0;
      if (count > 0 ||
          _leadsToSelection(sub.path, selectedPaths) ||
          _isSelected(sub.path)) {
        return true;
      }
    }
    for (final book in category.books) {
      final facet = FacetHelper.buildBookFacet(category.path, book);
      if ((facetCounts[facet] ?? 0) > 0 || _isSelected(facet)) return true;
    }
    return false;
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

  Widget _buildFlatRow(
    BuildContext context,
    _FlatRow row,
    List<_FlatRow> rows,
  ) {
    switch (row.kind) {
      case _FlatRowKind.rootHeader:
        // השורש — כותרת על רקע החלונית (בלי כרטיס/קופסת-אייקון). כשיש סינון
        // ממד מוצג שמו במקום 'ספריית אוצריא', וכפתור "נקה סינון" מנקה הכל.
        return NavTreeHeader(
          title: _rootTitle(),
          isSelected: !_anyFilterActive,
          onTap: () => onSetFacet('/'),
          onClearFilter: _anyFilterActive ? onClearAll : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (rows.any((r) => r.isExpanded))
                _buildCollapseAllButton(context, rows),
              const NavPanelSearchToggle(),
              ?rootHeaderAction,
            ],
          ),
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
              hasChildren: row.hasChildren,
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
      case _FlatRowKind.extraCategory:
        // קטגוריה סינתטית (ספק חיצוני) — שורת קטגוריה עליונה, שנפתחת
        // לספרים שהספק צירף (אם צירף).
        return _wrapInGroupCard(
          context,
          row,
          KeyedSubtree(
            key: ValueKey(row.facet),
            child: NavTreeTile.category(
              title: row.extraTitle!,
              level: 0,
              isSelected: _isSelected(row.facet!),
              isExpanded: row.isExpanded,
              hasChildren: row.hasChildren,
              count: row.count == -1 ? null : row.count,
              onTap: () => isMultiSelectPressed()
                  ? onToggleFacet(row.facet!)
                  : onSetFacet(row.facet!),
              onToggleExpand: () => onToggleExpand(row.facet!, row.isExpanded),
            ),
          ),
        );
      case _FlatRowKind.extraBook:
        // ספר של הספק החיצוני: אין לו Book בספרייה, ולכן גם אין אייקון
        // קטלוג או שם מחבר — רק שם ומספר המופעים שבו.
        return _wrapInGroupCard(
          context,
          row,
          KeyedSubtree(
            key: ValueKey(row.facet),
            child: NavTreeTile.book(
              title: row.extraTitle!,
              level: row.level - 1,
              isSelected: _isSelected(row.facet!),
              count: row.count,
              onTap: () => isMultiSelectPressed()
                  ? onToggleFacet(row.facet!)
                  : onSetFacet(row.facet!),
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
            bookFormatIcon(book),
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

  Widget _buildCollapseAllButton(BuildContext context, List<_FlatRow> rows) {
    return SizedBox.square(
      dimension: 28,
      child: IconButton(
        tooltip: context.settingsText('כווץ הכל'),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        icon: const Icon(FluentIcons.arrow_collapse_all_24_regular, size: 18),
        onPressed: () => _collapseAll(rows),
      ),
    );
  }

  /// גם ענפים פתוחים שמוסתרים תחת הורה סגור נסגרים, כדי שלא ייפתחו שוב
  /// כשההורה נפתח.
  void _collapseAll(List<_FlatRow> rows) {
    final paths = <String>{
      for (final row in rows)
        if (row.isExpanded) row.category?.path ?? row.facet!,
      for (final entry in expansion.entries)
        if (entry.value) entry.key,
    };
    for (final path in paths) {
      onToggleExpand(path, true);
    }
  }

  // ── קטגוריות ──────────────────────────────────────────────────────────────

  Widget _buildCategoryHeader(
    BuildContext context,
    Category category,
    int level,
    int count, {
    required bool isExpanded,
    required bool hasChildren,
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
      hasChildren: hasChildren,
      count: count == -1 ? null : count,
      trailing: loadingTrailing,
      onTap: () => isMultiSelectPressed()
          ? onToggleFacet(category.path)
          : onSetFacet(category.path),
      onToggleExpand: () => _toggleExpand(category, isExpanded),
    );
  }

  /// פתיחה ממשיכה לרדת דרך ענף שיש לו ילד גלוי יחיד (תת-קטגוריה), עד
  /// הרמה שבה התוצאות מתפצלות — חוסך לחיצה לכל רמת ביניים.
  void _toggleExpand(Category category, bool isExpanded) {
    onToggleExpand(category.path, isExpanded);
    if (isExpanded) return;
    final selectedPaths = _selectedPaths();
    var only = _singleVisibleSubCategory(category, selectedPaths);
    while (only != null && _hasVisibleChildren(only, selectedPaths)) {
      onToggleExpand(only.path, false);
      only = _singleVisibleSubCategory(only, selectedPaths);
    }
  }

  Category? _singleVisibleSubCategory(
    Category category,
    List<String> selectedPaths,
  ) {
    final hasVisibleBook = category.books.any((book) {
      final facet = FacetHelper.buildBookFacet(category.path, book);
      return (facetCounts[facet] ?? 0) > 0 || _isSelected(facet);
    });
    if (hasVisibleBook) return null;
    final visible = category.subCategories.where(
      (sub) =>
          (facetCounts[sub.path] ?? 0) > 0 ||
          _leadsToSelection(sub.path, selectedPaths) ||
          _isSelected(sub.path),
    );
    return visible.length == 1 ? visible.single : null;
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
    if (isLoading && !hasResults) {
      return const Center(child: CircularProgressIndicator());
    }

    // רשב"א מול רשב״א — גרשיים אינם חלק מההשוואה.
    final query = normalizeBookTitle(filterQuery).toLowerCase();
    // ספר ללא תוצאות מוסתר כאן בדיוק כמו בעץ: בחירתו הייתה מרוקנת את
    // התוצאות ומשאירה סינון שלא מיוצג בעץ אחרי ניקוי שדה האיתור.
    final matches = <_FilteredBook>[];
    for (final book in _allBooks(library)) {
      if (!_titleHaystack(book).contains(query)) {
        continue;
      }
      final facet = FacetHelper.buildBookFacet(
        FacetHelper.resolveCategoryPath(book),
        book,
      );
      final count = facetCounts[facet] ?? 0;
      if (count == 0) continue;
      matches.add(_FilteredBook(book, facet, count));
    }

    if (matches.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'לא נמצאו ספרים עם תוצאות',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return NavTreeFocusGroup(
      child: ListView.builder(
        padding: kNavTreeListPadding,
        itemCount: matches.length,
        itemBuilder: (context, index) {
          final match = matches[index];
          return _buildBook(context, match.book, match.facet, match.count, 0);
        },
      ),
    );
  }

  // ── עזרי traversal ──────────────────────────────────────────────────────────

  // כותרת מנורמלת לכל ספר מחושבת פעם אחת ולא בכל הקשה.
  static final Expando<String> _haystacks = Expando();

  static String _titleHaystack(Book book) =>
      _haystacks[book] ??= normalizeBookTitle(book.title).toLowerCase();

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

/// ספר שעבר את סינון שדה האיתור, יחד עם ה-facet והספירה שכבר חושבו עבורו.
class _FilteredBook {
  final Book book;
  final String facet;
  final int count;

  const _FilteredBook(this.book, this.facet, this.count);
}

/// קטגוריית-על סינתטית בעץ (דלי של ספק תוצאות חיצוני) והספרים שתחתיה.
/// ה-facets נבנים בצד הקורא — העץ עצמו רק מציג ומדווח עליהם.
class SearchTreeExtraCategory {
  final String title;
  final String facet;
  final int count;
  final List<SearchTreeExtraBook> books;

  const SearchTreeExtraCategory({
    required this.title,
    required this.facet,
    required this.count,
    this.books = const [],
  });
}

/// ספר של ספק חיצוני תחת קטגוריה סינתטית.
class SearchTreeExtraBook {
  final String title;
  final String facet;
  final int hits;

  const SearchTreeExtraBook({
    required this.title,
    required this.facet,
    required this.hits,
  });
}

enum _FlatRowKind { rootHeader, category, book, extraCategory, extraBook }

/// שורה משוטחת אחת ברשימת הניווט (לבנייה עצלה ב-ListView.builder).
/// [isGroupStart]/[isGroupEnd] מסמנים גבולות קבוצה עליונה — לעיצוב הכרטיס
/// המקובץ (פינות מעוגלות בקצוות ומפריד בין שורות), כמו במסך הספרייה.
class _FlatRow {
  final _FlatRowKind kind;
  final Category? category;
  final Book? book;
  final String? facet;
  final String? extraTitle;
  final int level;
  final int count;
  final bool isExpanded;
  final bool hasChildren;
  bool isGroupStart = false;
  bool isGroupEnd = false;

  _FlatRow._({
    required this.kind,
    this.category,
    this.book,
    this.facet,
    this.extraTitle,
    this.level = 0,
    this.count = 0,
    this.isExpanded = false,
    this.hasChildren = false,
  });

  _FlatRow.rootHeader(int count)
    : this._(kind: _FlatRowKind.rootHeader, count: count);

  _FlatRow.category(
    Category category,
    int level,
    int count,
    bool isExpanded,
    bool hasChildren,
  ) : this._(
        kind: _FlatRowKind.category,
        category: category,
        level: level,
        count: count,
        isExpanded: isExpanded,
        hasChildren: hasChildren,
      );

  _FlatRow.book(Book book, String facet, int count, int level)
    : this._(
        kind: _FlatRowKind.book,
        book: book,
        facet: facet,
        count: count,
        level: level,
      );

  _FlatRow.extraCategory(
    String title,
    String facet,
    int count,
    bool isExpanded,
    bool hasChildren,
  ) : this._(
        kind: _FlatRowKind.extraCategory,
        extraTitle: title,
        facet: facet,
        level: 1,
        count: count,
        isExpanded: isExpanded,
        hasChildren: hasChildren,
      );

  _FlatRow.extraBook(String title, String facet, int hits)
    : this._(
        kind: _FlatRowKind.extraBook,
        extraTitle: title,
        facet: facet,
        level: 2,
        count: hits,
      );
}
