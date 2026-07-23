import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/search/search_query_builder.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/widgets/dialogs/reusable_items_dialog.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';
import 'package:otzaria/widgets/lists/items_list_view.dart';

/// משחזר אפשרויות חיפוש שההיסטוריה שומרת תמיד פר-מילה. אפשרויות אחידות
/// מוחזרות למצב הגלובלי — אחרת הצ'יפים בדיאלוג העריכה מוצגים כבויים למרות
/// שהחיפוש עצמו רץ איתן.
void _restoreSearchOptions({
  required Map<String, Map<String, bool>>? saved,
  required Map<String, Map<String, bool>> perWord,
  required Map<String, bool> global,
  required ValueNotifier<bool> useGlobal,
}) {
  perWord.clear();
  global.clear();
  final savedOptions = saved ?? const <String, Map<String, bool>>{};
  final uniform = SearchQueryBuilder.globalOptionsFromPerWord(savedOptions);
  if (uniform != null) {
    global.addAll(uniform);
    useGlobal.value = true;
  } else {
    perWord.addAll(savedOptions);
    useGlobal.value = false;
  }
}

/// חיווי הגדרות החיפוש הכלליות (מ-[Bookmark.searchConfiguration]) לתצוגה
/// בכותרת המשנה של פריט היסטוריה. null כשאין הגדרות לא-ברירתיות או בפריט ישן.
String? _searchSettingsLabel(Map<String, dynamic>? config) {
  if (config == null) return null;
  final label = formatGeneralSearchSettings(
    SearchConfiguration.fromMap(config),
  );
  return label.isEmpty ? null : label;
}

class HistoryDialog extends StatelessWidget {
  const HistoryDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppCustomContentDialog(
      title: 'היסטוריה',
      scrollable: false,
      child: HistoryView(),
    );
  }
}

class HistoryView extends StatefulWidget {
  const HistoryView({super.key});

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  String? _selectedWorkspace;
  final FocusNode _searchFocusNode = FocusNode();

  /// קאש למפתחות הקיבוץ — נמנע מחישוב run-length encoding בכל קריאה ל-build
  /// כשרשימת ההיסטוריה לא משתנה.
  List<dynamic>? _cachedHistoryForRunKeys;
  Map<dynamic, String>? _cachedRunKeys;

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  Map<dynamic, String> _getRunKeys(List<dynamic> history) {
    if (identical(_cachedHistoryForRunKeys, history)) return _cachedRunKeys!;
    final runKeys = _computeRunKeys(history);
    _cachedHistoryForRunKeys = history;
    _cachedRunKeys = runKeys;
    return runKeys;
  }

  List<String> _workspaceNames(List<dynamic> history) {
    return history
        .map((item) => item.workspaceName)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
  }

