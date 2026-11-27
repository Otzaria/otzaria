import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/shelf_description.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/widgets/misc/app_selection_area.dart';
import 'package:otzaria/widgets/feedback/app_scrollbar.dart';

/// מציג את כל פרטי הקטגוריה הזמינים.
Future<void> showCategoryDetailsDialog(
  BuildContext context,
  Category category,
) async {
  await showSingleActionDialog(
    context: context,
    title: 'תיאור המדף',
    icon: FluentIcons.folder_24_regular,
    size: AppDialogSize.medium,
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
    // פס גלילה קבוע: תיאור מורחב ארוך נחתך בתחתית הדיאלוג, ובלי פס אין סימן
    // שיש המשך.
    return SizedBox(
      width: 500,
      child: AppScrollbar(
        controller: _scroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _scroll,
          child: AppSelectionArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DetailsHeading(title: category.title),
                // הקצר (מודגש) והארוך ברצף, תחת כותרת אחת. כשזה כל התוכן אין
                // צורך בכותרת מקטע.
                if (categoryHasDescription(category)) ...[
                  const SizedBox(height: AppTokens.spaceMD),
                  ShelfDescription(category: category),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
