import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';

/// דיאלוג בחירה מרובה עם חיפוש
class MultiSelectionDialog<T> extends StatefulWidget {
  final String title;
  final List<MultiSelectionItem<T>> items;
  final List<T> initialSelectedValues;
  final String searchHint;
  final String? emptyMessage;

  const MultiSelectionDialog({
    super.key,
    required this.title,
    required this.items,
    this.initialSelectedValues = const [],
    this.searchHint = 'חיפוש...',
    this.emptyMessage,
  });

  @override
  State<MultiSelectionDialog<T>> createState() =>
      _MultiSelectionDialogState<T>();
}

class _MultiSelectionDialogState<T> extends State<MultiSelectionDialog<T>> {
  late List<MultiSelectionItem<T>> filteredItems;
  late Set<T> selectedValues;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    filteredItems = widget.items;
    selectedValues = Set.from(widget.initialSelectedValues);
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
      if (query.isEmpty) {
        filteredItems = widget.items;
      } else {
        filteredItems = widget.items.where((item) {
          return item.label.toLowerCase().contains(query) ||
              item.searchValue.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
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
              child: widget.items.isEmpty
                  ? Center(
                      child: Text(
                        widget.emptyMessage ?? 'לא נמצאו פריטים',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : filteredItems.isEmpty
                      ? const Center(child: Text('לא נמצאו תוצאות'))
                      : ListView.builder(
                          itemCount: filteredItems.length,
                          itemBuilder: (context, index) {
                            final item = filteredItems[index];
                            final isSelected =
                                selectedValues.contains(item.value);

                            return CheckboxListTile(
                              title: Text(item.label),
                              subtitle: item.subtitle != null
                                  ? Text(item.subtitle!)
                                  : null,
                              value: isSelected,
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    selectedValues.add(item.value);
                                  } else {
                                    selectedValues.remove(item.value);
                                  }
                                });
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
        ElevatedButton(
          onPressed: selectedValues.isEmpty
              ? null
              : () => Navigator.of(context).pop(selectedValues.toList()),
          child: const Text('אישור'),
        ),
      ],
    );
  }
}

/// פונקציה להצגת דיאלוג בחירה מרובה עם חיפוש
Future<List<T>?> showMultiSelectionDialog<T>({
  required BuildContext context,
  required String title,
  required List<MultiSelectionItem<T>> items,
  List<T> initialSelectedValues = const [],
  String searchHint = 'חיפוש...',
  String? emptyMessage,
  bool barrierDismissible = true,
}) {
  return showDialog<List<T>>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => MultiSelectionDialog<T>(
      title: title,
      items: items,
      initialSelectedValues: initialSelectedValues,
      searchHint: searchHint,
      emptyMessage: emptyMessage,
    ),
  );
}

/// מחלקה לייצוג פריט בחירה מרובה
class MultiSelectionItem<T> {
  final String label;
  final String searchValue;
  final T value;
  final String? subtitle;

  const MultiSelectionItem({
    required this.label,
    required this.value,
    String? searchValue,
    this.subtitle,
  }) : searchValue = searchValue ?? label;
}
