import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
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
import 'package:otzaria/search/view/search_menu_style.dart';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/theme/app_input_tokens.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

/// סינון פעיל אחד בהיקף החיפוש, כפי שהוא מוצג כתגית.
typedef ScopeFilterEntry = ({
  String label,
  bool partial,
  VoidCallback onRemove,
});

/// הסינונים הפעילים לתגיות / למונה שבשדה. בחירת קטגוריות/ספרים ספציפיים
/// מיוצגת בפריט *אחד* ולא שם לכל פריט. בחירת "ספרי יסוד" ככלל אינה מגיעה
/// לכאן — היא facet ממדי (`/base`) ומתויגת בלופ שמתחת.
/// [baseBookFacets] — ה-facets של ספרי היסוד, כשהם ידועים. בחירה שכולה
/// מתוכם מיוחסת ל"ספרי יסוד" ולא ל"כל הספרים".
List<ScopeFilterEntry> activeScopeFilters({
  required Set<String> selected,
  required ValueChanged<Set<String>> onChanged,
  Set<String> baseBookFacets = const {},
}) {
  final result = <ScopeFilterEntry>[];
  final categories = FacetHelper.categoryFacetsOf(
    selected,
  ).where((f) => f != '/').toList();
  final dimensions = FacetHelper.dimensionFacetsOf(selected).toList();

  if (categories.isNotEmpty) {
    // כש-/base כבר מסומן יש לו תגית משלו, ואין לתייג "ספרי יסוד" פעמיים.
    final onlyBaseBooks =
        !dimensions.contains(FacetHelper.baseDimensionFacet) &&
        baseBookFacets.isNotEmpty &&
        categories.every(baseBookFacets.contains);
    result.add((
      label: onlyBaseBooks ? 'ספרי יסוד' : 'כל הספרים',
      partial: true,
      onRemove: () => onChanged(dimensions.toSet()),
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
        final next = Set<String>.from(selected)..remove(facet);
        onChanged(next);
      },
    ));
  }
  return result;
}

/// תגיות הסינון הפעילות של היקף החיפוש. נפרד מהשדה כדי שאפשר יהיה
/// למקם אותן בשורה משלהן ולא מתחת לשדה הצר.
class SearchScopeChips extends StatelessWidget {
  const SearchScopeChips({
    super.key,
    required this.selected,
    required this.onChanged,
    this.baseBookFacets = const {},
  });

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  /// ה-facets של ספרי היסוד — ראו [activeScopeFilters].
  final Set<String> baseBookFacets;

