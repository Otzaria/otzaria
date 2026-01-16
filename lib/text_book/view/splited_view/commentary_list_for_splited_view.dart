import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/view/combined_view/commentary_content.dart';
import 'package:otzaria/widgets/progressive_scrolling.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';
import 'package:flutter/foundation.dart';

class CommentaryList extends StatefulWidget {
  final Function(TextBookTab) openBookCallback;
  final double fontSize;
  final int index;
  final bool showSplitView;
  final VoidCallback? onClosePane;

  const CommentaryList({
    super.key,
    required this.openBookCallback,
    required this.fontSize,
    required this.index,
    required this.showSplitView,
    this.onClosePane,
  });

  @override
  State<CommentaryList> createState() => _CommentaryListState();
}

class _CommentaryListState extends State<CommentaryList> {
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier<String>('');

  final ScrollOffsetController scrollController = ScrollOffsetController();
  final ValueNotifier<int> _currentSearchIndexNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _totalSearchResultsNotifier = ValueNotifier<int>(0);
  final Map<int, int> _searchResultsPerItem = {};

  int _getItemSearchIndex(int itemIndex) {
    int cumulativeIndex = 0;
    for (int i = 0; i < itemIndex; i++) {
      cumulativeIndex += _searchResultsPerItem[i] ?? 0;
    }

    final itemResults = _searchResultsPerItem[itemIndex] ?? 0;
    if (itemResults == 0) return -1;

    final relativeIndex = _currentSearchIndexNotifier.value - cumulativeIndex;
    return (relativeIndex >= 0 && relativeIndex < itemResults)
        ? relativeIndex
        : -1;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchQueryNotifier.dispose();
    _currentSearchIndexNotifier.dispose();
    _totalSearchResultsNotifier.dispose();
    super.dispose();
  }

  void _scrollToSearchResult() {
    if (_totalSearchResultsNotifier.value == 0) return;

    // מחשבים באיזה פריט נמצאת התוצאה הנוכחית
    int cumulativeIndex = 0;
    int targetItemIndex = 0;

    for (int i = 0; i < _searchResultsPerItem.length; i++) {
      final itemResults = _searchResultsPerItem[i] ?? 0;
      if (_currentSearchIndexNotifier.value < cumulativeIndex + itemResults) {
        targetItemIndex = i;
        break;
      }
      cumulativeIndex += itemResults;
    }

    // גוללים לפריט הרלוונטי
    try {
      scrollController.animateScroll(
        offset: targetItemIndex * 100.0, // הערכה גסה של גובה פריט
        duration: const Duration(milliseconds: 300),
      );
    } catch (e) {
      // אם יש בעיה עם הגלילה, נתעלם מהשגיאה
    }
  }

  void _updateSearchResultsCount(int itemIndex, int count) {
    if (mounted) {
      _searchResultsPerItem[itemIndex] = count;
      _totalSearchResultsNotifier.value =
          _searchResultsPerItem.values.fold(0, (sum, count) => sum + count);
      if (_currentSearchIndexNotifier.value >=
              _totalSearchResultsNotifier.value &&
          _totalSearchResultsNotifier.value > 0) {
        _currentSearchIndexNotifier.value =
            _totalSearchResultsNotifier.value - 1;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TextBookBloc, TextBookState>(
        buildWhen: (previous, current) {
      if (previous is! TextBookLoaded || current is! TextBookLoaded) {
        return true;
      }
      return !listEquals(
              previous.activeCommentators, current.activeCommentators) ||
          previous.links != current.links ||
          !listEquals(previous.visibleIndices, current.visibleIndices) ||
          previous.selectedIndex != current.selectedIndex ||
          previous.fontSize != current.fontSize ||
          previous.removeNikud != current.removeNikud;
    }, builder: (context, state) {
      if (state is! TextBookLoaded) return const Center();
      final currentIndexes = state.selectedIndex != null
          ? [state.selectedIndex!]
          : state.visibleIndices;

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
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
                                  prefixIcon:
                                      const Icon(FluentIcons.search_24_regular),
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
                                                onPressed: currentIndex > 0
                                                    ? () {
                                                        _currentSearchIndexNotifier
                                                                .value =
                                                            currentIndex - 1;
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
                                                            currentIndex + 1;
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
                                                _searchQueryNotifier.value = '';
                                                _currentSearchIndexNotifier
                                                    .value = 0;
                                                _totalSearchResultsNotifier
                                                    .value = 0;
                                                _searchResultsPerItem.clear();
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
                                  if (_searchQueryNotifier.value != value) {
                                    _searchQueryNotifier.value = value;
                                    _currentSearchIndexNotifier.value = 0;
                                    _totalSearchResultsNotifier.value = 0;
                                    _searchResultsPerItem.clear();
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
            ),
          ),
          Expanded(
            child: FutureBuilder(
              future: getLinksforIndexs(
                  indexes: currentIndexes,
                  links: state.links,
                  commentatorsToShow: state.activeCommentators),
              builder: (context, thisLinksSnapshot) {
                if (!thisLinksSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (thisLinksSnapshot.data!.isEmpty) {
                  return const Center(child: Text("לא נמצאו מפרשים להצגה"));
                }

                // יצירת מפתח ייחודי לאינדקסים הנוכחיים
                final indexesKey = currentIndexes.join(',');

                return ProgressiveScroll(
                  scrollController: scrollController,
                  maxSpeed: 10000.0,
                  curve: 10.0,
                  accelerationFactor: 5,
                  child: ScrollablePositionedList.builder(
                    key: PageStorageKey(
                        '${thisLinksSnapshot.data![0].heRef}_$indexesKey'),
                    physics: const ClampingScrollPhysics(),
                    scrollOffsetController: scrollController,
                    shrinkWrap: true,
                    itemCount: thisLinksSnapshot.data!.length,
                    itemBuilder: (context, index1) => ListTile(
                      title: BlocBuilder<SettingsBloc, SettingsState>(
                        builder: (context, settingsState) {
                          String displayTitle =
                              thisLinksSnapshot.data![index1].heRef;
                          if (settingsState.replaceHolyNames) {
                            displayTitle = utils.replaceHolyNames(displayTitle);
                          }
                          return Text(displayTitle);
                        },
                      ),
                      subtitle: AnimatedBuilder(
                        animation: Listenable.merge([
                          _searchQueryNotifier,
                          _currentSearchIndexNotifier,
                          _totalSearchResultsNotifier,
                        ]),
                        builder: (context, _) {
                          return CommentaryContent(
                            key: ValueKey(
                                '${thisLinksSnapshot.data![index1].path2}_${thisLinksSnapshot.data![index1].index2}_$indexesKey'),
                            link: thisLinksSnapshot.data![index1],
                            fontSize: widget.fontSize,
                            openBookCallback: widget.openBookCallback,
                            removeNikud: state.removeNikud,
                            searchQuery: _searchQueryNotifier.value,
                            currentSearchIndex: _getItemSearchIndex(index1),
                            onSearchResultsCountChanged: (count) =>
                                _updateSearchResultsCount(index1, count),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    });
  }
}
