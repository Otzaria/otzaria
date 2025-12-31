import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/settings_state.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/settings/settings_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/text_book/models/search_results.dart';
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

class _GroupedResultItem {
  final String? header;
  final TextSearchResult? result;
  const _GroupedResultItem.header(this.header) : result = null;
  const _GroupedResultItem.result(this.result) : header = null;
  bool get isHeader => header != null;
}

class TextBookSearchView extends StatefulWidget {
  final String data;
  final ItemScrollController scrollControler;
  final FocusNode focusNode;
  final void Function() closeLeftPaneCallback;
  final String initialQuery;
  final Map<String, Map<String, bool>> initialSearchOptions;
  final Map<int, List<String>> initialAlternativeWords;
  final Map<String, String> initialSpacingValues;
  final SearchMode initialSearchMode;

  const TextBookSearchView({
    super.key,
    required this.data,
    required this.scrollControler,
    required this.focusNode,
    required this.closeLeftPaneCallback,
    required this.initialQuery,
    this.initialSearchOptions = const {},
    this.initialAlternativeWords = const {},
    this.initialSpacingValues = const {},
    this.initialSearchMode = SearchMode.exact,
  });

  @override
  TextBookSearchViewState createState() => TextBookSearchViewState();
}

class TextBookSearchViewState extends State<TextBookSearchView>
    with AutomaticKeepAliveClientMixin<TextBookSearchView> {
  TextEditingController searchTextController = TextEditingController();
  final SearchRepository _searchRepository = SearchRepository();
  List<TextSearchResult> searchResults = [];
  late ItemScrollController scrollControler;
  bool _isSearching = false;
  List<String> _content = [];
  String? _bookPath;
  Map<String, Map<String, bool>> _searchOptions = {};
  Map<int, List<String>> _alternativeWords = {};
  Map<String, String> _spacingValues = {};
  SearchMode _searchMode = SearchMode.exact;

  @override
  void initState() {
    super.initState();
    _content = widget.data.split('\n');

    searchTextController.text = widget.initialQuery;
    _searchOptions = widget.initialSearchOptions;
    _alternativeWords = widget.initialAlternativeWords;
    _spacingValues = widget.initialSpacingValues;
    _searchMode = widget.initialSearchMode;

    scrollControler = widget.scrollControler;
    widget.focusNode.requestFocus();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeBookPath();
    });
  }

  Future<void> _initializeBookPath() async {
    final state = context.read<TextBookBloc>().state;
    if (state is TextBookLoaded) {
      final bookTitle = state.book.title;
      debugPrint('📚 TextBookSearch: book.title = $bookTitle');

      final topics = await BookFacet.resolveTopics(
        title: bookTitle,
        initialTopics: state.book.topics,
        type: TextBook,
      );

      if (!mounted) return;

      debugPrint('📚 TextBookSearch: final topics = "$topics"');
      _bookPath = BookFacet.buildFacetPath(title: bookTitle, topics: topics);
      debugPrint('📚 TextBookSearch: _bookPath = $_bookPath');
      if (searchTextController.text.isNotEmpty) {
        _runInitialSearch();
      }
    }
  }

  void _runInitialSearch() {
    _searchTextUpdated();
  }

  Future<void> _searchTextUpdated() async {
    final query = searchTextController.text.trim();
    if (query.isEmpty || _bookPath == null) {
      setState(() {
        searchResults = [];
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
          searchResults = _convertSearchResults(results);
          _isSearching = false;
        });
      }
    } catch (e) {
      debugPrint('Search error: $e');
      if (mounted) {
        setState(() {
          searchResults = [];
          _isSearching = false;
        });
      }
    }
  }

  List<TextSearchResult> _convertSearchResults(List<SearchResult> results) {
    final List<TextSearchResult> converted = [];
    for (final result in results) {
      try {
        final lineNumber = result.segment.toInt();
        if (lineNumber >= 0 && lineNumber < _content.length) {
          converted.add(TextSearchResult(
            index: lineNumber,
            snippet: result.text,
            address: result.reference,
            query: searchTextController.text,
          ));
        }
      } catch (e) {
        debugPrint('Error converting result: $e');
      }
    }
    return converted;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // יצירת רשימה מקובצת - כותרת מופיעה רק כשהיא משתנה
    final List<_GroupedResultItem> items = [];
    String? lastAddress;
    for (final r in searchResults) {
      if (lastAddress != r.address) {
        items.add(_GroupedResultItem.header(r.address));
        lastAddress = r.address;
      }
      items.add(_GroupedResultItem.result(r));
    }

    return SearchPaneBase(
      searchController: searchTextController,
      focusNode: widget.focusNode,
      progressWidget:
          _isSearching ? const LinearProgressIndicator(minHeight: 4) : null,
      resultCountString: searchResults.isNotEmpty
          ? 'נמצאו ${searchResults.length} תוצאות'
          : null,
      resultsWidget: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];

          // אם זו כותרת קבוצה
          if (item.isHeader) {
            return BlocBuilder<SettingsBloc, SettingsState>(
              builder: (context, settingsState) {
                String text = item.header!;
                if (settingsState.replaceHolyNames) {
                  text = utils.replaceHolyNames(text);
                }
                return Padding(
                  padding: const EdgeInsets.only(
                    top: 8.0,
                    bottom: 8.0,
                    right: 4.0,
                    left: 4.0,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        FluentIcons.text_align_right_24_regular,
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
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          }

          // אם זו תוצאה רגילה
          final result = item.result!;
          return BlocBuilder<SettingsBloc, SettingsState>(
            builder: (context, settingsState) {
              String snippet = result.snippet;

              if (settingsState.replaceHolyNames) {
                snippet = utils.replaceHolyNames(snippet);
              }

              // יצירת TextSpans עם הדגשה של מילות החיפוש
              final highlightedSnippet = _buildHighlightedText(
                snippet,
                result.query,
                settingsState,
                context,
              );

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
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
                  onTap: () {
                    // תמיד השתמש ב-scrollController - זה עובד גם בצורת הדף
                    widget.scrollControler.scrollTo(
                      index: result.index,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.ease,
                    );
                    if (Platform.isAndroid) {
                      widget.closeLeftPaneCallback();
                    }
                  },
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: RichText(
                      textAlign: TextAlign.justify,
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 16,
                          fontFamily: settingsState.fontFamily,
                          color: Theme.of(context).colorScheme.onSurface,
                          height: 1.5,
                        ),
                        children: highlightedSnippet,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      isNoResults:
          searchResults.isEmpty &&
          searchTextController.text.isNotEmpty &&
          !_isSearching,
      onSearchTextChanged: (value) {
        context.read<TextBookBloc>().add(UpdateSearchText(value));
        _searchTextUpdated();
      },
      resetSearchCallback: () {
        setState(() {
          searchResults = [];
          _searchOptions = {};
          _alternativeWords = {};
          _spacingValues = {};
          _searchMode = SearchMode.exact;
        });
      },
      hintText: 'חפש כאן...',
      onAdvancedSearch: () {
        // Create a temporary SearchingTab to hold the state
        final tempTab = SearchingTab("חיפוש", searchTextController.text);
        tempTab.searchOptions.addAll(_searchOptions);
        tempTab.alternativeWords.addAll(_alternativeWords);
        tempTab.spacingValues.addAll(_spacingValues);
        tempTab.searchBloc.add(SetSearchMode(_searchMode));

        final bookTitle = (context.read<TextBookBloc>().state as TextBookLoaded)
            .book
            .title;

        showDialog(
          context: context,
          builder: (context) => SearchDialog(
            existingTab: tempTab,
            bookTitle: bookTitle,
            onSearch: (query, searchOptions, alternativeWords, spacingValues,
                searchMode) {
              searchTextController.text = query;
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

  // פונקציה ליצירת טקסט מודגש
  List<InlineSpan> _buildHighlightedText(
    String text,
    String query,
    SettingsState settingsState,
    BuildContext context,
  ) {
    if (query.isEmpty) {
      return [TextSpan(text: text)];
    }

    final List<InlineSpan> spans = [];
    final searchTerms = query.trim().split(RegExp(r'\s+'));

    final highlightRegex = RegExp(
      searchTerms.map(RegExp.escape).join('|'),
      caseSensitive: false,
    );

    int currentPosition = 0;

    for (final match in highlightRegex.allMatches(text)) {
      // טקסט רגיל לפני ההדגשה
      if (match.start > currentPosition) {
        spans.add(TextSpan(
          text: text.substring(currentPosition, match.start),
        ));
      }
      // הטקסט המודגש
      spans.add(TextSpan(
        text: match.group(0),
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 18,
          color: Color(0xFFD32F2F), // צבע אדום חזק למילות החיפוש
        ),
      ));
      currentPosition = match.end;
    }

    // טקסט רגיל אחרי ההדגשה האחרונה
    if (currentPosition < text.length) {
      spans.add(TextSpan(
        text: text.substring(currentPosition),
      ));
    }

    return spans;
  }

  @override
  bool get wantKeepAlive => true;
}
