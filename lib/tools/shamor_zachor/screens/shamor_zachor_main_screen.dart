import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';

import '../providers/shamor_zachor_data_provider.dart';
import '../providers/shamor_zachor_progress_provider.dart';
import '../widgets/error_boundary.dart';
import '../shamor_zachor_widget.dart';
import '../widgets/shamor_zachor_sidebar.dart';
import '../widgets/category_books_grid.dart';
import '../models/book_model.dart';
import 'book_detail_screen.dart';

/// Main screen for Shamor Zachor with Split View (Sidebar + Content)
class ShamorZachorMainScreen extends StatefulWidget {
  const ShamorZachorMainScreen({super.key});

  @override
  State<ShamorZachorMainScreen> createState() => _ShamorZachorMainScreenState();
}

class _ShamorZachorMainScreenState extends State<ShamorZachorMainScreen>
    with AutomaticKeepAliveClientMixin {
  static final Logger _logger = Logger('ShamorZachorMainScreen');

  // Navigation State
  String? _selectedCategoryName; // Display name (e.g. Zeraim)
  String? _selectedTopLevelName; // Key (e.g. Mishnah)
  BookCategory? _selectedCategoryObject;
  String? _selectedBookName;
  BookDetails? _selectedBookDetails;
  String _searchQuery = ''; // Search query from sidebar

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _logger.info('Initialized ShamorZachorMainScreen (Split View)');

    // Ensure data is loaded when screen is first displayed
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Load data provider first
      final dataProvider = context.read<ShamorZachorDataProvider>();
      final progressProvider = context.read<ShamorZachorProgressProvider>();

      await dataProvider.ensureLoaded();

      if (!mounted) return;

      // Then load progress provider (depends on data provider for migration)
      await progressProvider.ensureLoaded();

      if (mounted) {
        _notifyTitleChange();
      }
    });
  }

  void _navigateToBook(String category, String book, BookDetails details) {
    _logger.info(
        '_navigateToBook called: category=$category, book=$book, bookId=${details.id}');

    setState(() {
      // עדכון הקטגוריה לקטגוריה האמיתית של הספר
      // (לא "all_books_virtual")
      _selectedCategoryName = category;

      // שמירת ה-topLevelName הנוכחי אם לא הוגדר
      _selectedTopLevelName ??= 'all_books_virtual';

      _selectedBookName = book;
      _selectedBookDetails = details;
    });
    _notifyTitleChange();
  }

  void _onCategorySelected(
      String name, BookCategory category, String topLevelName) {
    setState(() {
      _selectedCategoryName = name;
      _selectedCategoryObject = category;
      _selectedTopLevelName = topLevelName;

      _selectedBookName = null;
      _selectedBookDetails = null;
      _searchQuery = ''; // Clear search when selecting a category
    });
    _notifyTitleChange();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      // Clear selection when searching
      if (query.length >= 2) {
        _selectedCategoryName = null;
        _selectedCategoryObject = null;
        _selectedTopLevelName = null;
        _selectedBookName = null;
        _selectedBookDetails = null;
      }
    });
    _notifyTitleChange();
  }

  void _notifyTitleChange() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        String title;
        if (_selectedBookName != null) {
          title = 'שמור וזכור - $_selectedBookName';
        } else if (_selectedCategoryName != null) {
          title = 'שמור וזכור - $_selectedCategoryName';
        } else {
          title = 'שמור וזכור';
        }

        final ancestorWidget =
            context.findAncestorWidgetOfExactType<ShamorZachorWidget>();
        if (ancestorWidget != null && ancestorWidget.onTitleChanged != null) {
          ancestorWidget.onTitleChanged!(title);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Define Sidebar Width
    const double sidebarWidth = 300.0;

    return Scaffold(
      body: ErrorBoundary(
        child:
            Consumer2<ShamorZachorDataProvider, ShamorZachorProgressProvider>(
          builder: (context, dataProvider, progressProvider, child) {
            if (dataProvider.isLoading || progressProvider.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (dataProvider.error != null || progressProvider.error != null) {
              return Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    const Text('שגיאה בטעינת הנתונים'),
                    ElevatedButton(
                        onPressed: () {
                          dataProvider.loadAllData();
                        },
                        child: const Text('נסה שוב'))
                  ]));
            }

            // Default Selection Logic: 'All Books'
            BookCategory? currentCategoryObject = _selectedCategoryObject;
            String? currentCategoryName = _selectedCategoryName;
            String? currentTopLevelName = _selectedTopLevelName;

            if (currentCategoryObject == null &&
                currentCategoryName == null &&
                _selectedBookName == null) {
              // Construct 'All Books' category (same logic as Sidebar)
              final allCategories = dataProvider.allBookData;
              // Use natural order from DataProvider (already sorted by orderIndex from DB)
              final sortedKeys = allCategories.keys.toList();

              currentCategoryName = 'כל הספרים';
              currentTopLevelName = 'all_books_virtual';
              currentCategoryObject = BookCategory(
                  name: 'כל הספרים',
                  books: {},
                  subcategories:
                      sortedKeys.map((key) => allCategories[key]!).toList(),
                  isCustom: false,
                  sourceFile: 'virtual',
                  schemaVersion: 1,
                  contentType: 'text',
                  defaultStartPage: 1);
            }

            return NotificationListener<BookNavigationNotification>(
              onNotification: (notification) {
                _navigateToBook(
                  notification.categoryName,
                  notification.bookName,
                  notification.bookDetails,
                );
                return true;
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Sidebar
                  SizedBox(
                    width: sidebarWidth,
                    child: ShamorZachorSidebar(
                      onCategorySelected: _onCategorySelected,
                      onSearchChanged: _onSearchChanged,
                      selectedCategoryName:
                          currentTopLevelName == 'all_books_virtual'
                              ? 'all_books_virtual'
                              : _selectedCategoryName,
                    ),
                  ),

                  // Vertical Divider
                  const VerticalDivider(width: 1),

                  // 2. Main Content Area
                  Expanded(
                    child: _selectedBookName != null &&
                            _selectedBookDetails != null
                        ? Builder(
                            builder: (context) {
                              // Debug log
                              _logger.info(
                                  'Creating BookDetailScreen: bookName=$_selectedBookName, bookId=${_selectedBookDetails!.id}');

                              return KeyedSubtree(
                                key: ValueKey(
                                    'Book_${_selectedCategoryName}_$_selectedBookName'),
                                child: BookDetailScreen(
                                  topLevelCategoryKey: _selectedTopLevelName ??
                                      _selectedCategoryName!,
                                  categoryName: _selectedCategoryName!,
                                  bookName: _selectedBookName!,
                                  bookId:
                                      _selectedBookDetails!.id, // העברת ה-ID
                                  bookDetails:
                                      _selectedBookDetails!, // Pass the details directly
                                  onBack: () {
                                    setState(() {
                                      _selectedBookName = null;
                                      _selectedBookDetails = null;
                                    });
                                    _notifyTitleChange();
                                  },
                                ),
                              );
                            },
                          )
                        : _searchQuery.length >= 2
                            ? _buildSearchResults(dataProvider)
                            : CategoryBooksGrid(
                                categoryName: currentCategoryName,
                                category: currentCategoryObject,
                                topLevelName: currentTopLevelName,
                                onBookSelected: _navigateToBook,
                              ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchResults(ShamorZachorDataProvider dataProvider) {
    final results = dataProvider.searchBooks(_searchQuery);

    // Create a virtual category with search results
    final searchCategory = BookCategory(
      name: 'תוצאות חיפוש: "$_searchQuery"',
      books: {for (var r in results) r.bookName: r.bookDetails},
      subcategories: null,
      isCustom: false,
      sourceFile: 'search',
      schemaVersion: 1,
      contentType: 'text',
      defaultStartPage: 1,
    );

    return CategoryBooksGrid(
      categoryName: 'תוצאות חיפוש',
      category: searchCategory,
      topLevelName: 'search_results',
      onBookSelected: _navigateToBook,
    );
  }
}
