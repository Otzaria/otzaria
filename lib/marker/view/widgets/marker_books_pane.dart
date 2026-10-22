import 'package:flutter/material.dart';
import 'package:otzaria/marker/models/marker_query.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';

/// חלונית הספרים של המרקר: ספר שנבחר מסנן את הרשימה אליו.
class MarkerBooksPane extends StatelessWidget {
  final List<MarkerBookCount> books;
  final int total;
  final ({String title, bool pdf})? selected;
  final ValueChanged<({String title, bool pdf})?> onSelected;

  const MarkerBooksPane({
    super.key,
    required this.books,
    required this.total,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return NavTreeFocusGroup(
      child: ListView.builder(
        padding: kNavTreeListPadding,
        itemCount: books.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return NavTreeHeader(
              title: 'כל הספרים',
              count: total,
              isSelected: selected == null,
              onTap: () => onSelected(null),
            );
          }
          final book = books[index - 1];
          final key = (title: book.title, pdf: book.pdf);
          final isSelected = key == selected;
          return NavTreeGroupCard(
            isGroupStart: index == 1,
            isGroupEnd: index == books.length,
            child: NavTreeTile.book(
              title: markerBookLabel(book.title, pdf: book.pdf),
              level: 0,
              count: book.count,
              isSelected: isSelected,
              onClearFilter: isSelected ? () => onSelected(null) : null,
              onTap: () => onSelected(key),
            ),
          );
        },
      ),
    );
  }
}
