import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/utils/ui/book_format_icon.dart';
import 'package:otzaria/widgets/lists/nav_tree_tile.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// תצוגה מקדימה של תיקייה בספרייה: שם, נתיב, תיאור (אם קיים), מונים ורשימת
/// התוכן לקריאה בלבד — הניווט עצמו נשאר בספרייה.
class CategoryPreviewPanel extends StatelessWidget {
  final Category category;

  /// נתיב התיקיות שמעל, מוצג מתחת לשם. ריק = לא מוצג.
  final String parentPath;

  /// תתי-התיקיות והספרים, מסוננים וממוינים כפי שיוצגו בכניסה לתיקייה.
  final List<Category> subCategories;
  final List<Book> books;

  /// null = התיקייה כבר פתוחה בספרייה, ואין לאן להיכנס.
  final VoidCallback? onOpen;

  const CategoryPreviewPanel({
    super.key,
    required this.category,
    required this.parentPath,
    required this.subCategories,
    required this.books,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final description = categoryInfoText(category);
    final counts = categoryContentCountsText(
      subCategories: subCategories.length,
      books: books.length,
    );

    final itemCount = subCategories.length + books.length;
    const headerInset = EdgeInsets.symmetric(
      horizontal: kNavTreeSideInset,
    );

    return GestureDetector(
      onDoubleTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          24 - kNavTreeSideInset,
          20,
          24 - kNavTreeSideInset,
          12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: headerInset,
              child: _header(theme, cs),
            ),
            if (description != null) ...[
              const SizedBox(height: 16),
              Padding(
                padding: headerInset,
                child: Text(description, style: theme.textTheme.bodyMedium),
              ),
            ],
            if (counts != null) ...[
              const SizedBox(height: 16),
              Padding(
                padding: headerInset,
                child: Text(
                  counts,
                  style: AppTextStyles.settingTitle.copyWith(
                    fontSize: AppTokens.fontMD,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: itemCount,
                itemBuilder: (context, index) => NavTreeGroupCard(
                  isGroupStart: index == 0,
                  isGroupEnd: index == itemCount - 1,
                  child: _contentRow(index),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contentRow(int index) {
    if (index < subCategories.length) {
      return NavTreeTile(
        title: subCategories[index].title,
        level: 0,
        fontWeight: FontWeight.w600,
      );
    }
    final book = books[index - subCategories.length];
    return NavTreeTile(
      title: book.title,
      subtitle: book.author?.trim(),
      level: 0,
      icon: bookFormatIcon(book),
      useFolderIcon: false,
      fontWeight: FontWeight.w500,
    );
  }

  Widget _header(ThemeData theme, ColorScheme cs) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackAction =
            constraints.maxWidth < MediaQuery.textScalerOf(context).scale(300);
        final action = onOpen == null
            ? null
            : ActionButton.recommended(
                text: 'פתח תיקייה',
                icon: FluentIcons.folder_open_24_regular,
                onPressed: onOpen,
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer,
                    borderRadius: AppTokens.borderRadiusAll,
                  ),
                  child: Icon(
                    FluentIcons.folder_24_regular,
                    size: 24,
                    color: cs.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        category.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (parentPath.isNotEmpty)
                        Text(
                          parentPath,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.secondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (action != null && !stackAction) ...[
                  const SizedBox(width: 12),
                  action,
                ],
              ],
            ),
            if (action != null && stackAction) ...[
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: action,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// שורת המונים של התיקייה, או null כשהיא ריקה.
@visibleForTesting
String? categoryContentCountsText({
  required int subCategories,
  required int books,
}) {
  final parts = [
    if (subCategories == 1) 'תיקייה אחת',
    if (subCategories > 1) '$subCategories תיקיות',
    if (books == 1) 'ספר אחד',
    if (books > 1) '$books ספרים',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}
