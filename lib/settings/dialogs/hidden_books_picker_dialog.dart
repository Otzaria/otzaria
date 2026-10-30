import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/settings/dialogs/list_dialog_frame.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// בוחר ספרים וקטגוריות להסתרה מתוך הספרייה.
Future<HiddenLibrarySelection?> showHiddenBooksPickerDialog({
  required BuildContext context,
  required Library library,
  required HiddenLibrarySelection hidden,
}) {
  return showDialog<HiddenLibrarySelection>(
    context: context,
    builder: settingsDialogBuilder(
      context,
      (_) => _HiddenBooksPickerDialog(library: library, hidden: hidden),
    ),
  );
}

class _HiddenBooksPickerDialog extends StatefulWidget {
  final Library library;
  final HiddenLibrarySelection hidden;

  const _HiddenBooksPickerDialog({required this.library, required this.hidden});

  @override
  State<_HiddenBooksPickerDialog> createState() =>
      _HiddenBooksPickerDialogState();
}

class _CategoryRow {
  final String title;
  final String path;
  final int depth;

  _CategoryRow(Category category)
    : title = category.title,
      path = category.path,
      depth = category.path.split('/').length - 2;

  bool matches(String query) =>
      title.toLowerCase().contains(query) || path.toLowerCase().contains(query);
}

class _PickerRow {
  final String key;
  final String title;
  final String details;
  final String haystack;
  final String categoryPath;

  _PickerRow(Book book, this.categoryPath)
    : key = PerBookSettings.bookKey(book),
      title = book.title,
      details = [
        if ((book.author ?? '').isNotEmpty) book.author!,
        categoryPath,
      ].join(' · '),
      haystack = '${book.title} ${book.author ?? ''} $categoryPath'
          .toLowerCase();

  bool matches(String query) => haystack.contains(query.toLowerCase());
}

class _HiddenBooksPickerDialogState extends State<_HiddenBooksPickerDialog> {
  late final List<_PickerRow> _rows;
  late List<_PickerRow> _visible;
  late final List<_CategoryRow> _categories;
  late List<_CategoryRow> _visibleCategories;
  late final Set<String> _selectedBooks;
  late final Set<String> _selectedCategories;
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _showCategories = false;

  bool _hiddenOnly = false;

  String? _hidingCategory(String path, {bool includeSelf = true}) {
    var current = includeSelf ? path : path.substring(0, path.lastIndexOf('/'));
    while (current.isNotEmpty) {
      if (_selectedCategories.contains(current)) return current;
      final separator = current.lastIndexOf('/');
      if (separator <= 0) break;
      current = current.substring(0, separator);
    }
    return null;
  }

  void _addCategory(Category category) {
    _categories.add(_CategoryRow(category));
    _rows.addAll(category.books.map((book) => _PickerRow(book, category.path)));
    for (final child in category.subCategories) {
      _addCategory(child);
    }
  }

