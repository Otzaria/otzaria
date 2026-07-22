import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_spinbox/flutter_spinbox.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/search/view/tantivy_search_results.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:toggle_switch/toggle_switch.dart';

class SearchModeToggle extends StatelessWidget {
  const SearchModeToggle({super.key, required this.tab});

  final SearchingTab tab;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        int currentIndex;
        switch (state.configuration.searchMode) {
          case SearchMode.advanced:
            currentIndex = 0;
            break;
          case SearchMode.exact:
            currentIndex = 1;
            break;
          case SearchMode.fuzzy:
            currentIndex = 2;
            break;
        }

        return Padding(
          padding: const EdgeInsets.all(8.0),
          child: ToggleSwitch(
            minWidth: 108,
            minHeight: 45,
            inactiveBgColor: Colors.grey,
            inactiveFgColor: Colors.white,
            initialLabelIndex: currentIndex,
            totalSwitches: 3,
            labels: const [
              'חיפוש מתקדם',
              'חיפוש מדוייק',
              'חיפוש מקורב',
            ],
            radiusStyle: true,
            onToggle: (index) {
              SearchMode newMode;
              switch (index) {
                case 0:
                  newMode = SearchMode.advanced;
                  break;
                case 1:
                  newMode = SearchMode.exact;
                  break;
                case 2:
                  newMode = SearchMode.fuzzy;
                  break;
                default:
                  newMode = SearchMode.advanced;
              }
              context.read<SearchBloc>().add(SetSearchMode(newMode));
              // מעבר ידני נשמר לסשן הנוכחי; בהפעלה הבאה חיפוש חדש נפתח
              // שוב בברירת המחדל (חיפוש רגיל).
              SearchDefaults.rememberSessionMode(newMode);
            },
          ),
        );
      },
    );
  }
}

class FuzzyDistance extends StatefulWidget {
  const FuzzyDistance({
    super.key,
    required this.tab,
    this.inputFocusNotifier,
    this.triggerSearch = true,
  });

  final SearchingTab tab;
  final ValueNotifier<bool>? inputFocusNotifier;
  final bool triggerSearch;

  @override
  State<FuzzyDistance> createState() => _FuzzyDistanceState();
}

