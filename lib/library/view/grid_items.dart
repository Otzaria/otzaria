import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/widgets/data_source_indicator.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/services/book_details_service.dart';
import 'package:otzaria/text_book/view/book_source_dialog.dart';
import 'package:otzaria/widgets/app_menu.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/book_locator.dart';

TextStyle? _boldBodyStyle(BuildContext context) {
  return Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
      );
}

TextStyle? _linkBodyStyle(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.bodyMedium?.copyWith(
    color: theme.colorScheme.primary,
    decoration: TextDecoration.underline,
  );
}

TextStyle? _mutedBodyStyle(BuildContext context) {
  return Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
      );
}

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
    ellipsis: '…',
    textDirection: textDirection,
    textAlign: textAlign,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: maxWidth);

  return textPainter.didExceedMaxLines;
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
        fontWeight: isFolder ? FontWeight.w700 : FontWeight.w500,
        color:
            isFolder ? theme.colorScheme.primary : theme.colorScheme.onSurface,
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

class CategoryGridItem extends StatelessWidget {
  final Category category;
  final VoidCallback onCategoryClickCallback;

  const CategoryGridItem({
    super.key,
    required this.category,
    required this.onCategoryClickCallback,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.18),
        ),
      ),
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(14.0),
        hoverColor: theme.colorScheme.primary.withValues(alpha: 0.08),
        hoverDuration: Durations.medium1,
        onTap: () => onCategoryClickCallback(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer
                      .withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  FluentIcons.folder_24_filled,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LibraryItemTitle(
                      text: category.title,
                      isFolder: true,
                    ),
                    if (category.shortDescription.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      LibraryOverflowTooltipText(
                        text: category.shortDescription,
                        maxLines: 2,
                        textAlign: TextAlign.right,
                        textDirection: TextDirection.rtl,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (category.shortDescription.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    mouseCursor: SystemMouseCursors.basic,
                    onPressed: null,
                    icon: const Icon(FluentIcons.info_24_regular),
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.6),
                    disabledColor: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class BookGridItem extends StatelessWidget {
  final bool showTopics;
  final Book book;
  final VoidCallback onBookClickCallback;
  final VoidCallback? onBookDeleted;
  final FocusNode? focusNode;

  const BookGridItem({
    super.key,
    required this.book,
    required this.onBookClickCallback,
    this.showTopics = false,
    this.onBookDeleted,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: book is ExternalLibraryBook
                ? theme.colorScheme.secondary.withValues(alpha: 0.2)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.9),
          ),
        ),
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          focusNode: focusNode,
          borderRadius: BorderRadius.circular(14.0),
          hoverColor: theme.colorScheme.secondary.withValues(alpha: 0.08),
          onTap: () => onBookClickCallback(),
          hoverDuration: Durations.medium1,
          child: SizedBox.expand(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                textDirection: TextDirection.rtl,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BookGridMediaColumn(book: book, showTopics: showTopics),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _BookGridTextColumn(
                      book: book,
                      showTopics: showTopics,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _BookGridActionColumn(
                    book: book,
                    onBookDeleted: onBookDeleted,
                  ),
                ],
              ),
            ),
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
    final iconBoxSize = showTopics ? 32.0 : 40.0;
    final iconSize = showTopics ? 18.0 : 20.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: iconBoxSize,
          height: iconBoxSize,
          decoration: BoxDecoration(
            color: book is ExternalLibraryBook
                ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.55)
                : theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: (book is PdfBook || book.fileType == 'pdf')
                ? Icon(
                    FluentIcons.document_pdf_24_regular,
                    color: theme.colorScheme.secondary,
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
                        color: theme.colorScheme.secondary,
                        size: iconSize,
                      ),
          ),
        ),
        if (kDebugMode && book is TextBook) ...[
          const SizedBox(height: 7),
          Transform.translate(
            offset: const Offset(0, 2),
            child: DataSourceIndicatorAsync(
              sourceFuture: FileSystemData.instance.getBookDataSource(
                book.title,
                categoryId: book.categoryId,
                fileType: book.fileType,
              ),
              size: 16,
            ),
          ),
        ],
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
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.primary,
    );
    final authorStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final topicsStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.primary.withValues(alpha: 0.85),
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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
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
              const SizedBox(height: 4),
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
                maxLines: 1,
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
        if ((book.heShortDesc ?? '').isNotEmpty)
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              mouseCursor: SystemMouseCursors.basic,
              onPressed: null,
              icon: const Icon(FluentIcons.info_24_regular),
              iconSize: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              disabledColor:
                  theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        if (book.categoryPath?.startsWith('ספרים אישיים') == true)
          SizedBox(
            width: 32,
            height: 32,
            child: AppPopupMenuButton<String>(
              icon: Icon(
                FluentIcons.more_vertical_24_regular,
                size: 18,
                color: theme.colorScheme.secondary,
              ),
              tooltip: 'אפשרויות',
              position: PopupMenuPosition.under,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              onSelected: (value) {
                if (value == 'delete') {
                  _showDeleteBookDialog(context, book, onBookDeleted);
                }
              },
              entries: const [
                AppMenuEntry<String>(
                  value: 'delete',
                  label: 'מחק ספר זה',
                  icon: FluentIcons.delete_24_regular,
                  isDestructive: true,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

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

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 45),
          child: GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                //max number of items per row is 5 and min is 1
                crossAxisCount: max(1, min(constraints.maxWidth ~/ 250, 5)),
                childAspectRatio: childAspectRatio,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4),
            itemCount: items.length,
            itemBuilder: (context, index) => items[index],
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
          ),
        );
      },
    );
  }
}

