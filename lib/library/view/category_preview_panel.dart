import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/models/books.dart';
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

    return GestureDetector(
      onDoubleTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox.square(
                  dimension: 32,
                  child: categoryIconChild(category, cs, 32),
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
                if (onOpen case final open?) ...[
                  const SizedBox(width: 12),
                  ActionButton.recommended(
                    text: 'פתח תיקייה',
                    icon: FluentIcons.folder_open_24_regular,
                    onPressed: open,
                  ),
                ],
              ],
            ),
            if (description != null) ...[
              const SizedBox(height: 16),
              Text(description, style: theme.textTheme.bodyMedium),
            ],
            if (counts != null) ...[
              const SizedBox(height: 16),
              Text(
                counts,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: subCategories.length + books.length,
                itemBuilder: (context, index) {
                  if (index < subCategories.length) {
                    return _ContentRow(
                      icon: categoryIconChild(subCategories[index], cs, 16),
                      title: subCategories[index].title,
                    );
                  }
                  final book = books[index - subCategories.length];
                  return _ContentRow(
                    icon: bookIconChild(
                      book,
                      cs,
                      16,
                      color: cs.onSurfaceVariant,
                    ),
                    title: book.title,
                    subtitle: book.author,
                  );
                },
              ),
            ),
          ],
        ),
      ),
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

class _ContentRow extends StatelessWidget {
  /// ווידג'ט ולא [IconData]: לוגו של ספרייה חיצונית הוא תמונה, לא גופן.
  final Widget icon;
  final String title;
  final String? subtitle;

  const _ContentRow({required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final author = subtitle?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox.square(dimension: 16, child: icon),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: title,
                children: [
                  if (author.isNotEmpty)
                    TextSpan(
                      text: '  $author',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
