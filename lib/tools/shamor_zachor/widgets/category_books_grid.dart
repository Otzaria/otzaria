import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import '../providers/shamor_zachor_data_provider.dart';
import '../providers/shamor_zachor_progress_provider.dart';
import '../models/book_model.dart';
import 'book_card_widget.dart'; // Using the rich card
import 'package:otzaria/widgets/feedback/tool_empty_state.dart';

class CategoryBooksGrid extends StatefulWidget {
  final String? categoryName;
  final String? topLevelName;
  final BookCategory? category;
  final List<BookSearchResult>? searchResults;
  final Function(String, String, BookDetails) onBookSelected;
  final String selectedFilter;

  const CategoryBooksGrid({
    super.key,
    this.categoryName,
    this.topLevelName,
    this.category,
    this.searchResults,
    required this.onBookSelected,
    this.selectedFilter = 'all',
  });

  @override
  State<CategoryBooksGrid> createState() => _CategoryBooksGridState();
}

class _CategoryBooksGridState extends State<CategoryBooksGrid> {
  static final Logger _logger = Logger('CategoryBooksGrid');
  final Set<String> _locallyRemovedBookKeys = <String>{};

  String _bookLocalKey(String category, String bookName, BookDetails details) {
    if (details.id != null) {
      return 'id:${details.id}';
    }

    return '$category::$bookName';
  }

  bool _isBookLocallyRemoved(
      String category, String bookName, BookDetails details) {
    return _locallyRemovedBookKeys
        .contains(_bookLocalKey(category, bookName, details));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.category == null &&
        widget.searchResults == null &&
        widget.categoryName != 'custom_books_virtual') {
      return ToolEmptyState(
        icon: FluentIcons.library_24_regular,
        message: 'בחר קטגוריה כדי לצפות בספרים',
      );
    }

