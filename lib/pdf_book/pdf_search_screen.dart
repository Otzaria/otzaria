// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:otzaria/utils/ref_helper.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/search_pane_base.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/search/book_facet.dart';
import 'package:search_engine/search_engine.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/models/books.dart';

//
// Simple Text Search View
//
class PdfBookSearchView extends StatefulWidget {
  const PdfBookSearchView({
    required this.textSearcher,
    required this.searchController,
    required this.focusNode,
    this.outline,
    this.bookTitle,
    this.bookTopics,
    this.initialSearchText = '',
    this.initialSearchOptions = const {},
    this.initialAlternativeWords = const {},
    this.initialSpacingValues = const {},
    this.initialSearchMode = SearchMode.exact,
    this.onSearchResultNavigated,
    super.key,
  });

  final PdfTextSearcher textSearcher;
  final TextEditingController searchController;
  final FocusNode focusNode;
  final List<PdfOutlineNode>? outline;
  final String? bookTitle;
  final String? bookTopics;
  final String initialSearchText;
  final Map<String, Map<String, bool>> initialSearchOptions;
  final Map<int, List<String>> initialAlternativeWords;
  final Map<String, String> initialSpacingValues;
  final SearchMode initialSearchMode;
  final VoidCallback? onSearchResultNavigated;

  @override
  State<PdfBookSearchView> createState() => _PdfBookSearchViewState();
}

class _PdfBookSearchViewState extends State<PdfBookSearchView> {
  final SearchRepository _searchRepository = SearchRepository();
  final scrollController = ScrollController();
  bool _isSearching = false;
  List<SearchResult> _searchResults = [];
  String? _bookPath;
  final _pageTitles = <int, String>{};
  Map<String, Map<String, bool>> _searchOptions = {};
  Map<int, List<String>> _alternativeWords = {};
  Map<String, String> _spacingValues = {};
  SearchMode _searchMode = SearchMode.exact;

  @override
  void initState() {
    super.initState();
    _searchOptions = widget.initialSearchOptions;
    _alternativeWords = widget.initialAlternativeWords;
    _spacingValues = widget.initialSpacingValues;
    _searchMode = widget.initialSearchMode;
    widget.searchController.addListener(_searchTextUpdated);
    _initializeBookPath();
  }

  Future<void> _initializeBookPath() async {
    final title = widget.bookTitle?.trim();
    if (title == null || title.isEmpty) return;

    debugPrint('📚 PdfSearch: book.title = $title');

    final topics = await BookFacet.resolveTopics(
      title: title,
      initialTopics: widget.bookTopics ?? '',
      type: PdfBook,
    );

    if (!mounted) return;

    debugPrint('📚 PdfSearch: final topics = "$topics"');
    _bookPath = BookFacet.buildFacetPath(title: title, topics: topics);
    debugPrint('📚 PdfSearch: _bookPath = $_bookPath');

    // If the controller already has text, start the search
    if (widget.searchController.text.isNotEmpty && mounted) {
      _searchTextUpdated();
    }
  }

  @override
  void dispose() {
    scrollController.dispose();
    widget.searchController.removeListener(_searchTextUpdated);
    super.dispose();
  }

