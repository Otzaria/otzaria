import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/empty_library/bloc/empty_library_event.dart';
import 'package:otzaria/empty_library/bloc/empty_library_state.dart';
import 'package:otzaria/core/scaffold_messenger.dart';
import 'package:file_picker/file_picker.dart';

class EmptyLibraryScreen extends StatelessWidget {
  final VoidCallback onLibraryLoaded;
  final EmptyLibraryBloc? bloc;

  const EmptyLibraryScreen({
    super.key,
    required this.onLibraryLoaded,
    this.bloc,
  });

  @override
  Widget build(BuildContext context) {
    if (bloc != null) {
      return BlocProvider.value(
        value: bloc!,
        child: _EmptyLibraryView(onLibraryLoaded: onLibraryLoaded),
      );
    }
    return BlocProvider(
      create: (context) => EmptyLibraryBloc(),
      child: _EmptyLibraryView(onLibraryLoaded: onLibraryLoaded),
    );
  }
}

class _EmptyLibraryView extends StatefulWidget {
  final VoidCallback onLibraryLoaded;

  const _EmptyLibraryView({required this.onLibraryLoaded});

  @override
  State<_EmptyLibraryView> createState() => _EmptyLibraryViewState();
}

class _EmptyLibraryViewState extends State<_EmptyLibraryView> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocConsumer<EmptyLibraryBloc, EmptyLibraryState>(
        listener: (context, state) {
          if (state is EmptyLibraryDirectorySelected) {
            _showRestartDialog(context);
          }
          if (state is EmptyLibraryZipExtracted) {
            UiSnack.showSuccess(
              'הקובץ "${state.extractedFileName}" חולץ בהצלחה!',
              backgroundColor: Theme.of(context).colorScheme.primary,
            );
          }
          if (state is EmptyLibraryError && state.errorMessage != null) {
            if (state.zipFiles != null && state.zipFiles!.isNotEmpty) {
              _showMultipleZipFilesDialog(context, state.zipFiles!);
            } else {
              UiSnack.showError(state.errorMessage!,
                  backgroundColor: Theme.of(context).colorScheme.error);
            }
          }
          if (state is EmptyLibraryAskingDeleteZip) {
            _showDeleteZipDialog(context, state);
          }
        },
        builder: (context, state) {
          return Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(16),
              child: _buildContent(context, state),
            ),
          );
        },
      ),
    );
  }

  void _showRestartDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('נדרשת הפעלה מחדש'),
        content: const Text(
          'הספרייה נמצאה בהצלחה.\nלחץ על הכפתור לסגירת האפליקציה, ולאחר מכן פתח אותה מחדש.',
        ),
        actions: [
          FilledButton.icon(
            onPressed: () => exit(0),
            icon: const Icon(FluentIcons.sign_out_24_regular),
            label: const Text('סגור את האפליקציה'),
          ),
        ],
      ),
    );
  }

  void _showDeleteZipDialog(
      BuildContext context, EmptyLibraryAskingDeleteZip state) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('מחיקת קובץ דחוס'),
        content: const Text(
          'האם למחוק את קובץ ה-ZIP המקורי?\n\n'
          'הקובץ הדחוס אינו נצרך עבור פעילות התוכנה והוא רק תופס מקום.\n'
          'מומלץ למחוק אותו.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              BlocProvider.of<EmptyLibraryBloc>(context).add(
                DeleteZipAnswered(
                  shouldDelete: false,
                  zipPath: state.zipPath,
                  extractedPath: state.extractedPath,
                ),
              );
            },
            child: const Text('השאר את הקובץ'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              BlocProvider.of<EmptyLibraryBloc>(context).add(
                DeleteZipAnswered(
                  shouldDelete: true,
                  zipPath: state.zipPath,
                  extractedPath: state.extractedPath,
                ),
              );
            },
            child: const Text('מחק את הקובץ'),
          ),
        ],
      ),
    );
  }

  void _showMultipleZipFilesDialog(
      BuildContext context, List<String> zipFiles) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('נמצאו מספר קבצים דחוסים'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('נמצאו הקבצים הדחוסים הבאים:'),
            const SizedBox(height: 8),
            ...zipFiles.map((file) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('• $file'),
                )),
            const SizedBox(height: 16),
            const Text(
              'אנא השאר רק קובץ דחוס אחד בתיקייה ונסה שוב.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('הבנתי'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, EmptyLibraryState state) {
    // אם בתהליך הורדה או חילוץ, נציג את ההתקדמות
    if (state is EmptyLibraryDownloading) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            FluentIcons.arrow_download_24_regular,
            size: 64,
            color: Colors.blue,
          ),
          const SizedBox(height: 24),
          const Text(
            'מוריד ספרייה',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: 300,
            child: Column(
              children: [
                LinearProgressIndicator(
                  value: state.progress > 0 ? state.progress : null,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 16),
                Text(
                  state.message,
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                if (state.progress > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${(state.progress * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    if (state is EmptyLibraryExtracting) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            FluentIcons.folder_zip_24_regular,
            size: 64,
            color: Colors.orange,
          ),
          const SizedBox(height: 24),
          const Text(
            'מחלץ ספרייה',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: 300,
            child: Column(
              children: [
                LinearProgressIndicator(
                  value: state.progress,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 16),
                Text(
                  state.message,
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '${(state.progress * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // המסך הרגיל
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          FluentIcons.library_24_regular,
          size: 64,
          color: Colors.grey,
        ),
        const SizedBox(height: 24),
        const Text(
          'לא נמצא קובץ מסד נתונים',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
        ),
        const SizedBox(height: 16),
        const Text(
          'יש לבחור קובץ מסד נתונים (seforim.db) או קובץ ZIP דחוס',
          style: TextStyle(fontSize: 16, color: Colors.grey),
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        if (state.selectedPath != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                state.selectedPath!,
                style: const TextStyle(fontSize: 14),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ElevatedButton.icon(
          onPressed: state.isLoading ? null : () => _pickFile(context),
          icon: const Icon(FluentIcons.folder_open_24_regular),
          label: const Text('בחר קובץ'),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: state.isLoading
              ? null
              : () {
                  BlocProvider.of<EmptyLibraryBloc>(context)
                      .add(DownloadLibraryRequested());
                },
          icon: const Icon(FluentIcons.arrow_download_24_regular),
          label: const Text(
            'עוד לא הורדת את קובץ הספרייה? לחץ כאן כדי להוריד אותה כעת',
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
          ),
        ),
        if (state.isLoading && state is EmptyLibraryLoading) ...[
          const SizedBox(height: 24),
          const CircularProgressIndicator(),
          const SizedBox(height: 8),
          const Text('בודק את התיקייה...'),
        ],
      ],
    );
  }

  Future<void> _pickFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db', 'zip'],
      dialogTitle: 'בחר קובץ מסד נתונים (seforim.db) או קובץ ZIP',
    );

    if (result == null || result.files.isEmpty || !context.mounted) return;

    final selectedFile = result.files.first.path;
    if (selectedFile == null) return;

    BlocProvider.of<EmptyLibraryBloc>(context)
        .add(PickDatabaseFileRequested(filePath: selectedFile));
  }
}
