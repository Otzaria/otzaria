import 'dart:async';
import 'dart:io';

import 'package:posix/posix.dart' as posix;

import 'print_pdf_source.dart';

/// משתף הפקה שטרם הושלמה ושומר קובץ נוכחי אחד עד להחלפת החתימה.
class PrintPdfFileCache {
  PrintPdfFileCache({Directory? temporaryDirectory})
    : _temporaryDirectory = temporaryDirectory ?? Directory.systemTemp;

  final Directory _temporaryDirectory;
  final _pending = <String, _FileEntry>{};
  final _entries = <_FileEntry>{};
  _FileEntry? _cached;
  String? _currentSignature;
  var _generation = 0;
  Completer<void>? _closed;
  (Object, StackTrace)? _cleanupError;

  Future<PrintPdfFileLease> acquire(
    String signature,
    Future<void> Function(String path) generate,
  ) {
    if (_closed != null) {
      throw StateError('The PDF file cache is closed.');
    }
    if (_currentSignature != signature) {
      _currentSignature = signature;
      _releaseCached();
    }
    final entry =
        _cached ??
        _pending.putIfAbsent(signature, () {
          final entry = _FileEntry(signature, _generation);
          _entries.add(entry);
          entry.ready = _produce(entry, generate);
          return entry;
        });
    entry.users++;
    return _acquireReady(entry);
  }

  Future<PrintPdfFileLease> _acquireReady(_FileEntry entry) async {
    try {
      await entry.ready;
      return PrintPdfFileLease._(entry.path!, () => _release(entry));
    } catch (error, stack) {
      try {
        await _release(entry);
      } catch (_) {
        // dispose reports cleanup failures without replacing this producer error.
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> _produce(
    _FileEntry entry,
    Future<void> Function(String path) generate,
  ) async {
    try {
      final directory = await _temporaryDirectory.createTemp('otzaria-print-');
      entry.directory = directory;
      if (Platform.isLinux || Platform.isMacOS) {
        try {
          posix.chmod(directory.path, '700');
        } on posix.PosixException catch (error) {
          throw FileSystemException(
            'Could not restrict the temporary PDF directory.',
            directory.path,
            OSError(error.message, error.code),
          );
        }
      }
      final file = File.fromUri(directory.uri.resolve('base.pdf'));
      entry.path = file.path;
      await generate(file.path);
      if (!await file.exists() || await file.length() == 0) {
        throw StateError('The PDF producer did not create a nonempty file.');
      }
      if (_closed == null &&
          entry.generation == _generation &&
          _currentSignature == entry.signature &&
          identical(_pending[entry.signature], entry)) {
        _cached = entry;
        entry.cached = true;
      }
    } finally {
      entry.finished = true;
      if (identical(_pending[entry.signature], entry)) {
        _pending.remove(entry.signature);
      }
      _cleanIfUnused(entry);
    }
  }

  /// מפקיע את בעלות המטמון; בקשות ומשתמשים קיימים ממשיכים להחזיק בקובץ.
  void invalidate() {
    _generation++;
    _currentSignature = null;
    _pending.clear();
    _releaseCached();
  }

  void _releaseCached() {
    final entry = _cached;
    _cached = null;
    if (entry == null) return;
    entry.cached = false;
    _cleanIfUnused(entry);
  }

  Future<void> _release(_FileEntry entry) {
    entry.users--;
    return _cleanIfUnused(entry) ?? Future<void>.value();
  }

  Future<void>? _cleanIfUnused(_FileEntry entry) {
    if (!entry.finished || entry.cached || entry.users != 0) return null;
    if (entry.cleanup != null) return entry.cleanup;
    final cleanup = entry.cleanup = _delete(entry.directory);
    cleanup.then(
      (_) {
        _entries.remove(entry);
        _completeClose();
      },
      onError: (Object error, StackTrace stack) {
        _cleanupError ??= (error, stack);
        _entries.remove(entry);
        _completeClose();
      },
    );
    return cleanup;
  }

  Future<void> _delete(Directory? directory) async {
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  /// ממתין גם להפקות ול-leases קיימים; יש לשחררם כדי שהסגירה תסתיים.
  Future<void> dispose() {
    if (_closed != null) return _closed!.future;
    _closed = Completer<void>();
    invalidate();
    _completeClose();
    return _closed!.future;
  }

  void _completeClose() {
    final closed = _closed;
    if (closed == null || closed.isCompleted || _entries.isNotEmpty) return;
    final error = _cleanupError;
    if (error == null) {
      closed.complete();
    } else {
      closed.completeError(error.$1, error.$2);
    }
  }
}

/// הקובץ נשאר חי עד שחרור כל המשתמשים, גם לאחר invalidation או סגירה.
class PrintPdfFileLease {
  PrintPdfFileLease._(String path, this._release) : _path = path;

  final String _path;
  final Future<void> Function() _release;
  Future<void>? _disposed;

  String get path {
    if (_disposed != null) throw StateError('The PDF file lease was released.');
    return _path;
  }

  PrintPdfSource get source => PrintPdfSource.file(path);

  Future<void> dispose() => _disposed ??= _release();
}

class _FileEntry {
  _FileEntry(this.signature, this.generation);

  final String signature;
  final int generation;
  late final Future<void> ready;
  Directory? directory;
  String? path;
  var users = 0;
  var cached = false;
  var finished = false;
  Future<void>? cleanup;
}
