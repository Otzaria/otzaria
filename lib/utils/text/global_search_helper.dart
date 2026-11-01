import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/common_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/search/search_defaults.dart';
import 'package:otzaria/semantic_search/models/semantic_result_item.dart';
import 'package:otzaria/semantic_search/repository/semantic_platform_support.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/semantic_search_tab.dart';

void openGlobalSearch(
  BuildContext context,
  String? selectedText, {
  bool insertAdjacent = true,
  bool? platformSupported,
}) {
  final query = selectedText?.trim() ?? '';
  if (query.isEmpty) {
    UiSnack.show(CommonMessages.noTextSelectedForSearch);
    return;
  }

  final SearchingTab tab;
  if (SearchDefaults.initialSemanticForNewSearch() &&
      (platformSupported ?? isSemanticSearchPlatformSupported())) {
    tab = SemanticSearchTab(
      runOnFirstShow: true,
      options: SemanticQueryOptions(
        query: query,
        includeLexical:
            SearchDefaults.initialSemanticIncludeLexicalForNewSearch(),
        groupIdenticalText:
            SearchDefaults.initialSemanticGroupIdenticalForNewSearch(),
      ),
    );
  } else {
    tab = SearchingTab.newSearch(SearchingTab.titleForQuery(query), query);
    context.read<HistoryBloc>().add(AddHistory(tab));
  }
  context.read<TabsBloc>().add(AddTab(tab, insertAdjacent: insertAdjacent));
}
