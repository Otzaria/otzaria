import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';
import 'package:otzaria/widgets/thin_divider.dart';

// Constants
const double _kMinQueryLength = 2;

class SearchFacetFiltering extends StatefulWidget {
  final SearchingTab tab;

  const SearchFacetFiltering({
    super.key,
    required this.tab,
  });

  @override
  State<SearchFacetFiltering> createState() => _SearchFacetFilteringState();
}

class _SearchFacetFilteringState extends State<SearchFacetFiltering>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final TextEditingController _filterQuery = TextEditingController();
  final Map<String, bool> _expansionState = {};

  // Canonical display order for top-level categories (overrides DB orderIndex).
  // Titles use ASCII double-quote; Hebrew gershayim (\u05F4 ״) is normalised
  // to ASCII " before lookup, so both DB titles and placeholder titles match.
  static const List<String> _orderedTopCategories = [
    'תנ"ך',
    'מדרש',
    'משנה',
    'תלמוד בבלי',
    'תלמוד ירושלמי',
    'תוספתא',
    'הלכה',
    'שו"ת',
    'קבלה',
    'סדר התפילה',
    'מחשבת ישראל',
    'חסידות',
    'ספרי מוסר',
    'מילונים וספרי יעץ',
    'לימוד יומי',
    'ספרות עזר',
    'בית שני',
  ];

  /// Returns a sort key for a top-level category.
  /// Categories listed in [_orderedTopCategories] get their index (0-based);
  /// all others are appended after with their DB order as a tie-breaker.
  int _getTopCategoryOrder(Category cat) {
    final normalized =
        cat.title.replaceAll('\u05F4', '"').replaceAll('\u05F3', "'");
    final idx = _orderedTopCategories.indexOf(normalized);
    return idx >= 0 ? idx : _orderedTopCategories.length + cat.order;
  }

  /// Normalises a DB orderIndex for display sorting.
  /// Negative values (e.g. -5 used for מפרשים) are remapped to the end
  /// (1000 + abs(value)) so they appear after the primary content.
  static int _normalizeOrder(int order) =>
      order >= 0 ? order : 1000 + order.abs();

  String _bookDedupKey(Book book) {
    final baseTitle = book.title.trim();
    final externalKey = book.externalLibraryId;
    if (externalKey != null && externalKey.isNotEmpty) {
      return 'ext:$externalKey';
    }
    final idKey = book.id;
    if (idKey != null) {
      return 'id:$idKey';
    }
    final categoryKey = book.categoryId?.toString() ?? book.categoryPath ?? '';
    return '$baseTitle|$categoryKey';
  }

  @override
  void dispose() {
    _filterQuery.dispose();
    super.dispose();
  }

  void _clearFilter() {
    _filterQuery.clear();
    context.read<SearchBloc>().add(ClearFilter());
  }

  @override
  void initState() {
    _filterQuery.text = context.read<SearchBloc>().state.filterQuery ?? '';
    super.initState();
  }

  void _onQueryChanged(String query) {
    if (query.length >= _kMinQueryLength) {
      context.read<SearchBloc>().add(UpdateFilterQuery(query));
    } else if (query.isEmpty) {
      context.read<SearchBloc>().add(ClearFilter());
    }
  }

  void _handleFacetToggle(BuildContext context, String facet) {
    final searchBloc = context.read<SearchBloc>();
    final state = searchBloc.state;
    if (state.currentFacets.contains(facet)) {
      searchBloc.add(RemoveFacet(facet));
    } else {
      searchBloc.add(AddFacet(facet));
    }
  }

  void _setFacet(BuildContext context, String facet) {
    context.read<SearchBloc>().add(SetFacet(
          facet,
          customSpacing: widget.tab.spacingValues,
          alternativeWords: widget.tab.alternativeWords,
          searchOptions: widget.tab.searchOptions,
        ));
  }

  Widget _buildSearchField() {
    return Container(
      height: 60, // Same height as the container on the right
      alignment: Alignment.center, // Vertically centers the RtlTextField
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: RtlTextField(
        controller: _filterQuery,
        decoration: InputDecoration(
          hintText: 'איתור ספר…',
          prefixIcon: const Icon(FluentIcons.filter_24_regular),
          suffixIcon: IconButton(
            onPressed: _clearFilter,
            icon: const Icon(FluentIcons.dismiss_24_regular),
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
        ),
        onChanged: _onQueryChanged,
      ),
    );
  }

  int _getBookFacetCount(Book book, Map<String, int> counts) {
    final categoryPath = FacetHelper.resolveCategoryPath(book);
    final bookFacet = FacetHelper.buildBookFacet(categoryPath, book.title);
    return counts[bookFacet] ?? counts['/${book.title}'] ?? 0;
  }

  Widget _buildBookTile(
    Book book,
    int count,
    int level,
    SearchState state, {
    String? categoryPath,
  }) {
    if (count == 0) {
      return const SizedBox.shrink();
    }

    // בניית facet בהתאם לפורמט האינדקס: /<topics>/<title>
    final resolvedCategoryPath =
        categoryPath ?? FacetHelper.resolveCategoryPath(book);
    final facet = FacetHelper.buildBookFacet(resolvedCategoryPath, book.title);
    final isSelected = state.currentFacets.contains(facet);
    return InkWell(
      onTap: () => HardwareKeyboard.instance.isControlPressed
          ? _handleFacetToggle(context, facet)
          : _setFacet(context, facet),
      onDoubleTap: () => _handleFacetToggle(context, facet),
      onLongPress: () => _handleFacetToggle(context, facet),
      child: Container(
        padding: EdgeInsets.only(
          right: 16.0 + (level * 12.0) + 24.0, // הזחה נוספת לספרים
          left: 16.0,
          top: 10.0,
          bottom: 10.0,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.3)
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
            Icon(
              FluentIcons.book_24_regular,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textStyle = const TextStyle(fontSize: 14);
                  final textPainter = TextPainter(
                    text: TextSpan(text: book.title, style: textStyle),
                    maxLines: 2,
                    textDirection: TextDirection.rtl,
                  )..layout(maxWidth: constraints.maxWidth);

                  final textWidget = Text(
                    book.title,
                    style: textStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  );

                  if (textPainter.didExceedMaxLines) {
                    return _IsolatedTooltip(
                        message: book.title, child: textWidget);
                  }
                  return textWidget;
                },
              ),
            ),
            // מספר התוצאות
            if (count != -1)
              Text(
                '($count)',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            if (count == -1)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBooksList(
    List<Book> books,
    SearchState state,
    Map<String, int> facetCounts,
  ) {
    // אם אין ספרים, הצג הודעה
    if (books.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('לא נמצאו ספרים'),
        ),
      );
    }

    if (state.isLoading && state.results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        final count = _getBookFacetCount(book, facetCounts);
        return _buildBookTile(book, count, 0, state);
      },
    );
  }

  Widget _buildCategoryTile(
    Category category,
    int count,
    int level,
    SearchState state,
    Map<String, int> facetCounts,
  ) {
    if (count == 0) return const SizedBox.shrink();
    final isSelected = state.currentFacets.contains(category.path);
    final isExpanded = _expansionState[category.path] ?? level == 0;

    void toggle() {
      setState(() {
        _expansionState[category.path] = !isExpanded;
      });
    }

    return Column(
      children: [
        // שורת הקטגוריה - סגנון ספרייה
        InkWell(
          onTap: () {
            // Ctrl+לחיצה = toggle, לחיצה רגילה = set
            if (HardwareKeyboard.instance.isControlPressed) {
              _handleFacetToggle(context, category.path);
            } else {
              _setFacet(context, category.path);
            }
          },
          onLongPress: () => _handleFacetToggle(context, category.path),
          child: Container(
            padding: EdgeInsets.only(
              right: 16.0 + (level * 12.0),
              left: 16.0,
              top: 12.0,
              bottom: 12.0,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.3)
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
                Icon(
                  isExpanded
                      ? FluentIcons.folder_open_24_regular
                      : FluentIcons.folder_24_regular,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final textStyle = TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      );
                      final textPainter = TextPainter(
                        text: TextSpan(
                          text: category.title,
                          style: textStyle,
                        ),
                        maxLines: 2,
                        textDirection: TextDirection.rtl,
                      )..layout(maxWidth: constraints.maxWidth);

                      final textWidget = Text(
                        category.title,
                        style: textStyle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      );

                      if (textPainter.didExceedMaxLines) {
                        return _IsolatedTooltip(
                            message: category.title, child: textWidget);
                      }
                      return textWidget;
                    },
                  ),
                ),
                // מספר התוצאות
                if (count != -1)
                  Text(
                    '($count)',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (count == -1)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                const SizedBox(width: 8),
                // כפתור החץ - מרחיב/מכווץ בלבד
                InkWell(
                  onTap: toggle,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Icon(
                      isExpanded
                          ? FluentIcons.chevron_up_24_regular
                          : FluentIcons.chevron_down_24_regular,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ילדים
        if (isExpanded)
          Column(
            children: _buildCategoryChildren(
              category,
              level,
              state,
              facetCounts,
            ),
          ),
      ],
    );
  }

  List<Widget> _buildCategoryChildren(
    Category category,
    int level,
    SearchState state,
    Map<String, int> facetCounts,
  ) {
    final List<Widget> children = [];

    final filteredSubCategories = category.subCategories.toList();
    if (category is Library) {
      filteredSubCategories.sort(
          (a, b) => _getTopCategoryOrder(a).compareTo(_getTopCategoryOrder(b)));
    } else {
      filteredSubCategories.sort((a, b) =>
          _normalizeOrder(a.order).compareTo(_normalizeOrder(b.order)));
    }

    // הוספת תת-קטגוריות
    for (final subCategory in filteredSubCategories) {
      final count = facetCounts[subCategory.path] ?? 0;
      children.add(
        _buildCategoryTile(subCategory, count, level + 1, state, facetCounts),
      );
    }

    // איחוד ספרים כפולים (למשל PDF וטקסט של אותו ספר) לאותה כותרת
    final uniqueBooksInCategory = <String, Book>{};
    for (final book in category.books) {
      uniqueBooksInCategory[_bookDedupKey(book)] ??= book;
    }

    final filteredBooks = uniqueBooksInCategory.values.toList();
    filteredBooks.sort((a, b) => a.order.compareTo(b.order));

    // הוספת ספרים
    for (final book in filteredBooks) {
      final categoryPath = category.path;
      final fullFacet = FacetHelper.buildBookFacet(categoryPath, book.title);
      final titleOnlyFacet = '/${book.title}';
      final count = facetCounts[fullFacet] ?? facetCounts[titleOnlyFacet] ?? 0;
      children.add(
        _buildBookTile(
          book,
          count,
          level + 1,
          state,
          categoryPath: category.path,
        ),
      );
    }

    return children;
  }

  List<Book> _getAllBooksFromLibrary(Category category) {
    final List<Book> allBooks = [];

    void collectBooks(Category cat) {
      // איחוד ספרים כפולים (למשל PDF וטקסט של אותו ספר) לאותה כותרת
      final uniqueBooksInCategory = <String, Book>{};
      for (final book in cat.books) {
        uniqueBooksInCategory[_bookDedupKey(book)] ??= book;
      }

      final sortedBooks = uniqueBooksInCategory.values.toList();
      sortedBooks.sort((a, b) => a.order.compareTo(b.order));
      allBooks.addAll(sortedBooks);

      final sortedSubCategories = cat.subCategories.toList();
      if (cat is Library) {
        sortedSubCategories.sort((a, b) =>
            _getTopCategoryOrder(a).compareTo(_getTopCategoryOrder(b)));
      } else {
        sortedSubCategories.sort((a, b) =>
            _normalizeOrder(a.order).compareTo(_normalizeOrder(b.order)));
      }

      for (final subCat in sortedSubCategories) {
        collectBooks(subCat);
      }
    }

    collectBooks(category);
    return allBooks;
  }

  Widget _buildFacetTree() {
    return BlocBuilder<LibraryBloc, LibraryState>(
      builder: (context, libraryState) {
        if (libraryState.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (libraryState.error != null) {
          return Center(child: Text('Error: ${libraryState.error}'));
        }

        return BlocBuilder<SearchBloc, SearchState>(
          builder: (context, searchState) {
            if (libraryState.library == null) {
              return const Center(child: Text('No library data available'));
            }

            final rootCategory = libraryState.library!;
            final facetCounts = searchState.facetCounts;

            // בדיקה אם יש סינון ספרים
            if (_filterQuery.text.length >= _kMinQueryLength) {
              // סינון ידנית מהספרייה
              final allBooks = _getAllBooksFromLibrary(rootCategory);
              final filtered = allBooks
                  .where((book) => book.title
                      .toLowerCase()
                      .contains(_filterQuery.text.toLowerCase()))
                  .toList();
              return _buildBooksList(filtered, searchState, facetCounts);
            }

            final rootCount = facetCounts[rootCategory.path] ?? 0;
            return SingleChildScrollView(
              key: PageStorageKey(widget.tab),
              child: _buildCategoryTile(
                rootCategory,
                rootCount,
                0,
                searchState,
                facetCounts,
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _buildSearchField(),
        const ThinDivider(), // Now perfectly aligned
        Expanded(
          child: _buildFacetTree(),
        ),
      ],
    );
  }
}

class _IsolatedTooltip extends StatefulWidget {
  final String message;
  final Widget child;

  const _IsolatedTooltip({
    required this.message,
    required this.child,
  });

  @override
  State<_IsolatedTooltip> createState() => _IsolatedTooltipState();
}

class _IsolatedTooltipState extends State<_IsolatedTooltip> {
  bool _showTooltip = false;
  Timer? _timer;
  final GlobalKey<TooltipState> _tooltipKey = GlobalKey<TooltipState>();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        _timer?.cancel();
        _timer = Timer(const Duration(milliseconds: 500), () {
          if (mounted) {
            setState(() => _showTooltip = true);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _tooltipKey.currentState?.ensureTooltipVisible();
            });
          }
        });
      },
      onExit: (_) {
        _timer?.cancel();
        if (_showTooltip && mounted) {
          setState(() => _showTooltip = false);
        }
      },
      child: _showTooltip
          ? Tooltip(
              key: _tooltipKey,
              message: widget.message,
              triggerMode: TooltipTriggerMode.manual,
              child: widget.child,
            )
          : widget.child,
    );
  }
}
