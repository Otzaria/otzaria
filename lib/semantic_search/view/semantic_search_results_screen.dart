import 'dart:async';

import 'package:otzaria/theme/app_fonts.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/view/book_preview_panel.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/models/search_preview_target.dart';
import 'package:otzaria/search/utils/in_book_search_routing.dart';
import 'package:otzaria/search/utils/search_result_opener.dart';
import 'package:otzaria/search/utils/snippet_builder.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/search/view/search_results_layout.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/search_feedback/semantic_search_strings.dart';
import 'package:otzaria/semantic_search/bloc/semantic_results_bloc.dart';
import 'package:otzaria/semantic_search/models/semantic_engine_models.dart';
import 'package:otzaria/semantic_search/models/semantic_mode_gate.dart';
import 'package:otzaria/semantic_search/repository/semantic_platform_support.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria/semantic_search/services/semantic_dwell_binding.dart';
import 'package:otzaria/semantic_search/view/semantic_mode_panel.dart';
import 'package:otzaria/semantic_search/view/widgets/semantic_facet_filtering.dart';
import 'package:otzaria/semantic_search/view/widgets/semantic_result_card.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/models/semantic_search_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/utils/text/copy_utils.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show MergedSibling, SemanticLexicalMode;

/// האם לבנות מחדש את מסגרת המסך (סרגל, מסננים, תצוגה מקדימה). סימון קטע
/// והצבעה משנים רק כרטיסים, והרשימה הפנימית מאזינה ל-bloc בעצמה.
@visibleForTesting
bool semanticLayoutNeedsRebuild(
  SemanticResultsState previous,
  SemanticResultsState current,
) =>
    previous.copyWith(
      votes: current.votes,
      passageHighlights: current.passageHighlights,
    ) !=
    current;

/// מסך כרטיסיית התוצאות של החיפוש הסמנטי.
class SemanticSearchResultsScreen extends StatefulWidget {
  const SemanticSearchResultsScreen({
    super.key,
    required this.tab,
    this.platformSupported,
  });

  final SemanticSearchTab tab;
  final bool? platformSupported;

  @override
  State<SemanticSearchResultsScreen> createState() =>
      _SemanticSearchResultsScreenState();
}

