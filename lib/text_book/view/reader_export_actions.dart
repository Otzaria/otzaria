import 'dart:io';
import 'package:otzaria/text_book/repository/book_notes_repository.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:otzaria/core/messages/text_book_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:otzaria/settings/settings_exports.dart' hide UpdateFontSize;
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/utils/text_book_export_utils.dart';
import 'package:otzaria/text_book/view/text_book_export_dialog.dart';
import 'package:otzaria/divine_names/repository/divine_names_repository.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/printing/print_content_models.dart';
import 'package:otzaria/printing/word_export_service.dart';
import 'package:otzaria/utils/file/save_file_with_extension.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:pdf/pdf.dart';

/// פרופיל ערוץ הייצוא של גוף הספר — משותף להדפסה ולייצוא.
TextDisplayProfile readerExportProfile(TextBookLoaded state) =>
    state.displayProfile(target: TextTarget.body, channel: TextChannel.export);

class _WordExportRequest {
  final String title;
  final TextBookExportRequest text;
  final String? fontFamily;
  final double fontSize;

  const _WordExportRequest({
    required this.title,
    required this.text,
    required this.fontFamily,
    required this.fontSize,
  });
}

Uint8List _createTextBookWordExport(_WordExportRequest request) {
  final blocks = textBookExportLines(request.text, stripHtml: false)
      .map((line) => PrintBlock(kind: PrintBlockKind.text, text: line))
      .toList(growable: false);

  return WordExportService.createWordDocument(
    title: request.title,
    blocks: blocks,
    format: PdfPageFormat.a4,
    isLandscape: false,
    pageMargin: 20,
    fontFamily: request.fontFamily,
    fontSize: request.fontSize,
  );
}

/// ייצוא הספר המלא (Word מעוצב או טקסט) מהקורא.
mixin ReaderExportActions<T extends StatefulWidget> on State<T> {
  Future<void> exportWholeBook(TextBookLoaded state) async {
    if (!state.protection.allowsEditableExport) {
      UiSnack.showError(TextBookMessages.editableExportRestricted);
      return;
    }
    if (!await verifySaferModePassword(context)) return;
    if (!mounted) return;

    try {
      // לא state.divineNames: הטעינה ברקע עשויה שלא להסתיים עד הייצוא.
      final book = state.book;
      final divineNames = await DivineNamesRepository.instance.spansFor(
        book.title,
        categoryId: book.categoryId,
        source: book.source,
        fileType: book.fileType,
        versionTitle: book.versionTitle,
      );
      if (!mounted) return;
      final choice = await showTextBookExportDialog(
        context,
        profile: readerExportProfile(state),
        hasDivineNames: !divineNames.isEmpty,
      );
      if (choice == null) return;
      if (!mounted) return;

      final selectedFormat = choice.format;
      final extension = selectedFormat.extension;
      final settingsState = context.read<SettingsBloc>().state;
      final profile = readerExportProfile(
        state,
      ).copyWith(holyName: choice.holyName, divineNames: choice.divineNames);
      final fullContent = await context
          .read<TextBookBloc>()
          .repository
          .getBookContent(state.book);

      final bookNotes = await BookNotesRepository.instance.notesFor(
        book.title,
        categoryId: book.categoryId,
        source: book.source,
        fileType: book.fileType,
        versionTitle: book.versionTitle,
      );
      final exportRequest = TextBookExportRequest(
        rawContent: fullContent,
        profile: profile,
        divineNames: divineNames,
        bookNotes: bookNotes,
      );
      final Uint8List bytes;
      final String successMessage;
      if (selectedFormat == TextBookExportFormat.word) {
        bytes = await compute(
          _createTextBookWordExport,
          _WordExportRequest(
            title: state.book.title,
            text: exportRequest,
            fontFamily: settingsState.fontFamily,
            fontSize: state.fontSize,
          ),
        );
        successMessage = TextBookMessages.wordFileSaved;
      } else {
        final text = await compute(createTextBookTextExport, exportRequest);
        bytes = Uint8List.fromList(utf8.encode(text));
        successMessage = TextBookMessages.textFileSaved;
      }

      if (!mounted) return;
      final path = await saveFileWithExtension(
        context: context,
        dialogTitle: 'ייצוא הספר',
        fileName:
            '${sanitizeTextBookExportFileName(state.book.title)}.$extension',
        extension: extension,
        bytes: bytes,
      );
      if (path == null) return;
      if (!mounted) return;
      UiSnack.showSuccess(successMessage);
    } on FileSystemException catch (e) {
      if (isLockedTextBookExportFileException(e)) {
        UiSnack.showError(TextBookMessages.exportFileLocked);
        return;
      }
      UiSnack.showError(TextBookMessages.exportFailed(e.message));
    } catch (e) {
      UiSnack.showError(TextBookMessages.exportFailed(e));
    }
  }
}
