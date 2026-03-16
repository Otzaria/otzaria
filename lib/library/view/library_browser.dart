import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/external_catalog/view/external_catalog_settings_helper.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/daf_yomi/daf_yomi_helper.dart';
import 'package:otzaria/file_sync/file_sync_bloc.dart';
import 'package:otzaria/file_sync/file_sync_repository.dart';
import 'package:otzaria/file_sync/file_sync_state.dart';
import 'package:otzaria/daf_yomi/daf_yomi.dart';
import 'package:otzaria/file_sync/file_sync_widget.dart';
import 'package:otzaria/widgets/filter_chips_widget.dart';
import 'package:otzaria/navigation/main_window_screen.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/library/view/otzar_book_dialog.dart';
import 'package:otzaria/library/view/book_preview_panel.dart';
import 'package:otzaria/library/view/resizable_preview_panel.dart';
import 'package:otzaria/widgets/responsive_action_bar.dart';
import 'package:otzaria/utils/open_book.dart';

import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';
import 'package:otzaria/settings/settings_exports.dart';

class LibraryBrowser extends StatefulWidget {
  const LibraryBrowser({super.key});

  @override
  State<LibraryBrowser> createState() => _LibraryBrowserState();
}

class _LibraryBrowserState extends State<LibraryBrowser>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int _depth = 0;
  final Set<String> _expandedCategories = {}; // קטגוריות שנפתחו בתצוגת רשימה

  // Canonical display order for top-level categories (overrides DB orderIndex).
  // Titles use ASCII double-quote; Hebrew gershayim (\u05F4 ״) is normalised
  // to ASCII " before lookup, so both DB titles and placeholder titles match.
  static const List<String> _orderedTopCategories = [
    'תנ"ך',
    'מדרש',
    'משנה',
    'תלמוד בבלי',
    'תלמוד ירושלמי',
    'תוספתא',
    'הלכה',
    'שו"ת',
    'קבלה',
    'סדר התפילה',
    'מחשבת ישראל',
    'חסידות',
    'ספרי מוסר',
    'מילונים וספרי יעץ',
    'לימוד יומי',
    'ספרות עזר',
    'בית שני',
  ];

  /// Returns a sort key for a top-level category.
  /// Categories listed in [_orderedTopCategories] get their index (0-based);
  /// all others are appended after with their DB order as a tie-breaker.
  int _getTopCategoryOrder(Category cat) {
    final normalized =
        cat.title.replaceAll('\u05F4', '"').replaceAll('\u05F3', "'");
    final idx = _orderedTopCategories.indexOf(normalized);
    return idx >= 0 ? idx : _orderedTopCategories.length + cat.order;
  }

  /// Normalises a DB orderIndex for display sorting.
  /// Negative values (e.g. -5 used for מפרשים) are remapped to the end
  /// (1000 + abs(value)) so they appear after the primary content.
  static int _normalizeOrder(int order) =>
      order >= 0 ? order : 1000 + order.abs();

  // FileSyncBloc יווצר פעם אחת בלבד
  late final FileSyncBloc _fileSyncBloc;

  @override
  void initState() {
    super.initState();
    context.read<LibraryBloc>().add(LoadLibrary());

    // יצירת FileSyncBloc פעם אחת בלבד
    _fileSyncBloc = FileSyncBloc(
      repository: FileSyncRepository(
        githubOwner: "Otzaria",
        repositoryName: "SeforimLibrary",
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      unawaited(
        ExternalCatalogSettingsHelper.maybeAutoSyncCatalogs(
          context.read<SettingsBloc>().state,
        ),
      );
    });
  }

  @override
  void dispose() {
    _fileSyncBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return MultiBlocListener(
      listeners: [
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (previous, current) {
            return previous.showExternalBooks != current.showExternalBooks ||
                previous.autoSyncCatalogs != current.autoSyncCatalogs;
          },
          listener: (context, settingsState) {
            unawaited(
              ExternalCatalogSettingsHelper.maybeAutoSyncCatalogs(
                settingsState,
              ),
            );
          },
        ),
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (previous, current) {
            return previous.showExternalBooks != current.showExternalBooks ||
                previous.showHebrewBooks != current.showHebrewBooks ||
                previous.showOtzarHachochma != current.showOtzarHachochma;
          },
          listener: (context, settingsState) {
            final query = context.read<LibraryBloc>().state.searchQuery;
            if (query != null && query.trim().length >= 3) {
              _searchWithSettings(context, settingsState);
            }
          },
        ),
      ],
      child: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, settingsState) {
          return BlocBuilder<LibraryBloc, LibraryState>(
            buildWhen: (previous, current) {
              // אל תבנה מחדש אם רק previewBook השתנה
              // נבנה מחדש רק אם שדות אחרים השתנו
              return previous.isLoading != current.isLoading ||
                  previous.error != current.error ||
                  previous.library != current.library ||
                  previous.currentCategory != current.currentCategory ||
                  previous.searchResults != current.searchResults ||
                  previous.searchQuery != current.searchQuery ||
                  previous.selectedTopics != current.selectedTopics;
            },
            builder: (context, state) {
              if (state.error != null) {
                return Center(child: Text('Error: ${state.error}'));
              }

              // אם אין ספרייה ולא בטעינה - הצג שגיאה
              if (state.library == null && !state.isLoading) {
                return const Center(child: Text('No library data available'));
              }

              // גם אם אין ספרייה אבל בטעינה - הצג את המסך עם שכבת טעינה
              return Stack(
                children: [
                  // תוכן הספרייה - תמיד מוצג (גם אם הספרייה null)
                  Scaffold(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    appBar: AppBar(
                      // Keep the AppBar visually consistent when scrolling
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      surfaceTintColor: Colors.transparent,
                      title: Row(
                        children: [
                          _buildLibraryActions(context, state, settingsState),
                          const SizedBox(width: 8),
                          Expanded(child: _buildSearchBar(state)),
                          DafYomi(
                            onDafYomiTap: (tractate, daf) {
                              openDafYomiBook(context, tractate, ' $daf.');
                            },
                            onCalendarTap: () {
                              // Reset to calendar BEFORE navigation using GlobalKey
                              (moreScreenKey.currentState as dynamic)
                                  ?.resetToCalendar();
                              // Then navigate
                              context.read<NavigationBloc>().add(
                                    const NavigateToScreen(Screen.more),
                                  );
                            },
                          ),
                        ],
                      ),
                    ),
                    body: LayoutBuilder(
                      builder: (context, constraints) {
                        final screenWidth = constraints.maxWidth;
                        const minPreviewWidth = 8.0;
                        // ברירת מחדל: שליש ברשת, שני שליש ברשימה
                        final previewWidth =
                            settingsState.libraryViewMode == 'list'
                                ? (screenWidth * 2 / 3)
                                : (screenWidth / 3);

                        final maxPreviewWidth = (screenWidth - 350)
                            .clamp(minPreviewWidth, screenWidth);

                        return Row(
                          children: [
                            // תוכן הספרייה - עכשיו בצד ימין
                            Expanded(
                              child: Column(
                                children: [
                                  if (context
                                          .read<FocusRepository>()
                                          .librarySearchController
                                          .text
                                          .length >
                                      2)
                                    _buildTopicsSelection(
                                        context, state, settingsState),
                                  // תוכן הספרייה
                                  Expanded(child: _buildContent(state)),
                                ],
                              ),
                            ),
                            // פאנל תצוגה מקדימה בצד שמאל עם מסגרת ואפשרות שינוי גודל
                            if (settingsState.libraryShowPreview)
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: ResizablePreviewPanel(
                                  key: ValueKey(
                                      screenWidth), // מפתח שמשתנה עם רוחב המסך
                                  initialWidth: previewWidth,
                                  minWidth: minPreviewWidth,
                                  maxWidth:
                                      maxPreviewWidth, // השאר לפחות 350px לרשימה (ככל שניתן)
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color:
                                          Theme.of(context).colorScheme.surface,
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline
                                            .withValues(alpha: 0.3),
                                        width: 1.0,
                                      ),
                                      borderRadius: BorderRadius.circular(8.0),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(7.0),
                                      child: BlocBuilder<LibraryBloc,
                                          LibraryState>(
                                        buildWhen: (previous, current) {
                                          // רק אם previewBook השתנה
                                          return previous.previewBook !=
                                              current.previewBook;
                                        },
                                        builder: (context, previewState) {
                                          return GestureDetector(
                                            onDoubleTap: () {
                                              if (previewState.previewBook !=
                                                  null) {
                                                _openBookInReader(
                                                    previewState.previewBook!,
                                                    0);
                                              }
                                            },
                                            child: BookPreviewPanel(
                                              book: previewState.previewBook,
                                              onOpenInReader: (index) {
                                                if (previewState.previewBook !=
                                                    null) {
                                                  _openBookInReader(
                                                      previewState.previewBook!,
                                                      index);
                                                }
                                              },
                                              onClose: () {
                                                context
                                                    .read<SettingsBloc>()
                                                    .add(
                                                      const UpdateLibraryShowPreview(
                                                          false),
                                                    );
                                              },
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  // שכבת חסימה בזמן טעינה
                  if (state.isLoading)
                    Positioned.fill(
                      child: Container(
                        color: Theme.of(context)
                            .colorScheme
                            .surface
                            .withValues(alpha: 0.3),
                        child: Center(
                          child: Container(
                            width: 200,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: _LoadingDotsText(),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSearchBar(LibraryState state) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        final focusRepository = context.read<FocusRepository>();
        return RtlTextField(
          controller: focusRepository.librarySearchController,
          focusNode: context.read<FocusRepository>().librarySearchFocusNode,
          autofocus: true,
          decoration: InputDecoration(
            constraints: const BoxConstraints(maxWidth: 400),
            prefixIcon: const Icon(FluentIcons.search_24_regular),
            suffixIcon: IconButton(
              onPressed: () {
                focusRepository.librarySearchController.clear();
                _update(context, state, settingsState);
                _refocusSearchBar();
              },
              icon: const Icon(FluentIcons.dismiss_24_regular),
            ),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(8.0)),
            ),
            hintText:
                'איתור ספר או מחבר ב${state.currentCategory?.title ?? ""}',
          ),
          onChanged: (value) {
            context.read<LibraryBloc>().add(UpdateSearchQuery(value));
            context.read<LibraryBloc>().add(const SelectTopics([]));
            _update(context, state, settingsState);
          },
        );
      },
    );
  }

  Widget _buildTopicsSelection(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
  ) {
    if (state.searchResults == null) {
      return const SizedBox.shrink();
    }

    final categoryTopics = [
      "תנך",
      "מדרש",
      "משנה",
      "תלמוד בבלי",
      "תלמוד ירושלמי",
      "הלכה",
      "משנה תורה",
      "שולחן ערוך",
      "חסידות",
      "קבלה",
      "ספרי מוסר",
      "שות",
      "ראשונים",
      "אחרונים",
      "מחברי זמננו",
    ];

    final allTopics = _getAllTopics(state.searchResults!);

    final relevantTopics =
        categoryTopics.where((element) => allTopics.contains(element)).toList();

    return FilterChipsSelector<String>(
      items: relevantTopics,
      selectedItems: state.selectedTopics ?? [],
      labelBuilder: (item) => item,
      wrapAlignment: WrapAlignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      onSelectionChanged: (list) {
        context.read<LibraryBloc>().add(SelectTopics(list));
        _update(context, state, settingsState);
        _refocusSearchBar();
      },
      chipBuilder: (context, item, isSelected) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: Chip(
          label: Text(item),
          backgroundColor:
              isSelected ? Theme.of(context).colorScheme.secondary : null,
          labelStyle: TextStyle(
            color:
                isSelected ? Theme.of(context).colorScheme.onSecondary : null,
            fontSize: 11,
          ),
          labelPadding: const EdgeInsets.all(0),
        ),
      ),
    );
  }

  Widget _buildContent(LibraryState state) {
    // אם אין ספרייה - הצג מסך ריק (שכבת הטעינה תכסה אותו)
    if (state.library == null || state.currentCategory == null) {
      return const Center(child: SizedBox.shrink());
    }

    final settingsState = context.read<SettingsBloc>().state;
    // במצב תצוגת רשת - תמיד רשת
    if (settingsState.libraryViewMode == 'grid') {
      final items = state.searchResults != null
          ? _buildSearchResults(state.searchResults!)
          : _buildCategoryContent(state.currentCategory!);

      return FutureBuilder<List<Widget>>(
        future: items,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.hasData && snapshot.data!.isEmpty) {
            final focusRepository = context.read<FocusRepository>();
            return Center(
              child: Text(
                focusRepository.librarySearchController.text.isNotEmpty
                    ? 'אין תוצאות עבור "${focusRepository.librarySearchController.text}"'
                    : 'אין פריטים להצגה בתיקייה זו',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            );
          }
          // שינוי: במקום ListView.builder, נשתמש ב-SingleChildScrollView עם Column
          // כדי למנוע בעיות גלילה כשה-widgets משנים גובה
          return SingleChildScrollView(
            key: PageStorageKey(state.currentCategory),
            child: Column(
              children: snapshot.data!,
            ),
          );
        },
      );
    }

    // תצוגת רשימה - גם בחיפוש וגם בלי
    if (state.searchResults != null) {
      // במצב חיפוש ברשימה - הצג רק את הספרים
      return _buildSearchListView(state.searchResults!);
    }

    // תצוגת רשימה עם עץ מתרחב
    return _buildListView(state.currentCategory!);
  }

  Future<List<Widget>> _buildSearchResults(List<Book> books) async {
    // בניית כל הפריטים מראש
    final bookWidgets = books
        .take(100)
        .map((book) => _buildBookItem(book, showTopics: true))
        .toList();

    return [
      MyGridView(items: bookWidgets),
    ];
  }

  Future<List<Widget>> _buildCategoryContent(Category category) async {
    List<Widget> items = [];

    final filteredBooks = category.books.toList();
    final filteredSubCategories = category.subCategories.toList();

    filteredBooks.sort((a, b) => a.order.compareTo(b.order));
    if (category is Library) {
      filteredSubCategories.sort(
          (a, b) => _getTopCategoryOrder(a).compareTo(_getTopCategoryOrder(b)));
    } else {
      filteredSubCategories.sort((a, b) =>
          _normalizeOrder(a.order).compareTo(_normalizeOrder(b.order)));
    }

    if (_depth != 0) {
      // Add books (limit to 20 for performance)
      final bookWidgets =
          filteredBooks.map((book) => _buildBookItem(book)).toList();
      items.add(MyGridView(items: bookWidgets));

      // If there are more books, show a 'load more' widget
      if (filteredBooks.length > 20) {
        items.add(Center(
            child: TextButton(
          onPressed: () => _showAllBooksDialog(filteredBooks),
          child: Text('הצג עוד ${filteredBooks.length - 20} פריטים'),
        )));
      }

      // Add subcategories
      for (Category subCategory in filteredSubCategories) {
        final subFilteredBooks = subCategory.books.toList();
        final subFilteredCategories = subCategory.subCategories.toList();

        subFilteredBooks.sort((a, b) => a.order.compareTo(b.order));
        subFilteredCategories.sort((a, b) => a.order.compareTo(b.order));

        items.add(Center(child: HeaderItem(category: subCategory)));

        // בניית כל הפריטים של תת-הקטגוריה מראש (הגבלה ל-20 פריטים)
        final subCategoryItems = <Widget>[
          ...subFilteredBooks.map((book) => _buildBookItem(book)),
          ...subFilteredCategories.map(
            (cat) => CategoryGridItem(
              category: cat,
              onCategoryClickCallback: () => _openCategory(cat),
            ),
          ),
        ];

        if (subFilteredBooks.length > 20) {
          subCategoryItems.add(Center(
              child: TextButton(
            onPressed: () => _showAllBooksDialog(subFilteredBooks),
            child: Text('הצג עוד ${subFilteredBooks.length - 20} פריטים'),
          )));
        }

        items.add(MyGridView(items: subCategoryItems));
      }
    } else {
      // בניית כל הפריטים מראש אך עם הגבלה ל-20 פריטים להצגה ראשונית
      final displayedBooks = filteredBooks.map((book) => _buildBookItem(book));
      final categoryItems = <Widget>[
        ...displayedBooks,
        ...filteredSubCategories.map(
          (cat) => CategoryGridItem(
            category: cat,
            onCategoryClickCallback: () => _openCategory(cat),
          ),
        ),
      ];

      items.add(MyGridView(items: categoryItems));

      if (filteredBooks.length > 20) {
        items.add(Center(
            child: TextButton(
          onPressed: () => _showAllBooksDialog(filteredBooks),
          child: Text('הצג עוד ${filteredBooks.length - 20} פריטים'),
        )));
      }
    }

    return items;
  }

  Widget _buildBookItem(Book book, {bool showTopics = false}) {
    if (book is ExternalLibraryBook) {
      return BookGridItem(
        book: book,
        onBookClickCallback: () => _openOtzarBook(book),
        showTopics: showTopics,
      );
    }

    return BlocBuilder<LibraryBloc, LibraryState>(
      buildWhen: (previous, current) {
        // רק אם הספר שנבחר השתנה ואחד מהם הוא הספר הנוכחי
        return (previous.previewBook != current.previewBook) &&
            (previous.previewBook == book || current.previewBook == book);
      },
      builder: (context, state) {
        final isSelected = state.previewBook == book;

        return GestureDetector(
          onDoubleTap: () {
            final index = book is PdfBook ? 1 : 0;
            _openBookInReader(book, index);
          },
          child: Container(
            decoration: isSelected
                ? BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  )
                : null,
            child: BookGridItem(
              book: book,
              showTopics: showTopics,
              onBookClickCallback: () {
                // אם תצוגה מקדימה מוצגת - הצג את הספר בתצוגה
                // אחרת - פתח את הספר בעיון
                final settingsState = context.read<SettingsBloc>().state;
                if (settingsState.libraryShowPreview) {
                  _showBookPreview(book);
                } else {
                  final index = book is PdfBook ? 1 : 0;
                  _openBookInReader(book, index);
                }
              },
              onBookDeleted: () {
                // רענון הספרייה לאחר מחיקת ספר
                // בדיקה שה-context עדיין בתוקף לאחר מחיקה אסינכרונית
                if (context.mounted) {
                  context.read<LibraryBloc>().add(RefreshLibrary());
                }
              },
            ),
          ),
        );
      },
    );
  }

  void _showBookPreview(Book book) {
    context.read<LibraryBloc>().add(SelectBookForPreview(book));
  }

  /// בניית תצוגת רשימה לתוצאות חיפוש
  Widget _buildSearchListView(List<Book> books) {
    return ListView.builder(
      itemCount: books.length,
      itemBuilder: (context, index) {
        return _buildListBookItem(books[index], 0);
      },
    );
  }

  /// בניית תצוגת רשימה עם עץ מתרחב
  Widget _buildListView(Category category) {
    return ListView(
      children: _buildCategoryTree(category, 0),
    );
  }

  /// בניית עץ קטגוריות ברקורסיבית
  List<Widget> _buildCategoryTree(Category category, int level) {
    List<Widget> widgets = [];

    final filteredBooks = category.books.toList();
    final filteredSubCategories = category.subCategories.toList();

    // מיון
    filteredBooks.sort((a, b) => a.order.compareTo(b.order));
    if (category is Library) {
      filteredSubCategories.sort(
          (a, b) => _getTopCategoryOrder(a).compareTo(_getTopCategoryOrder(b)));
    } else {
      filteredSubCategories.sort((a, b) =>
          _normalizeOrder(a.order).compareTo(_normalizeOrder(b.order)));
    }

    // הוספת תת-קטגוריות לפני הספרים
    for (final subCategory in filteredSubCategories) {
      final isExpanded = _expandedCategories.contains(subCategory.path);

      widgets.add(_buildListCategoryItem(subCategory, level, isExpanded));

      // אם הקטגוריה פתוחה, הוסף את התוכן שלה
      if (isExpanded) {
        widgets.addAll(_buildCategoryTree(subCategory, level + 1));
      }
    }

    // הוספת ספרים בקטגוריה הנוכחית אחרי התיקיות (מוגבל ל-20 פריטים)
    final int displayLimit = 500;
    for (int i = 0; i < filteredBooks.length && i < displayLimit; i++) {
      widgets.add(_buildListBookItem(filteredBooks[i], level));
    }
    if (filteredBooks.length > displayLimit) {
      final remaining = filteredBooks.length - displayLimit;
      widgets.add(InkWell(
        onTap: () => _showAllBooksDialog(filteredBooks),
        child: Container(
          padding: EdgeInsets.only(
            right: 16.0 + (level * 24.0),
            left: 16.0,
            top: 10.0,
            bottom: 10.0,
          ),
          child: Text('הצג עוד $remaining פריטים',
              style: TextStyle(color: Theme.of(context).colorScheme.primary)),
        ),
      ));
    }

    return widgets;
  }

  /// פריט קטגוריה בתצוגת רשימה
  Widget _buildListCategoryItem(Category category, int level, bool isExpanded) {
    return InkWell(
      onTap: () {
        setState(() {
          if (isExpanded) {
            _expandedCategories.remove(category.path);
          } else {
            _expandedCategories.add(category.path);
          }
        });
      },
      child: Container(
        padding: EdgeInsets.only(
          right: 16.0 + (level * 24.0),
          left: 16.0,
          top: 12.0,
          bottom: 12.0,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isExpanded
                  ? FluentIcons.folder_open_24_filled
                  : FluentIcons.folder_24_regular,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                category.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            Icon(
              isExpanded
                  ? FluentIcons.chevron_up_24_regular
                  : FluentIcons.chevron_down_24_regular,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  /// פריט ספר בתצוגת רשימה
  Widget _buildListBookItem(Book book, int level) {
    if (book is ExternalLibraryBook) {
      return _buildExternalBookListItem(book, level);
    }

    return BlocBuilder<LibraryBloc, LibraryState>(
      buildWhen: (previous, current) {
        return (previous.previewBook != current.previewBook) &&
            (previous.previewBook == book || current.previewBook == book);
      },
      builder: (context, state) {
        final isSelected = state.previewBook == book;

        return InkWell(
          onTap: () {
            // אם תצוגה מקדימה מוצגת - הצג את הספר בתצוגה
            // אחרת - פתח את הספר בעיון
            final settingsState = context.read<SettingsBloc>().state;
            if (settingsState.libraryShowPreview) {
              _showBookPreview(book);
            } else {
              final index = book is PdfBook ? 1 : 0;
              _openBookInReader(book, index);
            }
          },
          onDoubleTap: () {
            final index = book is PdfBook ? 1 : 0;
            _openBookInReader(book, index);
          },
          child: Container(
            padding: EdgeInsets.only(
              right: 16.0 + (level * 24.0), // אותה הזחה כמו תיקיות
              left: 16.0,
              top: 10.0,
              bottom: 10.0,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.3)
                  : null,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  book is PdfBook
                      ? FluentIcons.document_pdf_24_regular
                      : FluentIcons.document_text_24_regular,
                  color: Theme.of(context).colorScheme.secondary,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      if (book.author != null && book.author!.isNotEmpty)
                        Text(
                          book.author!,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// פריט ספר חיצוני בתצוגת רשימה
  Widget _buildExternalBookListItem(ExternalLibraryBook book, int level) {
    return InkWell(
      onTap: () => _openOtzarBook(book),
      child: Container(
        padding: EdgeInsets.only(
          right: 16.0 + (level * 24.0) + 32.0,
          left: 16.0,
          top: 10.0,
          bottom: 10.0,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Image.asset(
              book.link.toString().contains('tablet.otzar.org')
                  ? 'assets/logos/otzar.ico'
                  : 'assets/logos/hebrew_books.png',
              width: 18,
              height: 18,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: const TextStyle(
                      fontSize: 14,
                    ),
                  ),
                  if (book.author != null && book.author!.isNotEmpty)
                    Text(
                      book.author!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              FluentIcons.open_24_regular,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  void _openBookInReader(Book book, int index) {
    openBook(context, book, index, '');
  }

  void _openCategory(Category category) {
    setState(() => _depth++);
    context.read<LibraryBloc>().add(NavigateToCategory(category));
    _refocusSearchBar();
  }

  void _openOtzarBook(ExternalLibraryBook book) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return OtzarBookDialog(book: book);
      },
    );
    _refocusSearchBar();
  }

  void _showAllBooksDialog(List<Book> books) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('כל הספרים (${books.length})'),
          content: SizedBox(
            width: 600,
            height: 400,
            child: ListView.builder(
              itemCount: books.length,
              itemBuilder: (context, index) {
                return _buildListBookItem(books[index], 0);
              },
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

  List<String> _getAllTopics(List<Book> books) {
    final Set<String> topics = {};
    for (final book in books) {
      topics.addAll(book.topics.split(', '));
    }
    return topics.toList();
  }

  void _update(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
  ) {
    final searchText =
        context.read<FocusRepository>().librarySearchController.text;
    // Remove all quotation marks from the search query
    final cleanSearchText = searchText.replaceAll('"', '');

    context.read<LibraryBloc>().add(
          UpdateSearchQuery(cleanSearchText),
        );
    _searchWithSettings(context, settingsState);
    setState(() {});
    _refocusSearchBar();
  }

  void _searchWithSettings(BuildContext context, SettingsState settingsState) {
    context.read<LibraryBloc>().add(
          SearchBooks(
            showHebrewBooks: settingsState.showExternalBooks &&
                settingsState.showHebrewBooks,
            showOtzarHachochma: settingsState.showExternalBooks &&
                settingsState.showOtzarHachochma,
          ),
        );
  }

  void _refocusSearchBar({bool selectAll = false}) {
    final focusRepository = context.read<FocusRepository>();
    focusRepository.requestLibrarySearchFocus(selectAll: selectAll);
  }

  /// בניית כפתורי הפעולה של הספרייה עם רכיב רספונסיבי
  Widget _buildLibraryActions(
      BuildContext context, LibraryState state, SettingsState settingsState) {
    final screenWidth = MediaQuery.of(context).size.width;
    int maxButtons;

    if (screenWidth < 400) {
      maxButtons = 2; // מינימום 2 כדי להשאיר סינכרון מחוץ לתפריט
    } else if (screenWidth < 500) {
      maxButtons = 2; // 2 כפתורים + "..." במסכים קטנים
    } else if (screenWidth < 600) {
      maxButtons = 3; // 3 כפתורים + "..." במסכים בינוניים קטנים
    } else if (screenWidth < 700) {
      maxButtons = 4; // 4 כפתורים + "..." במסכים בינוניים
    } else if (screenWidth < 900) {
      maxButtons = 5; // 5 כפתורים + "..." במסכים גדולים
    } else {
      maxButtons = 6; // כל הכפתורים במסכים רחבים
    }

    return ResponsiveActionBar(
      key: ValueKey('action-bar-offline-${settingsState.isOfflineMode}'),
      actions: _buildPrioritizedLibraryActions(context, state, settingsState),
      alwaysInMenu:
          _buildAlwaysInMenuLibraryActions(context, state, settingsState),
      originalOrder:
          _buildOriginalOrderLibraryActions(context, state, settingsState),
      maxVisibleButtons: maxButtons,
      overflowOnRight: true, // כפתור "..." ימני במסך הספרייה
    );
  }

  List<ActionButtonData> _buildAlwaysInMenuLibraryActions(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
  ) {
    return <ActionButtonData>[];
  }

  /// בניית כפתור סינכרון - משותף לשתי הפונקציות
  ActionButtonData _buildSyncActionButton() {
    return ActionButtonData(
      widget: BlocProvider.value(
        value: _fileSyncBloc,
        child: BlocListener<FileSyncBloc, FileSyncState>(
          listener: (context, syncState) {
            if ((syncState.status == FileSyncStatus.completed ||
                    syncState.status == FileSyncStatus.error) &&
                syncState.hasNewSync) {
              context.read<LibraryBloc>().add(RefreshLibrary());
            }
          },
          child: const SyncIconButton(),
        ),
      ),
      icon: FluentIcons.arrow_sync_24_regular,
      tooltip: 'סינכרון',
      onPressed: () {
        // הפעולה מטופלת ב-SyncIconButton
      },
    );
  }

  /// בניית רשימת כפתורים בסדר המקורי (כמו במסך הרחב)
  List<ActionButtonData> _buildOriginalOrderLibraryActions(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
  ) {
    return [
      // חזור לתיקיה קודמת (ראשון במסך הרחב)
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(FluentIcons.arrow_up_24_regular),
          tooltip: 'חזרה לתיקיה הקודמת',
          onPressed: () {
            // בתצוגת רשימה - סגור את הקטגוריה האחרונה שנפתחה
            if (settingsState.libraryViewMode == 'list' &&
                _expandedCategories.isNotEmpty) {
              setState(() {
                _expandedCategories.remove(_expandedCategories.last);
              });
            }
            // בתצוגת רשת - חזור לקטגוריה הקודמת
            else if (state.currentCategory?.parent != null) {
              setState(() {
                _depth = _depth > 0 ? _depth - 1 : 0;
              });
              context.read<LibraryBloc>().add(NavigateUp());
              context.read<LibraryBloc>().add(const SearchBooks());
              _refocusSearchBar(selectAll: true);
            }
          },
        ),
        icon: FluentIcons.arrow_up_24_regular,
        tooltip: 'חזרה לתיקיה הקודמת',
        onPressed: () {
          // בתצוגת רשימה - סגור את הקטגוריה האחרונה שנפתחה
          if (settingsState.libraryViewMode == 'list' &&
              _expandedCategories.isNotEmpty) {
            setState(() {
              _expandedCategories.remove(_expandedCategories.last);
            });
          }
          // בתצוגת רשת - חזור לקטגוריה הקודמת
          else if (state.currentCategory?.parent != null) {
            setState(() {
              _depth = _depth > 0 ? _depth - 1 : 0;
            });
            context.read<LibraryBloc>().add(NavigateUp());
            context.read<LibraryBloc>().add(const SearchBooks());
            _refocusSearchBar(selectAll: true);
          }
        },
      ),

      // חזרה לתיקיה ראשית
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(FluentIcons.home_24_regular),
          tooltip: 'חזרה לתיקיה הראשית',
          onPressed: () {
            setState(() {
              _depth = 0;
              _expandedCategories.clear(); // נקה את העץ הפתוח
            });
            context.read<LibraryBloc>().add(LoadLibrary());
            context.read<FocusRepository>().librarySearchController.clear();
            _update(context, state, settingsState);
            _refocusSearchBar(selectAll: true);
          },
        ),
        icon: FluentIcons.home_24_regular,
        tooltip: 'חזרה לתיקיה הראשית',
        onPressed: () {
          setState(() {
            _depth = 0;
            _expandedCategories.clear(); // נקה את העץ הפתוח
          });
          context.read<LibraryBloc>().add(LoadLibrary());
          context.read<FocusRepository>().librarySearchController.clear();
          _update(context, state, settingsState);
          _refocusSearchBar(selectAll: true);
        },
      ),

      // סינכרון - מוצג רק אם מצב אופליין לא מופעל
      if (!settingsState.isOfflineMode) _buildSyncActionButton(),

      // טעינה מחדש
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(FluentIcons.arrow_clockwise_24_regular),
          tooltip: 'טעינה מחדש של רשימת הספרים',
          onPressed: () {
            context.read<LibraryBloc>().add(RefreshLibrary());
          },
        ),
        icon: FluentIcons.arrow_clockwise_24_regular,
        tooltip: 'טעינה מחדש של רשימת הספרים',
        onPressed: () {
          context.read<LibraryBloc>().add(RefreshLibrary());
        },
      ),
    ];
  }

  /// בניית רשימת כפתורים לפי סדר עדיפות (החשוב ביותר ראשון)
  List<ActionButtonData> _buildPrioritizedLibraryActions(
    BuildContext context,
    LibraryState state,
    SettingsState settingsState,
  ) {
    return [
      // 1) חזור לתיקיה קודמת + סינכרון (חייב להיות תמיד מחוץ לתפריט)
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(FluentIcons.arrow_up_24_regular),
          tooltip: 'חזרה לתיקיה הקודמת',
          onPressed: () {
            // בתצוגת רשימה - סגור את הקטגוריה האחרונה שנפתחה
            if (settingsState.libraryViewMode == 'list' &&
                _expandedCategories.isNotEmpty) {
              setState(() {
                _expandedCategories.remove(_expandedCategories.last);
              });
            }
            // בתצוגת רשת - חזור לקטגוריה הקודמת
            else if (state.currentCategory?.parent != null) {
              setState(() {
                _depth = _depth > 0 ? _depth - 1 : 0;
              });
              context.read<LibraryBloc>().add(NavigateUp());
              context.read<LibraryBloc>().add(const SearchBooks());
              _refocusSearchBar(selectAll: true);
            }
          },
        ),
        icon: FluentIcons.arrow_up_24_regular,
        tooltip: 'חזרה לתיקיה הקודמת',
        onPressed: () {
          // בתצוגת רשימה - סגור את הקטגוריה האחרונה שנפתחה
          if (settingsState.libraryViewMode == 'list' &&
              _expandedCategories.isNotEmpty) {
            setState(() {
              _expandedCategories.remove(_expandedCategories.last);
            });
          }
          // בתצוגת רשת - חזור לקטגוריה הקודמת
          else if (state.currentCategory?.parent != null) {
            setState(() {
              _depth = _depth > 0 ? _depth - 1 : 0;
            });
            context.read<LibraryBloc>().add(NavigateUp());
            context.read<LibraryBloc>().add(const SearchBooks());
            _refocusSearchBar(selectAll: true);
          }
        },
      ),

      // סינכרון - עדיפות גבוהה כדי שלא יכנס לתפריט "..."
      if (!settingsState.isOfflineMode) _buildSyncActionButton(),

      ActionButtonData(
        widget: IconButton(
          icon: const Icon(FluentIcons.home_24_regular),
          tooltip: 'חזרה לתיקיה הראשית',
          onPressed: () {
            setState(() {
              _depth = 0;
              _expandedCategories.clear(); // נקה את העץ הפתוח
            });
            context.read<LibraryBloc>().add(LoadLibrary());
            context.read<FocusRepository>().librarySearchController.clear();
            _update(context, state, settingsState);
            _refocusSearchBar(selectAll: true);
          },
        ),
        icon: FluentIcons.home_24_regular,
        tooltip: 'חזרה לתיקיה הראשית',
        onPressed: () {
          setState(() {
            _depth = 0;
            _expandedCategories.clear(); // נקה את העץ הפתוח
          });
          context.read<LibraryBloc>().add(LoadLibrary());
          context.read<FocusRepository>().librarySearchController.clear();
          _update(context, state, settingsState);
          _refocusSearchBar(selectAll: true);
        },
      ),

      // 5) טעינה מחדש של רשימת הספרים
      ActionButtonData(
        widget: IconButton(
          icon: const Icon(FluentIcons.arrow_clockwise_24_regular),
          tooltip: 'טעינה מחדש של רשימת הספרים',
          onPressed: () {
            context.read<LibraryBloc>().add(RefreshLibrary());
          },
        ),
        icon: FluentIcons.arrow_clockwise_24_regular,
        tooltip: 'טעינה מחדש של רשימת הספרים',
        onPressed: () {
          context.read<LibraryBloc>().add(RefreshLibrary());
        },
      ),
    ];
  }
}

/// Widget שמציג טקסט "טוען ספרייה" עם שלוש נקודות מתחלפות
class _LoadingDotsText extends StatefulWidget {
  const _LoadingDotsText();

  @override
  State<_LoadingDotsText> createState() => _LoadingDotsTextState();
}

class _LoadingDotsTextState extends State<_LoadingDotsText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // חישוב כמה נקודות להציג (0-3)
        final progress = _controller.value;
        int dots;
        if (progress < 0.25) {
          dots = 0;
        } else if (progress < 0.5) {
          dots = 1;
        } else if (progress < 0.75) {
          dots = 2;
        } else {
          dots = 3;
        }

        // יצירת מחרוזת עם 3 תווים: נקודות + רווחים
        final dotsString = '.' * dots + ' ' * (3 - dots);

        return Text(
          'טוען ספרייה$dotsString',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        );
      },
    );
  }
}
