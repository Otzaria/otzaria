/// קישורים בתפריטי הקשר
library;

import 'package:flutter/material.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/links/ui/sharing_links.dart';

/// מחלקה לטיפול בקישורים בתפריטי הקשר
class ContextMenuLinks {
  
  /// יצירת פריט תפריט לשיתוף קישור לספר
  static PopupMenuItem<String> createShareBookLinkMenuItem(
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
      onTap: () => SharingLinks.shareBookLink(
        context,
        book,
        position: position,
        highlightText: highlightText,
        fullSectionHighlight: fullSectionHighlight,
      ),
    );
  }

  /// יצירת פריט תפריט לשיתוף קישור מטאב
  static PopupMenuItem<String> createShareTabLinkMenuItem(
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
      onTap: () => SharingLinks.shareTabLink(context, tab),
    );
  }

  /// יצירת פריט תפריט לשיתוף קישור פשוט
  static PopupMenuItem<String> createShareSimpleLinkMenuItem(
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
      onTap: () => SharingLinks.shareSimpleBookLink(context, bookTitle),
    );
  }

  /// יצירת פריט תפריט לשיתוף קישור לכותרת
  static PopupMenuItem<String> createShareHeaderLinkMenuItem(
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
      onTap: () => SharingLinks.shareBookHeaderLink(context, bookTitle, header),
    );
  }

  /// רשימת פריטי תפריט לספר
  static List<PopupMenuItem<String>> getBookMenuItems(
    BuildContext context,
    Book book, {
    int? position,
    String? highlightText,
    bool fullSectionHighlight = false,
  }) {
    return [
      createShareBookLinkMenuItem(
        context,
        book,
        position: position,
        highlightText: highlightText,
        fullSectionHighlight: fullSectionHighlight,
      ),
      createShareSimpleLinkMenuItem(context, book.title),
    ];
  }

  /// רשימת פריטי תפריט לטאב
  static List<PopupMenuItem<String>> getTabMenuItems(
    BuildContext context,
    OpenedTab tab,
  ) {
    return [
      createShareTabLinkMenuItem(context, tab),
    ];
  }
}