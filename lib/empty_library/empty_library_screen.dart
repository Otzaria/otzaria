import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/empty_library/bloc/empty_library_event.dart';
import 'package:otzaria/empty_library/bloc/empty_library_state.dart';
import 'dart:io' show Platform;
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
          if (state is EmptyLibraryDownloaded) {
            onLibraryLoaded();
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

  Widget _buildContent(BuildContext context, EmptyLibraryState state) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'לא נמצאה ספרייה',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        if (state.selectedPath != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              state.selectedPath!,
              style: const TextStyle(fontSize: 16),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
            ),
          ),
        ElevatedButton.icon(
          onPressed: state.isDownloading
              ? null
              : () => BlocProvider.of<EmptyLibraryBloc>(context)
                  .add(PickDirectoryRequested()),
          icon: const Icon(FluentIcons.folder_open_24_regular),
          label: const Text('בחר תיקייה'),
        ),
        const SizedBox(height: 32),
        if (Platform.isAndroid)
          ElevatedButton.icon(
            onPressed: state.isDownloading
                ? null
                : () => BlocProvider.of<EmptyLibraryBloc>(context)
                    .add(PickAndExtractZipRequested()),
            icon: const Icon(FluentIcons.folder_zip_24_regular),
            label: const Text('בחר קובץ ZIP מהמכשיר'),
          ),
        const Text(
          'או',
          style: TextStyle(fontSize: 18),
        ),
        const SizedBox(height: 32),
        if (state.isDownloading) ...[
          _DownloadProgress(state: state),
        ] else
          ElevatedButton.icon(
            onPressed: state.isDownloading
                ? null
                : () => BlocProvider.of<EmptyLibraryBloc>(context)
                    .add(DownloadLibraryRequested()),
            icon: const Icon(FluentIcons.arrow_download_24_regular),
            label: const Text('הורד את הספרייה מהאינטרנט (1.5GB)'),
          ),
      ],
    );
  }
}

class _DownloadProgress extends StatelessWidget {
  final EmptyLibraryState state;

  const _DownloadProgress({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LinearProgressIndicator(value: state.downloadProgress),
        const SizedBox(height: 16),
        Text(state.currentOperation),
        if (state.downloadSpeed > 0)
          Text('מהירות הורדה: ${state.downloadSpeed.toStringAsFixed(2)} MB/s'),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: state.isCancelling
              ? null
              : () => BlocProvider.of<EmptyLibraryBloc>(context)
                  .add(CancelDownloadRequested()),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(FluentIcons.stop_24_regular),
          label: Text(state.isCancelling ? 'מבטל...' : 'בטל'),
        ),
      ],
    );
  }
}
