import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:logging/logging.dart';
import '../providers/shamor_zachor_data_provider.dart';
import '../providers/shamor_zachor_progress_provider.dart';
import '../models/book_model.dart';
import '../widgets/book_card_widget.dart'; // Using the rich card

class CategoryBooksGrid extends StatefulWidget {
  final String? categoryName;
  final String? topLevelName;
  final BookCategory? category;
  final Function(String, String, BookDetails) onBookSelected;

  const CategoryBooksGrid({
    super.key,
    this.categoryName,
    this.topLevelName,
    this.category,
    required this.onBookSelected,
  });

  @override
  State<CategoryBooksGrid> createState() => _CategoryBooksGridState();
}

class _CategoryBooksGridState extends State<CategoryBooksGrid> {
  static final Logger _logger = Logger('CategoryBooksGrid');

  // Using simplified filter enum/string from user request
  // User wanted "Like it was before" -> "Segmented Button".
  String _selectedFilter = 'all'; // all, in_progress, completed

  @override
  Widget build(BuildContext context) {
    if (widget.category == null &&
        widget.categoryName != 'custom_books_virtual') {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(FluentIcons.library_24_regular,
                size: 64, color: Colors.grey.withAlpha(100)),
            const SizedBox(height: 16),
            Text('בחר קטגוריה כדי לצפות בספרים',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: Colors.grey)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header with Segmented Button (Like Tracking Screen)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Segmented Button
              Align(
                alignment: Alignment.center,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment<String>(
                      value: 'all',
                      label: Text('הכל'),
                      icon: Icon(FluentIcons.library_24_regular),
                    ),
                    ButtonSegment<String>(
                      value: 'in_progress',
                      label: Text('בתהליך'),
                      icon: Icon(FluentIcons.hourglass_24_regular),
                    ),
                    ButtonSegment<String>(
                      value: 'completed',
                      label: Text('הושלם'),
                      icon: Icon(FluentIcons.checkmark_circle_24_regular),
                    ),
                  ],
                  selected: {_selectedFilter},
                  onSelectionChanged: (Set<String> newSelection) {
                    setState(() {
                      _selectedFilter = newSelection.first;
                    });
                  },
                  showSelectedIcon: false,
                ),
              ),
            ],
          ),
        ),

        // Grid Content
        Expanded(
          child:
              Consumer2<ShamorZachorDataProvider, ShamorZachorProgressProvider>(
            builder: (context, dataProvider, progressProvider, child) {
              // Debug log
              _logger.fine(
                  'CategoryBooksGrid builder called for category: ${widget.categoryName}');

              if (widget.categoryName == 'custom_books_virtual') {
                // Handling custom books - Flat list
                final custom = dataProvider.getCustomBooks();
                final allBooks = custom
                    .map((b) => {
                          'name': b['bookName'],
                          'details': b['bookDetails'],
                          'category': b['topLevelCategoryKey']
                        })
                    .toList();

                final filteredBooks = _filterBooks(allBooks, progressProvider);
                if (filteredBooks.isEmpty) {
                  return _buildEmptyState();
                }
                return _buildBooksGrid(filteredBooks, progressProvider,
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
                          final filtered =
                              _filterBooks(directBooks, progressProvider);
                          if (filtered.isEmpty) return const SizedBox.shrink();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionHeader(
                                  'ספרים ב${widget.category!.name}'),
                              _buildBooksGrid(filtered, progressProvider,
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
                        final filtered =
                            _filterBooks(subBooks, progressProvider);

                        if (filtered.isEmpty) return const SizedBox.shrink();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader(sub.name),
                            _buildBooksGrid(filtered, progressProvider,
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
                      _filterBooks(allBooks, progressProvider);

                  if (filteredBooks.isEmpty) {
                    return _buildEmptyState();
                  }
                  return _buildBooksGrid(filteredBooks, progressProvider,
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
    return const Center(
        child: Text('אין ספרים להצגה', style: TextStyle(color: Colors.grey)));
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

  List<Map<String, dynamic>> _filterBooks(List<Map<String, dynamic>> books,
      ShamorZachorProgressProvider progressProvider) {
    return books.where((book) {
      final name = book['name'] as String;
      final details = book['details'] as BookDetails;
      final category = book['category'] as String;

      final isCompleted =
          progressProvider.isBookCompleted(category, name, details);
      final isInProgress =
          progressProvider.isBookConsideredInProgress(category, name, details);

      if (_selectedFilter == 'in_progress') {
        return isInProgress && !isCompleted;
      }
      if (_selectedFilter == 'completed') {
        return isCompleted;
      }
      return true;
    }).toList();
  }

  Widget _buildBooksGrid(List<Map<String, dynamic>> books,
      ShamorZachorProgressProvider progressProvider,
      {bool shrinkWrap = false}) {
    return GridView.builder(
      padding: shrinkWrap ? EdgeInsets.zero : const EdgeInsets.all(16),
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      shrinkWrap: shrinkWrap,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 350,
        childAspectRatio: 1.5,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        mainAxisExtent: 180,
      ),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        final name = book['name'] as String;
        final details = book['details'] as BookDetails;
        final category = book['category'] as String;

        // השתמש ב-ID אם קיים, אחרת חזור לשיטה הישנה
        final progressData = details.id != null
            ? progressProvider.getProgressForBookById(details.id!)
            : progressProvider.getProgressForBook(category, name);
        final completionDate = details.id != null
            ? progressProvider.getCompletionDateSyncById(details.id!)
            : progressProvider.getCompletionDateSync(category, name);
        final categoryPath = book['categoryPath'] as String?;

        return BookCardWidget(
          topLevelCategoryKey: category,
          categoryName: categoryPath ?? widget.categoryName ?? '',
          bookName: name,
          bookDetails: details,
          bookProgressData: progressData,
          completionDate: completionDate,
          onTap: () {
            widget.onBookSelected(category, name, details);
          },
        );
      },
    );
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
