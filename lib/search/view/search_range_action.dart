import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

/// כפתור "הגבל לטווח" בשדה החיפוש בתוך ספר, משותף לספר טקסט ול-PDF.
Widget searchRangeAction({
  required BuildContext context,
  required bool isActive,
  required VoidCallback onPressed,
}) {
  return OtzariaSearchAction.icon(
    iconData: isActive
        ? FluentIcons.filter_20_filled
        : FluentIcons.filter_20_regular,
    onPressed: onPressed,
    tooltip: isActive
        ? 'החיפוש מוגבל לטווח — לחץ לשינוי'
        : 'הגבל את החיפוש לטווח בספר',
    color: isActive ? Theme.of(context).colorScheme.primary : null,
  );
}

/// חיווי הטווח הפעיל מתחת לשדה החיפוש, עם הסרה בלחיצה על ה-X.
class SearchRangeChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const SearchRangeChip({
    super.key,
    required this.label,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 12, end: 12, bottom: 4),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: InputChip(
          avatar: Icon(
            FluentIcons.filter_20_regular,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          label: Text(
            'טווח: $label',
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          deleteButtonTooltipMessage: 'חפש בכל הספר',
          onDeleted: onRemove,
        ),
      ),
    );
  }
}
