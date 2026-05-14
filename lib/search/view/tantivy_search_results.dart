import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/utils/snippet_builder.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/buttons/action_buttons.dart';

class TantivySearchResults extends StatefulWidget {
  final SearchingTab tab;
  const TantivySearchResults({
    super.key,
    required this.tab,
  });

  @override
  State<TantivySearchResults> createState() => _TantivySearchResultsState();
}

class _TantivySearchResultsState extends State<TantivySearchResults> {
  static const int _maxUnbrokenWordLength = 12;
  static const double _loadMoreThreshold = 200;
  final ScrollController _scrollController = ScrollController();
  final Map<String, List<InlineSpan>> _snippetCache = {};
  bool _isAutoLoadInFlight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) {
      return;
    }

    if (_scrollController.position.extentAfter > _loadMoreThreshold) {
      return;
    }

    _maybeLoadMore();
  }

  void _maybeLoadMore() {
    if (!mounted || _isAutoLoadInFlight) {
      return;
    }

    final state = context.read<SearchBloc>().state;
    final hasMoreResults = state.results.length < state.totalResults;

    if (state.isLoading || !hasMoreResults) {
      return;
    }

    _isAutoLoadInFlight = true;
    context.read<SearchBloc>().add(
          LoadMoreResults(
            customSpacing: widget.tab.spacingValues,
            alternativeWords: widget.tab.alternativeWords,
            searchOptions: widget.tab.effectiveSearchOptions(
              query: context.read<SearchBloc>().state.searchQuery,
            ),
          ),
        );
  }

  String _searchResultDedupeKey({
    required String title,
    required String reference,
    required int segment,
    required bool isPdf,
  }) {
    return 'search:${isPdf ? 'pdf' : 'text'}|$title|$reference|$segment';
  }

  String _formatTitleForWrapping(String title) {
    return title.split(' ').map(_insertBreakOpportunities).join(' ');
  }

  String _insertBreakOpportunities(String word) {
    if (word.characters.length <= _maxUnbrokenWordLength) {
      return word;
    }

    final buffer = StringBuffer();
    var currentLength = 0;

    for (final character in word.characters) {
      buffer.write(character);
      currentLength++;

      if (currentLength >= _maxUnbrokenWordLength) {
        buffer.write('\u200B');
        currentLength = 0;
      }
    }

    return buffer.toString();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constrains) {
      return BlocListener<SearchBloc, SearchState>(
        listenWhen: (previous, current) =>
            previous.isLoading != current.isLoading ||
            previous.results.length != current.results.length ||
            previous.totalResults != current.totalResults,
        listener: (context, state) {
          if (!state.isLoading) {
            _isAutoLoadInFlight = false;
          }

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _handleScroll();
            }
          });
        },
        child: BlocBuilder<SearchBloc, SearchState>(
          builder: (context, state) {
            // עכשיו רק מציגים את התוצאות - השורה התחתונה מוצגת במקום אחר
            return _buildResultsContent(state, constrains);
          },
        ),
      );
    });
  }

  Widget _buildResultsContent(SearchState state, BoxConstraints constrains) {
    // חשוב: בעת טעינה אנחנו לא רוצים לפרק את ה-ListView,
    // אחרת הגלילה מתאפסת לראש. לכן ספינר מרכזי מוצג רק כשאין עדיין תוצאות.
    if (state.isLoading && state.results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.searchQuery.isEmpty) {
      return const Center(child: Text("לא בוצע חיפוש"));
    }
    if (state.results.isEmpty && !state.isLoading) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(8.0),
        child: Text('אין תוצאות'),
      ));
    }

    // תמיד נשתמש ב-ListView גם לתוצאה אחת - כך היא תופיע למעלה
    final hasMoreResults = state.results.length < state.totalResults;
    final showInlineLoadingIndicator =
        state.isLoading && state.results.isNotEmpty && !hasMoreResults;
    final showLoadMoreButton = hasMoreResults;

    // אפשרויות אפקטיביות זהות לכל איטם ב-build הנוכחי -
    // מחשבים פעם אחת מחוץ ל-itemBuilder כדי לחסוך עבודה
    final effectiveOptions = widget.tab.effectiveSearchOptions(
      query: state.searchQuery,
    );

    return ListView.builder(
      key: PageStorageKey(widget.tab),
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: state.results.length +
          ((showInlineLoadingIndicator || showLoadMoreButton) ? 1 : 0),
      itemBuilder: (context, index) {
        // האיטם האחרון מציג אינדיקטור טעינה בזמן הזרמה,
        // או כפתור pagination כשיש עוד תוצאות בשרת.
        if (index == state.results.length) {
          if (showInlineLoadingIndicator) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 8),
                    Text('טוען תוצאות...'),
                  ],
                ),
              ),
            );
          }

          final remainingText =
              'טען תוצאות נוספות (${state.totalResults - state.results.length})';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: NeutralActionButton(
                  text: state.isLoading ? 'טוען...' : remainingText,
                  onPressed: () {
                    context.read<SearchBloc>().add(
                          LoadMoreResults(
                            customSpacing: widget.tab.spacingValues,
                            alternativeWords: widget.tab.alternativeWords,
                            searchOptions: effectiveOptions,
                          ),
                        );
                  },
                  isLoading: state.isLoading,
                  icon: state.isLoading
                      ? null
                      : FluentIcons.arrow_download_24_regular,
                ),
              ),
            ),
          );
        }
        final result = state.results[index];
        return BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            final colorScheme = Theme.of(context).colorScheme;
            String titleText = result.reference;
            String rawHtml = result.text;
            // Debug info removed for production
            if (settingsState.replaceHolyNames) {
              titleText = utils.replaceHolyNames(titleText);
              rawHtml = utils.replaceHolyNames(rawHtml);
            }

            // חישוב רוחב זמין לטקסט
            final wrappedTitleText = _formatTitleForWrapping(titleText);
            final availableWidth = constrains.maxWidth - 100.0;

            final snippetCacheKey = [
              result.id,
              result.segment,
              rawHtml.hashCode,
              state.searchQuery.hashCode,
              SearchQueryBuilder.hasTypoToleranceEnabled(effectiveOptions),
              widget.tab.searchOptionsChanged.value,
              widget.tab.alternativeWordsChanged.value,
              widget.tab.spacingValuesChanged.value,
              settingsState.fontSize,
              settingsState.fontFamily,
              settingsState.replaceHolyNames,
              colorScheme.onSurface.toARGB32(),
              availableWidth.round(),
            ].join('|');

            // Create the snippet using the new robust function
            // שימוש בגופן וגודל של המשתמש מההגדרות
            final snippetSpans = _snippetCache.putIfAbsent(
              snippetCacheKey,
              () {
                if (_snippetCache.length > 300) {
                  _snippetCache.clear();
                }
                return SnippetBuilder.createSnippetSpans(
                  fullHtml: rawHtml,
                  query: state.searchQuery,
                  defaultStyle: TextStyle(
                    fontSize: settingsState.fontSize,
                    fontFamily: settingsState.fontFamily,
                    color: colorScheme.onSurface,
                    height: 1.5,
                  ),
                  highlightStyle: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: settingsState.fontSize + 2,
                    fontFamily: settingsState.fontFamily,
                    color: const Color(0xFFD32F2F),
                  ),
                  availableWidth: availableWidth,
                  searchOptions: effectiveOptions,
                  alternativeWords: widget.tab.alternativeWords,
                  customSpacing: widget.tab.spacingValues,
                  searchDistance: state.configuration.distance,
                );
              },
            );

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.3),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: InkWell(
                onTap: () {
                  final rawQuery = widget.tab.queryController.text;
                  final hasEnabledOptions = effectiveOptions.values
                      .any((m) => m.values.any((v) => v == true));
                  final hasAlternativeWords = widget.tab.alternativeWords.values
                      .any((alts) => alts.any((w) => w.trim().isNotEmpty));
                  final hasSpacingValues = widget.tab.spacingValues.values
                      .any((v) => v.trim().isNotEmpty);
                  final looksLikeRegex =
                      RegExp(r'[\\.\*\+\?\|\(\)\[\]\{\}\^\$]')
                          .hasMatch(rawQuery);
                  final currentMode =
                      widget.tab.searchBloc.state.configuration.searchMode;

                    final shouldUseSimpleInBook = !hasEnabledOptions &&
                      !hasAlternativeWords &&
                      !hasSpacingValues &&
                      !looksLikeRegex &&
                      currentMode != SearchMode.fuzzy;

                  final inBookMode =
                      shouldUseSimpleInBook ? SearchMode.exact : currentMode;

                  if (result.isPdf) {
                    final pageNumber = result.segment.toInt() + 1;
                    context.read<TabsBloc>().add(
                          OpenOrFocusTab(
                            PdfBookTab(
                              book: PdfBook(
                                  title: result.title, path: result.filePath),
                              pageNumber: pageNumber,
                              dedupeKey: _searchResultDedupeKey(
                                title: result.title,
                                reference: result.reference,
                                segment: result.segment.toInt(),
                                isPdf: true,
                              ),
                              searchText: rawQuery,
                              searchOptions: effectiveOptions,
                              alternativeWords: widget.tab.alternativeWords,
                              spacingValues: widget.tab.spacingValues,
                              searchMode: inBookMode,
                              openLeftPane:
                                  (Settings.getValue<bool>('key-pin-sidebar') ??
                                          false) ||
                                      (Settings.getValue<bool>(
                                              'key-default-sidebar-open') ??
                                          false),
                              requiresStableLayout: true,
                            ),
                            targetTitle: result.reference,
                          ),
                        );
                  } else {
                    context.read<TabsBloc>().add(
                          OpenOrFocusTab(
                            TextBookTab(
                              book: TextBook(
                                title: result.title,
                              ),
                              index: result.segment.toInt(),
                              dedupeKey: _searchResultDedupeKey(
                                title: result.title,
                                reference: result.reference,
                                segment: result.segment.toInt(),
                                isPdf: false,
                              ),
                              searchText: rawQuery,
                              searchOptions: effectiveOptions,
                              alternativeWords: widget.tab.alternativeWords,
                              spacingValues: widget.tab.spacingValues,
                              searchMode: inBookMode,
                              openLeftPane:
                                  (Settings.getValue<bool>('key-pin-sidebar') ??
                                          false) ||
                                      (Settings.getValue<bool>(
                                              'key-default-sidebar-open') ??
                                          false),
                            ),
                            targetTitle: result.reference,
                          ),
                        );
                  }
                },
                borderRadius: BorderRadius.circular(12),
                hoverColor: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.3),
                splashColor: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.4),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // מספר התוצאה
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // תוכן התוצאה
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // נתיב (כותרת + הפניה)
                            Row(
                              children: [
                                if (result.isPdf)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Icon(
                                      FluentIcons.document_pdf_24_regular,
                                      size: 16,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    wrappedTitleText,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                    textAlign: TextAlign.right,
                                    textDirection: TextDirection.rtl,
                                    softWrap: true,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // הטקסט שנמצא
                            RichText(
                              textAlign: TextAlign.justify,
                              text: TextSpan(
                                style: TextStyle(
                                  fontSize: 16,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  height: 1.5,
                                ),
                                children: snippetSpans,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
