import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart' as ctx;
import 'package:otzaria/constants/fonts.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/commentary_content.dart';
import 'package:otzaria/widgets/progressive_scrolling.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/utils/context_menu_utils.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';

/// מייצג קבוצת קטעי פירוש רצופים מאותו ספר
class CommentaryGroup {
  final String bookTitle;
  final List<Link> links;

  CommentaryGroup({required this.bookTitle, required this.links});
}

/// מקבץ רשימת קישורים לקבוצות לפי שם הספר (רק קטעים רצופים)
List<CommentaryGroup> _groupConsecutiveLinks(List<Link> links) {
  if (links.isEmpty) return [];

  final groups = <CommentaryGroup>[];
  String? currentTitle;
  List<Link> currentGroup = [];

  for (final link in links) {
    final title = utils.getTitleFromPath(link.path2);

    if (currentTitle == null || currentTitle != title) {
      // ספר חדש - שומר את הקבוצה הקודמת ומתחיל קבוצה חדשה
      if (currentGroup.isNotEmpty) {
        groups.add(CommentaryGroup(
          bookTitle: currentTitle!,
          links: List.from(currentGroup),
        ));
      }
      currentTitle = title;
      currentGroup = [link];
    } else {
      // אותו ספר - מוסיף לקבוצה הנוכחית
      currentGroup.add(link);
    }
  }

  // מוסיף את הקבוצה האחרונה
  if (currentGroup.isNotEmpty) {
    groups.add(CommentaryGroup(
      bookTitle: currentTitle!,
      links: List.from(currentGroup),
    ));
  }

  return groups;
}

class CommentaryListBase extends StatefulWidget {
  final Function(TextBookTab) openBookCallback;
  final double fontSize;
  final List<int>? indexes;
  final bool showSearch;
  final VoidCallback? onClosePane;
  final bool shrinkWrap;
  final ItemPositionsListener? itemPositionsListener;
  final VoidCallback? onOpenCommentatorsFilter;

  const CommentaryListBase({
    super.key,
    required this.openBookCallback,
    required this.fontSize,
    this.indexes,
    required this.showSearch,
    this.onClosePane,
    this.shrinkWrap = true,
    this.itemPositionsListener,
    this.onOpenCommentatorsFilter,
  });

  @override
  State<CommentaryListBase> createState() => CommentaryListBaseState();
}

