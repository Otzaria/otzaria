import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/book_common/view/book_source_dialog.dart'
    show splitShortAndFullDescription;
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';

/// מציג את כל פרטי הקטגוריה הזמינים.
Future<void> showCategoryDetailsDialog(
  BuildContext context,
  Category category,
) async {
  await showSingleActionDialog(
    context: context,
    title: 'אודות הקטגוריה',
    icon: FluentIcons.folder_24_regular,
    headerBand: true,
    confirmText: 'סגור',
    customContent: _CategoryDetailsDialogContent(category: category),
  );
}

class _CategoryDetailsDialogContent extends StatefulWidget {
  const _CategoryDetailsDialogContent({required this.category});

  final Category category;

  @override
  State<_CategoryDetailsDialogContent> createState() =>
      _CategoryDetailsDialogContentState();
}

class _CategoryDetailsDialogContentState
    extends State<_CategoryDetailsDialogContent> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    final shortDescription = category.shortDescription.trim();
    // התיאור הקצר כבר בכותרת; כשהמורחב מתחיל בו, בכרטיס נשאר רק ההמשך.
    final split = splitShortAndFullDescription(
      shortDescription,
      category.description,
    );
    final fullDescription = split == null
        ? category.description.trim()
        : split.rest;

    // פס גלילה קבוע: תיאור מורחב ארוך נחתך בתחתית הדיאלוג, ובלי פס אין סימן
    // שיש המשך.
    return SizedBox(
      width: 500,
      child: RawScrollbar(
        controller: _scroll,
        thumbVisibility: true,
        thumbColor: Theme.of(context).colorScheme.outline,
        thickness: 6,
        radius: const Radius.circular(3),
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsetsDirectional.only(end: AppTokens.spaceMD),
          child: AppSelectionArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DetailsHeading(
                  title: category.title,
                  subtitle: shortDescription,
                ),
                if (fullDescription.isNotEmpty) ...[
                  const SizedBox(height: AppTokens.spaceMD),
                  DetailsCard(
                    title: 'תיאור',
                    icon: FluentIcons.document_text_24_regular,
                    children: [DetailsText(fullDescription)],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
