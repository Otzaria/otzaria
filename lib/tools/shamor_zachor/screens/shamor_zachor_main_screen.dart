import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:logging/logging.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import '../providers/shamor_zachor_data_provider.dart';
import '../providers/shamor_zachor_progress_provider.dart';
import '../widgets/error_boundary.dart';
import '../shamor_zachor_widget.dart';
import '../widgets/shamor_zachor_sidebar.dart';
import '../widgets/category_books_grid.dart';
import '../widgets/add_books_to_tracking_dialog.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import '../models/book_model.dart';
import 'book_detail_screen.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/shortcuts/key_map.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

/// Main screen for Shamor Zachor with Split View (Sidebar + Content)
class ShamorZachorMainScreen extends StatefulWidget {
  final ShamorZachorFocusController? focusController;

  const ShamorZachorMainScreen({
    super.key,
    this.focusController,
  });

  @override
  State<ShamorZachorMainScreen> createState() => _ShamorZachorMainScreenState();
}

class _ShamorZachorMainScreenState extends State<ShamorZachorMainScreen>
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
  String _searchQuery = ''; // Search query from top bar
  String _selectedFilter = 'in_progress'; // in_progress, completed, all

  /// מפתח שמירת מצב הצגת/הסתרת הסרגל בין הפעלות
  static const String _sidebarVisibleKey = 'sz:sidebar_visible';
  bool _isSidebarVisible = true;
  double _sidebarWidth = 300.0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _logger.info('Initialized ShamorZachorMainScreen (Split View)');
    _isSidebarVisible =
        Settings.getValue<bool>(_sidebarVisibleKey, defaultValue: true) ?? true;
    widget.focusController?.bind(_focusWindow);

    WidgetsBinding.instance.addPostFrameCallback((_) => _focusWindow());

    // Ensure data is loaded when screen is first displayed
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Load data provider first
      final dataProvider = context.read<ShamorZachorDataProvider>();
      final progressProvider = context.read<ShamorZachorProgressProvider>();

      await dataProvider.ensureLoaded();

      if (!mounted) return;

      // Then load progress provider (depends on the data provider)
      await progressProvider.ensureLoaded();

      if (mounted) {
        _notifyTitleChange();
      }
    });
  }

  @override
  void didUpdateWidget(covariant ShamorZachorMainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusController != widget.focusController) {
      oldWidget.focusController?.unbind(_focusWindow);
      widget.focusController?.bind(_focusWindow);
    }
  }

  void _navigateToBook(String category, String book, BookDetails details) {
    _logger.info(
        '_navigateToBook called: category=$category, book=$book, bookId=${details.id}');

    setState(() {
      // עדכון הקטגוריה לקטגוריה האמיתית של הספר
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
    _searchFocusNode.requestFocus();
  }

  void _focusWindow() {
    if (!mounted || !_windowFocusNode.canRequestFocus) return;
    _windowFocusNode.requestFocus();
  }

  /// מעדכן ושומר את מצב הצגת/הסתרת הסרגל כך שיישמר להפעלות הבאות
  void _setSidebarVisible(bool visible) {
    setState(() {
      _isSidebarVisible = visible;
    });
    Settings.setValue<bool>(_sidebarVisibleKey, visible);
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

  /// מחזור בין הסינונים: in_progress -> completed -> all -> in_progress
  void _cycleFilter() {
    _onFilterChanged(switch (_selectedFilter) {
      'in_progress' => 'completed',
      'completed' => 'all',
      'all' => 'in_progress',
      _ => 'in_progress',
    });
  }

  void _onFilterChanged(String value) {
    setState(() {
      _selectedFilter = value;
      // שינוי הסינון חוזר לרשימת הספרים גם אם ספר פתוח כעת
      _selectedBookName = null;
      _selectedBookDetails = null;
    });
    _notifyTitleChange();
  }

  /// בונה את שורת הסינון: [בתהליך | הושלם] [+ הוספה] [הכל].
  /// הבורר מפוצל לשניים כדי למקם את לחצן ההוספה בין "הושלם" ל"הכל".
  Widget _buildFilterControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: AppSegmentedControl<String>(
            options: const [
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
            onChanged: _onFilterChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: IconButton.filledTonal(
            tooltip: 'הוסף ספרים למעקב',
            visualDensity: VisualDensity.compact,
            onPressed: _openAddBooksDialog,
            icon: const RtlIcon(FluentIcons.add_24_regular),
          ),
        ),
        AppSegmentedControl<String>(
          options: const [
            SegmentOption<String>(
              value: 'all',
              label: 'הכל',
              icon: FluentIcons.library_24_regular,
            ),
          ],
          currentValue: _selectedFilter,
          onChanged: _onFilterChanged,
        ),
      ],
    );
  }

  Future<void> _openAddBooksDialog() async {
    final dataProvider = context.read<ShamorZachorDataProvider>();
    await showAddBooksToTrackingDialog(
      context: context,
      dataProvider: dataProvider,
    );
  }

  bool _isTextFieldFocused() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
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

  static const _modifiers = {'ctrl', 'control', 'shift', 'alt', 'meta'};

  ShortcutActivator? _activatorFromShortcut(String shortcut) {
    final parts = shortcut.toLowerCase().split('+');
    final hasCtrl = parts.contains('ctrl') || parts.contains('control');
    final hasShift = parts.contains('shift');
    final hasAlt = parts.contains('alt');
    final hasMeta = parts.contains('meta');

    final mainKeyName = parts.where((p) => !_modifiers.contains(p)).firstOrNull;
    if (mainKeyName == null) return null;

    LogicalKeyboardKey? logicalKey;
    if (mainKeyName.length == 1) {
      final code = mainKeyName.codeUnitAt(0);
      if (code >= 97 && code <= 122) {
        logicalKey = LogicalKeyboardKey(0x00000061 + (code - 97));
      }
    }
    logicalKey ??= KeyMap.keyFor(mainKeyName);
    if (logicalKey == null) return null;

    return SingleActivator(
      logicalKey,
      control: hasCtrl,
      shift: hasShift,
      alt: hasAlt,
      meta: hasMeta,
    );
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

  BookCategory? _findCategoryByName(
      BookCategory category, String categoryName) {
    if (category.name == categoryName) {
      return category;
    }

    for (final subCategory
        in category.subcategories ?? const <BookCategory>[]) {
      final match = _findCategoryByName(subCategory, categoryName);
      if (match != null) {
        return match;
      }
    }

    return null;
  }

  BookCategory? _resolveSelectedCategory(
      ShamorZachorDataProvider dataProvider) {
    final selectedCategoryName = _selectedCategoryName;
    final selectedTopLevelName = _selectedTopLevelName;

    if (selectedCategoryName == null || selectedTopLevelName == null) {
      return _selectedCategoryObject;
    }

    if (selectedTopLevelName == 'all_books_virtual' ||
        selectedTopLevelName == 'search_results') {
      return _selectedCategoryObject;
    }

    final topLevelCategory = dataProvider.allBookData[selectedTopLevelName];
    if (topLevelCategory == null) {
      return _selectedCategoryObject;
    }

    if (selectedCategoryName == selectedTopLevelName) {
      return topLevelCategory;
    }

    return _findCategoryByName(topLevelCategory, selectedCategoryName) ??
        _selectedCategoryObject;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final cycleFilterShortcutSetting = context.select(
      (SettingsBloc bloc) =>
          bloc.state.shortcuts['key-shortcut-shamor-zachor-cycle-filter'] ??
          ShortcutValidator
              .defaultShortcuts['key-shortcut-shamor-zachor-cycle-filter'] ??
          'ctrl+s',
    );
    final searchShortcutSetting = context.select(
      (SettingsBloc bloc) =>
          bloc.state.shortcuts['key-shortcut-search-current-window'] ??
          ShortcutValidator
              .defaultShortcuts['key-shortcut-search-current-window'] ??
          'ctrl+f',
    );

    return CallbackShortcuts(
      bindings: {
        _activatorFromShortcut(cycleFilterShortcutSetting) ??
            const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (_isTextFieldFocused()) return;
          _cycleFilter();
        },
        _activatorFromShortcut(searchShortcutSetting) ??
            const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          _focusSearchField();
        },
      },
      child: Focus(
        focusNode: _windowFocusNode,
        autofocus: true,
        onKeyEvent: _handleWindowKeyEvent,
        child: ErrorBoundary(
          child:
              Consumer2<ShamorZachorDataProvider, ShamorZachorProgressProvider>(
            builder: (context, dataProvider, progressProvider, child) {
              if (dataProvider.isLoading || progressProvider.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (dataProvider.error != null ||
                  progressProvider.error != null) {
                return Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      const Text('שגיאה בטעינת הנתונים'),
                      RecommendedActionButton(
                        text: 'נסה שוב',
                        onPressed: () async {
                          if (dataProvider.error != null) {
                            await dataProvider.loadAllData();
                          }
                          if (!context.mounted) {
                            return;
                          }
                          if (progressProvider.error != null) {
                            await progressProvider.retry();
                          }
                        },
                      )
                    ]));
              }

              // Default Selection Logic: 'All Books'
              BookCategory? currentCategoryObject =
                  _resolveSelectedCategory(dataProvider);
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
                child: Scaffold(
                  body: Builder(
                    builder: (context) {
                      final screenWidth = MediaQuery.sizeOf(context).width;
                      final useSecondaryRow = screenWidth < 900;
                      final filterControl = ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: _buildFilterControls(),
                      );
                      final narrowFilterControl = _buildFilterControls();

                      return Column(
                        children: [
                          AppTopBar(
                            leadingItems: [
                              AppTopBarItem(
                                widget: IconButton(
                                  tooltip: _isSidebarVisible
                                      ? 'הסתר ניווט'
                                      : 'הצג ניווט',
                                  onPressed: () =>
                                      _setSidebarVisible(!_isSidebarVisible),
                                  icon: AnimatedSwitcher(
                                    duration: AppTokens.animFast,
                                    transitionBuilder: (child, animation) =>
                                        RotationTransition(
                                      turns: Tween<double>(
                                        begin: 0.5,
                                        end: 0.0,
                                      ).animate(animation),
                                      child: FadeTransition(
                                        opacity: animation,
                                        child: child,
                                      ),
                                    ),
                                    child: Icon(
                                      _isSidebarVisible
                                          ? FluentIcons
                                              .panel_right_contract_24_regular
                                          : FluentIcons.panel_right_24_regular,
                                      key: ValueKey(_isSidebarVisible),
                                      size: 24,
                                    ),
                                  ),
                                  visualDensity: VisualDensity.standard,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondaryContainer,
                                ),
                              ),
                            ],
                            center: Row(
                              children: [
                                if (!useSecondaryRow) ...[
                                  filterControl,
                                  const SizedBox(width: 16),
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
                                      child: narrowFilterControl,
                                    ),
                                  )
                                : null,
                          ),
                          Expanded(
                            child: PrimaryScrollController(
                              controller: _contentScrollController,
                              child: AdaptiveSidePane(
                                isOpen: _isSidebarVisible,
                                alignment: AlignmentDirectional.centerEnd,
                                paneWidth: _sidebarWidth,
                                minMainContentWidth: 320,
                                onClose: () => _setSidebarVisible(false),
                                onOpen: () => _setSidebarVisible(true),
                                isResizable: true,
                                minPaneWidth: 220,
                                maxPaneWidth: 420,
                                onPaneWidthChanged: (nextWidth) {
                                  _sidebarWidth = nextWidth;
                                },
                                paneContent: ShamorZachorSidebar(
                                  onCategorySelected: _onCategorySelected,
                                  selectedCategoryName:
                                      currentTopLevelName == 'all_books_virtual'
                                          ? 'all_books_virtual'
                                          : _selectedCategoryName,
                                ),
                                wrapPaneInFloatingPanel: true,
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
                                              categoryName:
                                                  _selectedCategoryName!,
                                              bookName: _selectedBookName!,
                                              bookId: _selectedBookDetails!.id,
                                              bookDetails:
                                                  _selectedBookDetails!,
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
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults(ShamorZachorDataProvider dataProvider) {
    final results = dataProvider.searchBooks(_searchQuery);

    return CategoryBooksGrid(
      categoryName: 'תוצאות חיפוש',
      searchResults: results,
      topLevelName: 'search_results',
      onBookSelected: _navigateToBook,
      selectedFilter: _selectedFilter,
    );
  }

  @override
  void dispose() {
    widget.focusController?.unbind(_focusWindow);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _windowFocusNode.dispose();
    _contentScrollController.dispose();
    super.dispose();
  }
}
