import 'dart:convert';
import 'dart:io';

import 'package:otzaria/core/app_paths.dart';
import 'package:path/path.dart' as p;

/// תור פשוט לבקשות פתיחה חיצוניות שמגיעות ממופע נוסף של האפליקציה.
class ExternalActivationQueue {
  final String? queueFilePath;

  /// התור בשורש הנתונים, שגרסאות קודמות כתבו אליו.
  final String? legacyQueueFilePath;

  const ExternalActivationQueue({this.queueFilePath, this.legacyQueueFilePath});

  Future<String> resolveQueueFilePath() => _resolveQueueFilePath();

  Future<void> enqueueUriString(String uriString) async {
    final queueFile = File(await _resolveQueueFilePath());
    await queueFile.parent.create(recursive: true);

    final record = jsonEncode({
      'uri': uriString,
      'createdAt': DateTime.now().toIso8601String(),
    });

    await queueFile.writeAsString(
      '$record\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<List<String>> drainUriStrings() async =>
      _drainFile(await _resolveQueueFilePath());

  /// מנקז את התור בנתיב הישן; אין צורך לנטר אותו.
  Future<List<String>> drainLegacyUriStrings() async {
    final legacyPath = await _resolveLegacyQueueFilePath();
    return legacyPath == null ? const [] : _drainFile(legacyPath);
  }

  Future<List<String>> _drainFile(String queuePath) async {
    final queueFile = File(queuePath);
    final processingFile = File('$queuePath.processing');

    await _recoverProcessingFile(queueFile, processingFile);

    if (!await queueFile.exists()) {
      return const [];
    }

    try {
      await queueFile.rename(processingFile.path);
    } on FileSystemException {
      return const [];
    }

    try {
      final uris = <String>[];
      for (final line in await processingFile.readAsLines()) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) {
          continue;
        }

        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map<String, dynamic>) {
            final uri = decoded['uri'];
            if (uri is String && uri.trim().isNotEmpty) {
              uris.add(uri);
            }
          }
        } catch (_) {
          // מתעלמים משורה פגומה כדי לא לחסום את שאר הבקשות.
        }
      }

      return uris;
    } finally {
      if (await processingFile.exists()) {
        await processingFile.delete();
      }
    }
  }

  Future<void> _recoverProcessingFile(
    File queueFile,
    File processingFile,
  ) async {
    if (!await processingFile.exists()) {
      return;
    }

    if (!await queueFile.exists()) {
      await processingFile.rename(queueFile.path);
      return;
    }

    final recoveredContent = await processingFile.readAsString();
    if (recoveredContent.isNotEmpty) {
      await queueFile.writeAsString(
        recoveredContent,
        mode: FileMode.append,
        flush: true,
      );
    }

    await processingFile.delete();
  }

  Future<String> _resolveQueueFilePath() async {
    if (queueFilePath != null && queueFilePath!.trim().isNotEmpty) {
      return queueFilePath!;
    }

    // תיקייה ייעודית: ניטור שורש הנתונים ב-Windows מריץ GetFileAttributes
    // סינכרוני על ה-UI thread לכל כתיבה בו (#3590).
    return p.join(
      await AppPaths.getDataRootPath(),
      'external_activations',
      'pending_external_activations.jsonl',
    );
  }

  Future<String?> _resolveLegacyQueueFilePath() async {
    if (legacyQueueFilePath != null) return legacyQueueFilePath;
    if (queueFilePath != null) return null;
    return p.join(
      await AppPaths.getDataRootPath(),
      'pending_external_activations.jsonl',
    );
  }
}

/// מריץ ניקוז אחד בכל פעם; קריאה שמגיעה באמצע ריצה גורמת לריצה נוספת
/// מיד אחריה, ולא נבלעת עד האירוע הבא.
class CoalescingDrainRunner {
  CoalescingDrainRunner(this._drain);

  final Future<void> Function() _drain;
  Future<void>? _active;
  bool _rerunRequested = false;

  Future<void> run() {
    final active = _active;
    if (active != null) {
      _rerunRequested = true;
      return active;
    }
    return _active = _loop();
  }

  Future<void> _loop() async {
    try {
      do {
        _rerunRequested = false;
        await _drain();
      } while (_rerunRequested);
    } finally {
      _active = null;
    }
  }
}
