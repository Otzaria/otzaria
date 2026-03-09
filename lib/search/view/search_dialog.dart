import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/indexing/bloc/indexing_bloc.dart';
import 'package:otzaria/indexing/bloc/indexing_state.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/search/view/enhanced_search_field.dart';
import 'package:otzaria/search/view/advanced_search_controls.dart';
import 'package:otzaria/search/view/full_text_settings_widgets.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/widgets/indexing_warning.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/nikud_search_button.dart';

/// דיאלוג חיפוש מתקדם - מכיל את כל פקדי החיפוש וההגדרות
/// כשמבצעים חיפוש, הדיאלוג נסגר ונפתחת לשונית תוצאות
class SearchDialog extends StatefulWidget {
  final SearchingTab? existingTab;
  final Function(
    String query,
    Map<String, Map<String, bool>> searchOptions,
    Map<int, List<String>> alternativeWords,
    Map<String, String> spacingValues,
    SearchMode searchMode,
  )? onSearch;
  final String? bookTitle;

  const SearchDialog(
      {super.key, this.existingTab, this.onSearch, this.bookTitle});

  @override
  State<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<SearchDialog> {
  late SearchingTab _searchTab;
  bool _showIndexWarning = false;
  bool _showHistoryDropdown = false;
  final ValueNotifier<bool> _advancedControlsHasFocus = ValueNotifier(false);
  late final VoidCallback _queryListener;
  bool _searchWithNikud = false;

  @override
  void initState() {
    super.initState();

    // טעינת ההקלדה האחרונה מההגדרות (לא החיפוש בפועל)
    final lastTyping =
        Settings.getValue<String>('key-last-search-typing') ?? '';
    final lastMode =
        Settings.getValue<String>('key-last-search-mode') ?? 'advanced';

    // יצירת טאב עם ההקלדה האחרונה
    if (widget.existingTab != null) {
      _searchTab = widget.existingTab!;
    } else {
      _searchTab = SearchingTab("חיפוש", lastTyping);
    }

    // הגדרת מצב החיפוש האחרון
    final searchMode = lastMode == 'advanced'
        ? SearchMode.advanced
        : lastMode == 'fuzzy'
            ? SearchMode.fuzzy
            : SearchMode.exact;
    _searchTab.searchBloc.add(SetSearchMode(searchMode));

    // בדיקה אם האינדקס בתהליך בנייה
    final indexingState = context.read<IndexingBloc>().state;
    _showIndexWarning = indexingState is IndexingInProgress;

    // מאזין לשינויים בתיבת החיפוש כדי לעדכן את האפשרויות ולשמור את ההקלדה
    _queryListener = () {
      if (!mounted) return;
      // שמירת ההקלדה הנוכחית
      Settings.setValue<String>(
        'key-last-search-typing',
        _searchTab.queryController.text,
      );
    };
    _searchTab.queryController.addListener(_queryListener);

    // בקשת פוקוס לתיבת החיפוש
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchTab.searchFieldFocusNode.requestFocus();
      }
    });
  }

  Widget _buildIndexWarning() {
    if (!_showIndexWarning) return const SizedBox.shrink();

    return IndexingWarning(
      onDismiss: () {
        setState(() {
          _showIndexWarning = false;
        });
      },
    );
  }

  // בניית מגירת ההיסטוריה - מציג רק חיפושים מההיסטוריה הכללית
  Widget _buildHistoryDropdown() {
    return BlocBuilder<HistoryBloc, HistoryState>(
      builder: (context, state) {
        // סינון רק חיפושים
        final searchHistory =
            state.history.where((item) => item.isSearch).toList();

        if (searchHistory.isEmpty) return const SizedBox.shrink();

        // הגבלה ל-5 אחרונים
        final recentSearches = searchHistory.take(5).toList();

        return Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ScrollConfiguration(
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: recentSearches.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                thickness: 1,
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.2),
              ),
              itemBuilder: (context, index) {
                final bookmark = recentSearches[index];
                final query = bookmark.book.title; // הטקסט הפשוט של החיפוש
                final displayText =
                    bookmark.ref; // הטקסט המעוצב (עם קידומות וסיומות)

                return ListTile(
                  dense: true,
                  leading: const Icon(FluentIcons.search_24_regular, size: 18),
                  title: Text(
                    displayText,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 14),
                  ),
                  onTap: () {
                    // שחזור הטקסט הפשוט (ללא קידומות וסיומות)
                    _searchTab.queryController.text = query;

                    // שחזור האפשרויות הנוספות
                    if (bookmark.searchOptions != null) {
                      _searchTab.searchOptions.clear();
                      _searchTab.searchOptions.addAll(bookmark.searchOptions!);
                    }
                    if (bookmark.alternativeWords != null) {
                      _searchTab.alternativeWords.clear();
                      _searchTab.alternativeWords
                          .addAll(bookmark.alternativeWords!);
                    }
                    if (bookmark.spacingValues != null) {
                      _searchTab.spacingValues.clear();
                      _searchTab.spacingValues.addAll(bookmark.spacingValues!);
                    }

                    // עדכון התצוגה
                    setState(() {
                      _showHistoryDropdown = false;
                    });

                    _searchTab.searchFieldFocusNode.requestFocus();
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _searchTab.queryController.removeListener(_queryListener);
    _advancedControlsHasFocus.dispose();
    super.dispose();
  }

  void _performSearch() {
    String query = _searchTab.queryController.text.trim();

    if (query.isEmpty) {
      UiSnack.show('נא להזין טקסט לחיפוש');
      return;
    }

    // הסרת ניקוד כברירת מחדל, אלא אם המשתמש לחץ על כפתור "עם ניקוד"
    if (!_searchWithNikud && utils.hasNikud(query)) {
      query = utils.removeVolwels(query);
    }

    // שמירת מצב החיפוש האחרון
    final currentMode = _searchTab.searchBloc.state.configuration.searchMode;
    final modeString = currentMode == SearchMode.advanced
        ? 'advanced'
        : currentMode == SearchMode.fuzzy
            ? 'fuzzy'
            : 'exact';
    Settings.setValue<String>('key-last-search-mode', modeString);

    if (widget.onSearch != null) {
      widget.onSearch!(
        query,
        _searchTab.searchOptions,
        _searchTab.alternativeWords,
        _searchTab.spacingValues,
        currentMode,
      );
      Navigator.of(context).pop();
      return;
    }

    // יצירת טאב חדש לגמרי - ללא קשר לטאב קודם
    // שם הלשונית: "חיפוש: [מילות החיפוש]"
    final newSearchTab = SearchingTab("חיפוש: $query", query);

    // העתקת כל ההגדרות מהטאב הנוכחי לטאב החדש
    newSearchTab.searchOptions.addAll(_searchTab.searchOptions);
    newSearchTab.alternativeWords.addAll(_searchTab.alternativeWords);
    newSearchTab.spacingValues.addAll(_searchTab.spacingValues);

    // הוספה להיסטוריה
    context.read<HistoryBloc>().add(AddHistory(newSearchTab));

    // ביצוע החיפוש בטאב החדש
    newSearchTab.searchBloc.add(
      UpdateSearchQuery(
        query,
        customSpacing: newSearchTab.spacingValues,
        alternativeWords: newSearchTab.alternativeWords,
        searchOptions: newSearchTab.searchOptions,
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

  Widget _buildNavButton(
    BuildContext context,
    String title,
    IconData icon,
    SearchMode mode,
    bool isSelected,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          context.read<SearchBloc>().add(SetSearchMode(mode));
          _searchTab.searchFieldFocusNode.requestFocus();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 72,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.secondaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 24,
                color: isSelected
                    ? Theme.of(context).colorScheme.onSecondaryContainer
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected
                      ? Theme.of(context).colorScheme.onSecondaryContainer
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = (screenSize.width * 0.7).clamp(500.0, 900.0);
    final dialogHeight = (screenSize.height * 0.65).clamp(450.0, 700.0);

    return BlocProvider.value(
      value: _searchTab.searchBloc,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
          child: Container(
            width: dialogWidth,
            height: dialogHeight,
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // כותרת
                Row(
                  children: [
                    const Icon(FluentIcons.search_24_filled, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      widget.bookTitle != null
                          ? 'חיפוש ב${widget.bookTitle}'
                          : 'חיפוש',
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(FluentIcons.dismiss_24_regular),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'סגור',
                    ),
                  ],
                ),
                const Divider(height: 24),

                // אזהרת אינדקס
                _buildIndexWarning(),

                // תוכן הדיאלוג - Row עם ניווט מימין ותוכן משמאל
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Navigation Bar אנכי מימין
                      BlocBuilder<SearchBloc, SearchState>(
                        builder: (context, state) {
                          return Container(
                            width: 80,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildNavButton(
                                  context,
                                  'מדויק',
                                  FluentIcons.text_quote_24_regular,
                                  SearchMode.exact,
                                  state.configuration.searchMode ==
                                      SearchMode.exact,
                                ),
                                const SizedBox(height: 4),
                                _buildNavButton(
                                  context,
                                  'מתקדם',
                                  FluentIcons.search_info_24_regular,
                                  SearchMode.advanced,
                                  state.configuration.searchMode ==
                                      SearchMode.advanced,
                                ),
                                const SizedBox(height: 4),
                                _buildNavButton(
                                  context,
                                  'מקורב',
                                  FluentIcons
                                      .arrow_bidirectional_left_right_24_regular,
                                  SearchMode.fuzzy,
                                  state.configuration.searchMode ==
                                      SearchMode.fuzzy,
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      const SizedBox(width: 16),

                      // תוכן ראשי
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // שדה החיפוש + מרווח בין מילים + מגירת היסטוריה
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // שורה עם תיבת החיפוש ומרווח בין מילים - באותו גובה
                                  IntrinsicHeight(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        // שדה החיפוש עם כפתור היסטוריה
                                        Expanded(
                                          child: Stack(
                                            children: [
                                              // תיבת החיפוש
                                              BlocProvider.value(
                                                value: _searchTab.searchBloc,
                                                child: EnhancedSearchField(
                                                  key: enhancedSearchFieldKey,
                                                  widget: _SearchDialogWrapper(
                                                    tab: _searchTab,
                                                  ),
                                                ),
                                              ),
                                              // כפתור חיפוש - מצד ימין
                                              Positioned(
                                                right: 10,
                                                top: 8,
                                                bottom: 8,
                                                child: Center(
                                                  child: IconButton(
                                                    icon: const Icon(
                                                      FluentIcons
                                                          .search_24_filled,
                                                      size: 20,
                                                    ),
                                                    tooltip: 'חפש',
                                                    onPressed: _performSearch,
                                                    style: IconButton.styleFrom(
                                                      backgroundColor:
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .primaryContainer,
                                                      foregroundColor:
                                                          Theme.of(context)
                                                              .colorScheme
                                                              .primary,
                                                      padding:
                                                          const EdgeInsets.all(
                                                              6),
                                                      minimumSize:
                                                          const Size(32, 32),
                                                      tapTargetSize:
                                                          MaterialTapTargetSize
                                                              .shrinkWrap,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              // כפתור "עם ניקוד" - מופיע רק כאשר יש ניקוד
                                              if (utils.hasNikud(_searchTab
                                                  .queryController.text))
                                                Positioned(
                                                  left: 96,
                                                  top: 8,
                                                  bottom: 8,
                                                  child: Center(
                                                    child: NikudSearchButton(
                                                      isActive:
                                                          _searchWithNikud,
                                                      onPressed: () {
                                                        setState(() {
                                                          _searchWithNikud =
                                                              !_searchWithNikud;
                                                        });
                                                      },
                                                    ),
                                                  ),
                                                ),
                                              // כפתור היסטוריה - ליד כפתור ה-X
                                              Positioned(
                                                left: 48,
                                                top: 0,
                                                bottom: 0,
                                                child: Center(
                                                  child: IconButton(
                                                    icon: Icon(
                                                      _showHistoryDropdown
                                                          ? FluentIcons
                                                              .chevron_up_24_regular
                                                          : FluentIcons
                                                              .history_24_regular,
                                                      size: 24,
                                                    ),
                                                    tooltip:
                                                        'היסטוריית חיפושים',
                                                    padding: EdgeInsets.zero,
                                                    constraints:
                                                        const BoxConstraints(),
                                                    onPressed: () {
                                                      setState(() {
                                                        _showHistoryDropdown =
                                                            !_showHistoryDropdown;
                                                      });
                                                    },
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        // מרווח בין מילים - באותו גובה
                                        BlocBuilder<SearchBloc, SearchState>(
                                          builder: (context, state) {
                                            if (state.fuzzy) {
                                              return const SizedBox.shrink();
                                            }
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                right: 16.0,
                                              ),
                                              child: Center(
                                                child: FuzzyDistance(
                                                  tab: _searchTab,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),

                                  // מגירת היסטוריה - מתחת לשורה
                                  if (_showHistoryDropdown)
                                    _buildHistoryDropdown(),
                                ],
                              ),

                              const SizedBox(height: 16),

                              // אפשרויות חיפוש עם הטיפ
                              BlocBuilder<SearchBloc, SearchState>(
                                builder: (context, state) {
                                  if (!state.isAdvancedSearchEnabled) {
                                    return const SizedBox.shrink();
                                  }

                                  return AdvancedSearchControls(
                                    tab: _searchTab,
                                    compactMode: true,
                                    onEmptySubmit: _performSearch,
                                    inputFocusNotifier:
                                        _advancedControlsHasFocus,
                                  );
                                },
                              ),
                            ],
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
