import 'package:flutter/material.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';

/// Configuration for text book view strategies
class TextBookViewConfig {
  final List<String> content;
  final Function(OpenedTab) openBookCallback;
  final void Function(int, {String? searchText}) openLeftPaneTab;
  final ValueChanged<String?>? onSelectedTextChanged;
  final TextEditingValue searchTextController;
  final TextBookTab tab;
  final int? initialSidebarTabIndex;
  final Key? pageShapeKey;
  final GlobalKey? pageShapePrintBoundaryKey;
  final ValueNotifier<int?>? pageShapeSidebarTabNotifier;

  const TextBookViewConfig({
    required this.content,
    required this.openBookCallback,
    required this.openLeftPaneTab,
    this.onSelectedTextChanged,
    required this.searchTextController,
    required this.tab,
    this.initialSidebarTabIndex,
    this.pageShapeKey,
    this.pageShapePrintBoundaryKey,
    this.pageShapeSidebarTabNotifier,
  });
}

/// Strategy interface for different text book view modes
///
/// This follows the Strategy Pattern to allow easy addition of new
/// view modes without modifying existing code.
abstract class TextBookViewStrategy {
  /// Returns the display name of this view mode (for debugging/UI)
  String get displayName;

  /// Builds the widget tree for this view mode
  Widget buildView(BuildContext context, TextBookViewConfig config);

  /// Called when the strategy is selected (optional cleanup/setup)
  void onActivate() {}

  /// Called when switching away from this strategy (optional cleanup)
  void onDeactivate() {}
}

/// Enum representing available view modes
enum TextBookViewMode {
  /// Split view - commentaries shown in a side panel
  split,

  /// Combined view - commentaries shown below text
  combined,

  /// Page shape view - traditional Talmud page layout
  pageShape,
}

/// Extension to get display name for view modes
extension TextBookViewModeExtension on TextBookViewMode {
  /// Returns display name for UI
  String get displayName {
    switch (this) {
      case TextBookViewMode.split:
        return 'מפרשים בצד';
      case TextBookViewMode.combined:
        return 'מפרשים מתחת';
      case TextBookViewMode.pageShape:
        return 'צורת הדף';
    }
  }
}
