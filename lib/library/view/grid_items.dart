import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/widgets/data_source_indicator.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/services/sources_books_service.dart';
import 'package:otzaria/text_book/view/book_source_dialog.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math';
import 'package:otzaria/data/book_locator.dart';

class HeaderItem extends StatelessWidget {
  final Category category;

  const HeaderItem({
    super.key,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Text(category.title,
          style: TextStyle(
            fontSize: 20,
            color: Theme.of(context).colorScheme.secondary,
          )),
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
    return Card(
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(12.0),
        hoverColor:
            Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1),
        hoverDuration: Durations.medium1,
        onTap: () => onCategoryClickCallback(),
        child: Align(
            alignment: Alignment.topRight,
            child: Row(
              children: [
                Expanded(
                  child: ListTile(
                    mouseCursor: SystemMouseCursors.click,
                    title: Text(
                      category.title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                category.shortDescription.isEmpty
                    ? const SizedBox.shrink()
                    : Tooltip(
                        richMessage: WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              constraints: const BoxConstraints(maxWidth: 250),
                              child: Text(
                                category.shortDescription,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimary),
                              ),
                            )),
                        child: IconButton(
                          mouseCursor: SystemMouseCursors.click,
                          onPressed: () {
                            _showCategoryInfoDialog(context, category);
                          },
                          icon: const Icon(FluentIcons.info_24_regular),
                          color: Theme.of(context)
                              .colorScheme
                              .secondary
                              .withValues(alpha: 0.6),
                        ),
                      )
              ],
            )),
      ),
    );
  }
}

class BookGridItem extends StatelessWidget {
  final bool showTopics;
  final Book book;
  final VoidCallback onBookClickCallback;
  final VoidCallback? onBookDeleted;

