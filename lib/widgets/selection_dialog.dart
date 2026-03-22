import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/core/widgets/otzaria_search_field.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/widgets/tool_empty_state.dart';

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

class _SelectionDialogState<T> extends State<SelectionDialog<T>> {
  late List<SelectionItem<T>> filteredItems;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    filteredItems = widget.items;
    _searchController.addListener(_filterItems);
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      title: Text(widget.title, textDirection: TextDirection.rtl),
      content: SizedBox(
        width: 300,
        height: 400,
        child: Column(
          children: [
            OtzariaSearchField(
              controller: _searchController,
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
