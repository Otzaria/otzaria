import 'dart:async';
import 'package:otzaria/theme/app_tokens.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
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
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class AltTocSidebarView extends StatefulWidget {
  final Book book;
  final void Function() closeLeftPaneCallback;
  final ItemScrollController scrollController;

  /// פוקוס-נוד לשדה החיפוש של הכותרות, מנוהל ע"י המסך האב כדי לאפשר
  /// פוקוס אוטומטי בפתיחת הפאנל ובמעבר ללשונית 'כותרות'.
  final FocusNode? focusNode;

  const AltTocSidebarView({
    super.key,
    required this.book,
    required this.closeLeftPaneCallback,
    required this.scrollController,
    this.focusNode,
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

  // Available structures (e.g., Parasha, Daf)
  List<AltTocStructure> _structures = [];

  // Structure Data Caches
  // StructureID -> Root Entries
  final Map<int, List<AltTocEntry>> _structureRoots = {};
  // StructureID -> (ParentID -> Children)
  final Map<int, Map<int, List<AltTocEntry>>> _structureChildren = {};
  // StructureID -> (ChildID -> ParentID)
  final Map<int, Map<int, int>> _structureParents = {};

  // Expanded state
  // StructureID -> bool
  final Map<int, bool> _structureExpanded = {};
  // EntryID -> bool
  final Map<int, bool> _entryExpanded = {};

  // Active entry
  int? _activeEntryId;
  int? _lastScrolledEntryId;

  // מעקב פתיחת הפאנל: גלילה מחדש למיקום הפעיל רק במעבר סגור→פתוח.
  bool _wasLeftPaneShown = false;

  // Debounce timer to prevent rapid updates during scrolling
  Timer? _debounceTimer;

  // Caches the in-flight Future per structureId so every awaiter shares the same load
  final Map<int, Future<void>> _loadingFutures = {};

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStructures();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _sidebarScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onSearchChanged(String query) async {
    // Update UI immediately so the clear button and search mode appear without delay
    setState(() {});

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
    setState(() {});
  }

  List<AltTocEntry> _flattenEntries(int structureId) {
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
    return result;
  }

  List<({int structureId, AltTocEntry entry})> _getMatchingEntries(
    String rawQuery,
  ) {
    final normalizedQuery = normalizeFindQuery(rawQuery);
    if (normalizedQuery.isEmpty) return [];

    final results = <({int structureId, AltTocEntry entry})>[];
    for (final structure in _structures) {
      for (final entry in _flattenEntries(structure.id)) {
        final entryText = normalizeFindText(entry.text ?? '');
        if (entryText.contains(normalizedQuery)) {
          results.add((structureId: structure.id, entry: entry));
        }
      }
    }
    return results;
  }

  Future<void> _loadStructures() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final structures = await DatabaseLibraryProvider.instance
          .getAlternativeStructuresForBook(widget.book.title);
      if (mounted) {
        setState(() {
          _structures = structures;
          _isLoading = false;

          // If only one structure, expand it by default
          if (structures.length == 1) {
            _toggleStructure(structures.first);
          }
        });

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
      final entries = await DatabaseLibraryProvider.instance
          .getAllAlternativeEntries(structureId);

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
  }

  void _updateActiveItemFromBloc() {
    if (_isManuallyScrolling) return;

    final state = context.read<TextBookBloc>().state;
    // כשהפאנל סגור הגלילה נכשלת אך משבשת את _lastScrolledEntryId
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

  Future<void> _findAndHighlightEntry(int lineIndex) async {
    for (final structure in _structures) {
      final entryId = await DatabaseLibraryProvider.instance
          .getAltTocEntryForLine(widget.book.title, lineIndex, structure.id);

      if (entryId != null) {
        if (mounted && entryId != _activeEntryId) {
          setState(() {
            // Ensure loaded
            if (!_structureRoots.containsKey(structure.id)) {
              _structureExpanded[structure.id] = true;
              _loadEntriesForStructure(structure.id).then((_) {
                if (mounted) _expandParents(structure.id, entryId);
              });
            } else {
              _structureExpanded[structure.id] = true;
              _expandParents(structure.id, entryId);
            }

            _activeEntryId = entryId;
          });

          if (_activeEntryId != _lastScrolledEntryId) {
            _scrollToActiveItem(entryId);
          }
        }
        return;
      }
    }
  }

  void _scrollToActiveItem(int entryId) {
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

        _lastScrolledEntryId = entryId;
      } catch (e) {
        debugPrint('Error scrolling to active item: $e');
      }
    });
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
  }

  void _openLink(Link link) {
    if (link.path2 == widget.book.title) {
      // Ensure index is at least 0 to prevent RangeError
      final index = (link.index2 - 1).clamp(0, double.maxFinite).toInt();
      final state = context.read<TextBookBloc>().state;
      if (state is! TextBookLoaded) {
        return;
      }
      final navigation = scrollToSourceLine(
        scrollController: widget.scrollController,
        scrollOffsetController: state.scrollOffsetController,
        positionsListener: state.positionsListener,
        segments: state.readingSegments,
        lineIndex: index,
        viewportExtent:
            context.size?.height ?? MediaQuery.sizeOf(context).height,
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

  void _handleEntryTap(int structureId, AltTocEntry entry) {
    _isManuallyScrolling = false;
    _lastScrolledEntryId = null;

    // Always navigate on text tap, as requested
    _handleLeafClick(structureId, entry);
  }

  void _handleLeafClick(int structureId, AltTocEntry entry) async {
    try {
      // 1. Try to get links for this entry
      var links = await DatabaseLibraryProvider.instance.getLinksForAltTocEntry(
        structureId,
        entry.id,
      );

      // 2. If no links, but has children, try to get link from first child (recursively)
      if (links.isEmpty) {
        AltTocEntry? current = entry;
        while (current != null && links.isEmpty) {
          final children = _structureChildren[structureId]?[current.id];
          if (children != null && children.isNotEmpty) {
            current = children.first;
            links = await DatabaseLibraryProvider.instance
                .getLinksForAltTocEntry(structureId, current.id);
          } else {
            current = null;
          }
        }
      }

      if (!mounted) return;

      if (links.isNotEmpty) {
        _openLink(links.first);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('לא נמצא קישור לכותרת זו')),
        );
      }
    } catch (e) {
      debugPrint('Error handling leaf click: $e');
    }
  }

  Future<void> _handleStructureTap(AltTocStructure structure) async {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('לא נמצאו כותרות למבנה זה')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_structures.isEmpty) {
      return const Center(child: Text('אין כותרות חלופיות זמינות'));
    }

    final isSearching = _searchController.text.isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: RtlTextField(
            controller: _searchController,
            // ללא autofocus: הפוקוס מנוהל אך ורק דרך focusNode מהמסך האב
            // (_focusActiveTabSearchField), שמכבד את ההגנה מפני פוקוס אוטומטי
            // באנדרואיד. autofocus היה עוקף הגנה זו וקופץ מקלדת.
            focusNode: widget.focusNode,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'איתור כותרת...',
              prefixIcon: const Icon(FluentIcons.search_24_regular),
              suffixIcon: isSearching
                  ? IconButton(
                      icon: const Icon(FluentIcons.dismiss_24_regular),
                      onPressed: _clearSearch,
                    )
                  : null,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: AppTokens.borderRadiusAll,
              ),
            ),
          ),
        ),
        Expanded(
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
                      _lastScrolledEntryId = null;
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
                    child: ListView.builder(
                      controller: _sidebarScrollController,
                      itemCount: _structures.length,
                      itemBuilder: (context, index) {
                        return _buildStructureItem(_structures[index]);
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    final matches = _getMatchingEntries(_searchController.text);

    if (matches.isEmpty) {
      return const Center(
        child: Text(
          'לא נמצאו תוצאות',
        ),
      );
    }

    return ListView.builder(
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final (:structureId, :entry) = matches[index];
        final isSelected = entry.id == _activeEntryId;

        return Container(
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withValues(alpha: 0.3)
                : null,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 0.5,
              ),
            ),
          ),
          child: InkWell(
            onTap: () => _handleEntryTap(structureId, entry),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              child: Row(
                children: [
                  Icon(
                    FluentIcons.text_bullet_list_24_regular,
                    color: Theme.of(context).colorScheme.secondary,
                    size: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry.text ?? '',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStructureItem(AltTocStructure structure) {
    final isExpanded = _structureExpanded[structure.id] ?? false;
    final roots = _structureRoots[structure.id] ?? [];

    return Column(
      children: [
        // Structure Header (Root of this tree)
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              // Navigation Zone (Icon + Title)
              Expanded(
                child: InkWell(
                  onTap: () => _handleStructureTap(structure),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 12.0,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          FluentIcons.book_24_regular,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            structure.heTitle ??
                                structure.title ??
                                structure.key,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Expansion Zone (Arrow)
              InkWell(
                onTap: () => _toggleStructure(structure),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  child: Icon(
                    isExpanded
                        ? FluentIcons.chevron_up_24_regular
                        : FluentIcons.chevron_down_24_regular,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Children (The actual TOC)
        if (isExpanded)
          ...roots.map((entry) => _buildEntryItem(structure.id, entry)),
      ],
    );
  }

  Widget _buildEntryItem(int structureId, AltTocEntry entry) {
    final itemKey = _itemKeys.putIfAbsent(entry.id, () => GlobalKey());

    final children = _structureChildren[structureId]?[entry.id];
    final hasChildren = children != null && children.isNotEmpty;
    final isExpanded = _entryExpanded[entry.id] ?? false;
    final isSelected = entry.id == _activeEntryId;

    final level = entry.level;

    return Column(
      key: itemKey,
      children: [
        Container(
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withValues(alpha: 0.3)
                : null,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              // Content Area (Navigation Only)
              Expanded(
                child: InkWell(
                  onTap: () => _handleEntryTap(structureId, entry),
                  child: Container(
                    padding: EdgeInsets.only(
                      right: 16.0 + (level * 24.0),
                      left: 8.0,
                      top: 12.0,
                      bottom: 12.0,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          FluentIcons.text_bullet_list_24_regular,
                          color: Theme.of(context).colorScheme.secondary,
                          size: 18,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            entry.text ?? '',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Expansion Arrow (if children exist) (Toggle Only)
              if (hasChildren)
                InkWell(
                  onTap: () => _toggleEntryExpanded(entry.id),
                  child: Container(
                    padding: const EdgeInsets.only(
                      left: 16.0,
                      right: 8.0,
                      top: 12.0,
                      bottom: 12.0,
                    ),
                    child: Icon(
                      isExpanded
                          ? FluentIcons.chevron_up_24_regular
                          : FluentIcons.chevron_down_24_regular,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Children
        if (hasChildren && isExpanded)
          ...children.map((child) => _buildEntryItem(structureId, child)),
      ],
    );
  }
}
