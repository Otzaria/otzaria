import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'dart:math';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/book_locator.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/widgets/layout/app_card.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  הנחיות עיצוב:
//  • מבנה Row: RTL כדי אייקונים משמאל, טקסט מימין (מתאים ל-RTL UI).
//  • צבעי טקסט: cs.onSurface בכותרת ותיאור (במקום אדום/כחול), cs.primary בהדגשות.
//  • רקע אייקונים: cs.primary/secondary.withValues(alpha:0.12) או מבנה אדום+כחול.
//  • אייקונים מעוצבים: 32×32 container, 16px icon או קונטיינר רחוק שיותר.
//  • ריווח עליון ב-MyGridView: top: 8 או מרווח מתאים.
//  • Focus מוגדר במפורש: CategoryGridItem + BookGridItem תומכים ב-Focus.
//  • overflow: ellipsis + tooltip במרווח מספיק.
// ─────────────────────────────────────────────────────────────────────────────

bool _textOverflows({
  required BuildContext context,
  required String text,
  required TextStyle style,
  required int maxLines,
  required double maxWidth,
  required TextDirection textDirection,
  required TextAlign textAlign,
}) {
  final textPainter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: maxLines,
    ellipsis: 'Γאª',
    textDirection: textDirection,
    textAlign: textAlign,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: maxWidth);

  return textPainter.didExceedMaxLines;
}

Decoration _libraryTooltipDecoration(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: cs.surfaceContainerHigh,
    borderRadius: BorderRadius.circular(12),
  );
}

TextStyle _libraryTooltipTextStyle(BuildContext context) {
  final theme = Theme.of(context);
  return (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
    color: theme.colorScheme.onSurface,
    fontSize: 14,
    height: 1.3,
  );
}

class LibraryOverflowTooltipText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextAlign textAlign;
  final TextDirection? textDirection;

  const LibraryOverflowTooltipText({
    super.key,
    required this.text,
    this.style,
    this.maxLines = 2,
    this.textAlign = TextAlign.right,
    this.textDirection,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedStyle = style ?? DefaultTextStyle.of(context).style;
    final resolvedDirection = textDirection ?? Directionality.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasOverflow = constraints.maxWidth.isFinite &&
            constraints.maxWidth > 0 &&
            _textOverflows(
              context: context,
              text: text,
              style: resolvedStyle,
              maxLines: maxLines,
              maxWidth: constraints.maxWidth,
              textDirection: resolvedDirection,
              textAlign: textAlign,
            );

        final child = Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          textDirection: resolvedDirection,
          style: resolvedStyle,
        );

        if (!hasOverflow) {
          return child;
        }

        return Tooltip(
          message: text,
          waitDuration: const Duration(milliseconds: 300),
          preferBelow: false,
          verticalOffset: 18,
          textAlign: TextAlign.right,
          textStyle: _libraryTooltipTextStyle(context),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          margin: const EdgeInsets.all(12),
          constraints: const BoxConstraints(maxWidth: 260),
          decoration: _libraryTooltipDecoration(context),
          child: child,
        );
      },
    );
  }
}

class LibraryItemTitle extends StatelessWidget {
  final String text;
  final bool isFolder;
  final int maxLines;

  const LibraryItemTitle({
    super.key,
    required this.text,
    required this.isFolder,
    this.maxLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LibraryOverflowTooltipText(
      text: text,
      maxLines: maxLines,
      textAlign: TextAlign.right,
      textDirection: TextDirection.rtl,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: isFolder ? FontWeight.w700 : FontWeight.w600,
        color:
            theme.textTheme.titleMedium?.color ?? theme.colorScheme.onSurface,
      ),
    );
  }
}

class HeaderItem extends StatelessWidget {
  final Category category;

