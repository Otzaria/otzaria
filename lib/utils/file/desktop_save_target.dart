import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:otzaria/utils/file/atomic_file_publication.dart';
import 'package:otzaria/utils/file/file_picker_dialog_options.dart';
import 'package:otzaria/utils/file/save_target_name.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';

export 'atomic_file_publication.dart' show DesktopSaveTarget;

/// Chooses a path without creating a placeholder or truncating an existing
/// file. The caller must verify protected-mode access before opening this UI.
Future<DesktopSaveTarget?> chooseDesktopSaveTarget({
  required BuildContext context,
  required String fileName,
  String? extension,
  String? dialogTitle,
  Future<bool> Function(String fileName)? confirmOverwrite,
  bool Function()? isCancelled,
}) async {
  bool cancelled() => isCancelled?.call() ?? false;
  if (!context.mounted || cancelled()) return null;
  final windowsOptions = modalWindowsOptions(context);
  final suggested = saveTargetFileName(fileName, extension);
  final folder = await withFilePickerOwner(
    context,
    (picker) => picker.getDirectoryPath(
      dialogTitle: saveTargetFolderDialogTitle(dialogTitle),
      windowsOptions: windowsOptions,
      linuxOptions: kModalLinuxOptions,
    ),
  );
  if (folder == null || folder.isEmpty || !context.mounted || cancelled()) {
    return null;
  }
  final typed = await showInputDialog(
    context: context,
    title: dialogTitle ?? 'שמירת קובץ',
    labelText: 'שם הקובץ',
    initialValue: suggested,
    confirmText: 'שמור',
  );
  if (typed == null || !context.mounted || cancelled()) return null;
  final name = saveTargetFileName(typed, extension);
  final path = saveTargetPath(folder: folder, fileName: name);
  if (path == null || !context.mounted || cancelled()) return null;
  final exists =
      await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;
  if (!context.mounted || cancelled()) return null;
  if (exists) {
    final approved = confirmOverwrite != null
        ? await confirmOverwrite(name)
        : await showWarningDialog(
            context: context,
            title: 'הקובץ כבר קיים',
            content: 'הקובץ „$name” כבר קיים בתיקייה שנבחרה.',
            subtitle: 'התוכן הקיים יוחלף.',
            confirmText: 'החלפה',
          );
    if (approved != true || !context.mounted || cancelled()) return null;
  }
  return DesktopSaveTarget(path: path, overwriteApproved: exists);
}