class _FuzzyDistanceState extends State<FuzzyDistance> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // מאזין לשינויים במרווחים המותאמים אישית
    widget.tab.spacingValuesChanged.addListener(_onSpacingChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.tab.spacingValuesChanged.removeListener(_onSpacingChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onSpacingChanged() {
    setState(() {
      // עדכון התצוגה כשמשתמש משנה מרווחים
    });
  }

  void _onFocusChanged() {
    widget.inputFocusNotifier?.value = _focusNode.hasFocus;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        // טווח קרבה "פסקה"/"כותרת" מייתר את מגבלת המרווח — השדה מושבת
        // ומציג את שם הטווח במקומה. גם התאמה חלקית (לא "כל המילים")
        // מוותרת על סדר ומרחק ולכן מייתרת אותו.
        final scope = state.proximityScope;
        final wordMatchMode = state.wordMatchMode;
        final modeOverridesDistance =
            state.isAdvancedSearchEnabled && wordMatchMode != WordMatchMode.all;
        final scopeOverridesDistance =
            state.isAdvancedSearchEnabled && scope != SearchScope.wordDistance;
        // בדיקה אם יש מרווחים מותאמים אישית
        final hasCustomSpacing = state.isAdvancedSearchEnabled &&
            widget.tab.spacingValues.isNotEmpty &&
            !scopeOverridesDistance &&
            !modeOverridesDistance;
        final isEnabled = !hasCustomSpacing &&
            !scopeOverridesDistance &&
            !modeOverridesDistance;

        // במקורב המספר הוא מרחק עריכה בין המילה שהוקלדה לתוצאה,
        // לא מרווח בין מילים — התווית וההסבר משקפים זאת.
        final isFuzzy = state.configuration.searchMode == SearchMode.fuzzy;
        final String label;
        if (modeOverridesDistance) {
          label = wordMatchMode.label;
        } else if (scopeOverridesDistance) {
          label = scope.label;
        } else if (hasCustomSpacing) {
          label = 'מרווח בין מילים (מושבת)';
        } else if (isFuzzy) {
          label = 'מרחק חיפוש';
        } else {
          label = 'מרווח בין מילים';
        }

        final spinBox = Tooltip(
          message: modeOverridesDistance
              ? wordMatchMode.tooltip
              : scopeOverridesDistance
                  ? scope.tooltip
                  : isFuzzy
                      ? 'קובע עד כמה מותר לתוצאה להיות שונה מהמילים שהוקלדו.'
                      : 'קובע כמה מילים יכולות להופיע בין מילות החיפוש. כאשר מוגדרים מרווחים ידניים בין מילים, השדה הזה מושבת.',
          child: Focus(
            focusNode: _focusNode,
            child: SpinBox(
              enabled: isEnabled,
              decoration: InputDecoration(
                labelText: label,
                labelStyle: TextStyle(
                  color: hasCustomSpacing ||
                          scopeOverridesDistance ||
                          modeOverridesDistance
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : null,
                ),
                border: OutlineInputBorder(
                  borderRadius: AppTokens.borderRadiusAll,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 16.0,
                ),
              ),
              min: 0,
              max: 30,
              value: state.distance.toDouble(),
              onChanged: isEnabled
                  ? (value) => context.read<SearchBloc>().add(
                        widget.triggerSearch
                            ? UpdateDistance(value.toInt())
                            : UpdateDistanceWithoutSearch(value.toInt()),
                      )
                  : null,
            ),
          ),
        );

        // במצב "לפחות X מילים" שדה המרווח (חסר המשמעות) מוחלף בשדה מספר
        // המילים הנדרש.
        final countBox = Tooltip(
          message: 'מספר מילות החיפוש המזערי שחייב להופיע בכל תוצאה.',
          child: Focus(
            focusNode: _focusNode,
            child: SpinBox(
              decoration: InputDecoration(
                labelText: 'מספר מילים',
                border: OutlineInputBorder(
                  borderRadius: AppTokens.borderRadiusAll,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 16.0,
                ),
              ),
              min: 1,
              max: 30,
              value: state.wordMatchCount.toDouble(),
              onChanged: (value) => context.read<SearchBloc>().add(
                    widget.triggerSearch
                        ? UpdateWordMatchMode(wordMatchMode,
                            count: value.toInt())
                        : UpdateWordMatchModeWithoutSearch(wordMatchMode,
                            count: value.toInt()),
                  ),
            ),
          ),
        );

        // בורר הטווח רלוונטי רק לחיפוש המתקדם: במדויק אין קרבה כלל,
        // ובמקורב המרווח משמש כמרחק עריכה.
        if (!state.isAdvancedSearchEnabled) {
          return SizedBox(width: 140, child: spinBox);
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ScopeAndMatchMenu(
              scope: scope,
              mode: wordMatchMode,
              onSelected: (selectedScope, selectedMode) {
                final bloc = context.read<SearchBloc>();
                final config = bloc.state.configuration;
                if (selectedScope == config.proximityScope &&
                    selectedMode == config.wordMatchMode) {
                  return;
                }
                // מעדכנים את שני הערכים בשקט ומריצים חיפוש אחד בסוף, כדי
                // שלא ירוצו שני חיפושים גם כשרק אחד מהם השתנה.
                bloc.add(UpdateProximityScopeWithoutSearch(selectedScope));
                bloc.add(UpdateWordMatchModeWithoutSearch(selectedMode));
                if (widget.triggerSearch) {
                  bloc.add(UpdateSearchQuery(bloc.state.searchQuery));
                }
              },
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 150,
              child: wordMatchMode == WordMatchMode.atLeast ? countBox : spinBox,
            ),
          ],
        );
      },
    );
  }
}

/// תפריט מרוכז לטווח הקרבה ולמצב התאמת המילים: התפריט הראשי הוא טווח
/// הקרבה, ותחת כל טווח תת-תפריט לבחירת מצב ההתאמה.
class _ScopeAndMatchMenu extends StatelessWidget {
  const _ScopeAndMatchMenu({
    required this.scope,
    required this.mode,
    required this.onSelected,
  });

