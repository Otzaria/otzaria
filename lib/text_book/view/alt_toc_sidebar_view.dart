import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/text_book_messages.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:flutter/scheduler.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/migration/models/alt_toc_entry.dart';
import 'package:otzaria/migration/models/alt_toc_structure.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/search/utils/find_match_utils.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/utils/dibburim_structure.dart';
import 'package:otzaria/text_book/utils/inline_section_markers.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/text_book/utils/section_search_utils.dart'
    show bracketMarkerFractionInLine;
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:positioned_sliver_list/positioned_list.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';

/// "הלכות וסימנים" (`SimanNames`) ראשון — המבנה הראשון המתאים למיקום הוא
/// שנפתח מעצמו; שאר המבנים בסדר המסד.
List<AltTocStructure> sidebarStructureOrder(List<AltTocStructure> structures) =>
    [
      ...structures.where((s) => s.key == 'SimanNames'),
      ...structures.where((s) => s.key != 'SimanNames'),
    ];

final Expando<String> _matchTextCache = Expando<String>();

/// הטקסט המנורמל של [entry] לאיתור. אינו תלוי בשאילתה, ולכן נשמר בין הקשות.
@visibleForTesting
String altTocEntryMatchText(AltTocEntry entry) =>
    _matchTextCache[entry] ??= normalizeFindText(entry.text ?? '');

class AltTocSidebarView extends StatefulWidget {
  final TextBook book;
  final void Function() closeLeftPaneCallback;
  final LineScrollController lines;

  /// פוקוס-נוד לשדה החיפוש של הכותרות, מנוהל ע"י המסך האב כדי לאפשר
  /// פוקוס אוטומטי בפתיחת הפאנל ובמעבר ללשונית 'כותרות'.
  final FocusNode? focusNode;

  /// דיבורי-המתחיל של הספר (`lineIndex` → טקסט). כשאינם ריקים נוסף מבנה
  /// מסונתז "דיבורי המתחיל" שבו הם עלים תחת כותרות [tableOfContents].
  final Map<int, String> dibburim;
  final List<TocEntry> tableOfContents;

  const AltTocSidebarView({
    super.key,
    required this.book,
    required this.closeLeftPaneCallback,
    required this.lines,
    this.focusNode,
    this.dibburim = const {},
    this.tableOfContents = const [],
  });

  @override
  State<AltTocSidebarView> createState() => _AltTocSidebarViewState();
}

