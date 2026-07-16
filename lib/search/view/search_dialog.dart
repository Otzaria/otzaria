import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/search/search_scope_preferences.dart';
import 'package:otzaria/search/view/category_tree_selector.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/saved_alternatives_store.dart';
import 'package:otzaria/search/utils/category_query_parser.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/search/view/enhanced_search_field.dart';
import 'package:otzaria/search/view/search_dimension_filters.dart';
import 'package:otzaria/search/view/advanced_search_controls.dart';
import 'package:otzaria/search/view/full_text_settings_widgets.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/widgets/feedback/indexing_warning.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/tour/tour_target_keys.dart';

class SearchDialogResult {
  const SearchDialogResult({
    required this.query,
    required this.searchOptions,
    required this.alternativeWords,
    required this.spacingValues,
    required this.searchMode,
    required this.distance,
  });

  final String query;
  final Map<String, Map<String, bool>> searchOptions;
  final Map<int, List<String>> alternativeWords;
  final Map<String, String> spacingValues;
  final SearchMode searchMode;
  final int distance;
}

/// דיאלוג חיפוש מתקדם - מכיל את כל פקדי החיפוש וההגדרות
/// כשמבצעים חיפוש, הדיאלוג נסגר ונפתחת לשונית תוצאות
class SearchDialog extends StatefulWidget {
  final SearchingTab? existingTab;

  /// טאב תוצאות חי לעריכה: הדיאלוג נפתח עם כל הפרמטרים שלו, ובאישור
  /// החיפוש מוחל עליו במקום (ללא יצירת טאב חדש).
  final SearchingTab? editTab;
  final Function(
    String query,
    Map<String, Map<String, bool>> searchOptions,
    Map<int, List<String>> alternativeWords,
    Map<String, String> spacingValues,
    SearchMode searchMode,
    int distance,
  )? onSearch;
  final String? bookTitle;
  final bool returnResultOnSubmit;
  final SearchMode? initialSearchMode;

  const SearchDialog(
      {super.key,
      this.existingTab,
      this.editTab,
      this.onSearch,
      this.bookTitle,
      this.returnResultOnSubmit = false,
      this.initialSearchMode});

