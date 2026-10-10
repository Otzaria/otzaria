import 'dart:async';
import 'dart:convert';

import 'package:otzaria/theme/app_fonts.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/plugin_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/plugins/declarative/services/declarative_library_book_access.dart';
import 'package:otzaria/plugins/services/plugin_external_search_service.dart';
import 'package:otzaria/plugins/services/plugin_in_book_search_service.dart';
import 'package:otzaria/plugins/services/plugin_search_dialog_registry.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/external_search_status.dart';
import 'package:otzaria/search/models/external_search_summary.dart';
import 'package:otzaria/search/models/search_match_policy.dart';
import 'package:otzaria/search/models/search_preview_target.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/utils/snippet_builder.dart';
import 'package:otzaria/search/view/external_result_title_row.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/models/external_book_matches.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// מדור תוצאות ממקור חיצוני של תוסף (למשל היברובוקס) בטאב החיפוש המובנה.
///
/// הרכיב הוא sliver: הוא משתבץ בתוך רשימת הגלילה המאוחדת של
/// [TantivySearchResults] — מסך אחד לשני המקורות, בלי מדור נפרד עם גלילה
/// משלו. כשאין ספק פעיל הוא מתכווץ ל-sliver ריק.
///
/// המדור פעיל רק כשסומנה בדיאלוג החיפוש שורת תוסף שהצהירה `resultsProvider`
/// והתוסף נרשם כספק. השאילתה נשלחת לתוסף כאירוע ממוקד — אוצריא עצמה אינה
/// פונה לשירות החיפוש החיצוני. לחיצה על תוצאה פותחת את הספר במציג המובנה
/// (מקומית כשהקובץ קיים בתיקיית ההיברובוקס), עם עמודי ההתאמה כשהספק
/// חיפוש-בתוך-ספר זמין; כשחלונית התצוגה המקדימה פעילה, לחיצה אחת מציגה
/// אותה ולחיצה כפולה פותחת בעיון — כמו בתוצאות המנוע המובנה.
///
/// לצד עמודי התוצאות, הספק מצרף אינדקס תמציתי של כלל התוצאות עם קטגוריה
/// לכל ספר — הסיווג כולו (כולל עידון מול קטלוג השוואות, אם יש לספק כזה)
/// באחריות הספק; המדור רק מאמת את הנתיבים מול עץ הספרייה ומפרסם סיכום
/// ספירות דרך [SearchingTab.externalSearchSummary] — כך התוצאות החיצוניות
/// משתתפות בעץ הקטגוריות של החיפוש, ובחירת קטגוריה מסננת גם אותן (דפדוף
/// לפי ids).
class ExternalSearchResultsSection extends StatefulWidget {
  final SearchingTab tab;

  /// האם המסך מציג חלונית תצוגה מקדימה (פריסה רחבה בלבד) — כמו ב-
  /// [TantivySearchResults], שהוא גם המקור לערך.
  final bool showPreviewPane;

  const ExternalSearchResultsSection({
    super.key,
    required this.tab,
    this.showPreviewPane = false,
  });

  @override
  State<ExternalSearchResultsSection> createState() =>
      _ExternalSearchResultsSectionState();
}

/// נתיב הקטגוריה שמייצג facet שנבחר בעץ עבור סינון המדור: facet של ספר
/// (המקטע האחרון הוא מפתח ספר — 'id:'/'uid:'/'ext:'/נתיב קובץ, תמיד עם ':')
/// מתקפל לקטגוריית האם שלו. facet של ספר בדלי "עוד מ" נגמר ב-`#<id>` ולכן
/// אינו מתקפל — הוא מזוהה במורד הדרך כבחירה של ספר בודד.
@visibleForTesting
String externalFilterCategoryOf(String facet) {
  final segments = facet
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (segments.isNotEmpty && segments.last.contains(':')) {
    segments.removeLast();
  }
  return segments.isEmpty ? '/' : '/${segments.join('/')}';
}

