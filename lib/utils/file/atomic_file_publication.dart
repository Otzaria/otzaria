import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'file_publication_permissions.dart';
import 'file_publication_rename.dart';

class DesktopSaveTarget {
  final String path;
  final bool overwriteApproved;

  const DesktopSaveTarget({
    required this.path,
    this.overwriteApproved = false,
  });
}

final _pendingPublications = <String, Future<void>>{};

/// The producer must close its staging file before returning. Cancellation
/// returns false; producer and filesystem failures retain their original error.
Future<bool> publishFileAtomically({
  required DesktopSaveTarget target,
  required Future<void> Function(String stagingPath) producer,
  bool Function()? isCancelled,
}) async {
  if (isCancelled?.call() ?? false) return false;
  final requested = File(target.path).absolute;
  final parent = await requested.parent.resolveSymbolicLinks();
  final destination = File(p.join(parent, p.basename(requested.path)));
  await _checkOverwrite(destination.path, target.overwriteApproved);
  if (isCancelled?.call() ?? false) return false;

  final random = Random.secure();
  final suffix = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  // Plugin saves reclaim old .otztmp files; a long export may still be writing.
  final staging = await File(
    p.join(destination.parent.path, '.otzaria-save-$suffix.tmp'),
  ).create(exclusive: true);
  var published = false;
  var failed = false;
  try {
    makeFilePublicationPrivate(staging.path);
    if (Platform.isWindows) {
      await preserveFilePublicationPermissions(destination.path, staging.path);
    }
    if (isCancelled?.call() ?? false) return false;
    await producer(staging.path);
    if (isCancelled?.call() ?? false) return false;
    if (await FileSystemEntity.type(staging.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FileSystemException('Producer did not leave a file', staging.path);
    }
    final handle = await staging.open(mode: FileMode.append);
    Object? flushError;
    StackTrace? flushStack;
    try {
      await handle.flush();
    } catch (error, stack) {
      flushError = error;
      flushStack = stack;
    } finally {
      try {
        await handle.close();
      } catch (_) {
        if (flushError == null) rethrow;
      }
    }
    if (flushError != null) {
      Error.throwWithStackTrace(flushError, flushStack!);
    }

    final normalized = p.normalize(destination.path);
    final key = Platform.isWindows || Platform.isMacOS
        ? normalized.toLowerCase()
        : normalized;
    final previous = _pendingPublications[key];
    final completed = Completer<void>();
    _pendingPublications[key] = completed.future;
    try {
      if (previous != null) await previous;
      if (isCancelled?.call() ?? false) return false;
      await _checkOverwrite(destination.path, target.overwriteApproved);
      await preserveFilePublicationPermissions(destination.path, staging.path);
      if (isCancelled?.call() ?? false) return false;
      // Same-directory rename has filesystem-specific guarantees. Never fall
      // back to writing over the destination when replacement fails.
      if (target.overwriteApproved) {
        await staging.rename(destination.path);
      } else {
        await renamePublicationWithoutReplacing(staging.path, destination.path);
      }
      published = true;
      return true;
    } finally {
      if (identical(_pendingPublications[key], completed.future)) {
        _pendingPublications.remove(key);
      }
      completed.complete();
    }
  } catch (_) {
    failed = true;
    rethrow;
  } finally {
    if (!published) {
      try {
        await staging.delete();
      } on PathNotFoundException {
        // A failed producer may already have removed its partial output.
      } on FileSystemException {
        if (!failed) rethrow;
      }
    }
  }
}

Future<void> _checkOverwrite(String path, bool approved) async {
  if (!approved &&
      await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.notFound) {
    throw FileSystemException('Replacing this target was not approved', path);
  }
}