  @override
  State<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<SearchDialog> {
  late SearchingTab _searchTab;
  FocusRestorer? _focusRestorer;
  bool _showIndexInProgressWarning = false;
  bool _searchAllCategories = true;
  Set<String> _manualFacets = {};

  /// ה-facets הממדיים שנבחרו בדיאלוג (תקופה/מחבר/ספרי יסוד) — מצטרפים
  /// ב-AND לבחירת הקטגוריות בעת שיגור החיפוש.
  Set<String> _dimensionFacets = {};
  final ValueNotifier<bool> _advancedControlsHasFocus = ValueNotifier(false);
  final MenuController _historyMenuController = MenuController();
  late final VoidCallback _queryListener;
  Set<String> _selectedCategoryFacets = {'/'}; // ברירת מחדל: הכל
  late final bool _ownsSearchTab;

  bool get _usesStagedSubmit =>
      widget.onSearch != null ||
      widget.returnResultOnSubmit ||
      widget.editTab != null;

  /// תיבות "ניקוד/טעמים" (ברשת אפשרויות החיפוש המתקדם) מוצגות רק במסלולים
  /// שמריצים חיפוש אינדקס (טאב חדש או עריכת טאב קיים). במסלולי החזרת-תוצאה
  /// (חיפוש בתוך ספר טקסט/PDF) החיפוש רץ מקומית על הספר הפתוח ואינו תומך
  /// בהתאמת ניקוד — הצגת הפקד שם הייתה בחירה שנבלעת בלי השפעה.
  bool get _supportsVocalizedSearch =>
      widget.onSearch == null && !widget.returnResultOnSubmit;

  @override
  void initState() {
    super.initState();

    // יצירת טאב עם ההקלדה האחרונה
    _ownsSearchTab = widget.existingTab == null;
    if (widget.existingTab != null) {
      _searchTab = widget.existingTab!;
    } else if (widget.editTab != null) {
      // עריכה: עובדים על עותק — הטאב החי מתעדכן רק באישור החיפוש
      _searchTab = SearchingTab.clone(widget.editTab!);
    } else {
      final lastTyping =
          Settings.getValue<String>('key-last-search-typing') ?? '';

      // חיפוש חדש נפתח במצב ברירת המחדל (חיפוש רגיל/מדויק) עם המרווח
      // השמור; שינוי מצב או מרווח נשמר לסשן הנוכחי בלבד — כמו אפשרויות
      // החיפוש המתקדם.
      final searchMode =
          widget.initialSearchMode ?? SearchDefaults.initialModeForNewSearch();

      _searchTab = SearchingTab(
        "חיפוש",
        lastTyping,
        initialConfiguration: SearchConfiguration(
          searchMode: searchMode,
          distance: searchMode == SearchMode.fuzzy
              ? 2
              : SearchDefaults.initialDistanceForNewSearch(),
        ),
      );

      // חיפוש חדש נפתח עם אפשרויות ברירת המחדל של המצב שבו הוא נפתח
      // (או מצב הסשן הנוכחי) — לכל מצב חיפוש ברירות מחדל משלו
      _searchTab.globalSearchOptions.addAll(_initialOptionsForMode(searchMode));
    }

    final persisted = SearchScopePreferences.load();
    final initialScopeFacets = _searchTab.searchBloc.state.searchScopeFacets;
    // ה-scope של הטאב עשוי לשאת גם facets ממדיים (תקופה/מחבר/ספרי יסוד) —
    // מפצלים: הקטגוריות מזינות את עץ הבחירה, הממדים את פקדי הממדים.
    final initialCategories = FacetHelper.categoryFacetsOf(initialScopeFacets);
    final initialDimensions =
        FacetHelper.dimensionFacetsOf(initialScopeFacets).toSet();
    _dimensionFacets = initialDimensions.isNotEmpty
        ? initialDimensions
        : SearchScopePreferences.loadDimensionFacets();

    if (initialCategories.isNotEmpty) {
      // הטאב מגדיר scope מפורש — כבד אותו תמיד
      final isExplicitAll = initialCategories.contains('/');
      _searchAllCategories = isExplicitAll;
      _manualFacets = isExplicitAll
          ? Set<String>.from(persisted.manualFacets)
          : Set<String>.from(initialCategories);
    } else {
      _searchAllCategories = persisted.searchAllCategories;
      _manualFacets = Set<String>.from(persisted.manualFacets);
    }
    _selectedCategoryFacets =
        _searchAllCategories ? {'/'} : Set<String>.from(_manualFacets);

    // בדיקה אם האינדקס בתהליך בנייה - האזהרה ניתנת לסגירה ואינה חוסמת חיפוש
    final indexingState = context.read<IndexingBloc>().state;
    _showIndexInProgressWarning = indexingState is IndexingInProgress;

    // מאזין לשינויים בתיבת החיפוש כדי לעדכן את האפשרויות ולשמור את ההקלדה
    _queryListener = () {
      if (!mounted) return;
      // שמירת ההקלדה הנוכחית (לא בעריכה — כדי לא לדרוס את ההקלדה האחרונה)
      if (widget.editTab != null) return;
      Settings.setValue<String>(
        'key-last-search-typing',
        _searchTab.queryController.text,
      );
    };
    _searchTab.queryController.addListener(_queryListener);

    // בקשת פוקוס לתיבת החיפוש + רישום כ-active restorer לשחזור לאחר אירועי חלון
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchTab.searchFieldFocusNode.requestFocus();
        _focusRestorer = FocusRepository().registerActiveRestorer(
          restore: () {
            if (mounted) _searchTab.searchFieldFocusNode.requestFocus();
          },
          canRestore: () =>
              mounted &&
              _searchTab.searchFieldFocusNode.canRequestFocus &&
              (ModalRoute.of(context)?.isCurrent ?? false),
        );
      }
    });
  }

  Widget _buildIndexWarning() {
    return IndexingWarningContainer(
      inProgressDismissed: !_showIndexInProgressWarning,
      onDismiss: () => setState(() => _showIndexInProgressWarning = false),
    );
  }

  /// אפשרויות המילה של החיפוש הרגיל (מדויק): שגיאות כתיב, קידומות/סיומות
  /// דקדוקיות, כתיב מלא/חסר וחלק ממילה — מוחלות גלובלית על כל מילות
  /// השאילתה. בקשה עם אפשרות פעילה רצה בפועל דרך המסלול המתקדם של המנוע
  /// (ראה gateway), כך שאין צורך בשינוי מנוע.
  Widget _buildExactOptionsRow() {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final key in SearchQueryBuilder.exactWordOptionKeys)
            FilterChip(
              label: Text(key),
              visualDensity: VisualDensity.compact,
              selected: _searchTab.globalSearchOptions[key] ?? false,
              onSelected: (selected) {
                setState(() {
                  _searchTab.globalSearchOptions[key] = selected;
                  // במצב הרגיל אין עורך פר-מילה — הסימון תמיד גלובלי.
                  _searchTab.useGlobalSearchOptions.value = true;
                });
                _searchTab.searchOptionsChanged.value++;
              },
            ),
        ],
      ),
    );
  }

  /// ברירות המחדל של החיפוש הרגיל (מדויק) — תפריט נפתח כמו במצב המתקדם,
  /// אבל עצמאי לחלוטין: קובע רק את ברירות המחדל של החיפוש הרגיל, ורק
  /// לפרמטרים הקיימים בו (חמש אפשרויות המילה והמרווח בין מילים). ברירות
  /// המחדל של המצב המתקדם נקבעות בתפריט המקביל שבמסך המתקדם.
  Widget _buildExactDefaultsRow(SearchState state) {
    final defaults = SearchDefaults.loadExactDefaults();
    final savedDistance = SearchDefaults.loadDistanceDefault();
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Wrap(
        spacing: 4,
        children: [
          MenuAnchor(
            menuChildren: [
              for (final key in SearchQueryBuilder.exactWordOptionKeys)
                CheckboxMenuButton(
                  value: defaults[key] ?? false,
                  closeOnActivate: false,
                  onChanged: (checked) {
                    setState(() {
                      SearchDefaults.saveExactDefaults(
                          {...defaults, key: checked ?? false});
                      // שינוי ברירת מחדל מוחל מיד גם על התיבה בחלונית הפתוחה
                      _searchTab.globalSearchOptions[key] = checked ?? false;
                      _searchTab.useGlobalSearchOptions.value = true;
                    });
                    _searchTab.searchOptionsChanged.value++;
                  },
                  child: Text(key),
                ),
              const Divider(height: 8),
              MenuItemButton(
                closeOnActivate: false,
                onPressed: () {
                  setState(() {
                    SearchDefaults.saveDistanceDefault(state.distance);
                  });
                  UiSnack.show(
                      'מרווח ${state.distance} נקבע כברירת מחדל לחיפוש רגיל');
                },
                child: Text(
                    'קבע את המרווח הנוכחי (${state.distance}) כברירת מחדל'),
              ),
            ],
            builder: (context, controller, _) => Tooltip(
              message:
                  'סמן אילו אפשרויות ואיזה מרווח יופעלו אוטומטית בכל חיפוש רגיל חדש',
              child: ActionButton.ghost(
                text: 'קביעת ברירת מחדל לחיפוש רגיל',
                icon: FluentIcons.options_24_regular,
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
            ),
          ),
          Tooltip(
            message:
                'החזרת האפשרויות והמרווח ($savedDistance) לברירת המחדל השמורה',
            child: ActionButton.ghost(
              text: 'חזרה לברירת מחדל',
              icon: FluentIcons.arrow_reset_24_regular,
              onPressed: () {
                setState(() {
                  _searchTab.globalSearchOptions
                    ..clear()
                    ..addAll(SearchDefaults.loadExactDefaults());
                });
                _searchTab.searchOptionsChanged.value++;
                _searchTab.searchBloc.add(
                  _usesStagedSubmit
                      ? UpdateDistanceWithoutSearch(savedDistance)
                      : UpdateDistance(savedDistance),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // מציג רק חיפושים מההיסטוריה הכללית.
  Widget _buildHistoryDropdown() {
    return BlocBuilder<HistoryBloc, HistoryState>(
      builder: (context, state) {
        final searchHistory =
            state.history.where((item) => item.isSearch).toList();

        if (searchHistory.isEmpty) return const SizedBox.shrink();

        final recentSearches = searchHistory.take(50).toList();

        return Column(
          key: const ValueKey('search-history-menu'),
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < recentSearches.length; index++) ...[
              if (index > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              Builder(builder: (context) {
                final bookmark = recentSearches[index];
                final query = bookmark.book.title;
                final displayText = bookmark.ref;
                final originalIndex = state.history.indexOf(bookmark);

                return ListTile(
                  dense: true,
                  leading: const Icon(FluentIcons.search_24_regular, size: 18),
                  title: Text(
                    displayText,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 14),
                  ),
                  trailing: IconButton(
                    icon: const Icon(FluentIcons.delete_24_regular, size: 18),
                    tooltip: 'מחק מההיסטוריה',
                    onPressed: () => context
                        .read<HistoryBloc>()
                        .add(RemoveHistory(originalIndex)),
                  ),
                  onTap: () {
                    _searchTab.queryController.text = query;

                    // חיפוש היסטורי מורחב משוחזר במצב פר-מילה.
                    if (bookmark.searchOptions != null) {
                      _searchTab.searchOptions
                        ..clear()
                        ..addAll(bookmark.searchOptions!);
                      _searchTab.globalSearchOptions.clear();
                      _searchTab.useGlobalSearchOptions.value = false;
                    }
                    if (bookmark.alternativeWords != null) {
                      _searchTab.alternativeWords
                        ..clear()
                        ..addAll(bookmark.alternativeWords!);
                    }
                    if (bookmark.spacingValues != null) {
                      _searchTab.spacingValues
                        ..clear()
                        ..addAll(bookmark.spacingValues!);
                    }

                    _historyMenuController.close();
                    _searchTab.searchFieldFocusNode.requestFocus();
                  },
                );
              }),
            ],
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    final restorer = _focusRestorer;
    if (restorer != null) FocusRepository().unregisterActiveRestorer(restorer);
    _searchTab.queryController.removeListener(_queryListener);
    _advancedControlsHasFocus.dispose();
    if (_ownsSearchTab) {
      if (widget.editTab == null) {
        // מצב החיפוש והפרמטרים (אפשרויות לפי מצב + מרווח) נשמרים לסשן
        // הנוכחי; בהפעלה הבאה חוזרים לברירת המחדל (חיפוש רגיל).
        final config = _searchTab.searchBloc.state.configuration;
        _rememberSessionOptionsForMode(config.searchMode);
        SearchDefaults.rememberSessionMode(config.searchMode);
        if (config.searchMode != SearchMode.fuzzy) {
          SearchDefaults.rememberSessionDistance(config.distance);
        }
      }
      _searchTab.dispose();
    }
    super.dispose();
  }

  /// האפשרויות הגלובליות שאיתן נפתח חיפוש חדש במצב [mode] — לכל מצב
  /// ברירות מחדל וזיכרון-סשן משלו (במקורב אין אפשרויות מילה).
  Map<String, bool> _initialOptionsForMode(SearchMode mode) {
    return switch (mode) {
      SearchMode.advanced => SearchDefaults.initialOptionsForNewSearch(),
      SearchMode.exact => SearchDefaults.initialExactOptionsForNewSearch(),
      SearchMode.fuzzy => const {},
    };
  }

  /// משמר את האפשרויות הגלובליות הנוכחיות לזיכרון-הסשן של [mode].
  void _rememberSessionOptionsForMode(SearchMode mode) {
    switch (mode) {
      case SearchMode.advanced:
        SearchDefaults.rememberSessionOptions(_searchTab.globalSearchOptions);
      case SearchMode.exact:
        SearchDefaults.rememberSessionExactOptions(
            _searchTab.globalSearchOptions);
      case SearchMode.fuzzy:
        break;
    }
  }

  /// מעבר מצב בדיאלוג של חיפוש חדש: האפשרויות הגלובליות של המצב הישן
  /// נשמרות לסשן שלו, ואלו של המצב החדש נטענות במקומן — כך שלכל מצב
  /// סט אפשרויות עצמאי. בעריכת טאב קיים האפשרויות שייכות לטאב ולא מוחלפות.
  void _swapGlobalOptionsForModeChange(SearchMode oldMode, SearchMode newMode) {
    if (!_ownsSearchTab || widget.editTab != null || oldMode == newMode) {
      return;
    }
    _rememberSessionOptionsForMode(oldMode);
    if (newMode == SearchMode.fuzzy) {
      return; // אין אפשרויות מילה במקורב; המפה תוחלף בכניסה למצב הבא
    }
    setState(() {
      _searchTab.globalSearchOptions
        ..clear()
        ..addAll(_initialOptionsForMode(newMode));
      if (newMode == SearchMode.exact) {
        // במצב הרגיל אין עורך פר-מילה — הסימון תמיד גלובלי.
        _searchTab.useGlobalSearchOptions.value = true;
      }
    });
    _searchTab.searchOptionsChanged.value++;
  }

  void _performSearch() {
    // חסימת חיפוש כשאין אינדקס - חיפוש שמשתמש באינדקס לא יכול לרוץ.
    // אם ה-provider עוד לא הסתיים לטעון, לא חוסמים (השאילתה תמתין ל-engine).
    if (isSearchBlockedByMissingIndex(
      providerInitialized: TantivyDataProvider.instance.isInitialized.value,
    )) {
      UiSnack.showError('אינדקס לא קיים, לא ניתן לבצע חיפוש זה ללא אינדקס.');
      return;
    }

    String query = _searchTab.queryController.text.trim();
    String negativeQuery = _searchTab.negativeQueryController.text.trim();

    if (query.isEmpty) {
      UiSnack.show('נא להזין טקסט לחיפוש');
      return;
    }

    // תחביר קטגוריה: `מונח@קטגוריה` מצמצם את החיפוש לקטגוריה לפי שם.
    final parsedCategory = parseCategoryQuery(
      query,
      context.read<LibraryBloc>().state.library,
    );
    if (parsedCategory.hasCategoryToken && !parsedCategory.categoryFound) {
      UiSnack.showError(
          'הקטגוריה או הספר "${parsedCategory.notFoundNames.join('", "')}" לא נמצאו');
      return;
    }
    query = parsedCategory.query;
    if (query.isEmpty) {
      UiSnack.show('נא להזין טקסט לחיפוש');
      return;
    }

    // חיפוש רגיל עובד על טקסט ללא ניקוד; כשאפשרות "ניקוד"/"טעמים" מסומנת
    // (במצב מתקדם, גלובלית או פר-מילה) הסימנים שהוקלדו הם חלק מהשאילתה —
    // המנוע דורש אותם בטקסט — ואסור למחוק אותם. הבדיקה רצה על מפות המקור
    // (לא על האפשרויות האפקטיביות) כי אלה נבנות מהשאילתה אחרי המחיקה.
    final dialogMode = _searchTab.searchBloc.state.configuration.searchMode;
    final vocalizedSearch = _supportsVocalizedSearch &&
        dialogMode == SearchMode.advanced &&
        (_searchTab.useGlobalSearchOptions.value
            ? SearchQueryBuilder.globalOptionsRequestVocalized(
                _searchTab.globalSearchOptions)
            : SearchQueryBuilder.optionsRequestVocalized(
                _searchTab.searchOptions));
    if (!vocalizedSearch && utils.hasNikud(query)) {
      query = utils.removeVolwels(query);
    }
    if (!vocalizedSearch && utils.hasNikud(negativeQuery)) {
      negativeQuery = utils.removeVolwels(negativeQuery);
    }
    query = SearchQueryBuilder.sanitizeQuery(query);
    negativeQuery = SearchQueryBuilder.sanitizeQuery(negativeQuery);

    // שמירת מצב החיפוש האחרון
    final currentState = _searchTab.searchBloc.state;
    final currentMode = currentState.configuration.searchMode;
    final effectiveOptions = SearchQueryBuilder.effectiveSearchOptions(
      query: query,
      useGlobalOptions: _searchTab.useGlobalSearchOptions.value,
      globalOptions: _searchTab.globalSearchOptions,
      perWordOptions: _searchTab.searchOptions,
    );
    // כשמתג "חלופות שמורות" דלוק — הרחבת החיפוש בחלופות הגלובליות השמורות
    final effectiveAlternatives = _searchTab.useSavedAlternatives
        ? SavedAlternativesStore.mergeIntoQuery(
            query, _searchTab.alternativeWords)
        : _searchTab.alternativeWords;
    final normalizedParameters = SearchQueryBuilder.normalizeParametersForMode(
      currentMode,
      customSpacing: _searchTab.spacingValues,
      alternativeWords: effectiveAlternatives,
      searchOptions: effectiveOptions,
    );
    final effectiveNegativeOptions = SearchQueryBuilder.effectiveSearchOptions(
      query: negativeQuery,
      useGlobalOptions: _searchTab.useGlobalNegativeSearchOptions.value,
      globalOptions: _searchTab.negativeGlobalSearchOptions,
      perWordOptions: _searchTab.negativeSearchOptions,
    );
    final normalizedNegativeParameters =
        SearchQueryBuilder.normalizeParametersForMode(
      currentMode,
      customSpacing: _searchTab.negativeSpacingValues,
      alternativeWords: _searchTab.negativeAlternativeWords,
      searchOptions: effectiveNegativeOptions,
    );
    if (widget.returnResultOnSubmit) {
      Navigator.of(context).pop(
        SearchDialogResult(
          query: query,
          searchOptions: normalizedParameters.searchOptions,
          alternativeWords: normalizedParameters.alternativeWords,
          spacingValues: normalizedParameters.customSpacing,
          searchMode: currentMode,
          distance: _searchTab.searchBloc.state.distance,
        ),
      );
      return;
    }

    if (widget.onSearch != null) {
      final onSearch = widget.onSearch!;
      final searchOptions = normalizedParameters.searchOptions;
      final alternativeWords = normalizedParameters.alternativeWords;
      final spacingValues = normalizedParameters.customSpacing;
      final distance = _searchTab.searchBloc.state.distance;

      Navigator.of(context).pop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onSearch(
          query,
          searchOptions,
          alternativeWords,
          spacingValues,
          currentMode,
          distance,
        );
      });
      return;
    }

    // ה-facets שנבחרו לחיפוש. תחביר `@קטגוריה`/`@ספר` גובר על הבחירה הידנית.
    final categoriesToSearch = parsedCategory.categoryFound
        ? parsedCategory.facets!
        : _selectedCategoryFacets.isEmpty
            ? ['/']
            : _selectedCategoryFacets.toList();
    // ממדי הסינון שנבחרו בדיאלוג (תקופה/מחבר/ספרי יסוד) מצטרפים ב-AND —
    // גם כשהקטגוריה נקבעה בתחביר `@`.
    final facetsToSearch = [
      ...categoriesToSearch,
      ...(_dimensionFacets.toList()..sort()),
    ];
    final distance = _searchTab.searchBloc.state.distance;
    final proximityScope = currentState.configuration.proximityScope;

    if (widget.editTab != null) {
      _applyEditToTarget(
        query: query,
        negativeQuery: negativeQuery,
        mode: currentMode,
        distance: distance,
        proximityScope: proximityScope,
        facetsToSearch: facetsToSearch,
        effectiveAlternatives: effectiveAlternatives,
        normalizedParameters: normalizedParameters,
        normalizedNegativeParameters: normalizedNegativeParameters,
      );
      return;
    }

    // יצירת טאב חדש לגמרי - ללא קשר לטאב קודם.
    // ה-configuration מוזרקת בבנייה ולא דרך events אחרי AddTab, אחרת
    // snapshot השמירה של הטאבים מצלם את ברירת המחדל והמצב אובד בהפעלה הבאה.
    final newSearchTab = SearchingTab(
      "חיפוש: $query",
      query,
      initialConfiguration: SearchConfiguration(
        searchMode: currentMode,
        distance: distance,
        proximityScope: proximityScope,
        currentFacets: facetsToSearch,
        searchScopeFacets: facetsToSearch,
      ),
    );

    // העתקת כל ההגדרות מהטאב הנוכחי לטאב החדש
    newSearchTab.searchOptions.addAll(_searchTab.searchOptions.map(
      (key, value) => MapEntry(key, Map<String, bool>.from(value)),
    ));
    newSearchTab.globalSearchOptions.addAll(_searchTab.globalSearchOptions);
    newSearchTab.useGlobalSearchOptions.value =
        _searchTab.useGlobalSearchOptions.value;
    newSearchTab.negativeQueryController.text = negativeQuery;
    newSearchTab.negativeSearchOptions.addAll(
      _searchTab.negativeSearchOptions.map(
        (key, value) => MapEntry(key, Map<String, bool>.from(value)),
      ),
    );
    newSearchTab.negativeGlobalSearchOptions
        .addAll(_searchTab.negativeGlobalSearchOptions);
    newSearchTab.useGlobalNegativeSearchOptions.value =
        _searchTab.useGlobalNegativeSearchOptions.value;
    // חלופות שמורות שמוזגו הופכות לחלק מהטאב — נשמרות ומשוחזרות איתו
    newSearchTab.alternativeWords.addAll(effectiveAlternatives.map(
      (key, value) => MapEntry(key, List<String>.from(value)),
    ));
    newSearchTab.spacingValues.addAll(_searchTab.spacingValues);
    newSearchTab.negativeAlternativeWords.addAll(
      _searchTab.negativeAlternativeWords.map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      ),
    );
    newSearchTab.negativeSpacingValues.addAll(_searchTab.negativeSpacingValues);

    // מעבירים את ה-scope במפורש להיסטוריה — SetFacetsWithoutSearch מעדכן את
    // state אסינכרונית, ובלי זה החיפוש היה נשמר בלי ה-scope שנבחר.
    context
        .read<HistoryBloc>()
        .add(AddHistory(newSearchTab, scopeFacets: facetsToSearch));

    // ביצוע החיפוש בטאב החדש
    newSearchTab.searchBloc.add(
      UpdateSearchQuery(
        query,
        negativeQuery: negativeQuery,
        customSpacing: normalizedParameters.customSpacing,
        alternativeWords: normalizedParameters.alternativeWords,
        searchOptions: normalizedParameters.searchOptions,
        negativeCustomSpacing: normalizedNegativeParameters.customSpacing,
        negativeAlternativeWords: normalizedNegativeParameters.alternativeWords,
        negativeSearchOptions: normalizedNegativeParameters.searchOptions,
      ),
    );

    // סגירת הדיאלוג
    Navigator.of(context).pop();

    // פתיחת טאב חדש תמיד
    final tabsBloc = context.read<TabsBloc>();
    final navigationBloc = context.read<NavigationBloc>();

    tabsBloc.add(AddTab(newSearchTab));

    // מעבר למסך העיון
    navigationBloc.add(const NavigateToScreen(Screen.search));
  }

  /// מחיל את פרמטרי הדיאלוג על טאב התוצאות הנערך ומריץ בו את החיפוש מחדש.
  void _applyEditToTarget({
    required String query,
    required String negativeQuery,
    required SearchMode mode,
    required int distance,
    required SearchScope proximityScope,
    required List<String> facetsToSearch,
    required Map<int, List<String>> effectiveAlternatives,
    required SearchModeScopedParameters normalizedParameters,
    required SearchModeScopedParameters normalizedNegativeParameters,
  }) {
    final target = widget.editTab!;

    target.queryController.text = query;
    target.negativeQueryController.text = negativeQuery;
    target.searchOptions
      ..clear()
      ..addAll(_searchTab.searchOptions.map(
        (key, value) => MapEntry(key, Map<String, bool>.from(value)),
      ));
    target.globalSearchOptions
      ..clear()
      ..addAll(_searchTab.globalSearchOptions);
    target.negativeSearchOptions
      ..clear()
      ..addAll(_searchTab.negativeSearchOptions.map(
        (key, value) => MapEntry(key, Map<String, bool>.from(value)),
      ));
    target.negativeGlobalSearchOptions
      ..clear()
      ..addAll(_searchTab.negativeGlobalSearchOptions);
    target.useGlobalSearchOptions.value =
        _searchTab.useGlobalSearchOptions.value;
    target.useGlobalNegativeSearchOptions.value =
        _searchTab.useGlobalNegativeSearchOptions.value;
    target.alternativeWords
      ..clear()
      ..addAll(effectiveAlternatives.map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      ));
    target.spacingValues
      ..clear()
      ..addAll(_searchTab.spacingValues);
    target.negativeAlternativeWords
      ..clear()
      ..addAll(_searchTab.negativeAlternativeWords.map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      ));
    target.negativeSpacingValues
      ..clear()
      ..addAll(_searchTab.negativeSpacingValues);
    target.updateTitleFromAppliedQuery(query);

    target.searchBloc.add(SetSearchModeWithoutSearch(mode));
    target.searchBloc.add(UpdateDistanceWithoutSearch(distance));
    target.searchBloc.add(UpdateProximityScopeWithoutSearch(proximityScope));
    // facetsToSearch כבר כולל את ממדי הסינון שנבחרו בדיאלוג (הם אותחלו
    // מה-state של טאב היעד וניתנים לעריכה בדיאלוג עצמו).
    target.searchBloc.add(SetFacetsWithoutSearch(facetsToSearch));
    context.read<HistoryBloc>().add(AddHistory(
          target,
          scopeFacets: facetsToSearch,
          proximityScope: proximityScope,
        ));
    target.searchBloc.add(UpdateSearchQuery(
      query,
      negativeQuery: negativeQuery,
      customSpacing: normalizedParameters.customSpacing,
      alternativeWords: normalizedParameters.alternativeWords,
      searchOptions: normalizedParameters.searchOptions,
      negativeCustomSpacing: normalizedNegativeParameters.customSpacing,
      negativeAlternativeWords: normalizedNegativeParameters.alternativeWords,
      negativeSearchOptions: normalizedNegativeParameters.searchOptions,
    ));

    final tabsBloc = context.read<TabsBloc>();
    Navigator.of(context).pop();
    // שמירת הטאבים אחרי שאירועי ה-configuration הסינכרוניים עובדו,
    // אחרת ה-snapshot היה מצלם את המצב הישן של הטאב הנערך.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      tabsBloc.add(const SaveTabs());
    });
  }

  void _setSearchAllCategories(bool value) {
    setState(() {
      _searchAllCategories = value;
      _selectedCategoryFacets =
          _searchAllCategories ? {'/'} : Set<String>.from(_manualFacets);
    });
    SearchScopePreferences.save(
      searchAllCategories: _searchAllCategories,
      manualFacets: _manualFacets,
    );
  }

  void _onManualFacetsChanged(Set<String> selection) {
    setState(() {
      // עץ הבחירה עשוי להחזיר גם facets ממדיים ששומרו בבחירה — מפצלים
      // כדי שההעדפה הידנית של הקטגוריות תישאר נקייה מממדים.
      _manualFacets = FacetHelper.categoryFacetsOf(selection).toSet();
      if (!_searchAllCategories) {
        _selectedCategoryFacets = Set<String>.from(_manualFacets);
      }
    });
    SearchScopePreferences.save(
      searchAllCategories: _searchAllCategories,
      manualFacets: _manualFacets,
    );
  }

  /// חלונית מתקפלת "תקופה, מחבר וספרי יסוד" — סינון שמצטרף ב-AND לבחירת
  /// הקטגוריות (וגם למצב "חיפוש בכל הקטגוריות").
  Widget _buildDimensionFilters() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppTokens.borderRadiusAll,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: _dimensionFacets.isNotEmpty,
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          FluentIcons.filter_add_20_regular,
          size: 20,
          color: colorScheme.primary,
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                _dimensionFacets.isEmpty
                    ? 'תקופה, מחבר וספרי יסוד'
                    : 'תקופה, מחבר וספרי יסוד (${_dimensionFacets.length})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        children: [
          SearchDimensionControls(
            selected: _dimensionFacets,
            onChanged: (next) {
              setState(() => _dimensionFacets = next);
              SearchScopePreferences.saveDimensionFacets(next);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesToggle(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSpecific = !_searchAllCategories;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppSurfaces.togglePill(colorScheme, active: isSpecific),
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'כל הקטגוריות',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: isSpecific
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
          Transform.scale(
            scale: 0.75,
            child: Switch(
              value: _searchAllCategories,
              onChanged: _setSearchAllCategories,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  // ── שכבת התצוגה ─────────────────────────────────────────────────────

  Widget _buildHeader() {
    final colorScheme = Theme.of(context).colorScheme;
    final title = widget.editTab != null
        ? 'עריכת חיפוש'
        : widget.bookTitle != null
            ? 'חיפוש ב${widget.bookTitle}'
            : 'חיפוש בספרייה';
    final subtitle = widget.editTab != null
        ? 'עדכן את השאילתה ואת אפשרויות החיפוש'
        : widget.bookTitle != null
            ? 'חיפוש ממוקד בתוך הספר הפתוח'
            : 'בחר שאילתה, סוג חיפוש והיקף בספרייה';
    return ColoredBox(
      color: AppSurfaces.card(context),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(24, 16, 12, 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: AppTokens.borderRadiusAll,
              ),
              child: Icon(
                FluentIcons.search_24_filled,
                size: 22,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(FluentIcons.dismiss_24_regular),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'סגור',
            ),
          ],
        ),
      ),
    );
  }

  /// בורר מצב החיפוש — שלושה מקטעים ברוחב מלא, עם שורת תיאור קצרה
  /// של המצב הנבחר מתחתיהם.
  Widget _buildModeSelector(BuildContext context, SearchState state) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentMode = state.configuration.searchMode;

    Widget buildSegment(IconData icon, SearchMode mode) {
      final isSelected = currentMode == mode;
      final foreground = isSelected
          ? colorScheme.onSecondaryContainer
          : colorScheme.onSurfaceVariant;
      return Expanded(
        child: Tooltip(
          message: mode.tooltip,
          waitDuration: const Duration(milliseconds: 400),
          child: InkWell(
            onTap: () {
              final oldMode =
                  _searchTab.searchBloc.state.configuration.searchMode;
              _searchTab.searchBloc.add(
                !_usesStagedSubmit
                    ? SetSearchMode(mode)
                    : SetSearchModeWithoutSearch(mode),
              );
              _swapGlobalOptionsForModeChange(oldMode, mode);
              _searchTab.searchFieldFocusNode.requestFocus();
            },
            borderRadius: AppTokens.borderRadiusAll,
            child: AnimatedContainer(
              duration: AppTokens.animFast,
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.secondaryContainer
                    : colorScheme.surfaceContainerHigh,
                borderRadius: AppTokens.borderRadiusAll,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: foreground),
                  const SizedBox(width: 6),
                  Text(
                    mode.shortLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: AppTokens.borderRadiusAll,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: SizedBox(
              height: 36,
              child: Row(
                children: [
                  buildSegment(
                      FluentIcons.text_quote_24_regular, SearchMode.exact),
                  buildSegment(
                      FluentIcons.search_info_24_regular, SearchMode.advanced),
                  buildSegment(
                      FluentIcons.arrow_bidirectional_left_right_24_regular,
                      SearchMode.fuzzy),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          currentMode.tooltip,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// שדה החיפוש עם כפתור ההיסטוריה, ולצדו פקד המרווח/המרחק.
  /// ברוחב צר הפקד יורד לשורה נפרדת.
  Widget _buildQueryRow() {
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final historyMenuWidth = screenWidth < 420 ? screenWidth - 48 : 360.0;
    final searchField = EnhancedSearchField(
      key: enhancedSearchFieldKey,
      widget: _SearchDialogWrapper(tab: _searchTab),
      showInlineSearchButton: false,
      onSubmit: _performSearch,
      trailingAction: MenuAnchor(
        controller: _historyMenuController,
        alignmentOffset: const Offset(0, 4),
        style: MenuStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          backgroundColor:
              WidgetStatePropertyAll(colorScheme.surfaceContainerHigh),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: AppTokens.borderRadiusAll,
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
        ),
        menuChildren: [
          SizedBox(width: historyMenuWidth, child: _buildHistoryDropdown()),
        ],
        builder: (context, controller, _) => IconButton(
          icon: Icon(
            controller.isOpen
                ? FluentIcons.chevron_up_24_regular
                : FluentIcons.history_24_regular,
            size: 24,
          ),
          tooltip: 'היסטוריית חיפושים',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
      ),
    );

    final distanceWidget = FuzzyDistance(
      tab: _searchTab,
      inputFocusNotifier: _advancedControlsHasFocus,
      triggerSearch: !_usesStagedSubmit,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: distanceWidget,
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: searchField),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8.0),
              child: distanceWidget,
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchComposer(SearchState state) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppSurfaces.card(context),
        borderRadius: AppTokens.borderRadiusAll,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel('מה לחפש'),
          const SizedBox(height: 8),
          _buildQueryRow(),
          const SizedBox(height: 12),
          _sectionLabel('סוג החיפוש'),
          const SizedBox(height: 8),
          _buildModeSelector(context, state),
        ],
      ),
    );
  }

  /// שדה "ללא" — סינון תוצאות שמכילות מילים מסוימות (מצב מתקדם בלבד).
  Widget _buildNegativeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('החרגת תוצאות'),
        const SizedBox(height: 8),
        RtlTextField(
          controller: _searchTab.negativeQueryController,
          decoration: InputDecoration(
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            border: const OutlineInputBorder(),
            labelText: 'ללא',
            hintText: 'תוצאות שמכילות מילים אלו לא יופיעו',
            prefixIcon: const Icon(FluentIcons.subtract_24_regular),
            suffixIcon: IconButton(
              icon: const Icon(FluentIcons.dismiss_24_regular),
              onPressed: () {
                _searchTab.negativeQueryController.clear();
                setState(() {});
              },
            ),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _performSearch(),
        ),
        if (_searchTab.negativeQueryController.text.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          AdvancedSearchControls(
            tab: _searchTab,
            onEmptySubmit: _performSearch,
            inputFocusNotifier: _advancedControlsHasFocus,
            supportsVocalized: _supportsVocalizedSearch,
            queryController: _searchTab.negativeQueryController,
            searchOptions: _searchTab.negativeSearchOptions,
            globalSearchOptions: _searchTab.negativeGlobalSearchOptions,
            useGlobalSearchOptions: _searchTab.useGlobalNegativeSearchOptions,
            alternativeWords: _searchTab.negativeAlternativeWords,
            spacingValues: _searchTab.negativeSpacingValues,
            searchOptionsChanged: _searchTab.negativeSearchOptionsChanged,
            alternativeWordsChanged: _searchTab.negativeAlternativeWordsChanged,
            spacingValuesChanged: _searchTab.negativeSpacingValuesChanged,
            enableSavedAlternatives: false,
          ),
        ],
      ],
    );
  }

  /// שורת היקף החיפוש: סינון תקופה/מחבר/ספרי יסוד + מתג "כל הקטגוריות".
  Widget _buildScopeRow() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppSurfaces.card(context),
        borderRadius: AppTokens.borderRadiusAll,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel('היכן לחפש'),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDimensionFilters(),
                    const SizedBox(height: 8),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: _buildCategoriesToggle(context),
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildDimensionFilters()),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 48,
                    child: Center(child: _buildCategoriesToggle(context)),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// מסגרת אחידה לאזורי האפשרויות של המצבים השונים.
  Widget _optionsCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppSurfaces.card(context),
        borderRadius: AppTokens.borderRadiusAll,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: child,
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildFuzzyHint() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: AppTokens.borderRadiusAll,
            ),
            child: Icon(
              FluentIcons.arrow_bidirectional_left_right_24_regular,
              size: 24,
              color: colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'חיפוש מקורב',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'מוצא גם כתיב שונה ושיבושי כתיב קלים. מרחק החיפוש קובע עד כמה התוצאה יכולה להיות שונה מהמילים שהוקלדו.',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeContentLayout({
    required Widget controls,
    required Widget? categoryPanel,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (categoryPanel != null && constraints.maxWidth < 480) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KeyedSubtree(
                  key: const ValueKey('search-mode-controls'),
                  child: controls,
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  key: const ValueKey('search-category-panel'),
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: categoryPanel,
                ),
              ],
            ),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                key: const ValueKey('search-mode-controls'),
                child: controls,
              ),
            ),
            AnimatedSize(
              duration: AppTokens.animNormal,
              curve: Curves.easeInOut,
              child: categoryPanel == null
                  ? const SizedBox.shrink()
                  : SizedBox(
                      key: const ValueKey('search-category-panel'),
                      width: 260,
                      height: constraints.maxHeight,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(start: 12.0),
                        child: categoryPanel,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  /// תוכן האזור התחתון לפי מצב החיפוש: אפשרויות המילה (מדויק), פקדי
  /// המצב המתקדם, או רמז למצב המקורב — לצד עץ הקטגוריות כשנבחר היקף ידני.
  Widget _buildModeContent(SearchState state) {
    final showCategory = !_searchAllCategories && widget.bookTitle == null;

    if (!state.isAdvancedSearchEnabled) {
      final isExact = state.configuration.searchMode == SearchMode.exact;
      final modeControls = isExact
          ? _optionsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _sectionLabel('אפשרויות מילה'),
                  ),
                  const SizedBox(height: 8),
                  _buildExactOptionsRow(),
                  const SizedBox(height: 4),
                  _buildExactDefaultsRow(state),
                ],
              ),
            )
          : _optionsCard(child: _buildFuzzyHint());

      return _buildModeContentLayout(
        controls: modeControls,
        categoryPanel: showCategory
            ? CategoryTreeSelector(
                selectedFacets: _manualFacets,
                onSelectionChanged: _onManualFacetsChanged,
              )
            : null,
      );
    }

    final advancedControls = _optionsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdvancedSearchControls(
            tab: _searchTab,
            onEmptySubmit: _performSearch,
            inputFocusNotifier: _advancedControlsHasFocus,
            supportsVocalized: _supportsVocalizedSearch,
          ),
          if (widget.onSearch == null && !widget.returnResultOnSubmit) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _buildNegativeSection(),
          ],
        ],
      ),
    );
    final categoryPanel = showCategory
        ? CategoryTreeSelector(
            selectedFacets: _manualFacets,
            onSelectionChanged: _onManualFacetsChanged,
          )
        : null;

    return _buildModeContentLayout(
      controls: advancedControls,
      categoryPanel: categoryPanel,
    );
  }

  Widget _buildFooter() {
    final colorScheme = Theme.of(context).colorScheme;
    final showKeyboardHint = MediaQuery.sizeOf(context).width >= 520;
    return ColoredBox(
      color: AppSurfaces.card(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: Row(
          children: [
            if (showKeyboardHint)
              Expanded(
                child: Text(
                  'Enter מפעיל את החיפוש',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else
              const Spacer(),
            ActionButton.neutral(
              text: 'ביטול',
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<bool>(
              valueListenable: TantivyDataProvider.instance.isInitialized,
              builder: (context, providerInitialized, _) {
                final blocked = isSearchBlockedByMissingIndex(
                  providerInitialized: providerInitialized,
                );
                return Tooltip(
                  message: blocked
                      ? 'אינדקס לא קיים, לא ניתן לבצע חיפוש זה ללא אינדקס'
                      : 'חפש',
                  child: ActionButton.recommended(
                    text: widget.editTab != null ? 'עדכן חיפוש' : 'חפש',
                    icon: FluentIcons.search_24_regular,
                    onPressed: blocked ? null : _performSearch,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isCompact = screenSize.width < 600;
    final dialogWidth = isCompact
        ? screenSize.width - 24
        : (screenSize.width * 0.7).clamp(640.0, 900.0);
    final dialogHeight = screenSize.height < 560
        ? screenSize.height - 24
        : (screenSize.height * 0.84).clamp(500.0, 720.0);
    final horizontalPadding = isCompact ? 16.0 : 24.0;

    return BlocProvider.value(
      value: _searchTab.searchBloc,
      child: Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: AppSurfaces.solidPanelBackground(context),
        clipBehavior: Clip.antiAlias,
        child: FocusScope(
          onKeyEvent: (node, event) {
            // תפיסת Enter ברמת הדיאלוג - FocusScope תופס אירועים מכל הילדים
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.enter) {
              // אם הפוקוס בתוך אפשרויות מתקדמות - תן לשדה לטפל
              if (_advancedControlsHasFocus.value) {
                return KeyEventResult.ignored;
              }
              _performSearch();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: SizedBox(
            key: tourSearchDialogTargetKey,
            width: dialogWidth,
            height: dialogHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const Divider(height: 1),
                Expanded(
                  child: BlocBuilder<SearchBloc, SearchState>(
                    builder: (context, state) {
                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          16,
                          horizontalPadding,
                          0,
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildIndexWarning(),
                                    _buildSearchComposer(state),
                                    if (widget.bookTitle == null) ...[
                                      const SizedBox(height: 12),
                                      _buildScopeRow(),
                                    ],
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      height: 260,
                                      child: _buildModeContent(state),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wrapper class to provide the TantivyFullTextSearch interface
/// without actually using the full widget
class _SearchDialogWrapper {
  final SearchingTab tab;

  _SearchDialogWrapper({required this.tab});
}