/// מדיניות ההתאמה שנשלחת לספק — רק במצב המתקדם, כמו במנוע המובנה.
@visibleForTesting
SearchMatchPolicy externalMatchPolicyOf(SearchState state) =>
    state.isAdvancedSearchEnabled
    ? state.configuration.matchPolicy
    : SearchMatchPolicy.standard;

/// אימות נתיב קטגוריה שהספק צירף לרשומת אינדקס מול עץ הספרייה: נתיב קיים
/// מתקבל כמות שהוא; אחרת נופלים לקטגוריית-העל שלו אם היא קיימת; אחרת null
/// (הספר יוצג בדלי "עוד מ<מקור>").
@visibleForTesting
String? externalValidatedCategoryOf(
  String? suggested,
  Set<String> validPaths,
) {
  if (suggested == null) return null;
  if (validPaths.contains(suggested)) return suggested;
  final segments = suggested.split('/').where((s) => s.isNotEmpty);
  if (segments.isEmpty) return null;
  final top = '/${segments.first}';
  return validPaths.contains(top) ? top : null;
}

/// המזהים מתוך [index] שסיווגם ([categories]) תואם את בחירת הקטגוריות
/// [facets] (OR ביניהן; קטגוריה תואמת גם את צאצאיה). [otherFacet] הוא דלי
/// "עוד מ<מקור>" — תואם תוצאות ללא סיווג, ו-facet של ספר שתחתיו
/// (`<דלי>/#<id>`) תואם את אותו ספר בלבד.
@visibleForTesting
List<int> externalVisibleIdsFor({
  required List<ExternalSearchIndexEntry> index,
  required Map<int, String?> categories,
  required List<String> facets,
  required String? otherFacet,
}) {
  final pickedIds = <int>{};
  if (otherFacet != null) {
    for (final facet in facets) {
      final id = ExternalSearchSummary.bookIdIn(facet, otherFacet);
      if (id != null) pickedIds.add(id);
    }
  }

  bool matches(String? path) {
    for (final facet in facets) {
      if (facet == '/') return true;
      if (facet == otherFacet) {
        if (path == null) return true;
        continue;
      }
      if (path != null && (path == facet || path.startsWith('$facet/'))) {
        return true;
      }
    }
    return false;
  }

  return [
    for (final entry in index)
      if (pickedIds.contains(entry.id) || matches(categories[entry.id]))
        entry.id,
  ];
}