class CommentaryListBaseState extends State<CommentaryListBase> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final ScrollOffsetController scrollController = ScrollOffsetController();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final Map<String, GlobalKey> _itemKeys = {};
  int _currentSearchIndex = 0;
  int _totalSearchResults = 0;
  final Map<String, int> _searchResultsPerLink = {};
  int _lastScrollIndex = 0; // שומר את מיקום הגלילה האחרון
  bool _allExpanded = true; // מצב גלובלי של פתיחה/סגירה של כל המפרשים
  final Map<String, bool> _expansionStates =
      {}; // מעקב אחרי מצב כל ExpansionTile
  final Map<String, ExpansibleController> _controllers =
      {}; // controllers לכל ExpansionTile
  String? _savedSelectedText; // טקסט נבחר לתפריט הקשר

  String _getLinkKey(Link link) => '${link.path2}_${link.index2}';

  // רשימה של כל ה-links לפי סדר הופעתם (נבנית מחדש בכל build)
  List<Link> _orderedLinks = [];

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
        final relativeIndex = _currentSearchIndex - cumulativeIndex;
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
      // שומר את האינדקס של הפריט הראשון הנראה
      _lastScrollIndex = positions.first.index;
    }
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_updateLastScrollIndex);
    _searchController.dispose();
    // מנקה את כל ה-controllers
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _scrollToSearchResult() {
    if (_totalSearchResults == 0 ||
        _orderedLinks.isEmpty ||
        !_itemScrollController.isAttached) {
      return;
    }

    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;

    int cumulativeIndex = 0;
    Link? targetLink;

    // 1. מוצא את ה-link שמכיל את תוצאת החיפוש הנוכחית
    for (final link in _orderedLinks) {
      final linkKey = _getLinkKey(link);
      final itemResults = _searchResultsPerLink[linkKey] ?? 0;
      if (_currentSearchIndex < cumulativeIndex + itemResults) {
        targetLink = link;
        break;
      }
      cumulativeIndex += itemResults;
    }

    if (targetLink == null) return;

    // 2. מוצא את ה-group שמכיל את ה-link
    final groups = _groupConsecutiveLinks(_orderedLinks);
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

    if (targetGroupIndex == -1 || targetGroup == null) return;

    // 3. מבטיח שה-ExpansionTile של הקבוצה פתוח
    final currentIndexes = widget.indexes ??
        (state.selectedIndex != null
            ? [state.selectedIndex!]
            : state.visibleIndices);
    final indexesKey = currentIndexes.join(',');
    final groupKey = '${targetGroup.bookTitle}_$indexesKey';

    final bool isCurrentlyExpanded = _expansionStates[groupKey] ?? _allExpanded;

    // אם צריך לפתוח, פותח ומחכה לאנימציה
    if (!isCurrentlyExpanded) {
      setState(() {
        _expansionStates[groupKey] = true;
        _controllers[groupKey]?.expand();
      });
    }

    // 4. ביצוע הגלילה בשני שלבים בתוך Callback
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // המתנה לסיום אנימציית הפתיחה אם הייתה
      if (!isCurrentlyExpanded) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (!mounted) return;
      }

      // שלב א': גלילה גסה לקבוצה (כותרת הספר) כדי להבטיח שהפריטים ירונדרו
      if (_itemScrollController.isAttached) {
        _itemScrollController.scrollTo(
          index: targetGroupIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0.05, // מביא את הכותרת לראש העמוד
        );
      }

      // המתנה לסיום הגלילה הגסה ורינדור הפריטים
      await Future.delayed(const Duration(milliseconds: 350));
      // תיקון שגיאת לינט: בדיקת mounted אחרי await
      if (!mounted) return;

      // שלב ב': גלילה עדינה לפריט הספציפי באמצעות חישוב אופסט ידני
      final linkKey = _getLinkKey(targetLink!);
      final itemKey = _itemKeys[linkKey];
      final BuildContext? itemContext = itemKey?.currentContext;

      // תיקון שגיאת לינט: בדיקה ש-itemContext עצמו mounted
      if (itemContext != null && itemContext.mounted) {
        try {
          // מציאת ה-RenderObject של הפריט
          final RenderObject? itemRenderObj = itemContext.findRenderObject();
          if (itemRenderObj is! RenderBox) return;
          final RenderBox itemBox = itemRenderObj;

          // תיקון שגיאת לינט: שימוש במשתנה שאינו nullable
          final ScrollableState scrollable = Scrollable.of(itemContext);

          // תיקון שגיאת לינט: בדיקת mounted ל-scrollable לפני גישה ל-context שלו
          if (!scrollable.mounted) return;

          final RenderObject? viewportRenderObj =
              scrollable.context.findRenderObject();
          if (viewportRenderObj is! RenderBox) return;
          final RenderBox viewportBox = viewportRenderObj;

          // חישוב המיקום של הפריט ביחס ל-Viewport של הרשימה
          final Offset itemOffset =
              itemBox.localToGlobal(Offset.zero, ancestor: viewportBox);

          // אנו רוצים שהפריט יהיה בערך ב-10% מהחלק העליון של הרשימה
          final double targetY = viewportBox.size.height * 0.1;
          final double currentY = itemOffset.dy;

          // חישוב הדלתא לגלילה
          final double scrollDelta = currentY - targetY;

          // אם הדלתא משמעותית, נבצע גלילה מתקנת
          if (scrollDelta.abs() > 10) {
            scrollController.animateScroll(
                offset: scrollDelta, // גלילה יחסית
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
    if (mounted) {
      setState(() {
        _searchResultsPerLink[_getLinkKey(link)] = count;
        _totalSearchResults =
            _searchResultsPerLink.values.fold(0, (sum, count) => sum + count);
        if (_currentSearchIndex >= _totalSearchResults &&
            _totalSearchResults > 0) {
          _currentSearchIndex = _totalSearchResults - 1;
        }
      });
    }
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
    final groupKey = '${group.bookTitle}_$indexesKey';

    // אם אין מצב שמור עבור הקבוצה הזו, משתמש במצב הגלובלי
    if (!_expansionStates.containsKey(groupKey)) {
      _expansionStates[groupKey] = _allExpanded;
    }

    // יוצר controller אם לא קיים
    if (!_controllers.containsKey(groupKey)) {
      _controllers[groupKey] = ExpansibleController();
    }

    final isExpanded = _expansionStates[groupKey] ?? _allExpanded;

    return ExpansionTile(
      key: PageStorageKey(groupKey),
      controller: _controllers[groupKey],
      maintainState: true,
      initiallyExpanded: isExpanded,
      onExpansionChanged: (isExpanded) {
        _expansionStates[groupKey] = isExpanded;
        // בודק אם כל המפרשים פתוחים או סגורים ומעדכן את המצב הגלובלי
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _updateGlobalExpansionState();
            });
          }
        });
      },
      backgroundColor: Colors.transparent,
      collapsedBackgroundColor: Colors.transparent,
      title: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, settingsState) {
          String displayTitle = group.bookTitle;
          if (settingsState.replaceHolyNames) {
            displayTitle = utils.replaceHolyNames(displayTitle);
          }
          return Text(
            displayTitle,
            style: TextStyle(
              fontSize: widget.fontSize * 0.85,
              fontWeight: FontWeight.bold,
              fontFamily: AppFonts.defaultFont,
            ),
          );
        },
      ),
      children: group.links.map((link) {
        return ctx.ContextMenuRegion(
          contextMenu: ContextMenuUtils.buildCommentaryContextMenu(
            context: context,
            link: link,
            openBookCallback: widget.openBookCallback,
            fontSize: widget.fontSize,
            savedSelectedText: _savedSelectedText,
            onCopySelected: () => ContextMenuUtils.copyFormattedText(
              context: context,
              savedSelectedText: _savedSelectedText,
              fontSize: widget.fontSize,
            ),
          ),
          child: ListTile(
            key: _itemKeys[_getLinkKey(link)],
            contentPadding: const EdgeInsets.only(right: 32.0, left: 16.0),
            title: BlocBuilder<SettingsBloc, SettingsState>(
              builder: (context, settingsState) {
                String displayTitle = link.heRef;
                if (settingsState.replaceHolyNames) {
                  displayTitle = utils.replaceHolyNames(displayTitle);
                }

                return Text(
                  displayTitle,
                  style: TextStyle(
                    fontSize: widget.fontSize * 0.75,
                    fontWeight: FontWeight.normal,
                    fontFamily: AppFonts.defaultFont,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
                );
              },
            ),
            subtitle: CommentaryContent(
              key: ValueKey('${link.path2}_${link.index2}_$indexesKey'),
              link: link,
              fontSize: widget.fontSize,
              openBookCallback: widget.openBookCallback,
              removeNikud: state.removeNikud,
              searchQuery: widget.showSearch ? _searchQuery : '',
              currentSearchIndex:
                  widget.showSearch ? _getItemSearchIndex(link) : 0,
              onSearchResultsCountChanged: widget.showSearch
                  ? (count) => _updateSearchResultsCount(link, count)
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TextBookBloc, TextBookState>(builder: (context, state) {
      if (state is! TextBookLoaded) return const Center();

      Widget buildList() {
        return Builder(
          builder: (context) {
            // בודק מראש אם יש קישורים רלוונטיים לאינדקסים הנוכחיים
            final currentIndexes = widget.indexes ??
                (state.selectedIndex != null
                    ? [state.selectedIndex!]
                    : state.visibleIndices);

            // בדיקה אם יש בכלל קישורים לאינדקסים הנוכחיים (ללא סינון מפרשים)
            final hasAnyCommentaryLinks = state.links.any((link) =>
                currentIndexes.contains(link.index1 - 1) &&
                (link.connectionType == "commentary" ||
                    link.connectionType == "targum"));

            // סינון מהיר של קישורים רלוונטיים
            final hasRelevantLinks = state.links.any((link) =>
                currentIndexes.contains(link.index1 - 1) &&
                state.activeCommentators
                    .contains(utils.getTitleFromPath(link.path2)));

            // אם אין קישורים רלוונטיים, לא מציג כלום
            if (!hasRelevantLinks) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        hasAnyCommentaryLinks
                            ? 'לא נבחרו מפרשים להצגה'
                            : 'לא נמצאו מפרשים לקטע הנבחר',
                        style: TextStyle(
                          fontSize: widget.fontSize * 0.7,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (hasAnyCommentaryLinks &&
                          widget.onOpenCommentatorsFilter != null) ...[
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: widget.onOpenCommentatorsFilter,
                          icon: const Icon(FluentIcons.apps_list_24_regular),
                          label: const Text('בחר מפרשים'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }

            return FutureBuilder(
              future: getLinksforIndexs(
                  indexes: currentIndexes,
                  links: state.links,
                  commentatorsToShow: state.activeCommentators),
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
                final currentLinkKeys = data.map((l) => _getLinkKey(l)).toSet();
                _itemKeys.removeWhere(
                    (key, value) => !currentLinkKeys.contains(key));
                for (final key in currentLinkKeys) {
                  _itemKeys.putIfAbsent(key, () => GlobalKey());
                }

                // מקבץ את הקישורים לקבוצות רצופות
                final groups = _groupConsecutiveLinks(data);

                // יצירת מפתח ייחודי לאינדקסים הנוכחיים
                final indexesKey = currentIndexes.join(',');

                return ProgressiveScroll(
                  scrollController: scrollController,
                  maxSpeed: 10000.0,
                  curve: 10.0,
                  accelerationFactor: 5,
                  child: ScrollablePositionedList.builder(
                    itemScrollController: _itemScrollController,
                    itemPositionsListener: _itemPositionsListener,
                    initialScrollIndex:
                        _lastScrollIndex.clamp(0, groups.length - 1),
                    key: PageStorageKey(
                        'commentary_${indexesKey}_${state.activeCommentators.hashCode}'),
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
            );
          },
        );
      }

      if (widget.showSearch) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: RtlTextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'חפש בתוך המפרשים המוצגים...',
                        prefixIcon: const Icon(FluentIcons.search_24_regular),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_totalSearchResults > 1) ...[
                                    Text(
                                      '${_currentSearchIndex + 1}/$_totalSearchResults',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(
                                          FluentIcons.chevron_up_24_regular),
                                      iconSize: 20,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 24,
                                        minHeight: 24,
                                      ),
                                      onPressed: _currentSearchIndex > 0
                                          ? () {
                                              setState(() {
                                                _currentSearchIndex--;
                                              });
                                              _scrollToSearchResult();
                                            }
                                          : null,
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                          FluentIcons.chevron_down_24_regular),
                                      iconSize: 20,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 24,
                                        minHeight: 24,
                                      ),
                                      onPressed: _currentSearchIndex <
                                              _totalSearchResults - 1
                                          ? () {
                                              setState(() {
                                                _currentSearchIndex++;
                                              });
                                              _scrollToSearchResult();
                                            }
                                          : null,
                                    ),
                                  ],
                                  IconButton(
                                    icon: const Icon(
                                        FluentIcons.dismiss_24_regular),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _searchQuery = '';
                                        _currentSearchIndex = 0;
                                        _totalSearchResults = 0;
                                        _searchResultsPerLink.clear();
                                      });
                                    },
                                  ),
                                ],
                              )
                            : null,
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                          _currentSearchIndex = 0;
                          if (value.isEmpty) {
                            _totalSearchResults = 0;
                            _searchResultsPerLink.clear();
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // כפתור סגירה/פתיחה גלובלית של כל המפרשים - מוצג רק אם יש מפרשים פעילים
                  if (state.activeCommentators.isNotEmpty)
                    IconButton(
                      icon: Icon(
                        _allExpanded
                            ? FluentIcons.arrow_collapse_all_24_regular
                            : FluentIcons.arrow_expand_all_24_regular,
                      ),
                      tooltip: _allExpanded
                          ? 'סגור את כל המפרשים'
                          : 'פתח את כל המפרשים',
                      onPressed: () {
                        setState(() {
                          _allExpanded = !_allExpanded;
                          // מעדכן את כל המצבים של ה-ExpansionTiles
                          for (var key in _expansionStates.keys) {
                            _expansionStates[key] = _allExpanded;
                          }
                          // משתמש ב-controllers לפתיחה/סגירה
                          for (var controller in _controllers.values) {
                            if (_allExpanded) {
                              controller.expand();
                            } else {
                              controller.collapse();
                            }
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
            if (state.activeCommentators.isNotEmpty)
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
                      foregroundColor: Theme.of(context).colorScheme.primary,
                    ),
                    icon: Icon(
                      _allExpanded
                          ? FluentIcons.arrow_collapse_all_24_regular
                          : FluentIcons.arrow_expand_all_24_regular,
                    ),
                    tooltip: _allExpanded
                        ? 'סגור את כל המפרשים'
                        : 'פתח את כל המפרשים',
                    onPressed: () {
                      setState(() {
                        _allExpanded = !_allExpanded;
                        // מעדכן את כל המצבים של ה-ExpansionTiles
                        for (var key in _expansionStates.keys) {
                          _expansionStates[key] = _allExpanded;
                        }
                        // משתמש ב-controllers לפתיחה/סגירה
                        for (var controller in _controllers.values) {
                          if (_allExpanded) {
                            controller.expand();
                          } else {
                            controller.collapse();
                          }
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