  final SearchScope scope;
  final WordMatchMode mode;
  final void Function(SearchScope scope, WordMatchMode mode) onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDefault =
        scope == SearchScope.wordDistance && mode == WordMatchMode.all;
    final current = (scope, mode);
    return Tooltip(
      message: 'טווח קרבה: ${scope.label} · התאמת מילים: ${mode.label}',
      child: AppDropdownField<(SearchScope, WordMatchMode)>(
        value: current,
        isExpanded: false,
        menuMinWidth: 230,
        // הבחירה מטופלת ע"י תת-התפריטים; פריט ראשי אינו מחזיר ערך.
        onSelected: (_) {},
        entries: [
          for (final scopeOption in SearchScope.values)
            AppMenuEntry(value: (scopeOption, mode), label: scopeOption.label),
        ],
        selectedBuilder: (context, value) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.apps_list_24_regular,
              size: 20,
              color: isDefault ? colorScheme.onSurface : colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${scope.label} · ${mode.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        menuItemsBuilder: (context, metrics) => [
          for (final scopeOption in SearchScope.values)
            buildAppSubmenuPopupMenuItem<(SearchScope, WordMatchMode)>(
              context: context,
              metrics: metrics,
              label: scopeOption.label,
              menuChildren: [
                for (final modeOption in WordMatchMode.values)
                  buildAppPopupMenuItem<(SearchScope, WordMatchMode)>(
                    context,
                    AppMenuEntry(
                      value: (scopeOption, modeOption),
                      label: modeOption.label,
                      labelWidget: Tooltip(
                        message: modeOption.tooltip,
                        child: Text(modeOption.label),
                      ),
                    ),
                    metrics,
                    current,
                  ),
              ],
              onSelected: (selected) => onSelected(selected.$1, selected.$2),
            ),
        ],
      ),
    );
  }
}

class SearchTermsDisplay extends StatefulWidget {
  const SearchTermsDisplay({super.key, required this.tab});

  final SearchingTab tab;

  @override
  State<SearchTermsDisplay> createState() => _SearchTermsDisplayState();
}

