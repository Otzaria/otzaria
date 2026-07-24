import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/tools_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
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

  bool _isTracked(Book book) =>
      book.id != null && widget.dataProvider.isBookTrackedById(book.id!);

  /// שמור וזכור נשען על מזהי seforim.db בלבד; ספר אישי/חיצוני מחזיק מזהה
  /// ממרחב אחר שעלול להתנגש עם ספר רשמי אקראי, ולכן אינו נתמך.
  bool _isOfficialSeforimBook(Book book) =>
      book.id != null &&
      !book.isUserBook &&
      (book.externalLibraryId == null || book.externalLibraryId!.isEmpty);

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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    FluentIcons.library_24_regular,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'הוספת ספרים למעקב',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'בחר ספרים מעץ הספרייה. הספרים שייבחרו יתווספו לרשימת "בתהליך".',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _buildSearchField(),
              const SizedBox(height: 12),
              Expanded(child: _buildBody(colorScheme)),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_selectedBooks.isNotEmpty)
                    Text(
                      'נבחרו ${_selectedBooks.length}',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  const Spacer(),
                  ActionButton.neutral(
                    text: 'ביטול',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return RtlTextField(
      controller: _searchController,
      autofocus: true,
      decoration: InputDecoration(
        hintText: 'חיפוש ספר...',
        prefixIcon: const Icon(FluentIcons.search_24_regular),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(FluentIcons.dismiss_24_regular),
                onPressed: () => setState(_searchController.clear),
              ),
        border: OutlineInputBorder(borderRadius: AppTokens.borderRadiusAll),
        isDense: true,
      ),
      onChanged: (_) => setState(() {}),
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
          return const Center(child: CircularProgressIndicator());
        }

        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: AppTokens.borderRadiusAll,
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

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final category in topCategories)
          _buildCategoryNode(category, colorScheme, 0),
      ],
    );
  }

  Widget _buildCategoryNode(
    Category category,
    ColorScheme colorScheme,
    int level,
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
            padding: EdgeInsets.only(
              right: 12.0 + (level * 16.0),
              left: 12.0,
              top: 10.0,
              bottom: 10.0,
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
                const SizedBox(width: 8),
                RtlIcon(
                  isExpanded
                      ? FluentIcons.folder_open_24_regular
                      : FluentIcons.folder_24_regular,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    category.title,
                    style: TextStyle(
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
            _buildCategoryNode(sub, colorScheme, level + 1),
          for (final book in [
            ...category.books,
          ]..sort((a, b) => a.order.compareTo(b.order)))
            _buildBookTile(book, colorScheme, level + 1),
        ],
      ],
    );
  }

  Widget _buildBookTile(Book book, ColorScheme colorScheme, int level) {
    final isSelectable = _isOfficialSeforimBook(book);
    final alreadyTracked = isSelectable && _isTracked(book);
    final isSelected = isSelectable && _selectedBooks.containsKey(book.id);
    final disabledReason = isSelectable
        ? null
        : book.isUserBook
        ? 'ספר אישי — לא נתמך במעקב'
        : (book.externalLibraryId != null && book.externalLibraryId!.isNotEmpty)
        ? 'ספר חיצוני — לא נתמך במעקב'
        : 'ספר ללא מזהה — לא נתמך במעקב';

    return Padding(
      padding: EdgeInsets.only(right: level * 16.0),
      child: CheckboxListTile(
        dense: true,
        value: alreadyTracked || isSelected,
        onChanged: alreadyTracked || !isSelectable
            ? null
            : (v) => _toggleBook(book, v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          book.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colorScheme.onSurface),
        ),
        subtitle: alreadyTracked || disabledReason != null
            ? Text(
                alreadyTracked ? 'כבר במעקב' : disabledReason!,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              )
            : null,
        secondary: RtlIcon(
          FluentIcons.book_24_regular,
          size: 18,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildSearchResults(Library library, ColorScheme colorScheme) {
    final query = _query;
    final matches =
        library.getAllBooks().where((b) => b.title.contains(query)).toList()
          ..sort((a, b) => a.title.compareTo(b.title));

    if (matches.isEmpty) {
      return Center(
        child: Text(
          'לא נמצאו ספרים תואמים',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
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
