import 'package:flutter/material.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/plugins/models/plugin_search_field_action.dart';
import 'package:otzaria/plugins/view/plugin_search_field_actions.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/view/layout_fix_suggestion_banner.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/utils/category_query_parser.dart';
import 'package:otzaria/search/view/tantivy_full_text_search.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

class EnhancedSearchField extends StatefulWidget {
  final dynamic widget;

  /// האם להציג את כפתור החיפוש המובנה בתוך השדה.
  final bool showInlineSearchButton;

  /// callback חיצוני שיופעל במקום לוגיקת החיפוש הפנימית כשמוגדר.
  /// משמש בדיאלוג החיפוש המתקדם כך ש-Enter מוליך לחיפוש הנכון.
  final VoidCallback? onSubmit;

  /// ווידג'ט נוסף שיוצג בתוך ה-suffixIcon (לפני כפתור המחיקה).
  /// משמש להוספת כפתורים כגון היסטוריה, בלי לגרום לחפיפה עם תוכן הטקסט.
  final Widget? trailingAction;

  /// ההקשר שנשלח לתוסף בלחיצה על כפתורו; ראו [PluginSearchFieldActions].
  final Map<String, dynamic> Function()? pluginInvocationContext;

  const EnhancedSearchField({
    super.key,
    required this.widget,
    this.showInlineSearchButton = true,
    this.onSubmit,
    this.trailingAction,
    this.pluginInvocationContext,
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

class _EnhancedSearchFieldState extends State<EnhancedSearchField> {
  static const double _kSearchFieldMinWidth = 300;
  static const double _kControlHeight = 48;

  @override
  void initState() {
    super.initState();
    _attachTabListeners(widget.tab);
  }

  void _attachTabListeners(SearchingTab tab) {
    tab.queryController.addListener(_onTextChanged);
  }

  void _detachTabListeners(SearchingTab tab) {
    tab.queryController.removeListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant EnhancedSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tab, widget.tab)) {
      _detachTabListeners(oldWidget.tab);
      _attachTabListeners(widget.tab);
    }
  }

  @override
  void dispose() {
    _detachTabListeners(widget.tab);
    // בכוונה לא מנקים כאן את אפשרויות הטאב: הטאב שייך לבעליו (דיאלוג
    // החיפוש או טאב תוצאות חי), וה-dispose של השדה רץ לפני זה של הדיאלוג
    // — ניקוי כאן היה מרוקן את האפשרויות רגע לפני שהדיאלוג זוכר אותן
    // לסשן, ובטאב חי היה מוחק אפשרויות של חיפוש פעיל.
    super.dispose();
  }

  void _onTextChanged() {
    // אם שדה החיפוש התרוקן, נקה את האפשרויות הפר-מיליות (המפתחות שלהן
    // נגזרים ממילים שכבר אינן). האפשרויות הגלובליות אינן תלויות בשאילתה
    // ונשארות — הן נזרעות מברירת המחדל/הסשן ומחיקתן כאן הייתה מוחקת את
    // הסימונים בכל התרוקנות של השדה.
    if (widget.tab.queryController.text.trim().isEmpty) {
      widget.tab.searchOptions.clear();
    }
  }

  void _performSearch() {
    // אם קיים callback חיצוני (למשל מהדיאלוג), משתמשים בו במקום לוגיקת החיפוש הפנימית
    if (widget.onSubmit != null) {
      widget.onSubmit!();
      return;
    }

    String query = widget.tab.queryController.text.trim();
    if (query.isNotEmpty) {
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

      if (!widget.tab.requestsVocalizedSearch && utils.hasNikud(query)) {
        query = utils.removeVolwels(query);
      }

      final searchEvent = searchQueryEventForTab(widget.tab, query);

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
      context.read<SearchBloc>().add(searchEvent);
      widget.tab.isLeftPaneOpen.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: _kSearchFieldMinWidth,
                    minHeight: _kControlHeight,
                  ),
                  child: Tooltip(
                    message: context.settingsText(
                      'הקלד מילות חיפוש ולחץ Enter או על סמל החיפוש כדי לבצע חיפוש.',
                    ),
                    child: RtlTextField(
                      focusNode: widget.tab.searchFieldFocusNode,
                      controller: widget.tab.queryController,
                      onSubmitted: (e) {
                        _performSearch();
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHigh,
                        hintText: context.settingsText(
                          'הקלד מילות חיפוש · לצמצום: מצה@רשי/פסחים',
                        ),
                        labelText: context.settingsText('חיפוש'),
                        prefixIcon: widget.showInlineSearchButton
                            ? IconButton(
                                onPressed: _performSearch,
                                icon: const Icon(
                                  OtzariaIcons.search_24_regular,
                                ),
                              )
                            : const Icon(OtzariaIcons.search_24_regular),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PluginSearchFieldActions(
                              field: PluginSearchField.fullText,
                              controller: widget.tab.queryController,
                              onSubmitted: (_) => _performSearch(),
                              invocationContext: widget.pluginInvocationContext,
                              buttonSize: 40,
                              iconSize: 22,
                            ),
                            ?widget.trailingAction,
                            OtzariaSearchClearButton(
                              controller: widget.tab.queryController,
                              showWhenEmpty: true,
                              onCleared: () {
                                widget.tab.searchOptions.clear();
                                widget.tab.globalSearchOptions.clear();
                                context.read<SearchBloc>().add(
                                  UpdateSearchQuery(''),
                                );
                                context.read<SearchBloc>().add(
                                  UpdateFacetCounts({}),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // הצעת תיקון-מקלדת חיה תוך כדי הקלדה (issue #975):
              // מוצגת רק כשהטקסט נראה כהקלדה עברית במצב אנגלי,
              // ולחיצה מחליפה את תוכן השדה בלבד — החיפוש לא רץ מעצמו.
              TypingLayoutFixSuggestion(
                controller: widget.tab.queryController,
                fieldFocusNode: widget.tab.searchFieldFocusNode,
                hint: 'לחיצה תחליף את הטקסט שהוקלד',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
