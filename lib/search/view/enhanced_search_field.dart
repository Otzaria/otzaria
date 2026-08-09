import 'package:flutter/material.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/search/utils/category_query_parser.dart';
import 'package:otzaria/search/view/tantivy_full_text_search.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

class EnhancedSearchField extends StatefulWidget {
  final dynamic widget;

  /// callback חיצוני שיופעל במקום לוגיקת החיפוש הפנימית כשמוגדר.
  /// משמש בדיאלוג החיפוש המתקדם כך ש-Enter מוליך לחיפוש הנכון.
  final VoidCallback? onSubmit;

  /// ווידג'ט נוסף שיוצג לפני כפתור המחיקה (למשל כפתור ההיסטוריה).
  final Widget? trailingAction;

  const EnhancedSearchField({
    super.key,
    required this.widget,
    this.onSubmit,
    this.trailingAction,
  });

  SearchingTab get tab {
    // Support both TantivyFullTextSearch and _SearchDialogWrapper
    if (widget is TantivyFullTextSearch) {
      return (widget as TantivyFullTextSearch).tab;
    } else {
      // Assume it's _SearchDialogWrapper or similar with a tab property
      return widget.tab as SearchingTab;
    }
  }

  @override
  State<EnhancedSearchField> createState() => _EnhancedSearchFieldState();
}

// GlobalKey לגישה ל-State מבחוץ
final GlobalKey enhancedSearchFieldKey = GlobalKey();

class _EnhancedSearchFieldState extends State<EnhancedSearchField> {
  late final FocusNode _keyboardListenerFocusNode;

