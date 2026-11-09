import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/layout_tokens.dart';
import 'package:otzaria/widgets/controls/toggle_pill.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/core/messages/semantic_search_messages.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/search/search_scope_preferences.dart';
import 'package:otzaria/search/view/search_scope_menu.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_event.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/utils/facet_helper.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/search/search_dialog_query.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/plugins/models/plugin_search_dialog_item.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/services/plugin_search_dialog_registry.dart';
import 'package:otzaria/plugins/services/plugin_search_selection_preferences.dart';
import 'package:otzaria/search/utils/category_query_parser.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/search/view/enhanced_search_field.dart';
import 'package:otzaria/search/view/advanced_search_controls.dart';
import 'package:otzaria/indexing/models/index_update_mode.dart';
import 'package:otzaria/search/view/full_text_settings_widgets.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/widgets/feedback/indexing_warning.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/core/ui_snack.dart';
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

/// פותח את דף התוסף עם האירוע `search.requested`.
void launchPluginSearch(
  BuildContext context,
  String pluginId,
  Map<String, dynamic> payload,
) {
  PluginPageLauncher.instance.open(
    pluginId,
    topic: 'search.requested',
    payload: payload,
    viewId: View.of(context).viewId,
    windowKeys: AppWindowKeys.of(context),
  );
}

