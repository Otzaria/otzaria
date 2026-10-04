import 'dart:async';

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
import 'package:otzaria/search/view/search_scope_menu.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/search_feedback/semantic_search_strings.dart';
import 'package:otzaria/semantic_search/bloc/semantic_results_bloc.dart';
import 'package:otzaria/semantic_search/models/semantic_mode_gate.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria/semantic_search/services/semantic_dwell_binding.dart';
import 'package:otzaria/semantic_search/view/semantic_mode_panel.dart';
import 'package:otzaria/semantic_search/view/widgets/semantic_result_card.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/models/semantic_search_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/utils/text/copy_utils.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show MergedSibling;

/// מסך כרטיסיית התוצאות של החיפוש הסמנטי.
class SemanticSearchResultsScreen extends StatefulWidget {
  const SemanticSearchResultsScreen({super.key, required this.tab});

  final SemanticSearchTab tab;

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
  late Set<String> _scope;
  late bool _includeLexical;
  late bool _groupIdentical;
  double? _previewPaneWidthOverride;
  int _previewRequestId = 0;

  /// התוצאה שבתצוגה המקדימה; קובע אם להדגיש מילים בספר.
  SemanticResultItem? _previewItem;

  SemanticResultsBloc get _bloc => widget.tab.resultsBloc;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final options = widget.tab.options;
    _scope = options.facets.toSet();
    _includeLexical = options.includeLexical;
    _groupIdentical = options.groupIdenticalText;
    _scrollController.addListener(_handleScroll);
    if (widget.tab.runOnFirstShow &&
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
    if (state.hasMore && !state.isLoadingMore) {
      _bloc.add(const SemanticMoreResultsRequested());
    }
  }

  void _submit() {
    var query = widget.tab.queryController.text.trim();
    if (utils.hasNikud(query)) query = utils.removeVolwels(query).trim();
    if (query.isEmpty) {
      UiSnack.show(LibraryMessages.emptySearchQuery);
      return;
    }
    widget.tab.previewTarget.value = null;
    widget.tab.submit(
      SemanticQueryOptions(
        query: query,
        facets: semanticScopeFacets(
          _scope,
          isOfficialCategory: officialCategoryFilter(
            context.read<LibraryBloc>().state.library,
          ),
        ),
        includeLexical: _includeLexical,
        groupIdenticalText: _groupIdentical,
      ),
    );
  }

