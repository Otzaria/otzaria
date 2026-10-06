import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/search/search_scope_preferences.dart';
import 'package:otzaria/search/view/search_scope_menu.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/widgets/layout/centered_scrollable_state.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/saved_alternatives_store.dart';
import 'package:otzaria/plugins/models/plugin_search_dialog_item.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/services/plugin_search_dialog_registry.dart';
import 'package:otzaria/plugins/services/plugin_search_selection_preferences.dart';
import 'package:otzaria/search/utils/category_query_parser.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/search/view/enhanced_search_field.dart';
import 'package:otzaria/search/view/advanced_search_controls.dart';
import 'package:otzaria/search/view/full_text_settings_widgets.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/widgets/feedback/indexing_warning.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/tour/tour_target_keys.dart';
import 'package:otzaria/search_feedback/search_feedback_api.dart';
import 'package:otzaria/search_feedback/search_feedback_service.dart';
import 'package:otzaria/search_feedback/semantic_search_strings.dart';
import 'package:otzaria/semantic_search/bloc/semantic_search_bloc.dart';
import 'package:otzaria/semantic_search/models/semantic_availability.dart';
import 'package:otzaria/semantic_search/models/semantic_mode_gate.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria/semantic_search/repository/semantic_search_repository.dart';
import 'package:otzaria/semantic_search/view/semantic_mode_panel.dart';
import 'package:otzaria/tabs/models/semantic_search_tab.dart';

typedef PluginSearchSubmitLauncher =
    void Function(String pluginId, Map<String, dynamic> payload);

class SearchDialogResult {
  const SearchDialogResult({
    required this.query,
    required this.searchOptions,
    required this.alternativeWords,
    required this.spacingValues,
    required this.searchMode,
    required this.distance,
    this.matchPolicy = SearchMatchPolicy.standard,
    this.pluginSearchSelections = const {},
  });

  final String query;
  final Map<String, Map<String, bool>> searchOptions;
  final Map<int, List<String>> alternativeWords;
  final Map<String, String> spacingValues;
  final SearchMode searchMode;
  final int distance;

  /// טווח הקרבה ומצב התאמת המילים שנבחרו בדיאלוג — ראו [SearchMatchPolicy].
  final SearchMatchPolicy matchPolicy;

