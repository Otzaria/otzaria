import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// פותח דיאלוג עם רשימת כל הספרים בספרייה, חיפוש, וייצוא ל-CSV.
Future<void> showBooksListDialog({
  required BuildContext context,
  required List<Book> books,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _BooksListDialog(books: books),
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
    final query = _searchController.text.trim();
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
    final path = await FilePicker.saveFile(
      dialogTitle: 'בחר מיקום לשמירת רשימת הספרים',
      fileName: 'otzaria_books.csv',
      initialDirectory: downloadsDirectory?.path,
      allowedExtensions: ['csv'],
      type: FileType.custom,
      bytes: bytes,
      lockParentWindow: true,
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
    final media = MediaQuery.of(context);
    final maxWidth = media.size.width * 0.9;
    final maxHeight = media.size.height * 0.85;

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth > 720 ? 720 : maxWidth,
          maxHeight: maxHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(FluentIcons.book_24_regular, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'רשימת הספרים',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    '${_visibleRows.length} / ${_rows.length}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              RtlTextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(FluentIcons.search_24_regular),
                  hintText: 'חיפוש לפי שם, מחבר או קטגוריה',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _visibleRows.isEmpty
                    ? Center(
                        child: Text(
                          'לא נמצאו ספרים',
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
                    text: 'ייצוא ל-CSV',
                    icon: FluentIcons.arrow_download_24_regular,
                    isLoading: _isExporting,
                    onPressed: _exportToCsv,
                  ),
                  const Spacer(),
                  ActionButton.neutral(
                    text: 'סגור',
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

  const _BookRow({
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
          book.category?.path ?? book.categoryPath ?? book.heCategories ?? '',
      fileType: book.fileType ?? '',
    );
  }

  bool matches(String query) {
    final q = query.toLowerCase();
    return title.toLowerCase().contains(q) ||
        author.toLowerCase().contains(q) ||
        category.toLowerCase().contains(q) ||
        fileType.toLowerCase().contains(q);
  }
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
