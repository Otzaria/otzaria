import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_artifact_builder.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_delta_applier.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_fetcher.dart';
import 'package:otzaria/core/netfree_certificates.dart';
import 'package:path/path.dart' as p;
import 'package:seforim_library_updater/seforim_library_updater.dart';

/// Progress of [AttachedUpdateDownloader.download]; `total == 0` while the
/// parts are assembled and hashed.
typedef AttachedUpdateProgress = void Function(int received, int total);

/// מוריד ומרכיב ארטיפקט עדכון ב-isolate נפרד.
///
/// Download, per-part sha256, zstd and the final sha256 of a multi-GB file
/// would each stall frames on the UI isolate, so the whole pipeline runs in
/// one worker isolate that trusts the NetFree CAs itself.
class AttachedUpdateDownloader {
  const AttachedUpdateDownloader({
    this.fetcher,
    this.builder = const AttachedUpdateArtifactBuilder(),
    this.deltaApplier = const AttachedUpdateDeltaApplier(),
    this.certificates = loadNetfreeCaBytes,
    this.progressInterval = const Duration(milliseconds: 200),
  });

  /// Null means a default [AttachedUpdateFetcher].
  final AttachedUpdateFetcher? fetcher;
  final AttachedUpdateArtifactBuilder builder;
  final AttachedUpdateDeltaApplier deltaApplier;
  final Future<List<Uint8List>> Function() certificates;
  final Duration progressInterval;

  /// Downloads [artifact] into [combinedPath] (resuming a partial file) and
  /// assembles the verified database at [outputPath]. A `zstd-patch` artifact
  /// needs [basePath] — the installed database, which is only read.
  Future<void> download(
    AttachedUpdateArtifact artifact, {
    required String combinedPath,
    required String outputPath,
    String? basePath,
    AttachedUpdateProgress? onProgress,
    AttachedUpdateProgress? onExtractionProgress,
    AttachedUpdateCancelToken? cancel,
  }) async {
    AttachedUpdateArtifactBuilder.checkCancelled(cancel);
    await AttachedUpdateArtifactBuilder.ensureDistinctPaths([
      combinedPath,
      outputPath,
      '$combinedPath.lock',
      '$outputPath.lock',
      if (basePath != null) basePath,
    ]);
    AttachedUpdateArtifactBuilder.checkCancelled(cancel);
    await Directory(p.dirname(combinedPath)).create(recursive: true);
    await Directory(p.dirname(outputPath)).create(recursive: true);
    await withFileOperationLock(
      outputPath,
      () => withFileOperationLock(
        combinedPath,
        () => _downloadLocked(
          artifact,
          combinedPath,
          outputPath,
          basePath,
          onProgress,
          onExtractionProgress,
          cancel,
        ),
      ),
    );
  }

  Future<void> _downloadLocked(
    AttachedUpdateArtifact artifact,
    String combinedPath,
    String outputPath,
    String? basePath,
    AttachedUpdateProgress? onProgress,
    AttachedUpdateProgress? onExtractionProgress,
    AttachedUpdateCancelToken? cancel,
  ) async {
    AttachedUpdateArtifactBuilder.checkCancelled(cancel);
    final certs = await certificates();
    AttachedUpdateArtifactBuilder.checkCancelled(cancel);
    final events = ReceivePort();
    final drained = Completer<void>();
    SendPort? control;
    Object? callbackError;
    StackTrace? callbackStack;
    var stopRequested = false;
    void requestStop() {
      stopRequested = true;
      control?.send(null);
    }

    final unsubscribe = cancel?.onCancel(requestStop);
    final subscription = events.listen((message) {
      if (message == null) {
        if (!drained.isCompleted) drained.complete();
      } else if (message is SendPort) {
        control = message;
        if (stopRequested || (cancel?.isCancelled ?? false)) message.send(null);
      } else if (callbackError == null) {
        try {
          if (message is (int, int)) {
            onProgress?.call(message.$1, message.$2);
          } else if (message is (int, int, bool)) {
            if (onExtractionProgress != null) {
              onExtractionProgress(message.$1, message.$2);
            } else {
              onProgress?.call(message.$1, 0);
            }
          }
        } catch (error, stack) {
          callbackError = error;
          callbackStack = stack;
          requestStop();
        }
      }
    });
    final job = _Job(
      artifact: artifact,
      combinedPath: combinedPath,
      outputPath: outputPath,
      basePath: basePath,
      fetcher: fetcher ?? AttachedUpdateFetcher(),
      builder: builder,
      deltaApplier: deltaApplier,
      certificates: certs,
      events: events.sendPort,
      progressInterval: progressInterval,
    );
    var completed = false;
    try {
      final outcome = await _spawn(job);
      await drained.future;
      completed = outcome.$1 == null;
      if (callbackError != null) {
        Error.throwWithStackTrace(callbackError!, callbackStack!);
      }
      if (outcome.$1 != null) {
        Error.throwWithStackTrace(outcome.$1!, outcome.$2!);
      }
      AttachedUpdateArtifactBuilder.checkCancelled(cancel);
      if (stopRequested) throw const AttachedUpdateCancelled();
      final input = File(combinedPath);
      if (await input.exists()) await input.delete();
    } catch (_) {
      if (completed) {
        try {
          await File(outputPath).delete();
        } on FileSystemException {
          /* original error */
        }
      }
      rethrow;
    } finally {
      unsubscribe?.call();
      await subscription.cancel();
      events.close();
    }
  }