class _ExternalSearchResultsSectionState
    extends State<ExternalSearchResultsSection> {
  static const _pageSize = 20;
  static const _inBookMatchesTimeout = Duration(seconds: 15);

  /// ה-slot של הרכיב ברשימה המאוחדת הוא תמיד sliver — גם כשאין מה להציג.
  static const Widget _emptySliver = SliverToBoxAdapter(
    child: SizedBox.shrink(),
  );

  final List<ExternalSearchResult> _results = [];
  int _totalBooks = 0;
  int _totalHits = 0;
  bool _hasMore = false;
  bool _loading = false;
  String? _error;
  Object? _openingId;

  /// נתיב ה-PDF המקומי של תוצאה שכבר פוענחה — משמש לזיהוי "התוצאה הזו היא
  /// המוצגת כרגע בתצוגה המקדימה", שנשמרת לפי נתיב ולא לפי מזהה חיצוני.
  final Map<Object, String> _previewPaths = {};

  /// חתימת הבקשה האחרונה — מזהה מתי צריך חיפוש חדש ומסנן תשובות ישנות.
  String _fetchSignature = '';

  /// בחירת הקטגוריות בעץ — שינוי בה מסנן את המדור מחדש בלי חיפוש חדש.
  /// המפתח מחבר ב-NUL כי נתיבי קטגוריות מכילים רווחים.
  List<String> _filterFacets = const [];
  String _filterKey = '';

  /// דור הבקשות: כל איפוס (חיפוש חדש / שינוי סינון) מקדם אותו, ותשובות
  /// של דור ישן — כולל כאלה שכבר היו בטיסה — נזרקות.
  int _fetchGeneration = 0;

  /// אינדקס כלל התוצאות מהספק, והסיווג הסופי (אחרי עידון ואימות) לכל מזהה.
  List<ExternalSearchIndexEntry>? _index;
  Map<int, String?>? _categoryById;
  ExternalSearchSummary? _summary;

  /// במצב מסונן: מזהי התוצאות התואמות את הקטגוריות שנבחרו, בסדר האינדקס,
  /// וכמה מהם כבר התבקשו (המזהים החסרים במטמון הספק אינם חוזרים כשורות,
  /// ולכן העמוד הבא נספר לפי מזהים שנצרכו — לא לפי שורות שהוצגו).
  List<int>? _visibleIds;
  int _visibleConsumed = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncWithState(widget.tab.searchBloc.state);
    });
  }

  /// המדור הוא הכותב היחיד של [SearchingTab.externalSearchStatus], ולכן הוא
  /// מנקה אותו כשהוא יורד מהעץ (החלפת פריסה רחבה/צרה מרכיבה אותו מחדש) —
  /// אחרת שאר המסך היה ממשיך להתנהג כאילו יש מקור שני. סגירת טאב מפנה את
  /// ה-ValueNotifier רק 350ms אחרי פירוק העץ (ראו TabsBloc._disposeTabLater),
  /// כך שהכתיבה כאן קודמת לו.
  @override
  void dispose() {
    widget.tab.externalSearchStatus.value = null;
    super.dispose();
  }

  /// שם המקור לתגית שעל כל שורה — [resultsTitle] של שורת התוסף.
  String _sourceTag = '';

  /// שורת התוסף הפעילה: מסומנת בטאב, מצהירה resultsProvider והספק רשום.
  (String provider, String title)? _activeProvider(SearchState state) {
    final selections = state.configuration.pluginSearchSelections;
    for (final (pluginId, item)
        in PluginSearchDialogRegistry.instance.getAll()) {
      final provider = item.resultsProvider;
      if (provider == null) continue;
      if (selections['$pluginId/${item.id}'] != true) continue;
      if (!item.isVisibleIn(state.configuration.searchMode)) continue;
      if (!PluginExternalSearchService.instance.hasProvider(provider)) {
        continue;
      }
      return (provider, item.resultsTitle);
    }
    return null;
  }

  /// אפשרויות המילים האפקטיביות של הטאב, מנורמלות למצב החיפוש — אותה
  /// סמנטיקה כמו המנוע המובנה, כך ששני המקורות מחפשים לפי אותן הגדרות.
  Map<String, Map<String, bool>> _wordOptionsOf(SearchState state) =>
      SearchQueryBuilder.normalizeParametersForMode(
        state.configuration.searchMode,
        searchOptions: widget.tab.effectiveSearchOptions(
          query: state.searchQuery,
        ),
      ).searchOptions;

  /// המפה הגלובלית של הטאב (במצב "אפשרויות לכל המילים"), מנורמלת למצב.
  /// נשלחת לצד ה-wordOptions: מפתחות פר-מילה תלויים בטוקניזציה של המנוע
  /// (מקף מפצל מילה), וספק שמפרק את השאילתה אחרת נופל למפה הזו.
  Map<String, bool> _globalOptionsOf(SearchState state) =>
      widget.tab.useGlobalSearchOptions.value
      ? SearchQueryBuilder.normalizeGlobalOptionsForMode(
          state.configuration.searchMode,
          widget.tab.globalSearchOptions,
        )
      : const {};

  /// בחירת הקטגוריות הפעילה בעץ (בלי השורש ובלי ממדים) — הסינון של המדור.
  /// facet של ספר מתקפל לקטגוריית האם שלו.
  List<String> _selectedCategoryFacets(SearchState state) =>
      FacetHelper.categoryFacetsOf(state.currentFacets)
          .map(externalFilterCategoryOf)
          .where((facet) => facet != '/')
          .toSet()
          .toList()
        ..sort();

  /// מפרסם את מצב המדור לשורת המונים שבראש הטאב — המקום היחיד שבו ספירות
  /// המקור החיצוני וההתקדמות שלו מוצגות.
  void _publishStatus() {
    if (_fetchSignature.isEmpty || _sourceTag.isEmpty) {
      widget.tab.externalSearchStatus.value = null;
      return;
    }
    widget.tab.externalSearchStatus.value = ExternalSearchStatus(
      sourceTitle: _sourceTag,
      loading: _loading,
      books: _totalBooks,
      hits: _totalHits,
      ofTotalBooks: _filterActive ? _summary?.totalBooks : null,
      failed: _error != null,
    );
  }

  void _syncWithState(SearchState state) {
    final active = _activeProvider(state);
    if (active != null) _sourceTag = active.$2;
    final query = state.searchQuery.trim();
    final signature = active == null || query.isEmpty
        ? ''
        : '${active.$1} $query '
              '${state.configuration.searchMode.name} ${state.distance} '
              '${jsonEncode(externalMatchPolicyOf(state).toJson())} '
              '${jsonEncode(_globalOptionsOf(state))} '
              '${jsonEncode(_wordOptionsOf(state))}';
    final filterFacets = signature.isEmpty
        ? const <String>[]
        : _selectedCategoryFacets(state);
    // נתיבי קטגוריות מכילים רווחים — מפתח ההשוואה מחבר בתו שאינו חוקי בנתיב.
    final filterKey = filterFacets.join('\u0000');
    if (signature == _fetchSignature) {
      if (filterKey != _filterKey) {
        _filterFacets = filterFacets;
        _filterKey = filterKey;
        _applyFilterAndRefetch(state, active);
      }
      return;
    }
    _fetchSignature = signature;
    _filterFacets = filterFacets;
    _filterKey = filterKey;
    _fetchGeneration++;
    _index = null;
    _categoryById = null;
    _visibleIds = null;
    _visibleConsumed = 0;
    _summary = null;
    widget.tab.externalSearchSummary.value = null;
    setState(() {
      _results.clear();
      _totalBooks = 0;
      _totalHits = 0;
      _hasMore = false;
      _error = null;
      _loading = signature.isNotEmpty;
    });
    _publishStatus();
    if (signature.isNotEmpty) {
      unawaited(_fetch(state, active!.$1, reset: true));
    }
  }

  /// מחשב מחדש את המזהים הנראים לפי הסינון ומביא את העמוד הראשון שלהם.
  /// סינון בלי אף תוצאה תואמת מציג "לא נמצאו תוצאות" בלי לפנות לספק.
  void _applyFilterAndRefetch(
    SearchState state,
    (String, String)? active,
  ) {
    if (active == null) return;
    _recomputeVisibleIds();
    _fetchGeneration++;
    _visibleConsumed = 0;
    final visible = _visibleIds;
    setState(() {
      _results.clear();
      _error = null;
      _hasMore = false;
      if (visible != null) {
        _totalBooks = visible.length;
        _totalHits = _hitsOf(visible);
      }
      _loading = visible == null || visible.isNotEmpty;
    });
    _publishStatus();
    if (visible == null || visible.isNotEmpty) {
      unawaited(_fetch(state, active.$1, reset: true));
    }
  }

  /// הסינון פעיל רק כשנבחרו קטגוריות ויש סיווג מוכן.
  bool get _filterActive => _filterFacets.isNotEmpty && _visibleIds != null;

  void _recomputeVisibleIds() {
    final index = _index;
    final categories = _categoryById;
    if (_filterFacets.isEmpty || index == null || categories == null) {
      _visibleIds = null;
      return;
    }
    _visibleIds = externalVisibleIdsFor(
      index: index,
      categories: categories,
      facets: _filterFacets,
      otherFacet: _summary?.otherCategoryFacet,
    );
  }

  Future<void> _fetch(
    SearchState state,
    String provider, {
    required bool reset,
  }) async {
    final generation = _fetchGeneration;
    final signature = _fetchSignature;
    final offset = reset ? 0 : _results.length;
    final filtered = _filterActive;
    final visibleIds = _visibleIds;
    final idsOffset = reset ? 0 : _visibleConsumed;
    final idsSlice = filtered && visibleIds != null
        ? visibleIds.skip(idsOffset).take(_pageSize).toList()
        : null;
    // עדכון חלקי מחליף את חלון העמוד הנוכחי; הספירות הן רף-תחתון עד
    // לתשובה הסופית, וחיווי הטעינה נשאר דלוק.
    void applyPage(ExternalSearchPage page, {required bool done}) {
      if (!mounted || generation != _fetchGeneration) return;
      // אינדקס בלי סיווג מוכן (גם אחרי ניסיון שנכשל) — מסווגים (מחדש).
      if (page.index != null && _categoryById == null) {
        _index = page.index;
        _classifyIndex(signature);
        // סיווג יכול להפעיל סינון שהמתין לו, ואז כבר רצה בקשה חדשה — העמוד
        // הלא-מסונן שבידינו שייך לדור הקודם, וכתיבתו הייתה מציגה את תוצאות
        // החיפוש כולו עם ספירות מסוננות ובלי חיווי טעינה.
        if (!mounted || generation != _fetchGeneration) return;
      }
      setState(() {
        _results.removeRange(
          offset > _results.length ? _results.length : offset,
          _results.length,
        );
        _results.addAll(page.results);
        if (idsSlice != null) {
          // במצב מסונן הספירות מקומיות — הספק מחזיר את סיכומי החיפוש כולו.
          _totalBooks = visibleIds!.length;
          _totalHits = _hitsOf(visibleIds);
          if (done) _visibleConsumed = idsOffset + idsSlice.length;
          _hasMore = done && _visibleConsumed < visibleIds.length;
        } else {
          _totalBooks = page.totalBooks;
          _totalHits = page.totalHits;
          _hasMore = done && page.hasMore && page.results.isNotEmpty;
        }
        _loading = !done;
      });
      _publishStatus();
    }

    try {
      final page = await PluginExternalSearchService.instance.search(
        provider: provider,
        query: state.searchQuery.trim(),
        mode: state.configuration.searchMode.name,
        distance: state.distance,
        matchPolicy: externalMatchPolicyOf(state),
        offset: offset,
        limit: _pageSize,
        ids: idsSlice,
        options: _globalOptionsOf(state),
        wordOptions: _wordOptionsOf(state),
        onUpdate: (partial) => applyPage(partial, done: false),
      );
      applyPage(page, done: true);
    } catch (error) {
      if (!mounted || generation != _fetchGeneration) return;
      setState(() {
        _loading = false;
        _error = error is TimeoutException
            ? 'החיפוש החיצוני לא ענה בזמן'
            : error.toString().replaceFirst('Bad state: ', '');
      });
      _publishStatus();
    }
  }

  int _hitsOf(List<int> ids) {
    final index = _index;
    if (index == null) return 0;
    final idSet = ids.toSet();
    var total = 0;
    for (final entry in index) {
      if (idSet.contains(entry.id)) total += entry.hits;
    }
    return total;
  }

  /// מסווג את האינדקס: נתיבי הקטגוריות שהספק צירף (הסיווג עצמו נעשה בצד
  /// הספק — לאוצריא אין ידע ייחודי למקור) מאומתים מול עץ הספרייה, עם
  /// נפילה לקטגוריית-העל. התוצאה מתפרסמת לעץ הסינון של הטאב.
  void _classifyIndex(String signature) {
    final index = _index;
    if (index == null) return;
    final library = context.read<LibraryBloc>().state.library;
    final active = _activeProvider(widget.tab.searchBloc.state);
    if (library == null || active == null) {
      // אין עדיין ספרייה — משאירים את המדור בלי אינדקס כדי שהעותק שמגיע
      // עם התשובה הסופית ינסה לסווג שוב.
      _index = null;
      return;
    }
    if (signature != _fetchSignature) return;

    final validPaths = <String>{
      for (final category in library.getAllCategories()) category.path,
    };

    final categories = <int, String?>{};
    final counts = <String, int>{};
    final namedOther = <ExternalSearchBook>[];
    var other = 0;
    for (final entry in index) {
      final path = externalValidatedCategoryOf(entry.categoryPath, validPaths);
      categories[entry.id] = path;
      if (path == null) {
        other += 1;
        final title = entry.title;
        // ספר בלי שם אינו יכול להיות שורה בעץ; הוא עדיין נספר בדלי.
        if (title != null) {
          namedOther.add(
            ExternalSearchBook(id: entry.id, title: title, hits: entry.hits),
          );
        }
      } else {
        counts[path] = (counts[path] ?? 0) + 1;
      }
    }
    var totalHits = 0;
    for (final entry in index) {
      totalHits += entry.hits;
    }
    // שורות הדלי בעץ הן הרשימה הזו, ואין להן סדר קטלוגי כמו לספרי הספרייה —
    // לכן העשיר במופעים ראשון, ובתיקו לפי שם, כדי שהסדר יהיה יציב וקריא.
    namedOther.sort((a, b) {
      final byHits = b.hits.compareTo(a.hits);
      return byHits != 0 ? byHits : a.title.compareTo(b.title);
    });

    _categoryById = categories;
    _summary = ExternalSearchSummary(
      provider: active.$1,
      sourceTitle: active.$2,
      totalBooks: index.length,
      totalHits: totalHits,
      categoryBookCounts: counts,
      otherBooks: other,
      namedOtherBooks: namedOther,
    );
    widget.tab.externalSearchSummary.value = _summary;

    // סינון שהמתין לסיווג (קטגוריה נבחרה לפני שהאינדקס הגיע) נכנס עכשיו.
    if (_filterKey.isNotEmpty) {
      _applyFilterAndRefetch(widget.tab.searchBloc.state, active);
    }
  }

  void _loadMore(SearchState state) {
    final active = _activeProvider(state);
    if (active == null || _loading) return;
    setState(() => _loading = true);
    _publishStatus();
    unawaited(_fetch(state, active.$1, reset: false));
  }

  /// זהות הספר של תוצאה חיצונית, כפי שמסלולי הפענוח הדקלרטיביים מצפים לה.
  Map<String, dynamic> _identityOf(ExternalSearchResult result) => {
    'external': {'provider': result.provider, 'id': result.externalId},
  };

  /// לוכדים את התלויות לפני נקודות ה-await — ה-context עלול להתפרק בינתיים.
  DeclarativeLibraryBookAccess _bookAccess() =>
      DeclarativeLibraryBookAccess.otzaria(
        BookOpenCoordinator(
          tabsBloc: context.read<TabsBloc>(),
          historyBloc: context.read<HistoryBloc>(),
          navigationBloc: context.read<NavigationBloc>(),
        ),
      );

  /// לחיצה אחת: כשהתצוגה המקדימה פעילה — טוגל שלה, אחרת פתיחה בעיון.
  /// אותה התנהגות כמו בכרטיס תוצאה של המנוע המובנה.
  void _handleResultTap(
    ExternalSearchResult result,
    SearchState state,
    bool previewEnabled,
  ) {
    unawaited(
      previewEnabled
          ? _togglePreview(result, state)
          : _openResult(result, state),
    );
  }

  /// עמוד ההתאמה כמקטע של [SearchPreviewTarget] — מבוסס-0 בספר PDF.
  int _previewSegment(ExternalSearchResult result) =>
      (result.firstPage ?? 1) - 1;

  Future<void> _togglePreview(
    ExternalSearchResult result,
    SearchState state,
  ) async {
    final segment = _previewSegment(result);
    final knownPath = _previewPaths[result.externalId];
    final current = widget.tab.previewTarget.value;
    if (knownPath != null &&
        current != null &&
        current.matchesResult(
          filePath: knownPath,
          segment: segment,
          isPdf: true,
        )) {
      widget.tab.previewTarget.value = null;
      return;
    }
    if (_openingId != null) return;
    setState(() => _openingId = result.externalId);
    final access = _bookAccess();
    try {
      final book = (await access.findUniqueBooks([_identityOf(result)])).single;
      if (!mounted) return;
      // ספר שלא הורד הוא קישור לאתר המקור בלבד — אין לו תוכן מקומי להצגה,
      // ולכן לחיצה עליו נשארת פתיחה ישירה גם כשהתצוגה המקדימה פעילה.
      if (book is! PdfBook) {
        await _openViaAccess(result, state, access);
        return;
      }
      _previewPaths[result.externalId] = book.path;
      widget.tab.previewTarget.value = SearchPreviewTarget(
        book: book,
        title: result.title,
        reference: result.title,
        segment: segment,
        isPdf: true,
        filePath: book.path,
        openInReader: () => unawaited(
          _openResult(result, widget.tab.searchBloc.state),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  Future<void> _openResult(
    ExternalSearchResult result,
    SearchState state,
  ) async {
    if (_openingId != null) return;
    setState(() => _openingId = result.externalId);
    final access = _bookAccess();
    try {
      await _openViaAccess(result, state, access);
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  /// פתיחת הספר בפועל, בהנחה שחיווי הטעינה כבר הודלק על ידי הקורא.
  Future<void> _openViaAccess(
    ExternalSearchResult result,
    SearchState state,
    DeclarativeLibraryBookAccess access,
  ) async {
    final query = state.searchQuery.trim();
    // עמודי ההתאמה מגיעים מספק החיפוש-בתוך-ספר של התוסף; כישלון או
    // איטיות אינם מונעים את פתיחת הספר — פותחים בלעדיהם.
    ExternalBookMatches? matches;
    if (PluginInBookSearchService.instance.hasProvider(result.provider)) {
      try {
        matches = await PluginInBookSearchService.instance
            .search(
              provider: result.provider,
              externalId: result.externalId,
              query: query,
            )
            .timeout(_inBookMatchesTimeout);
      } catch (_) {
        matches = null;
      }
    }
    final opened = await access.openUnique(
      _identityOf(result),
      index: result.firstPage ?? 1,
      searchQuery: query,
      externalMatches: matches,
    );
    if (!opened) {
      UiSnack.show(PluginMessages.externalBookNotFound);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SearchBloc, SearchState>(
      bloc: widget.tab.searchBloc,
      listener: (context, state) => _syncWithState(state),
      builder: (context, state) {
        final active = _activeProvider(state);
        if (active == null || state.searchQuery.trim().isEmpty) {
          return _emptySliver;
        }
        _sourceTag = active.$2;
        return _buildSection(context, state);
      },
    );
  }

  /// המדור מציג תוצאות בלבד: המקור, ההתקדמות והספירות שלו מוצגים בשורת
  /// המונים שבראש הטאב (ראו [ExternalSearchStatus]).
  Widget _buildSection(BuildContext context, SearchState state) =>
      _buildBody(context, state);

  /// sliver ריק כשאין מה להראות — טעינה ראשונה (החיווי בשורת המונים) או
  /// מדור ריק לפני שהתקבלה תשובה כלשהי; אחרת נשאר רווח מת ברשימה.
  Widget _buildBody(BuildContext context, SearchState state) {
    if (_error != null) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              ActionButton.ghost(
                text: 'נסה שוב',
                onPressed: () {
                  _fetchSignature = '';
                  _syncWithState(state);
                },
              ),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      // בטעינה החיווי יושב בשורת המונים; לפני החיפוש הראשון (חתימה ריקה)
      // אין עדיין מה לדווח עליו.
      if (_loading || _fetchSignature.isEmpty) return _emptySliver;
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text('$_sourceTag: לא נמצאו תוצאות'),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      sliver: SliverList.builder(
        itemCount: _results.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _results.length) {
            return Center(
              child: ActionButton.ghost(
                onPressed: _loading ? null : () => _loadMore(state),
                text: _loading
                    ? 'טוען…'
                    : 'טען תוצאות נוספות (${_totalBooks - _results.length})',
              ),
            );
          }
          return BlocBuilder<SettingsBloc, SettingsState>(
            builder: (context, settings) =>
                _buildResultRow(context, state, _results[index], settings),
          );
        },
      ),
    );
  }

  /// כרטיס תוצאה באותה שפה עיצובית של תוצאות הספרייה במסך הזה: מסגרת
  /// מעוגלת, ריווח פנימי נדיב ושורת קטע בגובה קריא — ולא ListTile צפוף.
  ///
  /// גזיר הטקסט נצבע בגופן הספרים של המשתמש ([SettingsState.fontFamily]
  /// ובגודלו), כמו גזירי המנוע המובנה — אחרת אותה שאילתה מוצגת בשני גופנים
  /// שונים באותו מסך.
  Widget _buildResultRow(
    BuildContext context,
    SearchState state,
    ExternalSearchResult result,
    SettingsState settings,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final opening = _openingId == result.externalId;
    final enabled = _openingId == null || opening;
    final previewEnabled = widget.showPreviewPane && settings.searchShowPreview;
    return ValueListenableBuilder<SearchPreviewTarget?>(
      valueListenable: widget.tab.previewTarget,
      builder: (context, previewTarget, child) {
        final previewedPath = _previewPaths[result.externalId];
        final isPreviewed =
            previewEnabled &&
            previewedPath != null &&
            previewTarget != null &&
            previewTarget.matchesResult(
              filePath: previewedPath,
              segment: _previewSegment(result),
              isPdf: true,
            );
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            border: Border.all(
              color: isPreviewed
                  ? cs.primary
                  : cs.outline.withValues(alpha: 0.3),
              width: isPreviewed ? 1.5 : 1,
            ),
            borderRadius: AppTokens.borderRadiusAll,
          ),
          child: child,
        );
      },
      child: InkWell(
        onTap: enabled
            ? () => _handleResultTap(result, state, previewEnabled)
            : null,
        onDoubleTap: enabled && previewEnabled
            ? () => unawaited(_openResult(result, state))
            : null,
        borderRadius: AppTokens.borderRadiusAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              opening
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      OtzariaIcons.otzaria_icon_2_page_24_regular,
                      size: 20,
                      color: cs.primary,
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExternalResultTitleRow(
                      title: result.title,
                      hitCount: result.hitCount,
                      sourceTag: _sourceTag,
                      copyText: result.snippet,
                    ),
                    // result.meta (מחבר · מקום · שנה) אינו מוצג: כרטיס תוצאה
                    // של המנוע המובנה אינו נושא פרטי ספר, והשורה הזו רק
                    // הרחיקה את הגזיר מהכותרת.
                    if (result.snippet != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: RichText(
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.justify,
                          text: TextSpan(
                            children: SnippetBuilder.highlightLiteral(
                              plainText: result.snippet!,
                              query: state.searchQuery.trim(),
                              defaultStyle: TextStyle(
                                fontSize: settings.fontSize,
                                fontFamily: AppFonts.renderFontFamily(
                                  settings.fontFamily,
                                ),
                                color: cs.onSurface,
                                height: 1.5,
                              ),
                              // אותה הדגשה כמו בגזירי המנוע המובנה: מילה
                              // אדומה ומודגשת, ולא צביעת רקע.
                              highlightStyle: TextStyle(
                                fontSize: settings.fontSize + 2,
                                fontFamily: AppFonts.renderFontFamily(
                                  settings.fontFamily,
                                ),
                                height: 1.5,
                                fontWeight: FontWeight.bold,
                                color: cs.error,
                              ),
                            ),
                          ),
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
  }
}