    return Column(
      children: [
        // Grid Content
        Expanded(
          child:
              Consumer2<ShamorZachorDataProvider, ShamorZachorProgressProvider>(
            builder: (context, dataProvider, progressProvider, child) {
              // Debug log
              _logger.fine(
                  'CategoryBooksGrid builder called for category: ${widget.categoryName}');

              if (widget.searchResults != null) {
                final searchBooks = widget.searchResults!
                    .map(
                      (result) => {
                        'name': result.bookName,
                        'details': result.bookDetails,
                        'category': result.topLevelCategoryName,
                        'categoryPath': result.bookDetails.categoryPath ??
                            result.categoryName,
                      },
                    )
                    .toList(growable: false);
                final filteredBooks =
                    _filterBooks(searchBooks, progressProvider, dataProvider);

                if (filteredBooks.isEmpty) {
                  return _buildEmptyState();
                }

                return _buildBooksGrid(
                    filteredBooks, progressProvider, dataProvider,
                    shrinkWrap: false);
              }

              if (widget.category != null) {
                final effectiveTopLevelName =
                    widget.topLevelName ?? widget.category!.name;

                // Check if this is the virtual "All Books" category
                final isAllBooksVirtual =
                    widget.topLevelName == 'all_books_virtual';

                // Check if we should group by subcategories
                if (widget.category!.subcategories != null &&
                    widget.category!.subcategories!.isNotEmpty) {
                  // אם כל הספרים סוננו (אין תוצאות בפילטר) - הצג חיווי במקום עץ ריק
                  final allFiltered = _filterBooks(
                      _getAllBooksRecursive(
                          widget.category!, effectiveTopLevelName),
                      progressProvider,
                      dataProvider);
                  if (allFiltered.isEmpty) {
                    return _buildEmptyState();
                  }
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // 1. Direct books in this category (only if NOT "All Books")
                      if (!isAllBooksVirtual)
                        Builder(builder: (context) {
                          final directBooks = _getAllBooksRecursive(
                              BookCategory(
                                  name: widget.category!.name,
                                  books: widget.category!.books,
                                  subcategories: null, // Only direct books
                                  isCustom: widget.category!.isCustom,
                                  sourceFile: widget.category!.sourceFile,
                                  schemaVersion: widget.category!.schemaVersion,
                                  contentType: widget.category!.contentType,
                                  defaultStartPage:
                                      widget.category!.defaultStartPage),
                              effectiveTopLevelName);
                          final filtered = _filterBooks(
                              directBooks, progressProvider, dataProvider);
                          if (filtered.isEmpty) return const SizedBox.shrink();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader(
                                  'ספרים ב${widget.category!.name}'),
                              _buildBooksGrid(
                                  filtered, progressProvider, dataProvider,
                                  shrinkWrap: true),
                              const SizedBox(height: 24),
                            ],
                          );
                        }),

                      // 2. Subcategories - using natural order from DataProvider
                      ...widget.category!.subcategories!.map((sub) {
                        // For "All Books", use the subcategory's own name as topLevelName
                        final subTopLevelName = isAllBooksVirtual
                            ? sub.name
                            : effectiveTopLevelName;
                        final subBooks =
                            _getAllBooksRecursive(sub, subTopLevelName);
                        final filtered = _filterBooks(
                            subBooks, progressProvider, dataProvider);

                        if (filtered.isEmpty) return const SizedBox.shrink();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader(sub.name),
                            _buildBooksGrid(
                                filtered, progressProvider, dataProvider,
                                shrinkWrap: true),
                            const SizedBox(height: 32),
                          ],
                        );
                      }),
                    ],
                  );
                } else {
                  // Leaf category - Flat Grid
                  final allBooks = _getAllBooksRecursive(
                      widget.category!, effectiveTopLevelName);
                  final filteredBooks =
                      _filterBooks(allBooks, progressProvider, dataProvider);

                  if (filteredBooks.isEmpty) {
                    return _buildEmptyState();
                  }
                  return _buildBooksGrid(
                      filteredBooks, progressProvider, dataProvider,
                      shrinkWrap: false);
                }
              }

              return _buildEmptyState();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    switch (widget.selectedFilter) {
      case 'in_progress':
        return const ToolEmptyState(
          icon: FluentIcons.hourglass_24_regular,
          message: 'אין ספרים בתהליך',
          subtitle:
              'ניתן להוסיף ספרים למעקב באמצעות לחצן ההוספה (+) שליד הסינון, '
              'והם יופיעו כאן.',
        );
      case 'completed':
        return const ToolEmptyState(
          icon: FluentIcons.checkmark_circle_24_regular,
          message: 'אין ספרים שהושלמו',
        );
      default:
        return const ToolEmptyState(
          icon: FluentIcons.book_24_regular,
          message: 'אין ספרים להצגה',
        );
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(FluentIcons.folder_24_regular,
              color: Theme.of(context).colorScheme.primary, size: 20),
          const SizedBox(width: 8),
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const Expanded(child: Divider(indent: 16)),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filterBooks(
      List<Map<String, dynamic>> books,
      ShamorZachorProgressProvider progressProvider,
      ShamorZachorDataProvider dataProvider) {
    return books.where((book) {
      final name = book['name'] as String;
      final details = book['details'] as BookDetails;
      final category = book['category'] as String;

      if (_isBookLocallyRemoved(category, name, details)) {
        return false;
      }

      final bookId = details.id;
      final bool isCompleted;
      final bool isInProgress;
      final bool isTracked;

      if (bookId != null) {
        isCompleted = progressProvider.isBookCompletedById(bookId, details);
        isInProgress =
            progressProvider.isBookConsideredInProgressById(bookId, details);
        isTracked = dataProvider.isBookTrackedById(bookId);
      } else {
        isCompleted = false;
        isInProgress = false;
        isTracked = false;
      }

      if (widget.selectedFilter == 'in_progress') {
        // ספר שנוסף ידנית למעקב נחשב "בתהליך" עד שמושלם, גם ללא התקדמות בפועל
        return (isTracked || isInProgress) && !isCompleted;
      }
      if (widget.selectedFilter == 'completed') {
        return isCompleted;
      }
      return true;
    }).toList();
  }

  Widget _buildBooksGrid(
    List<Map<String, dynamic>> books,
    ShamorZachorProgressProvider progressProvider,
    ShamorZachorDataProvider dataProvider, {
    bool shrinkWrap = false,
  }) {
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: GridView.builder(
        padding: shrinkWrap ? EdgeInsets.zero : const EdgeInsets.all(16),
        physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
        shrinkWrap: shrinkWrap,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 350,
          childAspectRatio: 1.5,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          mainAxisExtent: 192,
        ),
        itemCount: books.length,
        itemBuilder: (context, index) {
          final book = books[index];
          final name = book['name'] as String;
          final details = book['details'] as BookDetails;
          final category = book['category'] as String;
          final categoryPath = book['categoryPath'] as String?;

          // ניתן להסיר ספר שנוסף ידנית (custom או tracked) או שיש לו התקדמות
          final bookId = details.id;
          final canRemove = details.isCustom ||
              (bookId != null &&
                  (dataProvider.isBookTrackedById(bookId) ||
                      progressProvider
                          .getProgressForBookById(bookId)
                          .isNotEmpty));

          return BookCardWidget(
            key: ValueKey('${details.id ?? 'no-id'}::$category::$name'),
            topLevelCategoryKey: category,
            categoryName: categoryPath ?? widget.categoryName ?? '',
            bookName: name,
            bookDetails: details,
            onTap: () {
              widget.onBookSelected(category, name, details);
            },
            onDelete: canRemove
                ? () => _confirmRemoveBook(context, name, details)
                : null,
          );
        },
      ),
    );
  }

  Future<void> _confirmRemoveBook(
      BuildContext context, String bookName, BookDetails details) async {
    final progressProvider = context.read<ShamorZachorProgressProvider>();
    final dataProvider = context.read<ShamorZachorDataProvider>();

    // ספר בסיס נשאר זמין תחת "הכל" - ההסרה רק מורידה אותו מ"בתהליך"
    final isBaseBook = !details.isCustom;
    final confirmed = await showWarningDialog(
      context: context,
      title: isBaseBook ? 'הסרה מרשימת המעקב' : 'הסרת ספר משמור וזכור',
      content: isBaseBook
          ? 'האם להסיר את "$bookName" מרשימת "בתהליך"?'
          : 'האם להסיר את "$bookName" משמור וזכור?',
      subtitle: 'ההתקדמות השמורה תימחק ולא ניתן לשחזר אותה',
      cancelText: 'ביטול',
      confirmText: 'הסר',
    );

    if (confirmed != true || !context.mounted) return;

    final topLevelCategory = details.categoryPath ?? widget.categoryName ?? '';
    final localBookKey = _bookLocalKey(topLevelCategory, bookName, details);

    try {
      // הסתרה מיידית רק לספר מותאם (שנעלם לגמרי); ספר בסיס נשאר ב"הכל"
      if (!isBaseBook) {
        setState(() {
          _locallyRemovedBookKeys.add(localBookKey);
        });
      }

      if (details.id != null) {
        await progressProvider.clearBookProgressById(
          details.id!,
          bookDetails: details,
        );
        await dataProvider.removeBookFromTracking(details.id!);
      }

      if (context.mounted) {
        UiSnack.show(isBaseBook
            ? 'הספר "$bookName" הוסר מרשימת המעקב'
            : 'הספר "$bookName" הוסר משמור וזכור');
      }
    } catch (e) {
      if (mounted && !isBaseBook) {
        setState(() {
          _locallyRemovedBookKeys.remove(localBookKey);
        });
      }
      if (context.mounted) {
        UiSnack.showError('שגיאה בהסרת הספר: $e');
      }
    }
  }

  List<Map<String, dynamic>> _getAllBooksRecursive(
      BookCategory category, String topLevelName,
      {String? parentPath}) {
    List<Map<String, dynamic>> books = [];

    // Build the current category path
    final currentPath =
        parentPath != null ? '$parentPath/${category.name}' : category.name;

    category.books.forEach((name, details) {
      // Use the actual category from BookDetails if available, otherwise use topLevelName
      final actualCategory =
          details.categoryPath?.split('/').first ?? topLevelName;

      books.add({
        'name': name,
        'details': details,
        'category': actualCategory, // שימוש בקטגוריה האמיתית
        'categoryPath':
            details.categoryPath ?? currentPath, // נתיב מלא של הקטגוריות
      });
    });

    category.subcategories?.forEach((sub) {
      books.addAll(
          _getAllBooksRecursive(sub, topLevelName, parentPath: currentPath));
    });

    return books;
  }
}