  Future<void> _searchTextUpdated() async {
    final query = widget.searchController.text.trim();
    if (query.isEmpty || _bookPath == null) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final results = await _searchRepository.searchTexts(
        query,
        [_bookPath!],
        1000,
        searchOptions: _searchOptions,
        alternativeWords: _alternativeWords,
        customSpacing: _spacingValues,
        fuzzy: _searchMode == SearchMode.fuzzy,
      );

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      debugPrint('PDF Search error: $e');
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Group results by page
    final Map<int, List<SearchResult>> resultsByPage = {};
    for (final result in _searchResults) {
      final pageNumber = result.segment.toInt() + 1;
      resultsByPage.putIfAbsent(pageNumber, () => []).add(result);
    }

    // Create flat list with headers
    final List<dynamic> items = [];
    for (final entry in resultsByPage.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key))) {
      items.add(entry.key); // Page number as header
      items.addAll(entry.value); // Results for this page

      // Load page title if not cached
      if (!_pageTitles.containsKey(entry.key)) {
        () async {
          final title = await refFromPageNumber(
              entry.key, widget.outline, widget.bookTitle);
          if (mounted) {
            setState(() {
              _pageTitles[entry.key] = title;
            });
          }
        }();
      }
    }

    return SearchPaneBase(
      searchController: widget.searchController,
      focusNode: widget.focusNode,
      progressWidget:
          _isSearching ? const LinearProgressIndicator(minHeight: 4) : null,
      resultCountString: _searchResults.isNotEmpty
          ? 'נמצאו ${_searchResults.length} תוצאות'
          : null,
      resultsWidget: ListView.builder(
        key: Key(widget.searchController.text),
        controller: scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];

          if (item is int) {
            // Page header
            return BlocBuilder<SettingsBloc, SettingsState>(
              builder: (context, settingsState) {
                String text = _pageTitles[item]?.isNotEmpty == true
                    ? _pageTitles[item]!
                    : 'עמוד $item';
                if (settingsState.replaceHolyNames) {
                  text = utils.replaceHolyNames(text);
                }
                return Padding(
                  padding: const EdgeInsets.only(
                    top: 8.0,
                    bottom: 8.0,
                    right: 20.0,
                    left: 20.0,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.picture_as_pdf,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          text,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          } else {
            // Search result
            final result = item as SearchResult;
            return SearchResultTile(
              key: ValueKey('${result.segment}_${result.text.hashCode}'),
              result: result,
              onTap: () async {
                // Navigate to the page
                final pageNumber = result.segment.toInt() + 1;
                final controller = widget.textSearcher.controller;
                if (controller != null) {
                  await controller.goToPage(pageNumber: pageNumber);
                }
                widget.onSearchResultNavigated?.call();
              },
              height: 50,
              query: widget.searchController.text,
            );
          }
        },
      ),
      isNoResults: widget.searchController.text.isNotEmpty &&
          _searchResults.isEmpty &&
          !_isSearching,
      onSearchTextChanged: (_) => _searchTextUpdated(),
      resetSearchCallback: () {
        setState(() {
          _searchResults = [];
          _searchOptions = {};
          _alternativeWords = {};
          _spacingValues = {};
          _searchMode = SearchMode.exact;
        });
      },
      hintText: 'חפש כאן..',
      onAdvancedSearch: () {
        // Create a temporary SearchingTab to hold the state
        final tempTab = SearchingTab("חיפוש", widget.searchController.text);
        tempTab.searchOptions.addAll(_searchOptions);
        tempTab.alternativeWords.addAll(_alternativeWords);
        tempTab.spacingValues.addAll(_spacingValues);
        tempTab.searchBloc.add(SetSearchMode(_searchMode));

        showDialog(
          context: context,
          builder: (context) => SearchDialog(
            existingTab: tempTab,
            bookTitle: widget.bookTitle,
            onSearch: (query, searchOptions, alternativeWords, spacingValues,
                searchMode) {
              widget.searchController.text = query;
              setState(() {
                _searchOptions = searchOptions;
                _alternativeWords = alternativeWords;
                _spacingValues = spacingValues;
                _searchMode = searchMode;
              });
              _searchTextUpdated();
            },
          ),
        );
      },
    );
  }
}

class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    required this.result,
    required this.onTap,
    required this.height,
    required this.query,
    super.key,
  });

  final SearchResult result;
  final void Function() onTap;
  final double height;
  final String query;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        final text =
            _createHighlightedText(result.text, query, settingsState, context);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.3),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              hoverColor: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.3),
              splashColor: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.4),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: text,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _createHighlightedText(
    String text,
    String query,
    SettingsState settingsState,
    BuildContext context,
  ) {
    String displayText = text;
    if (settingsState.replaceHolyNames) {
      displayText = utils.replaceHolyNames(displayText);
    }

    if (query.isEmpty) {
      return Text(
        displayText,
        style: TextStyle(
          fontSize: 16,
          fontFamily: settingsState.fontFamily,
          color: Theme.of(context).colorScheme.onSurface,
          height: 1.5,
        ),
      );
    }

    final searchTerms = query.trim().split(RegExp(r'\s+'));
    final highlightRegex = RegExp(
      searchTerms.map(RegExp.escape).join('|'),
      caseSensitive: false,
    );

    final List<InlineSpan> spans = [];
    int currentPosition = 0;

    for (final match in highlightRegex.allMatches(displayText)) {
      if (match.start > currentPosition) {
        spans.add(TextSpan(
          text: displayText.substring(currentPosition, match.start),
        ));
      }
      spans.add(TextSpan(
        text: match.group(0),
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 18,
          color: Color(0xFFD32F2F),
        ),
      ));
      currentPosition = match.end;
    }

    if (currentPosition < displayText.length) {
      spans.add(TextSpan(
        text: displayText.substring(currentPosition),
      ));
    }

    return Text.rich(
      TextSpan(
        children: spans,
        style: TextStyle(
          fontSize: 16,
          fontFamily: settingsState.fontFamily,
          color: Theme.of(context).colorScheme.onSurface,
          height: 1.5,
        ),
      ),
    );
  }
}
