import 'package:flutter/material.dart';
import 'package:otzaria/text_book/utils/visible_index.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/widgets/text_book_state_builder.dart';
import 'package:otzaria/text_book/view/combined_view/commentary_content.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/text_book/view/commentators_list_screen.dart';
import 'package:otzaria/widgets/misc/commentators_filter_button.dart';
import 'package:otzaria/widgets/layout/commentators_filter_screen.dart';
import 'package:otzaria/widgets/lists/commentators_selection_panel.dart';
import 'package:otzaria/widgets/misc/progressive_scrolling.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/utils/ui/context_menu_utils.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/widgets/feedback/app_future_builder.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:otzaria/services/commentary_service.dart';
import 'package:otzaria/text_book/view/selection/selection_sync_controller.dart';

// Type alias לתאימות לאחור - משתמש ב-LinkGroup מה-Service
typedef CommentaryGroup = LinkGroup;

class CommentaryListBase extends StatefulWidget {
  final Function(TextBookTab) openBookCallback;
  final double fontSize;
  final List<int>? indexes;
  final bool showSearch;
  final VoidCallback? onClosePane;
  final bool shrinkWrap;
  final ItemPositionsListener? itemPositionsListener;
  final List<String>? selectedCommentatorsOverride;
  final List<CommentatorGroup>? commentatorGroupsOverride;
  final String? bookTitleOverride;
  final ValueChanged<List<String>>? onSelectedCommentatorsOverrideChanged;
  final SelectionSyncController? selectionSyncController;

  const CommentaryListBase({
    super.key,
    required this.openBookCallback,
    required this.fontSize,
    this.indexes,
    required this.showSearch,
    this.onClosePane,
    this.shrinkWrap = true,
    this.itemPositionsListener,
    this.selectedCommentatorsOverride,
    this.commentatorGroupsOverride,
    this.bookTitleOverride,
    this.onSelectedCommentatorsOverrideChanged,
    this.selectionSyncController,
  });

  @override
  State<CommentaryListBase> createState() => CommentaryListBaseState();
}

class CommentaryListBaseState extends State<CommentaryListBase> {
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier<String>('');
  final ScrollOffsetController scrollController = ScrollOffsetController();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final Map<String, GlobalKey> _itemKeys = {};
  final ValueNotifier<int> _currentSearchIndexNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _totalSearchResultsNotifier = ValueNotifier<int>(0);
  final Map<String, int> _searchResultsPerLink = {};
  int _lastScrollIndex = 0; // שומר את מיקום הגלילה האחרון
  bool _allExpanded = true; // מצב גלובלי של פתיחה/סגירה של כל המפרשים
  final Map<String, bool> _expansionStates =
      {}; // מעקב אחרי מצב כל קבוצת מפרשים
  String? _cachedGroupingSignature;
  Future<List<CommentaryGroup>>? _cachedGroupsFuture;

  // Anti-jitter search stats
  Timer? _searchUpdateDebounce;
  final Map<String, int> _pendingCounts = {};

  final ValueNotifier<String?> _savedSelectedText =
      ValueNotifier<String?>(null); // טקסט נבחר לתפריט הקשר
  final ValueNotifier<Link?> _lastSelectedLink =
      ValueNotifier<Link?>(null); // ה-link האחרון שנוגעו בו (לכותרות בהעתקה)
  bool _showCommentatorsFilter = false; // האם להציג את מסך בחירת המפרשים
  bool _filterWasAutoOpened = false; // האם מסך הסינון נפתח אוטומטית (לא ידנית)
  bool _userInteractedWithFilter =
      false; // האם המשתמש בחר בעצמו בתוך פאנל הסינון
  final FocusNode _focusNode = FocusNode();
  final Object _selectionOwner = Object();
  int _selectionRevision = 0;

  String _getLinkKey(Link link) =>
      '${link.index1}_${link.path2}_${link.index2}';

  // רשימה של כל ה-links לפי סדר הופעתם (נבנית מחדש בכל build)
  List<Link> _orderedLinks = [];

  List<String> _selectedCommentators(TextBookLoaded state) {
    return widget.selectedCommentatorsOverride ?? state.activeCommentators;
  }

  String _buildGroupingSignature(List<Link> links) {
    return links
        .map((link) =>
            '${link.index1}|${link.path2}|${link.index2}|${link.connectionType}')
        .join('||');
  }

  Future<List<CommentaryGroup>> _getCachedGroups(List<Link> links) {
    final signature = _buildGroupingSignature(links);
    if (_cachedGroupingSignature == signature && _cachedGroupsFuture != null) {
      return _cachedGroupsFuture!;
    }

    _cachedGroupingSignature = signature;
    _cachedGroupsFuture = CommentaryService.groupConsecutiveLinksAsync(links);
    return _cachedGroupsFuture!;
  }

