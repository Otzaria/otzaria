import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
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
    final media = MediaQuery.of(context);
    final maxWidth = media.size.width * 0.9;

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth > 720 ? 720 : maxWidth,
          maxHeight: media.size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(OtzariaIcons.book_24_regular, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.settingsText('בחירת ספרים וקטגוריות להסתרה'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    context.settingsText(
                      'בחירות ישירות: {count}',
                      args: {
                        'count': _showCategories
                            ? _selectedCategories.length
                            : _selectedBooks.length,
                      },
                    ),
                    style:
                        Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(context.settingsText('ספרים')),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(context.settingsText('קטגוריות')),
                  ),
                ],
                selected: {_showCategories},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  setState(() => _showCategories = selection.single);
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
              const SizedBox(height: 12),
              RtlTextField(
                controller: _search,
                autofocus: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(OtzariaIcons.search_24_regular),
                  hintText: _showCategories
                      ? context.settingsText('חיפוש קטגוריה לפי שם או נתיב')
                      : context.settingsText('חיפוש לפי שם, מחבר או קטגוריה'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  icon: Icon(
                    _hiddenOnly
                        ? FluentIcons.eye_off_24_regular
                        : FluentIcons.eye_24_regular,
                    size: 18,
                  ),
                  label: Text(
                    _hiddenOnly
                        ? _showCategories
                              ? context.settingsText('הצג את כל הקטגוריות')
                              : context.settingsText('הצג את כל הספרים')
                        : context.settingsText('הצג רק מוסתרים'),
                  ),
                  onPressed: () {
                    _hiddenOnly = !_hiddenOnly;
                    _applyFilter();
                  },
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child:
                    (_showCategories
                        ? _visibleCategories.isEmpty
                        : _visible.isEmpty)
                    ? Center(
                        child: Text(
                          _showCategories
                              ? context.settingsText('לא נמצאו קטגוריות')
                              : context.settingsText('לא נמצאו ספרים'),
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      )
                    : Scrollbar(
                        controller: _scroll,
                        thumbVisibility: true,
                        child: ListView.separated(
                          controller: _scroll,
                          itemCount: _showCategories
                              ? _visibleCategories.length
                              : _visible.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            color: cs.surfaceContainerHighest,
                          ),
                          itemBuilder: (_, i) {
                            if (_showCategories) {
                              final row = _visibleCategories[i];
                              final inherited = _hidingCategory(
                                row.path,
                                includeSelf: false,
                              );
                              return CheckboxListTile(
                                value:
                                    inherited != null ||
                                    _selectedCategories.contains(row.path),
                                title: Padding(
                                  padding: EdgeInsetsDirectional.only(
                                    start: row.depth * 12.0,
                                  ),
                                  child: Text(row.title),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(row.path),
                                    if (inherited != null)
                                      Text(
                                        context.settingsText(
                                          'מוסתר דרך {category}',
                                          args: {'category': inherited},
                                        ),
                                      ),
                                  ],
                                ),
                                secondary: const Icon(
                                  FluentIcons.folder_24_regular,
                                ),
                                onChanged: inherited != null
                                    ? null
                                    : (checked) {
                                        setState(() {
                                          if (checked == true) {
                                            _selectedCategories.add(row.path);
                                          } else {
                                            _selectedCategories.remove(
                                              row.path,
                                            );
                                          }
                                        });
                                        if (_hiddenOnly) _applyFilter();
                                      },
                              );
                            }
                            final row = _visible[i];
                            final inherited = _hidingCategory(row.categoryPath);
                            return CheckboxListTile(
                              value:
                                  inherited != null ||
                                  _selectedBooks.contains(row.key),
                              title: Text(row.title),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(row.details),
                                  if (inherited != null)
                                    Text(
                                      context.settingsText(
                                        'מוסתר דרך {category}',
                                        args: {'category': inherited},
                                      ),
                                    ),
                                ],
                              ),
                              onChanged: inherited != null
                                  ? null
                                  : (checked) {
                                      setState(() {
                                        if (checked == true) {
                                          _selectedBooks.add(row.key);
                                        } else {
                                          _selectedBooks.remove(row.key);
                                        }
                                      });
                                      if (_hiddenOnly) _applyFilter();
                                    },
                            );
                          },
                        ),
                      ),
              ),
              const SizedBox(height: 12),
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
          ),
        ),
      ),
    );
  }
}
