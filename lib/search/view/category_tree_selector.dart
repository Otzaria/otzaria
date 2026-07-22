import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/search/search_scope_preferences.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/utils/find_match_utils.dart';
import 'package:otzaria/search/utils/scope_tree.dart';
import 'package:otzaria/search/utils/search_catalogue_order_helper.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

class SearchScopeSelector extends StatefulWidget {
  final Set<String> selectedFacets;
  final ValueChanged<Set<String>> onSelectionChanged;
  final bool shrinkWrapManualSelector;

  const SearchScopeSelector({
    super.key,
    required this.selectedFacets,
    required this.onSelectionChanged,
    this.shrinkWrapManualSelector = false,
  });

  @override
  State<SearchScopeSelector> createState() => _SearchScopeSelectorState();
}

class _SearchScopeSelectorState extends State<SearchScopeSelector> {
  bool _isLoaded = false;
  bool _searchAllCategories = true;
  Set<String> _manualSelectedFacets = {};

  /// facets ממדיים (/base, /era/, /author/) שהתקבלו בבחירה — עוברים הלאה
  /// כמות שהם ואינם חלק מלוגיקת "כל הקטגוריות"/בחירה ידנית.
  Set<String> _dimensionFacets = {};

  static Set<String> _categoryPartOf(Set<String> selection) =>
      selection.where((facet) => !FacetHelper.isDimensionFacet(facet)).toSet();

  static Set<String> _dimensionPartOf(Set<String> selection) =>
      selection.where(FacetHelper.isDimensionFacet).toSet();

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant SearchScopeSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameFacets(oldWidget.selectedFacets, widget.selectedFacets)) {
      // Skip if the new selection matches the explicit selection state we emit.
      if (!_sameFacets(widget.selectedFacets, _selectionState)) {
        _applyExternalSelection(widget.selectedFacets);
      }
    }
  }

  Future<void> _initialize() async {
    final persisted = SearchScopePreferences.load();
    final explicitCategories = _categoryPartOf(widget.selectedFacets);
    _dimensionFacets = _dimensionPartOf(widget.selectedFacets);

    final hasExplicitManualSelection =
        explicitCategories.isNotEmpty && !explicitCategories.contains('/');
    final isExplicitAllSelection = explicitCategories.contains('/');

    _searchAllCategories = hasExplicitManualSelection
        ? false
        : isExplicitAllSelection
        ? true
        : persisted.searchAllCategories;
    _manualSelectedFacets = hasExplicitManualSelection
        ? explicitCategories
        : persisted.manualFacets;

    if (!mounted) {
      return;
    }

    setState(() {
      _isLoaded = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onSelectionChanged(_selectionState);
    });
  }

  void _applyExternalSelection(Set<String> selection) {
    if (!_isLoaded) {
      return;
    }

    final categories = _categoryPartOf(selection);
    final hasExplicitManualSelection =
        categories.isNotEmpty && !categories.contains('/');

    setState(() {
      _dimensionFacets = _dimensionPartOf(selection);
      if (hasExplicitManualSelection) {
        _searchAllCategories = false;
        _manualSelectedFacets = categories;
      } else if (categories.contains('/')) {
        _searchAllCategories = true;
      } else {
        _searchAllCategories = false;
        _manualSelectedFacets = {};
      }
    });
  }

  bool _sameFacets(Set<String> a, Set<String> b) {
    return a.length == b.length && a.containsAll(b);
  }

  Set<String> get _selectionState => {
    ...(_searchAllCategories ? const {'/'} : _manualSelectedFacets),
    ..._dimensionFacets,
  };

  void _setSearchAllCategories(bool value) {
    setState(() {
      _searchAllCategories = value;
    });
    SearchScopePreferences.save(
      searchAllCategories: _searchAllCategories,
      manualFacets: _manualSelectedFacets,
    );
    widget.onSelectionChanged(_selectionState);
  }

  void _onManualSelectionChanged(Set<String> selection) {
    setState(() {
      // עץ הקטגוריות מחזיר את הבחירה כולל ה-facets הממדיים ששומרו בה —
      // מפצלים כדי שההעדפה הידנית של הקטגוריות תישאר נקייה מממדים.
      _dimensionFacets = _dimensionPartOf(selection);
      _manualSelectedFacets = _categoryPartOf(selection);
    });
    SearchScopePreferences.save(
      searchAllCategories: _searchAllCategories,
      manualFacets: _manualSelectedFacets,
    );
    if (!_searchAllCategories) {
      widget.onSelectionChanged(_selectionState);
    }
  }

  void _resetManualSelection() {
    setState(() {
      _manualSelectedFacets = {};
    });
    SearchScopePreferences.save(
      searchAllCategories: _searchAllCategories,
      manualFacets: _manualSelectedFacets,
    );
    if (!_searchAllCategories) {
      widget.onSelectionChanged(_selectionState);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final colorScheme = Theme.of(context).colorScheme;
    final manualCount = _manualSelectedFacets.length;
    final helperText = _searchAllCategories
        ? 'מופעל כברירת מחדל. כבה כדי לבחור קטגוריות או ספרים ידנית.'
        : manualCount == 0
        ? 'אפשר לחפש בעץ ולבחור קטגוריות או ספרים. עד שתיבחר בחירה ידנית, החיפוש יישאר בכל הקטגוריות.'
        : 'נשמרו $manualCount פריטים לבחירה הידנית הכללית.';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: AppTokens.borderRadiusAll,
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Icon(
                FluentIcons.globe_24_regular,
                size: 20,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'חיפוש בכל הקטגוריות',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      helperText,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _searchAllCategories,
                onChanged: _setSearchAllCategories,
              ),
            ],
          ),
        ),
        if (!_searchAllCategories) ...[
          const SizedBox(height: 12),
          if (widget.shrinkWrapManualSelector)
            CategoryTreeSelector(
              selectedFacets: _manualSelectedFacets,
              onSelectionChanged: _onManualSelectionChanged,
              onResetSelection: _resetManualSelection,
              shrinkWrap: true,
            )
          else
            Flexible(
              child: CategoryTreeSelector(
                selectedFacets: _manualSelectedFacets,
                onSelectionChanged: _onManualSelectionChanged,
                onResetSelection: _resetManualSelection,
              ),
            ),
        ],
      ],
    );
  }
}

