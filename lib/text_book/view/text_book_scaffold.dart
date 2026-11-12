import 'package:flutter/material.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/view/plugin_correction_session_banner.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/text_book/utils/reader_build_policy.dart';
import 'package:otzaria/text_book/view/strategies/strategies.dart';
import 'package:otzaria/text_book/widgets/text_book_state_builder.dart';

/// Scaffold for text book viewing that uses Strategy Pattern
/// to select the appropriate view mode.
class TextBookScaffold extends StatelessWidget {
  final List<String> content;
  final Function(OpenedTab) openBookCallback;
  final void Function(int, {String? searchText}) openLeftPaneTab;
  final void Function(String? text, int? lineIndex, int? column)?
  onSelectedTextChanged;
  final TextEditingValue searchTextController;
  final TextBookTab tab;
  final int? initialSidebarTabIndex;
  final Key? pageShapeKey; // מפתח עבור PageShapeScreen
  final Key? splitViewKey;
  final GlobalKey? pageShapePrintBoundaryKey; // מפתח עבור צילום למסמך הדפסה
  final ValueNotifier<int?>? pageShapeSidebarTabNotifier;

  /// בקשה לפתיחת דיאלוג הגדרות צורת הדף מתוך PageShapeScreen (עדכון חי)
  final ValueNotifier<int>? pageShapeOpenSettingsNotifier;
  final ValueChanged<String?>? openSearch;
  final ValueChanged<int>? onSidebarTabChanged;

  const TextBookScaffold({
    super.key,
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

  @override
  Widget build(BuildContext context) {
    return TextBookStateBuilder(
      buildWhen: shouldRebuildReader,
      builder: (context, state) {
        // Select the appropriate strategy based on current state
        final strategy = _selectStrategy(state);

        // Create configuration for the strategy
        final config = TextBookViewConfig(
          content: content,
          openBookCallback: openBookCallback,
          openLeftPaneTab: openLeftPaneTab,
          onSelectedTextChanged: onSelectedTextChanged,
          searchTextController: searchTextController,
          tab: tab,
          initialSidebarTabIndex: initialSidebarTabIndex,
          pageShapeKey: pageShapeKey,
          splitViewKey: splitViewKey,
          pageShapePrintBoundaryKey: pageShapePrintBoundaryKey,
          pageShapeSidebarTabNotifier: pageShapeSidebarTabNotifier,
          pageShapeOpenSettingsNotifier: pageShapeOpenSettingsNotifier,
          openSearch: openSearch,
          onSidebarTabChanged: onSidebarTabChanged,
        );

        return _withCorrectionBanner(
          strategy.buildView(context, config),
          pageShape: state.showPageShapeView,
        );
      },
    );
  }

  /// מבנה קבוע מהבנייה הראשונה: שינוי המבנה בתחילת סשן היה בונה את הקורא
  /// מחדש ומאבד בחירה ומצב. הבאנר עצמו ריק כשאין סשן.
  Widget _withCorrectionBanner(Widget view, {required bool pageShape}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PluginCorrectionSessionBanner(
          tabId: PluginCorrectionSessionService.tabIdFor(tab),
          pageShape: pageShape,
        ),
        Expanded(child: view),
      ],
    );
  }

  /// Selects the appropriate view strategy based on the current state
  TextBookViewStrategy _selectStrategy(dynamic state) {
    // Check for page shape view first (highest priority)
    if (state.showPageShapeView) {
      return PageShapeStrategyImpl();
    }

    return SplitViewStrategyImpl(showSplitView: state.showSplitView);
  }
}