  List<CommentatorGroup> _commentatorGroups(TextBookLoaded state) {
    return widget.commentatorGroupsOverride ?? state.commentatorGroups;
  }

  String _bookTitle(TextBookLoaded state) {
    return widget.bookTitleOverride ?? state.book.title;
  }

  int _getItemSearchIndex(Link link) {
    // מחשב את האינדקס המצטבר עד ל-link הנוכחי
    int cumulativeIndex = 0;
    final linkKey = _getLinkKey(link);

    for (final orderedLink in _orderedLinks) {
      final currentKey = _getLinkKey(orderedLink);
      if (currentKey == linkKey) {
        // מצאנו את ה-link הנוכחי
        final itemResults = _searchResultsPerLink[linkKey] ?? 0;
        if (itemResults == 0) return -1;

        // מחשב את האינדקס היחסי בתוך ה-link הזה
        final relativeIndex =
            _currentSearchIndexNotifier.value - cumulativeIndex;
        return (relativeIndex >= 0 && relativeIndex < itemResults)
            ? relativeIndex
            : -1;
      }
      cumulativeIndex += _searchResultsPerLink[currentKey] ?? 0;
    }

    return -1;
  }

  @override
  void initState() {
    super.initState();
    // האזנה לשינויים במיקום הגלילה כדי לשמור את המיקום האחרון
    _itemPositionsListener.itemPositions.addListener(_updateLastScrollIndex);
    widget.selectionSyncController?.addListener(_handleExternalSelectionChange);
  }