/// וידג'ט לבחירת קטגוריות לחיפוש עם עץ היררכי מתקפל
/// מאפשר בחירת קטגוריות ותת-קטגוריות לפני ביצוע חיפוש
class CategoryTreeSelector extends StatefulWidget {
  /// הקטגוריות שנבחרו - רשימת נתיבים (facets)
  final Set<String> selectedFacets;

  /// קריאה חוזרת כשהבחירה משתנה
  final ValueChanged<Set<String>> onSelectionChanged;

  /// קריאה חוזרת לאיפוס בחירה ידנית בלי לשנות את מצב הסוויץ' בהורה.
  final VoidCallback? onResetSelection;

  final bool shrinkWrap;

  const CategoryTreeSelector({
    super.key,
    required this.selectedFacets,
    required this.onSelectionChanged,
    this.onResetSelection,
    this.shrinkWrap = false,
  });

  @override
  State<CategoryTreeSelector> createState() => _CategoryTreeSelectorState();
}

class _CategoryTreeSelectorState extends State<CategoryTreeSelector> {
  static const int _minSearchQueryLength = 2;

  final Map<String, bool> _expansionState = {};
  final TextEditingController _searchController = TextEditingController();

  // נבנה בכל build מה-Library הנוכחי; זמין לפונקציות ה-toggle.
  ScopeTree? _tree;

  /// facets ממדיים (/base, /era/, /author/) שרוכבים על אותה רשימת בחירה —
  /// אינם נתיבי קטגוריה, ולכן לוגיקת העץ מתעלמת מהם, אבל כל שינוי בחירה
  /// שנפלט החוצה משמר אותם כמות שהם.
  Set<String> get _dimensionFacets =>
      widget.selectedFacets.where(FacetHelper.isDimensionFacet).toSet();

  /// בחירת הקטגוריות/ספרים בלבד — הקלט היחיד לכל חישובי מצב העץ.
  Set<String> get _categoryFacets => widget.selectedFacets
      .where((facet) => !FacetHelper.isDimensionFacet(facet))
      .toSet();

  /// פולט בחירת קטגוריות חדשה תוך צירוף ה-facets הממדיים ששמורים ברשימה.
  void _emitSelection(Set<String> categorySelection) {
    widget.onSelectionChanged({...categorySelection, ..._dimensionFacets});
  }

  bool get _isAllSelected => _categoryFacets.contains('/');

