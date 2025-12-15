import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/services/sources_books_service.dart';
import 'package:otzaria/text_book/view/book_source_dialog.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math';
import 'dart:io';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';

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
                book is PdfBook
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(0, 0, 10, 0),
                        child: Icon(FluentIcons.document_pdf_24_regular,
                            color: Theme.of(context)
                                .colorScheme
                                .secondary
                                .withValues(alpha: 0.6)),
                      )
                    : book is ExternalBook
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(0, 0, 10, 0),
                            child: Image.asset(
                              (book as ExternalBook)
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
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(0, 0, 10, 0),
                            child: Icon(FluentIcons.document_text_24_regular,
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
                book.heShortDesc == null || book.heShortDesc == ''
                    ? const SizedBox.shrink()
                    : Tooltip(
                        richMessage: WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              constraints: const BoxConstraints(maxWidth: 250),
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
                          color: Theme.of(context)
                              .colorScheme
                              .secondary
                              .withValues(alpha: 0.6),
                        ),
                      ),
                // כפתור תפריט אפשרויות (3 נקודות)
                book is! ExternalBook
                    ? PopupMenuButton<String>(
                        icon: Icon(
                          FluentIcons.more_vertical_24_regular,
                          color: Theme.of(context)
                              .colorScheme
                              .secondary
                              .withValues(alpha: 0.6),
                        ),
                        tooltip: 'אפשרויות',
                        onSelected: (value) {
                          if (value == 'delete') {
                            _showDeleteBookDialog(context, book, onBookDeleted);
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
                                    style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MyGridView extends StatelessWidget {
  final Future<List<Widget>> items;

  const MyGridView({super.key, required this.items});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return FutureBuilder(
            future: items,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 45),
                  child: GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        //max number of items per row is 5 and min is 1
                        crossAxisCount:
                            max(1, min(constraints.maxWidth ~/ 250, 5)),
                        childAspectRatio: 2,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4),
                    itemCount: snapshot.data!.length,
                    itemBuilder: (context, index) => snapshot.data![index],
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                  ),
                );
              }
              return const Center(child: CircularProgressIndicator());
            });
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
    // בדיקה אם הספר נמצא ב-DB
    final dataSource =
        await FileSystemData.instance.getBookDataSource(book.title);

    if (dataSource == 'DB') {
      // מחיקה מ-DB
      await _deleteBookFromDatabase(book);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('הספר "${book.title}" נמחק בהצלחה ממסד הנתונים'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      // מחיקה של קובץ
      await _deleteBookFile(book);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('הספר "${book.title}" נמחק בהצלחה'),
            backgroundColor: Colors.green,
          ),
        );
      }
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

/// מחיקת ספר ממסד הנתונים
Future<void> _deleteBookFromDatabase(Book book) async {
  final repository = SqliteDataProvider.instance.repository;
  if (repository == null) {
    throw Exception('לא ניתן לגשת למסד הנתונים');
  }

  // חיפוש הספר לפי שם וקטגוריה
  final dbBook = await _findBookInDatabase(repository, book);
  if (dbBook == null) {
    throw Exception('הספר "${book.title}" לא נמצא במסד הנתונים');
  }

  // מחיקה מלאה של הספר
  await repository.deleteBookCompletely(dbBook.id);
}

/// חיפוש ספר במסד הנתונים לפי שם וקטגוריה
Future<dynamic> _findBookInDatabase(dynamic repository, Book book) async {
  // אם יש קטגוריה, נחפש לפי קטגוריה
  if (book.category != null) {
    // קודם ננסה למצוא את הקטגוריה ב-DB
    final categories = await repository.getRootCategories();
    int? categoryId = await _findCategoryIdByPath(
        repository, categories, book.category!.path);

    if (categoryId != null) {
      // חיפוש הספר בקטגוריה הספציפית
      final booksInCategory = await repository.getBooksByCategory(categoryId);
      for (final dbBook in booksInCategory) {
        if (dbBook.title == book.title) {
          return dbBook;
        }
      }
    }
  }

  // אם לא מצאנו לפי קטגוריה, נחפש לפי שם בלבד
  return await repository.getBookByTitle(book.title);
}

/// חיפוש ID של קטגוריה לפי נתיב
Future<int?> _findCategoryIdByPath(
    dynamic repository, List<dynamic> categories, String path) async {
  final pathParts = path.split('/');

  for (final category in categories) {
    if (category.title == pathParts.first) {
      if (pathParts.length == 1) {
        return category.id;
      }
      // חיפוש רקורסיבי בתת-קטגוריות
      final subCategories = await repository.getCategoryChildren(category.id);
      final remainingPath = pathParts.sublist(1).join('/');
      return await _findCategoryIdByPath(
          repository, subCategories, remainingPath);
    }
  }
  return null;
}

/// מחיקת קובץ ספר
Future<void> _deleteBookFile(Book book) async {
  String? filePath;

  if (book is PdfBook) {
    filePath = book.path;
  } else if (book is TextBook) {
    // עבור TextBook, נשתמש ב-titleToPath
    final titleToPath = await FileSystemData.instance.titleToPath;
    filePath = titleToPath[book.title];
  }

  if (filePath == null || filePath.isEmpty) {
    throw Exception('לא נמצא נתיב לקובץ הספר');
  }

  // בדיקה שהקובץ נמצא בתיקייה הנכונה (לפי קטגוריה)
  if (book.category != null) {
    final expectedPath = _buildExpectedPath(book.category!);
    if (!filePath.contains(expectedPath)) {
      throw Exception(
          'הקובץ "${book.title}" לא נמצא בתיקייה הצפויה: $expectedPath');
    }
  }

  final file = File(filePath);
  if (!await file.exists()) {
    throw Exception('קובץ הספר לא נמצא');
  }

  await file.delete();
}

/// בניית נתיב צפוי לפי קטגוריה
String _buildExpectedPath(Category category) {
  // בניית נתיב מהקטגוריה - למשל: "אוצריא/תנך/תורה"
  final pathParts = category.path.split('/');
  return pathParts.join(Platform.pathSeparator);
}