  // Outcome delivery is distinct from successful completion; the same-port
  // sentinel guarantees that even the last progress callback is observed.
  static Future<(Object?, StackTrace?)> _spawn(_Job job) =>
      Isolate.run(() async {
        try {
          await _run(job);
          return (null, null);
        } catch (error, stack) {
          return (error, stack);
        } finally {
          job.events.send(null);
        }
      });

  static Future<void> _run(_Job job) async {
    trustCertificates(job.certificates);
    final control = ReceivePort();
    final cancel = AttachedUpdateCancelToken();
    control.listen((_) => cancel.cancel());
    job.events.send(control.sendPort);
    try {
      final previousOutput = File(job.outputPath);
      if (await previousOutput.exists()) await previousOutput.delete();
      var last = DateTime.fromMillisecondsSinceEpoch(0);
      void extractionProgress(int written) {
        final now = DateTime.now();
        if (written < job.artifact.size &&
            now.difference(last) < job.progressInterval) {
          return;
        }
        last = now;
        job.events.send((written, job.artifact.size, true));
      }

      await job.fetcher.downloadParts(
        job.artifact.parts,
        job.combinedPath,
        cancel: cancel,
        onProgress: (received, total) {
          final now = DateTime.now();
          if (received < total && now.difference(last) < job.progressInterval) {
            return;
          }
          last = now;
          job.events.send((received, total));
        },
      );
      if (cancel.isCancelled) throw const AttachedUpdateCancelled();
      job.events.send((0, 0));
      last = DateTime.fromMillisecondsSinceEpoch(0);
      if (job.artifact.compression == AttachedUpdateCompression.zstdPatch) {
        final base = job.basePath;
        if (base == null) {
          throw const AttachedUpdateArtifactMismatch(
            'a zstd-patch artifact needs the installed database',
          );
        }
        await job.deltaApplier.apply(
          job.artifact,
          job.combinedPath,
          base,
          job.outputPath,
          cancel: cancel,
          onProgress: extractionProgress,
          retainInput: true,
        );
      } else {
        await job.builder.build(
          job.artifact,
          job.combinedPath,
          job.outputPath,
          cancel: cancel,
          onProgress: extractionProgress,
          retainInput: true,
        );
      }
      AttachedUpdateArtifactBuilder.checkCancelled(cancel);
    } catch (_) {
      try {
        await File(job.outputPath).delete();
      } on FileSystemException {
        /* original error */
      }
      rethrow;
    } finally {
      control.close();
    }
  }
}

class _Job {
  const _Job({
    required this.artifact,
    required this.combinedPath,
    required this.outputPath,
    required this.basePath,
    required this.fetcher,
    required this.builder,
    required this.deltaApplier,
    required this.certificates,
    required this.events,
    required this.progressInterval,
  });

  final AttachedUpdateArtifact artifact;
  final String combinedPath;
  final String outputPath;
  final String? basePath;
  final AttachedUpdateFetcher fetcher;
  final AttachedUpdateArtifactBuilder builder;
  final AttachedUpdateDeltaApplier deltaApplier;
  final List<Uint8List> certificates;
  final SendPort events;
  final Duration progressInterval;
}
