import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/misc/keyboard_dialog_navigation.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/feedback/tool_empty_state.dart';

/// דיאלוג בחירה עם חיפוש
class SelectionDialog<T> extends StatefulWidget {
  final String title;
  final List<SelectionItem<T>> items;
  final T? initialValue;
  final String searchHint;

  const SelectionDialog({
    super.key,
    required this.title,
    required this.items,
    this.initialValue,
    this.searchHint = 'חיפוש...',
  });

  @override
  State<SelectionDialog<T>> createState() => _SelectionDialogState<T>();
}

class _SelectionDialogState<T> extends State<SelectionDialog<T>>
    with DialogNavigationMixin {
  late List<SelectionItem<T>> filteredItems;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    focusedButtonIndex = 0;
    filteredItems = widget.items;
    _searchController.addListener(_filterItems);
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _filterItems() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      filteredItems = widget.items.where((item) {
        return item.label.toLowerCase().contains(query) ||
            item.searchValue.toLowerCase().contains(query);
      }).toList();
    });
  }

  void _handleConfirm() {
    if (_searchFocusNode.hasFocus) {
      return;
    }

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return buildKeyboardNavigator(
      onConfirm: _handleConfirm,
      onCancel: () => Navigator.of(context).pop(),
      textFieldFocusNode: _searchFocusNode,
      child: AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        title: Text(
          widget.title,
          textDirection: TextDirection.rtl,
        ),
        content: SizedBox(
          width: 300,
          height: 400,
          child: Column(
            children: [
              OtzariaSearchField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                hintText: widget.searchHint,
                autofocus: true,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: filteredItems.isEmpty
                    ? const ToolEmptyState(
                        icon: FluentIcons.search_24_regular,
                        message: 'לא נמצאו תוצאות',
                      )
                    : ListView.builder(
                        itemCount: filteredItems.length,
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          final isSelected = item.value == widget.initialValue;

                          return ListTile(
                            title: Text(
                              item.label,
                              textDirection: TextDirection.rtl,
                            ),
                            selected: isSelected,
                            trailing: isSelected
                                ? const Icon(FluentIcons.checkmark_24_regular)
                                : null,
                            onTap: () {
                              Navigator.of(context).pop(item.value);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          NeutralActionButton(
            text: 'ביטול',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// פונקציה להצגת דיאלוג בחירה עם חיפוש
Future<T?> showSelectionDialog<T>({
  required BuildContext context,
  required String title,
  required List<SelectionItem<T>> items,
  T? initialValue,
  String searchHint = 'חיפוש...',
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => SelectionDialog<T>(
      title: title,
      items: items,
      initialValue: initialValue,
      searchHint: searchHint,
    ),
  );
}

/// מחלקה לייצוג פריט בחירה
class SelectionItem<T> {
  final String label;
  final String searchValue;
  final T value;

  const SelectionItem({
    required this.label,
    required this.value,
    String? searchValue,
  }) : searchValue = searchValue ?? label;
}
