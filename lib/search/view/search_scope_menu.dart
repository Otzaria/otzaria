import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/utils/find_match_utils.dart';
import 'package:otzaria/search/utils/foundational_book_classifier.dart';
import 'package:otzaria/search/utils/scope_tree.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// כפתור-שדה אחד המרכז את כל סינון היקף החיפוש: הקלדה מסננת בזמן אמת, ותפריט
/// עם ניווט drill-down פנימי (עץ הקטגוריות/ספרים, ספרי יסוד, תקופה, מחבר).
/// נשלט (controlled): מקבל את הבחירה הנוכחית ([selected], כולל facets
/// קטגוריאליים וממדיים יחד) ומדווח כל שינוי ב-[onChanged].
class SearchScopeMenuButton extends StatefulWidget {
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  /// רוחב השדה (העוגן). ברירת המחדל מתאימה לדיאלוג; בסרגל התוצאות מועבר
  /// [double.infinity] כדי להתרחב לרוחב הסרגל הניתן-לשינוי.
  final double width;

  /// האם להציג chips של הבחירה מתחת לשדה. בדיאלוג — כן; בסרגל התוצאות
  /// מועבר `false` (ה-chips היו מזיזים את העץ), ובמקומם מונה קומפקטי בשדה.
  final bool showChips;

  const SearchScopeMenuButton({
    super.key,
    required this.selected,
    required this.onChanged,
    this.width = 300,
    this.showChips = true,
  });

  @override
  State<SearchScopeMenuButton> createState() => _SearchScopeMenuButtonState();
}

class _SearchScopeMenuButtonState extends State<SearchScopeMenuButton> {
  final GlobalKey _anchorKey = GlobalKey();
  final OverlayPortalController _portal = OverlayPortalController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _fieldFocus = FocusNode();
  final GlobalKey<_ScopeMenuPanelState> _panelKey = GlobalKey();
  final Object _tapGroup = Object();

  Set<int> _baseBookIds = const {};
  Set<int> _baseUserBookIds = const {};

  Library? _library;
  ScopeTree? _treeCache;
  Future<ScopeTree>? _treeFuture;
  List<BookScopeNode>? _baseBookNodesCache;
  Future<void>? _baseBookNodesFuture;
  int _baseBookGeneration = 0;

  Future<ScopeTree?> _ensureTree() async {
    final library = _library;
    if (library == null) return null;
    final cached = _treeCache;
    if (cached != null) return cached;

    final pending = _treeFuture;
    if (pending != null) {
      final tree = await pending;
      return identical(library, _library) ? tree : null;
    }

    final future = ScopeTree.fromLibraryAsync(library);
    _treeFuture = future;
    try {
      final tree = await future;
      if (!mounted || !identical(library, _library)) return null;
      setState(() => _treeCache = tree);
      return tree;
    } finally {
      if (identical(_treeFuture, future)) _treeFuture = null;
    }
  }

  Future<void> _ensureBaseBookNodes() async {
    if (_baseBookNodesCache != null) return;
    if (_baseBookNodesFuture != null) return;

    final library = _library;
    if (library == null) return;
    final generation = _baseBookGeneration;
    final future = _classifyBaseBooks(library);
    _baseBookNodesFuture = future;
    try {
      await future;
    } finally {
      if (identical(_baseBookNodesFuture, future)) {
        _baseBookNodesFuture = null;
      }
    }
    if (mounted &&
        identical(library, _library) &&
        generation != _baseBookGeneration) {
      await _ensureBaseBookNodes();
    }
  }

