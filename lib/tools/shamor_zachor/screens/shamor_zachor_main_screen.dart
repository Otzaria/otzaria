import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';
import 'package:otzaria/core/focus_repository.dart';

import '../providers/shamor_zachor_data_provider.dart';
import '../providers/shamor_zachor_progress_provider.dart';
import '../widgets/error_boundary.dart';
import '../shamor_zachor_widget.dart';
import '../widgets/shamor_zachor_sidebar.dart';
import '../widgets/category_books_grid.dart';
import '../models/book_model.dart';
import 'book_detail_screen.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/shortcuts/shortcut_helper.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/widgets/app_top_bar.dart';
import 'package:otzaria/widgets/inputs/segmented_button_tile.dart';
import 'package:otzaria/widgets/adaptive_side_pane.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/otzaria_search_field.dart';

/// Main screen for Shamor Zachor with Split View (Sidebar + Content)
class ShamorZachorMainScreen extends StatefulWidget {
  const ShamorZachorMainScreen({
    super.key,
  });

  @override
  State<ShamorZachorMainScreen> createState() => ShamorZachorMainScreenState();
}

class ShamorZachorMainScreenState extends State<ShamorZachorMainScreen>
    with AutomaticKeepAliveClientMixin {
  static final Logger _logger = Logger('ShamorZachorMainScreen');
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _windowFocusNode = FocusNode(skipTraversal: true);
  final ScrollController _contentScrollController = ScrollController();

  // Navigation State
  String? _selectedCategoryName; // Display name (e.g. Zeraim)
  String? _selectedTopLevelName; // Key (e.g. Mishnah)
  BookCategory? _selectedCategoryObject;
  String? _selectedBookName;
  BookDetails? _selectedBookDetails;
  String _searchQuery = ''; // Search query from sidebar
  String _selectedFilter = 'all'; // all, in_progress, completed
  bool _isSidebarVisible = true;
  double _sidebarWidth = 300.0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _logger.info('Initialized ShamorZachorMainScreen (Split View)');
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusWindow());

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
    _searchController.clear();
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

  void _focusSearchField() {
    if (!mounted || !_searchFocusNode.canRequestFocus) return;
    requestFocusIfNeeded(_searchFocusNode);
  }

  void _focusWindow() {
    if (!mounted || !_windowFocusNode.canRequestFocus) return;
    requestFocusIfNeeded(_windowFocusNode);
  }

  void requestKeyboardFocus() {
    _focusWindow();
  }

  void _closeBookDetails() {
    setState(() {
      _selectedBookName = null;
      _selectedBookDetails = null;
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

  /// מחזור בין הסינונים: all -> in_progress -> completed -> all
  void _cycleFilter() {
    setState(() {
      _selectedFilter = switch (_selectedFilter) {
        'all' => 'in_progress',
        'in_progress' => 'completed',
        'completed' => 'all',
        _ => 'all',
      };
    });
  }

  bool _isTextFieldFocused() {
    final w = FocusManager.instance.primaryFocus?.context?.widget;
    return w is TextField ||
        w is EditableText ||
        w.runtimeType.toString().contains('TextField');
  }

  KeyEventResult _handleWindowKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_isTextFieldFocused()) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_selectedBookName != null && _selectedBookDetails != null) {
        _closeBookDetails();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.pageDown) {
      _scrollContent(forward: true);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      _scrollContent(forward: false);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _scrollContent({required bool forward}) {
    if (!_contentScrollController.hasClients) return;
    final position = _contentScrollController.position;
    final delta = (position.viewportDimension * 0.85) * (forward ? 1 : -1);
    final target =
        (position.pixels + delta).clamp(0.0, position.maxScrollExtent);
    _contentScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final cycleFilterShortcutSetting = context.select(
      (SettingsBloc bloc) =>
          bloc.state.shortcuts['key-shortcut-shamor-zachor-cycle-filter'] ??
          ShortcutValidator.defaultShortcuts[
              'key-shortcut-shamor-zachor-cycle-filter'] ??
          'ctrl+e',
    );
    final searchShortcutSetting = context.select(
      (SettingsBloc bloc) =>
          bloc.state.shortcuts['key-shortcut-search-current-window'] ??
          ShortcutValidator.defaultShortcuts[
              'key-shortcut-search-current-window'] ??
          'ctrl+f',
    );

    return CallbackShortcuts(
      bindings: {
        ShortcutHelper.activatorFromShortcut(cycleFilterShortcutSetting) ??
            const SingleActivator(LogicalKeyboardKey.keyE, control: true): () {
          if (_isTextFieldFocused()) return;
          _cycleFilter();
        },
        ShortcutHelper.activatorFromShortcut(searchShortcutSetting) ??
            const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          _focusSearchField();
        },
      },
      child: Focus(
        focusNode: _windowFocusNode,
        autofocus: true,
        onKeyEvent: _handleWindowKeyEvent,
        child: Scaffold(
          body: ErrorBoundary(
            child: Consumer2<ShamorZachorDataProvider,
                ShamorZachorProgressProvider>(
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
                    RecommendedActionButton(
                      text: 'נסה שוב',
                      onPressed: () {
                        dataProvider.loadAllData();
                      },
                    )
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
              child: Column(
                children: [
                  BlocBuilder<SettingsBloc, SettingsState>(
                    builder: (context, settingsState) => LayoutBuilder(
                      builder: (context, constraints) {
                        final useSecondaryRow = constraints.maxWidth < 900;
                        final filterControl = SizedBox(
                          width: 420,
                          child: AppSegmentedControl<String>(
                            options: const [
                              SegmentOption<String>(
                                value: 'all',
                                label: 'הכל',
                                icon: FluentIcons.library_24_regular,
                              ),
                              SegmentOption<String>(
                                value: 'in_progress',
                                label: 'בתהליך',
                                icon: FluentIcons.hourglass_24_regular,
                              ),
                              SegmentOption<String>(
                                value: 'completed',
                                label: 'הושלם',
                                icon: FluentIcons.checkmark_circle_24_regular,
                              ),
                            ],
                            currentValue: _selectedFilter,
                            onChanged: (value) {
                              setState(() {
                                _selectedFilter = value;
                              });
                            },
                          ),
                        );

                        return AppTopBar(
                          leadingItems: [
                            AppTopBarItem(
                              widget: ToolbarActionButton(
                                compact: settingsState.compactMenuMode,
                                tooltip: _isSidebarVisible
                                    ? 'הסתר ניווט'
                                    : 'הצג ניווט',
                                icon: FluentIcons.navigation_24_regular,
                                selected: _isSidebarVisible,
                                onPressed: () {
                                  setState(() {
                                    _isSidebarVisible = !_isSidebarVisible;
                                  });
                                },
                              ),
                            ),
                          ],
                          center: Row(
                            children: [
                              if (!useSecondaryRow) ...[
                                filterControl,
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: OtzariaSearchField(
                                  controller: _searchController,
                                  focusNode: _searchFocusNode,
                                  hintText: 'חפש...',
                                  onChanged: _onSearchChanged,
                                  onSubmitted: (_) => _focusWindow(),
                                  onClear: () => _onSearchChanged(''),
                                ),
                              ),
                            ],
                          ),
                          secondaryRow: useSecondaryRow
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: filterControl,
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                  Expanded(
                    child: PrimaryScrollController(
                      controller: _contentScrollController,
                      child: AdaptiveSidePane(
                      isOpen: _isSidebarVisible,
                      alignment: AlignmentDirectional.centerEnd,
                      paneWidth: _sidebarWidth,
                      minMainContentWidth: 320,
                      onClose: () {
                        setState(() {
                          _isSidebarVisible = false;
                        });
                      },
                      onOpen: () {
                        setState(() {
                          _isSidebarVisible = true;
                        });
                      },
                      paneColor: AppSurfaces.solidPanelBackground(context),
                      isResizable: true,
                      minPaneWidth: 220,
                      maxPaneWidth: 420,
                      onPaneWidthChanged: (nextWidth) {
                        setState(() {
                          _sidebarWidth = nextWidth;
                        });
                      },
                      paneContent: ShamorZachorSidebar(
                        onCategorySelected: _onCategorySelected,
                        selectedCategoryName:
                            currentTopLevelName == 'all_books_virtual'
                                ? 'all_books_virtual'
                                : _selectedCategoryName,
                      ),
                      narrowPaneBuilder: (context, paneContent) => Material(
                        color: AppSurfaces.solidPanelBackground(context),
                        child: SafeArea(child: paneContent),
                      ),
                      mainContent: _selectedBookName != null &&
                              _selectedBookDetails != null
                          ? Builder(
                              builder: (context) {
                                _logger.info(
                                    'Creating BookDetailScreen: bookName=$_selectedBookName, bookId=${_selectedBookDetails!.id}');

                                return KeyedSubtree(
                                  key: ValueKey(
                                      'Book_${_selectedCategoryName}_$_selectedBookName'),
                                  child: BookDetailScreen(
                                    topLevelCategoryKey:
                                        _selectedTopLevelName ??
                                            _selectedCategoryName!,
                                    categoryName: _selectedCategoryName!,
                                    bookName: _selectedBookName!,
                                    bookId: _selectedBookDetails!.id,
                                    bookDetails: _selectedBookDetails!,
                                    onBack: _closeBookDetails,
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
                                  selectedFilter: _selectedFilter,
                                ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
            ),
          ),
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
      selectedFilter: _selectedFilter,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _windowFocusNode.dispose();
    _contentScrollController.dispose();
    super.dispose();
  }
}
