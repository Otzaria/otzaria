import 'dart:convert';
import 'dart:typed_data';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/settings/dialogs/list_dialog_frame.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/utils/file/save_file_with_extension.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// פותח דיאלוג עם רשימת כל הספרים בספרייה, חיפוש, וייצוא ל-CSV.
Future<void> showBooksListDialog({
  required BuildContext context,
  required List<Book> books,
}) {
  return showDialog<void>(
    context: context,
    builder: settingsDialogBuilder(
      context,
      (_) => _BooksListDialog(books: books),
    ),
  );
}

class _BooksListDialog extends StatefulWidget {
  final List<Book> books;

  const _BooksListDialog({required this.books});

  @override
  State<_BooksListDialog> createState() => _BooksListDialogState();
}

class _BooksListDialogState extends State<_BooksListDialog> {
  late final List<_BookRow> _rows;
  late List<_BookRow> _visibleRows;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    // ה-Library Providers כבר ממיינים books ו-subCategories לפי order,
    // אז getAllBooks() מחזיר בסדר תצוגת הספרייה. שומרים על אותו סדר.
    _rows = widget.books.map(_BookRow.fromBook).toList();
    _visibleRows = _rows;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _visibleRows = query.isEmpty
          ? _rows
          : _rows.where((r) => r.matches(query)).toList();
    });
  }

  Future<void> _exportToCsv() async {
    final downloadsDirectory = await getDownloadsDirectory();
    if (!mounted) return;

    final csv = _buildCsv(_rows);
    final bytes = Uint8List.fromList(utf8.encode('\uFEFF$csv'));
    final path = await saveFileWithExtension(
      dialogTitle: context.settingsText('בחר מיקום לשמירת רשימת הספרים'),
      fileName: 'otzaria_books.csv',
      initialDirectory: downloadsDirectory?.path,
      extension: 'csv',
      bytes: bytes,
    );
    if (path == null || !mounted) return;

    setState(() => _isExporting = true);
    try {
      if (!mounted) return;
      UiSnack.show(SettingsMessages.booksListSaved(_rows.length));
    } catch (e) {
      if (!mounted) return;
      UiSnack.showError(SettingsMessages.fileSaveError(e));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListDialogFrame(
      icon: OtzariaIcons.book_24_regular,
      title: context.settingsText('רשימת הספרים'),
      counter: '${_visibleRows.length} / ${_rows.length}',
      children: [
        const SizedBox(height: 12),
        RtlTextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            prefixIcon: const Icon(OtzariaIcons.search_24_regular),
            hintText: context.settingsText(
              'חיפוש לפי שם, מחבר או קטגוריה',
            ),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _visibleRows.isEmpty
              ? Center(
                  child: Text(
                    context.settingsText('לא נמצאו ספרים'),
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                )
              : Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: ListView.separated(
                    controller: _scrollController,
                    itemCount: _visibleRows.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: cs.surfaceContainerHighest,
                    ),
                    itemBuilder: (_, i) => _BookListRow(
                      row: _visibleRows[i],
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ActionButton.recommended(
              text: context.settingsText('ייצוא ל-CSV'),
              icon: FluentIcons.arrow_download_24_regular,
              isLoading: _isExporting,
              onPressed: _exportToCsv,
            ),
            const Spacer(),
            ActionButton.neutral(
              text: context.settingsText('סגור'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }
}

class _BookListRow extends StatelessWidget {
  final _BookRow row;
  const _BookListRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subtitleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    final detailsLine = [
      if (row.author.isNotEmpty) row.author,
      if (row.category.isNotEmpty) row.category,
      if (row.fileType.isNotEmpty) row.fileType,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.title,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (detailsLine.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              detailsLine,
              style: subtitleStyle,
            ),
          ],
        ],
      ),
    );
  }
}

class _BookRow {
  final String title;
  final String author;
  final String category;
  final String fileType;

  _BookRow({
    required this.title,
    required this.author,
    required this.category,
    required this.fileType,
  });

  factory _BookRow.fromBook(Book book) {
    return _BookRow(
      title: book.title,
      author: book.author ?? '',
      category:
          (book.category?.path ?? book.categoryPath ?? book.heCategories ?? '')
              .replaceFirst(RegExp(r'^/+'), ''),
      fileType: book.fileType ?? '',
    );
  }

  // השדות באותיות קטנות מחושבים פעם אחת ולא בכל הקשה.
  late final _lowerFields = [
    title,
    author,
    category,
    fileType,
  ].map((field) => field.toLowerCase()).toList();

  bool matches(String lowerQuery) =>
      _lowerFields.any((field) => field.contains(lowerQuery));
}

String _buildCsv(List<_BookRow> rows) {
  final buf = StringBuffer();
  buf.write(
    '${_csvEscape('כותרת')},${_csvEscape('מחבר')},${_csvEscape('קטגוריה')},${_csvEscape('סוג קובץ')}\r\n',
  );
  for (final r in rows) {
    buf.write(_csvEscape(r.title));
    buf.write(',');
    buf.write(_csvEscape(r.author));
    buf.write(',');
    buf.write(_csvEscape(r.category));
    buf.write(',');
    buf.write(_csvEscape(r.fileType));
    buf.write('\r\n');
  }
  return buf.toString();
}

String _csvEscape(String value) {
  if (value.isEmpty) return '';
  final needsQuoting =
      value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!needsQuoting) return value;
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}