class _SearchTermsDisplayState extends State<SearchTermsDisplay> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _attachTabListeners(widget.tab);
  }

  void _attachTabListeners(SearchingTab tab) {
    tab.queryController.addListener(_onTextChanged);
    tab.searchOptionsChanged.addListener(_onSearchOptionsChanged);
    tab.alternativeWordsChanged.addListener(_onAlternativeWordsChanged);
  }

  void _detachTabListeners(SearchingTab tab) {
    tab.queryController.removeListener(_onTextChanged);
    tab.searchOptionsChanged.removeListener(_onSearchOptionsChanged);
    tab.alternativeWordsChanged.removeListener(_onAlternativeWordsChanged);
  }

  @override
  void didUpdateWidget(covariant SearchTermsDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tab, widget.tab)) {
      _detachTabListeners(oldWidget.tab);
      _attachTabListeners(widget.tab);
    }
  }

  void _onSearchOptionsChanged() {
    // עדכון התצוגה כשמשתמש משנה אפשרויות
    setState(() {
      // זה יגרום לעדכון של התצוגה
    });
  }

  void _onAlternativeWordsChanged() {
    // עדכון התצוגה כשמשתמש משנה מילים חילופיות
    setState(() {
      // זה יגרום לעדכון של התצוגה
    });
  }

  double _calculateFormattedTextWidth(String text, BuildContext context) {
    if (text.trim().isEmpty) return 0.0;

    // יצירת TextSpan עם הטקסט המעוצב
    final spans = _buildFormattedTextSpans(text, context);

    // שימוש ב-TextPainter למדידת הרוחב האמיתי
    final textPainter = TextPainter(
      text: TextSpan(children: spans),
      maxLines: 1,
      textDirection: TextDirection.rtl,
    );

    textPainter.layout(maxWidth: double.infinity);
    return textPainter.size.width;
  }

  // פונקציה להמרת מספרים לתת-כתב Unicode
  String _convertToSubscript(String number) {
    const Map<String, String> subscriptMap = {
      '0': '₀',
      '1': '₁',
      '2': '₂',
      '3': '₃',
      '4': '₄',
      '5': '₅',
      '6': '₆',
      '7': '₇',
      '8': '₈',
      '9': '₉',
    };

    return number.split('').map((char) => subscriptMap[char] ?? char).join();
  }

  List<TextSpan> _buildFormattedTextSpans(String text, BuildContext context) {
    if (text.trim().isEmpty) return [const TextSpan(text: '')];

    // פיצול דרך המנוע — המפתחות "{word}_{index}" חייבים להתאים לאלו
    // שבונה advanced_search_controls מ-splitQueryWords (רמב"ם מילה אחת,
    // בית-דין שתיים), אחרת האפשרויות יוצגו ליד המילה הלא-נכונה.
    final words = SearchQueryBuilder.splitQueryWords(text);
    final List<TextSpan> spans = [];
    final activeParameters = SearchQueryBuilder.normalizeParametersForMode(
      widget.tab.searchBloc.state.configuration.searchMode,
      customSpacing: widget.tab.spacingValues,
      alternativeWords: widget.tab.alternativeWords,
      searchOptions: widget.tab.effectiveSearchOptions(query: text),
    );

    // מיפוי אפשרויות לקיצורים
    const Map<String, String> optionAbbreviations = {
      'קידומות': 'ק',
      'סיומות': 'ס',
      'קידומות דקדוקיות': 'קד',
      'סיומות דקדוקיות': 'סד',
      'כתיב מלא/חסר': 'מח',
      'חלק ממילה': 'ש',
      'קידומות ארמיות': 'קא',
      'סיומות ארמיות': 'סא',
      'התעלם מגרשיים': 'גר',
      'תרגום ארמי': 'תא',
      'ראשי תיבות': 'רת',
    };

    // אפשרויות שמופיעות אחרי המילה (סיומות)
    const Set<String> suffixOptions = {
      'סיומות',
      'סיומות דקדוקיות',
      'סיומות ארמיות'
    };

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final wordKey = '${word}_$i';

      // בדיקה אם יש אפשרויות למילה הזו
      final wordOptions = activeParameters.searchOptions[wordKey];
      final selectedOptions = wordOptions?.entries
              .where((entry) => entry.value)
              .map((entry) => entry.key)
              .toList() ??
          [];

      // בדיקה אם יש מילים חילופיות למילה הזו
      final alternativeWords = activeParameters.alternativeWords[i] ?? [];

      // הפרדה בין קידומות לסיומות
      final prefixes = selectedOptions
          .where((opt) => !suffixOptions.contains(opt))
          .map((opt) => optionAbbreviations[opt] ?? opt)
          .toList();

      final suffixes = selectedOptions
          .where((opt) => suffixOptions.contains(opt))
          .map((opt) => optionAbbreviations[opt] ?? opt)
          .toList();

      // הוספת קידומות לפני המילה
      if (prefixes.isNotEmpty) {
        spans.add(
          TextSpan(
            text: '(${prefixes.join(',')})',
            style: TextStyle(
              fontSize: 10, // גופן קטן יותר לקיצורים
              fontWeight: FontWeight.normal,
              color: Theme.of(context).primaryColor,
            ),
          ),
        );
        spans.add(const TextSpan(text: ' '));
      }

      // הוספת המילה המודגשת
      spans.add(
        TextSpan(
          text: word,
          style: TextStyle(
            fontSize: 16, // גופן גדול יותר למילים
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );

      // הוספת מילים חילופיות אם יש
      if (alternativeWords.isNotEmpty) {
        for (final altWord in alternativeWords) {
          // הוספת "או" בצבע הסיומות
          spans.add(const TextSpan(text: ' '));
          spans.add(
            TextSpan(
              text: 'או',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
                color: Theme.of(context).primaryColor,
              ),
            ),
          );
          spans.add(const TextSpan(text: ' '));

          // הוספת המילה החילופית המודגשת
          spans.add(
            TextSpan(
              text: altWord,
              style: TextStyle(
                fontSize: 16, // גופן גדול יותר למילים
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          );
        }
      }

      // הוספת סיומות אחרי המילה (והמילים החילופיות)
      if (suffixes.isNotEmpty) {
        spans.add(const TextSpan(text: ' '));
        spans.add(
          TextSpan(
            text: '(${suffixes.join(',')})',
            style: TextStyle(
              fontSize: 10, // גופן קטן יותר לקיצורים
              fontWeight: FontWeight.normal,
              color: Theme.of(context).primaryColor,
            ),
          ),
        );
      }

      // הוספת + בין המילים (לא אחרי המילה האחרונה)
      if (i < words.length - 1) {
        // בדיקה אם יש מרווח מוגדר בין המילים
        final spacingKey = '$i-${i + 1}';
        final spacingValue = activeParameters.customSpacing[spacingKey];

        if (spacingValue != null && spacingValue.isNotEmpty) {
          // הצגת + עם המרווח מתחת
          spans.add(const TextSpan(text: ' '));

          // הוספת + עם המספר כתת-כתב
          spans.add(
            TextSpan(
              text: '+',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          );
          // הוספת המספר כתת-כתב עם Unicode subscript characters
          final subscriptValue = _convertToSubscript(spacingValue);
          spans.add(
            TextSpan(
              text: subscriptValue,
              style: TextStyle(
                fontSize: 14, // גופן מעט יותר גדול למספר המרווח
                fontWeight: FontWeight.normal,
                color: Theme.of(context).primaryColor,
              ),
            ),
          );

          spans.add(const TextSpan(text: ' '));
        } else {
          // + רגיל ללא מרווח
          spans.add(
            TextSpan(
              text: ' + ',
              style: TextStyle(
                fontSize: 16, // גופן גדול יותר ל-+
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          );
        }
      }
    }

    return spans;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _detachTabListeners(widget.tab);
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {
      // עדכון התצוגה כשהטקסט משתנה
    });
  }

  Widget _buildFormattedText(String text, BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();

    final spans = _buildFormattedTextSpans(text, context);
    return RichText(
      text: TextSpan(children: spans),
      textAlign: TextAlign.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        // נציג את הטקסט מה-state של החיפוש (לא מה-controller שמשתנה)
        final displayText = state.searchQuery;

        if (displayText.isEmpty) {
          return const SizedBox.shrink();
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final double formattedTextWidth = _calculateFormattedTextWidth(
              displayText,
              context,
            );

            // תצוגה פשוטה ללא מסגרת - ללא width קבוע כדי לאפשר מרכוז
            return formattedTextWidth <= (constraints.maxWidth - 20)
                ? _buildFormattedText(displayText, context)
                : SizedBox(
                    width: double.infinity,
                    child: LayoutBuilder(
                      builder: (context, _) {
                        // וידוא שה-ScrollController מחובר לפני הצגת Scrollbar
                        return Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          trackVisibility: true,
                          thickness: 3.0,
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            scrollDirection: Axis.horizontal,
                            child: _buildFormattedText(displayText, context),
                          ),
                        );
                      },
                    ),
                  );
          },
        );
      },
    );
  }
}