  String? _effectiveSelectedWorkspace(List<String> workspaceNames) {
    final selectedWorkspace = _selectedWorkspace;
    if (selectedWorkspace == null) {
      return null;
    }
    if (workspaceNames.contains(selectedWorkspace)) {
      return selectedWorkspace;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedWorkspace == null) {
        return;
      }
      setState(() {
        _selectedWorkspace = null;
      });
    });
    return null;
  }

  OpenedTab _buildTabForHistoryItem(Bookmark bookmark) {
    if (bookmark.targetKind == BookmarkTargetKind.commentators) {
      if (bookmark.book is PdfBook) {
        final sourceTab = PdfBookTab(
          book: bookmark.book as PdfBook,
          pageNumber: bookmark.index,
          openLeftPane: shouldAutoOpenReadingLeftPane(),
        )..activeCommentators = bookmark.commentatorsToShow.toSet();
        return PdfCommentatorsTab(sourceTab: sourceTab);
      }

      final sourceTab =
          OpenedTab.fromBook(
                bookmark.book,
                bookmark.index,
                commentators: bookmark.commentatorsToShow,
                openLeftPane: shouldAutoOpenReadingLeftPane(),
              )
              as TextBookTab;
      return CommentatorsTab(sourceTab: sourceTab);
    }

    return OpenedTab.fromBook(
      bookmark.book,
      bookmark.index,
      commentators: bookmark.commentatorsToShow,
      openLeftPane: shouldAutoOpenReadingLeftPane(),
    );
  }

  void _openBook(
    BuildContext context,
    Bookmark bookmark, {
    String? targetTitle,
  }) {
    final tab = _buildTabForHistoryItem(bookmark);

    context.read<TabsBloc>().add(
      OpenOrFocusTab(tab, targetTitle: targetTitle),
    );
    context.read<NavigationBloc>().add(const NavigateToScreen(Screen.reading));
    // Close the dialog if this view is displayed inside one
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Widget? _getLeadingIcon(Book book, bool isSearch) {
    if (isSearch) {
      return const Icon(FluentIcons.search_24_regular);
    }
    if (book is PdfBook) {
      if (book.path.toLowerCase().endsWith('.docx')) {
        return const Icon(FluentIcons.document_text_24_regular);
      }
      return const Icon(FluentIcons.document_pdf_24_regular);
    }
    if (book is TextBook) {
      return const Icon(FluentIcons.document_text_24_regular);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HistoryBloc, HistoryState>(
      builder: (context, state) {
        if (state is HistoryLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state is HistoryError) {
          return Center(child: Text('Error: ${state.message}'));
        }

        final workspaceNames = _workspaceNames(state.history);
        final effectiveSelectedWorkspace = _effectiveSelectedWorkspace(
          workspaceNames,
        );
        final runKeys = _getRunKeys(state.history);

        return Column(
          children: [
            if (workspaceNames.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 4.0,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Wrap(
                    spacing: 6,
                    children: workspaceNames.map((name) {
                      final selected = effectiveSelectedWorkspace == name;
                      final cs = Theme.of(context).colorScheme;
                      return FilterChip(
                        label: Text(
                          name,
                          style: TextStyle(
                            fontSize: 12,
                            color: selected
                                ? cs.onPrimary
                                : cs.onSurfaceVariant,
                          ),
                        ),
                        selected: selected,
                        onSelected: (_) {
                          setState(() {
                            _selectedWorkspace = selected ? null : name;
                          });
                          _searchFocusNode.requestFocus();
                        },
                        selectedColor: cs.primary,
                        backgroundColor: cs.surfaceContainerHighest,
                        checkmarkColor: cs.onPrimary,
                        side: BorderSide.none,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 0,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            Expanded(
              child: ItemsListView(
                searchFocusNode: _searchFocusNode,
                items: state.history,
                additionalFilter: effectiveSelectedWorkspace == null
                    ? null
                    : (item) =>
                          item.workspaceName == effectiveSelectedWorkspace,
                groupKeyBuilder: (item) => runKeys[item] ?? '',
                groupTitleBuilder: (item) => item.workspaceName as String?,
                searchKeyBuilder: (item) {
                  final parts = [item.ref as String];
                  final ws = item.workspaceName as String?;
                  if (ws != null) parts.add(ws);
                  return parts.join(' ');
                },
                onItemTap: (ctx, item, originalIndex) {
                  if (item.isSearch) {
                    final tabsBloc = ctx.read<TabsBloc>();
                    final searchMode = item.searchMode ?? SearchMode.advanced;
                    final scopeFacets =
                        (item.searchScopeFacets != null &&
                            item.searchScopeFacets!.isNotEmpty)
                        ? List<String>.from(item.searchScopeFacets!)
                        : const ['/'];
                    // ה-configuration המלא משוחזר מהמפה השמורה; פריטים ישנים
                    // (ללא מפה) נופלים לשדות הבודדים. ה-facets תמיד מגיעים
                    // מלוגיקת ה-scope כאן, לא מהמפה.
                    final savedConfig = item.searchConfiguration;
                    final baseConfig = savedConfig != null
                        ? SearchConfiguration.fromMap(savedConfig)
                        : SearchConfiguration(
                            searchMode: searchMode,
                            distance:
                                item.distance ??
                                (searchMode == SearchMode.fuzzy ? 2 : 0),
                            proximityScope:
                                item.proximityScope ?? SearchScope.wordDistance,
                          );
                    // ה-configuration מוזרקת בבנייה ולא דרך events אחרי AddTab,
                    // אחרת snapshot השמירה מצלם advanced והמצב אובד בהפעלה הבאה.
                    final searchTab = SearchingTab(
                      'חיפוש',
                      null,
                      initialConfiguration: baseConfig.copyWith(
                        currentFacets: scopeFacets,
                        searchScopeFacets: scopeFacets,
                      ),
                    );

                    // Restore search query and options
                    searchTab.queryController.text = item.book.title;
                    searchTab.negativeQueryController.text =
                        item.negativeSearchText ?? '';
                    _restoreSearchOptions(
                      saved: item.searchOptions,
                      perWord: searchTab.searchOptions,
                      global: searchTab.globalSearchOptions,
                      useGlobal: searchTab.useGlobalSearchOptions,
                    );
                    searchTab.alternativeWords.clear();
                    searchTab.alternativeWords.addAll(
                      item.alternativeWords ?? {},
                    );
                    searchTab.spacingValues.clear();
                    searchTab.spacingValues.addAll(item.spacingValues ?? {});
                    _restoreSearchOptions(
                      saved: item.negativeSearchOptions,
                      perWord: searchTab.negativeSearchOptions,
                      global: searchTab.negativeGlobalSearchOptions,
                      useGlobal: searchTab.useGlobalNegativeSearchOptions,
                    );
                    searchTab.negativeAlternativeWords.clear();
                    searchTab.negativeAlternativeWords.addAll(
                      item.negativeAlternativeWords ?? {},
                    );
                    searchTab.negativeSpacingValues.clear();
                    searchTab.negativeSpacingValues.addAll(
                      item.negativeSpacingValues ?? {},
                    );
                    // פריט שנשמר תחת חוקי-פיצול ישנים של המנוע ימופה
                    // למילים הלא-נכונות — עדיף לנקות מאשר לזלוג.
                    searchTab.dropStalePerWordStateIfNeeded();

                    searchTab.updateTitleFromAppliedQuery(
                      searchTab.queryController.text,
                    );
                    // AddTab רק אחרי שכל מצב הטאב מולא — saveTabs מצלם אותו כאן
                    tabsBloc.add(AddTab(searchTab));
                    searchTab.searchBloc.add(
                      UpdateSearchQuery(
                        searchTab.queryController.text,
                        negativeQuery: searchTab.negativeQueryController.text,
                        customSpacing: searchTab.spacingValues,
                        alternativeWords: searchTab.alternativeWords,
                        // האפקטיביות ולא הפר-מיליות: במצב גלובלי משוחזר הן
                        // מורחבות מהמפה הגלובלית לכל מילה.
                        searchOptions: searchTab.effectiveSearchOptions(
                          query: searchTab.queryController.text,
                        ),
                        negativeCustomSpacing: searchTab.negativeSpacingValues,
                        negativeAlternativeWords:
                            searchTab.negativeAlternativeWords,
                        negativeSearchOptions: searchTab
                            .effectiveNegativeSearchOptions(
                              query: searchTab.negativeQueryController.text,
                            ),
                      ),
                    );

                    // Navigate to search screen
                    ctx.read<NavigationBloc>().add(
                      const NavigateToScreen(Screen.search),
                    );
                    if (Navigator.of(ctx).canPop()) {
                      Navigator.of(ctx).pop();
                    }
                    return;
                  }
                  _openBook(
                    ctx,
                    item,
                    targetTitle: item.ref,
                  );
                },
                onDelete: (ctx, originalIndex) {
                  ctx.read<HistoryBloc>().add(RemoveHistory(originalIndex));
                  UiSnack.show(NotesMessages.historyEntryDeleted);
                },
                onClearAll: (ctx) {
                  ctx.read<HistoryBloc>().add(ClearHistory());
                  UiSnack.show(NotesMessages.allHistoryDeleted);
                },
                hintText: 'חפש בהיסטוריה...',
                emptyText: 'אין היסטוריה',
                notFoundText: 'לא נמצאו תוצאות',
                clearAllText: 'מחק את כל ההיסטוריה',
                leadingIconBuilder: (item) =>
                    _getLeadingIcon(item.book, item.isSearch),
                // פריט חיפוש מציג ככותרת את השאילתה המפורמטת (אפשרויות
                // ומרווחים); ההגדרות הכלליות והקטגוריות יורדות לכותרת המשנה
                // כדי שלא ייראו כחלק מהשאילתה. פריט קריאה מציג את שם הספר.
                titleBuilder: (item) => (item.isSearch as bool)
                    ? item.ref as String
                    : item.book.title as String,
                subtitleBuilder: (item) {
                  if (item.isSearch as bool) {
                    final segments = <String>[];
                    final settings = _searchSettingsLabel(
                      item.searchConfiguration as Map<String, dynamic>?,
                    );
                    if (settings != null) segments.add('הגדרות: $settings');
                    final facets = item.searchScopeFacets as List<String>?;
                    if (facets != null && facets.isNotEmpty) {
                      final allNames = _facetDisplayNames(facets);
                      final displayed = allNames.length > 2
                          ? '${allNames.take(2).join(', ')}...'
                          : allNames.join(', ');
                      segments.add('בקטגוריות: $displayed');
                    }
                    return segments.isEmpty ? null : segments.join('  •  ');
                  }
                  return ItemsListView.locationSubtitle(item);
                },
                subtitleTooltipBuilder: (item) {
                  if (!(item.isSearch as bool)) return null;
                  final facets = item.searchScopeFacets as List<String>?;
                  if (facets == null || facets.length <= 2) return null;
                  final segments = <String>[];
                  final settings = _searchSettingsLabel(
                    item.searchConfiguration as Map<String, dynamic>?,
                  );
                  if (settings != null) segments.add('הגדרות: $settings');
                  segments.add(
                    'בקטגוריות: ${_facetDisplayNames(facets).join(', ')}',
                  );
                  return segments.join('  •  ');
                },
              ),
            ),
          ],
        );
      },
    );
  }

  static List<String> _facetDisplayNames(List<String> facets) {
    return facets.map((facet) {
      final segments = facet.split('/').where((segment) => segment.isNotEmpty);
      return segments.isNotEmpty ? segments.last : facet;
    }).toList();
  }

  /// קיבוץ לפי ריצות רציפות של אותו שולחן עבודה (run-length encoding).
  /// שולחן A שמופיע פעמיים לא-רציפות יקבל שתי קבוצות נפרדות.
  static Map<dynamic, String> _computeRunKeys(List<dynamic> history) {
    final runKeys = Map<dynamic, String>.identity();
    bool isFirst = true;
    String? lastWorkspace;
    int runIndex = 0;
    for (final item in history) {
      final ws = item.workspaceName as String?;
      if (isFirst || ws != lastWorkspace) {
        runIndex++;
        lastWorkspace = ws;
        isFirst = false;
      }
      runKeys[item] = '${ws ?? ''}_$runIndex';
    }
    return runKeys;
  }
}