  String get _normalizedSearchQuery =>
      normalizeFindQuery(_searchController.text);

  bool get _hasActiveSearch =>
      _normalizedSearchQuery.length >= _minSearchQueryLength;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // --- לוגיקת בחירה ---

  void _toggleAll(bool select) {
    if (select) {
      _emitSelection({'/'}); // הכל נבחר
    } else {
      _emitSelection({}); // שום דבר לא נבחר
    }
  }

  void _toggleCategory(Category category, bool select) {
    if (_tree == null) return;
    _toggleFacet(category.path, select);
  }

  // --- לוגיקת תצוגת מצב ---

  /// מחזיר true/false/null (tristate) לצ'קבוקס
  bool? _getCategoryCheckState(Category category) =>
      _tree?.categoryCheckState(category.path, _categoryFacets) ?? false;

  // --- בנייה ---

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LibraryBloc, LibraryState>(
      builder: (context, libraryState) {
        if (libraryState.library == null) {
          return const SizedBox.shrink();
        }

        final library = libraryState.library!;
        final tree = ScopeTree.fromLibrary(library);
        _tree = tree;
        final topCategories = library.subCategories.toList()
          ..sort(
            (a, b) => SearchCatalogueOrderHelper.topCategoryOrder(
              a,
            ).compareTo(SearchCatalogueOrderHelper.topCategoryOrder(b)),
          );
        final searchResults = _hasActiveSearch
            ? tree.search(_normalizedSearchQuery)
            : const <ScopeSearchResultItem>[];

        final treeBody = Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.3),
            ),
            borderRadius: AppTokens.borderRadiusAll,
          ),
          child: ClipRRect(
            borderRadius: AppTokens.borderRadiusAll,
            child: _hasActiveSearch
                ? _buildSearchResultsView(context, searchResults)
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final category in topCategories)
                          _buildCategoryNode(context, category, 0),
                      ],
                    ),
                  ),
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            const SizedBox(height: 8),
            _buildSearchField(context),
            const SizedBox(height: 8),
            if (widget.shrinkWrap)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: treeBody,
              )
            else
              Expanded(child: treeBody),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final hasSelection = _categoryFacets.isNotEmpty && !_isAllSelected;

    return Row(
      children: [
        Icon(
          FluentIcons.library_24_regular,
          size: 18,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Text(
          'חיפוש בקטגוריות',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const Spacer(),
        if (hasSelection)
          Tooltip(
            message: 'איפוס בחירה',
            child: IconButton(
              icon: const Icon(FluentIcons.arrow_reset_24_regular, size: 16),
              onPressed: widget.onResetSelection ?? () => _toggleAll(false),
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              padding: const EdgeInsets.all(6),
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.secondaryContainer,
                foregroundColor: Theme.of(
                  context,
                ).colorScheme.onSecondaryContainer,
                shape: AppTokens.roundedShape,
              ),
            ),
          ),
        Checkbox(
          value: _isAllSelected
              ? true
              : _categoryFacets.isEmpty
              ? false
              : null,
          tristate: true,
          onChanged: (value) => _toggleAll(value == true),
        ),
        Text(
          'הכל',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return RtlTextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'איתור קטגוריה או ספר...',
        prefixIcon: const Icon(FluentIcons.search_24_regular),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  setState(_searchController.clear);
                },
                icon: const Icon(FluentIcons.dismiss_24_regular),
              ),
        border: OutlineInputBorder(
          borderRadius: AppTokens.borderRadiusAll,
        ),
        isDense: true,
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildSearchResultsView(
    BuildContext context,
    List<ScopeSearchResultItem> results,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_normalizedSearchQuery.length < _minSearchQueryLength) {
      return Center(
        child: Text(
          'הקלד לפחות $_minSearchQueryLength תווים כדי לחפש.',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    if (results.isEmpty) {
      return Center(
        child: Text(
          'לא נמצאו קטגוריות או ספרים תואמים.',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'נמצאו ${results.length} תוצאות',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  SizedBox(
                    height: 30,
                    child: ActionButton.recommended(
                      text: 'בחר הכל',
                      icon: FluentIcons.checkbox_checked_24_regular,
                      onPressed: () => _selectAllSearchResults(results),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 30,
                    child: ActionButton.neutral(
                      text: 'נקה',
                      icon: FluentIcons.eraser_24_regular,
                      onPressed: () => _clearSearchResultsSelection(results),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final item = results[index];
              final isSelected = _isFacetCovered(item.facet);
              return InkWell(
                onTap: () => _toggleFacet(item.facet, !isSelected),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primaryContainer.withValues(alpha: 0.25)
                        : null,
                    border: Border(
                      bottom: BorderSide(
                        color: colorScheme.outline.withValues(alpha: 0.15),
                      ),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: isSelected,
                        onChanged: (_) => _toggleFacet(item.facet, !isSelected),
                      ),
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          item.isBook
                              ? FluentIcons.book_24_regular
                              : FluentIcons.folder_24_regular,
                          size: 18,
                          color: item.isBook
                              ? colorScheme.onSurfaceVariant
                              : colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: item.isBook
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                                color: colorScheme.onSurface,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (item.subtitle.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                item.subtitle,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _selectAllSearchResults(List<ScopeSearchResultItem> results) {
    final tree = _tree;
    if (tree == null) return;
    var selection = _categoryFacets;
    for (final result in results) {
      selection = tree.selectFacet(result.facet, selection);
    }
    _emitSelection(selection);
  }

  void _clearSearchResultsSelection(List<ScopeSearchResultItem> results) {
    final tree = _tree;
    if (tree == null) return;
    var selection = _categoryFacets;
    for (final result in results) {
      selection = tree.deselectFacet(result.facet, selection);
    }
    _emitSelection(selection);
  }

  bool _isFacetCovered(String facet) =>
      _tree?.isFacetCovered(facet, _categoryFacets) ?? false;

  void _toggleFacet(String facet, bool select) {
    final tree = _tree;
    if (tree == null) return;
    final nextSelection = select
        ? tree.selectFacet(facet, _categoryFacets)
        : tree.deselectFacet(facet, _categoryFacets);
    _emitSelection(nextSelection);
  }

  Widget _buildCategoryNode(
    BuildContext context,
    Category category,
    int level,
  ) {
    final hasChildren = category.subCategories.isNotEmpty;
    final isExpanded = _expansionState[category.path] ?? false;
    final checkState = _getCategoryCheckState(category);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.only(
            right: 8.0 + (level * 20.0),
            left: 8.0,
            top: 4.0,
            bottom: 4.0,
          ),
          child: Row(
            children: [
              // צ'קבוקס - תמיד פעיל
              SizedBox(
                width: 28,
                height: 28,
                child: Checkbox(
                  value: checkState,
                  tristate: true,
                  onChanged: (value) => _toggleCategory(
                    category,
                    // tristate: null → true → false → true
                    // כשהמצב הנוכחי true/null → ביטול; false → בחירה
                    checkState != false ? false : true,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // אייקון תיקייה (לחיץ להרחבה)
              InkWell(
                onTap: hasChildren
                    ? () => setState(() {
                        _expansionState[category.path] = !isExpanded;
                      })
                    : null,
                borderRadius: AppTokens.borderRadiusAll,
                child: Icon(
                  hasChildren
                      ? (isExpanded
                            ? FluentIcons.folder_open_24_regular
                            : FluentIcons.folder_24_regular)
                      : FluentIcons.folder_24_regular,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              // שם הקטגוריה (לחיץ להרחבה)
              Expanded(
                child: InkWell(
                  onTap: hasChildren
                      ? () => setState(() {
                          _expansionState[category.path] = !isExpanded;
                        })
                      : null,
                  child: Text(
                    category.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: level == 0
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              // חץ הרחבה
              if (hasChildren)
                InkWell(
                  onTap: () => setState(() {
                    _expansionState[category.path] = !isExpanded;
                  }),
                  borderRadius: AppTokens.borderRadiusAll,
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Icon(
                      isExpanded
                          ? FluentIcons.chevron_up_24_regular
                          : FluentIcons.chevron_down_24_regular,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // ילדים
        if (isExpanded && hasChildren)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: _buildSortedChildren(context, category, level + 1),
          ),
      ],
    );
  }

  List<Widget> _buildSortedChildren(
    BuildContext context,
    Category category,
    int level,
  ) {
    final sorted = category.subCategories.toList()
      ..sort(
        (a, b) => SearchCatalogueOrderHelper.normalizeOrder(
          a.order,
        ).compareTo(SearchCatalogueOrderHelper.normalizeOrder(b.order)),
      );

    return [
      for (final sub in sorted) _buildCategoryNode(context, sub, level),
    ];
  }
}