  Future<void> _classifyBaseBooks(Library library) async {
    final generation = _baseBookGeneration;
    final tree = await _ensureTree();
    if (tree == null || !identical(library, _library)) return;

    final result = <BookScopeNode>[];
    final books = tree.allBookNodes();
    for (var i = 0; i < books.length; i++) {
      final node = books[i];
      if (_isBaseBook(node.book)) result.add(node);
      if ((i + 1) % 200 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (!mounted ||
        !identical(library, _library) ||
        generation != _baseBookGeneration) {
      return;
    }
    setState(() => _baseBookNodesCache = result);
  }

  @override
  void initState() {
    super.initState();
    _loadBaseBookIds();
    _fieldFocus.addListener(_onFocusChanged);
    _searchController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _fieldFocus.removeListener(_onFocusChanged);
    _fieldFocus.dispose();
    _searchController.removeListener(_onTextChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    // פתיחה בלבד בעת קבלת פוקוס. סגירה אינה תלויה בפוקוס — לחיצה על פריט
    // בתפריט מאבדת את פוקוס השדה (התנהגות EditableText), והסגירה מתבצעת רק
    // בלחיצה מחוץ לתפריט או ב-Escape.
    if (_fieldFocus.hasFocus && _library != null && !_portal.isShowing) {
      _portal.show();
    }
  }

  void _close() {
    if (_portal.isShowing) _portal.hide();
    if (_fieldFocus.hasFocus) _fieldFocus.unfocus();
  }

  void _onTextChanged() => setState(() {});

  Future<void> _loadBaseBookIds() async {
    final repo = SqliteDataProvider.instance.repository;
    final ids = repo == null ? <int>{} : await repo.loadBaseBookIds();
    var userIds = <int>{};
    final userRepo = UserBooksDatabaseHolder.instance.repositoryIfInitialized;
    if (userRepo != null) {
      try {
        userIds = await userRepo.loadBaseBookIds();
      } catch (_) {
        userIds = <int>{};
      }
    }
    if (mounted) {
      setState(() {
        _baseBookIds = ids;
        _baseUserBookIds = userIds;
        _baseBookGeneration++;
        _baseBookNodesCache = null;
      });
    }
  }

  bool _isBaseBook(Book book) {
    if (FoundationalBookClassifier.classify(
          FacetHelper.resolveCategoryPath(book),
          book.title,
        ) !=
        null) {
      return true;
    }
    final id = book.id;
    if (id == null) return false;
    return book.isUserBook
        ? _baseUserBookIds.contains(id)
        : _baseBookIds.contains(id);
  }

  KeyEventResult _handleFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final panel = _panelKey.currentState;
    if (panel == null) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        panel.moveHighlight(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        panel.moveHighlight(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        panel.activateHighlight();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.space:
        if (_searchController.text.isEmpty) {
          panel.toggleHighlight();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.escape:
        if (!panel.goBack()) _fieldFocus.unfocus();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.backspace:
        if (_searchController.text.isEmpty && panel.goBack()) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LibraryBloc, LibraryState>(
      builder: (context, libraryState) {
        final library = libraryState.library;
        final enabled = library != null;
        if (!identical(library, _library)) {
          _library = library;
          _treeCache = null;
          _treeFuture = null;
          _baseBookGeneration++;
          _baseBookNodesCache = null;
          _baseBookNodesFuture = null;
        }

        return OverlayPortal(
          controller: _portal,
          overlayChildBuilder: _buildOverlay,
          child: SizedBox(
            width: widget.width,
            child: widget.showChips
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // העוגן הוא השדה בלבד — כך התפריט לא זז כשה-chips משתנים.
                      KeyedSubtree(
                        key: _anchorKey,
                        child: _buildField(context, enabled: enabled),
                      ),
                      _buildActiveChips(context),
                    ],
                  )
                : KeyedSubtree(
                    key: _anchorKey,
                    child: _buildField(context, enabled: enabled),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildField(BuildContext context, {required bool enabled}) {
    final colorScheme = Theme.of(context).colorScheme;
    // המונה בשדה מחליף את ה-chips רק כשהם מוסתרים (בסרגל התוצאות).
    final filters = _activeFilters();
    final showBadge = !widget.showChips && filters.isNotEmpty;

    return TapRegion(
      groupId: _tapGroup,
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: _handleFieldKey,
        child: RtlTextField(
          controller: _searchController,
          focusNode: _fieldFocus,
          enabled: enabled,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: colorScheme.surfaceContainerHigh,
            hintText: 'סינון לפי ספר או מחבר',
            hintStyle: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
            prefixIcon: !showBadge
                ? Icon(
                    FluentIcons.filter_24_regular,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  )
                : Tooltip(
                    message: filters.map((f) => f.label).join(', '),
                    child: Badge(
                      label: Text('${filters.length}'),
                      offset: const Offset(-2, 2),
                      child: Icon(
                        FluentIcons.filter_24_regular,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(FluentIcons.dismiss_24_regular, size: 18),
                    tooltip: 'ניקוי',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _searchController.clear(),
                  )
                : Icon(
                    FluentIcons.chevron_down_16_regular,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
            border: OutlineInputBorder(
              borderRadius: AppTokens.borderRadiusAll,
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppTokens.borderRadiusAll,
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveChips(BuildContext context) {
    final filters = _activeFilters();
    if (filters.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final f in filters)
            InputChip(
              avatar: f.partial
                  ? Icon(
                      FluentIcons.checkbox_indeterminate_24_regular,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )
                  : null,
              label: Text(f.label, style: const TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onDeleted: f.onRemove,
            ),
        ],
      ),
    );
  }

  /// הסינונים הפעילים ל-chips / למונה שבשדה. בחירת קטגוריות/ספרים ספציפיים
  /// מיוצגת בפריט *אחד* ("כל הספרים") ולא שם לכל פריט. בחירת "ספרי יסוד"
  /// ככלל אינה מגיעה לכאן — היא facet ממדי (`/base`) ומתויגת בלופ שמתחת.
  List<({String label, bool partial, VoidCallback onRemove})> _activeFilters() {
    final result = <({String label, bool partial, VoidCallback onRemove})>[];
    final categories = FacetHelper.categoryFacetsOf(
      widget.selected,
    ).where((f) => f != '/').toList();
    final dimensions = FacetHelper.dimensionFacetsOf(widget.selected).toList();

    if (categories.isNotEmpty) {
      result.add((
        label: 'כל הספרים',
        partial: true,
        onRemove: () => widget.onChanged(dimensions.toSet()),
      ));
    }

    for (final facet in dimensions) {
      final String label;
      if (facet == FacetHelper.baseDimensionFacet) {
        label = 'ספרי יסוד';
      } else if (facet.startsWith(FacetHelper.eraDimensionPrefix)) {
        label = facet.substring(FacetHelper.eraDimensionPrefix.length);
      } else if (facet.startsWith(FacetHelper.authorDimensionPrefix)) {
        label = facet.substring(FacetHelper.authorDimensionPrefix.length);
      } else {
        label = facet;
      }
      result.add((
        label: label,
        partial: false,
        onRemove: () {
          final next = Set<String>.from(widget.selected)..remove(facet);
          widget.onChanged(next);
        },
      ));
    }
    return result;
  }

  Widget _buildOverlay(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final anchorBox =
        _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (anchorBox == null ||
        overlayBox == null ||
        !anchorBox.hasSize ||
        !overlayBox.hasSize) {
      return const SizedBox.shrink();
    }
    final anchorRect = MatrixUtils.transformRect(
      anchorBox.getTransformTo(overlayBox),
      Offset.zero & anchorBox.size,
    );

    return CustomSingleChildLayout(
      delegate: _MenuLayoutDelegate(anchorRect: anchorRect),
      child: TapRegion(
        groupId: _tapGroup,
        onTapOutside: (_) => _close(),
        child: Material(
          elevation: 8,
          color: colorScheme.surfaceContainerHigh,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: AppTokens.borderRadiusAll,
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          // הפוקוס נשמר בשדה לאחר כל פעולה (onKeepFocus) כדי לאפשר הקלדה
          // וניווט מקלדת רציפים גם אחרי לחיצה בעכבר על פריט בתפריט.
          child: ExcludeFocus(
            child: _ScopeMenuPanel(
              key: _panelKey,
              tree: _treeCache,
              baseBookNodes: _baseBookNodesCache,
              onRequireTree: () => unawaited(_ensureTree()),
              onRequireBaseBooks: () => unawaited(_ensureBaseBookNodes()),
              searchController: _searchController,
              selected: widget.selected,
              onChanged: widget.onChanged,
              onKeepFocus: () => _fieldFocus.requestFocus(),
            ),
          ),
        ),
      ),
    );
  }
}

/// ממקם את התפריט מתחת לשדה (או מעליו כשאין מקום), מוצמד לגבולות המסך
/// כדי שלא יחרוג מהחלון. הרוחב שווה לרוחב השדה (סגנון תפריט סינון M3).
class _MenuLayoutDelegate extends SingleChildLayoutDelegate {
  final Rect anchorRect;

  const _MenuLayoutDelegate({required this.anchorRect});

  static const double _gap = 4;
  static const double _margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final spaceBelow =
        constraints.maxHeight - anchorRect.bottom - _gap - _margin;
    final spaceAbove = anchorRect.top - _gap - _margin;
    final maxHeight = math.min(440.0, math.max(spaceBelow, spaceAbove));
    return BoxConstraints(
      minWidth: anchorRect.width,
      maxWidth: anchorRect.width,
      maxHeight: math.max(0.0, maxHeight),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxLeft = size.width - childSize.width - _margin;
    final left = (anchorRect.right - childSize.width)
        .clamp(_margin, math.max(_margin, maxLeft))
        .toDouble();

    final below = anchorRect.bottom + _gap;
    final double top;
    if (below + childSize.height <= size.height - _margin) {
      top = below;
    } else {
      final above = anchorRect.top - _gap - childSize.height;
      top = above >= _margin
          ? above
          : (size.height - childSize.height - _margin)
                .clamp(_margin, size.height)
                .toDouble();
    }
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(_MenuLayoutDelegate oldDelegate) =>
      oldDelegate.anchorRect != anchorRect;
}

/// התקופות המוצגות לסינון. 'שאר מפרשים' לעולם לא מוטבעת, ו'תורה שבכתב'
/// אינה תקופת פרשנות רלוונטית לסינון.
final List<String> _eraNames = [
  for (final era in CommentaryEra.values)
    if (era != CommentaryEra.other && era != CommentaryEra.torahShebichtav)
      era.hebrewName,
];

enum _View { root, categories, base }

/// פריט בתפריט. [isHeader] = כותרת-קבוצה לא-אינטראקטיבית (מדולגת בניווט
/// המקלדת). [onDrill] — אם קיים, השורה מובילה למעבר מסך פנימי (drill-down).
class _MenuItem {
  final String label;
  final String subtitle;
  final IconData? icon;
  final bool useRtlIcon;
  final bool? check;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onTap;
  final VoidCallback? onDrill;

  /// פעולת "רק" — בחירת השורה הזו בלבד תוך ניקוי כל שאר הבחירה.
  final VoidCallback? onOnly;
  final bool isHeader;

  bool get isDrill => onDrill != null;

  const _MenuItem({
    required this.label,
    this.subtitle = '',
    required this.icon,
    this.useRtlIcon = false,
    required this.check,
    this.onToggle,
    this.onTap,
    this.onDrill,
    this.onOnly,
  }) : isHeader = false;

  const _MenuItem.header(this.label)
    : subtitle = '',
      icon = null,
      useRtlIcon = false,
      check = null,
      onToggle = null,
      onTap = null,
      onDrill = null,
      onOnly = null,
      isHeader = true;
}

class _ScopeMenuPanel extends StatefulWidget {
  final ScopeTree? tree;
  final List<BookScopeNode>? baseBookNodes;
  final VoidCallback onRequireTree;
  final VoidCallback onRequireBaseBooks;
  final TextEditingController searchController;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final VoidCallback onKeepFocus;

  const _ScopeMenuPanel({
    super.key,
    required this.tree,
    required this.baseBookNodes,
    required this.onRequireTree,
    required this.onRequireBaseBooks,
    required this.searchController,
    required this.selected,
    required this.onChanged,
    required this.onKeepFocus,
  });

  @override
  State<_ScopeMenuPanel> createState() => _ScopeMenuPanelState();
}

class _ScopeMenuPanelState extends State<_ScopeMenuPanel> {
  static const int _minSearchQueryLength = 2;
  static const int _authorSuggestionsLimit = 15;
  static const double _rowHeight = 44;

  final ScrollController _scrollController = ScrollController();

  late Set<String> _selection;
  _View _view = _View.root;
  final List<ScopeNode> _stack = [];
  int _highlight = 0;
  int _hoveredRow = -1;

  List<String> _authorResults = const [];
  int _authorRequestId = 0;
  Set<String> _baseFacetSet = const {};

  @override
  void initState() {
    super.initState();
    _selection = Set<String>.from(widget.selected);
    _syncBaseFacetSet();
    widget.searchController.addListener(_onQueryChanged);
  }

  @override
  void didUpdateWidget(covariant _ScopeMenuPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.baseBookNodes, widget.baseBookNodes)) {
      _syncBaseFacetSet();
    }
    if (oldWidget.tree != null && widget.tree == null) {
      _view = _View.root;
      _stack.clear();
      _highlight = 0;
    }
    final incoming = widget.selected;
    if (incoming.length != _selection.length ||
        !incoming.containsAll(_selection)) {
      _selection = Set<String>.from(incoming);
    }
    if (_hasActiveSearch) {
      widget.onRequireTree();
    } else if (_view == _View.base && widget.baseBookNodes == null) {
      widget.onRequireBaseBooks();
    } else if (_view == _View.categories && widget.tree == null) {
      widget.onRequireTree();
    }
  }

  void _syncBaseFacetSet() {
    _baseFacetSet = {
      for (final node in widget.baseBookNodes ?? const <BookScopeNode>[])
        node.facet,
    };
  }

  @override
  void dispose() {
    widget.searchController.removeListener(_onQueryChanged);
    _scrollController.dispose();
    super.dispose();
  }

  String get _normalizedQuery =>
      normalizeFindQuery(widget.searchController.text);
  bool get _hasActiveSearch => _normalizedQuery.length >= _minSearchQueryLength;

  Set<String> get _categoryPart =>
      FacetHelper.categoryFacetsOf(_selection).toSet();
  Set<String> get _dimensionPart =>
      FacetHelper.dimensionFacetsOf(_selection).toSet();

  void _onQueryChanged() {
    setState(() => _highlight = 0);
    if (_hasActiveSearch) widget.onRequireTree();
    _fetchAuthors();
  }

  Future<void> _fetchAuthors() async {
    if (!_hasActiveSearch) {
      if (_authorResults.isNotEmpty) setState(() => _authorResults = const []);
      return;
    }
    final requestId = ++_authorRequestId;
    final repo = SqliteDataProvider.instance.repository;
    if (repo == null) return;
    try {
      final names = await repo.searchAuthorNames(
        widget.searchController.text.trim(),
        limit: _authorSuggestionsLimit,
      );
      if (!mounted || requestId != _authorRequestId) return;
      setState(() => _authorResults = names);
    } catch (_) {
      if (!mounted || requestId != _authorRequestId) return;
      setState(() => _authorResults = const []);
    }
  }

  void _apply(Set<String> next) {
    setState(() => _selection = next);
    widget.onChanged(Set<String>.from(next));
    widget.onKeepFocus();
  }

  void _setCategorySelection(Set<String> nextCategory) {
    _apply({...nextCategory, ..._dimensionPart});
  }

  void _toggleCategoryFacet(String facet, bool select) {
    final tree = widget.tree;
    if (tree == null) return;
    final nextCategory = select
        ? tree.selectFacet(facet, _categoryPart)
        : tree.deselectFacet(facet, _categoryPart);
    _setCategorySelection(nextCategory);
  }

  void _toggleDimension(String facet, bool select) {
    final next = Set<String>.from(_selection);
    if (select) {
      next.add(facet);
    } else {
      next.remove(facet);
    }
    _apply(next);
  }

  /// מסיר את כל הסימונים (כולל "כל הספרים") — מאפשר לבחור למשל רק ספר יסוד אחד.
  void _clearAll() => _apply(<String>{});

  /// בחירת "רק" — הבחירה מוחלפת ב-[facet] בלבד.
  void _selectOnly(String facet) => _apply({facet});

  /// כל ספרי היסוד תחת [folderFacet], בסדר הספרייה.
  List<BookScopeNode> _baseUnder(String folderFacet) => [
    for (final n in widget.baseBookNodes ?? const <BookScopeNode>[])
      if (n.facet.startsWith('$folderFacet/')) n,
  ];

  // ── ניווט drill-down ─────────────────────────────────────────────────────

  void _drillInto(ScopeNode node) {
    setState(() {
      _stack.add(node);
      _highlight = 0;
    });
  }

  void _enterView(_View view) {
    if (view == _View.base) {
      widget.onRequireBaseBooks();
    } else if (view == _View.categories) {
      widget.onRequireTree();
    }
    setState(() {
      _view = view;
      _stack.clear();
      _highlight = 0;
    });
  }

  void _goToDepth(int depth) {
    setState(() {
      _stack.removeRange(depth, _stack.length);
      _highlight = 0;
    });
  }

  /// חזרה רמה אחת. מחזיר false אם כבר בשורש (הכפתור יסגור אז את התפריט).
  bool goBack() {
    if (_view == _View.root) return false;
    setState(() {
      if (_stack.isNotEmpty) {
        _stack.removeLast();
      } else {
        _view = _View.root;
      }
      _highlight = 0;
    });
    return true;
  }

  // ── ניווט מקלדת ──────────────────────────────────────────────────────────

  List<int> _selectableIndices(List<_MenuItem> items) => [
    for (var i = 0; i < items.length; i++)
      if (!items[i].isHeader) i,
  ];

  void moveHighlight(int delta) {
    final items = _currentItems();
    final selectable = _selectableIndices(items);
    if (selectable.isEmpty) return;
    final pos = selectable.indexOf(_highlight);
    final nextPos = (pos < 0 ? 0 : pos + delta).clamp(0, selectable.length - 1);
    setState(() => _highlight = selectable[nextPos]);
    _scrollToHighlight();
  }

  void activateHighlight() {
    final items = _currentItems();
    if (_highlight < 0 || _highlight >= items.length) return;
    final item = items[_highlight];
    if (item.isDrill) {
      item.onDrill!();
    } else if (item.check == null && item.onTap != null) {
      item.onTap!();
    } else {
      item.onToggle?.call(!(item.check ?? false));
    }
  }

  void toggleHighlight() {
    final items = _currentItems();
    if (_highlight < 0 || _highlight >= items.length) return;
    final item = items[_highlight];
    item.onToggle?.call(!(item.check ?? false));
  }

  void _scrollToHighlight() {
    if (!_scrollController.hasClients) return;
    final target = _highlight * _rowHeight;
    final min = _scrollController.position.minScrollExtent;
    final max = _scrollController.position.maxScrollExtent;
    _scrollController.animateTo(
      (target - _rowHeight).clamp(min, max),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  // ── בניית הפריטים לפי המצב ────────────────────────────────────────────────

  List<_MenuItem> _currentItems() {
    if (_hasActiveSearch) {
      return widget.tree == null ? const [] : _searchItems();
    }
    switch (_view) {
      case _View.root:
        return _rootItems();
      case _View.categories:
        return widget.tree == null ? const [] : _categoryLevelItems();
      case _View.base:
        return widget.tree == null || widget.baseBookNodes == null
            ? const []
            : _baseLevelItems();
    }
  }

  _MenuItem _bookItem(BookScopeNode node) {
    final tree = widget.tree!;
    return _MenuItem(
      label: node.title,
      subtitle: node.subtitle,
      icon: OtzariaIcons.book_24_regular,
      useRtlIcon: true,
      check: tree.isFacetCovered(node.facet, _categoryPart),
      onToggle: (v) => _toggleCategoryFacet(node.facet, v),
    );
  }

  _MenuItem _folderItem(ScopeNode node) {
    final tree = widget.tree!;
    return _MenuItem(
      label: node.title,
      icon: FluentIcons.folder_24_regular,
      // סימון תיקיה בוחר את התיקיה כולה; לחיצה על השורה נכנסת פנימה (מעבר מסך).
      check: tree.categoryCheckState(node.facet, _categoryPart),
      onToggle: (v) => _toggleCategoryFacet(node.facet, v),
      onDrill: () => _drillInto(node),
    );
  }

  /// רמת "כל הספרים": ילדי הרמה הנוכחית, עם קיפול שרשרת ילד-יחיד.
  List<_MenuItem> _categoryLevelItems() {
    final tree = widget.tree!;
    final nodes = _stack.isEmpty
        ? tree.visibleChildren(null)
        : tree.expandedChildren(_stack.last);
    final out = <_MenuItem>[];
    for (final node in nodes) {
      if (node is BookScopeNode) {
        out.add(_bookItem(node));
        continue;
      }
      final single = tree.singleBookOf(node);
      out.add(single != null ? _bookItem(single) : _folderItem(node));
    }
    return out;
  }

  /// רמת "ספרי יסוד": בשורש — תיקיות ראשיות עם ספרי יסוד; בתוך תיקיה — רשימה
  /// שטוחה של *כל* ספרי היסוד שתחתיה (ללא ירידה לתת-תיקיות).
  List<_MenuItem> _baseLevelItems() {
    final tree = widget.tree!;
    if (_stack.isNotEmpty) {
      return [
        for (final book in _baseUnder(_stack.last.facet)) _bookItem(book),
      ];
    }
    final out = <_MenuItem>[];
    for (final top in tree.visibleChildren(
      null,
      onlyBooks: _baseFacetSet,
    )) {
      final single = tree.singleBookOf(top, onlyBooks: _baseFacetSet);
      out.add(single != null ? _bookItem(single) : _folderItem(top));
    }
    return out;
  }

  List<_MenuItem> _rootItems() {
    final categoryPart = _categoryPart;
    // "נקה הכל" מוצג רק כשיש צמצום כלשהו (קטגוריה או ממד).
    final isEverything =
        (categoryPart.isEmpty || categoryPart.contains('/')) &&
        _dimensionPart.isEmpty;
    // התיבה משקפת את חלק הקטגוריות בלבד, בעקביות עם התיקיות שבמסך הפנימי:
    // סט ריק = לא מסומן (אף שחיפוש בלי שום סינון עדיין רץ על הכול).
    final hasAllCategories = categoryPart.contains('/');
    final hasPartialCategories = categoryPart.isNotEmpty && !hasAllCategories;
    final baseSelected = _selection.contains(FacetHelper.baseDimensionFacet);

    return [
      if (!isEverything)
        _MenuItem(
          label: 'נקה הכל',
          icon: FluentIcons.arrow_reset_24_regular,
          check: null,
          onTap: _clearAll,
        ),
      _MenuItem(
        label: 'כל הספרים',
        icon: FluentIcons.library_24_regular,
        check: hasAllCategories ? true : (hasPartialCategories ? null : false),
        onToggle: (v) => _setCategorySelection(v ? {'/'} : {}),
        onDrill: () => _enterView(_View.categories),
      ),
      _MenuItem(
        label: 'ספרי יסוד',
        icon: OtzariaIcons.book_star_24_regular,
        useRtlIcon: true,
        check: baseSelected,
        onToggle: (v) => _toggleDimension(FacetHelper.baseDimensionFacet, v),
        onDrill: () => _enterView(_View.base),
      ),
      const _MenuItem.header('תקופה'),
      for (final era in _eraNames)
        _MenuItem(
          label: era,
          icon: OtzariaIcons.calendar_24_regular,
          useRtlIcon: true,
          check: _selection.contains(FacetHelper.buildEraFacet(era)),
          onToggle: (v) => _toggleDimension(FacetHelper.buildEraFacet(era), v),
        ),
    ];
  }

  List<_MenuItem> _searchItems() {
    final tree = widget.tree!;
    final query = _normalizedQuery;
    final categoryPart = _categoryPart;
    final treeResults = tree.search(query);
    final eraMatches = [
      for (final era in _eraNames)
        if (normalizeFindText(era).contains(query)) era,
    ];
    return [
      // ברירת המחדל ("כל הספרייה") מסמנת את כל התוצאות — בלי שורה זו הדרך
      // היחידה לצמצם היא הורדת סימון שורה-שורה (issue #933).
      if (_selection.isNotEmpty)
        _MenuItem(
          label: 'נקה הכל',
          icon: FluentIcons.arrow_reset_24_regular,
          check: null,
          onTap: _clearAll,
        ),
      for (final author in _authorResults)
        _MenuItem(
          label: author,
          subtitle: 'מחבר',
          icon: OtzariaIcons.person_24_regular,
          check: _selection.contains(FacetHelper.buildAuthorFacet(author)),
          onToggle: (v) =>
              _toggleDimension(FacetHelper.buildAuthorFacet(author), v),
          onOnly: () => _selectOnly(FacetHelper.buildAuthorFacet(author)),
        ),
      for (final era in eraMatches)
        _MenuItem(
          label: era,
          subtitle: 'תקופה',
          icon: OtzariaIcons.calendar_24_regular,
          useRtlIcon: true,
          check: _selection.contains(FacetHelper.buildEraFacet(era)),
          onToggle: (v) => _toggleDimension(FacetHelper.buildEraFacet(era), v),
          onOnly: () => _selectOnly(FacetHelper.buildEraFacet(era)),
        ),
      for (final item in treeResults)
        _MenuItem(
          label: item.title,
          subtitle: item.subtitle,
          icon: item.isBook
              ? OtzariaIcons.book_24_regular
              : FluentIcons.folder_24_regular,
          useRtlIcon: item.isBook,
          check: tree.isFacetCovered(item.facet, categoryPart),
          onToggle: (v) => _toggleCategoryFacet(item.facet, v),
          onOnly: () => _selectOnly(item.facet),
        ),
    ];
  }

  // ── בנייה ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final items = _currentItems();
    final waitingForTree =
        (_hasActiveSearch || _view != _View.root) && widget.tree == null;
    final waitingForBaseBooks =
        !_hasActiveSearch &&
        _view == _View.base &&
        widget.baseBookNodes == null;
    final selectable = _selectableIndices(items);
    if (selectable.isNotEmpty && !selectable.contains(_highlight)) {
      _highlight = selectable.first;
    }

    final showBreadcrumb = !_hasActiveSearch && _view != _View.root;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showBreadcrumb) _buildBreadcrumb(context),
        Flexible(
          child: waitingForTree || waitingForBaseBooks
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
              ? _buildEmpty(context)
              : ListView.builder(
                  controller: _scrollController,
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: items.length,
                  itemBuilder: (context, index) =>
                      _buildRow(context, items[index], index),
                ),
        ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        _hasActiveSearch ? 'לא נמצאו תוצאות' : 'אין פריטים',
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _buildBreadcrumb(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final root = _view == _View.base ? 'ספרי יסוד' : 'כל הספרים';
    final trail = [root, for (final node in _stack) node.title];

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const RtlIcon(FluentIcons.arrow_right_24_regular, size: 20),
            tooltip: 'חזרה',
            visualDensity: VisualDensity.compact,
            onPressed: goBack,
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  for (var i = 0; i < trail.length; i++) ...[
                    if (i > 0)
                      Icon(
                        FluentIcons.chevron_left_16_regular,
                        size: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    TextButton(
                      onPressed: i == trail.length - 1
                          ? null
                          : () => _goToDepth(i),
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        trail[i],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: i == trail.length - 1
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(height: 1, color: colorScheme.outlineVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, _MenuItem item, int index) {
    if (item.isHeader) return _buildSectionHeader(context, item.label);
    final colorScheme = Theme.of(context).colorScheme;
    final highlighted = index == _highlight;
    final isFolder =
        item.icon == FluentIcons.folder_24_regular ||
        item.icon == FluentIcons.library_24_regular ||
        item.icon == OtzariaIcons.book_star_24_regular;
    final iconColor = isFolder
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    void onRowTap() {
      if (item.isDrill) {
        item.onDrill!();
      } else if (item.check == null && item.onTap != null) {
        item.onTap!();
      } else {
        item.onToggle?.call(!(item.check ?? false));
      }
    }

    // במגע אין hover — "רק" מוצג תמיד; בעכבר הוא נחשף בריחוף או בניווט מקלדת.
    final showOnly =
        item.onOnly != null &&
        (Platform.isAndroid ||
            Platform.isIOS ||
            Platform.isWindows ||
            index == _hoveredRow ||
            highlighted);

    return InkWell(
      canRequestFocus: false,
      onTap: onRowTap,
      onHover: (hovering) {
        if (hovering) {
          setState(() => _hoveredRow = index);
        } else if (_hoveredRow == index) {
          setState(() => _hoveredRow = -1);
        }
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: _rowHeight),
        color: highlighted ? colorScheme.primary.withValues(alpha: 0.10) : null,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          children: [
            // check==null עם onToggle = מצב ביניים (tristate); בלי onToggle
            // זו שורת פעולה (כמו "נקה הכל") שאין לה תיבה.
            if (item.onToggle != null)
              SizedBox(
                width: 28,
                height: 28,
                child: Checkbox(
                  value: item.check,
                  tristate: true,
                  onChanged: (_) {
                    item.onToggle?.call(!(item.check ?? false));
                    widget.onKeepFocus();
                  },
                ),
              )
            else
              const SizedBox(width: 28),
            const SizedBox(width: 2),
            if (item.icon != null) ...[
              item.useRtlIcon
                  ? RtlIcon(item.icon!, size: 18, color: iconColor)
                  : Icon(item.icon, size: 18, color: iconColor),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.subtitle.isNotEmpty)
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (showOnly) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: 'בחר רק את זה',
                child: TextButton(
                  onPressed: () {
                    item.onOnly!();
                    widget.onKeepFocus();
                  },
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'רק',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
            if (item.isDrill) ...[
              const SizedBox(width: 4),
              // בכיוון RTL מתהפך ומצביע שמאלה — כיוון הכניסה פנימה.
              RtlIcon(
                FluentIcons.chevron_left_24_regular,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