class OrderOfResults extends StatelessWidget {
  const OrderOfResults({super.key, required this.widget, this.compact = false});

  final TantivySearchResults widget;

  /// במצב קומפקטי מוצג כפתור "לפי" שפותח תפריט נפתח במקום dropdown רגיל.
  final bool compact;

  static const _entries = [
    AppMenuEntry(value: ResultsOrder.relevance, label: 'לפי רלוונטיות'),
    AppMenuEntry(value: ResultsOrder.catalogue, label: 'לפי סדר קטלוגי'),
    AppMenuEntry(value: ResultsOrder.generation, label: 'לפי סדר הדורות'),
  ];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        if (compact) {
          return AppPopupMenuButton<ResultsOrder>(
            tooltip: 'סדר תוצאות',
            initialValue: state.sortBy,
            entries: _entries,
            onSelected: (value) {
              context.read<SearchBloc>().add(UpdateSortOrder(value));
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
                borderRadius: AppTokens.borderRadiusAll,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'לפי',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    FluentIcons.chevron_down_12_regular,
                    size: 12,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ],
              ),
            ),
          );
        }
        return SizedBox(
          width: 183,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: AppDropdownField<ResultsOrder>(
              value: state.sortBy,
              decoration: const InputDecoration(
                labelText: 'מיון',
                border: OutlineInputBorder(),
              ),
              entries: _entries,
              onSelected: (value) {
                if (value != null) {
                  context.read<SearchBloc>().add(UpdateSortOrder(value));
                }
              },
            ),
          ),
        );
      },
    );
  }
}

/// בורר מצב איחוד תוצאות — מקביל ויזואלית ל-[OrderOfResults]:
/// dropdown במסך רחב וכפתור תפריט קומפקטי במסך צר.
class GroupingOfResults extends StatelessWidget {
  const GroupingOfResults({super.key, this.compact = false});

  /// במצב קומפקטי מוצג כפתור "איחוד" שפותח תפריט נפתח במקום dropdown רגיל.
  final bool compact;

  static final _entries = [
    for (final mode in ResultGroupingMode.values)
      AppMenuEntry(
        value: mode,
        label: mode.label,
        labelWidget: Tooltip(
          message: mode.tooltip,
          child: Text(mode.label),
        ),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchBloc, SearchState>(
      builder: (context, state) {
        if (compact) {
          return AppPopupMenuButton<ResultGroupingMode>(
            tooltip: 'איחוד תוצאות',
            initialValue: state.resultGrouping,
            entries: _entries,
            onSelected: (value) {
              context.read<SearchBloc>().add(UpdateResultGrouping(value));
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
                borderRadius: AppTokens.borderRadiusAll,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'איחוד',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    FluentIcons.chevron_down_12_regular,
                    size: 12,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ],
              ),
            ),
          );
        }
        return SizedBox(
          width: 183,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Tooltip(
              message: state.resultGrouping.tooltip,
              child: AppDropdownField<ResultGroupingMode>(
                value: state.resultGrouping,
                decoration: const InputDecoration(
                  labelText: 'איחוד תוצאות',
                  border: OutlineInputBorder(),
                ),
                entries: _entries,
                onSelected: (value) {
                  if (value != null) {
                    context.read<SearchBloc>().add(UpdateResultGrouping(value));
                  }
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
