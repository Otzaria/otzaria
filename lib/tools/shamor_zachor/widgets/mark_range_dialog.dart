import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';

import '../models/book_model.dart';
import 'hebrew_utils.dart';

/// טווח שנבחר בדיאלוג סימון הטווח (אינדקסים מוחלטים, כולל הקצוות)
class MarkRangeSelection {
  final int fromIndex;
  final int toIndex;
  final bool value;

  const MarkRangeSelection({
    required this.fromIndex,
    required this.toIndex,
    required this.value,
  });
}

/// התווית של פריט ברשימת הבחירה — נתיב הסעיפים בספר היררכי, ואחרת
/// שם החלק (כשיש כמה) עם מספר הדף/העמוד.
String markRangeItemLabel(BookDetails bookDetails, LearnableItem item) {
  if (item.hierarchyPath.isNotEmpty) return item.hierarchyPath.join(' · ');

  final pageLabel = HebrewUtils.pageLabel(
    item.pageNumber,
    item.amudKey,
    bookDetails.isDafType,
  );
  if (bookDetails.hasMultipleParts && item.partName.isNotEmpty) {
    return '${item.partName} · $pageLabel';
  }
  return pageLabel;
}

/// דיאלוג לסימון (או ביטול סימון) של טווח רציף בעמודה אחת.
/// מחזיר null אם המשתמש ביטל.
Future<MarkRangeSelection?> showMarkRangeDialog({
  required BuildContext context,
  required BookDetails bookDetails,
  required String columnLabel,
}) async {
  final items = bookDetails.learnableItems;
  if (items.isEmpty) return null;

  final draft = _RangeDraft(
    fromIndex: items.first.absoluteIndex,
    toIndex: items.last.absoluteIndex,
  );

  final confirmed = await showTwoActionsDialog(
    context: context,
    title: 'סימון טווח בעמודה "$columnLabel"',
    icon: FluentIcons.checkmark_circle_24_regular,
    headerBand: true,
    content: '',
    confirmText: 'החל',
    customContent: _MarkRangeForm(bookDetails: bookDetails, draft: draft),
  );

  if (confirmed != true) return null;
  return MarkRangeSelection(
    fromIndex: draft.fromIndex,
    toIndex: draft.toIndex,
    value: draft.value,
  );
}

/// הבחירה הנוכחית בטופס — משותפת בין הטופס לבין הפונקציה שפתחה אותו,
/// כי הדיאלוג הסטנדרטי מחזיר bool בלבד.
class _RangeDraft {
  int fromIndex;
  int toIndex;
  bool value = true;

  _RangeDraft({required this.fromIndex, required this.toIndex});
}

class _MarkRangeForm extends StatefulWidget {
  final BookDetails bookDetails;
  final _RangeDraft draft;

  const _MarkRangeForm({required this.bookDetails, required this.draft});

  @override
  State<_MarkRangeForm> createState() => _MarkRangeFormState();
}

class _MarkRangeFormState extends State<_MarkRangeForm> {
  late final List<AppMenuEntry<int>> _entries = widget
      .bookDetails
      .learnableItems
      .map(
        (item) => AppMenuEntry<int>(
          value: item.absoluteIndex,
          label: markRangeItemLabel(widget.bookDetails, item),
        ),
      )
      .toList();

  int get _count => (widget.draft.toIndex - widget.draft.fromIndex).abs() + 1;

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    return SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _picker(
                  'מ־',
                  draft.fromIndex,
                  (v) => draft.fromIndex = v,
                ),
              ),
              const SizedBox(width: AppTokens.spaceMD),
              Expanded(
                child: _picker('עד', draft.toIndex, (v) => draft.toIndex = v),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceMD),
          AppSegmentedControl<bool>(
            expandToFillWidth: true,
            currentValue: draft.value,
            options: const [
              SegmentOption(value: true, label: 'סמן'),
              SegmentOption(value: false, label: 'בטל סימון'),
            ],
            onChanged: (v) => setState(() => draft.value = v),
          ),
          const SizedBox(height: AppTokens.spaceMD),
          _summary(context),
        ],
      ),
    );
  }

  /// כמה פריטים ייגעו בפעולה, בתיבה בולטת מתחת לבחירה.
  Widget _summary(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final marking = widget.draft.value;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMD,
          vertical: AppTokens.spaceSM + 2,
        ),
        child: Row(
          children: [
            Icon(
              marking
                  ? FluentIcons.checkbox_checked_24_regular
                  : FluentIcons.checkbox_unchecked_24_regular,
              size: AppTokens.fontXL,
              color: cs.onSecondaryContainer,
            ),
            const SizedBox(width: AppTokens.spaceSM),
            Expanded(
              child: Text(
                marking
                    ? '$_count פריטים יסומנו'
                    : 'הסימון של $_count פריטים יבוטל',
                style: TextStyle(
                  fontSize: AppTokens.fontMD,
                  fontWeight: FontWeight.w600,
                  color: cs.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _picker(String label, int value, ValueChanged<int> onPicked) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: AppTokens.fontSM,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppTokens.spaceXS),
        AppDropdownField<int>(
          value: value,
          entries: _entries,
          enableSearch: true,
          onSelected: (v) {
            if (v == null) return;
            setState(() => onPicked(v));
          },
        ),
      ],
    );
  }
}
