import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';

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
      title: Text(widget.title),
      content: SizedBox(
        width: 300,
        height: 400,
        child: Column(
          children: [
            RtlTextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: widget.searchHint,
                prefixIcon: const Icon(FluentIcons.search_24_regular),
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filteredItems.length,
                itemBuilder: (context, index) {
                  final item = filteredItems[index];
                  final isSelected = item.value == widget.initialValue;

                  return ListTile(
                    title: Text(item.label),
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ביטול'),
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