  const BookGridItem({
    super.key,
    required this.book,
    required this.onBookClickCallback,
    this.showTopics = false,
    this.onBookDeleted,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      child: Card(
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(12.0),
          hoverColor:
              Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1),
          onTap: () => onBookClickCallback(),
          hoverDuration: Durations.medium1,
          child: Align(
            alignment: Alignment.topRight,
            child: Row(
              children: [
                (book is PdfBook || book.fileType == 'pdf')
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(0, 0, 10, 0),
                        child: Icon(FluentIcons.document_pdf_24_regular,
                            color: Theme.of(context)
                                .colorScheme
                                .secondary
                                .withValues(alpha: 0.6)),
                      )
                    : book is ExternalLibraryBook
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(0, 0, 10, 0),
                            child: Image.asset(
                              (book as ExternalLibraryBook)
                                      .link
                                      .toString()
                                      .contains('tablet.otzar.org')
                                  ? 'assets/logos/otzar.ico'
                                  : 'assets/logos/hebrew_books.png',
                              width: 20,
                              height: 20,
                              fit: BoxFit.contain,
                            ),
                          )
                        : book.fileType == 'docx'
                            ? Padding(
                                padding: const EdgeInsets.fromLTRB(0, 0, 10, 0),
                                child: Icon(
                                    FluentIcons.document_one_page_24_regular,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .secondary
                                        .withValues(alpha: 0.6)),
                              )
                            : Padding(
                                padding: const EdgeInsets.fromLTRB(0, 0, 10, 0),
                                child: Icon(
                                    FluentIcons.document_text_24_regular,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .secondary
                                        .withValues(alpha: 0.6)),
                              ),
                Expanded(
                  child: ListTile(
                    mouseCursor: SystemMouseCursors.click,
                    title: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: book.title,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary),
                          ),
                          showTopics
                              ? TextSpan(
                                  text: '\n${book.topics}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.9)),
                                )
                              : const TextSpan()
                        ],
                      ),
                    ),
                    subtitle: Text(
                        (book.author == "" || book.author == null)
                            ? ''
                            : book.author!,
                        style: const TextStyle(fontSize: 13)),
                  ),
                ),
                // כפתורים מאונכים - מחולקים באופן שווה לאורך גובה הכרטיס
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      // Data source indicator (DB or File)
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: Center(
                          child: book is TextBook
                              ? DataSourceIndicatorAsync(
                                  sourceFuture: FileSystemData.instance
                                      .getBookDataSource(book.title,
                                          book.categoryPath, book.fileType),
                                  size: 18.0,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                      // כפתור מידע
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: (book.heShortDesc == null ||
                                book.heShortDesc == '')
                            ? const SizedBox.shrink()
                            : Tooltip(
                                richMessage: WidgetSpan(
                                    alignment: PlaceholderAlignment.baseline,
                                    baseline: TextBaseline.alphabetic,
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      constraints:
                                          const BoxConstraints(maxWidth: 250),
                                      child: Text(
                                        book.heShortDesc!,
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onPrimary),
                                      ),
                                    )),
                                child: IconButton(
                                  mouseCursor: SystemMouseCursors.click,
                                  onPressed: () {
                                    _showBookInfoDialog(context, book);
                                  },
                                  icon: const Icon(FluentIcons.info_24_regular),
                                  iconSize: 18,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .secondary
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                      ),
                      // כפתור תפריט אפשרויות (3 נקודות)
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: book is! ExternalLibraryBook
                            ? PopupMenuButton<String>(
                                icon: Icon(
                                  FluentIcons.more_vertical_24_regular,
                                  size: 18,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .secondary
                                      .withValues(alpha: 0.6),
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
                                    _showDeleteBookDialog(
                                        context, book, onBookDeleted);
                                  }
                                },
                                itemBuilder: (BuildContext context) => [
                                  const PopupMenuItem<String>(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(FluentIcons.delete_24_regular,
                                            color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('מחק ספר זה',
                                            style:
                                                TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 45),
          child: GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                //max number of items per row is 5 and min is 1
                crossAxisCount: max(1, min(constraints.maxWidth ~/ 250, 5)),
                childAspectRatio: 2,
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
                        const TextSpan(
                          text: 'מחבר: ',
                          style: TextStyle(fontWeight: FontWeight.bold),
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
                        const TextSpan(
                          text: 'קטגוריה: ',
                          style: TextStyle(fontWeight: FontWeight.bold),
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
                        const TextSpan(
                          text: 'תקופה: ',
                          style: TextStyle(fontWeight: FontWeight.bold),
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
                        const TextSpan(
                          text: 'חיבור: ',
                          style: TextStyle(fontWeight: FontWeight.bold),
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
                        const TextSpan(
                          text: 'הוצאה לאור: ',
                          style: TextStyle(fontWeight: FontWeight.bold),
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
                        const TextSpan(
                          text: 'שמות נוספים: ',
                          style: TextStyle(fontWeight: FontWeight.bold),
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
                        const TextSpan(
                          text: 'תיאור מקוצר על הספר: ',
                          style: TextStyle(fontWeight: FontWeight.bold),
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
                        const TextSpan(
                          text: 'תיאור הספר: ',
                          style: TextStyle(fontWeight: FontWeight.bold),
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
                        const TextSpan(
                          text: 'מקור הספר: ',
                          style: TextStyle(fontWeight: FontWeight.bold),
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
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.blue,
                                decoration: TextDecoration.underline,
                              ),
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
                        const TextSpan(
                          text: 'מקור הספר: ',
                          style: TextStyle(fontWeight: FontWeight.bold),
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
              text: const TextSpan(
                style: TextStyle(fontSize: 14, color: Colors.black87),
                children: [
                  TextSpan(
                    text: 'זכויות יוצרים: ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text: 'המידע יוגדר בהמשך',
                    style: TextStyle(fontStyle: FontStyle.italic),
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
    final bookDetails = SourcesBooksService().getBookDetails(book.title);
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
  showDialog(
    context: context,
    builder: (BuildContext context) {
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
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _deleteBook(context, book);
              onBookDeleted?.call();
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('כן, אני רוצה למחוק'),
          ),
        ],
      );
    },
  );
}

/// מחיקת ספר - מ-DB או מהקובץ
Future<void> _deleteBook(BuildContext context, Book book) async {
  try {
    // שימוש ב-BookLocator למחיקת הספר
    final success = await BookLocator.deleteBook(
      book.title,
      category: book.category,
    );

    if (!success) {
      throw Exception('המחיקה נכשלה');
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('הספר "${book.title}" נמחק בהצלחה'),
          backgroundColor: Colors.green,
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה במחיקת הספר: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
