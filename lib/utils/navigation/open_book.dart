import 'package:flutter/material.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/models/books.dart';
import "package:flutter_bloc/flutter_bloc.dart";
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';

void openBook(BuildContext context, Book book, int index, String searchQuery,
    {bool ignoreHistory = false,
    bool requiresStableLayout = false,
    String? pinpointHighlight}) {
  final coordinator = BookOpenCoordinator(
    tabsBloc: context.read<TabsBloc>(),
    historyBloc: context.read<HistoryBloc>(),
    navigationBloc: context.read<NavigationBloc>(),
  );
  coordinator.openBook(
    book,
    index,
    searchQuery,
    ignoreHistory: ignoreHistory,
    requiresStableLayout: requiresStableLayout,
    pinpointHighlight: pinpointHighlight,
  );
}