  /// בחירות של שורות החיפוש הסטטיות שהיו פעילות בעת אישור הדיאלוג.
  final Map<String, bool> pluginSearchSelections;
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
  )?
  onSearch;
  final String? bookTitle;
  final bool returnResultOnSubmit;
  final SearchMode? initialSearchMode;
  final PluginSearchDialogRegistry? pluginSearchDialogRegistry;
  final PluginSearchSubmitLauncher? pluginSearchSubmitLauncher;

  /// ברירת המחדל: [SemanticSearchRepository.instance] (לבדיקות).
  final SemanticSearchRepository? semanticRepository;

  /// ברירת המחדל: [SearchFeedbackService.instance] (לבדיקות).
  final SearchFeedbackConsentStore? semanticConsent;

  /// האם מותרת התצוגה המקדימה של פיתוח; ברירת המחדל [kDebugMode].
  final bool semanticDebugPreview;

  const SearchDialog({
    super.key,
    this.existingTab,
    this.editTab,
    this.onSearch,
    this.bookTitle,
    this.returnResultOnSubmit = false,
    this.initialSearchMode,
    this.pluginSearchDialogRegistry,
    this.pluginSearchSubmitLauncher,
    this.semanticRepository,
    this.semanticConsent,
    this.semanticDebugPreview = kDebugMode,
  });

  @override
  State<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<SearchDialog> {
  late SearchingTab _searchTab;
  FocusRestorer? _focusRestorer;
  bool _indexInProgressWarningDismissed = false;

  /// null = לפי מצב האפשרויות (פתוח כשיש בו הגדרה פעילה); אחרת בחירת המשתמש.
  bool? _moreOptionsExpanded;

  /// אפשרויות המילה של החיפוש הרגיל שמוצגות תמיד; השאר תחת "אפשרויות נוספות".
  static const List<String> _primaryExactOptionKeys = [
    'קידומות דקדוקיות',
    'סיומות דקדוקיות',
    'כתיב מלא/חסר',
  ];

  /// בחירת היקף החיפוש המאוחדת — facets קטגוריאליים (עץ/ספרים) וממדיים
  /// (תקופה/מחבר/ספרי יסוד) יחד. נשלט ע"י [SearchScopeMenuButton].
  Set<String> _scopeSelection = {'/'};
  final ValueNotifier<bool> _advancedControlsHasFocus = ValueNotifier(false);
  final MenuController _historyMenuController = MenuController();
  late final VoidCallback _queryListener;
  late final bool _ownsSearchTab;
  late final PluginSearchDialogRegistry _pluginSearchDialogRegistry;
  late final Map<String, bool> _pluginSearchSelections;
  late final Map<String, bool> _persistedPluginSelections;

  /// המצב הסמנטי נבחר; נשמר לסשן כמו מצבי החיפוש האחרים.
  static bool _sessionPrefersSemantic = false;
  bool _semanticSelected = false;
  bool _semanticIncludeLexical = true;
  bool _semanticGroupIdentical = true;
  bool _semanticSubmitted = false;
  SemanticSearchBloc? _semanticBloc;
  TabsBloc? _tabsBloc;

  /// החיפוש נשלח לכרטיסייה חדשה, ולכן [SearchDialog.existingTab] זמני ומיותר.
  bool _existingTabHandedOff = false;

  /// חיפוש חדש בספרייה או עריכת חיפוש חכם; לא בתוך ספר ולא בעריכת חיפוש רגיל.
  bool get _supportsSemanticMode =>
      widget.bookTitle == null &&
      widget.onSearch == null &&
      !widget.returnResultOnSubmit &&
      (widget.editTab == null || _editedSemanticTab != null);

  SemanticSearchTab? get _editedSemanticTab => switch (widget.editTab) {
    final SemanticSearchTab tab => tab,
    _ => null,
  };

  bool _semanticVisible(SemanticAvailability? availability) =>
      availability != null &&
      isSemanticModeVisible(availability, debug: widget.semanticDebugPreview);

  bool get _isSemanticActive =>
      _semanticSelected && _semanticVisible(_semanticBloc?.state.availability);

  bool get _usesStagedSubmit =>
      widget.onSearch != null ||
      widget.returnResultOnSubmit ||
      widget.editTab != null;

  /// תרומות סטטיות מיועדות לחיפוש הספרייה, שבו בחירתן נשמרת עם טאב התוצאות.
  /// בחיפוש בתוך ספר ה-callback הקיים אינו נושא את הבחירות הלאה.
  bool get _supportsPluginSearchDialogItems =>
      widget.bookTitle == null &&
      widget.onSearch == null &&
      !widget.returnResultOnSubmit;

  /// תיבות "ניקוד/טעמים" (ברשת אפשרויות החיפוש המתקדם) מוצגות רק במסלולים
  /// שמריצים חיפוש אינדקס (טאב חדש או עריכת טאב קיים). במסלולי החזרת-תוצאה
  /// (חיפוש בתוך ספר טקסט/PDF) החיפוש רץ מקומית על הספר הפתוח ואינו תומך
  /// בהתאמת ניקוד — הצגת הפקד שם הייתה בחירה שנבלעת בלי השפעה.
  bool get _supportsVocalizedSearch =>
      widget.onSearch == null && !widget.returnResultOnSubmit;

  @override
  void initState() {
    super.initState();
    _pluginSearchDialogRegistry =
        widget.pluginSearchDialogRegistry ??
        PluginSearchDialogRegistry.instance;

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
        // בלי העדפות תצוגת התוצאות: זה טאב השירות של הדיאלוג, והמיון/האיחוד
        // שלו נראים רק בבקשת החיפוש שנשלחת לתוספים.
        initialConfiguration: SearchConfiguration(
          searchMode: searchMode,
          distance: searchMode == SearchMode.fuzzy
              ? kMaxFuzzyDistance
              : SearchDefaults.initialDistanceForNewSearch(),
        ),
      );

      // חיפוש חדש נפתח עם אפשרויות ברירת המחדל של המצב שבו הוא נפתח
      // (או מצב הסשן הנוכחי) — לכל מצב חיפוש ברירות מחדל משלו
      _searchTab.globalSearchOptions.addAll(_initialOptionsForMode(searchMode));
    }
    if (widget.existingTab != null) _tabsBloc = context.read<TabsBloc?>();
    if (_supportsSemanticMode) {
      _semanticBloc = SemanticSearchBloc(
        repository:
            widget.semanticRepository ?? SemanticSearchRepository.instance,
      )..add(const SemanticSearchStarted());
      // מצב מבוקש במפורש (קיצור חיפוש מתקדם, איתור) גובר על זיכרון הסשן.
      _semanticSelected =
          _editedSemanticTab != null ||
          (_sessionPrefersSemantic &&
              widget.initialSearchMode == null &&
              widget.existingTab == null);
    }
    _pluginSearchSelections = Map<String, bool>.from(
      _searchTab.searchBloc.state.configuration.pluginSearchSelections,
    );
    _persistedPluginSelections = Map<String, bool>.from(
      PluginSearchSelectionPreferences.load(),
    );

    final persisted = SearchScopePreferences.load();
    final initialScopeFacets = _searchTab.searchBloc.state.searchScopeFacets;
    // ה-scope של הטאב עשוי לשאת גם facets ממדיים (תקופה/מחבר/ספרי יסוד) —
    // מפצלים: הקטגוריות והממדים מתאחדים לבחירה אחת עבור תפריט הסינון.
    final initialCategories = FacetHelper.categoryFacetsOf(initialScopeFacets);
    final initialDimensions = FacetHelper.dimensionFacetsOf(
      initialScopeFacets,
    ).toSet();
    final dimensions = initialDimensions.isNotEmpty
        ? initialDimensions
        : SearchScopePreferences.loadDimensionFacets();

    // טאב טרי שנוצר כאן נושא את ברירת המחדל ['/'] — זה אינו scope מפורש,
    // ורק טאב שהגיע מבחוץ (קיים/בעריכה) גובר על ההעדפה השמורה.
    final tabDefinesScope =
        widget.existingTab != null || widget.editTab != null;
    final Set<String> categories;
    if (tabDefinesScope && initialCategories.isNotEmpty) {
      categories = initialCategories.contains('/')
          ? {'/'}
          : Set<String>.from(initialCategories);
    } else {
      categories = persisted.searchAllCategories
          ? {'/'}
          : Set<String>.from(persisted.manualFacets);
    }
    _scopeSelection = {...categories, ...dimensions};
    final editedOptions = _editedSemanticTab?.options;
    if (editedOptions != null) {
      _scopeSelection = editedOptions.facets.toSet();
      _semanticIncludeLexical = editedOptions.includeLexical;
      _semanticGroupIdentical = editedOptions.groupIdenticalText;
    }

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
      inProgressDismissed: _indexInProgressWarningDismissed,
      onDismiss: () => setState(() => _indexInProgressWarningDismissed = true),
    );
  }

  /// מסך ריק במקום פקדי החיפוש כשאין אינדקס — עם בניית אינדקס או מעבר
  /// להגדרות הספרייה.
  Widget _buildIndexMissingState(IndexingState indexingState) {
    final cs = Theme.of(context).colorScheme;
    final isBuilding = indexingState is IndexingInProgress;
    final processed = indexingState.booksProcessed ?? 0;
    final total = indexingState.totalBooks ?? 0;
    return CenteredScrollableState(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.search_24_regular,
              size: 64,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(
              isBuilding
                  ? context.settingsText('אינדקס החיפוש בבנייה')
                  : context.settingsText('אינדקס החיפוש לא קיים'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              isBuilding
                  ? context.settingsText(
                      'החיפוש יתאפשר כשבניית האינדקס תסתיים. ניתן להמשיך לעיין בספרים בינתיים.',
                    )
                  : context.settingsText(
                      'כדי לחפש בתוכן הספרים יש לבנות תחילה את אינדקס החיפוש. הבנייה רצה ברקע, וניתן להמשיך לעיין בספרים בינתיים.',
                    ),
              style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (isBuilding) ...[
              LinearProgressIndicator(
                value: total > 0 ? processed / total : null,
              ),
              if (total > 0) ...[
                const SizedBox(height: 8),
                Text(
                  context.settingsText(
                    '{processed} מתוך {total} ספרים',
                    args: {'processed': processed, 'total': total},
                  ),
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 24),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: ActionButton.recommended(
                  text: context.settingsText('בנה אינדקס'),
                  icon: FluentIcons.play_24_regular,
                  onPressed: () {
                    final library = context.read<LibraryBloc>().state.library;
                    if (library != null) {
                      context.read<IndexingBloc>().add(StartIndexing(library));
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: ActionButton.neutral(
                text: context.settingsText('הגדרות ספרייה'),
                icon: FluentIcons.settings_24_regular,
                onPressed: () {
                  Navigator.of(context).pop();
                  mainWindowScreenKey.currentState?.handleInternalDeepLink(
                    'otzaria://settings/library',
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// אפשרויות המילה של החיפוש הרגיל (מדויק): שגיאות כתיב, קידומות/סיומות
  /// דקדוקיות, כתיב מלא/חסר וחלק ממילה — מוחלות גלובלית על כל מילות
  /// השאילתה. בקשה עם אפשרות פעילה רצה בפועל דרך המסלול המתקדם של המנוע
  /// (ראה gateway), כך שאין צורך בשינוי מנוע.
  Widget _buildExactOptionsRow(
    Set<String> disabledOptionIds,
    List<String> keys,
  ) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final key in keys)
            Tooltip(
              message: context.settingsText(
                SearchQueryBuilder.wordOptionDescriptions[key] ?? key,
              ),
              child: FilterChip(
                label: Text(context.settingsText(key)),
                visualDensity: VisualDensity.compact,
                selected: _searchTab.globalSearchOptions[key] ?? false,
                onSelected:
                    disabledOptionIds.contains(
                      SearchQueryBuilder.pluginOptionIdByWordOptionKey[key],
                    )
                    ? null
                    : (selected) {
                        setState(() {
                          _searchTab.globalSearchOptions[key] = selected;
                          // במצב הרגיל אין עורך פר-מילה — הסימון תמיד גלובלי.
                          _searchTab.useGlobalSearchOptions.value = true;
                        });
                        _searchTab.searchOptionsChanged.value++;
                      },
              ),
            ),
        ],
      ),
    );
  }

  /// קביעת מצב החיפוש הנוכחי כמצב שבו ייפתח כל חיפוש חדש. הפריט בתפריט
  /// נלחץ בטעות, ולכן השמירה עוברת דרך אישור.
  Future<void> _confirmSetModeAsDefault(SearchMode mode) async {
    final modeLabel = context.settingsText(mode.shortLabel);
    final confirmed = await showTwoActionsDialog(
      context: context,
      title: context.settingsText('קביעת מצב ברירת המחדל'),
      content: context.settingsText(
        'כל חיפוש חדש ייפתח מעכשיו במצב "{mode}". ניתן לשנות זאת שוב בכל עת.',
        args: {'mode': modeLabel},
      ),
      cancelText: context.settingsText('ביטול'),
      confirmText: context.settingsText('קבע כברירת מחדל'),
    );
    if (confirmed != true) return;
    SearchDefaults.saveModeDefault(mode);
    UiSnack.show(LibraryMessages.searchModeSetAsDefault(modeLabel));
  }

  /// תפריט ברירות המחדל של המצב הנוכחי — פעולה נדירה, ולכן בתפריט
  /// בשורה התחתונה ולא בגוף החלונית.
  Widget _buildDefaultsMenu(SearchState state) {
    final mode = state.configuration.searchMode;
    final isExact = mode == SearchMode.exact;
    final disabledOptionIds = _disabledSearchOptionIds(state);
    final defaults = isExact
        ? SearchDefaults.loadExactDefaults()
        : SearchDefaults.loadDefaults();
    // "ניקוד"/"טעמים" מוצעות רק במסלולים שתומכים בחיפוש מנוקד — כברירת
    // מחדל הן מגבילות כל חיפוש חדש לטקסטים מנוקדים בלבד.
    final keys = isExact
        ? SearchQueryBuilder.exactWordOptionKeys
        : [
            ...SearchQueryBuilder.availableWordOptionKeys,
            ...SearchQueryBuilder.advancedOnlyWordOptionKeys,
            if (_supportsVocalizedSearch)
              ...SearchQueryBuilder.vocalizedWordOptionKeys,
          ];

    void saveDefault(String key, bool checked) {
      setState(() {
        final updated = {...defaults, key: checked};
        if (isExact) {
          SearchDefaults.saveExactDefaults(updated);
          _searchTab.useGlobalSearchOptions.value = true;
        } else {
          SearchDefaults.saveDefaults(updated);
        }
        // שינוי ברירת מחדל מוחל מיד גם על הסימון בחלונית הפתוחה
        _searchTab.globalSearchOptions[key] = checked;
      });
      _searchTab.searchOptionsChanged.value++;
    }

    void resetToDefaults() {
      setState(() {
        _searchTab.globalSearchOptions
          ..clear()
          ..addAll(defaults);
        if (!isExact) _searchTab.searchOptions.clear();
      });
      _searchTab.searchOptionsChanged.value++;
      if (isExact) {
        final savedDistance = SearchDefaults.loadDistanceDefault();
        _searchTab.searchBloc.add(
          _usesStagedSubmit
              ? UpdateDistanceWithoutSearch(savedDistance)
              : UpdateDistance(savedDistance),
        );
      }
    }

    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          key: const ValueKey('search-dialog-default-mode'),
          leadingIcon: const Icon(FluentIcons.bookmark_24_regular),
          onPressed: () => _confirmSetModeAsDefault(mode),
          child: Text(context.settingsText('קבע מצב זה כברירת מחדל')),
        ),
        if (mode != SearchMode.fuzzy)
          SubmenuButton(
            menuChildren: [
              for (final key in keys)
                CheckboxMenuButton(
                  value: defaults[key] ?? false,
                  closeOnActivate: false,
                  onChanged:
                      disabledOptionIds.contains(
                        SearchQueryBuilder.pluginOptionIdByWordOptionKey[key],
                      )
                      ? null
                      : (checked) => saveDefault(key, checked ?? false),
                  child: Text(isExact ? context.settingsText(key) : key),
                ),
              if (isExact) ...[
                const Divider(height: 8),
                MenuItemButton(
                  closeOnActivate: false,
                  onPressed: () {
                    setState(() {
                      SearchDefaults.saveDistanceDefault(state.distance);
                    });
                    UiSnack.show(
                      LibraryMessages.distanceSetAsDefault(state.distance),
                    );
                  },
                  child: Text(
                    context.settingsText(
                      'קבע את המרווח הנוכחי ({distance}) כברירת מחדל',
                      args: {'distance': state.distance},
                    ),
                  ),
                ),
              ],
            ],
            leadingIcon: const Icon(FluentIcons.options_24_regular),
            child: Text(
              isExact
                  ? context.settingsText('קביעת ברירת מחדל לחיפוש רגיל')
                  : context.settingsText('קביעת ברירת מחדל לחיפוש מתקדם'),
            ),
          ),
        if (mode != SearchMode.fuzzy)
          MenuItemButton(
            leadingIcon: const Icon(FluentIcons.arrow_reset_24_regular),
            onPressed: resetToDefaults,
            child: Text(context.settingsText('חזרה לברירת מחדל')),
          ),
      ],
      // ה-tooltip דרך הכפתור ולא כעטיפה: בתוך MenuAnchor.builder עטיפה
      // חיצונית מתמזגת לצומת הסמנטיקה של עוגן התפריט (issue #1399).
      builder: (context, controller, _) => IconButton(
        key: const ValueKey('search-dialog-defaults-menu'),
        icon: const Icon(FluentIcons.more_horizontal_24_regular),
        tooltip: context.settingsText('ברירות מחדל לחיפוש'),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  // מציג רק חיפושים מההיסטוריה הכללית.
  Widget _buildHistoryDropdown() {
    return BlocBuilder<HistoryBloc, HistoryState>(
      builder: (context, state) {
        final searchHistory = state.history
            .where((item) => item.isSearch)
            .toList();

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
              Builder(
                builder: (context) {
                  final bookmark = recentSearches[index];
                  final query = bookmark.book.title;
                  final displayText = bookmark.ref;
                  final originalIndex = state.history.indexOf(bookmark);

                  return ListTile(
                    dense: true,
                    leading: const Icon(
                      OtzariaIcons.search_24_regular,
                      size: 18,
                    ),
                    title: Text(
                      displayText,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 14),
                    ),
                    trailing: IconButton(
                      icon: const Icon(FluentIcons.delete_24_regular, size: 18),
                      tooltip: context.settingsText('מחק מההיסטוריה'),
                      onPressed: () => context.read<HistoryBloc>().add(
                        RemoveHistory(originalIndex),
                      ),
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
                },
              ),
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
    _semanticBloc?.close();
    _disposeHandedOffExistingTab();
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

  /// טאב זמני שנמסר לדיאלוג (איתור, ספרייה) ואינו פתוח — נסגר עם ה-bloc שלו.
  void _disposeHandedOffExistingTab() {
    final existing = widget.existingTab;
    final tabsBloc = _tabsBloc;
    if (existing == null || !_existingTabHandedOff || tabsBloc == null) return;
    final open = tabsBloc.state.tabs.expand(leafPanes);
    if (!open.any((tab) => identical(tab, existing))) existing.dispose();
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
          _searchTab.globalSearchOptions,
        );
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
      UiSnack.showError(LibraryMessages.searchIndexMissing);
      return;
    }
    if (_isSemanticActive) {
      _performSemanticSearch();
      return;
    }

    String query = _searchTab.queryController.text.trim();
    String negativeQuery = _searchTab.negativeQueryController.text.trim();

    if (query.isEmpty) {
      UiSnack.show(LibraryMessages.emptySearchQuery);
      return;
    }

    // תחביר קטגוריה: `מונח@קטגוריה` מצמצם את החיפוש לקטגוריה לפי שם.
    final parsedCategory = parseCategoryQuery(
      query,
      context.read<LibraryBloc>().state.library,
    );
    if (parsedCategory.hasCategoryToken && !parsedCategory.categoryFound) {
      UiSnack.showError(
        LibraryMessages.categoryOrBookNotFound(parsedCategory.notFoundNames),
      );
      return;
    }
    query = parsedCategory.query;
    if (query.isEmpty) {
      UiSnack.show(LibraryMessages.emptySearchQuery);
      return;
    }

    // חיפוש רגיל עובד על טקסט ללא ניקוד; כשאפשרות "ניקוד"/"טעמים" מסומנת
    // (במצב מתקדם, גלובלית או פר-מילה) הסימנים שהוקלדו הם חלק מהשאילתה —
    // המנוע דורש אותם בטקסט — ואסור למחוק אותם. הבדיקה רצה על מפות המקור
    // (לא על האפשרויות האפקטיביות) כי אלה נבנות מהשאילתה אחרי המחיקה.
    final dialogMode = _searchTab.searchBloc.state.configuration.searchMode;
    final vocalizedSearch =
        _supportsVocalizedSearch &&
        dialogMode == SearchMode.advanced &&
        (_searchTab.useGlobalSearchOptions.value
            ? SearchQueryBuilder.globalOptionsRequestVocalized(
                _searchTab.globalSearchOptions,
              )
            : SearchQueryBuilder.optionsRequestVocalized(
                _searchTab.searchOptions,
              ));
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
            query,
            _searchTab.alternativeWords,
          )
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
          matchPolicy: currentState.configuration.matchPolicy,
          pluginSearchSelections: _allPluginSearchSelections(),
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
    final selectedCategories = FacetHelper.categoryFacetsOf(_scopeSelection);
    final categoriesToSearch = parsedCategory.categoryFound
        ? parsedCategory.facets!
        : selectedCategories.isEmpty
        ? ['/']
        : selectedCategories;
    // ממדי הסינון שנבחרו בדיאלוג (תקופה/מחבר/ספרי יסוד) מצטרפים ב-AND —
    // גם כשהקטגוריה נקבעה בתחביר `@`.
    final facetsToSearch = [
      ...categoriesToSearch,
      ...(FacetHelper.dimensionFacetsOf(_scopeSelection).toList()..sort()),
    ];
    final distance = _searchTab.searchBloc.state.distance;
    final proximityScope = currentState.configuration.proximityScope;

    if (_openSelectedPluginSearchTargets(
      query: query,
      negativeQuery: negativeQuery,
      mode: currentMode,
      distance: distance,
      proximityScope: proximityScope,
      facets: facetsToSearch,
      normalizedParameters: normalizedParameters,
      normalizedNegativeParameters: normalizedNegativeParameters,
    )) {
      Navigator.of(context).pop();
      return;
    }

    // מעבר מחיפוש חכם לחיפוש רגיל פותח כרטיסייה חדשה.
    if (widget.editTab != null && _editedSemanticTab == null) {
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
      initialConfiguration: SearchDefaults.withResultPreferences(
        SearchConfiguration(
          searchMode: currentMode,
          distance: distance,
          proximityScope: proximityScope,
          currentFacets: facetsToSearch,
          searchScopeFacets: facetsToSearch,
          pluginSearchSelections: _allPluginSearchSelections(),
        ),
      ),
    );

    // העתקת כל ההגדרות מהטאב הנוכחי לטאב החדש
    newSearchTab.searchOptions.addAll(
      _searchTab.searchOptions.map(
        (key, value) => MapEntry(key, Map<String, bool>.from(value)),
      ),
    );
    newSearchTab.globalSearchOptions.addAll(_searchTab.globalSearchOptions);
    newSearchTab.useGlobalSearchOptions.value =
        _searchTab.useGlobalSearchOptions.value;
    newSearchTab.negativeQueryController.text = negativeQuery;
    newSearchTab.negativeSearchOptions.addAll(
      _searchTab.negativeSearchOptions.map(
        (key, value) => MapEntry(key, Map<String, bool>.from(value)),
      ),
    );
    newSearchTab.negativeGlobalSearchOptions.addAll(
      _searchTab.negativeGlobalSearchOptions,
    );
    newSearchTab.useGlobalNegativeSearchOptions.value =
        _searchTab.useGlobalNegativeSearchOptions.value;
    // חלופות שמורות שמוזגו הופכות לחלק מהטאב — נשמרות ומשוחזרות איתו
    newSearchTab.alternativeWords.addAll(
      effectiveAlternatives.map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      ),
    );
    newSearchTab.spacingValues.addAll(_searchTab.spacingValues);
    newSearchTab.negativeAlternativeWords.addAll(
      _searchTab.negativeAlternativeWords.map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      ),
    );
    newSearchTab.negativeSpacingValues.addAll(_searchTab.negativeSpacingValues);

    // מעבירים את ה-scope במפורש להיסטוריה — SetFacetsWithoutSearch מעדכן את
    // state אסינכרונית, ובלי זה החיפוש היה נשמר בלי ה-scope שנבחר.
    context.read<HistoryBloc>().add(
      AddHistory(newSearchTab, scopeFacets: facetsToSearch),
    );

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
    _existingTabHandedOff = true;
    final tabsBloc = context.read<TabsBloc>();
    final navigationBloc = context.read<NavigationBloc>();

    tabsBloc.add(AddTab(newSearchTab));

    // מעבר למסך העיון
    navigationBloc.add(const NavigateToScreen(Screen.search));
  }

  /// בלי הסכמה או בלי נתונים אין חיפוש; הדיאלוג עצמו אינו רושם דבר.
  void _performSemanticSearch() {
    final availability = _semanticBloc?.state.availability;
    if (_semanticSubmitted ||
        availability == null ||
        !canRunSemanticSearch(
          availability,
          debug: widget.semanticDebugPreview,
        )) {
      return;
    }
    final query = _searchTab.queryController.text;
    if (query.trim().isEmpty) {
      UiSnack.show(LibraryMessages.emptySearchQuery);
      return;
    }
    _semanticSubmitted = true;
    _existingTabHandedOff = true;
    _sessionPrefersSemantic = true;
    final options = SemanticQueryOptions(
      query: query,
      facets: semanticScopeFacets(
        _scopeSelection,
        isOfficialCategory: officialCategoryFilter(
          context.read<LibraryBloc>().state.library,
        ),
      ),
      includeLexical: _semanticIncludeLexical,
      groupIdenticalText: _semanticGroupIdentical,
    );
    final edited = _editedSemanticTab;
    if (edited != null) {
      Navigator.of(context).pop();
      edited.submit(options);
      return;
    }
    final tab = SemanticSearchTab(runOnFirstShow: true, options: options);
    final tabsBloc = context.read<TabsBloc>();
    final navigationBloc = context.read<NavigationBloc>();
    Navigator.of(context).pop();
    tabsBloc.add(AddTab(tab));
    navigationBloc.add(const NavigateToScreen(Screen.search));
  }

  SearchFeedbackConsentStore get _semanticConsentStore =>
      widget.semanticConsent ?? SearchFeedbackService.instance;

  Future<void> _grantSemanticConsent() async {
    await _semanticConsentStore.grant();
    if (!mounted) return;
    _semanticBloc?.add(const SemanticSearchStarted());
  }

  Future<void> _declineSemanticConsent() async {
    await _semanticConsentStore.decline();
    _sessionPrefersSemantic = false;
    if (mounted) setState(() => _semanticSelected = false);
  }

  /// מספק את זמינות המצב הסמנטי; `null` כשהמצב אינו נתמך בדיאלוג הזה.
  Widget _withSemanticAvailability(
    Widget Function(SemanticAvailability? availability) builder,
  ) {
    final bloc = _semanticBloc;
    if (bloc == null) return builder(null);
    return BlocBuilder<SemanticSearchBloc, SemanticSearchState>(
      bloc: bloc,
      builder: (context, state) => builder(state.availability),
    );
  }

  Widget _buildSemanticPanel(SemanticAvailability availability) {
    return SemanticModePanel(
      availability: availability,
      debug: widget.semanticDebugPreview,
      queryController: _searchTab.queryController,
      queryFocusNode: _searchTab.searchFieldFocusNode,
      scopeSelection: _scopeSelection,
      onScopeChanged: _onScopeChanged,
      includeLexical: _semanticIncludeLexical,
      onIncludeLexicalChanged: (value) =>
          setState(() => _semanticIncludeLexical = value),
      groupIdenticalText: _semanticGroupIdentical,
      onGroupIdenticalTextChanged: (value) =>
          setState(() => _semanticGroupIdentical = value),
      onSubmit: _performSearch,
      onGrantConsent: _grantSemanticConsent,
      onDeclineConsent: _declineSemanticConsent,
      queryTrailingAction: _buildHistoryButton(),
      onDownload: () => _semanticBloc?.add(const SemanticDownloadRequested()),
      onCancelDownload: () =>
          _semanticBloc?.add(const SemanticDownloadCancelRequested()),
    );
  }

  bool _openSelectedPluginSearchTargets({
    required String query,
    required String negativeQuery,
    required SearchMode mode,
    required int distance,
    required SearchScope proximityScope,
    required List<String> facets,
    required SearchModeScopedParameters normalizedParameters,
    required SearchModeScopedParameters normalizedNegativeParameters,
  }) {
    final selections = _allPluginSearchSelections();
    final targets = _pluginSearchDialogRegistry.getAll().where((record) {
      final item = record.$2;
      return item.openPluginOnSubmit &&
          item.isVisibleIn(mode) &&
          selections[_pluginSelectionKey(record.$1, item.id)] == true;
    }).toList();
    if (targets.isEmpty) return false;

    final configuration = _searchTab.searchBloc.state.configuration;
    final request = <String, dynamic>{
      'query': query,
      'mode': mode.name,
      'order': configuration.sortBy.name,
      'limit': configuration.numResults,
      'distance': distance,
      'facets': facets,
      if (normalizedParameters.searchOptions.isNotEmpty)
        'wordOptions': normalizedParameters.searchOptions,
      if (mode == SearchMode.advanced) ...{
        if (negativeQuery.isNotEmpty) 'negativeQuery': negativeQuery,
        'proximityScope': proximityScope.name,
        'wordMatchMode': configuration.wordMatchMode.name,
        if (configuration.wordMatchMode == WordMatchMode.atLeast)
          'wordMatchCount': configuration.wordMatchCount,
        'grouping': configuration.resultGrouping.name,
        if (normalizedParameters.alternativeWords.isNotEmpty)
          'alternativeWords': _stringKeyed(
            normalizedParameters.alternativeWords,
          ),
        if (normalizedParameters.customSpacing.isNotEmpty)
          'customSpacing': normalizedParameters.customSpacing,
        if (normalizedNegativeParameters.searchOptions.isNotEmpty)
          'negativeWordOptions': normalizedNegativeParameters.searchOptions,
        if (normalizedNegativeParameters.alternativeWords.isNotEmpty)
          'negativeAlternativeWords': _stringKeyed(
            normalizedNegativeParameters.alternativeWords,
          ),
        if (normalizedNegativeParameters.customSpacing.isNotEmpty)
          'negativeCustomSpacing': normalizedNegativeParameters.customSpacing,
      },
    };
    final launch =
        widget.pluginSearchSubmitLauncher ??
        (String pluginId, Map<String, dynamic> payload) {
          PluginPageLauncher.instance.open(
            pluginId,
            topic: 'search.requested',
            payload: payload,
          );
        };
    for (final target in targets) {
      launch(target.$1, {'itemId': target.$2.id, 'request': request});
    }
    return true;
  }

  Map<String, List<String>> _stringKeyed(Map<int, List<String>> values) => {
    for (final entry in values.entries) entry.key.toString(): entry.value,
  };

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
      ..addAll(
        _searchTab.searchOptions.map(
          (key, value) => MapEntry(key, Map<String, bool>.from(value)),
        ),
      );
    target.globalSearchOptions
      ..clear()
      ..addAll(_searchTab.globalSearchOptions);
    target.negativeSearchOptions
      ..clear()
      ..addAll(
        _searchTab.negativeSearchOptions.map(
          (key, value) => MapEntry(key, Map<String, bool>.from(value)),
        ),
      );
    target.negativeGlobalSearchOptions
      ..clear()
      ..addAll(_searchTab.negativeGlobalSearchOptions);
    target.useGlobalSearchOptions.value =
        _searchTab.useGlobalSearchOptions.value;
    target.useGlobalNegativeSearchOptions.value =
        _searchTab.useGlobalNegativeSearchOptions.value;
    target.alternativeWords
      ..clear()
      ..addAll(
        effectiveAlternatives.map(
          (key, value) => MapEntry(key, List<String>.from(value)),
        ),
      );
    target.spacingValues
      ..clear()
      ..addAll(_searchTab.spacingValues);
    target.negativeAlternativeWords
      ..clear()
      ..addAll(
        _searchTab.negativeAlternativeWords.map(
          (key, value) => MapEntry(key, List<String>.from(value)),
        ),
      );
    target.negativeSpacingValues
      ..clear()
      ..addAll(_searchTab.negativeSpacingValues);
    target.updateTitleFromAppliedQuery(query);

    target.searchBloc.add(SetSearchModeWithoutSearch(mode));
    target.searchBloc.add(UpdateDistanceWithoutSearch(distance));
    target.searchBloc.add(UpdateProximityScopeWithoutSearch(proximityScope));
    target.searchBloc.add(
      UpdatePluginSearchSelectionsWithoutSearch(_allPluginSearchSelections()),
    );
    // facetsToSearch כבר כולל את ממדי הסינון שנבחרו בדיאלוג (הם אותחלו
    // מה-state של טאב היעד וניתנים לעריכה בדיאלוג עצמו).
    target.searchBloc.add(SetFacetsWithoutSearch(facetsToSearch));
    context.read<HistoryBloc>().add(
      AddHistory(
        target,
        scopeFacets: facetsToSearch,
        proximityScope: proximityScope,
      ),
    );
    target.searchBloc.add(
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

    final tabsBloc = context.read<TabsBloc>();
    Navigator.of(context).pop();
    // שמירת הטאבים אחרי שאירועי ה-configuration הסינכרוניים עובדו,
    // אחרת ה-snapshot היה מצלם את המצב הישן של הטאב הנערך.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      tabsBloc.add(const SaveTabs());
    });
  }

  void _onScopeChanged(Set<String> selection) {
    setState(() => _scopeSelection = selection);
    final categories = FacetHelper.categoryFacetsOf(selection).toSet();
    final dimensions = FacetHelper.dimensionFacetsOf(selection).toSet();
    final isAll = categories.isEmpty || categories.contains('/');
    SearchScopePreferences.save(
      searchAllCategories: isAll,
      manualFacets: isAll ? <String>{} : categories,
    );
    SearchScopePreferences.saveDimensionFacets(dimensions);
  }

  // ── שכבת התצוגה ─────────────────────────────────────────────────────

  Widget _buildHeader() {
    final title = widget.editTab != null
        ? context.settingsText('עריכת חיפוש')
        : widget.bookTitle != null
        ? context.settingsText(
            'חיפוש ב{book}',
            args: {'book': widget.bookTitle},
          )
        : context.settingsText('חיפוש בספרייה');
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(FluentIcons.dismiss_24_regular),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: context.settingsText('סגור'),
          ),
        ],
      ),
    );
  }

  /// בורר מצב החיפוש — שלושה מקטעים ברוחב מלא; ההסבר של כל מצב ב-tooltip.
  Widget _buildModeSelector(
    BuildContext context,
    SearchState state,
    SemanticAvailability? semanticAvailability,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentMode = state.configuration.searchMode;
    final semanticVisible = _semanticVisible(semanticAvailability);
    final semanticActive = _semanticSelected && semanticVisible;

    Widget segmentBody(IconData icon, String label, bool isSelected) {
      final foreground = isSelected
          ? colorScheme.onSecondaryContainer
          : colorScheme.onSurfaceVariant;
      return AnimatedContainer(
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
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: foreground,
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget buildSemanticSegment() {
      return Expanded(
        child: Tooltip(
          message: context.settingsText(
            'מוצא קטעים שעוסקים בעניין שתיארתם, גם כשהמילים שונות.',
          ),
          waitDuration: const Duration(milliseconds: 400),
          child: InkWell(
            key: const ValueKey('search-dialog-semantic-mode'),
            onTap: () {
              setState(() => _semanticSelected = true);
              _sessionPrefersSemantic = true;
              _searchTab.searchFieldFocusNode.requestFocus();
            },
            borderRadius: AppTokens.borderRadiusAll,
            child: segmentBody(
              FluentIcons.lightbulb_24_regular,
              context.settingsText(kSemanticSearchModeLabel),
              semanticActive,
            ),
          ),
        ),
      );
    }

    Widget buildSegment(IconData icon, SearchMode mode) {
      final isSelected = !semanticActive && currentMode == mode;
      return Expanded(
        child: Tooltip(
          message: context.settingsText(mode.tooltip),
          waitDuration: const Duration(milliseconds: 400),
          child: InkWell(
            onTap: () {
              _semanticSelected = false;
              _sessionPrefersSemantic = false;
              final oldMode =
                  _searchTab.searchBloc.state.configuration.searchMode;
              _searchTab.searchBloc.add(
                !_usesStagedSubmit
                    ? SetSearchMode(mode)
                    : SetSearchModeWithoutSearch(mode),
              );
              _swapGlobalOptionsForModeChange(oldMode, mode);
              setState(() => _moreOptionsExpanded = null);
              _searchTab.searchFieldFocusNode.requestFocus();
            },
            borderRadius: AppTokens.borderRadiusAll,
            child: segmentBody(
              icon,
              context.settingsText(mode.shortLabel),
              isSelected,
            ),
          ),
        ),
      );
    }

    return Material(
      color: colorScheme.surfaceContainerHigh,
      borderRadius: AppTokens.borderRadiusAll,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SizedBox(
          height: 36,
          child: Row(
            children: [
              buildSegment(FluentIcons.text_quote_24_regular, SearchMode.exact),
              buildSegment(
                FluentIcons.search_info_24_regular,
                SearchMode.advanced,
              ),
              buildSegment(
                FluentIcons.arrow_bidirectional_left_right_24_regular,
                SearchMode.fuzzy,
              ),
              if (semanticVisible) buildSemanticSegment(),
            ],
          ),
        ),
      ),
    );
  }

  /// כפתור היסטוריית החיפושים שבסוף שדה החיפוש.
  Widget _buildHistoryButton() {
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final historyMenuWidth = screenWidth < 420 ? screenWidth - 48 : 360.0;
    return MenuAnchor(
      controller: _historyMenuController,
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        backgroundColor: WidgetStatePropertyAll(
          colorScheme.surfaceContainerHigh,
        ),
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
        tooltip: context.settingsText('היסטוריית חיפושים'),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  /// שדה החיפוש עם כפתור ההיסטוריה, ומתחתיו שורה אחת של "איפה ואיך":
  /// היקף החיפוש ופקד המרווח/המרחק.
  Widget _buildQueryRow() {
    final searchField = EnhancedSearchField(
      key: enhancedSearchFieldKey,
      widget: _SearchDialogWrapper(tab: _searchTab),
      onSubmit: _performSearch,
      trailingAction: _buildHistoryButton(),
    );

    final distanceWidget = FuzzyDistance(
      tab: _searchTab,
      inputFocusNotifier: _advancedControlsHasFocus,
      triggerSearch: !_usesStagedSubmit,
    );

    // תפריט הסינון המאוחד רלוונטי רק לחיפוש בספרייה (לא בחיפוש בתוך ספר).
    final scopeButton = widget.bookTitle == null
        ? SearchScopeMenuButton(
            selected: _scopeSelection,
            onChanged: _onScopeChanged,
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        searchField,
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [?scopeButton, distanceWidget],
          ),
        ),
      ],
    );
  }

  /// שדה "ללא" — סינון תוצאות שמכילות מילים מסוימות (מצב מתקדם בלבד).
  Widget _buildNegativeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel(context.settingsText('החרגת תוצאות')),
        const SizedBox(height: 8),
        RtlTextField(
          controller: _searchTab.negativeQueryController,
          decoration: InputDecoration(
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            border: const OutlineInputBorder(),
            labelText: context.settingsText('ללא', context: 'searchExclude'),
            hintText: context.settingsText(
              'תוצאות שמכילות מילים אלו לא יופיעו',
            ),
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

  /// האזור הראשי לפי מצב החיפוש: אפשרויות המילה השכיחות (רגיל) או
  /// עורך המילים (מתקדם). במקורב פקד המרחק שבשורת השאילתה מספיק.
  Widget? _buildModeContent(SearchState state) {
    final disabledOptionIds = _disabledSearchOptionIds(state);
    final Widget controls;
    switch (state.configuration.searchMode) {
      case SearchMode.exact:
        controls = _buildExactOptionsRow(
          disabledOptionIds,
          _primaryExactOptionKeys,
        );
      case SearchMode.advanced:
        controls = _optionsCard(
          child: AdvancedSearchControls(
            tab: _searchTab,
            onEmptySubmit: _performSearch,
            inputFocusNotifier: _advancedControlsHasFocus,
            supportsVocalized: _supportsVocalizedSearch,
            supportsCategorySyntax: true,
            disabledWordOptionIds: disabledOptionIds,
          ),
        );
      case SearchMode.fuzzy:
        return null;
    }

    return KeyedSubtree(
      key: const ValueKey('search-mode-controls'),
      child: controls,
    );
  }

  /// אפשרויות נדירות מקופלות תחת "אפשרויות נוספות". המקטע נפתח מעצמו כשיש
  /// בו הגדרה פעילה — כדי שהגדרה שמשפיעה על התוצאות לא תוסתר.
  Widget? _buildMoreOptions(SearchState state) {
    final mode = state.configuration.searchMode;
    final sections = <Widget>[];
    var hasActive = false;

    if (mode == SearchMode.exact) {
      final keys = SearchQueryBuilder.exactWordOptionKeys
          .where((key) => !_primaryExactOptionKeys.contains(key))
          .toList();
      sections.add(
        _buildExactOptionsRow(_disabledSearchOptionIds(state), keys),
      );
      hasActive |= keys.any(
        (key) => _searchTab.globalSearchOptions[key] ?? false,
      );
    }
    if (mode == SearchMode.advanced &&
        widget.onSearch == null &&
        !widget.returnResultOnSubmit) {
      sections.add(_buildNegativeSection());
      hasActive |= _searchTab.negativeQueryController.text.trim().isNotEmpty;
    }
    final pluginItems = _visiblePluginItems(mode);
    if (pluginItems.isNotEmpty) {
      sections.add(_buildPluginSearchRows(pluginItems));
      hasActive |= pluginItems.any(
        (record) =>
            _pluginSelectionValue(record.$1, record.$2) !=
            record.$2.defaultValue,
      );
    }
    if (sections.isEmpty) return null;

    final expanded = _moreOptionsExpanded ?? hasActive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ActionButton.ghost(
            key: const ValueKey('search-dialog-more-options'),
            text: context.settingsText('אפשרויות נוספות'),
            icon: expanded
                ? FluentIcons.chevron_up_24_regular
                : FluentIcons.chevron_down_24_regular,
            onPressed: () => setState(() => _moreOptionsExpanded = !expanded),
          ),
        ),
        if (expanded)
          for (final section in sections) ...[
            const SizedBox(height: 8),
            section,
          ],
      ],
    );
  }

  String _pluginSelectionKey(String pluginId, String itemId) =>
      '$pluginId/$itemId';

  /// בחירת המשתמש בטאב הנוכחי גוברת על הבחירה האחרונה השמורה, וזו על
  /// `defaultValue` שבמניפסט.
  bool _pluginSelectionValue(String pluginId, PluginSearchDialogItem item) {
    final key = _pluginSelectionKey(pluginId, item.id);
    return _pluginSearchSelections[key] ??
        _persistedPluginSelections[key] ??
        item.defaultValue;
  }

  Map<String, bool> _allPluginSearchSelections() {
    final selections = Map<String, bool>.from(_pluginSearchSelections);
    for (final record in _pluginSearchDialogRegistry.getAll()) {
      selections.putIfAbsent(
        _pluginSelectionKey(record.$1, record.$2.id),
        () => _pluginSelectionValue(record.$1, record.$2),
      );
    }
    return selections;
  }

  Set<String> _disabledSearchOptionIds(SearchState state) {
    if (!_supportsPluginSearchDialogItems) return const {};
    final mode = state.configuration.searchMode;
    return {
      for (final record in _pluginSearchDialogRegistry.getAll())
        if (record.$2.isVisibleIn(mode) &&
            _pluginSelectionValue(record.$1, record.$2))
          ...record.$2.disabledOptionsFor(mode),
    };
  }

  void _updatePluginSearchSelection(
    String pluginId,
    PluginSearchDialogItem item,
    bool value,
  ) {
    final key = _pluginSelectionKey(pluginId, item.id);
    setState(() {
      _pluginSearchSelections[key] = value;
    });
    _persistedPluginSelections[key] = value;
    PluginSearchSelectionPreferences.save(_persistedPluginSelections);
    _searchTab.searchBloc.add(
      UpdatePluginSearchSelectionsWithoutSearch(_allPluginSearchSelections()),
    );
  }

  List<(String, PluginSearchDialogItem)> _visiblePluginItems(SearchMode mode) {
    if (!_supportsPluginSearchDialogItems) return const [];
    return _pluginSearchDialogRegistry
        .getAll()
        .where((record) => record.$2.isVisibleIn(mode))
        .toList();
  }

  Widget _buildPluginSearchRows(
    List<(String, PluginSearchDialogItem)> visibleItems,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final record in visibleItems)
          CheckboxListTile(
            key: ValueKey('plugin-search-dialog-${record.$1}-${record.$2.id}'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: Text(record.$2.title),
            value: _pluginSelectionValue(record.$1, record.$2),
            onChanged: (value) => _updatePluginSearchSelection(
              record.$1,
              record.$2,
              value ?? false,
            ),
          ),
      ],
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 24, 14),
      child: Row(
        children: [
          // ברירות המחדל בתפריט שייכות לחיפוש הרגיל בלבד.
          _withSemanticAvailability(
            (availability) => Visibility(
              visible: !(_semanticSelected && _semanticVisible(availability)),
              // שומר את גובה השורה, כדי ש"חפש" לא יקפוץ בין המצבים.
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: BlocBuilder<SearchBloc, SearchState>(
                builder: (context, state) => _buildDefaultsMenu(state),
              ),
            ),
          ),
          const Spacer(),
          ValueListenableBuilder<bool>(
            valueListenable: TantivyDataProvider.instance.isInitialized,
            builder: (context, providerInitialized, _) {
              final blocked = isSearchBlockedByMissingIndex(
                providerInitialized: providerInitialized,
              );
              return _withSemanticAvailability(
                (semanticAvailability) => _buildSearchButton(
                  blocked: blocked,
                  semanticBlocked:
                      _semanticSelected &&
                      _semanticVisible(semanticAvailability) &&
                      !canRunSemanticSearch(
                        semanticAvailability!,
                        debug: widget.semanticDebugPreview,
                      ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchButton({
    required bool blocked,
    required bool semanticBlocked,
  }) {
    return Tooltip(
      message: blocked
          ? context.settingsText(
              'אינדקס לא קיים, לא ניתן לבצע חיפוש זה ללא אינדקס',
            )
          : context.settingsText('חפש'),
      child: ActionButton.recommended(
        key: const ValueKey('search-dialog-submit'),
        text: widget.editTab != null
            ? context.settingsText('עדכן חיפוש')
            : context.settingsText('חפש'),
        icon: FluentIcons.search_24_regular,
        onPressed: blocked || semanticBlocked ? null : _performSearch,
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
    // גובה קבוע: פתיחת "אפשרויות נוספות" או מעבר מצב לא מקפיצים את החלון.
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
                Expanded(
                  child: _IndexMissingGate(
                    missingBuilder: _buildIndexMissingState,
                    child: ListenableBuilder(
                      listenable: _pluginSearchDialogRegistry,
                      builder: (context, _) =>
                          BlocBuilder<SearchBloc, SearchState>(
                            builder: (context, state) =>
                                _withSemanticAvailability((
                                  semanticAvailability,
                                ) {
                                  final semanticActive =
                                      _semanticSelected &&
                                      _semanticVisible(semanticAvailability);
                                  final modeContent = semanticActive
                                      ? null
                                      : _buildModeContent(state);
                                  final moreOptions = semanticActive
                                      ? null
                                      : _buildMoreOptions(state);
                                  return SingleChildScrollView(
                                    padding: EdgeInsets.fromLTRB(
                                      horizontalPadding,
                                      8,
                                      horizontalPadding,
                                      8,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _buildIndexWarning(),
                                        _buildModeSelector(
                                          context,
                                          state,
                                          semanticAvailability,
                                        ),
                                        const SizedBox(height: 12),
                                        if (semanticActive)
                                          _buildSemanticPanel(
                                            semanticAvailability!,
                                          )
                                        else
                                          _buildQueryRow(),
                                        if (modeContent != null) ...[
                                          const SizedBox(height: 12),
                                          modeContent,
                                        ],
                                        if (moreOptions != null) ...[
                                          const SizedBox(height: 4),
                                          moreOptions,
                                        ],
                                      ],
                                    ),
                                  );
                                }),
                          ),
                    ),
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

/// מציג את [missingBuilder] במקום [child] כל עוד אין אינדקס חיפוש; מתעדכן
/// גם כשהאינדוקס מסתיים (רשימת הספרים המאונדקסים אינה ניתנת להאזנה).
class _IndexMissingGate extends StatelessWidget {
  const _IndexMissingGate({required this.missingBuilder, required this.child});

  final Widget Function(IndexingState state) missingBuilder;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: TantivyDataProvider.instance.isInitialized,
      builder: (context, providerInitialized, _) =>
          BlocBuilder<IndexingBloc, IndexingState>(
            builder: (context, state) =>
                isSearchBlockedByMissingIndex(
                  providerInitialized: providerInitialized,
                )
                ? missingBuilder(state)
                : child,
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
