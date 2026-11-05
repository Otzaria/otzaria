import 'package:flutter/material.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';

/// Configuration for text book view strategies
class TextBookViewConfig {
  final List<String> content;
  final Function(OpenedTab) openBookCallback;
  final void Function(int, {String? searchText}) openLeftPaneTab;
  final void Function(String? text, int? lineIndex, int? column)?
  onSelectedTextChanged;
  final TextEditingValue searchTextController;
  final TextBookTab tab;
  final int? initialSidebarTabIndex;
  final Key? pageShapeKey;
  final Key? splitViewKey;
  final GlobalKey? pageShapePrintBoundaryKey;
  final ValueNotifier<int?>? pageShapeSidebarTabNotifier;

  /// בקשה לפתיחת דיאלוג הגדרות צורת הדף מתוך PageShapeScreen (עדכון חי)
  final ValueNotifier<int>? pageShapeOpenSettingsNotifier;
  final ValueChanged<String?>? openSearch;
  final ValueChanged<int>? onSidebarTabChanged;

  const TextBookViewConfig({
    required this.content,
    required this.openBookCallback,
    required this.openLeftPaneTab,
    this.onSelectedTextChanged,
    required this.searchTextController,
    required this.tab,
    this.initialSidebarTabIndex,
    this.pageShapeKey,
    this.splitViewKey,
    this.pageShapePrintBoundaryKey,
    this.pageShapeSidebarTabNotifier,
    this.pageShapeOpenSettingsNotifier,
    this.openSearch,
    this.onSidebarTabChanged,
  });
}

/// Strategy interface for different text book view modes
///
/// This follows the Strategy Pattern to allow easy addition of new
/// view modes without modifying existing code.
abstract class TextBookViewStrategy {
  /// Builds the widget tree for this view mode
  Widget buildView(BuildContext context, TextBookViewConfig config);
}
