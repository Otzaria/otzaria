import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/settings_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/settings/services/custom_folders/personal_books_import_service.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
import 'package:otzaria/widgets/widgets_exports.dart';
import 'package:path/path.dart' as p;

/// פאנל ייבוא וניהול ספרים אישיים במובייל.
///
/// באנדרואיד/iOS אין גישה קבועה לתיקיות חיצוניות, ולכן הקבצים שנבחרו
/// מועתקים לתיקייה פנימית קבועה שנרשמת כתיקייה מותאמת אישית — משם ממשיך
/// צינור הסריקה והאינדוקס הרגיל.
class PersonalBooksImportPanel extends StatefulWidget {
  const PersonalBooksImportPanel({
    super.key,
    this.service,
    this.pickFilesOverride,
  });

  /// לצורכי בדיקה — שירות עם תיקייה זמנית.
  final PersonalBooksImportService? service;

  /// לצורכי בדיקה — עוקף את בורר הקבצים של המערכת.
  final Future<List<String>?> Function()? pickFilesOverride;

  @override
  State<PersonalBooksImportPanel> createState() =>
      _PersonalBooksImportPanelState();
}

class _PersonalBooksImportPanelState extends State<PersonalBooksImportPanel> {
  late final PersonalBooksImportService _service;
  bool _isExpanded = false;
  bool _isCopying = false;
  List<File> _importedFiles = const [];

  // מאזין לתור הגלובלי כדי שהכפתורים ייחסמו גם כשמסלול אחר (כגון file_sync)
  // כותב ל-DB באמצעות אותו תור.
  void _onQueueBusyChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PersonalBooksImportService();
    DatabaseLibraryProvider.operationQueue.busyCount.addListener(
      _onQueueBusyChanged,
    );
    _refreshFileList();
  }

  @override
  void dispose() {
    DatabaseLibraryProvider.operationQueue.busyCount.removeListener(
      _onQueueBusyChanged,
    );
    super.dispose();
  }

  Future<void> _refreshFileList() async {
    final files = await _service.listImportedFiles();
    if (!mounted) return;
    setState(() => _importedFiles = files);
  }

  Future<List<String>?> _pickFiles() async {
    final override = widget.pickFilesOverride;
    if (override != null) return override();

    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['txt', 'pdf', 'docx', 'epub'],
      dialogTitle: 'בחר קבצי ספרים לייבוא',
    );
    if (result == null) return null;
    return result.paths.whereType<String>().toList();
  }

  Future<void> _importBooks() async {
    final bloc = context.read<CustomFoldersBloc>();
    final paths = await _pickFiles();
    if (!mounted || paths == null || paths.isEmpty) return;

    setState(() => _isCopying = true);
    try {
      final result = await _service.copyFiles(paths);
      if (!mounted) return;

      if (result.errors.isNotEmpty) {
        UiSnack.showError(
          SettingsMessages.importErrors(result.errors.join('\n')),
        );
      }
      if (result.skippedUnsupported > 0) {
        UiSnack.show(
          SettingsMessages.unsupportedFilesSkipped(result.skippedUnsupported),
        );
      }
      if (result.copied == 0) return;

      await _refreshFileList();
      if (!mounted) return;
      setState(() => _isExpanded = true);

      // ההודעות על תוצאת הסריקה מגיעות מה-BLoC דרך ה-listener למטה.
      final folderPath = await _service.getFolderPath();
      final alreadyRegistered = bloc.state.folders.any(
        (f) => f.path == folderPath,
      );
      bloc.add(
        alreadyRegistered
            ? RescanCustomFolders(
                showNoChangesMessage: false,
                onlyFolderPath: folderPath,
              )
            : AddCustomFolder(folderPath),
      );
    } finally {
      if (mounted) setState(() => _isCopying = false);
    }
  }

  Future<void> _deleteBook(File file) async {
    final bloc = context.read<CustomFoldersBloc>();
    final title = p.basenameWithoutExtension(file.path);
    final confirmed = await showWarningDialog(
      context: context,
      title: 'מחיקת ספר',
      content: 'האם למחוק את "$title" מהספרים האישיים?',
      cancelText: 'ביטול',
      confirmText: 'מחק',
    );
    if (confirmed != true || !mounted) return;

    try {
      await _service.deleteImportedFile(file.path);
    } catch (e) {
      UiSnack.showError(SettingsMessages.bookDeleteError(e));
      return;
    }
    await _refreshFileList();
    // הסריקה מסירה מה-DB ספרים שקובצם נמחק (prune) ומרעננת את הספרייה.
    bloc.add(
      RescanCustomFolders(
        showNoChangesMessage: false,
        onlyFolderPath: await _service.getFolderPath(),
      ),
    );
    UiSnack.show(SettingsMessages.bookDeleted(title));
  }

  String _fileTypeLabel(String filePath) {
    switch (p.extension(filePath).toLowerCase()) {
      case '.pdf':
        return 'PDF';
      case '.docx':
        return 'Word';
      case '.epub':
        return 'EPUB';
      default:
        return 'טקסט';
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CustomFoldersBloc, CustomFoldersState>(
      listenWhen: (prev, curr) =>
          (curr.message != null && curr.message != prev.message) ||
          (curr.error != null && curr.error != prev.error) ||
          (prev.isSyncing && !curr.isSyncing),
      listener: (context, state) {
        if (state.message != null) UiSnack.show(state.message!);
        if (state.error != null) UiSnack.showError(state.error!);
        if (!state.isSyncing) _refreshFileList();
      },
      builder: (context, state) {
        final isBusy =
            _isCopying ||
            state.isSyncing ||
            DatabaseLibraryProvider.operationQueue.isBusy;
        return ExpandableSection(
          icon: FluentIcons.book_add_24_regular,
          title: 'הספרים שלי',
          subtitle: _importedFiles.isEmpty
              ? 'ייבוא קבצי TXT, PDF, Word ו-EPUB לספרייה'
              : '${_importedFiles.length} ספרים מיובאים',
          trailing: ActionButton.recommended(
            text: 'ייבוא ספרים',
            icon: FluentIcons.book_add_24_regular,
            onPressed: _importBooks,
            isLoading: isBusy,
          ),
          isExpanded: _isExpanded,
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          hasContent: _importedFiles.isNotEmpty,
          children: [
            Container(
              margin: const EdgeInsets.only(right: 16, left: 16, bottom: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: AppTokens.borderRadiusAll,
              ),
              child: Column(
                children: [
                  for (final file in _importedFiles)
                    _buildFileItem(file, isBusy),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFileItem(File file, bool isBusy) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      hoverColor: Colors.transparent,
      leading: RtlIcon(
        FluentIcons.book_24_regular,
        color: cs.primary,
        size: 20,
      ),
      title: Text(
        p.basenameWithoutExtension(file.path),
        style: const TextStyle(fontSize: 14),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _fileTypeLabel(file.path),
        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
      ),
      trailing: IconButton(
        icon: const Icon(FluentIcons.delete_24_regular, size: 18),
        onPressed: isBusy ? null : () => _deleteBook(file),
        tooltip: 'מחק ספר',
      ),
    );
  }
}
