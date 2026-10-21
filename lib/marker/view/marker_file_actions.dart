import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/messages/marker_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/marker/models/marker_highlight.dart';
import 'package:otzaria/marker/models/marker_palette.dart';
import 'package:otzaria/marker/repository/marker_repository.dart';
import 'package:otzaria/marker/services/marker_book_index.dart';
import 'package:otzaria/marker/services/marker_export.dart';
import 'package:otzaria/marker/services/marker_settings.dart';
import 'package:otzaria/marker/services/marker_transfer.dart';
import 'package:otzaria/marker/view/widgets/marker_import_dialog.dart';
import 'package:otzaria/printing/view/printing_screen.dart';
import 'package:otzaria/printing/word_export_service.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/utils/file/file_picker_dialog_options.dart';
import 'package:otzaria/utils/file/save_file_with_extension.dart';
import 'package:pdf/pdf.dart';

const String _documentTitle = 'סימונים במרקר';

String _today() => DateTime.now().toIso8601String().substring(0, 10);

Future<void> printMarkerHighlights(
  BuildContext context,
  List<MarkerHighlight> highlights,
) async {
  if (highlights.isEmpty) {
    UiSnack.show(MarkerMessages.nothingToExport);
    return;
  }
  await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PrintingScreen(
      data: Future.value(''),
      bookId: _documentTitle,
      documentTitle: _documentTitle,
      prebuiltBlocks: markerPrintBlocks(
        highlights,
        palette: MarkerSettings.instance.palette,
      ),
    ),
  );
}

Future<void> exportMarkerToWord(
  BuildContext context,
  List<MarkerHighlight> highlights,
) async {
  if (highlights.isEmpty) {
    UiSnack.show(MarkerMessages.nothingToExport);
    return;
  }
  try {
    final bytes = WordExportService.createWordDocument(
      title: _documentTitle,
      blocks: markerPrintBlocks(
        highlights,
        palette: MarkerSettings.instance.palette,
      ),
      format: PdfPageFormat.a4,
      isLandscape: false,
      pageMargin: 20,
      fontFamily: context.read<SettingsBloc>().state.fontFamily,
    );
    final path = await saveFileWithExtension(
      context: context,
      dialogTitle: 'בחירת מיקום לקובץ הוורד',
      fileName: 'otzaria_marker_${_today()}.docx',
      extension: 'docx',
      bytes: bytes,
    );
    if (path != null) UiSnack.showSuccess(MarkerMessages.exportCompleted);
  } catch (error) {
    debugPrint('Marker Word export failed: $error');
    UiSnack.showError(MarkerMessages.exportFailed);
  }
}

/// גיבוי לקובץ: [only] — רק הסימונים האלה, ואחרת כולם.
Future<void> backupMarkerToFile(
  BuildContext context, {
  List<MarkerHighlight>? only,
}) async {
  try {
    final bytes = await MarkerTransfer().encodeBackup(
      palette: MarkerSettings.instance.palette,
      only: only,
    );
    if (!context.mounted) return;
    final path = await saveFileWithExtension(
      context: context,
      dialogTitle: 'בחירת מיקום לקובץ הגיבוי',
      fileName: 'otzaria_marker_backup_${_today()}.json',
      extension: 'json',
      bytes: bytes,
    );
    if (path != null) UiSnack.showSuccess(MarkerMessages.backupCompleted);
  } catch (error) {
    debugPrint('Marker backup failed: $error');
    UiSnack.showError(MarkerMessages.exportFailed);
  }
}

MarkerBookIndex? _libraryIndex(BuildContext context) {
  final library = context.read<LibraryBloc>().state.library;
  return library == null ? null : MarkerBookIndex.of(library);
}

Future<void> importMarkerFromFile(BuildContext context) async {
  if (!await verifySaferModePassword(context) || !context.mounted) return;
  final picked = await FilePicker.pickFile(
    dialogTitle: 'בחירת קובץ גיבוי של המרקר',
    allowedExtensions: ['json'],
    type: FileType.custom,
    windowsOptions: kModalWindowsOptions,
    linuxOptions: kModalLinuxOptions,
  );
  final path = picked?.path;
  if (path == null || !context.mounted) return;
  final transfer = MarkerTransfer();
  final MarkerImportPreview preview;
  try {
    preview = await transfer.previewFile(path, books: _libraryIndex(context));
  } on MarkerBackupTooLargeException {
    UiSnack.showError(MarkerMessages.importFileTooLarge);
    return;
  } on MarkerBackupFormatException {
    UiSnack.showError(MarkerMessages.importInvalidFile);
    return;
  } catch (error) {
    debugPrint('Marker import read failed: $error');
    UiSnack.showError(MarkerMessages.importReadFailed);
    return;
  }
  if (!context.mounted) return;
  await _confirmAndImport(context, transfer, preview, fromLegacyPlugin: false);
}

/// מייבא את מה שתוסף המרקר הישן שמר, בלי לשנות את נתוני התוסף.
Future<void> importMarkerFromLegacyPlugin(BuildContext context) async {
  if (!await verifySaferModePassword(context) || !context.mounted) return;
  final transfer = MarkerTransfer();
  final MarkerImportPreview? preview;
  try {
    preview = await transfer.previewLegacyPlugin(
      books: _libraryIndex(context),
    );
  } catch (error) {
    debugPrint('Marker legacy read failed: $error');
    UiSnack.showError(MarkerMessages.importLegacyReadFailed);
    return;
  }
  if (!context.mounted) return;
  if (preview == null) {
    UiSnack.show(MarkerMessages.importNoLegacyData);
    return;
  }
  await _confirmAndImport(context, transfer, preview, fromLegacyPlugin: true);
}

Future<void> _confirmAndImport(
  BuildContext context,
  MarkerTransfer transfer,
  MarkerImportPreview preview, {
  required bool fromLegacyPlugin,
}) async {
  if (preview.highlights.isEmpty && preview.deletedSinceImport == 0) {
    UiSnack.show(MarkerMessages.importNothingFound);
    return;
  }
  final settings = MarkerSettings.instance;
  final options = await showMarkerImportDialog(
    context,
    preview: preview,
    paletteIsDefault: settings.palette == MarkerPalette.defaults(),
    fromLegacyPlugin: fromLegacyPlugin,
  );
  if (options == null) return;
  if (options.backupFirst) {
    try {
      await transfer.writeSafetyBackup(settings.palette);
    } catch (error) {
      debugPrint('Marker safety backup failed: $error');
      UiSnack.showError(MarkerMessages.safetyBackupFailed);
      return;
    }
  }
  final MarkerImportSummary summary;
  try {
    summary = await transfer.apply(preview);
  } catch (error, stackTrace) {
    debugPrint('Marker import failed: $error');
    debugPrintStack(stackTrace: stackTrace, maxFrames: 8);
    UiSnack.showError(MarkerMessages.importFailed);
    return;
  }
  if (options.importPalette && preview.palette != null) {
    try {
      await settings.setPalette(preview.palette!);
    } catch (error) {
      debugPrint('Marker palette import failed: $error');
      UiSnack.showError(MarkerMessages.paletteImportFailed);
      return;
    }
  }
  final message = MarkerMessages.importCompleted(
    summary.added,
    summary.skipped,
  );
  summary.added == 0 ? UiSnack.show(message) : UiSnack.showSuccess(message);
}
