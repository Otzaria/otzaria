import 'dart:async';

import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/library/view/book_preview_panel.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/models/search_preview_target.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/utils/in_book_search_routing.dart';
import 'package:otzaria/search/utils/index_freshness_warner.dart';
import 'package:otzaria/search/models/external_search_status.dart';
import 'package:otzaria/search/utils/snippet_builder.dart';
import 'package:otzaria/search/view/external_search_results_section.dart';
import 'package:otzaria/search/view/search_result_source_tag.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/utils/navigation/talmud_bavli_open_format.dart';
import 'package:otzaria/utils/text/copy_utils.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart'
    show MergedSibling;

/// אזור התוצאות של טאב החיפוש — רשימת גלילה אחת לשני המקורות: תוצאות
/// המנוע המובנה, ואיתן (כשספק חיצוני של תוסף פעיל) בלוק התוצאות החיצוניות
/// כ-sliver באותה רשימה ([ExternalSearchResultsSection]) — בלי חלוקת המסך
/// לשני מדורים נפרדים. גם מצבי הריק/טעינה/שגיאה של המנוע מרונדרים כאן,
/// כדי שהבלוק החיצוני יישאר חי ונראה גם כשלמנוע אין מה להציג.
class TantivySearchResults extends StatefulWidget {
  final SearchingTab tab;
  final VoidCallback? onEditSearch;

  /// האם לצרף חלונית תצוגה מקדימה לצד הרשימה (רק בפריסה הרחבה). כשפעילה
  /// (יחד עם ההגדרה), לחיצה אחת על תוצאה פותחת/סוגרת תצוגה מקדימה ולחיצה
  /// כפולה פותחת בעיון; אחרת לחיצה אחת פותחת בעיון כרגיל.
  final bool showPreviewPane;