class SearchDialogResult {
  const SearchDialogResult({
    required this.query,
    required this.searchOptions,
    required this.alternativeWords,
    required this.spacingValues,
    required this.searchMode,
    required this.distance,
    this.matchPolicy = SearchMatchPolicy.standard,
    this.searchTemplate,
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
  final InBookSearchTemplate? searchTemplate;

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

/// מקטעי בורר המצב: שלושת מצבי המנוע והחיפוש החכם.
enum _ModeChoice {
  exact(SearchMode.exact, FluentIcons.text_quote_24_regular),
  advanced(SearchMode.advanced, FluentIcons.search_info_24_regular),
  fuzzy(
    SearchMode.fuzzy,
    FluentIcons.arrow_bidirectional_left_right_24_regular,
  ),
  semantic(null, OtzariaIcons.search_in_star_24_regular);

  const _ModeChoice(this.mode, this.icon);

  /// `null` בחיפוש החכם, שאינו מצב של המנוע הלקסיקלי.
  final SearchMode? mode;
  final IconData icon;

  static _ModeChoice of(SearchMode mode) =>
      values.firstWhere((choice) => choice.mode == mode);

  String get label => mode?.shortLabel ?? kSemanticSearchModeName;

  /// במקטע צר: "חכם", כמו "מדויק" ו"מקורב" בלי "חיפוש". השם המלא ב-tooltip.
  String? get narrowLabel => mode == null ? 'חכם' : null;
}

class _SearchDialogState extends State<SearchDialog> {
  /// מאגר הפוקוס של החלון; נשמר כאן כי ב-dispose אסור לחפש ב-context.
  late final FocusRepository _focus;

  late SearchingTab _searchTab;
  late final SearchDialogQuery _query;
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
  final MenuController _defaultsMenuController = MenuController();
  late final VoidCallback _queryListener;
  late final bool _ownsSearchTab;
  late final PluginSearchDialogRegistry _pluginSearchDialogRegistry;
  late final Map<String, bool> _pluginSearchSelections;
  late Map<String, bool> _persistedPluginSelections;

  bool _semanticSelected = false;
  bool _semanticIncludeLexical =
      SearchDefaults.initialSemanticIncludeLexicalForNewSearch();
  bool _semanticGroupIdentical =
      SearchDefaults.initialSemanticGroupIdenticalForNewSearch();
  bool _semanticSubmitted = false;
  SemanticSearchBloc? _semanticBloc;
  TabsBloc? _tabsBloc;

  /// החיפוש נשלח לכרטיסייה חדשה, ולכן [SearchDialog.existingTab] זמני ומיותר.
  bool _existingTabHandedOff = false;

  /// חיפוש בספרייה, חדש או בעריכה; לא בתוך ספר (issue #1892).
  bool get _supportsSemanticMode =>
      widget.bookTitle == null &&
      widget.onSearch == null &&
      !widget.returnResultOnSubmit;

  SemanticSearchTab? get _editedSemanticTab => switch (widget.editTab) {
    final SemanticSearchTab tab => tab,
    _ => null,
  };

  /// כרטיסייה חכמה בעריכה נשארת חכמה גם לפני שהזמינות נבדקה; אחרת הדיאלוג
  /// נפתח במצב רגיל ו"עדכן חיפוש" פותח כרטיסייה רגילה חדשה (issue #1892).
  bool _semanticVisible(SemanticAvailability? availability) =>
      _editedSemanticTab != null ||
      (availability != null &&
          isSemanticModeVisible(
            availability,
            debug: widget.semanticDebugPreview,
          ));

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
    _focus = FocusRepository.of(context);
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
      final lastTyping = SearchDialogQuery.loadLastTyping();

      // בלי העדפות תצוגת התוצאות: זה טאב השירות של הדיאלוג, והמיון/האיחוד
      // שלו נראים רק בבקשת החיפוש שנשלחת לתוספים.
      _searchTab = SearchingTab.newSearch(
        "חיפוש",
        lastTyping,
        mode: widget.initialSearchMode,
        withResultPreferences: false,
      );
    }
    _query = SearchDialogQuery(
      _searchTab,
      supportsVocalizedSearch: _supportsVocalizedSearch,
    );
    if (widget.existingTab != null) _tabsBloc = context.read<TabsBloc?>();
    if (_supportsSemanticMode) {
      _semanticBloc = SemanticSearchBloc(
        repository:
            widget.semanticRepository ?? SemanticSearchRepository.instance,
      )..add(const SemanticSearchStarted());
      // מצב מבוקש במפורש (קיצור חיפוש מתקדם, איתור) וכרטיסייה בעריכה
      // גוברים על זיכרון הסשן.
      _semanticSelected =
          _editedSemanticTab != null ||
          (SearchDefaults.initialSemanticForNewSearch() &&
              widget.initialSearchMode == null &&
              widget.existingTab == null &&
              widget.editTab == null);
      if (_semanticSelected) {
        // autofocus אינו בוחר טקסט; מכינים את הבחירה לפני הרכבת השדה,
        // כדי שבדיקת הזמינות לא תדרוס בחירת סמן מאוחרת יותר.
        _searchTab.queryController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _searchTab.queryController.text.length,
        );
      }
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
      SearchDialogQuery.saveLastTyping(_searchTab.queryController.text);
    };
    _searchTab.queryController.addListener(_queryListener);

    // בקשת פוקוס לתיבת החיפוש + רישום כ-active restorer לשחזור לאחר אירועי חלון
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchTab.searchFieldFocusNode.requestFocus();
        _focusRestorer = _focus.registerActiveRestorer(
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
    // אינדקס בסכמה ישנה אינו נפתח, ואינדוקס רגיל נדחה עליו עד שיאופס.
    final rebuildRequired = TantivyDataProvider.instance.requiresManualReindex;
    return OtzariaEmptyState.large(
      icon: FluentIcons.search_24_regular,
      title: isBuilding
          ? context.settingsText('אינדקס החיפוש בבנייה')
          : rebuildRequired
          ? context.settingsText('אינדקס החיפוש דורש בנייה מחדש')
          : context.settingsText('אינדקס החיפוש לא קיים'),
      message: isBuilding
          ? context.settingsText(
              'החיפוש יתאפשר כשבניית האינדקס תסתיים. ניתן להמשיך לעיין בספרים בינתיים.',
            )
          : rebuildRequired
          ? context.settingsText(
              'האינדקס הקיים נבנה בגרסה קודמת של מנוע החיפוש, ויש לבנות אותו מחדש כדי לחפש. הבנייה רצה ברקע, וניתן להמשיך לעיין בספרים בינתיים.',
            )
          : context.settingsText(
              'כדי לחפש בתוכן הספרים יש לבנות תחילה את אינדקס החיפוש. הבנייה רצה ברקע, וניתן להמשיך לעיין בספרים בינתיים.',
            ),
      body: isBuilding
          ? Column(
              children: [
                LinearProgressIndicator(
                  value: total > 0 ? processed / total : null,
                ),
                if (total > 0) ...[
                  const SizedBox(height: AppTokens.spaceSM),
                  Text(
                    context.settingsText(
                      '{processed} מתוך {total} ספרים',
                      args: {'processed': processed, 'total': total},
                    ),
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            )
          : null,
      actions: [
        if (!isBuilding)
          // אינדוקס בזמן העדכון היה קורא ממסד שהעדכון סוגר ומחליף.
          ValueListenableBuilder<bool>(
            valueListenable: TantivyDataProvider.instance.isIndexingDeferred,
            builder: (context, deferred, _) => deferred
                ? Text(
                    context.settingsText(
                      'האינדקס ייבנה אוטומטית בסיום עדכון הספרייה.',
                    ),
                    style: TextStyle(color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  )
                : ActionButton.recommended(
                    text: rebuildRequired
                        ? context.settingsText('אפס ובנה מחדש')
                        : context.settingsText('בנה אינדקס'),
                    icon: FluentIcons.play_24_regular,
                    onPressed: () async {
                      final indexingBloc = context.read<IndexingBloc>();
                      // העץ המלא: העץ של LibraryBloc מסונן מהסתרות.
                      final library = await DataRepository.instance.library;
                      indexingBloc.add(
                        rebuildRequired
                            ? ResetAndIndex(library)
                            : StartIndexing(library),
                      );
                    },
                  ),
          ),
        ActionButton.neutral(
          text: context.settingsText('הגדרות ספרייה'),
          icon: FluentIcons.settings_24_regular,
          onPressed: () {
            final mainScreen = AppWindowKeys.of(
              context,
            ).mainWindowScreen.currentState;
            Navigator.of(context).pop();
            mainScreen?.handleInternalDeepLink(
              'otzaria://open/settings/library',
            );
          },
        ),
      ],
    );
  }

  /// אפשרויות המילה של החיפוש הרגיל (מדויק): שגיאות כתיב, קידומות/סיומות
  /// דקדוקיות, כתיב מלא/חסר וחלק ממילה — מוחלות גלובלית על כל מילות
  /// השאילתה. בקשה עם אפשרות פעילה רצה בפועל דרך המסלול המתקדם של המנוע
  /// (ראה gateway), כך שאין צורך בשינוי מנוע.
  Widget _buildExactOptionsRow(
    Set<String> disabledOptionIds,
    List<String> keys, {
    List<Widget> trailing = const [],
  }) {
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
          ...trailing,
        ],
      ),
    );
  }

  /// "שמור על סדר המילים המקורי" בחיפוש הרגיל, בסגנון שאר אפשרויות המילה.
  Widget _buildWordOrderChip(SearchState state) {
    return Tooltip(
      message: context.settingsText(
        'כשמבוטל, מילות החיפוש נמצאות בכל סדר בתוך מגבלת המרווח.',
      ),
      child: FilterChip(
        key: const ValueKey('search-word-order-chip'),
        label: Text(context.settingsText('שמור על סדר המילים המקורי')),
        visualDensity: VisualDensity.compact,
        selected: !state.anyOrder,
        onSelected: (keepOrder) => _searchTab.searchBloc.add(
          _usesStagedSubmit
              ? UpdateWordOrderWithoutSearch(!keepOrder)
              : UpdateWordOrder(!keepOrder),
        ),
      ),
    );
  }

  /// קביעת מצב החיפוש הנוכחי כמצב שבו ייפתח כל חיפוש חדש. הפריט בתפריט
  /// נלחץ בטעות, ולכן השמירה עוברת דרך אישור. [mode] הוא null במצב החכם.
  Future<void> _confirmSetModeAsDefault(SearchMode? mode) async {
    final modeLabel = context.settingsText(
      mode?.shortLabel ?? kSemanticSearchModeLabel,
    );
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
    if (mode == null) {
      SearchDefaults.saveSemanticDefault();
    } else {
      SearchDefaults.saveModeDefault(mode);
    }
    UiSnack.show(LibraryMessages.searchModeSetAsDefault(modeLabel));
  }

  /// תפריט ברירות המחדל של המצב הנוכחי — פעולה נדירה, ולכן בתפריט
  /// בשורה התחתונה ולא בגוף החלונית.
  Widget _buildDefaultsMenu(
    SearchState state, {
    required bool semanticActive,
  }) {
    final mode = state.configuration.searchMode;
    // אפשרויות המילה והמרווח שייכים למצב הלקסיקלי, ואינם חלים על החכם.
    final hasWordOptions = !semanticActive && mode != SearchMode.fuzzy;
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
      final bloc = _searchTab.searchBloc;
      final savedDistance = SearchDefaults.loadDistanceDefault();
      final savedPolicy = SearchDefaults.loadMatchPolicyDefault();
      // הכל בשקט, וחיפוש אחד בסוף — כמו בבורר הטווח.
      bloc.add(UpdateDistanceWithoutSearch(savedDistance));
      bloc.add(
        UpdateWordOrderWithoutSearch(SearchDefaults.loadAnyOrderDefault()),
      );
      if (!isExact) {
        bloc.add(UpdateProximityScopeWithoutSearch(savedPolicy.proximityScope));
        bloc.add(
          UpdateWordMatchModeWithoutSearch(
            savedPolicy.wordMatchMode,
            count: savedPolicy.wordMatchCount,
          ),
        );
      }
      if (!_usesStagedSubmit) bloc.add(const RerunSearch());
    }

    void saveAnyOrderDefault(bool keepOrder) {
      setState(() => SearchDefaults.saveAnyOrderDefault(!keepOrder));
      // כמו אפשרויות המילה: ברירת מחדל חדשה מוחלת מיד גם על החלונית הפתוחה.
      _searchTab.searchBloc.add(
        _usesStagedSubmit
            ? UpdateWordOrderWithoutSearch(!keepOrder)
            : UpdateWordOrder(!keepOrder),
      );
    }

    void saveMatchPolicyDefault() {
      final policy = state.configuration.matchPolicy;
      setState(() => SearchDefaults.saveMatchPolicyDefault(policy));
      UiSnack.show(
        LibraryMessages.proximitySetAsDefault(
          policy.proximityScope.label,
          policy.wordMatchMode == WordMatchMode.atLeast
              ? 'לפחות ${policy.wordMatchCount} מילים'
              : policy.wordMatchMode.label,
        ),
      );
    }

    return MenuAnchor(
      controller: _defaultsMenuController,
      menuChildren: [
        MenuItemButton(
          key: const ValueKey('search-dialog-default-mode'),
          leadingIcon: const Icon(FluentIcons.bookmark_24_regular),
          onPressed: () =>
              _confirmSetModeAsDefault(semanticActive ? null : mode),
          child: Text(context.settingsText('קבע מצב זה כברירת מחדל')),
        ),
        if (hasWordOptions)
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
              CheckboxMenuButton(
                key: const ValueKey('search-dialog-default-word-order'),
                value: !SearchDefaults.loadAnyOrderDefault(),
                closeOnActivate: false,
                onChanged: (checked) => saveAnyOrderDefault(checked ?? true),
                child: Text(context.settingsText('שמור על סדר המילים המקורי')),
              ),
              if (!isExact)
                MenuItemButton(
                  key: const ValueKey('search-dialog-default-proximity'),
                  closeOnActivate: false,
                  onPressed: saveMatchPolicyDefault,
                  child: Text(
                    context.settingsText(
                      'קבע את טווח הקרבה הנוכחי ({scope}) כברירת מחדל',
                      args: {
                        'scope': _matchPolicyLabel(
                          state.configuration.matchPolicy,
                        ),
                      },
                    ),
                  ),
                ),
            ],
            leadingIcon: const Icon(FluentIcons.options_24_regular),
            child: Text(
              isExact
                  ? context.settingsText('קביעת ברירת מחדל לחיפוש רגיל')
                  : context.settingsText('קביעת ברירת מחדל לחיפוש מתקדם'),
            ),
          ),
        if (hasWordOptions)
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

  String _matchPolicyLabel(SearchMatchPolicy policy) {
    final mode = policy.wordMatchMode == WordMatchMode.atLeast
        ? context.settingsText(
            'לפחות {count} מילים',
            args: {'count': policy.wordMatchCount},
          )
        : context.settingsText(policy.wordMatchMode.label);
    return '${context.settingsText(policy.proximityScope.label)} · $mode';
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
                      size: AppTokens.iconSM,
                    ),
                    title: Text(
                      displayText,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 14),
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        FluentIcons.delete_24_regular,
                        size: AppTokens.iconSM,
                      ),
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
    if (restorer != null) _focus.unregisterActiveRestorer(restorer);
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
          SearchDefaults.rememberSessionAnyOrder(config.anyOrder);
        }
        if (config.searchMode == SearchMode.advanced) {
          SearchDefaults.rememberSessionMatchPolicy(config.matchPolicy);
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
        ..addAll(SearchDefaults.initialOptionsForMode(newMode));
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

    if (_searchTab.queryController.text.trim().isEmpty) {
      UiSnack.show(LibraryMessages.emptySearchQuery);
      return;
    }

    final normalizedQueries = _query.normalizedQueries(_library);
    final parsedCategory = normalizedQueries.category;
    if (parsedCategory.hasCategoryToken && !parsedCategory.categoryFound) {
      UiSnack.showError(
        LibraryMessages.categoryOrBookNotFound(parsedCategory.notFoundNames),
      );
      return;
    }
    final query = normalizedQueries.query;
    final negativeQuery = normalizedQueries.negativeQuery;
    if (query.isEmpty) {
      UiSnack.show(LibraryMessages.emptySearchQuery);
      return;
    }

    // שמירת מצב החיפוש האחרון
    final currentState = _searchTab.searchBloc.state;
    final currentMode = currentState.configuration.searchMode;
    final (
      positive: normalizedParameters,
      negative: normalizedNegativeParameters,
      alternatives: effectiveAlternatives,
    ) = _query.normalizedParameters(
      query: query,
      negativeQuery: negativeQuery,
    );
    if (widget.returnResultOnSubmit) {
      final requestedPolicy = currentState.configuration.matchPolicyWithSpacing(
        normalizedParameters.customSpacing,
      );
      final wordDefaults = _searchTab.useGlobalSearchOptions.value
          ? SearchQueryBuilder.normalizeGlobalOptionsForMode(
              currentMode,
              _searchTab.globalSearchOptions,
            )
          : null;
      Navigator.of(context).pop(
        SearchDialogResult(
          query: query,
          searchOptions: normalizedParameters.searchOptions,
          alternativeWords: normalizedParameters.alternativeWords,
          spacingValues: normalizedParameters.customSpacing,
          searchMode: currentMode,
          distance: _searchTab.searchBloc.state.distance,
          matchPolicy: currentState.configuration.matchPolicyWithSpacing(
            normalizedParameters.customSpacing,
            query: query,
          ),
          searchTemplate: wordDefaults == null && requestedPolicy.isStandard
              ? null
              : InBookSearchTemplate(
                  wordDefaults: wordDefaults,
                  requestedPolicy: requestedPolicy,
                ),
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

    final facetsToSearch = SearchDialogQuery.facetsToSearch(
      parsedCategory,
      _scopeSelection,
    );
    final distance = _searchTab.searchBloc.state.distance;
    final configuration = currentState.configuration;
    final proximityScope = configuration.proximityScope;

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
        configuration: configuration,
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
          wordMatchMode: configuration.wordMatchMode,
          wordMatchCount: configuration.wordMatchCount,
          anyOrder: configuration.anyOrder,
          currentFacets: facetsToSearch,
          searchScopeFacets: facetsToSearch,
          pluginSearchSelections: _allPluginSearchSelections(),
        ),
      ),
    );

    _query.copyParametersTo(
      newSearchTab,
      query: query,
      negativeQuery: negativeQuery,
      effectiveAlternatives: effectiveAlternatives,
    );

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
  Library? get _library => context.read<LibraryBloc>().state.library;

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
    final library = _library;
    final parsedCategory = parseCategoryQuery(
      _searchTab.queryController.text,
      library,
    );
    if (parsedCategory.hasCategoryToken && !parsedCategory.categoryFound) {
      UiSnack.showError(
        LibraryMessages.categoryOrBookNotFound(parsedCategory.notFoundNames),
      );
      return;
    }
    final query = parsedCategory.query;
    if (query.trim().isEmpty) {
      UiSnack.show(LibraryMessages.emptySearchQuery);
      return;
    }
    final isOfficialCategory = officialCategoryFilter(library);
    final selection = parsedCategory.categoryFound
        ? [
            ...parsedCategory.facets!,
            ...FacetHelper.dimensionFacetsOf(_scopeSelection),
          ]
        : _scopeSelection;
    if (!selection.every(
      (facet) => isSemanticScopeFacetSupported(
        facet,
        includeLexical: _semanticIncludeLexical,
        isOfficialCategory: isOfficialCategory,
      ),
    )) {
      UiSnack.showError(SemanticSearchMessages.unsupportedScope);
      return;
    }
    _semanticSubmitted = true;
    _existingTabHandedOff = true;
    SearchDefaults.rememberSessionSemantic(true);
    final options = SemanticQueryOptions(
      query: query,
      facets: semanticScopeFacets(selection),
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
    SearchDefaults.rememberSessionSemantic(false);
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
      onIncludeLexicalChanged: (value) {
        setState(() => _semanticIncludeLexical = value);
        // עריכת כרטיסייה קיימת אינה משנה את ברירת המחדל לחיפוש חדש.
        if (widget.editTab == null) {
          SearchDefaults.saveSemanticIncludeLexicalDefault(value);
        }
      },
      groupIdenticalText: _semanticGroupIdentical,
      onGroupIdenticalTextChanged: (value) {
        setState(() => _semanticGroupIdentical = value);
        if (widget.editTab == null) {
          SearchDefaults.saveSemanticGroupIdenticalDefault(value);
        }
      },
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

    final request = pluginSearchRequest(
      query: query,
      negativeQuery: negativeQuery,
      mode: mode,
      distance: distance,
      proximityScope: proximityScope,
      facets: facets,
      configuration: _searchTab.searchBloc.state.configuration,
      normalizedParameters: normalizedParameters,
      normalizedNegativeParameters: normalizedNegativeParameters,
    );
    final launch =
        widget.pluginSearchSubmitLauncher ??
        (pluginId, payload) => launchPluginSearch(context, pluginId, payload);
    for (final target in targets) {
      launch(target.$1, {'itemId': target.$2.id, 'request': request});
    }
    return true;
  }

  /// מחיל את פרמטרי הדיאלוג על טאב התוצאות הנערך ומריץ בו את החיפוש מחדש.
  void _applyEditToTarget({
    required String query,
    required String negativeQuery,
    required SearchMode mode,
    required int distance,
    required SearchConfiguration configuration,
    required List<String> facetsToSearch,
    required Map<int, List<String>> effectiveAlternatives,
    required SearchModeScopedParameters normalizedParameters,
    required SearchModeScopedParameters normalizedNegativeParameters,
  }) {
    final target = widget.editTab!;
    _query.copyParametersTo(
      target,
      query: query,
      negativeQuery: negativeQuery,
      effectiveAlternatives: effectiveAlternatives,
    );
    target.updateTitleFromAppliedQuery(query);

    target.searchBloc.add(SetSearchModeWithoutSearch(mode));
    target.searchBloc.add(UpdateDistanceWithoutSearch(distance));
    target.searchBloc.add(
      UpdateProximityScopeWithoutSearch(configuration.proximityScope),
    );
    target.searchBloc.add(
      UpdateWordMatchModeWithoutSearch(
        configuration.wordMatchMode,
        count: configuration.wordMatchCount,
      ),
    );
    target.searchBloc.add(UpdateWordOrderWithoutSearch(configuration.anyOrder));
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
        proximityScope: configuration.proximityScope,
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

  String _title() => widget.editTab != null
      ? context.settingsText('עריכת חיפוש')
      : widget.bookTitle != null
      ? context.settingsText('חיפוש ב{book}', args: {'book': widget.bookTitle})
      : context.settingsText('חיפוש בספרייה');

  /// בורר מצב החיפוש — מקטעים ברוחב מלא; ההסבר של כל מצב ב-tooltip.
  /// במדידה: האייקונים יורדים והתוויות מתקצרות כשאין להן מקום, ורק כשגם אז
  /// תווית נחתכת (באנגלית ב-320–360, או בטקסט מוגדל) — 2×2 עם התוויות המלאות
  /// (סקירה שלישית של 4.11, q-ss7).
  Widget _buildModeSelector(
    BuildContext context,
    SearchState state,
    SemanticAvailability? semanticAvailability,
  ) {
    final semanticVisible = _semanticVisible(semanticAvailability);
    final current = _semanticSelected && semanticVisible
        ? _ModeChoice.semantic
        : _ModeChoice.of(state.configuration.searchMode);

    return AppSegmentedControl<_ModeChoice>(
      expandToFillWidth: true,
      twoRowsWhenClipped: true,
      currentValue: current,
      options: [
        for (final choice in _ModeChoice.values)
          if (choice != _ModeChoice.semantic || semanticVisible)
            SegmentOption(
              value: choice,
              label: context.settingsText(choice.label),
              shortLabel: switch (choice.narrowLabel) {
                final short? => context.settingsText(short),
                null => null,
              },
              icon: choice.icon,
              tooltip: _modeTooltip(choice),
              labelKey: choice == _ModeChoice.semantic
                  ? const ValueKey('search-dialog-semantic-mode')
                  : null,
            ),
      ],
      onChanged: _onModeChoice,
    );
  }

  String _modeTooltip(_ModeChoice choice) {
    final mode = choice.mode;
    if (mode != null) return context.settingsText(mode.tooltip);
    final name = context.settingsText(kSemanticSearchModeLabel);
    final description = context.settingsText(
      'מוצא קטעים שעוסקים בעניין שתיארתם, גם כשהמילים שונות.',
    );
    return '$name\n$description';
  }

  void _onModeChoice(_ModeChoice choice) {
    final mode = choice.mode;
    SearchDefaults.rememberSessionSemantic(mode == null);
    if (mode == null) {
      setState(() => _semanticSelected = true);
    } else {
      _semanticSelected = false;
      final oldMode = _searchTab.searchBloc.state.configuration.searchMode;
      _searchTab.searchBloc.add(
        !_usesStagedSubmit
            ? SetSearchMode(mode)
            : SetSearchModeWithoutSearch(mode),
      );
      _swapGlobalOptionsForModeChange(oldMode, mode);
      setState(() => _moreOptionsExpanded = null);
    }
    _searchTab.searchFieldFocusNode.requestFocus();
  }

  /// כפתור היסטוריית החיפושים שבסוף שדה החיפוש.
  Widget _buildHistoryButton() {
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    const menuWidth = 360.0, fullWidthBelow = 420.0, margin = 24.0;
    final historyMenuWidth = screenWidth < fullWidthBelow
        ? screenWidth - 2 * margin
        : menuWidth;
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
            side: BorderSide(
              color:
                  AppSurfaces.regionBorder(context) ??
                  colorScheme.outlineVariant,
            ),
          ),
        ),
      ),
      menuChildren: [
        SizedBox(width: historyMenuWidth, child: _buildHistoryDropdown()),
      ],
      builder: (context, controller, _) => OtzariaSearchAction.icon(
        iconData: controller.isOpen
            ? FluentIcons.chevron_up_24_regular
            : FluentIcons.history_24_regular,
        tooltip: context.settingsText('היסטוריית חיפושים'),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  /// שדה החיפוש עם כפתור ההיסטוריה, ומתחתיו שורה אחת של "איפה ואיך":
  /// היקף החיפוש ופקד המרווח/המרחק.
  Widget _buildQueryRow() {
    final searchField = EnhancedSearchField(
      key: AppWindowKeys.of(context).enhancedSearchField,
      tab: _searchTab,
      onSubmit: _performSearch,
      trailingAction: _buildHistoryButton(),
      pluginInvocationContext: () => _query.pluginInvocationContext(
        library: _library,
        scopeSelection: _scopeSelection,
        pluginSelections: _allPluginSearchSelections(),
      ),
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
            excludeUserBooks:
                !IndexUpdateMode.readStored().indexesPersonalBooks,
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
            labelText: context.settingsText('ללא', context: 'searchExclude'),
            hintText: context.settingsText(
              'תוצאות שמכילות מילים אלו לא יופיעו',
            ),
            prefixIcon: const Icon(FluentIcons.subtract_24_regular),
            suffixIcon: OtzariaSearchClearButton(
              controller: _searchTab.negativeQueryController,
              onCleared: () => setState(() {}),
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
        // ui-lint: allow UIL-017 — כותרת קטנה 13 של דיאלוג החיפוש ואיתור המקורות נשארת (DD-14, השלמה 2.11)
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

    final pluginItems = _visiblePluginItems(mode);
    if (mode == SearchMode.exact) {
      final keys = SearchQueryBuilder.exactWordOptionKeys
          .where((key) => !_primaryExactOptionKeys.contains(key))
          .toList();
      // פריטי התוסף באותה שורת שבבים, כמו שאר האפשרויות (q10 Q8e).
      sections.add(
        _buildExactOptionsRow(
          _disabledSearchOptionIds(state),
          keys,
          trailing: [
            _buildWordOrderChip(state),
            ..._buildPluginSearchChips(pluginItems),
          ],
        ),
      );
      hasActive |=
          keys.any((key) => _searchTab.globalSearchOptions[key] ?? false) ||
          state.anyOrder;
    }
    if (mode == SearchMode.advanced &&
        widget.onSearch == null &&
        !widget.returnResultOnSubmit) {
      sections.add(_buildNegativeSection());
      hasActive |= _searchTab.negativeQueryController.text.trim().isNotEmpty;
    }
    if (pluginItems.isNotEmpty) {
      if (mode != SearchMode.exact) {
        sections.add(
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _buildPluginSearchChips(pluginItems),
            ),
          ),
        );
      }
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

  bool _pluginSelectionValue(String pluginId, PluginSearchDialogItem item) {
    final key = _pluginSelectionKey(pluginId, item.id);
    return PluginSearchSelectionPreferences.resolveSelection(
      item,
      tabValue: _pluginSearchSelections[key],
      persistedValue: _persistedPluginSelections[key],
    );
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
    final persisted = PluginSearchSelectionPreferences.persistedAfterChange(
      _persistedPluginSelections,
      key,
      item,
      value,
    );
    if (persisted != null) {
      _persistedPluginSelections = persisted;
      PluginSearchSelectionPreferences.save(persisted);
    }
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

  /// פריטי התוסף בשפה של שאר האפשרויות: תיבה היא FilterChip ומתג הוא
  /// AppTogglePill, כמו במצב המתקדם (q10 Q8e).
  List<Widget> _buildPluginSearchChips(
    List<(String, PluginSearchDialogItem)> visibleItems,
  ) {
    return [
      for (final (pluginId, item) in visibleItems)
        if (item.isSwitch)
          AppTogglePill(
            key: ValueKey('plugin-search-dialog-$pluginId-${item.id}'),
            label: item.title,
            value: _pluginSelectionValue(pluginId, item),
            onChanged: (value) =>
                _updatePluginSearchSelection(pluginId, item, value),
          )
        else
          FilterChip(
            key: ValueKey('plugin-search-dialog-$pluginId-${item.id}'),
            label: Text(item.title),
            visualDensity: VisualDensity.compact,
            selected: _pluginSelectionValue(pluginId, item),
            onSelected: (value) =>
                _updatePluginSearchSelection(pluginId, item, value),
          ),
    ];
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 24, 14),
      child: Row(
        children: [
          BlocBuilder<SearchBloc, SearchState>(
            builder: (context, state) => _withSemanticAvailability(
              (availability) => _buildDefaultsMenu(
                state,
                semanticActive:
                    _semanticSelected && _semanticVisible(availability),
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
    final screenHeight = MediaQuery.sizeOf(context).height;
    final isCompact = WindowClass.of(context).isCompact;
    // גובה קבוע: פתיחת "אפשרויות נוספות" או מעבר מצב לא מקפיצים את החלון.
    final dialogHeight = screenHeight < 560
        ? screenHeight - 24
        : (screenHeight * 0.84).clamp(500.0, 720.0);
    final horizontalPadding = isCompact ? 16.0 : 24.0;

    return BlocProvider.value(
      value: _searchTab.searchBloc,
      child: AppDialogFrame(
        surfaceKey: TourTargetKeys.of(context).searchDialog,
        icon: FluentIcons.search_24_regular,
        title: _title(),
        // בחיפוש בתוך ספר אין תפריט היקף, ולכן אין להבטיח אותו בכותרת.
        subtitle: context.settingsText(
          widget.bookTitle == null
              ? 'בחר שאילתה, סוג חיפוש והיקף'
              : 'בחר שאילתה וסוג חיפוש',
        ),
        subtitleMaxLines: 1,
        fitTitle: true,
        size: AppDialogSize.large,
        height: dialogHeight,
        padding: EdgeInsets.zero,
        backgroundColor: AppSurfaces.panelBackground(context),
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
            // התפריטים נפתחים בלי להזיז את הפוקוס מהשדה, ולכן Escape מגיע לכאן
            // ולא לתפריט — סוגרים קודם תפריט פתוח, ורק אחר כך את הדיאלוג.
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              for (final menu in [
                _historyMenuController,
                _defaultsMenuController,
              ]) {
                if (menu.isOpen) {
                  menu.close();
                  return KeyEventResult.handled;
                }
              }
            }
            return KeyEventResult.ignored;
          },
          child: SizedBox.expand(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
