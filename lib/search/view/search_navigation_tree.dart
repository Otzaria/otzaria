import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:positioned_sliver_list/positioned_sliver_list.dart'
    show SuperListView;
import 'package:flutter/services.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/utils/search_catalogue_order_helper.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:otzaria/widgets/navigation/nav_tree_collapse_all_button.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/utils/ui/book_format_icon.dart';

/// עץ ניווט תוצאות החיפוש בעיצוב מסך הספרייה ([library_browser.dart]),
/// בנוי מ-[NavTreeTile]. העץ משוטח לרשימת שורות ומרונדר ב-SuperListView.builder
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

  /// היקף החיפוש (למשל מ-@ או מההיסטוריה).
  final Iterable<String> scopeFacets;

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
    required this.onClearAll,
    this.extraRootCategories = const [],
    this.extraCategoriesFirst = false,
    this.rootHeaderAction,
    this.scopeFacets = const [],
  });

  static const double _iconBoxSize = 26;
  static const double _iconSize = 14;

  // רענון הקטלוג מפרסם שורש חדש. עדכוני ספירה ובחירה משתמשים באותו העץ.
  static final _catalogues = Expando<_SearchTreeCatalogue>();

  _SearchTreeCatalogue get _catalogue =>
      _catalogues[library] ??= _SearchTreeCatalogue(library);

  bool _isSelected(String facet) => selectedFacets.contains(facet);

  /// ב-Mac המוסכמה לריבוי בחירה היא Cmd+Click, בשאר הפלטפורמות Ctrl+Click.
  static bool _isMultiSelectPressed() {
    final keyboard = HardwareKeyboard.instance;
    if (Platform.isMacOS) {
      return keyboard.isMetaPressed || keyboard.isControlPressed;
    }
    return keyboard.isControlPressed;
  }

  /// נתיבי הקטגוריות/ספרים המסוננים כרגע (בלי השורש ובלי ממדים).
  _FacetPathIndex _selectedPaths() => _FacetPathIndex(
    FacetHelper.categoryFacetsOf(selectedFacets).where((f) => f != '/'),
  );

  /// האם [path] הוא אב-קדמון של סינון פעיל. ענף כזה נפתח כברירת מחדל ומוצג
  /// גם בספירה 0 — אחרת הסינון הפעיל נעלם מהעץ ואין דרך לבטלו.
  static bool _leadsToSelection(String path, _FacetPathIndex selectedPaths) =>
      selectedPaths.hasDescendant(path);

  /// שורות שנשארות גלויות בספירה 0. חברי היקף (@) אינם נשמרים — אחרת כל ספרי
  /// ההיקף מוצגים גם בלי תוצאות — מלבד פריט יחיד שנבחר ידנית.
  _FacetPathIndex _pinnedPaths(_FacetPathIndex selectedPaths) {
    final scope = FacetHelper.categoryFacetsOf(scopeFacets).toSet();
    final paths = selectedPaths.paths;
    if (scope.isEmpty || scope.contains('/') || paths.length == 1) {
      return selectedPaths;
    }
    return _FacetPathIndex(paths.where((path) => !scope.contains(path)));
  }

  static bool _isPinned(String path, _FacetPathIndex pinnedPaths) =>
      pinnedPaths.contains(path) || _leadsToSelection(path, pinnedPaths);

  bool get _categoryFilterActive =>
      FacetHelper.categoryFacetsOf(selectedFacets).any((f) => f != '/');

  @override
  Widget build(BuildContext context) {
    if (filterQuery.length >= 2) {
      return _buildFilteredBookList(context);
    }
    // שיטוח לשורות + SuperListView.builder: בנייה מוקדמת של כל העץ מקפיאה את
    // הגלילה, ו-ListView בונה בקפיצה בפס הגלילה כל שורה שבדרך (#4766).
    final rows = _flattenRows();
    return NavTreeFocusGroup(
      child: SuperListView.builder(
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
    final pinnedPaths = _pinnedPaths(selectedPaths);
    _flattenChildren(library, 0, rows, selectedPaths, pinnedPaths);
    if (!extraCategoriesFirst) _appendExtraRows(rows, selectedPaths);
    _markGroupBoundaries(rows);
    return rows;
  }

  void _appendExtraRows(List<_FlatRow> rows, _FacetPathIndex selectedPaths) {
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
    _FacetPathIndex selectedPaths,
    _FacetPathIndex pinnedPaths,
  ) {
    final projection = _catalogue.of(category);
    for (final sub in projection.orderedSubCategories) {
      final subPath = _catalogue.of(sub).facet;
      final count = facetCounts[subPath] ?? 0;
      final leadsToSelection = _leadsToSelection(subPath, selectedPaths);
      if (count == 0 && !_isPinned(subPath, pinnedPaths)) continue;
      // ספירה שמקורה רק בספק חיצוני (היברובוקס) יכולה לשבת על קטגוריה שאין
      // תחתיה שום שורה נראית — הענף העמוק אינו בקטלוג המקומי, או שהספר אינו
      // ספר ספרייה. בלי ילדים נראים אין חץ הרחבה; הלחיצה על השורה עצמה
      // מסננת ומציגה את התוצאות.
      final hasChildren = _hasVisibleChildren(sub, pinnedPaths);
      final isExpanded =
          hasChildren && (expansion[subPath] ?? leadsToSelection);
      rows.add(
        _FlatRow.category(sub, level + 1, count, isExpanded, hasChildren),
      );
      if (isExpanded) {
        _flattenChildren(sub, level + 1, rows, selectedPaths, pinnedPaths);
      }
    }
    for (final book in projection.orderedBooks) {
      final facet = projection.bookFacet(book);
      final count = facetCounts[facet] ?? 0;
      if (count == 0 && !pinnedPaths.contains(facet)) continue;
      rows.add(_FlatRow.book(book, facet, count, level + 1));
    }
  }

  /// האם לקטגוריה יש לפחות שורה נראית אחת מתחתיה — אותם תנאים בדיוק
  /// שבהם [_flattenChildren] מרנדר ילד (קטגוריה או ספר).
  bool _hasVisibleChildren(Category category, _FacetPathIndex pinnedPaths) {
    for (final sub in category.subCategories) {
      final facet = _catalogue.of(sub).facet;
      final count = facetCounts[facet] ?? 0;
      if (count > 0 || _isPinned(facet, pinnedPaths)) return true;
    }
    final projection = _catalogue.of(category);
    for (final book in category.books) {
      final facet = projection.bookFacet(book);
      if ((facetCounts[facet] ?? 0) > 0 || pinnedPaths.contains(facet)) {
        return true;
      }
    }
    return false;
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
              // אותו כלל כמו בתוכן העניינים (#3103): "הרחב הכל" כשהכל מכווץ,
              // "כווץ הכל" כשמשהו פתוח. בלי ענף שאפשר לפתוח, אין כפתור.
              if (rows.any((r) => r.hasChildren))
                NavTreeCollapseAllButton(
                  isCollapsed: !rows.any((r) => r.isExpanded),
                  onCollapseAll: () => _collapseAll(rows),
                  onExpandAll: _expandAll,
                ),
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
            key: ValueKey(_catalogue.of(row.category!).path),
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
              onTap: () => _isMultiSelectPressed()
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
              onTap: () => _isMultiSelectPressed()
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

  /// גם ענפים פתוחים שמוסתרים תחת הורה סגור נסגרים, כדי שלא ייפתחו שוב
  /// כשההורה נפתח.
  void _collapseAll(List<_FlatRow> rows) {
    final paths = <String>{
      for (final row in rows)
        if (row.isExpanded)
          switch (row.category) {
            final category? => _catalogue.of(category).facet,
            null => row.facet!,
          },
      for (final entry in expansion.entries)
        if (entry.value) entry.key,
    };
    for (final path in paths) {
      onToggleExpand(path, true);
    }
  }

  /// פותח כל ענף שאפשר לפתוח, גם ענפים שמתחת להורה סגור, כדי שכל העץ ייפתח
  /// בלחיצה אחת. ענף שכבר פתוח (גם בפתיחה האוטומטית של ענף הבחירה) לא
  /// נשלח, כי [onToggleExpand] הופך את המצב.
  void _expandAll() {
    final selectedPaths = _selectedPaths();
    for (final path in _expandablePaths(selectedPaths)) {
      final isExpanded =
          expansion[path] ?? _leadsToSelection(path, selectedPaths);
      if (!isExpanded) onToggleExpand(path, false);
    }
  }

  /// כל הענפים שיש להם חץ הרחבה, באותם תנאים שבהם [_flattenChildren]
  /// ו־[_appendExtraRows] מרנדרים שורה עם ילדים, בלי תלות במצב הפתיחה.
  List<String> _expandablePaths(_FacetPathIndex selectedPaths) {
    final pinnedPaths = _pinnedPaths(selectedPaths);
    final paths = <String>[];
    void walk(Category category) {
      for (final sub in category.subCategories) {
        final count = facetCounts[sub.path] ?? 0;
        if (count == 0 && !_isPinned(sub.path, pinnedPaths)) continue;
        if (!_hasVisibleChildren(sub, pinnedPaths)) continue;
        paths.add(sub.path);
        walk(sub);
      }
    }

    walk(library);
    for (final extra in extraRootCategories) {
      if (extra.books.isEmpty) continue;
      if (extra.count == 0 &&
          !_isSelected(extra.facet) &&
          !_leadsToSelection(extra.facet, selectedPaths)) {
        continue;
      }
      paths.add(extra.facet);
    }
    return paths;
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

    final facet = _catalogue.of(category).facet;
    return NavTreeTile.category(
      title: category.title,
      level: level,
      isSelected: _isSelected(facet),
      isExpanded: isExpanded,
      hasChildren: hasChildren,
      count: count == -1 ? null : count,
      trailing: loadingTrailing,
      onTap: () =>
          _isMultiSelectPressed() ? onToggleFacet(facet) : onSetFacet(facet),
      onToggleExpand: () => _toggleExpand(category, isExpanded),
    );
  }

  /// פתיחה ממשיכה לרדת דרך ענף שיש לו ילד גלוי יחיד (תת-קטגוריה), עד
  /// הרמה שבה התוצאות מתפצלות — חוסך לחיצה לכל רמת ביניים.
  void _toggleExpand(Category category, bool isExpanded) {
    onToggleExpand(_catalogue.of(category).facet, isExpanded);
    if (isExpanded) return;
    final pinnedPaths = _pinnedPaths(_selectedPaths());
    var only = _singleVisibleSubCategory(category, pinnedPaths);
    while (only != null && _hasVisibleChildren(only, pinnedPaths)) {
      onToggleExpand(_catalogue.of(only).facet, false);
      only = _singleVisibleSubCategory(only, pinnedPaths);
    }
  }

  Category? _singleVisibleSubCategory(
    Category category,
    _FacetPathIndex pinnedPaths,
  ) {
    final projection = _catalogue.of(category);
    final hasVisibleBook = category.books.any((book) {
      final facet = projection.bookFacet(book);
      return (facetCounts[facet] ?? 0) > 0 || pinnedPaths.contains(facet);
    });
    if (hasVisibleBook) return null;
    final visible = category.subCategories.where((sub) {
      final facet = _catalogue.of(sub).facet;
      return (facetCounts[facet] ?? 0) > 0 || _isPinned(facet, pinnedPaths);
    });
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
          _isMultiSelectPressed() ? onToggleFacet(facet) : onSetFacet(facet),
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
    // כל מילות הסינון נדרשות, גם כשמפרידה ביניהן מילת יחס או סדרן שונה.
    // התאמה רצופה נשארת המסלול המהיר, במיוחד לשאילתה בת מילה אחת.
    final query = normalizeBookTitle(filterQuery).toLowerCase();
    final words = query.trim().split(RegExp(r'\s+'));
    final hasMultipleWords = words.length > 1;
    // ספר ללא תוצאות מוסתר כאן בדיוק כמו בעץ: בחירתו הייתה מרוקנת את
    // התוצאות ומשאירה סינון שלא מיוצג בעץ אחרי ניקוי שדה האיתור.
    final matches = <_FilteredBook>[];
    for (final entry in _catalogue.filterCandidates(facetCounts)) {
      if (!entry.haystack.contains(query) &&
          (!hasMultipleWords ||
              words.any((word) => !entry.haystack.contains(word)))) {
        continue;
      }
      final count = facetCounts[entry.facet] ?? 0;
      if (count == 0) continue;
      matches.add(_FilteredBook(entry.book, entry.facet, count));
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
      child: SuperListView.builder(
        padding: kNavTreeListPadding,
        itemCount: matches.length,
        itemBuilder: (context, index) {
          final match = matches[index];
          return _buildBook(context, match.book, match.facet, match.count, 0);
        },
      ),
    );
  }
}

class _SearchTreeCatalogue {
  _SearchTreeCatalogue(this.root);

  final Library root;
  final _categories = Map<Category, _CategoryProjection>.identity();

  _CategoryProjection of(Category category) =>
      _categories[category] ??= _CategoryProjection(category);

  late final List<_FilterEntry> _filterEntries = _collectFilterEntries();
  late final _filterEntriesByFacet = _indexFilterEntries();

  Map<String, List<_FilterEntry>> _indexFilterEntries() {
    final index = <String, List<_FilterEntry>>{};
    for (final entry in _filterEntries) {
      (index[entry.facet] ??= []).add(entry);
    }
    return index;
  }

  Iterable<_FilterEntry> filterCandidates(Map<String, int> counts) {
    if (counts.isEmpty) return const [];
    // כשמרבית הקטלוג מועמד, מעבר על הסדר הקיים זול מאיסוף ומיון.
    final limit = _filterEntries.length ~/ 8;
    if (counts.length > limit) return _filterEntries;

    final candidates = <_FilterEntry>[];
    for (final count in counts.entries) {
      if (count.value == 0) continue;
      final books = _filterEntriesByFacet[count.key];
      if (books == null) continue;
      if (candidates.length + books.length > limit) return _filterEntries;
      candidates.addAll(books);
    }
    return candidates..sort((a, b) => a.index.compareTo(b.index));
  }

  List<_FilterEntry> _collectFilterEntries() {
    final entries = <_FilterEntry>[];
    void collect(Category category) {
      final projection = of(category);
      for (final book in projection.orderedBooks) {
        entries.add(_FilterEntry(book, entries.length));
      }
      for (final sub in projection.orderedSubCategories) {
        collect(sub);
      }
    }

    collect(root);
    return entries;
  }
}

/// מידע שתלוי בקטלוג בלבד; נבנה רק כשענף נבדק או נפתח.
class _CategoryProjection {
  _CategoryProjection(this.category);

  final Category category;
  late final String path = category.path;
  late final String facet = FacetHelper.categoryFacet(category);

  late final List<Category> orderedSubCategories =
      category.subCategories.toList()
        ..sort(SearchCatalogueOrderHelper.subCategoryOrder(category));

  late final List<Book> orderedBooks = _orderedUniqueBooks();
  final _facetsByBook = Map<Book, String>.identity();

  String bookFacet(Book book) =>
      _facetsByBook[book] ??= FacetHelper.buildBookFacet(facet, book);

  List<Book> _orderedUniqueBooks() {
    final unique = <String, Book>{};
    for (final book in category.books) {
      unique[_dedupKey(book)] ??= book;
    }
    return unique.values.toList()..sort((a, b) => a.order.compareTo(b.order));
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

/// ספר ברשימת הסינון; הכותרת המנורמלת וה-facet מחושבים בפעם הראשונה שנדרשים.
class _FilterEntry {
  final Book book;
  final int index;

  _FilterEntry(this.book, this.index);

  late final String haystack = normalizeBookTitle(book.title).toLowerCase();

  late final String facet = FacetHelper.buildBookFacet(
    FacetHelper.resolveCategoryPath(book),
    book,
  );
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

/// שורה משוטחת אחת ברשימת הניווט (לבנייה עצלה ב-SuperListView.builder).
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

class _FacetPathIndex {
  _FacetPathIndex(Iterable<String> paths)
    : paths = paths.toList(growable: false);

  final List<String> paths;
  late final Set<String> _exactPaths = paths.toSet();
  late final Set<String> _ancestors = _collectAncestors();

  bool contains(String path) => _exactPaths.contains(path);

  bool hasDescendant(String path) => _ancestors.contains(path);

  Set<String> _collectAncestors() {
    final ancestors = <String>{};
    for (final path in _exactPaths) {
      for (
        var slash = path.indexOf('/');
        slash >= 0;
        slash = path.indexOf('/', slash + 1)
      ) {
        ancestors.add(path.substring(0, slash));
      }
    }
    return ancestors;
  }
}
