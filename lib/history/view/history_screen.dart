import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/widgets/dialogs/reusable_items_dialog.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';
import 'package:otzaria/widgets/lists/items_list_view.dart';

class HistoryDialog extends StatelessWidget {
  const HistoryDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return const ReusableItemsDialog(
      title: 'היסטוריה',
      child: HistoryView(),
    );
  }
}

class HistoryView extends StatelessWidget {
  const HistoryView({super.key});

  void _openBook(
    BuildContext context,
    Book book,
    int index,
    List<String>? commentators, {
    String? targetTitle,
  }) {
    final tab = OpenedTab.fromBook(
      book,
      index,
      commentators: commentators,
      openLeftPane: shouldAutoOpenReadingLeftPane(),
    );

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

        return ItemsListView(
          items: state.history,
          onItemTap: (ctx, item, originalIndex) {
            if (item.isSearch) {
              final tabsBloc = ctx.read<TabsBloc>();
              // Always create a new search tab instead of reusing existing one
              final searchTab = SearchingTab('חיפוש', null);
              tabsBloc.add(AddTab(searchTab));

              // Restore search query and options
              // ההיסטוריה שומרת אפשרויות מורחבות פר-מילה,
              // לכן עוברים למצב פר-מילה כדי שהן יוצגו ויפעלו בדיוק כפי שנשמרו
              searchTab.queryController.text = item.book.title;
              searchTab.searchOptions.clear();
              searchTab.searchOptions.addAll(item.searchOptions ?? {});
              searchTab.useGlobalSearchOptions.value = false;
              searchTab.alternativeWords.clear();
              searchTab.alternativeWords.addAll(item.alternativeWords ?? {});
              searchTab.spacingValues.clear();
              searchTab.spacingValues.addAll(item.spacingValues ?? {});
              searchTab.searchBloc.add(
                SetSearchMode(item.searchMode ?? SearchMode.advanced),
              );

              if (item.searchScopeFacets != null &&
                  item.searchScopeFacets!.isNotEmpty) {
                searchTab.searchBloc
                    .add(SetFacetsWithoutSearch(item.searchScopeFacets!));
              }

              searchTab
                  .updateTitleFromAppliedQuery(searchTab.queryController.text);
              searchTab.searchBloc.add(UpdateSearchQuery(
                searchTab.queryController.text,
                customSpacing: searchTab.spacingValues,
                alternativeWords: searchTab.alternativeWords,
                searchOptions: searchTab.searchOptions,
              ));

              // Navigate to search screen
              ctx
                  .read<NavigationBloc>()
                  .add(const NavigateToScreen(Screen.search));
              if (Navigator.of(ctx).canPop()) {
                Navigator.of(ctx).pop();
              }
              return;
            }
            _openBook(
              ctx,
              item.book,
              item.index,
              item.commentatorsToShow,
              targetTitle: item.ref,
            );
          },
          onDelete: (ctx, originalIndex) {
            ctx.read<HistoryBloc>().add(RemoveHistory(originalIndex));
            UiSnack.show('נמחק בהצלחה');
          },
          onClearAll: (ctx) {
            ctx.read<HistoryBloc>().add(ClearHistory());
            UiSnack.show('כל ההיסטוריה נמחקה');
          },
          hintText: 'חפש בהיסטוריה...',
          emptyText: 'אין היסטוריה',
          notFoundText: 'לא נמצאו תוצאות',
          clearAllText: 'מחק את כל ההיסטוריה',
          leadingIconBuilder: (item) =>
              _getLeadingIcon(item.book, item.isSearch),
          subtitleBuilder: (item) {
            final parts = <String>[];
            final facets = item.searchScopeFacets;
            if (facets != null && facets.isNotEmpty) {
              final allNames = _facetDisplayNames(facets);
              final displayed = allNames.length > 2
                  ? '${allNames.take(2).join(', ')}...'
                  : allNames.join(', ');
              parts.add('חיפוש בקטגוריות: $displayed');
            }
            if (item.workspaceName != null) {
              parts.add(item.workspaceName!);
            }
            return parts.isEmpty ? null : parts.join(' | ');
          },
          subtitleTooltipBuilder: (item) {
            final facets = item.searchScopeFacets;
            if (facets == null || facets.length <= 2) return null;
            return 'חיפוש בקטגוריות: ${_facetDisplayNames(facets).join(', ')}';
          },
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
}
