import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/core/scaffold_messenger.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/widgets/items_list_view.dart';

class BookmarkView extends StatelessWidget {
  const BookmarkView({super.key});

  void _openBook(
      BuildContext context, Book book, int index, List<String>? commentators) {
    final tab = OpenedTab.fromBook(
      book,
      index,
      commentators: commentators,
      openLeftPane: (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
          (Settings.getValue<bool>('key-default-sidebar-open') ?? false),
    );

    context.read<TabsBloc>().add(AddTab(tab));
    context.read<NavigationBloc>().add(const NavigateToScreen(Screen.reading));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BookmarkBloc, BookmarkState>(
      builder: (context, state) {
        return ItemsListView(
          items: state.bookmarks,
          onItemTap: (ctx, item, originalIndex) =>
              _openBook(ctx, item.book, item.index, item.commentatorsToShow),
          onDelete: (ctx, originalIndex) {
            ctx.read<BookmarkBloc>().removeBookmark(originalIndex);
            UiSnack.show('הסימניה נמחקה');
          },
          onClearAll: (ctx) {
            ctx.read<BookmarkBloc>().clearBookmarks();
            UiSnack.show('כל הסימניות נמחקו');
          },
          hintText: 'חפש בסימניות...',
          emptyText: 'אין סימניות',
          notFoundText: 'לא נמצאו תוצאות',
          clearAllText: 'מחק את כל הסימניות',
          leadingIconBuilder: (item) =>
              item.book is PdfBook ? const Icon(FluentIcons.document_pdf_24_regular) : null,
        );
      },
    );
  }
}