  @override
  void didUpdateWidget(CommentaryListBase oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionSyncController != widget.selectionSyncController) {
      oldWidget.selectionSyncController
          ?.removeListener(_handleExternalSelectionChange);
      widget.selectionSyncController
          ?.addListener(_handleExternalSelectionChange);
    }
    // סגירה אוטומטית של מסך הסינון כאשר המפרשים עוברים מריק לא-ריק
    // (קורה כאשר המשתמש בוחר "כל המפרשים" מהתפריט הימני)
    if (_showCommentatorsFilter &&
        _filterWasAutoOpened &&
        !_userInteractedWithFilter &&
        (oldWidget.selectedCommentatorsOverride?.isEmpty ?? true) &&
        (widget.selectedCommentatorsOverride?.isNotEmpty ?? false)) {
      setState(() {
        _showCommentatorsFilter = false;
        _filterWasAutoOpened = false;
      });
    }
  }

  void scrollToTop() {
    if (_itemScrollController.isAttached) {
      _itemScrollController.scrollTo(
        index: 0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _updateLastScrollIndex() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      _lastScrollIndex = topmostVisibleIndex(positions);
    }
  }

  void _openCommentatorsFilter() {
    setState(() {
      _showCommentatorsFilter = true;
      _filterWasAutoOpened = false;
    });
  }

  void _closeCommentatorsFilter() {
    setState(() {
      _showCommentatorsFilter = false;
      _userInteractedWithFilter = false;
    });
  }

  @override
  void dispose() {
    _searchUpdateDebounce?.cancel();
    _itemPositionsListener.itemPositions.removeListener(_updateLastScrollIndex);
    widget.selectionSyncController
        ?.removeListener(_handleExternalSelectionChange);
    _searchController.dispose();
    _savedSelectedText.dispose();
    _lastSelectedLink.dispose();
    _searchQueryNotifier.dispose();
    _currentSearchIndexNotifier.dispose();
    _totalSearchResultsNotifier.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleExternalSelectionChange() {
    final controller = widget.selectionSyncController;
    if (controller == null ||
        identical(controller.activeOwner, _selectionOwner)) {
      return;
    }

    if (!mounted) {
      return;
    }

    _savedSelectedText.value = null;
    _lastSelectedLink.value = null;
    setState(() {
      _selectionRevision = controller.revision;
    });
  }

  Future<void> _scrollToSearchResult() async {
    if (_totalSearchResultsNotifier.value == 0 ||
        _orderedLinks.isEmpty ||
        !_itemScrollController.isAttached) {
      return;
    }

    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) {
      return;
    }

    int cumulativeIndex = 0;
    Link? targetLink;

    // 1. מוצא את ה-link שמכיל את תוצאת החיפוש הנוכחית
    for (final link in _orderedLinks) {
      final linkKey = _getLinkKey(link);
      final itemResults = _searchResultsPerLink[linkKey] ?? 0;
      if (_currentSearchIndexNotifier.value < cumulativeIndex + itemResults) {
        targetLink = link;
        break;
      }
      cumulativeIndex += itemResults;
    }

    if (targetLink == null) {
      return;
    }

    // 2. מוצא את ה-group שמכיל את ה-link
    final groups = await _getCachedGroups(_orderedLinks);
    int targetGroupIndex = -1;
    CommentaryGroup? targetGroup;

    for (int i = 0; i < groups.length; i++) {
      final group = groups[i];
      if (group.links.any((l) => _getLinkKey(l) == _getLinkKey(targetLink!))) {
        targetGroupIndex = i;
        targetGroup = group;
        break;
      }
    }

    if (targetGroupIndex == -1 || targetGroup == null) {
      return;
    }

    // 3. מבטיח שה-ExpansionTile של הקבוצה פתוח
    final groupKey = targetGroup.bookTitle;

    final bool isCurrentlyExpanded = _expansionStates[groupKey] ?? true;

    // אם צריך לפתוח, פותח ומחכה לאנימציה
    if (!isCurrentlyExpanded) {
      setState(() {
        _expansionStates[groupKey] = true;
      });
    }

    // 4. ביצוע הגלילה בתוך Callback
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // המתנה לסיום אנימציית הפתיחה אם הייתה
      if (!isCurrentlyExpanded) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (!mounted) return;
      }

      final linkKey = _getLinkKey(targetLink!);
      final itemKey = _itemKeys[linkKey];
      final BuildContext? itemContext = itemKey?.currentContext;

      // בודק אם הפריט כבר בעץ הרינדור (לא נדרשת גלילה גסה להכניסו לזיכרון)
      final bool itemInRenderTree = itemContext != null &&
          itemContext.mounted &&
          itemContext.findRenderObject() is RenderBox;

      // שלב א': גלילה גסה לקבוצה – רק אם הפריט לא בעץ הרינדור
      if (!itemInRenderTree) {
        if (_itemScrollController.isAttached) {
          _itemScrollController.scrollTo(
            index: targetGroupIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            alignment: 0.05,
          );
        }
        await Future.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
      }

      // שלב ב': גלילה עדינה לפריט הספציפי
      final BuildContext? ctx = itemKey?.currentContext;
      if (ctx != null && ctx.mounted) {
        try {
          final RenderObject? itemRenderObj = ctx.findRenderObject();
          if (itemRenderObj is! RenderBox) return;
          final RenderBox itemBox = itemRenderObj;

          final ScrollableState scrollable = Scrollable.of(ctx);
          if (!scrollable.mounted) return;

          final RenderObject? viewportRenderObj =
              scrollable.context.findRenderObject();
          if (viewportRenderObj is! RenderBox) return;
          final RenderBox viewportBox = viewportRenderObj;

          final Offset itemOffset =
              itemBox.localToGlobal(Offset.zero, ancestor: viewportBox);

          // מביא את הפריט ל-10% מראש הרשימה
          final double targetY = viewportBox.size.height * 0.1;
          final double scrollDelta = itemOffset.dy - targetY;

          if (scrollDelta.abs() > 10) {
            scrollController.animateScroll(
                offset: scrollDelta,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut);
          }
        } catch (e) {
          debugPrint('Error during micro-scrolling: $e');
        }
      }
    });
  }

  void _updateSearchResultsCount(Link link, int count) {
    if (!mounted) return;

    final key = _getLinkKey(link);
    // אם הכמות לא השתנתה, אין צורך לעשות כלום
    if (_searchResultsPerLink[key] == count) return;

    _pendingCounts[key] = count;

    // אם כבר יש טיימר פעיל, רק עדכנו את הרשימה הממתינה
    if (_searchUpdateDebounce?.isActive ?? false) return;

    // הפעלת הטיימר
    _searchUpdateDebounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      _searchResultsPerLink.addAll(_pendingCounts);
      _pendingCounts.clear();
      _totalSearchResultsNotifier.value =
          _searchResultsPerLink.values.fold(0, (sum, count) => sum + count);

      // תיקון אינדקס אם חרגנו מהגבולות
      if (_currentSearchIndexNotifier.value >=
              _totalSearchResultsNotifier.value &&
          _totalSearchResultsNotifier.value > 0) {
        _currentSearchIndexNotifier.value = 0;
      }
    });
  }

  void _updateGlobalExpansionState() {
    if (_expansionStates.isEmpty) return;

    // בודק אם כל המפרשים פתוחים
    final allExpanded = _expansionStates.values.every((state) => state == true);
    // בודק אם כל המפרשים סגורים
    final allCollapsed =
        _expansionStates.values.every((state) => state == false);

    // מעדכן את המצב הגלובלי רק אם כולם באותו מצב
    if (allExpanded) {
      _allExpanded = true;
    } else if (allCollapsed) {
      _allExpanded = false;
    }
    // אם יש מצב מעורב, לא משנים את _allExpanded
  }

  Widget _buildCommentaryGroupTile({
    required CommentaryGroup group,
    required TextBookLoaded state,
    required String indexesKey,
  }) {
    final groupKey = group.bookTitle;

    // אם אין מצב שמור עבור הקבוצה הזו, משתמש במצב הגלובלי
    if (!_expansionStates.containsKey(groupKey)) {
      _expansionStates[groupKey] = _allExpanded;
    }

    final isExpanded = _expansionStates[groupKey] ?? _allExpanded;

    return _CollapsibleCommentaryGroup(
      key: PageStorageKey(groupKey),
      group: group,
      isExpanded: isExpanded,
      fontSize: widget.fontSize,
      openBookCallback: widget.openBookCallback,
      removeNikud: state.removeNikud,
      removePunctuation: state.removePunctuation,
      showSearch: widget.showSearch,
      searchQueryListenable: _searchQueryNotifier,
      currentSearchIndexListenable: _currentSearchIndexNotifier,
      totalSearchResultsListenable: _totalSearchResultsNotifier,
      getItemSearchIndex: _getItemSearchIndex,
      updateSearchResultsCount: _updateSearchResultsCount,
      itemKeys: _itemKeys,
      getLinkKey: _getLinkKey,
      indexesKey: indexesKey,
      savedSelectedTextListenable: _savedSelectedText,
      lastSelectedLinkListenable: _lastSelectedLink,
      selectionSyncController: widget.selectionSyncController,
      selectionOwner: _selectionOwner,
      selectionRevision: _selectionRevision,
      onExpansionChanged: (expanded) {
        _expansionStates[groupKey] = expanded;
        // בודק אם כל המפרשים פתוחים או סגורים ומעדכן את המצב הגלובלי
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _updateGlobalExpansionState();
            });
          }
        });
      },
      onLinkSelected: (link, text) {
        _savedSelectedText.value = text;
        _lastSelectedLink.value = link;
        _focusNode.requestFocus();
      },
      onLinkSelectionCleared: () {
        _savedSelectedText.value = null;
        _lastSelectedLink.value = null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextBookStateBuilder(
        buildWhen: (previous, current) {
          // מבטיח בניה מחדש רק כשיש שינוי בנתונים שמשפיעים על תצוגת המפרשים
          if (previous is! TextBookLoaded || current is! TextBookLoaded) {
            return true;
          }
          return !listEquals(
                  previous.activeCommentators, current.activeCommentators) ||
              previous.links != current.links || // השוואת רפרנס לביצועים
              !listEquals(previous.visibleIndices, current.visibleIndices) ||
              previous.selectedIndex != current.selectedIndex ||
              previous.fontSize != current.fontSize ||
              previous.removeNikud != current.removeNikud ||
              previous.removePunctuation != current.removePunctuation;
        },
        loadingWidget: const Center(),
        builder: (context, state) {
          final selectedCommentators = _selectedCommentators(state);
          final shouldAutoOpenOverrideFilter = widget.showSearch &&
              widget.onSelectedCommentatorsOverrideChanged != null &&
              selectedCommentators.isEmpty &&
              !_showCommentatorsFilter;

          if (shouldAutoOpenOverrideFilter) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _showCommentatorsFilter = true;
                  _filterWasAutoOpened = true;
                });
              }
            });
            return const Center(child: CircularProgressIndicator());
          }

          Widget buildList() {
            return Builder(
              builder: (context) {
                // בודק מראש אם יש קישורים רלוונטיים לאינדקסים הנוכחיים
                final currentIndexesRaw = widget.indexes ??
                    (state.selectedIndex != null
                        ? [state.selectedIndex!]
                        : state.visibleIndices);

                // בהפעלה מחדש/מצבים נדירים יכול להגיע לכאן עם רשימת אינדקסים ריקה,
                // מה שגורם ל"אין מפרשים" גם כשיש. נבחר אינדקס ברירת מחדל יציב.
                final currentIndexes = currentIndexesRaw.isNotEmpty
                    ? currentIndexesRaw
                    : [
                        state.selectedIndex ??
                            (state.visibleIndices.isNotEmpty
                                ? state.visibleIndices.first
                                : 0)
                      ];

                // בדיקה אם יש בכלל קישורים לאינדקסים הנוכחיים (ללא סינון מפרשים)
                final hasAnyCommentaryLinks = currentIndexes.any((idx) {
                  final lineLinks = state.linksByLine[idx + 1];
                  if (lineLinks == null) return false;
                  return lineLinks.any((link) {
                    final type = link.connectionType.toUpperCase();
                    return type == "COMMENTARY" || type == "TARGUM";
                  });
                });

                // סינון מהיר של קישורים רלוונטיים
                final hasRelevantLinks = currentIndexes.any((idx) {
                  final lineLinks = state.linksByLine[idx + 1];
                  if (lineLinks == null) return false;
                  return lineLinks.any((link) => selectedCommentators
                      .contains(utils.getTitleFromPath(link.path2)));
                });

                // אם אין קישורים רלוונטיים
                if (!hasRelevantLinks) {
                  // אם יש מפרשים זמינים אבל לא נבחרו בכלל - פתח אוטומטית את מסך הבחירה
                  if (widget.showSearch &&
                      hasAnyCommentaryLinks &&
                      selectedCommentators.isEmpty &&
                      !_showCommentatorsFilter) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _showCommentatorsFilter = true;
                          _filterWasAutoOpened = true;
                        });
                      }
                    });
                    return const Center(child: CircularProgressIndicator());
                  }

                  // אין מפרשים בכלל לקטע הזה, או שיש מפרשים נבחרים אבל הם לא רלוונטיים
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        hasAnyCommentaryLinks
                            ? 'לא נמצאו מפרשים מהנבחרים לקטע זה'
                            : 'לא נמצאו מפרשים לקטע הנבחר',
                        style: TextStyle(
                          fontSize: widget.fontSize * 0.7,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final commentaryWidget = FutureBuilder<List<Link>>(
                  future: getLinksforIndexs(
                      indexes: currentIndexes,
                      links: state.links,
                      commentatorsToShow: selectedCommentators),
                  builder: (context, thisLinksSnapshot) {
                    if (!thisLinksSnapshot.hasData) {
                      // רק אם יש קישורים רלוונטיים, מציג אנימציית טעינה
                      return _buildSkeletonLoading();
                    }
                    if (thisLinksSnapshot.data!.isEmpty) {
                      // אם אין מפרשים, פשוט נציג מסך ריק
                      return const SizedBox.shrink();
                    }
                    final data = thisLinksSnapshot.data!;

                    // שומר את הסדר של ה-links לצורך חישוב אינדקס החיפוש
                    _orderedLinks = data;

                    // מנקה מפתחות ישנים ומכין מפתחות חדשים
                    final currentLinkKeys =
                        data.map((l) => _getLinkKey(l)).toSet();
                    _itemKeys.removeWhere(
                        (key, value) => !currentLinkKeys.contains(key));
                    for (final key in currentLinkKeys) {
                      _itemKeys.putIfAbsent(key, () => GlobalKey());
                    }

                    // ניקוי ספירות חיפוש מקישורים שאינם בקטע הנוכחי
                    // (מניעת ספירה מנופחת ממעבר בין קטעים)
                    final staleSearchKeys = _searchResultsPerLink.keys
                        .where((key) => !currentLinkKeys.contains(key))
                        .toList();
                    if (staleSearchKeys.isNotEmpty) {
                      for (final key in staleSearchKeys) {
                        _searchResultsPerLink.remove(key);
                      }
                      _pendingCounts.removeWhere(
                          (key, _) => !currentLinkKeys.contains(key));
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        final newTotal = _searchResultsPerLink.values
                            .fold(0, (sum, c) => sum + c);
                        _totalSearchResultsNotifier.value = newTotal;
                        if (_currentSearchIndexNotifier.value >= newTotal) {
                          _currentSearchIndexNotifier.value = 0;
                        }
                      });
                    }

                    _expansionStates.removeWhere((key, value) => !data.any(
                        (link) => key == utils.getTitleFromPath(link.path2)));

                    final indexesKey = currentIndexes.join(',');

                    return Shortcuts(
                      shortcuts: <ShortcutActivator, Intent>{
                        LogicalKeySet(
                          LogicalKeyboardKey.control,
                          LogicalKeyboardKey.keyC,
                        ): const _CopyCommentaryIntent(),
                        LogicalKeySet(
                          LogicalKeyboardKey.meta,
                          LogicalKeyboardKey.keyC,
                        ): const _CopyCommentaryIntent(),
                      },
                      child: Actions(
                        actions: <Type, Action<Intent>>{
                          _CopyCommentaryIntent:
                              CallbackAction<_CopyCommentaryIntent>(
                            onInvoke: (_) {
                              ContextMenuUtils.copyFormattedText(
                                context: context,
                                savedSelectedText: _savedSelectedText.value,
                                fontSize: widget.fontSize,
                                link: _lastSelectedLink.value,
                              );
                              return null;
                            },
                          ),
                        },
                        child: Focus(
                          focusNode: _focusNode,
                          child: AppFutureBuilder<List<CommentaryGroup>>(
                            future: _getCachedGroups(data),
                            loadingWidget: _buildSkeletonLoading(),
                            builder: (context, groups) {
                              for (final group in groups) {
                                final groupKey = group.bookTitle;
                                _expansionStates.putIfAbsent(
                                    groupKey, () => _allExpanded);
                              }

                              return ProgressiveScroll(
                                scrollController: scrollController,
                                maxSpeed: 10000.0,
                                curve: 10.0,
                                accelerationFactor: 5,
                                child: ScrollablePositionedList.builder(
                                  itemScrollController: _itemScrollController,
                                  itemPositionsListener: _itemPositionsListener,
                                  initialScrollIndex: _lastScrollIndex.clamp(
                                      0, groups.length - 1),
                                  key: PageStorageKey(
                                      'commentary_${selectedCommentators.join(',')}_$_allExpanded'),
                                  physics: const ClampingScrollPhysics(),
                                  scrollOffsetController: scrollController,
                                  shrinkWrap: widget.shrinkWrap,
                                  itemCount: groups.length,
                                  itemBuilder: (context, groupIndex) {
                                    final group = groups[groupIndex];
                                    return _buildCommentaryGroupTile(
                                      group: group,
                                      state: state,
                                      indexesKey: indexesKey,
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                );

                return commentaryWidget;
              },
            );
          }

          if (widget.showSearch) {
            // אם מסך בחירת המפרשים פתוח, מציג אותו במקום הרשימה
            if (_showCommentatorsFilter) {
              final groups = _commentatorGroups(state);
              final customSelection =
                  widget.onSelectedCommentatorsOverrideChanged;
              return CommentatorsFilterScreen(
                onBack: _closeCommentatorsFilter,
                child: customSelection != null
                    ? CommentatorsSelectionPanel(
                        groups: groups,
                        selectedCommentators: selectedCommentators,
                        onSelectionChanged: (list) {
                          _userInteractedWithFilter = true;
                          customSelection(list);
                        },
                        bookTitle: _bookTitle(state),
                      )
                    : CommentatorsListView(
                        onCommentatorSelected: _closeCommentatorsFilter,
                      ),
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      // כפתור בחירת מפרשים - בצד ימין
                      CommentatorsFilterButton(
                        isActive: false,
                        onPressed: _openCommentatorsFilter,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        iconSize: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ValueListenableBuilder<String>(
                          valueListenable: _searchQueryNotifier,
                          builder: (context, query, _) {
                            return ValueListenableBuilder<int>(
                              valueListenable: _totalSearchResultsNotifier,
                              builder: (context, total, __) {
                                return ValueListenableBuilder<int>(
                                  valueListenable: _currentSearchIndexNotifier,
                                  builder: (context, currentIndex, ___) {
                                    return RtlTextField(
                                      controller: _searchController,
                                      decoration: InputDecoration(
                                        hintText: 'חפש בתוך המפרשים המוצגים...',
                                        prefixIcon: const Icon(
                                            FluentIcons.search_24_regular),
                                        suffixIcon: query.isNotEmpty
                                            ? Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (total > 1) ...[
                                                    Text(
                                                      '${currentIndex + 1}/$total',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    IconButton(
                                                      icon: const Icon(FluentIcons
                                                          .chevron_up_24_regular),
                                                      iconSize: 20,
                                                      padding: EdgeInsets.zero,
                                                      constraints:
                                                          const BoxConstraints(
                                                        minWidth: 24,
                                                        minHeight: 24,
                                                      ),
                                                      onPressed:
                                                          currentIndex > 0
                                                              ? () {
                                                                  _currentSearchIndexNotifier
                                                                          .value =
                                                                      currentIndex -
                                                                          1;
                                                                  _scrollToSearchResult();
                                                                }
                                                              : null,
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(FluentIcons
                                                          .chevron_down_24_regular),
                                                      iconSize: 20,
                                                      padding: EdgeInsets.zero,
                                                      constraints:
                                                          const BoxConstraints(
                                                        minWidth: 24,
                                                        minHeight: 24,
                                                      ),
                                                      onPressed: currentIndex <
                                                              total - 1
                                                          ? () {
                                                              _currentSearchIndexNotifier
                                                                      .value =
                                                                  currentIndex +
                                                                      1;
                                                              _scrollToSearchResult();
                                                            }
                                                          : null,
                                                    ),
                                                  ],
                                                  IconButton(
                                                    icon: const Icon(FluentIcons
                                                        .dismiss_24_regular),
                                                    onPressed: () {
                                                      _searchController.clear();
                                                      _searchQueryNotifier
                                                          .value = '';
                                                      _currentSearchIndexNotifier
                                                          .value = 0;
                                                      _totalSearchResultsNotifier
                                                          .value = 0;
                                                      _searchResultsPerLink
                                                          .clear();
                                                      _pendingCounts.clear();
                                                    },
                                                  ),
                                                ],
                                              )
                                            : null,
                                        isDense: true,
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8.0),
                                        ),
                                      ),
                                      onChanged: (value) {
                                        if (_searchQueryNotifier.value !=
                                            value) {
                                          _searchQueryNotifier.value = value;
                                          _currentSearchIndexNotifier.value = 0;
                                          _totalSearchResultsNotifier.value = 0;
                                          _searchResultsPerLink.clear();
                                          _pendingCounts.clear();
                                        }
                                      },
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      // כפתור סגירה/פתיחה גלובלית של כל המפרשים - מוצג רק אם יש מפרשים פעילים
                      if (selectedCommentators.isNotEmpty)
                        IconButton(
                          icon: Icon(
                            _allExpanded
                                ? FluentIcons.arrow_collapse_all_24_regular
                                : FluentIcons.arrow_expand_all_24_regular,
                          ),
                          tooltip: _allExpanded
                              ? 'כווץ את כל המפרשים'
                              : 'הרחב את כל המפרשים',
                          onPressed: () {
                            setState(() {
                              _allExpanded = !_allExpanded;
                              // מעדכן את כל המצבים של הקבוצות
                              for (var key in _expansionStates.keys) {
                                _expansionStates[key] = _allExpanded;
                              }
                            });
                          },
                        ),
                      // מציג את לחצן הסגירה רק אם יש callback
                      if (widget.onClosePane != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surface
                                .withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: IconButton(
                            iconSize: 18,
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            icon: const Icon(FluentIcons.dismiss_24_regular),
                            onPressed: widget.onClosePane,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Flexible(
                  fit: FlexFit.loose,
                  child: buildList(),
                ),
              ],
            );
          } else {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // כפתור גלובלי מעל הרשימה
                if (selectedCommentators.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.1),
                          foregroundColor:
                              Theme.of(context).colorScheme.primary,
                        ),
                        icon: Icon(
                          _allExpanded
                              ? FluentIcons.arrow_collapse_all_24_regular
                              : FluentIcons.arrow_expand_all_24_regular,
                        ),
                        tooltip: _allExpanded
                            ? 'כווץ את כל המפרשים'
                            : 'הרחב את כל המפרשים',
                        onPressed: () {
                          setState(() {
                            _allExpanded = !_allExpanded;
                            // מעדכן את כל המצבים של הקבוצות
                            for (var key in _expansionStates.keys) {
                              _expansionStates[key] = _allExpanded;
                            }
                          });
                        },
                      ),
                    ),
                  ),
                // הרשימה
                Flexible(
                  child: buildList(),
                ),
              ],
            );
          }
        });
  }

  /// בניית skeleton loading לפרשנות - מספר פרשנויות עם כותרת ושלוש שורות
  Widget _buildSkeletonLoading() {
    final baseColor = Theme.of(context).colorScheme.surfaceContainerHighest;

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4, // מציג 4 שלדים של פרשנויות
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // כותרת הפרשן
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _SkeletonLine(width: 0.3, height: 20, color: baseColor),
              ),
            ),
            // שלוש שורות תוכן
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: _SkeletonLine(width: 0.95, height: 16, color: baseColor),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: _SkeletonLine(width: 0.92, height: 16, color: baseColor),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: _SkeletonLine(width: 0.88, height: 16, color: baseColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget של שורה סטטית לשלד טעינה
class _SkeletonLine extends StatelessWidget {
  final double width;
  final double height;
  final Color color;

  const _SkeletonLine({
    required this.width,
    required this.color,
    this.height = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: MediaQuery.of(context).size.width * width,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// Widget מותאם אישית להצגת קבוצת מפרשים עם אפשרות כיווץ/הרחבה
/// שלא מפריע לבחירת טקסט והעתקה (במקום ExpansionTile)
class _CollapsibleCommentaryGroup extends StatefulWidget {
  final CommentaryGroup group;
  final bool isExpanded;
  final double fontSize;
  final Function(TextBookTab) openBookCallback;
  final bool removeNikud;
  final bool removePunctuation;
  final bool showSearch;
  final ValueListenable<String> searchQueryListenable;
  final ValueListenable<int> currentSearchIndexListenable;
  final ValueListenable<int> totalSearchResultsListenable;
  final int Function(Link) getItemSearchIndex;
  final void Function(Link, int) updateSearchResultsCount;
  final Map<String, GlobalKey> itemKeys;
  final String Function(Link) getLinkKey;
  final String indexesKey;
  final ValueListenable<String?> savedSelectedTextListenable;
  final ValueListenable<Link?> lastSelectedLinkListenable;
  final SelectionSyncController? selectionSyncController;
  final Object selectionOwner;
  final int selectionRevision;
  final void Function(bool) onExpansionChanged;
  final void Function(Link link, String text) onLinkSelected;
  final VoidCallback onLinkSelectionCleared;

  const _CollapsibleCommentaryGroup({
    super.key,
    required this.group,
    required this.isExpanded,
    required this.fontSize,
    required this.openBookCallback,
    required this.removeNikud,
    required this.removePunctuation,
    required this.showSearch,
    required this.searchQueryListenable,
    required this.currentSearchIndexListenable,
    required this.totalSearchResultsListenable,
    required this.getItemSearchIndex,
    required this.updateSearchResultsCount,
    required this.itemKeys,
    required this.getLinkKey,
    required this.indexesKey,
    required this.savedSelectedTextListenable,
    required this.lastSelectedLinkListenable,
    required this.selectionSyncController,
    required this.selectionOwner,
    required this.selectionRevision,
    required this.onExpansionChanged,
    required this.onLinkSelected,
    required this.onLinkSelectionCleared,
  });

  @override
  State<_CollapsibleCommentaryGroup> createState() =>
      _CollapsibleCommentaryGroupState();
}

class _CollapsibleCommentaryGroupState
    extends State<_CollapsibleCommentaryGroup> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.isExpanded;
  }

  @override
  void didUpdateWidget(_CollapsibleCommentaryGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isExpanded != widget.isExpanded) {
      _isExpanded = widget.isExpanded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // כותרת הקבוצה - ניתנת ללחיצה להרחבה/כיווץ
        InkWell(
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
            widget.onExpansionChanged(_isExpanded);
          },
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: _isExpanded ? -0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_left,
                    size: 20,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: BlocBuilder<SettingsBloc, SettingsState>(
                    builder: (context, settingsState) {
                      String displayTitle = widget.group.bookTitle;
                      if (settingsState.replaceHolyNames) {
                        displayTitle = utils.replaceHolyNames(displayTitle);
                      }
                      return Text(
                        displayTitle,
                        style: TextStyle(
                          fontSize: widget.fontSize * 0.85,
                          fontWeight: FontWeight.bold,
                          fontFamily: settingsState.commentatorsFontFamily,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        // תוכן המפרשים - מוצג רק כשמורחב
        if (_isExpanded)
          ...widget.group.links.map((link) {
            return SelectionArea(
              key: ValueKey(
                'commentary_${widget.getLinkKey(link)}_${widget.selectionRevision}',
              ),
              contextMenuBuilder: (context, selectableRegionState) {
                return const SizedBox.shrink();
              },
              onSelectionChanged: (selection) {
                if (selection != null && selection.plainText.isNotEmpty) {
                  widget.selectionSyncController
                      ?.activate(widget.selectionOwner);
                  widget.onLinkSelected(link, selection.plainText);
                } else if (selection == null ||
                    selection.plainText.trim().isEmpty) {
                  widget.selectionSyncController?.clear(widget.selectionOwner);
                  widget.onLinkSelectionCleared();
                }
              },
              child: ValueListenableBuilder<String?>(
                valueListenable: widget.savedSelectedTextListenable,
                child: Padding(
                  key: widget.itemKeys[widget.getLinkKey(link)],
                  padding: const EdgeInsets.only(
                      right: 32.0, left: 16.0, top: 8.0, bottom: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BlocBuilder<SettingsBloc, SettingsState>(
                        builder: (context, settingsState) {
                          return FutureBuilder<String>(
                            future: link.displayReference,
                            builder: (context, snapshot) {
                              String displayTitle = snapshot.data ??
                                  link.fallbackDisplayReference;
                              if (settingsState.replaceHolyNames) {
                                displayTitle =
                                    utils.replaceHolyNames(displayTitle);
                              }
                              return Text(
                                displayTitle,
                                style: TextStyle(
                                  fontSize: widget.fontSize * 0.75,
                                  fontWeight: FontWeight.normal,
                                  fontFamily:
                                      settingsState.commentatorsFontFamily,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.5),
                                ),
                                textDirection: TextDirection.rtl,
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 4),
                      AnimatedBuilder(
                        animation: Listenable.merge([
                          widget.searchQueryListenable,
                          widget.currentSearchIndexListenable,
                          widget.totalSearchResultsListenable,
                        ]),
                        builder: (context, _) {
                          final searchQuery = widget.showSearch
                              ? widget.searchQueryListenable.value
                              : '';
                          final currentSearchIndex = widget.showSearch
                              ? widget.getItemSearchIndex(link)
                              : 0;
                          return AppContextMenuRegion(
                            menuBuilder: (menuCtx, _) =>
                                ContextMenuUtils.buildCommentaryContextMenu(
                              context: menuCtx,
                              link: link,
                              openBookCallback: widget.openBookCallback,
                              fontSize: widget.fontSize,
                              savedSelectedText:
                                  widget.savedSelectedTextListenable.value,
                              onCopySelected: () =>
                                  ContextMenuUtils.copyFormattedText(
                                context: menuCtx,
                                savedSelectedText:
                                    widget.savedSelectedTextListenable.value,
                                fontSize: widget.fontSize,
                                link: widget.lastSelectedLinkListenable.value,
                              ),
                            ),
                            child: CommentaryContent(
                              key: ValueKey(
                                  '${link.index1}_${link.path2}_${link.index2}'),
                              link: link,
                              fontSize: widget.fontSize,
                              openBookCallback: widget.openBookCallback,
                              removeNikud: widget.removeNikud,
                              removePunctuation: widget.removePunctuation,
                              searchQuery: searchQuery,
                              currentSearchIndex: currentSearchIndex,
                              onSearchResultsCountChanged: widget.showSearch
                                  ? (count) => widget.updateSearchResultsCount(
                                        link,
                                        count,
                                      )
                                  : null,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                builder: (context, selectedText, child) => child!,
              ),
            );
          }),
        const Divider(height: 1),
      ],
    );
  }
}

class _CopyCommentaryIntent extends Intent {
  const _CopyCommentaryIntent();
}
