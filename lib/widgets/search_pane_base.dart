import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

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

  @override
  State<SearchPaneBase> createState() => _SearchPaneBaseState();
}

class _SearchPaneBaseState extends State<SearchPaneBase> {
  Timer? _debounceTimer;

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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.progressWidget != null) widget.progressWidget!,
        const SizedBox(height: 4),
        Row(
          children: [
            const SizedBox(width: 8),
            Expanded(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: widget.searchController,
                    builder: (context, value, _) {
                      return TextField(
                        autofocus: true,
                        focusNode: widget.focusNode,
                        controller: widget.searchController,
                        textAlign: TextAlign.right,
                        onChanged: (value) => _debounce(
                            () => widget.onSearchTextChanged?.call(value)),
                        onSubmitted: (_) {
                          widget.focusNode.requestFocus();
                        },
                        decoration: InputDecoration(
                          hintText: widget.hintText,
                          suffixIcon: IconButton(
                            tooltip: 'נקה',
                            onPressed: value.text.isNotEmpty
                                ? () {
                                    widget.searchController.clear();
                                    widget.onSearchTextChanged?.call('');
                                    widget.resetSearchCallback();
                                    widget.focusNode.requestFocus();
                                  }
                                : null,
                            icon: const Icon(FluentIcons.dismiss_24_regular),
                          ),
                        ),
                        textInputAction: TextInputAction.search,
                        textDirection: TextDirection.rtl,
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        if (widget.resultCountString != null)
          Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                widget.resultCountString!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).textTheme.bodySmall?.color ??
                      Colors.grey[700],
                ),
              ),
            ),
          ),
        const SizedBox(height: 4),
        Expanded(
          child: widget.isNoResults
              ? const Center(child: Text('אין תוצאות'))
              : widget.resultsWidget,
        ),
      ],
    );
  }
}