  @override
  void initState() {
    super.initState();
    _rows = [];
    _categories = [];
    for (final category in widget.library.subCategories) {
      _addCategory(category);
    }
    _selectedBooks = {...widget.hidden.bookKeys};
    _selectedCategories = {...widget.hidden.categoryPaths};
    _visible = _rows;
    _visibleCategories = _categories;
    _search.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _search.removeListener(_applyFilter);
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final query = _search.text.trim().toLowerCase();
    setState(() {
      _visible = _rows
          .where(
            (row) =>
                (query.isEmpty || row.matches(query)) &&
                (!_hiddenOnly ||
                    _selectedBooks.contains(row.key) ||
                    _hidingCategory(row.categoryPath) != null),
          )
          .toList();
      _visibleCategories = _categories
          .where(
            (row) =>
                (query.isEmpty || row.matches(query)) &&
                (!_hiddenOnly ||
                    _selectedCategories.contains(row.path) ||
                    _hidingCategory(row.path, includeSelf: false) != null),
          )
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListDialogFrame(
      icon: OtzariaIcons.book_delete_24_regular,
      title: context.settingsText('בחירת ספרים וקטגוריות להסתרה'),
      counter: context.settingsText(
        'בחירות ישירות: {count}',
        args: {
          'count': _showCategories
              ? _selectedCategories.length
              : _selectedBooks.length,
        },
      ),
      children: [
        const SizedBox(height: AppTokens.spaceMD),
        AppSegmentedControl<bool>(
          options: [
            SegmentOption(value: false, label: context.settingsText('ספרים')),
            SegmentOption(
              value: true,
              label: context.settingsText('קטגוריות'),
            ),
          ],
          currentValue: _showCategories,
          expandToFillWidth: true,
          onChanged: (value) {
            setState(() => _showCategories = value);
            _search.clear();
            if (_scroll.hasClients) _scroll.jumpTo(0);
          },
        ),
        if (_showCategories)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              context.settingsText(
                'הסתרת קטגוריה כוללת את תתי־הקטגוריות וכל הספרים שבתוכה',
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: AppTokens.spaceMD),
        OtzariaSearchField(
          controller: _search,
          autofocus: true,
          hintText: _showCategories
              ? context.settingsText('חיפוש קטגוריה לפי שם או נתיב')
              : context.settingsText('חיפוש לפי שם, מחבר או קטגוריה'),
        ),
        const SizedBox(height: AppTokens.spaceSM),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ActionButton.ghost(
            icon: _hiddenOnly
                ? FluentIcons.eye_off_24_regular
                : FluentIcons.eye_24_regular,
            text: _hiddenOnly
                ? _showCategories
                      ? context.settingsText('הצג את כל הקטגוריות')
                      : context.settingsText('הצג את כל הספרים')
                : context.settingsText('הצג רק מוסתרים'),
            onPressed: () {
              _hiddenOnly = !_hiddenOnly;
              _applyFilter();
            },
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child:
              (_showCategories ? _visibleCategories.isEmpty : _visible.isEmpty)
              ? OtzariaEmptyState(
                  isCompact: true,
                  icon: OtzariaIcons.search_in_library_24_regular,
                  title: _showCategories
                      ? context.settingsText('לא נמצאו קטגוריות')
                      : context.settingsText('לא נמצאו ספרים'),
                )
              : ListDialogCard(
                  child: Scrollbar(
                    controller: _scroll,
                    thumbVisibility: true,
                    // שכבת Material שקופה: בלעדיה הקו התחתון של שורת הרשימה
                    // (ListTile.shape) נצייר מחוץ לאזור הגלילה, מעל הכפתורים.
                    child: Material(
                      type: MaterialType.transparency,
                      child: ListView.builder(
                        controller: _scroll,
                        // גובה שורה קבוע: קפיצת פס הגלילה לא בונה את כל השורות בדרך
                        prototypeItem: const CheckboxListTile(
                          value: false,
                          onChanged: null,
                          title: Text(''),
                          subtitle: Text(''),
                        ),
                        itemCount: _showCategories
                            ? _visibleCategories.length
                            : _visible.length,
                        itemBuilder: (_, i) {
                          final category = _showCategories
                              ? _visibleCategories[i]
                              : null;
                          final book = category == null ? _visible[i] : null;
                          final key = category?.path ?? book!.key;
                          final selected = category == null
                              ? _selectedBooks
                              : _selectedCategories;
                          final inherited = _hidingCategory(
                            category?.path ?? book!.categoryPath,
                            includeSelf: category == null,
                          );
                          return CheckboxListTile(
                            shape: Border(
                              bottom: listDialogRowDivider(context),
                            ),
                            value: inherited != null || selected.contains(key),
                            title: Padding(
                              padding: EdgeInsetsDirectional.only(
                                start: (category?.depth ?? 0) * 12.0,
                              ),
                              child: Text(
                                category?.title ?? book!.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: AppTokens.fontMD + 1,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                            subtitle: Row(
                              spacing: 12,
                              children: [
                                Flexible(
                                  child: Text(
                                    category?.path ?? book!.details,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: AppTokens.fontSM,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                if (inherited != null)
                                  Flexible(
                                    child: Text(
                                      context.settingsText(
                                        'מוסתר דרך {category}',
                                        args: {'category': inherited},
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: AppTokens.fontSM,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            secondary: category == null
                                ? const Icon(OtzariaIcons.book_24_regular)
                                : const Icon(FluentIcons.folder_24_regular),
                            onChanged: inherited != null
                                ? null
                                : (checked) {
                                    setState(() {
                                      if (checked == true) {
                                        selected.add(key);
                                      } else {
                                        selected.remove(key);
                                      }
                                    });
                                    if (_hiddenOnly) _applyFilter();
                                  },
                          );
                        },
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: AppTokens.spaceMD),
        Row(
          children: [
            ActionButton.recommended(
              text: context.settingsText('שמור'),
              onPressed: () => Navigator.of(context).pop(
                HiddenLibrarySelection(
                  bookKeys: _selectedBooks,
                  categoryPaths: _selectedCategories,
                ),
              ),
            ),
            const Spacer(),
            ActionButton.ghost(
              text: context.settingsText('ביטול'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }
}