  @override
  void initState() {
    super.initState();
    _keyboardListenerFocusNode = FocusNode(
      debugLabel: 'enhanced_search_field_keyboard_listener',
      skipTraversal: true,
      canRequestFocus: false,
    );
    widget.tab.queryController.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant EnhancedSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tab, widget.tab)) {
      oldWidget.tab.queryController.removeListener(_onTextChanged);
      widget.tab.queryController.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.tab.queryController.removeListener(_onTextChanged);
    _keyboardListenerFocusNode.dispose();
    // בכוונה לא מנקים כאן את אפשרויות הטאב: הטאב שייך לבעליו (דיאלוג
    // החיפוש או טאב תוצאות חי), וה-dispose של השדה רץ לפני זה של הדיאלוג
    // — ניקוי כאן היה מרוקן את האפשרויות רגע לפני שהדיאלוג זוכר אותן
    // לסשן, ובטאב חי היה מוחק אפשרויות של חיפוש פעיל.
    super.dispose();
  }

  void _onTextChanged() {
    // שדה שהתרוקן: האפשרויות הפר-מיליות נגזרות ממילים שכבר אינן ולכן
    // נמחקות. האפשרויות הגלובליות אינן תלויות בשאילתה ונשארות — הן נזרעות
    // מברירת המחדל/הסשן, ומחיקתן כאן הייתה מוחקת סימונים בכל התרוקנות.
    if (widget.tab.queryController.text.trim().isEmpty) {
      widget.tab.searchOptions.clear();
    }
  }

  void _clearField() {
    widget.tab.queryController.clear();
    widget.tab.searchOptions.clear();
    widget.tab.globalSearchOptions.clear();
    context.read<SearchBloc>().add(UpdateSearchQuery(''));
    context.read<SearchBloc>().add(UpdateFacetCounts({}));
    widget.tab.searchFieldFocusNode.requestFocus();
  }

  void _performSearch() {
    // אם קיים callback חיצוני (למשל מהדיאלוג), משתמשים בו במקום לוגיקת החיפוש הפנימית
    if (widget.onSubmit != null) {
      widget.onSubmit!();
      return;
    }

    String query = widget.tab.queryController.text.trim();
    if (query.isEmpty) return;

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
    if (query.isEmpty) return;

    // אם הוקלד תחביר `@`, מנקים אותו מהשדה — ההיסטוריה שומרת את טקסט השדה,
    // והשחזור ממנה אינו מפענח `@` מחדש (אחרת יחפש מילולית "שלום@תורה").
    if (widget.tab.queryController.text != query) {
      widget.tab.queryController.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }

    // חיפוש רגיל עובד על טקסט ללא ניקוד; כשאפשרות "ניקוד"/"טעמים" מסומנת
    // (במצב מתקדם, גלובלית או פר-מילה) הסימנים שהוקלדו הם חלק מהשאילתה —
    // המנוע דורש אותם — ואסור למחוק. הבדיקה על מפות המקור, כי האפשרויות
    // האפקטיביות נבנות מהשאילתה אחרי המחיקה.
    final fieldConfig = widget.tab.searchBloc.state.configuration;
    final vocalizedSearch =
        fieldConfig.searchMode == SearchMode.advanced &&
        (widget.tab.useGlobalSearchOptions.value
            ? SearchQueryBuilder.globalOptionsRequestVocalized(
                widget.tab.globalSearchOptions,
              )
            : SearchQueryBuilder.optionsRequestVocalized(
                widget.tab.searchOptions,
              ));
    if (!vocalizedSearch && utils.hasNikud(query)) {
      query = utils.removeVolwels(query);
    }

    final searchMode = fieldConfig.searchMode;
    final normalizedParameters = SearchQueryBuilder.normalizeParametersForMode(
      searchMode,
      customSpacing: widget.tab.spacingValues,
      alternativeWords: widget.tab.alternativeWords,
      searchOptions: widget.tab.effectiveSearchOptions(query: query),
    );
    final normalizedNegativeParameters =
        SearchQueryBuilder.normalizeParametersForMode(
          searchMode,
          customSpacing: widget.tab.negativeSpacingValues,
          alternativeWords: widget.tab.negativeAlternativeWords,
          searchOptions: widget.tab.effectiveNegativeSearchOptions(
            query: widget.tab.negativeQueryController.text,
          ),
        );

    widget.tab.updateTitleFromAppliedQuery(query);
    // תחביר `@קטגוריה`/`@ספר` גובר על scope הקיים של הטאב. מעבירים את
    // ה-scope במפורש להיסטוריה כדי שלא ייאבד עד שה-SearchBloc יעדכן state.
    context.read<HistoryBloc>().add(
      AddHistory(
        widget.tab,
        scopeFacets: parsedCategory.categoryFound
            ? parsedCategory.facets
            : null,
      ),
    );
    if (parsedCategory.categoryFound) {
      context.read<SearchBloc>().add(
        SetFacetsWithoutSearch(parsedCategory.facets!),
      );
    }
    context.read<SearchBloc>().add(
      UpdateSearchQuery(
        query,
        negativeQuery: widget.tab.negativeQueryController.text,
        customSpacing: normalizedParameters.customSpacing,
        alternativeWords: normalizedParameters.alternativeWords,
        searchOptions: normalizedParameters.searchOptions,
        negativeCustomSpacing: normalizedNegativeParameters.customSpacing,
        negativeAlternativeWords: normalizedNegativeParameters.alternativeWords,
        negativeSearchOptions: normalizedNegativeParameters.searchOptions,
      ),
    );
    widget.tab.isLeftPaneOpen.value = false;
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardListenerFocusNode,
      onKeyEvent: (KeyEvent event) {
        // טיפול ב-Enter גם כשהפוקוס לא בתיבת החיפוש
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter &&
            !widget.tab.searchFieldFocusNode.hasFocus) {
          _performSearch();
        }
      },
      child: OtzariaSearchField(
        controller: widget.tab.queryController,
        focusNode: widget.tab.searchFieldFocusNode,
        hintText: 'הקלד מילות חיפוש',
        onSubmitted: (_) => _performSearch(),
        onClear: _clearField,
        trailingActions: widget.trailingAction == null
            ? null
            : [widget.trailingAction!],
      ),
    );
  }
}
