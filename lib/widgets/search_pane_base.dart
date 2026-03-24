import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/otzaria_search_field.dart';
import 'package:otzaria/theme/theme_exports.dart';

class SearchPaneBase extends StatefulWidget {
  const SearchPaneBase({
    required this.searchController,
    required this.focusNode,
    this.progressWidget,
    this.resultCountString,
    required this.resultsWidget,
    required this.isNoResults,
    this.onSearchTextChanged,
    required this.resetSearchCallback,
    this.hintText,
    this.onAdvancedSearch,
    this.additionalActions,
    // ── Collapse ──────────────────────────────────────────────────────────
    /// כשאמת — שדה החיפוש מתכווץ אוטומטית לאייקון בזמן גלילה למטה.
    /// המסך הקורא אחראי לחבר את resultsWidget ל-NotificationListener
    /// (ראה דוגמה ב-build), או לשלוט על isCompact ידנית.
    this.collapsibleOnScroll = false,
    super.key,
  });

  final TextEditingController searchController;
  final FocusNode focusNode;
  final Widget? progressWidget;
  final String? resultCountString;
  final Widget resultsWidget;
  final bool isNoResults;
  final ValueChanged<String>? onSearchTextChanged;
  final VoidCallback resetSearchCallback;
  final String? hintText;
  final VoidCallback? onAdvancedSearch;
  final List<Widget>? additionalActions;

  /// האם לאפשר collapse בגלילה (M3 scroll-hide pattern)
  final bool collapsibleOnScroll;

  @override
  State<SearchPaneBase> createState() => _SearchPaneBaseState();
}

class _SearchPaneBaseState extends State<SearchPaneBase> {
  Timer? _debounceTimer;

  /// האם שדה החיפוש מכווץ כעת
  bool _isCompact = false;

  void _debounce(VoidCallback action) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      action();
      _debounceTimer = null;
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  // ── Scroll handler ───────────────────────────────────────────────────────
  bool _onScrollNotification(ScrollNotification notification) {
    if (!widget.collapsibleOnScroll) return false;

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      final offset = notification.metrics.pixels;

      // גלילה למטה > 4dp: כווץ
      if (delta > 4 && !_isCompact) {
        setState(() => _isCompact = true);
      }
      // גלילה למעלה או חזרה לראש: פתח
      else if ((delta < -4 || offset <= 0) && _isCompact) {
        setState(() => _isCompact = false);
      }
    }

    // פוקוס בשדה — תמיד פתוח
    if (notification is UserScrollNotification && _isCompact) {
      if (widget.focusNode.hasFocus) {
        setState(() => _isCompact = false);
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final searchField = Padding(
      key: const ValueKey('searchField'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceSM,
        vertical: AppTokens.spaceXS,
      ),
      child: OtzariaSearchField(
        controller: widget.searchController,
        focusNode: widget.focusNode,
        autofocus: true,
        hintText: widget.hintText ?? '',
        onChanged: (v) => _debounce(() => widget.onSearchTextChanged?.call(v)),
        onSubmitted: (_) => widget.focusNode.requestFocus(),
        onClear: () {
          widget.onSearchTextChanged?.call('');
          widget.resetSearchCallback();
          widget.focusNode.requestFocus();
        },
        isCompact: _isCompact,
        onExpand: () => setState(() => _isCompact = false),
        leading: const Icon(FluentIcons.search_24_regular),
        trailingActions: [
          if (widget.additionalActions != null) ...widget.additionalActions!,
          if (widget.onAdvancedSearch != null)
            OtzariaSearchAction.settings(onPressed: widget.onAdvancedSearch!),
        ],
      ),
    );

    // תוכן התוצאות — עוטף ב-NotificationListener לתמיכת collapse
    final resultsArea = NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: widget.isNoResults
          ? const Center(child: Text('אין תוצאות'))
          : widget.resultsWidget,
    );

    return Column(
      children: [
        if (widget.progressWidget != null) widget.progressWidget!,
        // שורת חיפוש — מיושרת לשמאל כשמכווץ (לא ממלאת כל הרוחב)
        AnimatedAlign(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: _isCompact
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.center,
          child: searchField,
        ),
        if (!_isCompact && widget.resultCountString != null)
          Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                widget.resultCountString!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        Expanded(child: resultsArea),
      ],
    );
  }
}
