import 'package:flutter/material.dart';
import 'package:otzaria/core/messages/messages_exports.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/services/category_commentators_service.dart';
import 'package:otzaria/book_common/utils/category_settings_utils.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

/// דיאלוג "מפרשים קבועים לקטגוריה" (issue #866): קובע את בחירת המפרשים
/// הנוכחית כברירת המחדל לכל ספרי הקטגוריה שנבחרה, או מסיר קביעה קיימת.
///
/// [onSaved] נקרא אחרי שמירה מוצלחת — אתרי הקריאה מנקים בו את הבחירה
/// הפר-ספרית של הספר הנוכחי, כדי שהקביעה תחול גם עליו בעתיד.
Future<void> showCategoryCommentatorsDialog({
  required BuildContext context,
  required String bookTitle,
  required String? heCategories,
  required List<String> selectedCommentators,
  VoidCallback? onSaved,
}) async {
  final categories = parseBookCategories(heCategories);
  if (categories.isEmpty) return;

  var selectedCategory =
      CategoryCommentatorsService.getActiveCategory(heCategories) ??
      categories.first;
  var removed = false;

  final confirmed = await showTwoActionsDialog(
    context: context,
    title: 'מפרשים קבועים לקטגוריה',
    content: '',
    confirmText: 'קבע',
    customContent: StatefulBuilder(
      builder: (context, setState) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selectedCommentators.isEmpty
                  ? 'לא נבחרו מפרשים — בספרי הקטגוריה לא ייפתחו מפרשים אוטומטית.'
                  : 'המפרשים הנבחרים (${selectedCommentators.length}) ייפתחו אוטומטית בכל ספרי הקטגוריה.',
            ),
            const SizedBox(height: 16),
            if (categories.length > 1)
              AppDropdownField<String>(
                value: selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'בחר קטגוריה',
                  border: OutlineInputBorder(),
                ),
                entries: categories
                    .map(
                      (category) => AppMenuEntry<String>(
                        value: category,
                        label: category,
                      ),
                    )
                    .toList(),
                onSelected: (value) {
                  if (value != null) {
                    setState(() => selectedCategory = value);
                  }
                },
              )
            else
              Text(
                'קטגוריה: $selectedCategory',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            if (CategoryCommentatorsService.hasCategorySettings(
              selectedCategory,
            )) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ActionButton.warning(
                  text: 'הסר קביעה קיימת',
                  onPressed: () async {
                    removed = true;
                    final category = selectedCategory;
                    Navigator.of(context).pop(false);
                    await CategoryCommentatorsService.reset(category);
                    UiSnack.show(
                      TextBookMessages.categoryCommentatorsCleared(category),
                    );
                  },
                ),
              ),
            ],
          ],
        );
      },
    ),
  );

  if (removed || confirmed != true) return;

  await CategoryCommentatorsService.save(
    selectedCategory,
    selectedCommentators,
    bookTitle: bookTitle,
  );
  UiSnack.show(TextBookMessages.categoryCommentatorsSaved(selectedCategory));
  onSaved?.call();
}
