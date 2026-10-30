import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/feedback/loading_indicator.dart';
import 'package:otzaria/widgets/feedback/tool_empty_state.dart';
import 'package:otzaria/widgets/layout/meta_chip.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/tools_messages.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/navigation/talmud_bavli_open_format.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import '../providers/shamor_zachor_data_provider.dart';

/// פותח דיאלוג לבחירת ספרים מעץ הספרייה והוספתם למעקב בשמור וזכור.
///
/// [dataProvider] מועבר במפורש כי הוא Provider מקומי שאינו זמין מעל ה-Navigator.
Future<void> showAddBooksToTrackingDialog({
  required BuildContext context,
  required ShamorZachorDataProvider dataProvider,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => AddBooksToTrackingDialog(dataProvider: dataProvider),
  );
}

/// דיאלוג בחירת ספרים מעץ הספרייה להוספה לרשימת "בתהליך" בשמור וזכור.
class AddBooksToTrackingDialog extends StatefulWidget {
  final ShamorZachorDataProvider dataProvider;

  const AddBooksToTrackingDialog({super.key, required this.dataProvider});

  @override
  State<AddBooksToTrackingDialog> createState() =>
      _AddBooksToTrackingDialogState();
}

class _AddBooksToTrackingDialogState extends State<AddBooksToTrackingDialog> {
  static const int _minSearchQueryLength = 2;

  final TextEditingController _searchController = TextEditingController();
  final Map<String, bool> _expansionState = {};
  final Map<int, Book> _selectedBooks = {};
  bool _isAdding = false;

  String get _query => _searchController.text.trim();
  bool get _hasActiveSearch => _query.length >= _minSearchQueryLength;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Category? _talmudTextTitlesLibrary;
  Set<String>? _talmudTextTitlesCache;

  /// כותרות מהדורות הטקסט של מסכתות הבבלי, ממוטמנות פר-מופע ספרייה.
  Set<String> _talmudTextTitles(Library library) {
    if (!identical(library, _talmudTextTitlesLibrary)) {
      _talmudTextTitlesLibrary = library;
      _talmudTextTitlesCache = talmudBavliTextTitles(library);
    }
    return _talmudTextTitlesCache!;
  }

  /// מסתיר מהרשימה מהדורת PDF מצורפת של מסכת בבלי — היא שואלת את מזהה ספר
  /// הטקסט, ולכן מעקב עליה היה כפילות של אותה שורה בדיוק.
  List<Book> _visibleBooks(List<Book> books, Set<String> talmudTextTitles) =>
      books
          .where((b) => !isTalmudBavliPdfLibraryDuplicate(b, talmudTextTitles))
          .toList();

  bool _isTracked(Book book) =>
      book.id != null && widget.dataProvider.isBookTrackedById(book.id!);

  /// שמור וזכור נשען על מזהי seforim.db בלבד; ספר אישי/חיצוני מחזיק מזהה
  /// ממרחב אחר שעלול להתנגש עם ספר רשמי אקראי, ולכן אינו נתמך.
  bool _isOfficialSeforimBook(Book book) =>
      book.id != null &&
      book.isOfficialLibraryBook &&
      !DatabaseConstants.isTalmudBavliPdfExternalLibraryId(
        book.externalLibraryId,
      );

  void _toggleBook(Book book, bool selected) {
    if (!_isOfficialSeforimBook(book)) return;
    setState(() {
      if (selected) {
        _selectedBooks[book.id!] = book;
      } else {
        _selectedBooks.remove(book.id);
      }
    });
  }

