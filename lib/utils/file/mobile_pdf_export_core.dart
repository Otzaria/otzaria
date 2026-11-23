import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'mobile_pdf_export_models.dart';

const mobilePdfExportDirectoryName = 'otzaria-pdf-exports-v1';

/// Pure Dart ownership/lifetime implementation used by the platform service.
/// [temporaryDirectory] must resolve to the app's private cache directory.
class MobilePdfExportCoordinator {
  MobilePdfExportCoordinator({
    required this.platform,
    required this._backend,
    required this._temporaryDirectory,
    Future<void> Function(Directory directory)? deleteStagingDirectory,
  }) : _deleteStagingDirectory = deleteStagingDirectory ?? _deleteDirectory;

  final MobilePdfExportPlatform platform;
  final MobilePdfExportBackend _backend;
  final Future<Directory> Function() _temporaryDirectory;
  final Future<void> Function(Directory directory) _deleteStagingDirectory;

  bool get isSupported => platform != MobilePdfExportPlatform.unsupported;

  /// Returns immediately. Every operation receives a separate file, even when
  /// callers share an immutable base PDF. The producer must close its handles
  /// before its future completes; no complete PDF bytes cross this API.
  MobilePdfExportOperation start({
    required String fileName,
    required Future<void> Function(String stagingPath) producer,
    void Function()? onCancelRequested,
  }) {
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final operation = _MobilePdfExportOperation(
      id: id,
      fileName: safeMobilePdfFileName(fileName),
      producer: producer,
      onCancelRequested: onCancelRequested,
      coordinator: this,
    );
    scheduleMicrotask(operation.run);
    return operation;
  }

  static Future<void> _deleteDirectory(Directory directory) async {
    await directory.delete();
  }
}

/// One filename component, at most 255 UTF-8 bytes including `.pdf`.
String safeMobilePdfFileName(String value) {
  var stem = value.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]'), '_').trim();
  while (stem.toLowerCase().endsWith('.pdf')) {
    stem = stem.substring(0, stem.length - 4).trimRight();
  }
  stem = stem.replaceFirst(RegExp(r'[ .]+$'), '');
  if (stem.isEmpty || stem == '.' || stem == '..') stem = 'document';
  final result = StringBuffer();
  var length = 0;
  for (final rune in stem.runes) {
    final character = String.fromCharCode(rune);
    final bytes = utf8.encode(character).length;
    if (length + bytes > 251) break;
    result.write(character);
    length += bytes;
  }
  return '$result.pdf';
}

class _MobilePdfExportOperation implements MobilePdfExportOperation {
  _MobilePdfExportOperation({
    required this.id,
    required this.fileName,
    required this.producer,
    required this.onCancelRequested,
    required this.coordinator,
  });

  @override
  final String id;
  final String fileName;
  final Future<void> Function(String stagingPath) producer;
  final void Function()? onCancelRequested;
  final MobilePdfExportCoordinator coordinator;
  final _result = Completer<MobilePdfExportResult>();
  bool _cancelled = false;
  bool _nativeStarted = false;
  bool _terminal = false;
  Future<void>? _cancelFuture;
  Directory? _ownedDirectory;
  File? _ownedSource;
  String? _rootPath;
  String _stage = 'staging_failed';

  @override
  bool get isCancellationRequested => _cancelled;

  @override
  Future<MobilePdfExportResult> get result => _result.future;

  @override
  Future<void> cancel() {
    final existing = _cancelFuture;
    if (existing != null) return existing;
    final completion = Completer<void>();
    _cancelFuture = completion.future;
    _cancelled = true;
    unawaited(_requestCancel(completion));
    return completion.future;
  }

  Future<void> _requestCancel(Completer<void> completion) async {
    if (!_terminal) {
      try {
        onCancelRequested?.call();
      } catch (error, stack) {
        _logFailure('cancel producer', error, stack);
      }
      if (_nativeStarted) {
        try {
          await coordinator._backend.cancelExport(id);
        } catch (error, stack) {
          // The original export still owns the file. A lost acknowledgement
          // cannot make deleting it safe, nor undo a committed save.
          _logFailure('cancel acknowledgement', error, stack);
        }
      }
    }
    completion.complete();
  }