class _SemanticSearchResultsScreenState
    extends State<SemanticSearchResultsScreen>
    with AutomaticKeepAliveClientMixin {
  static const double _loadMoreThreshold = 200;
  static const double _previewMinWidth = 800;

  final ScrollController _scrollController = ScrollController();
  final Map<String, List<InlineSpan>> _snippetCache = {};
  double? _previewPaneWidthOverride;

  Map<String, int> _facetCountsCache = const {};
  List<SemanticResultItem>? _facetCountsItems;
  int _previewRequestId = 0;

  /// התוצאה שבתצוגה המקדימה; קובע אם להדגיש מילים בספר.
  SemanticResultItem? _previewItem;

  SemanticResultsBloc get _bloc => widget.tab.resultsBloc;

  bool get _platformSupported =>
      widget.platformSupported ?? isSemanticSearchPlatformSupported();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final options = widget.tab.options;
    _scrollController.addListener(_handleScroll);
    if (widget.tab.runOnFirstShow &&
        _platformSupported &&
        _bloc.state.status == SemanticResultsStatus.initial &&
        options.query.trim().isNotEmpty) {
      _bloc.add(SemanticSearchSubmitted(options));
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > _loadMoreThreshold) {
      return;
    }
    final state = _bloc.state;
    if (state.hasMore && !state.isLoadingMore && state.message == null) {
      _bloc.add(const SemanticMoreResultsRequested());
    }
  }

  /// מריץ שוב את החיפוש האחרון (כולל צמצום פעיל).
  void _rerun() {
    final options = _bloc.state.options ?? widget.tab.options;
    if (options.query.trim().isEmpty) {
      UiSnack.show(LibraryMessages.emptySearchQuery);
      return;
    }
    _clearPreview();
    _bloc.add(SemanticSearchSubmitted(options));
  }

  void _openEditDialog() {
    showDialog(
      context: context,
      builder: (_) => SearchDialog(editTab: widget.tab),
    );
  }

  List<String> get _currentFacets =>
      _bloc.state.options?.facets ?? widget.tab.options.facets;

  void _narrow(List<String> categories, List<String> dimensions) {
    final scope = FacetHelper.categoryFacetsOf(widget.tab.options.facets);
    final facets = semanticScopeFacets(
      [...(categories.isEmpty ? scope : categories), ...dimensions],
      isOfficialCategory: officialCategoryFilter(
        context.read<LibraryBloc>().state.library,
      ),
    );
    _clearPreview();
    widget.tab.narrow(facets);
  }

  void _setFacet(String facet) {
    final dimensions = FacetHelper.dimensionFacetsOf(_currentFacets);
    _narrow(facet == '/' ? const [] : [facet], dimensions);
  }

  void _toggleFacet(String facet) {
    final categories = FacetHelper.categoryFacetsOf(_currentFacets)
      ..remove('/');
    if (!categories.remove(facet)) categories.add(facet);
    _narrow(categories, FacetHelper.dimensionFacetsOf(_currentFacets));
  }

  void _toggleDimension(String facet) {
    final dimensions = FacetHelper.dimensionFacetsOf(_currentFacets);
    if (!dimensions.remove(facet)) dimensions.add(facet);
    _narrow(
      FacetHelper.categoryFacetsOf(_currentFacets),
      dimensions..sort(),
    );
  }

  /// ספירה לפי קטגוריה של התוצאות שמוצגות כעת.
  Map<String, int> _facetCounts(SemanticResultsState state) {
    if (identical(state.items, _facetCountsItems)) return _facetCountsCache;
    final library = context.read<LibraryBloc>().state.library;
    if (library == null) return const {};
    _facetCountsItems = state.items;
    return _facetCountsCache = FacetHelper.buildFacetCountsFromResults(
      state.items,
      widget.tab.searchBloc.booksByIndexedFilePath(library),
    );
  }

  void _clearPreview() {
    _previewRequestId++;
    _previewItem = null;
    widget.tab.previewTarget.value = null;
  }

  /// החיפוש בספר רץ באותו מצב שבו הצד המילולי מצא את התוצאה — מילים בכל
  /// סדר ובצורותיהן; חיפוש מדויק היה מחפש רצף ליטרלי ולא מוצא.
  InBookSearchParameters get _inBookParameters =>
      InBookSearchRouting.resolveForReadingTab(
        searchMode: switch (kSmartSearchLexicalMode) {
          SemanticLexicalMode.exact => SearchMode.exact,
          SemanticLexicalMode.fuzzy => SearchMode.fuzzy,
        },
        distance: kSmartSearchFuzzyMaxDistance,
        searchOptions: const {},
        matchPolicy: SearchMatchPolicy.smart,
      );

  /// מילים להדגשה בספר; תוצאה לפי עניין בלבד נפתחת בלי הדגשת מילים.
  String _searchTextFor(SemanticResultItem? item) =>
      item == null || item.isSemanticOnly ? '' : widget.tab.options.query;

  Future<void> _openItem(
    int index,
    SearchFeedbackOpenVia via, {
    bool inBackground = false,
    MergedSibling? sibling,
  }) async {
    final state = _bloc.state;
    if (index < 0 || index >= state.items.length) return;
    final parent = state.items[index];
    final searchContext = _bloc.searchContext;
    final searchId = state.searchId;
    final item = sibling == null ? parent : parent.forSibling(sibling);
    final opened = await _openLocation(
      title: item.title,
      reference: item.reference,
      segment: item.segment,
      isPdf: item.isPdf,
      filePath: item.filePath,
      searchText: _searchTextFor(item),
      inBackground: inBackground,
    );
    if (opened == null ||
        !mounted ||
        searchId != _bloc.state.searchId ||
        !identical(searchContext, _bloc.searchContext)) {
      return;
    }
    if (searchContext == null ||
        (sibling == null && _bloc.isUserBookAt(index))) {
      return;
    }
    final bloc = _bloc;
    final openId = bloc.recordOpen(
      index,
      via,
      sibling: sibling,
      expectedContext: searchContext,
      expectedItem: parent,
    );
    SemanticDwellBinding.of(
      context.read<TabsBloc>(),
      context.read<NavigationBloc>(),
    ).tracker.begin(
      // פתיחה רגילה עשויה למקד כרטיסייה קיימת — נקשרת לפעילה הבאה.
      tab: inBackground ? opened : null,
      resultsTab: widget.tab,
      onEnd: (dwell, reason) => openId.then((id) async {
        if (id != null) {
          await bloc.recordDwell(searchContext, id, dwell, reason);
        }
      }),
    );
  }

  Future<OpenedTab?> _openLocation({
    required String title,
    required String reference,
    required int segment,
    required bool isPdf,
    required String filePath,
    required String searchText,
    bool inBackground = false,
  }) async {
    final resolution = await widget.tab.searchBloc.resolveBookForIndexedPath(
      filePath,
      indexedTitle: title,
    );
    if (!mounted) return null;
    if (resolution.isStale) {
      UiSnack.showError(LibraryMessages.searchResultIndexOutOfDate);
      return null;
    }
    return openSearchResultInReader(
      context,
      resolvedBook: resolution.book,
      title: title,
      reference: reference,
      segment: segment,
      isPdf: isPdf,
      filePath: filePath,
      searchText: searchText,
      searchOptions: const {},
      alternativeWords: const {},
      spacingValues: const {},
      inBook: _inBookParameters,
      inBackground: inBackground,
    );
  }

  Future<void> _togglePreview({
    required SemanticResultItem item,
    required String title,
    required String reference,
    required int segment,
    required bool isPdf,
    required String filePath,
    int? recordIndex,
    MergedSibling? recordSibling,
  }) async {
    final requestId = ++_previewRequestId;
    final searchId = _bloc.state.searchId;
    final searchContext = _bloc.searchContext;
    final current = widget.tab.previewTarget.value;
    if (current != null &&
        current.matchesResult(
          filePath: filePath,
          segment: segment,
          isPdf: isPdf,
        )) {
      _clearPreview();
      return;
    }
    final resolution = await widget.tab.searchBloc.resolveBookForIndexedPath(
      filePath,
      indexedTitle: title,
    );
    if (!mounted ||
        requestId != _previewRequestId ||
        searchId != _bloc.state.searchId) {
      return;
    }
    if (resolution.isStale) {
      UiSnack.showError(LibraryMessages.searchResultIndexOutOfDate);
      return;
    }
    final resolved = resolution.book;
    final Book book = isPdf
        ? (resolved is PdfBook
              ? resolved
              : PdfBook(title: title, path: filePath))
        : switch (resolved) {
            final TextBook value => value,
            final ConvertibleDocumentBook value => value.toTextBook(),
            _ => TextBook(title: title),
          };
    _previewItem = item;
    widget.tab.previewTarget.value = SearchPreviewTarget(
      book: book,
      title: title,
      reference: reference,
      segment: segment,
      isPdf: isPdf,
      filePath: filePath,
    );
    if (recordIndex != null) {
      unawaited(
        _bloc.recordOpen(
          recordIndex,
          SearchFeedbackOpenVia.preview,
          sibling: recordSibling,
          expectedContext: searchContext,
          expectedItem: item,
        ),
      );
    }
  }

  void _togglePreviewOf(int index) {
    if (index < 0 || index >= _bloc.state.items.length) return;
    final item = _bloc.state.items[index];
    unawaited(
      _togglePreview(
        item: item,
        title: item.title,
        reference: item.reference,
        segment: item.segment,
        isPdf: item.isPdf,
        filePath: item.filePath,
        recordIndex: index,
      ),
    );
  }

  void _copy(
    SemanticResultItem item,
    String snippetHtml,
    SettingsState settings,
    String ref,
  ) {
    final plainText = utils.stripHtmlIfNeeded(snippetHtml);
    final bookName = settings.replaceHolyNames
        ? utils.replaceHolyNames(item.title, style: settings.holyNameStyle)
        : item.title;
    Clipboard.setData(
      ClipboardData(
        text: CopyUtils.formatTextWithHeaders(
          originalText: plainText,
          copyWithHeaders: settings.copyWithHeaders,
          copyHeaderFormat: settings.copyHeaderFormat,
          bookName: bookName,
          currentPath: CopyUtils.referencePath(
            bookName: bookName,
            reference: ref,
          ),
        ),
      ),
    );
    UiSnack.show(UiSnack.textCopied);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_platformSupported) {
      return Scaffold(
        body: _emptyState(
          icon: FluentIcons.info_24_regular,
          title: context.settingsText('החיפוש אינו זמין כרגע'),
        ),
      );
    }
    return Scaffold(
      body: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: _bloc),
          // מילות החיפוש בסרגל (SearchTermsDisplay) נקראות מ-SearchBloc.
          BlocProvider.value(value: widget.tab.searchBloc),
        ],
        child: BlocConsumer<SemanticResultsBloc, SemanticResultsState>(
          listenWhen: (previous, current) =>
              previous.searchId != current.searchId,
          listener: (context, state) {
            _clearPreview();
            if (_scrollController.hasClients) _scrollController.jumpTo(0);
          },
          buildWhen: semanticLayoutNeedsRebuild,
          builder: (context, state) {
            final loading = state.status == SemanticResultsStatus.loading;
            return SearchResultsLayout(
              tab: widget.tab,
              label: context.settingsText(kSemanticSearchModeLabel),
              hasQuery: widget.tab.options.query.trim().isNotEmpty,
              query: widget.tab.options.query.trim(),
              onEditSearch: _openEditDialog,
              countsBuilder: (context, collapsed) =>
                  _buildResultCounts(context, state, collapsed: collapsed),
              banners: [
                if (state.isDebugPreview) const SemanticDebugPreviewBanner(),
                if (isWholeLibraryScope(_currentFacets))
                  const _NarrowScopeBanner(),
              ],
              resultsBuilder: (showPreviewPane) => LayoutBuilder(
                builder: (context, constraints) {
                  final body = _buildBody(constraints);
                  if (!showPreviewPane ||
                      constraints.maxWidth < _previewMinWidth) {
                    return body;
                  }
                  return _wrapWithPreviewPane(body, constraints);
                },
              ),
              facetPane: SemanticFacetFiltering(
                facetCounts: _facetCounts(state),
                selectedFacets: _currentFacets,
                isLoading: loading,
                hasResults: state.items.isNotEmpty,
                onSetFacet: _setFacet,
                onToggleFacet: _toggleFacet,
                onClearAll: () => _narrow(const [], const []),
                onToggleDimension: _toggleDimension,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildResultCounts(
    BuildContext context,
    SemanticResultsState state, {
    required bool collapsed,
  }) {
    final count = state.items.length;
    final line = context.settingsText(
      'מוצגות כעת {count} תוצאות',
      args: {'count': '$count'},
    );
    final text = Text(
      collapsed ? '$count' : line,
      key: const ValueKey('semantic-results-count'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 14,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
    return collapsed ? Tooltip(message: line, child: text) : text;
  }

  /// הודעת הכשל של המצב, מתורגמת ועם שם המצב.
  String? _message(String? template) => template == null
      ? null
      : context.settingsText(
          template,
          args: {'name': context.settingsText(kSemanticSearchModeName)},
        );

  Widget _emptyState({
    required IconData icon,
    required String title,
    String? message,
    Widget? action,
  }) {
    return OtzariaEmptyState(
      icon: icon,
      title: title,
      message: message,
      action: action,
    );
  }

  Widget _buildBody(BoxConstraints constraints) {
    return BlocBuilder<SemanticResultsBloc, SemanticResultsState>(
      builder: (context, state) {
        switch (state.status) {
          case SemanticResultsStatus.initial:
            if (widget.tab.options.query.trim().isNotEmpty) {
              return _emptyState(
                icon: OtzariaIcons.search_in_library_24_regular,
                title: context.settingsText('החיפוש לא הורץ מחדש'),
                message: context.settingsText(
                  'כרטיסייה ששוחזרה או שוכפלה אינה מחפשת מעצמה. לחצו כדי לחפש שוב.',
                ),
                action: ActionButton.recommended(
                  key: const ValueKey('semantic-results-rerun'),
                  text: context.settingsText('לחץ לחיפוש מחדש'),
                  icon: FluentIcons.search_24_regular,
                  onPressed: _rerun,
                ),
              );
            }
            return _emptyState(
              icon: OtzariaIcons.search_in_library_24_regular,
              title: context.settingsText('לא בוצע חיפוש'),
              message: context.settingsText(
                'תארו את העניין שאתם מחפשים ולחצו על "חפש".',
              ),
            );
          case SemanticResultsStatus.loading:
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  ActionButton.neutral(
                    key: const ValueKey('semantic-results-cancel'),
                    text: context.settingsText('עצור'),
                    icon: FluentIcons.dismiss_24_regular,
                    onPressed: () =>
                        _bloc.add(const SemanticSearchCancelRequested()),
                  ),
                ],
              ),
            );
          case SemanticResultsStatus.cancelled:
            return _emptyState(
              icon: FluentIcons.dismiss_circle_24_regular,
              title: context.settingsText('החיפוש הופסק'),
              action: ActionButton.recommended(
                text: context.settingsText('חפש שוב'),
                icon: FluentIcons.arrow_clockwise_24_regular,
                onPressed: _rerun,
              ),
            );
          case SemanticResultsStatus.failed:
            return _emptyState(
              icon: FluentIcons.warning_24_regular,
              title: context.settingsText('החיפוש נכשל'),
              message: _message(state.message),
              action: ActionButton.recommended(
                text: context.settingsText('נסה שוב'),
                icon: FluentIcons.arrow_clockwise_24_regular,
                onPressed: _rerun,
              ),
            );
          case SemanticResultsStatus.unavailable:
            return _emptyState(
              icon: FluentIcons.info_24_regular,
              title: context.settingsText('החיפוש אינו זמין כרגע'),
              message: _message(state.message),
            );
          case SemanticResultsStatus.loaded:
            if (state.items.isEmpty) {
              return _emptyState(
                icon: OtzariaIcons.search_not_found_24_regular,
                title: context.settingsText('אין תוצאות'),
                message: context.settingsText(
                  'נסו לתאר את העניין במילים אחרות או להרחיב את היקף החיפוש.',
                ),
              );
            }
            return _buildList(state, constraints);
        }
      },
    );
  }

  Widget _buildList(SemanticResultsState state, BoxConstraints constraints) {
    final showPreview = constraints.maxWidth >= _previewMinWidth;
    final itemCount = state.items.length + (state.hasMore ? 1 : 0);
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settings) {
        final previewEnabled = showPreview && settings.searchShowPreview;
        return ValueListenableBuilder<SearchPreviewTarget?>(
          valueListenable: widget.tab.previewTarget,
          builder: (context, previewTarget, _) => ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              if (index == state.items.length) {
                return _buildLoadMore(state);
              }
              return _buildCard(
                state,
                index,
                settings,
                previewEnabled: previewEnabled,
                previewTarget: previewTarget,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildLoadMore(SemanticResultsState state) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Column(
            children: [
              if (state.message != null) ...[
                Text(
                  _message(state.message)!,
                  key: const ValueKey('semantic-results-page-error'),
                ),
                const SizedBox(height: 8),
              ],
              ActionButton.neutral(
                key: const ValueKey('semantic-results-more'),
                text: state.message != null
                    ? context.settingsText('נסה שוב')
                    : state.isLoadingMore
                    ? context.settingsText('טוען...')
                    : context.settingsText('טען תוצאות נוספות'),
                isLoading: state.isLoadingMore,
                icon: state.isLoadingMore
                    ? null
                    : FluentIcons.arrow_download_24_regular,
                onPressed: () =>
                    _bloc.add(const SemanticMoreResultsRequested()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(
    SemanticResultsState state,
    int index,
    SettingsState settings, {
    required bool previewEnabled,
    required SearchPreviewTarget? previewTarget,
  }) {
    final item = state.items[index];
    final colorScheme = Theme.of(context).colorScheme;
    var reference = item.reference;
    final shownHtml = state.passageHighlights[index] ?? item.snippetHtml;
    var html = shownHtml;
    if (settings.replaceHolyNames) {
      reference = utils.replaceHolyNames(
        reference,
        style: settings.holyNameStyle,
      );
      html = utils.replaceHolyNames(html, style: settings.holyNameStyle);
    }
    final cacheKey = [
      item.id,
      item.segment,
      html.hashCode,
      settings.fontSize,
      settings.fontFamily,
      colorScheme.onSurface.toARGB32(),
    ].join('|');
    final spans = _snippetCache.putIfAbsent(cacheKey, () {
      if (_snippetCache.length > 300) _snippetCache.clear();
      final defaultStyle = TextStyle(
        fontSize: settings.fontSize,
        fontFamily: AppFonts.renderFontFamily(settings.fontFamily),
        color: colorScheme.onSurface,
        height: 1.5,
      );
      return SnippetBuilder.fromHighlightedHtml(
        html: html,
        defaultStyle: defaultStyle,
        highlightStyle: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: settings.fontSize + 2,
          fontFamily: AppFonts.renderFontFamily(settings.fontFamily),
          color: colorScheme.error,
        ),
        markStyle: defaultStyle.copyWith(
          backgroundColor: AppSurfaces.semanticPassageHighlight(colorScheme),
        ),
      );
    });
    final isPreviewed =
        previewEnabled &&
        previewTarget != null &&
        previewTarget.matchesResult(
          filePath: item.filePath,
          segment: item.segment,
          isPdf: item.isPdf,
        );
    return SemanticResultCard(
      key: ValueKey('semantic-result-$index'),
      item: item,
      rank: index + 1,
      titleText: reference,
      snippetSpans: spans,
      vote: state.votes[index],
      isPreviewed: isPreviewed,
      groupIdenticalText: state.options?.groupIdenticalText ?? true,
      onTap: previewEnabled
          ? () => _togglePreviewOf(index)
          : () => _openItem(index, SearchFeedbackOpenVia.click),
      onDoubleTap: previewEnabled
          ? () => _openItem(index, SearchFeedbackOpenVia.click)
          : null,
      onKeyboardOpen: () => _openItem(index, SearchFeedbackOpenVia.keyboard),
      onOpenInBackground: () => _openItem(
        index,
        SearchFeedbackOpenVia.background,
        inBackground: true,
      ),
      onVote: (vote) => _bloc.add(SemanticVoteToggled(index, vote)),
      onCopy: () => _copy(item, shownHtml, settings, reference),
      onOpenSibling: (sibling) =>
          _openItem(index, SearchFeedbackOpenVia.click, sibling: sibling),
      onOpenSiblingInBackground: (sibling) => _openItem(
        index,
        SearchFeedbackOpenVia.background,
        inBackground: true,
        sibling: sibling,
      ),
      onPreviewSibling: previewEnabled
          ? (sibling) => unawaited(
              _togglePreview(
                item: item,
                title: sibling.title,
                reference: sibling.reference,
                segment: sibling.segment.toInt(),
                isPdf: sibling.isPdf,
                filePath: sibling.filePath,
                recordIndex: index,
                recordSibling: sibling,
              ),
            )
          : null,
    );
  }

  Widget _wrapWithPreviewPane(Widget mainContent, BoxConstraints constraints) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (p, c) => p.searchShowPreview != c.searchShowPreview,
      builder: (context, settings) {
        return ValueListenableBuilder<SearchPreviewTarget?>(
          valueListenable: widget.tab.previewTarget,
          builder: (context, target, _) {
            final inBook = _inBookParameters;
            final available = constraints.maxWidth;
            final minWidth = available < 280 ? available : 280.0;
            final maxWidth = (available - 320).clamp(minWidth, available);
            final paneWidth = (_previewPaneWidthOverride ?? available * 0.4)
                .clamp(minWidth, maxWidth);
            return AdaptiveSidePane(
              isOpen: settings.searchShowPreview && target != null,
              alignment: AlignmentDirectional.centerStart,
              mainContent: mainContent,
              paneContent: BookPreviewPanel(
                book: target?.book,
                initialTextIndex: target != null && !target.isPdf
                    ? target.segment
                    : null,
                initialPdfPage: target != null && target.isPdf
                    ? target.segment + 1
                    : null,
                searchText: _searchTextFor(_previewItem),
                searchMode: inBook.searchMode,
                searchDistance: inBook.distance,
                matchPolicy: inBook.matchPolicy,
                onOpenInReader: (_, {bool? forcePdf}) {
                  final openTarget = widget.tab.previewTarget.value;
                  if (openTarget == null) return;
                  unawaited(
                    _openLocation(
                      title: openTarget.title,
                      reference: openTarget.reference,
                      segment: openTarget.segment,
                      isPdf: openTarget.isPdf,
                      filePath: openTarget.filePath,
                      searchText: _searchTextFor(_previewItem),
                    ),
                  );
                },
              ),
              paneWidth: paneWidth,
              minPaneWidth: minWidth,
              maxPaneWidth: maxWidth,
              minMainContentWidth: 300,
              isResizable: true,
              autoHandleResponsiveVisibility: false,
              onPaneWidthChanged: (w) => _previewPaneWidthOverride = w,
              onClose: _clearPreview,
            );
          },
        );
      },
    );
  }
}

/// המלצה לצמצם את ההיקף, כשהחיפוש רץ על כל הספרייה.
class _NarrowScopeBanner extends StatelessWidget {
  const _NarrowScopeBanner();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: cs.primaryContainer.withValues(alpha: 0.4),
      child: Row(
        children: [
          Icon(FluentIcons.info_24_regular, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: SemanticNarrowScopeHint(
              style: TextStyle(fontSize: 13, color: cs.primary),
            ),
          ),
        ],
      ),
    );
  }
}