/// הצגת חלון מידע עבור ספר
// ignore: unused_element
void _showBookInfoDialog(BuildContext context, Book book) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(
          book.title,
          textAlign: TextAlign.right,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1) מחבר
              if (book.author != null && book.author!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: RichText(
                    textAlign: TextAlign.right,
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: 'מחבר: ',
                          style: _boldBodyStyle(context),
                        ),
                        TextSpan(text: book.author),
                      ],
                    ),
                  ),
                ),
              // 2) קטגוריה
              if (book.heCategories != null && book.heCategories!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: RichText(
                    textAlign: TextAlign.right,
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: 'קטגוריה: ',
                          style: _boldBodyStyle(context),
                        ),
                        TextSpan(text: book.heCategories),
                      ],
                    ),
                  ),
                ),
              // 3) תקופה
              if (book.heEra != null && book.heEra!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: RichText(
                    textAlign: TextAlign.right,
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: 'תקופה: ',
                          style: _boldBodyStyle(context),
                        ),
                        TextSpan(text: book.heEra),
                      ],
                    ),
                  ),
                ),
              // 4) תאריך ומקום חיבור
              if ((book.compDateStringHe != null &&
                      book.compDateStringHe!.isNotEmpty) ||
                  (book.compPlaceStringHe != null &&
                      book.compPlaceStringHe!.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: RichText(
                    textAlign: TextAlign.right,
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: 'חיבור: ',
                          style: _boldBodyStyle(context),
                        ),
                        TextSpan(
                          text: [
                            if (book.compPlaceStringHe != null &&
                                book.compPlaceStringHe!.isNotEmpty)
                              book.compPlaceStringHe,
                            if (book.compDateStringHe != null &&
                                book.compDateStringHe!.isNotEmpty)
                              book.compDateStringHe,
                          ].where((s) => s != null && s.isNotEmpty).join(', '),
                        ),
                      ],
                    ),
                  ),
                ),
              // 5) תאריך ומקום הוצאה לאור
              if ((book.pubDateStringHe != null &&
                      book.pubDateStringHe!.isNotEmpty) ||
                  (book.pubPlaceStringHe != null &&
                      book.pubPlaceStringHe!.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: RichText(
                    textAlign: TextAlign.right,
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: 'הוצאה לאור: ',
                          style: _boldBodyStyle(context),
                        ),
                        TextSpan(
                          text: [
                            if (book.pubPlaceStringHe != null &&
                                book.pubPlaceStringHe!.isNotEmpty)
                              book.pubPlaceStringHe,
                            if (book.pubDateStringHe != null &&
                                book.pubDateStringHe!.isNotEmpty)
                              book.pubDateStringHe,
                          ].where((s) => s != null && s.isNotEmpty).join(', '),
                        ),
                      ],
                    ),
                  ),
                ),
              // 6) שמות נוספים
              if (book.extraTitles != null && book.extraTitles!.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: RichText(
                    textAlign: TextAlign.right,
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: 'שמות נוספים: ',
                          style: _boldBodyStyle(context),
                        ),
                        TextSpan(
                          text: book.extraTitles!
                              .where((title) => title != book.title)
                              .join(', '),
                        ),
                      ],
                    ),
                  ),
                ),
              // 7) תיאור מקוצר
              if (book.heShortDesc != null && book.heShortDesc!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                  child: RichText(
                    textAlign: TextAlign.right,
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: 'תיאור מקוצר על הספר: ',
                          style: _boldBodyStyle(context),
                        ),
                        TextSpan(text: book.heShortDesc),
                      ],
                    ),
                  ),
                ),
              // 8) תיאור מלא
              if (book.heDesc != null && book.heDesc!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                  child: RichText(
                    textAlign: TextAlign.right,
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: 'תיאור הספר: ',
                          style: _boldBodyStyle(context),
                        ),
                        TextSpan(text: book.heDesc),
                      ],
                    ),
                  ),
                ),
              // 9) מקור הספר + זכויות יוצרים
              _buildBookSourceSection(book),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('סגור'),
          ),
        ],
      );
    },
  );
}