  Future<void> run() async {
    MobilePdfExportResult outcome;
    try {
      outcome = await _perform();
    } catch (error, stack) {
      _logFailure(_stage, error, stack);
      outcome = MobilePdfExportResult(
        operationId: id,
        status: _cancelled && !_nativeStarted
            ? MobilePdfExportStatus.cancelled
            : MobilePdfExportStatus.failed,
        errorCode: _stage,
        errorMessage: error.toString(),
      );
    }
    _terminal = true;
    if (!outcome.hasNativeStagingCleanupFailure) {
      try {
        await _cleanup();
      } catch (error, stack) {
        _logFailure('staging cleanup', error, stack);
        outcome = outcome.withStagingCleanupError(error);
      }
    }
    _result.complete(outcome);
  }

  MobilePdfExportResult _cancelledResult() => MobilePdfExportResult(
    operationId: id,
    status: MobilePdfExportStatus.cancelled,
  );

  Future<MobilePdfExportResult> _perform() async {
    if (_cancelled) return _cancelledResult();
    if (!coordinator.isSupported) {
      return MobilePdfExportResult(
        operationId: id,
        status: MobilePdfExportStatus.failed,
        errorCode: 'unsupported_platform',
      );
    }
    final temporary = await coordinator._temporaryDirectory();
    if (_cancelled) return _cancelledResult();
    final cachePath = await temporary.resolveSymbolicLinks();
    final root = Directory(p.join(cachePath, mobilePdfExportDirectoryName));
    await root.create();
    _rootPath = root.path;
    await _checkRoot();
    final directory = Directory(p.join(root.path, id));
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException(
        'Export directory already exists',
        directory.path,
      );
    }
    await directory.create();
    _ownedDirectory = directory;
    final source = File(p.join(directory.path, fileName));
    await source.create(exclusive: true);
    _ownedSource = source;
    if (_cancelled) return _cancelledResult();
    _stage = 'producer_failed';
    await producer(source.path);
    if (_cancelled) return _cancelledResult();
    _stage = 'staging_failed';
    await _checkRoot();
    if (await FileSystemEntity.type(source.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await source.resolveSymbolicLinks() != source.path ||
        await source.length() == 0) {
      throw FileSystemException(
        'Producer did not create a regular PDF file',
        source.path,
      );
    }
    if (_cancelled) return _cancelledResult();
    _stage = 'native_failed';
    _nativeStarted = true;
    final outcome = await coordinator._backend.exportFile(
      MobilePdfExportRequest(
        operationId: id,
        sourcePath: source.path,
        fileName: fileName,
      ),
    );
    _stage = 'invalid_native_result';
    return outcome.checkedFor(id);
  }

  Future<void> _checkRoot() async {
    final root = _rootPath!;
    if (await FileSystemEntity.type(root, followLinks: false) !=
            FileSystemEntityType.directory ||
        await Directory(root).resolveSymbolicLinks() != root) {
      throw FileSystemException('Export root is not the owned directory', root);
    }
  }

  Future<void> _cleanup() async {
    final directory = _ownedDirectory;
    if (directory == null) return;
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) return;
    await _checkRoot();
    if (type == FileSystemEntityType.link) {
      await Link(directory.path).delete();
      return;
    }
    if (type != FileSystemEntityType.directory ||
        await directory.resolveSymbolicLinks() != directory.path) {
      throw FileSystemException(
        'Export directory changed before cleanup',
        directory.path,
      );
    }
    final source = _ownedSource;
    if (source != null) {
      final sourceType = await FileSystemEntity.type(
        source.path,
        followLinks: false,
      );
      if (sourceType == FileSystemEntityType.file) {
        await source.delete();
      } else if (sourceType == FileSystemEntityType.link) {
        await Link(source.path).delete();
      } else if (sourceType != FileSystemEntityType.notFound) {
        throw FileSystemException(
          'Export source changed before cleanup',
          source.path,
        );
      }
    }
    // An unexpected sibling is not ours to remove. Native may already have
    // removed this child; otherwise delete only a now-empty directory.
    await coordinator._deleteStagingDirectory(directory);
  }

  void _logFailure(String stage, Object error, StackTrace stack) {
    developer.log(
      'Mobile PDF export: $stage',
      name: 'otzaria.pdf_file_export',
      error: error,
      stackTrace: stack,
    );
  }
}
