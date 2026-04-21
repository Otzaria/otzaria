import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/utils/snippet_builder.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/widgets_exports.dart';

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
  final ScrollController _scrollController = ScrollController();
  final Map<String, List<InlineSpan>> _snippetCache = {};

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
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constrains) {
      return BlocBuilder<SearchBloc, SearchState>(
        builder: (context, state) {
          // עכשיו רק מציגים את התוצאות - השורה התחתונה מוצגת במקום אחר
          return _buildResultsContent(state, constrains);
        },
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
    // תיקון שגיאות כתיב: totalResults = מה שנטען בפועל, לכן בודקים hasMoreResults
    final hasMoreResults = state.isTypoToleranceEnabled
        ? state.hasMoreResults
        : state.results.length < state.totalResults;
    final showInlineLoadingIndicator =
        state.isLoading && state.results.isNotEmpty && !hasMoreResults;
    final showLoadMoreButton = hasMoreResults;

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

          // תיקון שגיאות כתיב: totalResults = נטענו בפועל, לכן אין ספירה מדויקת
          final isLevenshtein = state.isTypoToleranceEnabled;
          final remainingText = isLevenshtein
              ? 'טען תוצאות נוספות'
              : 'טען תוצאות נוספות (${state.totalResults - state.results.length})';
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
                            searchOptions: widget.tab.searchOptions,
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
              state.isTypoToleranceEnabled,
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
                  searchOptions: widget.tab.searchOptions,
                  alternativeWords: widget.tab.alternativeWords,
                  customSpacing: widget.tab.spacingValues,
                  typoToleranceEnabled: state.isTypoToleranceEnabled,
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
                  final hasEnabledOptions = widget.tab.searchOptions.values
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

                  final shouldUseLegacyInBook = !hasEnabledOptions &&
                      !hasAlternativeWords &&
                      !hasSpacingValues &&
                      !state.isTypoToleranceEnabled &&
                      !looksLikeRegex &&
                      currentMode != SearchMode.fuzzy &&
                      currentMode != SearchMode.levenshtein;

                  final inBookMode =
                      shouldUseLegacyInBook ? SearchMode.exact : currentMode;

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
                              searchOptions: widget.tab.searchOptions,
                              alternativeWords: widget.tab.alternativeWords,
                              spacingValues: widget.tab.spacingValues,
                              searchMode: inBookMode,
                              typoToleranceEnabled:
                                  state.isTypoToleranceEnabled,
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
                              searchOptions: widget.tab.searchOptions,
                              alternativeWords: widget.tab.alternativeWords,
                              spacingValues: widget.tab.spacingValues,
                              searchMode: inBookMode,
                              typoToleranceEnabled:
                                  state.isTypoToleranceEnabled,
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
