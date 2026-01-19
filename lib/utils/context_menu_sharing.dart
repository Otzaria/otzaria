import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/utils/sharing_utils.dart';

/// Utility class for context menu sharing functions
/// This centralizes the sharing logic that was duplicated across multiple view files
class ContextMenuSharing {
  
  /// Share book link from any text book view
  static Future<void> shareBookLink(
    BuildContext context,
    TextBookTab tab,
    Function(String) onSuccess,
    Function(String) onError,
  ) async {
    final state = context.read<TextBookBloc>().state;
    if (state is! TextBookLoaded) return;
    
    await SharingUtils.shareBookLink(tab, onSuccess, onError);
  }

  /// Share section link for a specific index
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
    
    await SharingUtils.shareSectionLink(tempTab, onSuccess, onError);
  }

  /// Share highlighted text link for a specific index
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
    
    await SharingUtils.shareHighlightedTextLink(
      tempTab,
      onSuccess,
      onError,
      selectedText: selectedText,
    );
  }
}