import 'package:flutter/material.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/plugins/models/plugin_search_field_action.dart';
import 'package:otzaria/plugins/view/plugin_search_field_actions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/view/layout_fix_suggestion_banner.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

class EnhancedSearchField extends StatefulWidget {
  final SearchingTab tab;

  /// האם להציג את כפתור החיפוש המובנה בתוך השדה.
  final bool showInlineSearchButton;

  /// מגיש את החיפוש: Enter בשדה, כפתור החיפוש או שליחה מכפתור תוסף.
  final VoidCallback onSubmit;

  /// ווידג'ט נוסף שיוצג בתוך ה-suffixIcon (לפני כפתור המחיקה).
  /// משמש להוספת כפתורים כגון היסטוריה, בלי לגרום לחפיפה עם תוכן הטקסט.
  final Widget? trailingAction;

  /// ההקשר שנשלח לתוסף בלחיצה על כפתורו; ראו [PluginSearchFieldActions].
  final Map<String, dynamic> Function()? pluginInvocationContext;

  const EnhancedSearchField({
    super.key,
    required this.tab,
    required this.onSubmit,
    this.showInlineSearchButton = true,
    this.trailingAction,
    this.pluginInvocationContext,
  });

  @override
  State<EnhancedSearchField> createState() => _EnhancedSearchFieldState();
}

class _EnhancedSearchFieldState extends State<EnhancedSearchField> {
  static const double _kSearchFieldMinWidth = 300;
  static const double _kControlHeight = 48;

  /// מתחת לרוחב הזה הרמז המלא ("הקלד מילות חיפוש · לצמצום: ...") נחתך בין
  /// האייקונים, ולכן ברמז רק "הקלד מילות חיפוש", ודרך הצמצום עוברת לשורת עזר
  /// מתחת לשדה (q12 Q8, טלפון).
  static const double _kFullHintMinWidth = 520;

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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final shortHint = constraints.maxWidth < _kFullHintMinWidth;
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
                          onSubmitted: (_) => widget.onSubmit(),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHigh,
                            hintText: shortHint
                                ? context.settingsText('הקלד מילות חיפוש')
                                : context.settingsText(
                                    'הקלד מילות חיפוש · לצמצום: מצה@רשי/פסחים',
                                  ),
                            helperText: shortHint
                                ? context.settingsText('לצמצום: מצה@רשי/פסחים')
                                : null,
                            labelText: context.settingsText('חיפוש'),
                            prefixIcon: widget.showInlineSearchButton
                                ? IconButton(
                                    onPressed: widget.onSubmit,
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
                                  onSubmitted: (_) => widget.onSubmit(),
                                  invocationContext:
                                      widget.pluginInvocationContext,
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
      },
    );
  }
}