  @override
  Widget build(BuildContext context) {
    final filters = activeScopeFilters(
      selected: selected,
      onChanged: onChanged,
      baseBookFacets: baseBookFacets,
    );
    if (filters.isEmpty) return const SizedBox.shrink();
    return Wrap(
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
    );
  }
}

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

  /// גובה קבוע לשדה — להשוואה לגובה שדה החיפוש שלצדו. null = לפי התוכן.
  final double? height;

  /// האם להציג chips של הבחירה מתחת לשדה. בדיאלוג — כן; בסרגל התוצאות
  /// מועבר `false` (ה-chips היו מזיזים את העץ), ובמקומם מונה קומפקטי בשדה.
  final bool showChips;

  /// מדווח את ה-facets של ספרי היסוד ברגע שסווגו, כדי שמי שמציג את התגיות
  /// מחוץ לווידג'ט ([SearchScopeChips]) יוכל לייחס להם בחירה.
  final ValueChanged<Set<String>>? onBaseBookFacetsResolved;

  const SearchScopeMenuButton({
    super.key,
    required this.selected,
    required this.onChanged,
    this.width = 300,
    this.height,
    this.showChips = true,
    this.onBaseBookFacetsResolved,
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
  Set<String> _baseBookFacets = const {};
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
    setState(() {
      _baseBookNodesCache = result;
      _baseBookFacets = tree.facetsFullyWithin({
        for (final node in result) node.facet,
      });
    });
    widget.onBaseBookFacetsResolved?.call(_baseBookFacets);
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
        _baseBookFacets = const {};
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
          _baseBookFacets = const {};
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
    final filters = _activeFilters();
    // אותו גודל טקסט של שדה החיפוש שלצדו.
    final fontSize = AppInputTokens.fontSize(
      context.read<SettingsBloc?>()?.state.compactMenuMode ?? false,
    );

    return TapRegion(
      groupId: _tapGroup,
      child: Tooltip(
        message: 'צמצום החיפוש לקטגוריה, לספר או למחבר',
        waitDuration: const Duration(milliseconds: 500),
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: _handleFieldKey,
          child: SizedBox(
            height: widget.height,
            child: RtlTextField(
              controller: _searchController,
              focusNode: _fieldFocus,
              enabled: enabled,
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(fontSize: fontSize),
              decoration: AppInputTokens.filledDecoration(
                context,
                height: widget.height,
                // הרמז מתאר את המצב הנוכחי ולא את מה שמקלידים — זה מה
                // שהמשתמש צריך לדעת כשהוא מסתכל על השורה.
                hintText: filters.isEmpty ? 'כל הספרייה' : 'צמצום נוסף',
                hintStyle: TextStyle(
                  fontSize: fontSize,
                  color: colorScheme.onSurfaceVariant,
                ),
                prefixIcon: Icon(
                  FluentIcons.filter_24_regular,
                  size: 20,
                  color: filters.isEmpty
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.primary,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          FluentIcons.dismiss_24_regular,
                          size: 18,
                        ),
                        tooltip: 'ניקוי',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _searchController.clear(),
                      )
                    : Icon(
                        FluentIcons.chevron_down_16_regular,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveChips(BuildContext context) {
    if (_activeFilters().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SearchScopeChips(
        selected: widget.selected,
        onChanged: widget.onChanged,
        baseBookFacets: _baseBookFacets,
      ),
    );
  }

  List<ScopeFilterEntry> _activeFilters() => activeScopeFilters(
    selected: widget.selected,
    onChanged: widget.onChanged,
    baseBookFacets: _baseBookFacets,
  );

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
          elevation: SearchMenuSurface.elevation,
          color: SearchMenuSurface.background(colorScheme),
          clipBehavior: Clip.antiAlias,
          shape: SearchMenuSurface.shape(colorScheme),
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

  /// מצב התיבה: true/false, ו-null = סימון חלקי. "אין תיבה בכלל" מיוצג
  /// ב-[showCheck] ולא ב-null, אחרת פריט חלקי היה מאבד את התיבה.
  final bool? check;
  final bool showCheck;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onTap;
  final VoidCallback? onDrill;
  final bool isHeader;

  bool get isDrill => onDrill != null;

  const _MenuItem({
    required this.label,
    this.subtitle = '',
    required this.icon,
    this.useRtlIcon = false,
    required this.check,
    this.onToggle,
    this.onDrill,
  }) : showCheck = true,
       onTap = null,
       isHeader = false;

  /// שורת פעולה בלי תיבת סימון (למשל "נקה הכל").
  const _MenuItem.action({
    required this.label,
    required this.icon,
    required this.onTap,
  }) : subtitle = '',
       useRtlIcon = false,
       check = null,
       showCheck = false,
       onToggle = null,
       onDrill = null,
       isHeader = false;

  const _MenuItem.header(this.label)
    : subtitle = '',
      icon = null,
      useRtlIcon = false,
      check = null,
      showCheck = false,
      onToggle = null,
      onTap = null,
      onDrill = null,
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
  static const double _rowHeight = SearchMenuRow.height;

  final ScrollController _scrollController = ScrollController();

  late Set<String> _selection;
  _View _view = _View.root;
  final List<ScopeNode> _stack = [];
  int _highlight = 0;

  List<String> _authorResults = const [];
  int _authorRequestId = 0;
  Set<String> _baseFacetSet = const {};

  /// [_baseFacetSet] בתוספת תיקיות שכל ספריהן ספרי יסוד — הבחירה מתקפלת
  /// לעתים ל-facet של תיקיה, ובלי זה היא לא הייתה מיוחסת לספרי היסוד.
  Set<String> _baseCoveredFacets = const {};

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
    if (!identical(oldWidget.baseBookNodes, widget.baseBookNodes) ||
        !identical(oldWidget.tree, widget.tree)) {
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
    _baseCoveredFacets =
        widget.tree?.facetsFullyWithin(_baseFacetSet) ?? _baseFacetSet;
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

  /// כל ספרי היסוד תחת [folderFacet], בסדר הספרייה.
  List<BookScopeNode> _baseUnder(String folderFacet) => [
    for (final n in widget.baseBookNodes ?? const <BookScopeNode>[])
      if (n.facet.startsWith('$folderFacet/')) n,
  ];

  /// סימון/ביטול של קבוצת ספרים כיחידה אחת.
  void _toggleBooks(List<BookScopeNode> books, bool select) {
    final tree = widget.tree;
    if (tree == null || books.isEmpty) return;
    var next = _categoryPart;
    for (final book in books) {
      next = select
          ? tree.selectFacet(book.facet, next)
          : tree.deselectFacet(book.facet, next);
    }
    _setCategorySelection(next);
  }

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
    } else if (item.onTap != null) {
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
      icon: FluentIcons.book_24_regular,
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

  /// שורת תיקיה בתצוגת "ספרי יסוד". הסימון נוגע רק בספרי היסוד שתחתיה —
  /// סימון התיקיה כולה היה מרחיב את החיפוש גם לספרים שאינם ספרי יסוד.
  _MenuItem _baseFolderItem(ScopeNode node) {
    final tree = widget.tree!;
    final books = _baseUnder(node.facet);
    final covered = books
        .where((book) => tree.isFacetCovered(book.facet, _categoryPart))
        .length;
    return _MenuItem(
      label: node.title,
      icon: FluentIcons.folder_24_regular,
      check: covered == 0
          ? false
          : covered == books.length
          ? true
          : null,
      onToggle: (v) => _toggleBooks(books, v),
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
      out.add(single != null ? _bookItem(single) : _baseFolderItem(top));
    }
    return out;
  }

  List<_MenuItem> _rootItems() {
    final categoryPart = _categoryPart;
    // "כל הספרים" מסומן רק כשאין שום צמצום (לא קטגוריה ולא ממד).
    final isEverything =
        (categoryPart.isEmpty || categoryPart.contains('/')) &&
        _dimensionPart.isEmpty;
    final baseSelected = _selection.contains(FacetHelper.baseDimensionFacet);
    // בחירה של ספרים בודדים נשמרת כ-facets קטגוריאליים, בלי זכר לתצוגה שממנה
    // נבחרו. כשכולם ספרי יסוד — הסימון החלקי שייך ל"ספרי יסוד", לא ל"כל הספרים".
    final selectedBooks = categoryPart.where((f) => f != '/');
    final onlyBaseBooks =
        !baseSelected &&
        selectedBooks.isNotEmpty &&
        _baseCoveredFacets.isNotEmpty &&
        selectedBooks.every(_baseCoveredFacets.contains);

    return [
      if (!isEverything)
        _MenuItem.action(
          label: 'נקה הכל',
          icon: FluentIcons.arrow_reset_24_regular,
          onTap: _clearAll,
        ),
      _MenuItem(
        label: 'כל הספרים',
        icon: FluentIcons.library_24_regular,
        check: isEverything
            ? true
            : (selectedBooks.isNotEmpty && !onlyBaseBooks ? null : false),
        onToggle: (_) => isEverything ? _clearAll() : _apply({'/'}),
        onDrill: () => _enterView(_View.categories),
      ),
      _MenuItem(
        label: 'ספרי יסוד',
        icon: FluentIcons.book_star_24_regular,
        useRtlIcon: true,
        check: baseSelected ? true : (onlyBaseBooks ? null : false),
        onToggle: (v) => _toggleDimension(FacetHelper.baseDimensionFacet, v),
        onDrill: () => _enterView(_View.base),
      ),
      const _MenuItem.header('תקופה'),
      for (final era in _eraNames)
        _MenuItem(
          label: era,
          icon: FluentIcons.calendar_24_regular,
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
      for (final author in _authorResults)
        _MenuItem(
          label: author,
          subtitle: 'מחבר',
          icon: FluentIcons.person_24_regular,
          check: _selection.contains(FacetHelper.buildAuthorFacet(author)),
          onToggle: (v) =>
              _toggleDimension(FacetHelper.buildAuthorFacet(author), v),
        ),
      for (final era in eraMatches)
        _MenuItem(
          label: era,
          subtitle: 'תקופה',
          icon: FluentIcons.calendar_24_regular,
          useRtlIcon: true,
          check: _selection.contains(FacetHelper.buildEraFacet(era)),
          onToggle: (v) => _toggleDimension(FacetHelper.buildEraFacet(era), v),
        ),
      for (final item in treeResults)
        _MenuItem(
          label: item.title,
          subtitle: item.subtitle,
          icon: item.isBook
              ? FluentIcons.book_24_regular
              : FluentIcons.folder_24_regular,
          useRtlIcon: item.isBook,
          check: tree.isFacetCovered(item.facet, categoryPart),
          onToggle: (v) => _toggleCategoryFacet(item.facet, v),
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
                  padding: SearchMenuSurface.listPadding,
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
        item.icon == FluentIcons.book_star_24_regular;
    final iconColor = isFolder
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    void onRowTap() {
      if (item.isDrill) {
        item.onDrill!();
      } else if (item.onTap != null) {
        item.onTap!();
      } else {
        item.onToggle?.call(!(item.check ?? false));
      }
    }

    return InkWell(
      canRequestFocus: false,
      onTap: onRowTap,
      child: SearchMenuRow(
        label: item.label,
        subtitle: item.subtitle,
        icon: item.icon,
        useRtlIcon: item.useRtlIcon,
        iconColor: iconColor,
        highlighted: highlighted,
        leading: item.showCheck
            ? Checkbox(
                value: item.check,
                tristate: true,
                onChanged: (_) {
                  item.onToggle?.call(!(item.check ?? false));
                  widget.onKeepFocus();
                },
              )
            : null,
        trailing: item.isDrill
            // בכיוון RTL מתהפך ומצביע שמאלה — כיוון הכניסה פנימה.
            ? RtlIcon(
                FluentIcons.chevron_left_24_regular,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              )
            : null,
      ),
    );
  }
}
