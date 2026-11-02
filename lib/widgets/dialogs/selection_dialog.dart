import 'package:flutter/material.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/dialogs/dialog_teardown.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';

/// דיאלוג בחירה עם חיפוש
class SelectionDialog<T> extends StatefulWidget {
  final String title;
  final List<SelectionItem<T>> items;
  final T? initialValue;

  /// null = "חיפוש..." בשפת הממשק.
  final String? searchHint;

  /// תג האייקון: מה בוחרים. null = אייקון משפחת הבחירה.
  final IconData? icon;

  /// גובה הרשימה עד חלק זה מגובה החלון (DD-07: בחירה עד 60%).
  static const double maxHeightFactor = 0.6;

  const SelectionDialog({
    super.key,
    required this.title,
    required this.items,
    this.initialValue,
    this.searchHint,
    this.icon,
  });

  @override
  State<SelectionDialog<T>> createState() => _SelectionDialogState<T>();
}

class _SelectionDialogState<T> extends State<SelectionDialog<T>>
    with DialogFocusRestorerMixin<SelectionDialog<T>> {
  late List<SelectionItem<T>> filteredItems;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    filteredItems = widget.items;
    _searchController.addListener(_filterItems);
    registerDialogFocusRestorer(_searchFocusNode);
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

  @override
  Widget build(BuildContext context) {
    // Enter על פריט בוחר אותו (הפריט עצמו מגיב ל-Enter); בשדה החיפוש אינו סוגר.
    return AppDialogFrame(
      title: widget.title,
      icon: widget.icon ?? AppDialogIcons.selection,
      size: AppDialogSize.small,
      height:
          MediaQuery.sizeOf(context).height * SelectionDialog.maxHeightFactor,
      handleEnterKey: false,
      actions: [
        ActionButton.neutral(
          text: context.settingsText('ביטול'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      child: Column(
        children: [
          OtzariaSearchField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            hintText: widget.searchHint ?? context.settingsText('חיפוש...'),
            autofocus: true,
          ),
          const SizedBox(height: AppTokens.spaceSM),
          Expanded(
            child: filteredItems.isEmpty
                ? OtzariaEmptyState(
                    icon: OtzariaIcons.search_24_regular,
                    title: context.settingsText('לא נמצאו תוצאות'),
                  )
                : ListView.builder(
                    itemCount: filteredItems.length,
                    itemBuilder: (context, index) {
                      final item = filteredItems[index];
                      final isSelected = item.value == widget.initialValue;

                      return ListTile(
                        title: Text(
                          item.label,
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
    );
  }
}

/// פונקציה להצגת דיאלוג בחירה עם חיפוש
Future<T?> showSelectionDialog<T>({
  required BuildContext context,
  required String title,
  required List<SelectionItem<T>> items,
  T? initialValue,
  String? searchHint,
  bool barrierDismissible = true,
  IconData? icon,
}) {
  return showDialogUntilTornDown<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (_) => Directionality(
      textDirection: Directionality.of(context),
      child: SelectionDialog<T>(
        title: title,
        items: items,
        initialValue: initialValue,
        searchHint: searchHint,
        icon: icon,
      ),
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
