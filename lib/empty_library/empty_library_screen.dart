import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/empty_library/bloc/empty_library_event.dart';
import 'package:otzaria/empty_library/bloc/empty_library_state.dart';
import 'package:otzaria/core/scaffold_messenger.dart';

class EmptyLibraryScreen extends StatelessWidget {
  final VoidCallback onLibraryLoaded;

  const EmptyLibraryScreen({super.key, required this.onLibraryLoaded});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => EmptyLibraryBloc(),
      child: _EmptyLibraryView(onLibraryLoaded: onLibraryLoaded),
    );
  }
}

class _EmptyLibraryView extends StatelessWidget {
  final VoidCallback onLibraryLoaded;

  const _EmptyLibraryView({required this.onLibraryLoaded});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocConsumer<EmptyLibraryBloc, EmptyLibraryState>(
        listener: (context, state) {
          if (state is EmptyLibraryDirectorySelected) {
            _showRestartDialog(context);
          }
          if (state is EmptyLibraryError && state.errorMessage != null) {
            UiSnack.showError(state.errorMessage!,
                backgroundColor: Theme.of(context).colorScheme.error);
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

  Widget _buildContent(BuildContext context, EmptyLibraryState state) {
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
          'לא נמצאה ספרייה',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        const Text(
          'יש לבחור את תיקיית "אוצריא" המכילה את קובץ מסד הנתונים',
          style: TextStyle(fontSize: 16, color: Colors.grey),
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
          onPressed: state.isLoading
              ? null
              : () => BlocProvider.of<EmptyLibraryBloc>(context)
                  .add(PickDirectoryRequested()),
          icon: const Icon(FluentIcons.folder_open_24_regular),
          label: const Text('בחר תיקייה'),
        ),
        if (state.isLoading) ...[
          const SizedBox(height: 24),
          const CircularProgressIndicator(),
          const SizedBox(height: 8),
          const Text('בודק את התיקייה...'),
        ],
      ],
    );
  }
}