class _AltTocSidebarViewState extends State<AltTocSidebarView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final ScrollController _sidebarScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final Map<int, GlobalKey> _itemKeys = {};
  bool _isManuallyScrolling = false;

  // דפדוף בחיצים בין תוצאות החיפוש בלי לעזוב את שדה הטקסט (כמו ב"איתור").
  // הערך הוא מיקום ברשימת התוצאות; מתאפס בכל שינוי שאילתה.
  int? _highlightedMatchPos;
  final ItemScrollController _searchScrollController = ItemScrollController();
  final ItemPositionsListener _searchPositionsListener =
      ItemPositionsListener.create();

  // Available structures (e.g., Parasha, Daf)
  List<AltTocStructure> _structures = [];

  // Structure Data Caches
  // StructureID -> Root Entries
  final Map<int, List<AltTocEntry>> _structureRoots = {};
  // StructureID -> (ParentID -> Children)
  final Map<int, Map<int, List<AltTocEntry>>> _structureChildren = {};
  // StructureID -> (ChildID -> ParentID)
  final Map<int, Map<int, int>> _structureParents = {};
  // StructureID -> entries in document order, cached for search and active entry.
  final Map<int, List<AltTocEntry>> _flattenedEntries = {};

  // Expanded state
  // StructureID -> bool
  final Map<int, bool> _structureExpanded = {};
  // EntryID -> bool
  final Map<int, bool> _entryExpanded = {};

  // Active entry and scroll state are scoped to a structure: a line may belong
  // to several alternative structures at once.
  final Map<int, int> _activeEntryIds = {};
  final Map<int, int> _selectedEntryLineIndices = {};
  int _navigationRequest = 0;
  final Map<int, int> _lastScrolledEntryIds = {};

  // מעבר כותרת בגלילה מחליף רק את הסימון; מאזין לכל ערך בונה מחדש שתי שורות ולא את כל העץ.
  final Map<int, ValueNotifier<int>> _selectionTicks = {};

  // מעקב פתיחת הפאנל: גלילה מחדש למיקום הפעיל רק במעבר סגור→פתוח.
  bool _wasLeftPaneShown = false;

  // Debounce timer to prevent rapid updates during scrolling
  Timer? _debounceTimer;

  // Caches the in-flight Future per structureId so every awaiter shares the same load
  final Map<int, Future<void>> _loadingFutures = {};

  bool _isLoading = true;
  late bool _hasDibburimEntries;

  @override
  void initState() {
    super.initState();
    _hasDibburimEntries = hasDibburimEntries(
      widget.tableOfContents,
      widget.dibburim,
    );
    _loadStructures();
  }

  @override
  void didUpdateWidget(covariant AltTocSidebarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.dibburim, widget.dibburim) &&
        identical(oldWidget.tableOfContents, widget.tableOfContents)) {
      return;
    }
    _structureRoots.remove(kDibburimStructureId);
    _structureChildren.remove(kDibburimStructureId);
    _structureParents.remove(kDibburimStructureId);
    _flattenedEntries.remove(kDibburimStructureId);
    _structureExpanded.remove(kDibburimStructureId);
    _activeEntryIds.remove(kDibburimStructureId);
    _lastScrolledEntryIds.remove(kDibburimStructureId);
    _structures.removeWhere((s) => s.id == kDibburimStructureId);
    _hasDibburimEntries = hasDibburimEntries(
      widget.tableOfContents,
      widget.dibburim,
    );
    if (_hasDibburimEntries) {
      _structures.add(dibburimStructure);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    for (final ticks in _selectionTicks.values) {
      ticks.dispose();
    }
    _sidebarScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onSearchChanged(String query) async {
    // Update UI immediately so the clear button and search mode appear without delay
    setState(() => _highlightedMatchPos = null);

    if (query.isNotEmpty) {
      // Load all structures so search works across all of them
      for (final structure in _structures) {
        await _loadEntriesForStructure(structure.id);
      }
    }

    // Refresh results after loads complete, guarded against disposal
    if (mounted) setState(() {});
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _highlightedMatchPos = null);
  }

  /// מזיז את סימון הדפדוף בין תוצאות החיפוש; הפוקוס נשאר בשדה.
  void _moveHighlightedMatch(int delta) {
    final matches = _getMatchingEntries(_searchController.text);
    if (matches.isEmpty) return;
    final current = _highlightedMatchPos ?? (delta >= 0 ? -1 : matches.length);
    final next = (current + delta).clamp(0, matches.length - 1);
    if (next == current) return;
    setState(() => _highlightedMatchPos = next);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollSearchResultIntoView(next);
    });
  }

  /// גולל את רשימת התוצאות אל התוצאה המסומנת, רק אם אינה גלויה במלואה.
  void _scrollSearchResultIntoView(int matchPos) {
    if (!_searchScrollController.isAttached) return;
    // +1: פריט 0 ברשימה הוא הכותרת הראשית.
    final index = matchPos + 1;
    final positions = _searchPositionsListener.itemPositions.value;
    for (final p in positions) {
      if (p.index == index &&
          p.itemLeadingEdge >= 0 &&
          p.itemTrailingEdge <= 1) {
        return;
      }
    }
    _searchScrollController.scrollTo(
      index: index,
      alignment: 0.3,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  /// אנטר בשדה החיפוש: פתיחת התוצאה המסומנת, ובהיעדר סימון — הראשונה.
  void _openHighlightedMatch() {
    final matches = _getMatchingEntries(_searchController.text);
    if (matches.isEmpty) return;
    final pos = (_highlightedMatchPos ?? 0).clamp(0, matches.length - 1);
    final (:structureId, :entry) = matches[pos];
    _handleEntryTap(structureId, entry);
  }

  List<AltTocEntry> _flattenEntries(int structureId) {
    final cached = _flattenedEntries[structureId];
    if (cached != null) return cached;
    final result = <AltTocEntry>[];
    void visit(AltTocEntry entry) {
      result.add(entry);
      final children = _structureChildren[structureId]?[entry.id] ?? [];
      for (final child in children) {
        visit(child);
      }
    }

    for (final root in _structureRoots[structureId] ?? []) {
      visit(root);
    }
    return _flattenedEntries[structureId] = result;
  }

  /// התוצאות האחרונות, לפי השאילתה וזהות הרשימות של [_flattenEntries] (טעינה
  /// מחליפה רשימה): כל חץ בונה מחדש, וסריקת אלפי דיבורים עולה אלפיות שנייה.
  ({
    String query,
    List<List<AltTocEntry>> sources,
    List<({int structureId, AltTocEntry entry})> matches,
  })?
  _lastMatches;

  List<({int structureId, AltTocEntry entry})> _getMatchingEntries(
    String rawQuery,
  ) {
    final sources = [for (final s in _structures) _flattenEntries(s.id)];
    final last = _lastMatches;
    if (last != null &&
        last.query == rawQuery &&
        listEquals(last.sources, sources)) {
      return last.matches;
    }

    final normalizedQuery = normalizeFindQuery(rawQuery);
    if (normalizedQuery.isEmpty) return [];

    final results = <({int structureId, AltTocEntry entry})>[];
    for (final structure in _structures) {
      for (final entry in _flattenEntries(structure.id)) {
        if (altTocEntryMatchText(entry).contains(normalizedQuery)) {
          results.add((structureId: structure.id, entry: entry));
        }
      }
    }
    _lastMatches = (query: rawQuery, sources: sources, matches: results);
    return results;
  }

  Future<void> _loadStructures() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final structures = await DatabaseLibraryProvider.instance
          .getAlternativeStructuresForBook(widget.book);
      if (mounted) {
        setState(() {
          _structures = [
            ...sidebarStructureOrder(structures),
            if (_hasDibburimEntries) dibburimStructure,
          ];
          _isLoading = false;
        });

        if (_structures.length == 1) {
          final structure = _structures.single;
          if (structure.id == kDibburimStructureId) {
            await _loadEntriesForStructure(structure.id);
            if (!mounted) return;
          }
          // השמטת שם הספר יכולה להשאיר דיבורים ישירות בשורש.
          if (structure.id != kDibburimStructureId ||
              _structureRoots[structure.id]?.every(
                    (entry) => entry.hasChildren,
                  ) ==
                  true) {
            _toggleStructure(structure);
          }
        }

        // הפאנל בונה את התצוגה רק כשהוא נפתח, וה-BlocListener לא יירה על
        // ה-state ההתחלתי. גלילה ראשונית למיקום הפעיל אחרי טעינת המבנים.
        final state = context.read<TextBookBloc>().state;
        if (state is TextBookLoaded && state.showLeftPane) {
          _wasLeftPaneShown = true;
        }
        _updateActiveItemFromBloc();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        debugPrint('Error loading structures: $e');
      }
    }
  }

  Future<void> _loadEntriesForStructure(int structureId) {
    // Already loaded — return immediately
    if (_structureRoots.containsKey(structureId)) return Future.value();

    // Load in-flight — return the same Future so every awaiter waits for it
    if (_loadingFutures.containsKey(structureId)) {
      return _loadingFutures[structureId]!;
    }

    final future = _doLoadEntries(structureId);
    _loadingFutures[structureId] = future;
    return future;
  }

  Future<void> _doLoadEntries(int structureId) async {
    try {
      final entries = structureId == kDibburimStructureId
          ? buildDibburimEntries(widget.tableOfContents, widget.dibburim)
          : await DatabaseLibraryProvider.instance.getAllAlternativeEntries(
              structureId,
              source: widget.book.source,
            );

      if (mounted) {
        setState(() {
          _processEntries(structureId, entries);
        });

        // Check active item for this newly loaded structure
        _updateActiveItemFromBloc();
      }
    } catch (e) {
      debugPrint('Error loading entries for structure $structureId: $e');
    } finally {
      _loadingFutures.remove(structureId);
    }
  }

  void _processEntries(int structureId, List<AltTocEntry> entries) {
    _structureRoots[structureId] = [];
    _structureChildren[structureId] = {};
    _structureParents[structureId] = {};
    _flattenedEntries.remove(structureId);

    for (var entry in entries) {
      if (entry.parentId == null) {
        _structureRoots[structureId]!.add(entry);
      } else {
        _structureChildren[structureId]!
            .putIfAbsent(entry.parentId!, () => [])
            .add(entry);
        _structureParents[structureId]![entry.id] = entry.parentId!;
      }
    }
  }

  void _toggleStructure(AltTocStructure structure) {
    setState(() {
      final isExpanded = _structureExpanded[structure.id] ?? false;
      _structureExpanded[structure.id] = !isExpanded;

      if (!isExpanded) {
        // Opening
        _loadEntriesForStructure(structure.id);
      }
    });
    _updateActiveItemFromBloc();
  }

  void _updateActiveItemFromBloc() {
    if (_isManuallyScrolling) return;

    final state = context.read<TextBookBloc>().state;
    // כשהפאנל סגור הגלילה נכשלת אך משבשת את _lastScrolledEntryIds
    // וחוסמת את הגלילה האמיתית בפתיחה הבאה.
    if (state is TextBookLoaded && !state.showLeftPane) return;
    if (state is TextBookLoaded && !_isLoading) {
      final index =
          state.selectedIndex ??
          (state.visibleIndices.isNotEmpty ? state.visibleIndices.first : null);
      if (index != null) {
        _findAndHighlightEntry(index);
      }
    }
  }

  /// מבנים שכותרותיהם מוזרקות לגוף הטקסט ([buildSectionHeadings]).
  bool _hasInjectedHeadings(int structureId) => _structures.any(
    (s) => s.id == structureId && (s.key == 'Topic' || s.key == 'Parasha'),
  );

  Future<int?> _entryIdForLine(int lineIndex, int structureId) async {
    if (structureId != kDibburimStructureId) {
      // כותרת סימן מעל פתיחת נושא משויכת במסד לנושא הקודם, אך מוצגת תחת
      // הנושא החדש — הרשומה נקבעת לפי שורת התוכן שהיא פותחת.
      final state = context.read<TextBookBloc>().state;
      if (_hasInjectedHeadings(structureId) && state is TextBookLoaded) {
        final content = state.content;
        while (lineIndex + 1 < content.length &&
            sectionHeadingLinesAbove([content[lineIndex]]) == 1) {
          lineIndex++;
        }
      }
      return DatabaseLibraryProvider.instance.getAltTocEntryForLine(
        widget.book.title,
        lineIndex,
        structureId,
        source: widget.book.source,
      );
    }
    if (_structureExpanded[structureId] != true) return null;
    await _loadEntriesForStructure(structureId);
    return activeDibburimEntryId(_flattenEntries(structureId), lineIndex);
  }

  /// האב הגלוי הגבוה ביותר של [entryId]: הערך עצמו כשכל אבותיו פתוחים.
  int _visibleAncestor(int structureId, int entryId) {
    final parents = _structureParents[structureId] ?? const {};
    var visible = entryId;
    var current = entryId;
    while (parents.containsKey(current)) {
      final parent = parents[current]!;
      if (_entryExpanded[parent] != true) visible = parent;
      current = parent;
    }
    return visible;
  }

  Future<void> _findAndHighlightEntry(int lineIndex) async {
    final matches = <({int structureId, int entryId})>[];
    for (final structure in _structures) {
      var resolvedId = await _entryIdForLine(lineIndex, structure.id);

      // הדיבורים אינם נפתחים מעצמם: מבנה מכווץ מדולג, ובמבנה פתוח מסומן
      // האב הגלוי בלבד עד שהמשתמש פותח את החץ.
      if (resolvedId != null && structure.id == kDibburimStructureId) {
        resolvedId = _visibleAncestor(structure.id, resolvedId);
      }

      if (resolvedId != null) {
        matches.add((structureId: structure.id, entryId: resolvedId));
      }
    }
    if (!mounted || matches.isEmpty) return;

    final changed = matches
        .where((match) => _activeEntryIds[match.structureId] != match.entryId)
        .where(
          (match) => !_sharesLineWithActive(
            match.structureId,
            match.entryId,
            lineIndex,
          ),
        )
        .toList();
    if (changed.isEmpty) return;

    // שומרים את התנהגות המבנים הקיימים: רק המבנה הראשון המתאים נפתח
    // אוטומטית. דיבורי-המתחיל נשארים מכווצים עד בחירת המשתמש.
    final databaseMatch = matches.firstWhere(
      (match) => match.structureId != kDibburimStructureId,
      orElse: () => (structureId: kDibburimStructureId, entryId: 0),
    );
    final needsRebuild =
        _searchController.text.isNotEmpty ||
        (databaseMatch.structureId != kDibburimStructureId &&
            !_isRevealed(databaseMatch.structureId, databaseMatch.entryId));
    for (final match in changed) {
      _selectionTicks[_activeEntryIds[match.structureId]]?.value++;
      _selectionTicks[match.entryId]?.value++;
    }
    final update = needsRebuild ? setState : (VoidCallback fn) => fn();
    update(() {
      for (final match in changed) {
        _activeEntryIds[match.structureId] = match.entryId;
      }

      if (databaseMatch.structureId != kDibburimStructureId) {
        if (!_structureRoots.containsKey(databaseMatch.structureId)) {
          _structureExpanded[databaseMatch.structureId] = true;
          _loadEntriesForStructure(databaseMatch.structureId).then((_) {
            if (mounted) {
              _expandParents(databaseMatch.structureId, databaseMatch.entryId);
            }
          });
        } else {
          _structureExpanded[databaseMatch.structureId] = true;
          _expandParents(databaseMatch.structureId, databaseMatch.entryId);
        }
      }
    });

    for (final match in changed) {
      if (_lastScrolledEntryIds[match.structureId] != match.entryId) {
        _scrollToActiveItem(match.structureId, match.entryId);
      }
    }
  }

  /// אחים שנפתחים באותה שורה (דפים בפסקה אחת) ממופים במסד לאחרון שבהם,
  /// ולכן האח שנבחר בלחיצה נשאר מסומן כל עוד השורה לא התחלפה.
  bool _sharesLineWithActive(int structureId, int entryId, int lineIndex) {
    if (_selectedEntryLineIndices[structureId] != lineIndex) return false;
    final activeId = _activeEntryIds[structureId];
    if (activeId == null || structureId == kDibburimStructureId) return false;
    AltTocEntry? find(int id) =>
        _flattenEntries(structureId).where((e) => e.id == id).firstOrNull;
    final active = find(activeId);
    final resolved = find(entryId);
    return active != null &&
        resolved != null &&
        active.lineId != null &&
        active.lineId == resolved.lineId &&
        active.parentId == resolved.parentId;
  }

  void _selectEntry(int structureId, int entryId, int lineIndex) {
    _selectedEntryLineIndices[structureId] = lineIndex;
    final previous = _activeEntryIds[structureId];
    if (previous == entryId) return;
    _selectionTicks[previous]?.value++;
    _selectionTicks[entryId]?.value++;
    _activeEntryIds[structureId] = entryId;
  }

  void _scrollToActiveItem(int structureId, int entryId) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isManuallyScrolling) return;

      // Safety check: ensure scroll controller is attached
      if (!_sidebarScrollController.hasClients) return;

      try {
        final key = _itemKeys[entryId];
        final itemContext = key?.currentContext;
        if (itemContext == null) return;

        final itemRenderObject = itemContext.findRenderObject();
        if (itemRenderObject is! RenderBox) return;

        final scrollableBox =
            _sidebarScrollController.position.context.storageContext
                    .findRenderObject()
                as RenderBox;

        final itemOffset = itemRenderObject
            .localToGlobal(Offset.zero, ancestor: scrollableBox)
            .dy;
        final viewportHeight = scrollableBox.size.height;
        final itemHeight = itemRenderObject.size.height;

        final target =
            _sidebarScrollController.offset +
            itemOffset -
            (viewportHeight / 2) +
            (itemHeight / 2);

        _sidebarScrollController.animateTo(
          target.clamp(0.0, _sidebarScrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );

        _lastScrolledEntryIds[structureId] = entryId;
      } catch (e) {
        debugPrint('Error scrolling to active item: $e');
      }
    });
  }

  /// הערך כבר גלוי בעץ, ולכן ההרחבה שב-[_findAndHighlightEntry] לא תשנה דבר.
  bool _isRevealed(int structureId, int entryId) {
    if (_structureExpanded[structureId] != true ||
        !_structureRoots.containsKey(structureId)) {
      return false;
    }
    final parents = _structureParents[structureId] ?? const {};
    for (var id = parents[entryId]; id != null; id = parents[id]) {
      if (_entryExpanded[id] != true) return false;
    }
    return true;
  }

  void _expandParents(int structureId, int entryId) {
    if (!_structureParents.containsKey(structureId)) return;

    var currentId = entryId;
    final parents = _structureParents[structureId]!;

    while (parents.containsKey(currentId)) {
      final parentId = parents[currentId]!;
      if (_entryExpanded[parentId] != true) {
        _entryExpanded[parentId] = true;
      }
      currentId = parentId;
    }
  }

  void _toggleEntryExpanded(int entryId) {
    setState(() {
      _entryExpanded[entryId] = !(_entryExpanded[entryId] ?? false);
    });
    // בדיבורים הסימון עוקב אחרי הרמה הגלויה, ולכן מחושב מחדש אחרי פתיחה/כיווץ.
    _updateActiveItemFromBloc();
  }

  /// גלילת הספר הפתוח לשורה [lineIndex], ולסמן `[markerTitle…]` כשהוא בתוכה.
  Future<void> _scrollToLine(int lineIndex, {String? markerTitle}) async {
    final request = ++_navigationRequest;
    final bloc = context.read<TextBookBloc>();
    final state = bloc.state;
    if (state is! TextBookLoaded) {
      return;
    }
    var line = lineIndex >= 0 && lineIndex < state.content.length
        ? state.content[lineIndex]
        : null;
    if (markerTitle != null && !state.isContentLineLoaded(lineIndex)) {
      final epoch = widget.lines.navigationEpoch.value;
      final range = await bloc.repository.getBookContentRange(
        state.book,
        startLine: lineIndex,
        endLine: lineIndex,
      );
      if (!mounted ||
          request != _navigationRequest ||
          epoch != widget.lines.navigationEpoch.value) {
        return;
      }
      line = range?.lines.firstOrNull;
    }
    final navigation = widget.lines.scrollToLine(
      lineIndex,
      intraLineFraction: line == null || markerTitle == null
          ? 0
          : bracketMarkerFractionInLine(line, markerTitle),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );

    if (Platform.isAndroid) {
      unawaited(
        closePaneAfterNavigation(
          navigation: navigation,
          closePane: () {
            if (mounted) widget.closeLeftPaneCallback();
          },
        ),
      );
    } else {
      unawaited(navigation);
    }
  }

  Future<void> _openLink(Link link, {String? markerTitle}) async {
    if (link.path2 == widget.book.title) {
      // Ensure index is at least 0 to prevent RangeError
      await _scrollToLine(
        (link.index2 - 1).clamp(0, double.maxFinite).toInt(),
        markerTitle: markerTitle,
      );
    } else {
      context.read<TabsBloc>().add(
        OpenOrFocusTab(
          TextBookTab(
            book: TextBook(
              title: link.path2,
              categoryId: link.targetCategoryId,
              fileType: link.targetFileType,
              filePath: link.path2,
            ),
            index: link.index2,
          ),
          insertAdjacent: true,
        ),
      );
      context.read<NavigationBloc>().add(
        const NavigateToScreen(Screen.reading),
      );
    }
  }

  void _handleEntryTap(
    int structureId,
    AltTocEntry entry, {
    bool toggleIfLinkless = false,
  }) {
    _isManuallyScrolling = false;
    _lastScrolledEntryIds.remove(structureId);
    _handleLeafClick(structureId, entry, toggleIfLinkless: toggleIfLinkless);
  }

  void _handleLeafClick(
    int structureId,
    AltTocEntry entry, {
    bool toggleIfLinkless = false,
  }) async {
    if (structureId == kDibburimStructureId) {
      await _scrollToLine(dibburimLineIndex(entry.id));
      return;
    }
    try {
      // 1. Try to get links for this entry
      var links = await DatabaseLibraryProvider.instance.getLinksForAltTocEntry(
        structureId,
        entry.id,
        source: widget.book.source,
      );

      // צומת בלי קישור משלו: הלחיצה פותחת/סוגרת, ורק בפתיחה מנווטת לבן הראשון.
      if (links.isEmpty &&
          toggleIfLinkless &&
          (_structureChildren[structureId]?[entry.id]?.isNotEmpty ?? false)) {
        if (!mounted) return;
        final wasExpanded = _entryExpanded[entry.id] ?? false;
        _toggleEntryExpanded(entry.id);
        if (wasExpanded) return;
      }

      // 2. If no links, but has children, try to get link from first child (recursively)
      var linkEntry = entry;
      if (links.isEmpty) {
        AltTocEntry? current = entry;
        while (current != null && links.isEmpty) {
          final children = _structureChildren[structureId]?[current.id];
          if (children != null && children.isNotEmpty) {
            current = children.first;
            linkEntry = current;
            links = await DatabaseLibraryProvider.instance
                .getLinksForAltTocEntry(
                  structureId,
                  current.id,
                  source: widget.book.source,
                );
          } else {
            current = null;
          }
        }
      }

      if (!mounted) return;

      if (links.isNotEmpty) {
        final link = links.first;
        final state = context.read<TextBookBloc>().state;
        if (_hasInjectedHeadings(structureId) &&
            link.path2 == widget.book.title &&
            state is TextBookLoaded) {
          // כותרת הנושא מוצגת מעל כותרות הסימן שלפני שורת היעד — אליה מנווטים.
          final line = link.index2 - 1;
          final content = state.content;
          String? at(int i) => i >= 0 && i < content.length ? content[i] : null;
          await _scrollToLine(
            line - sectionHeadingLinesAbove([at(line - 1), at(line - 2)]),
          );
        } else {
          if (link.path2 == widget.book.title) {
            _selectEntry(structureId, linkEntry.id, link.index2 - 1);
          }
          await _openLink(link, markerTitle: linkEntry.text);
        }
      } else {
        UiSnack.show(TextBookMessages.headingLinkNotFound);
      }
    } catch (e) {
      debugPrint('Error handling leaf click: $e');
    }
  }

  Future<void> _handleStructureTap(AltTocStructure structure) async {
    // למבנה אין קישור משלו: לחיצה עליו פותחת/סוגרת, ורק בפתיחה מנווטת.
    final wasExpanded = _structureExpanded[structure.id] ?? false;
    _toggleStructure(structure);
    if (wasExpanded) return;

    // Ensure entries are loaded
    if (!_structureRoots.containsKey(structure.id)) {
      await _loadEntriesForStructure(structure.id);
      if (!mounted) return;
    }

    final roots = _structureRoots[structure.id];
    if (roots != null && roots.isNotEmpty) {
      // Navigate to the first root entry
      _handleLeafClick(structure.id, roots.first);
    } else {
      UiSnack.show(TextBookMessages.structureHeadingsNotFound);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_structures.isEmpty) {
      return const OtzariaEmptyState(
        isCompact: true,
        icon: OtzariaIcons.text_bullet_list_tree_24_regular,
        title: 'אין כותרות חלופיות זמינות',
      );
    }

    final isSearching = _searchController.text.isNotEmpty;

    final delegate = NavPanelSearchDelegate(
      controller: _searchController,
      hintText: 'איתור כותרת...',
      focusNode: widget.focusNode,
      onChanged: _onSearchChanged,
      onSubmitted: (_) => _openHighlightedMatch(),
      onClear: _clearSearch,
      onArrowDown: isSearching ? () => _moveHighlightedMatch(1) : null,
      onArrowUp: isSearching ? () => _moveHighlightedMatch(-1) : null,
    );

    return NavPanelCollapsibleSearch(
      delegate: delegate,
      child: isSearching
          ? _buildSearchResults()
          : BlocListener<TextBookBloc, TextBookState>(
              listenWhen: (previous, current) {
                // Only trigger on visibleIndices changes, NOT selectedIndex
                // This prevents interference with text selection
                if (current is! TextBookLoaded) return false;
                if (previous is! TextBookLoaded) return true;

                final prevVisibleIndex = previous.visibleIndices.isNotEmpty
                    ? previous.visibleIndices.first
                    : -1;
                final currVisibleIndex = current.visibleIndices.isNotEmpty
                    ? current.visibleIndices.first
                    : -1;

                return prevVisibleIndex != currVisibleIndex ||
                    previous.showLeftPane != current.showLeftPane;
              },
              listener: (context, state) {
                if (state is! TextBookLoaded ||
                    context.read<TextBookBloc>().isClosed) {
                  return;
                }
                if (!state.showLeftPane) {
                  _wasLeftPaneShown = false;
                  return;
                }
                final justOpened = !_wasLeftPaneShown;
                _wasLeftPaneShown = true;
                if (_isManuallyScrolling) return;

                // Use only visibleIndices, not selectedIndex
                final index = state.visibleIndices.isNotEmpty
                    ? state.visibleIndices.first
                    : null;
                if (index == null) return;

                if (justOpened) {
                  // פתיחת הפאנל: גלילה מיידית למיקום הפעיל (ה-guard
                  // עלול לחסום אחרת אם נשבש ברקע בזמן שהפאנל היה סגור).
                  _lastScrolledEntryIds.clear();
                  _findAndHighlightEntry(index);
                } else {
                  // Debounce to prevent rapid updates during fast scrolling
                  _debounceTimer?.cancel();
                  _debounceTimer = Timer(
                    const Duration(milliseconds: 300),
                    () {
                      if (mounted) {
                        _findAndHighlightEntry(index);
                      }
                    },
                  );
                }
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollStartNotification &&
                      notification.dragDetails != null) {
                    _isManuallyScrolling = true;
                  } else if (notification is ScrollEndNotification) {
                    _isManuallyScrolling = false;
                  }
                  return false;
                },
                child: NavTreeFocusGroup(
                  child: ListView.builder(
                    controller: _sidebarScrollController,
                    padding: kNavTreeListPadding,
                    // +1 עבור הכותרת הראשית, שנגללת עם הרשימה.
                    itemCount: _structures.length + 1,
                    itemBuilder: (context, index) => index == 0
                        ? NavTreeHeader(
                            title: widget.book.title,
                            trailing: const NavPanelSearchToggle(),
                          )
                        : _buildStructureItem(_structures[index - 1]),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildSearchResults() {
    final matches = _getMatchingEntries(_searchController.text);

    if (matches.isEmpty) {
      return const OtzariaEmptyState(
        isCompact: true,
        icon: OtzariaIcons.search_in_titles_24_regular,
        title: 'לא נמצאו תוצאות',
      );
    }

    return NavTreeFocusGroup(
      // רשימה וירטואלית לפי אינדקס, כדי שדפדוף בחיצים יוכל לגלול גם אל
      // תוצאה שטרם הורכבה בעץ.
      child: ScrollablePositionedList.builder(
        itemScrollController: _searchScrollController,
        itemPositionsListener: _searchPositionsListener,
        padding: kNavTreeListPadding,
        itemCount: matches.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return NavTreeHeader(
              title: widget.book.title,
              trailing: const NavPanelSearchToggle(),
            );
          }
          final (:structureId, :entry) = matches[index - 1];
          // בזמן דפדוף בחיצים הסימון הוא של תוצאת הדפדוף, לא של המיקום הפעיל.
          final isSelected = _highlightedMatchPos != null
              ? _highlightedMatchPos == index - 1
              : entry.id == _activeEntryIds[structureId];
          return NavTreeGroupCard(
            isGroupStart: index == 1,
            isGroupEnd: index == matches.length,
            child: NavTreeTile.heading(
              title: entry.text ?? '',
              level: 0,
              isSelected: isSelected,
              onTap: () => _handleEntryTap(structureId, entry),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStructureItem(AltTocStructure structure) {
    final isExpanded = _structureExpanded[structure.id] ?? false;
    final roots = _structureRoots[structure.id] ?? [];
    // הכותרות נטענות רק בפתיחה, ולכן מבנה שעוד לא נטען מציג חץ.
    final hasChildren =
        !_structureRoots.containsKey(structure.id) ||
        roots.isNotEmpty ||
        (structure.id == kDibburimStructureId && _hasDibburimEntries);

    return Column(
      children: [
        // כותרת המבנה — שורש העץ הזה, כרטיס עומד בפני עצמו.
        NavTreeGroupCard(
          isGroupStart: true,
          isGroupEnd: true,
          child: NavTreeTile.category(
            title: structure.heTitle ?? structure.title ?? structure.key,
            level: 0,
            isExpanded: isExpanded,
            hasChildren: hasChildren,
            onTap: () => _handleStructureTap(structure),
            onToggleExpand: () => _toggleStructure(structure),
          ),
        ),
        // כל כותרת ראשית עם כותרות המשנה שלה היא כרטיס נפרד, ולא רצף אחד.
        if (isExpanded)
          ...roots.map(
            (root) => _buildEntryItem(structure.id, root, isGroupStart: true),
          ),
      ],
    );
  }

  Widget _buildEntryItem(
    int structureId,
    AltTocEntry entry, {
    bool isGroupStart = false,
    bool isGroupEnd = true,
  }) {
    final itemKey = _itemKeys.putIfAbsent(entry.id, () => GlobalKey());

    final children = _structureChildren[structureId]?[entry.id];
    final hasChildren = children != null && children.isNotEmpty;
    final isExpanded = _entryExpanded[entry.id] ?? false;
    // רמת המבנה היא 0, ולכן ערכי ה-TOC מוזחים רמה אחת פנימה.
    final level = entry.level + 1;

    final tile = ValueListenableBuilder<int>(
      valueListenable: _selectionTicks.putIfAbsent(
        entry.id,
        () => ValueNotifier(0),
      ),
      builder: (context, _, _) => NavTreeTile.heading(
        title: entry.text ?? '',
        level: level,
        isSelected: entry.id == _activeEntryIds[structureId],
        isExpanded: isExpanded,
        hasChildren: hasChildren,
        onTap: () =>
            _handleEntryTap(structureId, entry, toggleIfLinkless: hasChildren),
        onToggleExpand: hasChildren
            ? () => _toggleEntryExpanded(entry.id)
            : null,
      ),
    );

    return Column(
      key: itemKey,
      children: [
        NavTreeGroupCard(
          isGroupStart: isGroupStart,
          isGroupEnd: isGroupEnd && !(hasChildren && isExpanded),
          child: tile,
        ),
        if (hasChildren && isExpanded)
          ...children.asMap().entries.map(
            (e) => _buildEntryItem(
              structureId,
              e.value,
              isGroupEnd: isGroupEnd && e.key == children.length - 1,
            ),
          ),
      ],
    );
  }
}