  Future<void> _addSelected() async {
    if (_selectedBooks.isEmpty) {
      UiSnack.show(ToolsMessages.noBooksSelectedToAdd);
      return;
    }

    setState(() => _isAdding = true);

    try {
      final result = await widget.dataProvider.addCustomBooks(
        _selectedBooks.values
            .map((b) => (id: b.id, bookName: b.title, categoryId: b.categoryId))
            .toList(),
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      if (result.added > 0) {
        UiSnack.show(ToolsMessages.booksAddedToTracking(result.added));
      }
      if (result.failed > 0) {
        UiSnack.showError(ToolsMessages.booksAddFailed(result.failed));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAdding = false);
      UiSnack.showError(ToolsMessages.booksAddError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDialogHeader(
              icon: FluentIcons.library_24_regular,
              title: 'הוספת ספרים למעקב',
              subtitle:
                  'בחר ספרים מעץ הספרייה. הספרים שייבחרו יתווספו לרשימת "בתהליך".',
              closeEnabled: !_isAdding,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.spaceLG,
                  AppTokens.spaceMD,
                  AppTokens.spaceLG,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSearchField(),
                    const SizedBox(height: AppTokens.spaceMD),
                    Expanded(child: _buildBody(colorScheme)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTokens.spaceMD),
              child: Row(
                children: [
                  // ברוחב טלפון המספר מופיע בכפתור ההוספה עצמו.
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child:
                          _selectedBooks.isEmpty ||
                              MediaQuery.sizeOf(context).width < 520
                          ? null
                          : Padding(
                              padding: const EdgeInsetsDirectional.only(
                                start: AppTokens.spaceSM,
                              ),
                              child: MetaChip(
                                icon: FluentIcons.checkmark_circle_24_regular,
                                label: 'נבחרו ${_selectedBooks.length}',
                              ),
                            ),
                    ),
                  ),
                  ActionButton.neutral(
                    text: 'ביטול',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: AppTokens.spaceSM),
                  ActionButton.recommended(
                    text: _selectedBooks.isEmpty
                        ? 'הוסף'
                        : 'הוסף (${_selectedBooks.length})',
                    icon: FluentIcons.add_24_regular,
                    isLoading: _isAdding,
                    onPressed: _addSelected,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return OtzariaSearchField(
      controller: _searchController,
      autofocus: true,
      // מחפש בספרייה כולה, לא מסנן את הרשימה שעל המסך — ולכן העדשה
      // הממוקדת, אותה אחת שנושא שדה החיפוש של מסך הספרייה.
      icon: OtzariaIcons.search_in_library_24_regular,
      hintText: 'חיפוש ספר...',
      onChanged: (_) => setState(() {}),
      onClear: () => setState(() {}),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    return BlocBuilder<LibraryBloc, LibraryState>(
      builder: (context, state) {
        final library = state.library;
        final hasContent =
            library != null &&
            library.subCategories.any(
              (c) => c.books.isNotEmpty || c.subCategories.isNotEmpty,
            );

        if (!hasContent) {
          return const LoadingIndicator();
        }

        // Material and not a decorated box, so the tiles' ink is painted
        // above the card colour.
        return Material(
          color: AppSurfaces.card(context),
          shape: RoundedRectangleBorder(
            borderRadius: AppTokens.borderRadiusAll,
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: _hasActiveSearch
              ? _buildSearchResults(library, colorScheme)
              : _buildTree(library, colorScheme),
        );
      },
    );
  }

  Widget _buildTree(Library library, ColorScheme colorScheme) {
    final topCategories = [...library.subCategories]
      ..sort((a, b) => a.order.compareTo(b.order));

    final talmudTextTitles = _talmudTextTitles(library);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final category in topCategories)
          _buildCategoryNode(category, colorScheme, 0, talmudTextTitles),
      ],
    );
  }

  Widget _buildCategoryNode(
    Category category,
    ColorScheme colorScheme,
    int level,
    Set<String> talmudTextTitles,
  ) {
    final hasChildren =
        category.subCategories.isNotEmpty || category.books.isNotEmpty;
    if (!hasChildren) return const SizedBox.shrink();

    final isExpanded = _expansionState[category.path] ?? false;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => setState(() {
            _expansionState[category.path] = !isExpanded;
          }),
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: AppTokens.spaceMD + (level * AppTokens.spaceLG),
              end: AppTokens.spaceMD,
              top: AppTokens.spaceSM + 2,
              bottom: AppTokens.spaceSM + 2,
            ),
            child: Row(
              children: [
                RtlIcon(
                  isExpanded
                      ? FluentIcons.chevron_down_24_regular
                      : FluentIcons.chevron_left_24_regular,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppTokens.spaceSM),
                RtlIcon(
                  isExpanded
                      ? FluentIcons.folder_open_24_regular
                      : FluentIcons.folder_24_regular,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: AppTokens.spaceSM + 2),
                Expanded(
                  child: Text(
                    category.title,
                    style: TextStyle(
                      fontSize: AppTokens.fontMD + 1,
                      fontWeight: level == 0
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded) ...[
          for (final sub in [
            ...category.subCategories,
          ]..sort((a, b) => a.order.compareTo(b.order)))
            _buildCategoryNode(sub, colorScheme, level + 1, talmudTextTitles),
          for (final book in _visibleBooks(
            category.books,
            talmudTextTitles,
          )..sort((a, b) => a.order.compareTo(b.order)))
            _buildBookTile(book, colorScheme, level + 1),
        ],
      ],
    );
  }

  Widget _buildBookTile(Book book, ColorScheme colorScheme, int level) {
    final isSelectable = _isOfficialSeforimBook(book);
    final alreadyTracked = isSelectable && _isTracked(book);
    final isSelected = isSelectable && _selectedBooks.containsKey(book.id);
    final external = book.externalLibraryId;
    final isExternalCatalog =
        external != null &&
        external.isNotEmpty &&
        !DatabaseConstants.isBundledLibrarySource(external);
    final disabledReason = isSelectable
        ? null
        : book.isUserBook
        ? 'ספר אישי — לא נתמך במעקב'
        : isExternalCatalog
        ? 'ספר חיצוני — לא נתמך במעקב'
        : 'ספר ללא מזהה — לא נתמך במעקב';

    return Padding(
      padding: EdgeInsetsDirectional.only(start: level * AppTokens.spaceLG),
      child: CheckboxListTile(
        dense: true,
        value: alreadyTracked || isSelected,
        onChanged: alreadyTracked || !isSelectable
            ? null
            : (v) => _toggleBook(book, v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsetsDirectional.only(
          start: AppTokens.spaceSM,
          end: AppTokens.spaceMD,
        ),
        title: Row(
          children: [
            Icon(
              OtzariaIcons.book_24_regular,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppTokens.spaceSM),
            Expanded(
              child: Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTokens.fontMD + 1,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        subtitle: alreadyTracked || disabledReason != null
            ? Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: 18 + AppTokens.spaceSM,
                ),
                child: Text(
                  alreadyTracked ? 'כבר במעקב' : disabledReason!,
                  style: TextStyle(
                    fontSize: AppTokens.fontSM,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildSearchResults(Library library, ColorScheme colorScheme) {
    final query = _query;
    final matches = _visibleBooks(
      library.getAllBooks().where((b) => b.title.contains(query)).toList(),
      _talmudTextTitles(library),
    )..sort((a, b) => a.title.compareTo(b.title));

    if (matches.isEmpty) {
      return const ToolEmptyState(
        icon: OtzariaIcons.search_in_library_24_regular,
        message: 'לא נמצאו ספרים תואמים',
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: matches.length,
      itemBuilder: (context, index) =>
          _buildBookTile(matches[index], colorScheme, 0),
    );
  }
}
