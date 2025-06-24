import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/models/books.dart';

class BookmarkView extends StatelessWidget {
  const BookmarkView({Key? key}) : super(key: key);

  bool _isSameBook(Book a, Book b) {
    if (a.runtimeType != b.runtimeType) return false;
    if (a is PdfBook && b is PdfBook) return a.path == b.path;
    return a.title == b.title;
  }

  void _openBook(
      BuildContext context, Book book, int index, List<String>? commentators) {
    final tab = book is PdfBook
        ? PdfBookTab(book: book, pageNumber: index)
        : TextBookTab(
            book: book as TextBook, index: index, commentators: commentators);

    context.read<TabsBloc>().add(AddTab(tab));
    context.read<NavigationBloc>().add(const NavigateToScreen(Screen.reading));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BookmarkBloc, BookmarkState>(
      builder: (context, state) {
        return state.bookmarks.isEmpty
            ? const Center(child: Text('אין סימניות'))
            : Column(
                children: [
                  Expanded(
                    child: BlocBuilder<TabsBloc, TabsState>(
                      builder: (context, tabsState) {
                        final currentTab = tabsState.currentTab;
                        Book? currentBook;
                        int? currentIndex;
                        if (currentTab is TextBookTab) {
                          currentBook = currentTab.book;
                          final st = currentTab.bloc.state;
                          if (st is TextBookLoaded) {
                            currentIndex = st.visibleIndices.first;
                          } else {
                            currentIndex = currentTab.index;
                          }
                        } else if (currentTab is PdfBookTab) {
                          currentBook = currentTab.book;
                          currentIndex = currentTab.pdfViewerController.isReady
                              ? (currentTab.pdfViewerController.pageNumber ??
                                  currentTab.pageNumber)
                              : currentTab.pageNumber;
                        }

                        return ListView.builder(
                          itemCount: state.bookmarks.length,
                          itemBuilder: (context, index) {
                            final bookmark = state.bookmarks[index];
                            final bool isSelected = currentBook != null &&
                                currentIndex != null &&
                                _isSameBook(bookmark.book, currentBook) &&
                                bookmark.index == currentIndex;
                            return ListTile(
                              selected: isSelected,
                              // Match other screens by using onSecondary
                              // for the selected text so it remains legible
                              // against the highlight background in dark mode.
                              selectedColor:
                                  Theme.of(context).colorScheme.onSecondary,
                              selectedTileColor: Theme.of(context)
                                  .colorScheme
                                  .secondary
                                  .withOpacity(0.2),
                              title: Text(bookmark.ref),
                              onTap: () => _openBook(
                                  context,
                                  bookmark.book,
                                  bookmark.index,
                                  bookmark.commentatorsToShow),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete_forever,
                                ),
                                onPressed: () {
                                  context
                                      .read<BookmarkBloc>()
                                      .removeBookmark(index);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('הסימניה נמחקה'),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ElevatedButton(
                      onPressed: () {
                        context.read<BookmarkBloc>().clearBookmarks();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('כל הסימניות נמחקו'),
                          ),
                        );
                      },
                      child: const Text('מחק את כל הסימניות'),
                    ),
                  ),
                ],
              );
      },
    );
  }
}