  const HeaderItem({
    super.key,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Text(
        category.title,
        textDirection: TextDirection.rtl,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.secondary,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CategoryGridItem
//  Layout RTL: [info-icon?] [folder-icon] [12px] [Expanded text (right-aligned)]
//  במצב RTL: טקסט מימין, אייקונים משמאל כדי לשמור ויזואלית תקינה.
// ─────────────────────────────────────────────────────────────────────────────

class CategoryGridItem extends StatelessWidget {
  final Category category;
  final VoidCallback onCategoryClickCallback;
  final FocusNode? focusNode;

  const CategoryGridItem({
    super.key,
    required this.category,
    required this.onCategoryClickCallback,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AppCard(
      onTap: onCategoryClickCallback,
      focusNode: focusNode,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          // שומר על סדר אייקונים משמאל וטקסט מימין בתוך ממשק RTL.
          textDirection: TextDirection.rtl,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  LibraryItemTitle(
                    text: category.title,
                    isFolder: true,
                  ),
                  if (category.shortDescription.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    LibraryOverflowTooltipText(
                      text: category.shortDescription,
                      maxLines: 2,
                      textAlign: TextAlign.right,
                      textDirection: TextDirection.rtl,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSecondaryContainer,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 18),
            if (category.shortDescription.isNotEmpty)
              Tooltip(
                message: category.shortDescription,
                waitDuration: const Duration(milliseconds: 400),
                child: Icon(
                  FluentIcons.info_24_regular,
                  size: 16,
                  color: theme.colorScheme.onSecondaryContainer
                      .withValues(alpha: 0.6),
                ),
              ),
            const SizedBox(width: 4),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                FluentIcons.folder_24_regular,
                color: cs.onSecondaryContainer,
                size: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BookGridItem
//  Layout RTL: [action-col] [media-col] [12px] [Expanded text (right-aligned)]
//  במצב RTL: טקסט מימין, אייקונים משמאל כדי לשמור ויזואלית תקינה.
// ─────────────────────────────────────────────────────────────────────────────

class BookGridItem extends StatelessWidget {
  final bool showTopics;
  final bool isSelected;
  final Book book;
  final VoidCallback onBookClickCallback;
  final VoidCallback? onBookDeleted;
  final FocusNode? focusNode;

  const BookGridItem({
    super.key,
    required this.book,
    required this.onBookClickCallback,
    this.showTopics = false,
    this.isSelected = false,
    this.onBookDeleted,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onBookClickCallback,
      focusNode: focusNode,
      selected: isSelected,
      child: SizedBox.expand(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              Expanded(
                child: _BookGridTextColumn(
                  book: book,
                  showTopics: showTopics,
                ),
              ),
              const SizedBox(width: 18),
              SizedBox(
                width: 32,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    _BookGridMediaColumn(
                      book: book,
                      showTopics: showTopics,
                    ),
                    _BookGridActionColumn(
                      book: book,
                      onBookDeleted: onBookDeleted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookGridMediaColumn extends StatelessWidget {
  final Book book;
  final bool showTopics;

  const _BookGridMediaColumn({
    required this.book,
    required this.showTopics,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // אייקונים מעוצבים: 32×32 container, 16px icon או קונטיינר רחוק שיותר
    const double iconBoxSize = 32.0;
    const double iconSize = 16.0;

    final iconContainer = Container(
      width: iconBoxSize,
      height: iconBoxSize,
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: (book is PdfBook || book.fileType == 'pdf')
            ? Icon(
                FluentIcons.document_pdf_24_regular,
                color: cs.onSecondaryContainer,
                size: iconSize,
              )
            : book is ExternalLibraryBook
                ? Image.asset(
                    (book as ExternalLibraryBook)
                            .link
                            .toString()
                            .contains('tablet.otzar.org')
                        ? 'assets/logos/otzar.ico'
                        : 'assets/logos/hebrew_books.png',
                    width: iconSize,
                    height: iconSize,
                    fit: BoxFit.contain,
                  )
                : Icon(
                    book.fileType == 'docx'
                        ? FluentIcons.document_one_page_24_regular
                        : FluentIcons.document_text_24_regular,
                    color: cs.onSecondaryContainer,
                    size: iconSize,
                  ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        book.isUserBook
            ? Tooltip(
                message: 'ספר אישי',
                waitDuration: const Duration(milliseconds: 400),
                child: SizedBox(
                  width: iconBoxSize,
                  height: iconBoxSize,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      iconContainer,
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: cs.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppSurfaces.card(context),
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            FluentIcons.person_24_regular,
                            size: 8,
                            color: cs.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : iconContainer,
      ],
    );
  }
}

class _BookGridTextColumn extends StatelessWidget {
  final Book book;
  final bool showTopics;

  const _BookGridTextColumn({
    required this.book,
    required this.showTopics,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // כותרת: onSurface כדי מבנה מאוחד ומסודר (ולא primary שיכול להיות מדי בולט)
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurface,
    );
    final authorStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSecondaryContainer,
    );
    final topicsStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.secondary.withValues(alpha: 0.85),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final titleOverflow = titleStyle != null &&
            constraints.maxWidth.isFinite &&
            constraints.maxWidth > 0 &&
            _textOverflows(
              context: context,
              text: book.title,
              style: titleStyle,
              maxLines: 2,
              maxWidth: constraints.maxWidth,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
            );

        final authorMaxLines = titleOverflow ? 1 : 2;
        final hasAuthor = (book.author ?? '').isNotEmpty;
        final hasTopics = showTopics && book.topics.trim().isNotEmpty;
        final topicsMaxLines = !hasTopics
            ? 0
            : constraints.maxHeight < 110
                ? 1
                : constraints.maxHeight < 140 || hasAuthor || titleOverflow
                    ? 2
                    : 3;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.max,
          children: [
            LibraryOverflowTooltipText(
              text: book.title,
              maxLines: 2,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: titleStyle,
            ),
            if (hasAuthor) ...[
              const SizedBox(height: 3),
              LibraryOverflowTooltipText(
                text: book.author!,
                maxLines: authorMaxLines,
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
                style: authorStyle,
              ),
            ],
            if (hasTopics) ...[
              const Spacer(),
              LibraryOverflowTooltipText(
                text: book.topics,
                maxLines: topicsMaxLines,
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
                style: topicsStyle,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _BookGridActionColumn extends StatelessWidget {
  final Book book;
  final VoidCallback? onBookDeleted;

  const _BookGridActionColumn({
    required this.book,
    required this.onBookDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FutureBuilder<bool>(
          future: _canDeleteBookFromLibrary(book),
          builder: (context, snapshot) {
            // מחיקה מהספרייה מותרת רק לספרי משתמש מסוג "עותק עצמאי"
            // (התוכן שמור בתוכנה). ספר "קריאה מהקבצים" נמחק רק ע"י מחיקת
            // הקובץ מהדיסק, והספרייה הרשמית (seforim.db) אינה ניתנת למחיקה.
            if (snapshot.data != true) {
              return const SizedBox.shrink();
            }

            return SizedBox(
              width: 28,
              height: 28,
              child: AppPopupMenuButton<String>(
                icon: Icon(
                  FluentIcons.more_vertical_24_regular,
                  size: 15,
                  color: theme.colorScheme.secondary,
                ),
                tooltip: 'אפשרויות נוספות',
                position: PopupMenuPosition.under,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                onSelected: (value) {
                  if (value == 'delete') {
                    _showDeleteBookDialog(context, book, onBookDeleted);
                  }
                },
                entries: const [
                  AppMenuEntry<String>(
                    value: 'delete',
                    label: 'מחק מהספרייה',
                    icon: FluentIcons.delete_24_regular,
                    isDestructive: true,
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  MyGridView
//  • ריווח top: 8 או מרווח מתאים
//  • FocusTraversalGroup כדי לנווט Tab בסדר קריאה (ולא קפיצה ציגזג)
// ─────────────────────────────────────────────────────────────────────────────

class MyGridView extends StatelessWidget {
  final List<Widget> items;

  const MyGridView({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        final width = constraints.maxWidth;
        final baseRatio = width >= 1400
            ? 2.1
            : width >= 1100
                ? 1.95
                : width >= 800
                    ? 1.8
                    : 1.65;
        final textAdjustment =
            textScale <= 1.0 ? 1.0 : (1.0 / (1.0 + ((textScale - 1.0) * 0.65)));
        final childAspectRatio = (baseRatio * textAdjustment).clamp(1.45, 2.15);

        return FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: Padding(
            // top: 8 או מרווח מתאים; horizontal: 45 או רוחב אף
            padding:
                const EdgeInsets.only(top: 8, left: 45, right: 45, bottom: 0),
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: max(1, min(constraints.maxWidth ~/ 250, 5)),
                childAspectRatio: childAspectRatio,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) => items[index],
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
            ),
          ),
        );
      },
    );
  }
}

/// בודק האם ניתן למחוק את [book] דרך הספרייה.
///
/// מותר רק לספרי משתמש מסוג "עותק עצמאי" (התוכן שמור בתוכנה). ספר
/// "קריאה מהקבצים" (file-backed) נמחק רק ע"י מחיקת הקובץ מהדיסק, והספרייה
/// הרשמית אינה ניתנת למחיקה ע"י המשתמש.
Future<bool> _canDeleteBookFromLibrary(Book book) {
  return FileSystemData.instance.canDeleteUserBookFromLibrary(
    title: book.title,
    categoryId: book.categoryId,
    fileType: book.fileType ?? 'txt',
    isUserBook: book.isUserBook,
  );
}

Future<void> _showDeleteBookDialog(
    BuildContext context, Book book, VoidCallback? onBookDeleted) async {
  final confirmed = await showWarningDialog(
    context: context,
    title: 'למחוק את הספר?',
    content: 'הספר "${book.title}" יימחק מהספרייה.',
    subtitle: 'לא ניתן לשחזר ספר שנמחק.',
    cancelText: 'ביטול',
    confirmText: 'מחק',
  );

  if (confirmed != true) {
    return;
  }

  await _deleteBook(book);
  onBookDeleted?.call();
}

Future<void> _deleteBook(Book book) async {
  try {
    final success = await BookLocator.deleteBook(
      book.title,
      category: book.category,
      categoryId: book.categoryId,
    );

    if (!success) {
      throw Exception('המחיקה נכשלה');
    }

    UiSnack.show('הספר "${book.title}" נמחק מהספרייה');
  } catch (e) {
    UiSnack.showError('שגיאה במחיקת הספר: $e');
  }
}