/// בניית סקציית מקור הספר וזכויות יוצרים
Widget _buildBookSourceSection(Book book) {
  return FutureBuilder<Map<String, dynamic>>(
    future: _getBookSourceInfo(book),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const SizedBox.shrink();
      }

      final sourceInfo = snapshot.data!;
      final displayInfo = sourceInfo['displayInfo'] as Map<String, String>;
      final displayText = displayInfo['text']!;
      final url = displayInfo['url']!;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: url.isNotEmpty
                ? RichText(
                    textAlign: TextAlign.right,
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: 'מקור הספר: ',
                          style: _boldBodyStyle(context),
                        ),
                        WidgetSpan(
                          child: InkWell(
                            onTap: () async {
                              final uri = Uri.parse(url);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri);
                              }
                            },
                            child: Text(
                              displayText,
                              style: _linkBodyStyle(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : RichText(
                    textAlign: TextAlign.right,
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: 'מקור הספר: ',
                          style: _boldBodyStyle(context),
                        ),
                        TextSpan(text: displayText),
                      ],
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: RichText(
              textAlign: TextAlign.right,
              text: TextSpan(
                style: _mutedBodyStyle(context),
                children: [
                  TextSpan(
                    text: 'זכויות יוצרים: ',
                    style: _boldBodyStyle(context),
                  ),
                  TextSpan(
                    text: 'המידע יוגדר בהמשך',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// קבלת מידע על מקור הספר
Future<Map<String, dynamic>> _getBookSourceInfo(Book book) async {
  try {
    final bookDetails = await BookDetailsService().getBookDetails(book);
    final bookSource = bookDetails['תיקיית המקור'] ?? 'לא נמצא מקור';
    final displayInfo = getSourceDisplayInfo(bookSource);

    return {
      'source': bookSource,
      'displayInfo': displayInfo,
    };
  } catch (e) {
    return {
      'source': 'לא נמצא מקור',
      'displayInfo': {'text': 'לא נמצא מקור', 'url': ''},
    };
  }
}

/// הצגת חלון מידע עבור קטגוריה
// ignore: unused_element
void _showCategoryInfoDialog(BuildContext context, Category category) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(
          category.title,
          textAlign: TextAlign.right,
        ),
        content: SingleChildScrollView(
          child: Text(
            category.shortDescription,
            textAlign: TextAlign.right,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('סגור'),
          ),
        ],
      );
    },
  );
}

/// הצגת דיאלוג אישור למחיקת ספר
void _showDeleteBookDialog(
    BuildContext context, Book book, VoidCallback? onBookDeleted) {
  final errorColor = Theme.of(context).colorScheme.error;
  showDialog(
    context: context,
    // שימוש ב-dialogContext נפרד כדי לא להסתיר את ה-context החיצוני
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: const Text(
          'מחיקת ספר',
          textAlign: TextAlign.right,
        ),
        content: Text(
          'האם אתה בטוח שאתה רוצה למחוק את הספר "${book.title}"?\nלא ניתן לשחזר פעולה זו!',
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              // שימוש ב-context החיצוני (לא context הדיאלוג שכבר הוסר)
              await _deleteBook(book);
              onBookDeleted?.call();
            },
            style: TextButton.styleFrom(
              foregroundColor: errorColor,
            ),
            child: const Text('כן, אני רוצה למחוק'),
          ),
        ],
      );
    },
  );
}

/// מחיקת ספר - מ-DB או מהקובץ
Future<void> _deleteBook(Book book) async {
  try {
    // שימוש ב-BookLocator למחיקת הספר
    final success = await BookLocator.deleteBook(
      book.title,
      category: book.category,
    );

    if (!success) {
      throw Exception('המחיקה נכשלה');
    }

    UiSnack.show('הספר "${book.title}" נמחק בהצלחה');
  } catch (e) {
    UiSnack.showError('שגיאה במחיקת הספר: $e');
  }
}
