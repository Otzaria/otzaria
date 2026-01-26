import 'package:flutter/material.dart';

/// A simple, reusable widget for displaying a list of selectable chips.
/// Replaces the complex filter_list library with a lightweight solution
/// using Flutter's built-in FilterChip widget.
///
/// Features:
/// - Multi-select or single-select mode
/// - Custom chip builder support
/// - Wrap alignment configuration
/// - Callback on selection change
class FilterChipsWidget<T> extends StatefulWidget {
  const FilterChipsWidget({
    super.key,
    required this.items,
    required this.selectedItems,
    required this.labelBuilder,
    required this.onSelectionChanged,
    this.chipBuilder,
    this.wrapAlignment = WrapAlignment.start,
    this.wrapSpacing = 8.0,
    this.runSpacing = 4.0,
    this.padding = const EdgeInsets.all(8.0),
  });

  /// All available items to display as chips
  final List<T> items;

  /// Currently selected items
  final List<T> selectedItems;

  /// Function to get the display label for an item
  final String Function(T item) labelBuilder;

  /// Callback when selection changes
  final void Function(List<T> selectedItems) onSelectionChanged;

  /// Optional custom chip builder for full control over chip appearance
  final Widget Function(BuildContext context, T item, bool isSelected)?
      chipBuilder;

  /// Alignment of chips in the wrap
  final WrapAlignment wrapAlignment;

  /// Horizontal spacing between chips
  final double wrapSpacing;

  /// Vertical spacing between rows
  final double runSpacing;

  /// Padding around the entire widget
  final EdgeInsets padding;

  @override
  State<FilterChipsWidget<T>> createState() => _FilterChipsWidgetState<T>();
}

class _FilterChipsWidgetState<T> extends State<FilterChipsWidget<T>> {
  late List<T> _selectedItems;

  @override
  void initState() {
    super.initState();
    _selectedItems = List<T>.from(widget.selectedItems);
  }

  @override
  void didUpdateWidget(FilterChipsWidget<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedItems != oldWidget.selectedItems) {
      _selectedItems = List<T>.from(widget.selectedItems);
    }
  }

  void _toggleSelection(T item) {
    setState(() {
      if (_selectedItems.contains(item)) {
        _selectedItems.remove(item);
      } else {
        _selectedItems.add(item);
      }
    });
    widget.onSelectionChanged(_selectedItems);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding,
      child: Wrap(
        alignment: widget.wrapAlignment,
        spacing: widget.wrapSpacing,
        runSpacing: widget.runSpacing,
        children: widget.items.map((item) {
          final isSelected = _selectedItems.contains(item);

          if (widget.chipBuilder != null) {
            return GestureDetector(
              onTap: () => _toggleSelection(item),
              child: widget.chipBuilder!(context, item, isSelected),
            );
          }

          return FilterChip(
            label: Text(widget.labelBuilder(item)),
            selected: isSelected,
            onSelected: (_) => _toggleSelection(item),
            selectedColor: Theme.of(context).colorScheme.secondary,
            labelStyle: TextStyle(
              color:
                  isSelected ? Theme.of(context).colorScheme.onSecondary : null,
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// A simplified version that maintains selection state externally
/// (stateless version for use with Bloc/Cubit)
class FilterChipsSelector<T> extends StatelessWidget {
  const FilterChipsSelector({
    super.key,
    required this.items,
    required this.selectedItems,
    required this.labelBuilder,
    required this.onSelectionChanged,
    this.chipBuilder,
    this.wrapAlignment = WrapAlignment.start,
    this.wrapSpacing = 8.0,
    this.runSpacing = 4.0,
    this.padding = const EdgeInsets.all(8.0),
  });

  /// All available items to display as chips
  final List<T> items;

  /// Currently selected items
  final List<T> selectedItems;

  /// Function to get the display label for an item
  final String Function(T item) labelBuilder;

  /// Callback when selection changes
  final void Function(List<T> selectedItems) onSelectionChanged;

  /// Optional custom chip builder for full control over chip appearance
  final Widget Function(BuildContext context, T item, bool isSelected)?
      chipBuilder;

  /// Alignment of chips in the wrap
  final WrapAlignment wrapAlignment;

  /// Horizontal spacing between chips
  final double wrapSpacing;

  /// Vertical spacing between rows
  final double runSpacing;

  /// Padding around the entire widget
  final EdgeInsets padding;

  void _toggleSelection(T item) {
    final newSelection = List<T>.from(selectedItems);
    if (newSelection.contains(item)) {
      newSelection.remove(item);
    } else {
      newSelection.add(item);
    }
    onSelectionChanged(newSelection);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Wrap(
        alignment: wrapAlignment,
        spacing: wrapSpacing,
        runSpacing: runSpacing,
        children: items.map((item) {
          final isSelected = selectedItems.contains(item);

          if (chipBuilder != null) {
            return GestureDetector(
              onTap: () => _toggleSelection(item),
              child: chipBuilder!(context, item, isSelected),
            );
          }

          return FilterChip(
            label: Text(labelBuilder(item)),
            selected: isSelected,
            onSelected: (_) => _toggleSelection(item),
            selectedColor: Theme.of(context).colorScheme.secondary,
            labelStyle: TextStyle(
              color:
                  isSelected ? Theme.of(context).colorScheme.onSecondary : null,
            ),
          );
        }).toList(),
      ),
    );
  }
}