  const TantivySearchResults({
    super.key,
    required this.tab,
    this.onEditSearch,
    this.showPreviewPane = false,
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

  /// חתימת החיפוש האחרון (שאילתה + קטגוריות) שעבורו כבר גללנו לראש הרשימה.
  /// משמשת להבחנה בין חיפוש חדש (חתימה משתנה → גלילה לראש) לבין טעינת המשך
  /// (אותה חתימה → שימור מיקום הגלילה).
  String? _lastSearchSignature;

  int _previewRequestId = 0;

  /// רוחב חי של חלונית התצוגה המקדימה בזמן גרירה (לא נשמר בין הפעלות).
  double? _previewPaneWidthOverride;

  Widget _buildInformativeEmptyState({
    required IconData icon,
    required String title,
    required String message,
    bool showEditButton = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          // הרכיב מוצג גם כשורה קומפקטית בתוך sliver (גובה לא חסום) —
          // בלי min ה-Column היה דורש גובה אינסופי.
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (showEditButton && widget.onEditSearch != null) ...[
              const SizedBox(height: 16),
              ActionButton.neutral(
                text: 'ערוך חיפוש',
                onPressed: widget.onEditSearch!,
                icon: FluentIcons.edit_24_regular,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    // אתחול החתימה מה-state הנוכחי כדי שהשינוי הראשון (למשל טעינת המשך בטאב
    // חיפוש משוחזר) לא ייחשב בטעות ל"חיפוש חדש" ויאפס את הגלילה.
    _lastSearchSignature = _searchSignature(context.read<SearchBloc>().state);
  }

  /// חתימת חיפוש: שאילתה + קטגוריות. זהה בין chunks של אותו חיפוש ובטעינת
  /// המשך, ומשתנה רק בחיפוש חדש (שינוי שאילתה או קטגוריה).
  String _searchSignature(SearchState state) =>
      '${state.searchQuery} ${state.currentFacets.join('')}';

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
    // במצב איחוד הרשימה נספרת בקבוצות — displayTotal מחזיר totalGroups.
    final hasMoreResults = state.results.length < state.displayTotal;

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
        negativeCustomSpacing: widget.tab.negativeSpacingValues,
        negativeAlternativeWords: widget.tab.negativeAlternativeWords,
        negativeSearchOptions: widget.tab.effectiveNegativeSearchOptions(
          query: context.read<SearchBloc>().state.negativeQuery,
        ),
      ),
    );
  }

  String _searchResultDedupeKey({
    required String title,
    required String reference,
    required int segment,
    required bool isPdf,
    required String filePath,
  }) {
    // filePath הוא מפתח האינדקס היציב ('uid:5'/'id:5' או נתיב PDF) — בלעדיו
    // תוצאה מספר אישי הייתה מתמקדת בטאב פתוח של ספר רשמי באותה כותרת.
    return 'search:${isPdf ? 'pdf' : 'text'}|$title|$reference|$segment|$filePath';
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

  /// לחיצה אחת על תוצאה: כשהתצוגה המקדימה פעילה — טוגל שלה (לחיצה חוזרת
  /// על אותה תוצאה סוגרת); אחרת — פתיחה בעיון כמו לחיצה כפולה.
  void _handleResultTap({
    required bool previewEnabled,
    required String title,
    required String reference,
    required int segment,
    required bool isPdf,
    required String filePath,
    required Map<String, Map<String, bool>> effectiveOptions,
  }) {
    if (previewEnabled) {
      _togglePreview(
        title: title,
        reference: reference,
        segment: segment,
        isPdf: isPdf,
        filePath: filePath,
      );
      return;
    }
    _openResultLocation(
      title: title,
      reference: reference,
      segment: segment,
      isPdf: isPdf,
      filePath: filePath,
      effectiveOptions: effectiveOptions,
    );
  }

  Future<void> _togglePreview({
    required String title,
    required String reference,
    required int segment,
    required bool isPdf,
    required String filePath,
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

    // אותו אימות זהות כמו בפתיחה בעיון — אינדקס לא מסונכרן לא מציג ספר שגוי.
    final resolution = await widget.tab.searchBloc.resolveBookForIndexedPath(
      filePath,
      indexedTitle: title,
    );
    if (!mounted || requestId != _previewRequestId) return;
    if (resolution.isStale) {
      UiSnack.showError(LibraryMessages.searchResultIndexOutOfDate);
      return;
    }
    final resolvedBook = resolution.book;
    final Book book = isPdf
        ? (resolvedBook is PdfBook
              ? resolvedBook
              : PdfBook(title: title, path: filePath))
        : switch (resolvedBook) {
            final TextBook value => value,
            final ConvertibleDocumentBook value => value.toTextBook(),
            _ => TextBook(title: title),
          };
    widget.tab.previewTarget.value = SearchPreviewTarget(
      book: book,
      title: title,
      reference: reference,
      segment: segment,
      isPdf: isPdf,
      filePath: filePath,
    );
  }

  /// פתיחת מיקום של תוצאה (או של תוצאה מאוחדת) בטאב קריאה — נתיב קוד
  /// משותף ללחיצה על כרטיס ראשי וללחיצה על שורת sibling בקבוצה מאוחדת.
  Future<void> _openResultLocation({
    required String title,
    required String reference,
    required int segment,
    required bool isPdf,
    required String filePath,
    required Map<String, Map<String, bool>> effectiveOptions,
  }) async {
    // המפתח משמר את זהות הספר (ספר אישי מול רשמי בעל אותה כותרת), והכותרת
    // מאמתת אותו: אינדקס שאינו מסונכרן ממפה את המפתח לספר אחר לגמרי.
    final resolution = await widget.tab.searchBloc.resolveBookForIndexedPath(
      filePath,
      indexedTitle: title,
    );
    if (!mounted) return;
    if (resolution.isStale) {
      UiSnack.showError(LibraryMessages.searchResultIndexOutOfDate);
      return;
    }
    final resolvedBook = resolution.book;

    // השאילתה שבוצעה בפועל — לא הטקסט שבתיבה, שהמשתמש עשוי היה לערוך בלי
    // לחפש; searchText שגוי היה גורר הדגשה של מחרוזת שהתוצאה לא נמצאה בה.
    final appliedQuery = widget.tab.searchBloc.state.searchQuery;
    final rawQuery = appliedQuery.trim().isNotEmpty
        ? appliedQuery
        : widget.tab.queryController.text;
    final configuration = widget.tab.searchBloc.state.configuration;

    // אין צורך בזיהוי "שאילתת רגקס": המנוע מנקה מטא-תווים
    // ב-sanitize_query לפני בניית השאילתה, כך שקלט המשתמש
    // לעולם אינו מפורש כתבנית — שאילתה בלי אפשרויות מיוחדות
    // היא תמיד ליטרלית וניתנת לחיפוש פשוט בתוך הספר.
    final inBookParameters = InBookSearchRouting.resolveForReadingTab(
      searchMode: configuration.searchMode,
      distance: configuration.distance,
      searchOptions: effectiveOptions,
      alternativeWords: widget.tab.alternativeWords,
      spacingValues: widget.tab.spacingValues,
      matchPolicy: configuration.matchPolicy,
    );
    final inBookMode = inBookParameters.searchMode;
    final inBookDistance = inBookParameters.distance;
    final inBookMatchPolicy = inBookParameters.matchPolicy;

    final openLeftPane =
        (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
        (Settings.getValue<bool>('key-default-sidebar-open') ?? false);

    if (isPdf) {
      final pageNumber = segment + 1;
      context.read<TabsBloc>().add(
        OpenOrFocusTab(
          PdfBookTab(
            book: resolvedBook is PdfBook
                ? resolvedBook
                : PdfBook(title: title, path: filePath),
            pageNumber: pageNumber,
            dedupeKey: _searchResultDedupeKey(
              title: title,
              reference: reference,
              segment: segment,
              isPdf: true,
              filePath: filePath,
            ),
            searchText: rawQuery,
            searchOptions: effectiveOptions,
            alternativeWords: widget.tab.alternativeWords,
            spacingValues: widget.tab.spacingValues,
            searchMode: inBookMode,
            searchDistance: inBookDistance,
            matchPolicy: inBookMatchPolicy,
            openLeftPane: openLeftPane,
            requiresStableLayout: true,
          ),
          targetTitle: reference,
          insertAdjacent: true,
        ),
      );
    } else {
      final textBook = switch (resolvedBook) {
        final TextBook book => book,
        final ConvertibleDocumentBook book => book.toTextBook(),
        _ => TextBook(title: title),
      };

      final dedupeKey = _searchResultDedupeKey(
        title: title,
        reference: reference,
        segment: segment,
        isPdf: false,
        filePath: filePath,
      );

      TextBookTab buildTextTab() => TextBookTab(
        book: textBook,
        index: segment,
        dedupeKey: dedupeKey,
        searchText: rawQuery,
        searchOptions: effectiveOptions,
        alternativeWords: widget.tab.alternativeWords,
        spacingValues: widget.tab.spacingValues,
        searchMode: inBookMode,
        searchDistance: inBookDistance,
        matchPolicy: inBookMatchPolicy,
        initialSearchResultLines: {segment},
        showPageShapeView: PageShapeSettingsManager.getViewModePreference(
          title,
        ),
        openLeftPane: openLeftPane,
      );

      // הגדרת "פורמט פתיחת תלמוד בבלי": תוצאת טקסט של מסכת בבלי נפתחת
      // מיידית כטאב טעינה, ומיפוי העמוד ל-PDF רץ בתוך הטאב עצמו.
      final target = await resolveTalmudBavliPdfBook(textBook);
      if (!mounted) return;

      final OpenedTab tab = target == null
          ? buildTextTab()
          : buildTalmudBavliResolvingTab(
              target: target,
              textIndex: segment,
              dedupeKey: dedupeKey,
              buildTextTab: (_) => buildTextTab(),
              buildPdfTab: (page, _) => PdfBookTab(
                book: target.pdfBook,
                pageNumber: page,
                dedupeKey: dedupeKey,
                searchText: rawQuery,
                searchOptions: effectiveOptions,
                alternativeWords: widget.tab.alternativeWords,
                spacingValues: widget.tab.spacingValues,
                searchMode: inBookMode,
                searchDistance: inBookDistance,
                matchPolicy: inBookMatchPolicy,
                openLeftPane: openLeftPane,
                requiresStableLayout: true,
              ),
            );

      context.read<TabsBloc>().add(
        OpenOrFocusTab(tab, targetTitle: reference, insertAdjacent: true),
      );
      unawaited(IndexFreshnessWarner.instance.warnIfContentDrifted(textBook));
    }
  }

  /// עוטף את אזור התוצאות בחלונית התצוגה המקדימה (בפריסה הרחבה בלבד).
  Widget _wrapWithPreviewPane(Widget mainContent, BoxConstraints constraints) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (p, c) => p.searchShowPreview != c.searchShowPreview,
      builder: (context, settings) {
        return ValueListenableBuilder<SearchPreviewTarget?>(
          valueListenable: widget.tab.previewTarget,
          builder: (context, target, _) {
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
                searchText: widget.tab.searchBloc.state.searchQuery,
                onOpenInReader: (_) {
                  final openTarget = widget.tab.previewTarget.value;
                  if (openTarget == null) return;
                  _openResultLocation(
                    title: openTarget.title,
                    reference: openTarget.reference,
                    segment: openTarget.segment,
                    isPdf: openTarget.isPdf,
                    filePath: openTarget.filePath,
                    effectiveOptions: widget.tab.effectiveSearchOptions(
                      query: widget.tab.searchBloc.state.searchQuery,
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constrains) {
        final resultsArea = _buildListenerArea();
        if (!widget.showPreviewPane) return resultsArea;
        return _wrapWithPreviewPane(resultsArea, constrains);
      },
    );
  }

  Widget _buildListenerArea() {
    return LayoutBuilder(
      builder: (context, constrains) {
        return BlocListener<SearchBloc, SearchState>(
          listenWhen: (previous, current) =>
              previous.isLoading != current.isLoading ||
              previous.results.length != current.results.length ||
              previous.totalResults != current.totalResults ||
              previous.searchQuery != current.searchQuery ||
              previous.currentFacets.join('|') !=
                  current.currentFacets.join('|'),
          listener: (context, state) {
            if (!state.isLoading) {
              _isAutoLoadInFlight = false;
            }

            // חיפוש חדש (שינוי שאילתה או קטגוריה) — מאפס את הגלילה לראש הרשימה.
            // טעינת המשך (LoadMore) שומרת על אותה חתימה ולכן לא נוגעת בגלילה,
            // וכך גם chunks עוקבים של אותו חיפוש (החתימה זהה).
            final signature = _searchSignature(state);
            if (signature != _lastSearchSignature) {
              _lastSearchSignature = signature;
              _previewRequestId++;
              // חיפוש חדש מחליף את התוצאות — התוצאה שבתצוגה המקדימה כבר
              // אינה ברשימה, לכן החלונית נסגרת.
              widget.tab.previewTarget.value = null;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _scrollController.hasClients) {
                  _scrollController.jumpTo(0);
                }
              });
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
      },
    );
  }

  /// שאילתת החיפוש האחרון שהושלם — מבחין בין "חיפוש חדש" (ספינר חוסם במקום
  /// התוצאות הישנות) לבין "טען עוד" באותה שאילתה (אסור להעלים את הקיימות).
  String _lastCompletedQuery = '';

  void _updateLastCompletedQuery(SearchState state) {
    if (!state.isLoading) {
      _lastCompletedQuery = state.searchQuery;
    }
  }

  bool _shouldShowBlockingLoader(SearchState state) {
    final currentQuery = state.searchQuery.trim();
    final lastQuery = _lastCompletedQuery.trim();
    return state.isLoading &&
        currentQuery.isNotEmpty &&
        currentQuery != lastQuery;
  }

  Widget _buildResultsContent(SearchState state, BoxConstraints constrains) {
    _updateLastCompletedQuery(state);
    // רשימת גלילה אחת לשני המקורות: הבלוק החיצוני הוא sliver באותו
    // CustomScrollView, ולכן כל מצבי המנוע (כולל ריק/טעינה/שגיאה) מרונדרים
    // אף הם כ-slivers — אחרת הבלוק החיצוני היה יורד מהעץ יחד עם הרשימה.
    return ValueListenableBuilder<ExternalSearchStatus?>(
      valueListenable: widget.tab.externalSearchStatus,
      builder: (context, externalStatus, _) {
        return BlocBuilder<SettingsBloc, SettingsState>(
          buildWhen: (p, c) => p.externalResultsFirst != c.externalResultsFirst,
          builder: (context, settings) {
            // ה-key מאפשר ל-Flutter לזהות את המדור כשהוא נודד בין ראש
            // הרשימה לסופה (החלפת "קודמות/מאוחרות"): בלעדיו ה-State היה
            // מפורק ונבנה מחדש — והמדור היה יורה חיפוש חיצוני חדש במקום
            // רק להחליף מקום.
            final externalSliver = ExternalSearchResultsSection(
              key: const ValueKey('external-results-sliver'),
              tab: widget.tab,
            );
            final engineSlivers = _buildEngineSlivers(
              state,
              hasExternal: externalStatus != null,
            );
            final scrollView = CustomScrollView(
              key: PageStorageKey(widget.tab),
              controller: _scrollController,
              // מיקום הבלוק החיצוני נשלט בהגדרה "קודמות/מאוחרות"
              // (ExternalResultsPositionControl): כברירת מחדל אחרי תוצאות
              // המנוע — כמו הקטגוריה "עוד מ<מקור>" בסוף עץ הקטגוריות.
              slivers: settings.externalResultsFirst
                  ? [externalSliver, ...engineSlivers]
                  : [...engineSlivers, externalSliver],
            );
            if (!state.resultsTruncated || state.results.isEmpty) {
              return scrollView;
            }
            // תוצאות חלקיות: השאילתה חרגה מתקציב איסוף-הטרמים במנוע, כך שרק
            // ההרחבות בעדיפות הגבוהה הוגשו. מציגים באנר קבוע מעל הרשימה.
            return Column(
              children: [
                _buildTruncatedBanner(context),
                Expanded(child: scrollView),
              ],
            );
          },
        );
      },
    );
  }

  /// מצב-מנוע שממלא את שארית המסך כשאין מקור חיצוני (המראה המקורי), ונשאר
  /// קומפקטי כשיש — אחרת הוא היה דוחק את הבלוק החיצוני אל מחוץ למסך.
  Widget _engineStateSliver(Widget child, {required bool hasExternal}) =>
      hasExternal
      ? SliverToBoxAdapter(child: child)
      : SliverFillRemaining(hasScrollBody: false, child: child);

  List<Widget> _buildEngineSlivers(
    SearchState state, {
    required bool hasExternal,
  }) {
    // חשוב: בטעינת-המשך אנחנו לא רוצים לפרק את הרשימה, אחרת הגלילה מתאפסת
    // לראש. לכן ספינר חוסם מוצג רק בחיפוש חדש או כשאין עדיין תוצאות.
    if (_shouldShowBlockingLoader(state) ||
        (state.isLoading && state.results.isEmpty)) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (state.searchQuery.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildInformativeEmptyState(
            icon: OtzariaIcons.search_24_regular,
            title: 'לא בוצע חיפוש',
            message: 'הקלד מילות חיפוש ולחץ על כפתור "חפש" כדי להתחיל.',
          ),
        ),
      ];
    }
    if (state.hasNoSelectedFacets) {
      return [
        _engineStateSliver(
          _buildInformativeEmptyState(
            icon: FluentIcons.filter_dismiss_24_regular,
            title: 'לא נבחרו קטגוריות',
            message: 'בחר קטגוריה אחת לפחות כדי לבצע חיפוש.',
          ),
          hasExternal: hasExternal,
        ),
      ];
    }
    if (state.results.isEmpty) {
      // הבחנה בין חיפוש ריק לגיטימי לבין כשל בחיפוש: אם errorMessage קיים,
      // תקלת מנוע (או FFI) הסתיימה בלי תוצאות — מציגים את ההודעה בצבע שגיאה
      // במקום "אין תוצאות" המטעה.
      if (state.errorMessage != null) {
        return [
          _engineStateSliver(
            Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  state.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
            hasExternal: hasExternal,
          ),
        ];
      }
      // חריגה מתקציב ההרחבות במנוע שהצטמצמה לאפס תוצאות: "אין תוצאות" מטעה
      // כאן, כי החיפוש לא נבדק במלואו.
      if (state.resultsTruncated) {
        return [
          _engineStateSliver(
            _buildInformativeEmptyState(
              icon: FluentIcons.warning_24_regular,
              title: 'הגעת למגבלת אפשרויות החיפוש',
              message:
                  'שילוב הגדרות ההרחבה (קידומות, סיומות, שגיאות כתיב וכד׳) יצר '
                  'יותר מדי אפשרויות עבור המנוע. נסה להוריד חלק מהגדרות החיפוש '
                  'או לצמצם את מילות החיפוש.',
              showEditButton: true,
            ),
            hasExternal: hasExternal,
          ),
        ];
      }
      return [
        _engineStateSliver(
          _buildInformativeEmptyState(
            icon: FluentIcons.document_search_24_regular,
            title: 'אין תוצאות',
            message:
                'נסה להרחיב קטגוריות, לשנות מצב חיפוש או לעדכן את מילות החיפוש.',
            showEditButton: true,
          ),
          hasExternal: hasExternal,
        ),
      ];
    }
    return [_buildEngineListSliver(state)];
  }

  Widget _buildEngineListSliver(SearchState state) {
    // (במצב איחוד הספירה היא בקבוצות — displayTotal).
    final hasMoreResults = state.results.length < state.displayTotal;
    final showInlineLoadingIndicator =
        state.isLoading && state.results.isNotEmpty && !hasMoreResults;
    final showLoadMoreButton = hasMoreResults;

    // אפשרויות אפקטיביות זהות לכל איטם ב-build הנוכחי -
    // מחשבים פעם אחת מחוץ ל-itemBuilder כדי לחסוך עבודה
    final effectiveOptions = widget.tab.effectiveSearchOptions(
      query: state.searchQuery,
    );

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList.builder(
        itemCount:
            state.results.length +
            ((showInlineLoadingIndicator || showLoadMoreButton) ? 1 : 0),
        itemBuilder: (context, index) {
          // האיטם האחרון מציג אינדיקטור טעינה בזמן הזרמה,
          // או כפתור pagination כשיש עוד תוצאות בשרת.
          if (index == state.results.length) {
            // כשהבלוק החיצוני יושב אחרי תוצאות המנוע, "מרחק מתחתית הגלילה"
            // כבר אינו מודד את סוף תוצאות המנוע — לכן עצם הופעת האיטם האחרון
            // בטווח הבנייה מפעילה טעינת-המשך (בנוסף ל-listener של הגלילה).
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _maybeLoadMore();
            });
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
                'טען תוצאות נוספות (${state.displayTotal - state.results.length})';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: ActionButton.neutral(
                    text: state.isLoading ? 'טוען...' : remainingText,
                    onPressed: () {
                      context.read<SearchBloc>().add(
                        LoadMoreResults(
                          customSpacing: widget.tab.spacingValues,
                          alternativeWords: widget.tab.alternativeWords,
                          searchOptions: effectiveOptions,
                          negativeCustomSpacing:
                              widget.tab.negativeSpacingValues,
                          negativeAlternativeWords:
                              widget.tab.negativeAlternativeWords,
                          negativeSearchOptions: widget.tab
                              .effectiveNegativeSearchOptions(
                                query: state.negativeQuery,
                              ),
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
              final previewEnabled =
                  widget.showPreviewPane && settingsState.searchShowPreview;
              String titleText = result.reference;
              String rawHtml = result.text;
              // Debug info removed for production
              if (settingsState.replaceHolyNames) {
                titleText = utils.replaceHolyNames(titleText);
                rawHtml = utils.replaceHolyNames(rawHtml);
              }

              final wrappedTitleText = _formatTitleForWrapping(titleText);

              // ההדגשה מגיעה מוכנה מהמנוע בתוך rawHtml, ולכן המפתח תלוי רק
              // ב-HTML ובסגנון התצוגה — לא בפרמטרי החיפוש.
              final snippetCacheKey = [
                result.id,
                result.segment,
                rawHtml.hashCode,
                settingsState.fontSize,
                settingsState.fontFamily,
                settingsState.replaceHolyNames,
                colorScheme.onSurface.toARGB32(),
              ].join('|');

              // Create the snippet using the new robust function
              // שימוש בגופן וגודל של המשתמש מההגדרות
              final snippetSpans = _snippetCache.putIfAbsent(
                snippetCacheKey,
                () {
                  if (_snippetCache.length > 300) {
                    _snippetCache.clear();
                  }
                  return SnippetBuilder.fromHighlightedHtml(
                    html: rawHtml,
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
                      color: colorScheme.error,
                    ),
                  );
                },
              );

              return ValueListenableBuilder<SearchPreviewTarget?>(
                valueListenable: widget.tab.previewTarget,
                builder: (context, previewTarget, child) {
                  final isPreviewed =
                      previewEnabled &&
                      previewTarget != null &&
                      previewTarget.matchesResult(
                        filePath: result.filePath,
                        segment: result.segment.toInt(),
                        isPdf: result.isPdf,
                      );
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isPreviewed
                            ? colorScheme.primary
                            : colorScheme.outline.withValues(alpha: 0.3),
                        width: isPreviewed ? 1.5 : 1,
                      ),
                      borderRadius: AppTokens.borderRadiusAll,
                    ),
                    child: child,
                  );
                },
                child: InkWell(
                  onTap: () => _handleResultTap(
                    previewEnabled: previewEnabled,
                    title: result.title,
                    reference: result.reference,
                    segment: result.segment.toInt(),
                    isPdf: result.isPdf,
                    filePath: result.filePath,
                    effectiveOptions: effectiveOptions,
                  ),
                  onDoubleTap: previewEnabled
                      ? () => _openResultLocation(
                          title: result.title,
                          reference: result.reference,
                          segment: result.segment.toInt(),
                          isPdf: result.isPdf,
                          filePath: result.filePath,
                          effectiveOptions: effectiveOptions,
                        )
                      : null,
                  borderRadius: AppTokens.borderRadiusAll,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // מספר התוצאה
                        Container(
                          constraints: const BoxConstraints(minWidth: 32),
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            borderRadius: AppTokens.borderRadiusAll,
                          ),
                          child: Center(
                            widthFactor: 1,
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
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
                              Row(
                                children: [
                                  if (result.isPdf)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: Icon(
                                        OtzariaIcons.book_pdf_24_regular,
                                        size: 16,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    ),
                                  Expanded(
                                    child: Text(
                                      result.title,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                      textAlign: TextAlign.right,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  // תגית מקור: מבדילה את תוצאות המנוע המובנה
                                  // מתוצאות ספק חיצוני שמוצגות באותו מסך. בלי
                                  // מדור חיצוני אין ממה להבדיל, והתגית הייתה
                                  // רק גוזלת רוחב משם הספר.
                                  ValueListenableBuilder<ExternalSearchStatus?>(
                                    valueListenable:
                                        widget.tab.externalSearchStatus,
                                    builder: (context, status, _) =>
                                        status == null
                                        ? const SizedBox(width: 4)
                                        : const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox(width: 8),
                                              SearchResultSourceTag(
                                                label: 'אוצריא',
                                              ),
                                              SizedBox(width: 4),
                                            ],
                                          ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      FluentIcons.copy_24_regular,
                                      size: 16,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                    tooltip: 'העתק טקסט',
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                    onPressed: () {
                                      final plainText = utils.stripHtmlIfNeeded(
                                        rawHtml,
                                      );
                                      // אותה התנהגות כמו העתקה ממסך הקריאה:
                                      // המקור והכותרת מצורפים לפי ההגדרות.
                                      // titleText כבר עבר החלפת שמות קודש.
                                      final bookName =
                                          settingsState.replaceHolyNames
                                          ? utils.replaceHolyNames(result.title)
                                          : result.title;
                                      final textToCopy =
                                          CopyUtils.formatTextWithHeaders(
                                            originalText: plainText,
                                            copyWithHeaders:
                                                settingsState.copyWithHeaders,
                                            copyHeaderFormat:
                                                settingsState.copyHeaderFormat,
                                            bookName: bookName,
                                            currentPath:
                                                CopyUtils.referencePath(
                                                  bookName: bookName,
                                                  reference: titleText,
                                                ),
                                          );
                                      Clipboard.setData(
                                        ClipboardData(text: textToCopy),
                                      );
                                      UiSnack.show(UiSnack.textCopied);
                                    },
                                  ),
                                ],
                              ),
                              if (wrappedTitleText.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    wrappedTitleText,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                    textAlign: TextAlign.right,
                                    softWrap: true,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              // הטקסט שנמצא
                              RichText(
                                textAlign: TextAlign.justify,
                                text: TextSpan(
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    height: 1.5,
                                  ),
                                  children: snippetSpans,
                                ),
                              ),
                              // תוצאות שאוחדו לכרטיס זה (במצב איחוד תוצאות)
                              if (result.mergedCount > 1)
                                _MergedSiblingsSection(
                                  mergedCount: result.mergedCount,
                                  siblings: result.merged,
                                  groupingMode: state.resultGrouping,
                                  onOpenSibling: (sibling) =>
                                      _openResultLocation(
                                        title: sibling.title,
                                        reference: sibling.reference,
                                        segment: sibling.segment.toInt(),
                                        isPdf: sibling.isPdf,
                                        filePath: sibling.filePath,
                                        effectiveOptions: effectiveOptions,
                                      ),
                                  onPreviewSibling: previewEnabled
                                      ? (sibling) => _togglePreview(
                                          title: sibling.title,
                                          reference: sibling.reference,
                                          segment: sibling.segment.toInt(),
                                          isPdf: sibling.isPdf,
                                          filePath: sibling.filePath,
                                        )
                                      : null,
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
      ),
    );
  }

  Widget _buildTruncatedBanner(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: colorScheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            FluentIcons.warning_24_regular,
            size: 18,
            color: colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'ייתכן שהתוצאות חלקיות: החיפוש רחב מדי ולכן הוצגו רק חלק '
              'מההתאמות. צמצמו את החיפוש (למשל הוסיפו אות או מילה).',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onTertiaryContainer,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

/// חיווי "תוצאות מאוחדות" בתחתית כרטיס תוצאה: שורת מונה עדינה שנפתחת
/// ללחיצה ומציגה את שאר חברות הקבוצה ([MergedSibling]) כשורות קומפקטיות.
/// לחיצה על שורה פותחת את המיקום בדיוק כמו לחיצה על תוצאה ראשית.
class _MergedSiblingsSection extends StatefulWidget {
  const _MergedSiblingsSection({
    required this.mergedCount,
    required this.siblings,
    required this.groupingMode,
    required this.onOpenSibling,
    this.onPreviewSibling,
  });

  /// גודל הקבוצה כולה (כולל הנציג המוצג בכרטיס).
  final int mergedCount;

  /// שאר חברות הקבוצה (עד התקרה במנוע — ייתכן ש-mergedCount גדול יותר).
  final List<MergedSibling> siblings;

  final ResultGroupingMode groupingMode;
  final ValueChanged<MergedSibling> onOpenSibling;

  /// כשהתצוגה המקדימה פעילה: לחיצה אחת על שורה עוברת לכאן (טוגל תצוגה)
  /// ולחיצה כפולה פותחת בעיון; null = לחיצה אחת פותחת בעיון כרגיל.
  final ValueChanged<MergedSibling>? onPreviewSibling;

  @override
  State<_MergedSiblingsSection> createState() => _MergedSiblingsSectionState();
}

class _MergedSiblingsSectionState extends State<_MergedSiblingsSection> {
  bool _expanded = false;

  String get _badgeText => switch (widget.groupingMode) {
    ResultGroupingMode.sameSection =>
      'נמצאו ${widget.mergedCount} תוצאות בטווח זה',
    ResultGroupingMode.identicalText => 'מופיע ב-${widget.mergedCount} מקומות',
    ResultGroupingMode.none => 'נמצאו ${widget.mergedCount} תוצאות',
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // כמה חברות קבוצה נחתכו בתקרת המנוע ואינן זמינות כקישורים.
    final hiddenCount = widget.mergedCount - widget.siblings.length - 1;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: AppTokens.borderRadiusAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 4.0,
                vertical: 2.0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    FluentIcons.layer_24_regular,
                    size: 16,
                    color: colorScheme.secondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _badgeText,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.secondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? FluentIcons.chevron_up_16_regular
                        : FluentIcons.chevron_down_16_regular,
                    size: 16,
                    color: colorScheme.secondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final sibling in widget.siblings)
                    InkWell(
                      onTap: () =>
                          (widget.onPreviewSibling ?? widget.onOpenSibling)
                              .call(sibling),
                      onDoubleTap: widget.onPreviewSibling != null
                          ? () => widget.onOpenSibling(sibling)
                          : null,
                      borderRadius: AppTokens.borderRadiusAll,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4.0,
                          vertical: 4.0,
                        ),
                        child: Text(
                          '${sibling.title} — ${sibling.reference}',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.primary,
                          ),
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  if (hiddenCount > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4.0,
                        vertical: 4.0,
                      ),
                      child: Text(
                        'ועוד $hiddenCount תוצאות…',
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