  InBookSearchParameters get _inBookParameters =>
      InBookSearchRouting.resolveForReadingTab(
        searchMode: SearchMode.exact,
        distance: 0,
        searchOptions: const {},
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
    if (opened == null || !mounted) return;
    final searchContext = _bloc.searchContext;
    if (searchContext == null ||
        (sibling == null && _bloc.isUserBookAt(index))) {
      return;
    }
    final bloc = _bloc;
    final openId = bloc.recordOpen(index, via, sibling: sibling);
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
    final current = widget.tab.previewTarget.value;
    if (current != null &&
        current.matchesResult(
          filePath: filePath,
          segment: segment,
          isPdf: isPdf,
        )) {
      widget.tab.previewTarget.value = null;
      return;
    }
    final resolution = await widget.tab.searchBloc.resolveBookForIndexedPath(
      filePath,
      indexedTitle: title,
    );
    if (!mounted || requestId != _previewRequestId) return;
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
        ),
      );
    }
  }

  void _togglePreviewOf(int index) {
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

  void _copy(SemanticResultItem item, SettingsState settings, String ref) {
    final plainText = utils.stripHtmlIfNeeded(item.snippetHtml);
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
    return Scaffold(
      body: BlocProvider.value(
        value: _bloc,
        child: BlocListener<SemanticResultsBloc, SemanticResultsState>(
          listenWhen: (previous, current) =>
              previous.searchId != current.searchId,
          listener: (context, state) {
            widget.tab.previewTarget.value = null;
            if (_scrollController.hasClients) _scrollController.jumpTo(0);
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final results = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context),
                  const Divider(height: 1),
                  Expanded(child: _buildBody(constraints)),
                ],
              );
              if (constraints.maxWidth < _previewMinWidth) return results;
              return _wrapWithPreviewPane(results, constraints);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: BlocBuilder<SemanticResultsBloc, SemanticResultsState>(
        buildWhen: (p, c) =>
            p.status != c.status || p.isDebugPreview != c.isDebugPreview,
        builder: (context, state) {
          final loading = state.status == SemanticResultsStatus.loading;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: RtlTextField(
                      key: const ValueKey('semantic-results-query'),
                      controller: widget.tab.queryController,
                      decoration: InputDecoration(
                        isDense: true,
                        border: const OutlineInputBorder(),
                        labelText: context.settingsText(
                          kSemanticSearchModeName,
                        ),
                        prefixIcon: const Icon(
                          OtzariaIcons.search_in_the_library_24_regular,
                        ),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (loading)
                    ActionButton.neutral(
                      key: const ValueKey('semantic-results-cancel'),
                      text: context.settingsText('עצור'),
                      icon: FluentIcons.dismiss_24_regular,
                      onPressed: () =>
                          _bloc.add(const SemanticSearchCancelRequested()),
                    )
                  else
                    ActionButton.recommended(
                      key: const ValueKey('semantic-results-search'),
                      text: context.settingsText('חפש'),
                      icon: FluentIcons.search_24_regular,
                      onPressed: _submit,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SearchScopeMenuButton(
                    selected: _scope,
                    width: 240,
                    showChips: false,
                    onChanged: (selection) =>
                        setState(() => _scope = selection),
                  ),
                  FilterChip(
                    label: Text(context.settingsText('שלב גם התאמה מילולית')),
                    visualDensity: VisualDensity.compact,
                    selected: _includeLexical,
                    onSelected: (value) =>
                        setState(() => _includeLexical = value),
                  ),
                  FilterChip(
                    label: Text(context.settingsText('איחוד טקסטים זהים')),
                    visualDensity: VisualDensity.compact,
                    selected: _groupIdentical,
                    onSelected: (value) =>
                        setState(() => _groupIdentical = value),
                  ),
                ],
              ),
              if (state.isDebugPreview) ...[
                const SizedBox(height: 8),
                const SemanticDebugPreviewBanner(),
              ],
            ],
          );
        },
      ),
    );
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
                icon: OtzariaIcons.search_in_the_library_24_regular,
                title: context.settingsText('החיפוש לא הורץ מחדש'),
                message: context.settingsText(
                  'כרטיסייה ששוחזרה או שוכפלה אינה מחפשת מעצמה. לחצו כדי לחפש שוב.',
                ),
                action: ActionButton.recommended(
                  key: const ValueKey('semantic-results-rerun'),
                  text: context.settingsText('לחץ לחיפוש מחדש'),
                  icon: FluentIcons.search_24_regular,
                  onPressed: _submit,
                ),
              );
            }
            return _emptyState(
              icon: OtzariaIcons.search_in_the_library_24_regular,
              title: context.settingsText('לא בוצע חיפוש'),
              message: context.settingsText(
                'תארו את העניין שאתם מחפשים ולחצו על "חפש".',
              ),
            );
          case SemanticResultsStatus.loading:
            return const Center(child: CircularProgressIndicator());
          case SemanticResultsStatus.cancelled:
            return _emptyState(
              icon: FluentIcons.dismiss_circle_24_regular,
              title: context.settingsText('החיפוש הופסק'),
              action: ActionButton.recommended(
                text: context.settingsText('חפש שוב'),
                icon: FluentIcons.arrow_clockwise_24_regular,
                onPressed: _submit,
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
                onPressed: _submit,
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
          child: ActionButton.neutral(
            key: const ValueKey('semantic-results-more'),
            text: state.isLoadingMore
                ? context.settingsText('טוען...')
                : context.settingsText('טען תוצאות נוספות'),
            isLoading: state.isLoadingMore,
            icon: state.isLoadingMore
                ? null
                : FluentIcons.arrow_download_24_regular,
            onPressed: () => _bloc.add(const SemanticMoreResultsRequested()),
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
    var html = item.snippetHtml;
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
      return SnippetBuilder.fromHighlightedHtml(
        html: html,
        defaultStyle: TextStyle(
          fontSize: settings.fontSize,
          fontFamily: settings.fontFamily,
          color: colorScheme.onSurface,
          height: 1.5,
        ),
        highlightStyle: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: settings.fontSize + 2,
          fontFamily: settings.fontFamily,
          color: colorScheme.error,
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
      onCopy: () => _copy(item, settings, reference),
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
              onClose: () => widget.tab.previewTarget.value = null,
            );
          },
        );
      },
    );
  }
}
