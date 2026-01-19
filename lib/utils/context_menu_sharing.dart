// This file has been moved to lib/links/ui/sharing_links.dart
// Import the new module instead:
// import 'package:otzaria/links/links.dart';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/links/ui/sharing_links.dart';

/// Legacy wrapper for ContextMenuSharing - use SharingLinks from links module instead
/// 
/// This class is deprecated and will be removed in a future version.
/// Please use the new links module: import 'package:otzaria/links/links.dart';
@Deprecated('Use SharingLinks from the links module instead')
class ContextMenuSharing {
  
  @Deprecated('Use SharingLinks from links module instead')
  static Future<void> shareBookLink(
    BuildContext context,
    TextBookTab tab,
    Function(String) onSuccess,
    Function(String) onError,
  ) async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;
    
    await SharingLinks.shareBookLinkLegacy(tab, onSuccess, onError);
  }

  @Deprecated('Use SharingLinks from links module instead')
  static Future<void> shareSectionLink(
    BuildContext context,
    String bookTitle,
    int index,
    Function(String) onSuccess,
    Function(String) onError,
  ) async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;
    
    // Create temporary tab with the specific index
    final tempTab = TextBookTab(book: state.book, index: index);
    
    await SharingLinks.shareSectionLink(tempTab, onSuccess, onError);
  }

  @Deprecated('Use SharingLinks from links module instead')
  static Future<void> shareTextHighlightLink(
    BuildContext context,
    String bookTitle,
    int index,
    String? selectedText,
    Function(String) onSuccess,
    Function(String) onError,
  ) async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;
    
    // Create temporary tab with the specific index
    final tempTab = TextBookTab(book: state.book, index: index);
    
    await SharingLinks.shareHighlightedTextLink(
      tempTab,
      onSuccess,
      onError,
      selectedText: selectedText,
    );
  }
}