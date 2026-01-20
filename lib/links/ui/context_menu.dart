/// תפריטי הקשר לקישורים
library;

import 'package:flutter/material.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/tab.dart';
import '../services/sharing_service.dart';

/// מחלקה לטיפול בקישורים בתפריטי הקשר
class ContextMenuLinks {
  
  /// יצירת פריט תפריט לשיתוף קישור לספר
  static PopupMenuItem<String> shareBookItem(
    BuildContext context,
    Book book, {
    int? position,
    String? highlightText,
    bool fullSectionHighlight = false,
  }) {
    return PopupMenuItem<String>(
      value: 'share_book_link',
      child: const Row(
        children: [
          Icon(Icons.link),
          SizedBox(width: 8),
          Text('שתף קישור'),
        ],
      ),
      onTap: () => SharingService.shareBook(
        context,
        book,
        position: position,
        highlightText: highlightText,
        fullSectionHighlight: fullSectionHighlight,
      ),
    );
  }

  /// יצירת פריט תפריט לשיתוף קישור מטאב
  static PopupMenuItem<String> shareTabItem(
    BuildContext context,
    OpenedTab tab,
  ) {
    return PopupMenuItem<String>(
      value: 'share_tab_link',
      child: const Row(
        children: [
          Icon(Icons.link),
          SizedBox(width: 8),
          Text('שתף קישור'),
        ],
      ),
      onTap: () => SharingService.shareTab(context, tab),
    );
  }

  /// יצירת פריט תפריט לשיתוף קישור פשוט
  static PopupMenuItem<String> shareSimpleItem(
    BuildContext context,
    String bookTitle,
  ) {
    return PopupMenuItem<String>(
      value: 'share_simple_link',
      child: const Row(
        children: [
          Icon(Icons.link),
          SizedBox(width: 8),
          Text('שתף קישור לספר'),
        ],
      ),
      onTap: () => SharingService.shareSimpleBook(context, bookTitle),
    );
  }

  /// יצירת פריט תפריט לשיתוף קישור לכותרת
  static PopupMenuItem<String> shareHeaderItem(
    BuildContext context,
    String bookTitle,
    String header,
  ) {
    return PopupMenuItem<String>(
      value: 'share_header_link',
      child: const Row(
        children: [
          Icon(Icons.link),
          SizedBox(width: 8),
          Text('שתף קישור לכותרת'),
        ],
      ),
      onTap: () => SharingService.shareBookHeader(context, bookTitle, header),
    );
  }

  /// יצירת פריט תפריט לשיתוף עם הדגשה
  static PopupMenuItem<String> shareHighlightItem(
    BuildContext context,
    Book book,
    int position,
    String highlightText,
  ) {
    return PopupMenuItem<String>(
      value: 'share_highlight_link',
      child: const Row(
        children: [
          Icon(Icons.highlight),
          SizedBox(width: 8),
          Text('שתף עם הדגשה'),
        ],
      ),
      onTap: () => SharingService.shareWithHighlight(
        context, 
        book, 
        position, 
        highlightText,
      ),
    );
  }

  /// יצירת פריט תפריט לשיתוף עם הדגשת מקטע מלא
  static PopupMenuItem<String> shareFullHighlightItem(
    BuildContext context,
    Book book,
    int position,
  ) {
    return PopupMenuItem<String>(
      value: 'share_full_highlight_link',
      child: const Row(
        children: [
          Icon(Icons.highlight_alt),
          SizedBox(width: 8),
          Text('שתף עם הדגשת מקטע'),
        ],
      ),
      onTap: () => SharingService.shareWithFullHighlight(
        context, 
        book, 
        position,
      ),
    );
  }

  /// רשימת פריטי תפריט בסיסיים לספר
  static List<PopupMenuItem<String>> bookItems(
    BuildContext context,
    Book book, {
    int? position,
    String? highlightText,
    bool fullSectionHighlight = false,
  }) {
    final items = <PopupMenuItem<String>>[
      shareBookItem(
        context,
        book,
        position: position,
        highlightText: highlightText,
        fullSectionHighlight: fullSectionHighlight,
      ),
      shareSimpleItem(context, book.title),
    ];

    // הוספת פריטי הדגשה אם רלוונטי
    if (position != null) {
      if (highlightText != null && highlightText.isNotEmpty) {
        items.add(shareHighlightItem(context, book, position, highlightText));
      }
      items.add(shareFullHighlightItem(context, book, position));
    }

    return items;
  }

  /// רשימת פריטי תפריט לטאב
  static List<PopupMenuItem<String>> tabItems(
    BuildContext context,
    OpenedTab tab,
  ) {
    return [
      shareTabItem(context, tab),
    ];
  }

  /// רשימת פריטי תפריט מורחבת
  static List<PopupMenuItem<String>> extendedItems(
    BuildContext context,
    Book book,
    int position, {
    String? highlightText,
    String? header,
  }) {
    final items = bookItems(
      context, 
      book, 
      position: position, 
      highlightText: highlightText,
    );

    if (header != null && header.isNotEmpty) {
      items.add(shareHeaderItem(context, book.title, header));
    }

    return items;
  }
}