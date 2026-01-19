// This file has been moved to lib/links/ui/sharing_links.dart
// Import the new module instead:
// import 'package:otzaria/links/links.dart';

import 'package:flutter/material.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/links/ui/sharing_links.dart' as links;

/// Legacy wrapper for ContextMenuSharing - use ContextMenuSharing from links module instead
/// 
/// This class is deprecated and will be removed in a future version.
/// Please use the new links module: import 'package:otzaria/links/links.dart';
@Deprecated('Use ContextMenuSharing from the links module instead')
class ContextMenuSharing {
  
  @Deprecated('Use ContextMenuSharing from links module instead')
  static Future<void> shareBookLink(
    BuildContext context,
    TextBookTab tab,
    Function(String) onSuccess,
    Function(String) onError,
  ) async {
    return links.ContextMenuSharing.shareBookLink(context, tab, onSuccess, onError);
  }

  @Deprecated('Use ContextMenuSharing from links module instead')
  static Future<void> shareSectionLink(
    BuildContext context,
    String bookTitle,
    int index,
    Function(String) onSuccess,
    Function(String) onError,
  ) async {
    return links.ContextMenuSharing.shareSectionLink(context, bookTitle, index, onSuccess, onError);
  }

  @Deprecated('Use ContextMenuSharing from links module instead')
  static Future<void> shareTextHighlightLink(
    BuildContext context,
    String bookTitle,
    int index,
    String? selectedText,
    Function(String) onSuccess,
    Function(String) onError,
  ) async {
    return links.ContextMenuSharing.shareTextHighlightLink(context, bookTitle, index, selectedText, onSuccess, onError);
  }
}