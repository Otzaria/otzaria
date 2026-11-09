import 'dart:convert';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/settings/dialogs/list_dialog_frame.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/utils/file/save_file_with_extension.dart';
import 'package:otzaria/utils/ui/book_format_icon.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/feedback/app_scrollbar.dart';

/// פותח דיאלוג עם רשימות הספרים — ספרי הספרייה והספרים האישיים — חיפוש,
/// וייצוא ל-CSV.
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
  late final List<_BookRow> _libraryRows;
  late final List<_BookRow> _personalRows;
  late List<_BookRow> _visibleRows;
  String _visibleQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showPersonal = false;
  bool _isExporting = false;

  List<_BookRow> get _rows => _showPersonal ? _personalRows : _libraryRows;

  @override
  void initState() {
    super.initState();
    // ה-Library Providers כבר ממיינים books ו-subCategories לפי order,
    // אז getAllBooks() מחזיר בסדר תצוגת הספרייה. שומרים על אותו סדר.
    final rows = widget.books.map(_BookRow.fromBook).toList();
    _libraryRows = rows.where((r) => !r.isPersonal).toList();
    _personalRows = rows.where((r) => r.isPersonal).toList();
    _visibleRows = _libraryRows;
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.removeListener(_applyFilter);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    // שאילתה שמכילה את הקודמת מתאימה רק לשורות שכבר מוצגות.
    final source = _visibleQuery.isNotEmpty && query.contains(_visibleQuery)
        ? _visibleRows
        : _rows;
    setState(() {
      _visibleQuery = query;
      _visibleRows = query.isEmpty
          ? _rows
          : source.where((r) => r.matches(query)).toList();
    });
  }

  void _selectList({required bool personal}) {
    _showPersonal = personal;
    _searchController.clear();
    _applyFilter();
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  Future<void> _exportToCsv() async {
    final downloadsDirectory = await getDownloadsDirectory();
    if (!mounted) return;

    final bytes = Uint8List.fromList(
      utf8.encode(buildBooksCsv(widget.books)),
    );
    if (!mounted) return;
    final path = await saveFileWithExtension(
      context: context,
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
      UiSnack.show(SettingsMessages.booksListSaved(widget.books.length));
    } catch (e) {
      if (!mounted) return;
      UiSnack.showError(SettingsMessages.fileSaveError(e));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialogFrame(
      icon: OtzariaIcons.book_24_regular,
      title: context.settingsText('רשימת הספרים'),
      trailing: ListDialogCounter('${_visibleRows.length} / ${_rows.length}'),
      size: AppDialogSize.large,
      padding: AppTokens.dialogPadding.copyWith(top: 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppTokens.spaceMD),
          AppSegmentedControl<bool>(
            options: [
              SegmentOption(
                value: false,
                label: context.settingsText(
                  'ספרייה {count}',
                  args: {'count': _libraryRows.length},
                ),
              ),
              SegmentOption(
                value: true,
                label: context.settingsText(
                  'אישיים {count}',
                  args: {'count': _personalRows.length},
                ),
              ),
            ],
            currentValue: _showPersonal,
            expandToFillWidth: true,
            onChanged: (personal) => _selectList(personal: personal),
          ),
          const SizedBox(height: AppTokens.spaceMD),
          OtzariaSearchField(
            controller: _searchController,
            autofocus: true,
            hintText: context.settingsText('חיפוש לפי שם, מחבר או קטגוריה'),
          ),
          const SizedBox(height: AppTokens.spaceMD),
          Expanded(
            child: _visibleRows.isEmpty
                ? OtzariaEmptyState(
                    isCompact: true,
                    icon: OtzariaIcons.search_in_library_24_regular,
                    title: context.settingsText('לא נמצאו ספרים'),
                  )
                : AppCard(
                    child: AppScrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      // שכבת Material שקופה: בלעדיה הקו התחתון של שורת הרשימה
                      // (ListTile.shape) מצויר מחוץ לאזור הגלילה.
                      child: Material(
                        type: MaterialType.transparency,
                        child: ListView.builder(
                          controller: _scrollController,
                          // גובה שורה קבוע: קפיצת פס הגלילה לא בונה את כל השורות בדרך
                          prototypeItem: _BookListRow(row: _BookRow.blank()),
                          itemCount: _visibleRows.length,
                          itemBuilder: (_, i) => _BookListRow(
                            row: _visibleRows[i],
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: AppTokens.spaceMD),
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
    final detailsLine = [
      if (row.author.isNotEmpty) row.author,
      if (row.category.isNotEmpty) row.category,
      if (row.fileType.isNotEmpty) row.fileType,
    ].join(' · ');

    // שורת פרטים גם כשאין פרטים: הגובה חייב להיות זהה לתבנית.
    return ListTile(
      shape: Border(bottom: listDialogRowDivider(context)),
      leading: Icon(row.icon),
      title: Tooltip(
        message: row.title,
        child: Text(
          row.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: AppTokens.fontMD + 1,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
      ),
      subtitle: Tooltip(
        message: detailsLine,
        child: Text(
          detailsLine,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: AppTokens.fontSM,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _BookRow {
  final String title;
  final String author;
  final String category;
  final String fileType;
  final IconData icon;
  final bool isPersonal;

  _BookRow({
    required this.title,
    required this.author,
    required this.category,
    required this.fileType,
    required this.icon,
    required this.isPersonal,
  });

  /// שורה ריקה בגובה שורה רגילה, לתבנית הגובה של הרשימה.
  _BookRow.blank()
    : title = ' ',
      author = ' ',
      category = '',
      fileType = '',
      icon = FluentIcons.document_text_24_regular,
      isPersonal = false;

  factory _BookRow.fromBook(Book book) {
    return _BookRow(
      title: book.title,
      author: book.author ?? '',
      category:
          (book.category?.path ?? book.categoryPath ?? book.heCategories ?? '')
              .replaceFirst(RegExp(r'^/+'), ''),
      fileType: book.fileType ?? '',
      icon: bookFormatIcon(book),
      isPersonal: book.isPersonalBook,
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

/// ה-BOM גורם ל-Excel לקרוא את הקובץ כ-UTF-8.
const _csvBom = '\uFEFF';

/// קובץ ה-CSV של רשימת הספרים: ספרי הספרייה ואחריהם האישיים.
@visibleForTesting
String buildBooksCsv(List<Book> books) {
  final rows = books.map(_BookRow.fromBook).toList();
  final buf = StringBuffer(_csvBom);
  buf.write(
    '${_csvEscape('כותרת')},${_csvEscape('מחבר')},${_csvEscape('קטגוריה')},${_csvEscape('סוג קובץ')},${_csvEscape('מקור')}\r\n',
  );
  for (final r in [
    ...rows.where((r) => !r.isPersonal),
    ...rows.where((r) => r.isPersonal),
  ]) {
    buf.write(_csvEscape(r.title));
    buf.write(',');
    buf.write(_csvEscape(r.author));
    buf.write(',');
    buf.write(_csvEscape(r.category));
    buf.write(',');
    buf.write(_csvEscape(r.fileType));
    buf.write(',');
    buf.write(_csvEscape(r.isPersonal ? 'אישי' : 'ספרייה'));
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
