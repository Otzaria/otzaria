import 'dart:convert';
import 'dart:io';

import 'package:otzaria/core/app_paths.dart';
import 'package:path/path.dart' as p;

/// תוצאת טיפול בבקשת `otzaria://plugin/install-local`.
enum PluginInstallOutcome {
  installed('installed'),
  updated('updated'),
  cancelled('cancelled'),
  failed('failed'),
  rejectedOlder('rejected_older'),
  rejectedIncompatible('rejected_incompatible');

  const PluginInstallOutcome(this.wireName);

  final String wireName;
}

/// יומן התוצאות שהמעדכן הלא-מקוון קורא כדי לדעת מה עלה בגורל תוסף שמסר
/// לאוצריא. שורת JSON לכל בקשה; הקורא מתאים לפי `path` ו-`at`.
class PluginInstallResultsLog {
  PluginInstallResultsLog({
    Future<String> Function()? resolveDataRoot,
    DateTime Function()? now,
  }) : _resolveDataRoot = resolveDataRoot ?? AppPaths.getDataRootPath,
       _now = now ?? DateTime.now;

  static final PluginInstallResultsLog instance = PluginInstallResultsLog();

  static const String fileName = 'plugin_install_results.jsonl';

  /// הערך של `pluginInstallResults` ב-otzaria_capabilities.json.
  static const int formatVersion = 1;

  static const int _maxLines = 500;
  static const int _keptLines = 200;

  final Future<String> Function() _resolveDataRoot;
  final DateTime Function() _now;
  Future<void> _pending = Future.value();

  Future<void> append({
    required String path,
    required PluginInstallOutcome outcome,
    String? pluginId,
    String? version,
    String? message,
  }) {
    final line = jsonEncode({
      'path': path,
      'pluginId': pluginId,
      'version': version,
      'outcome': outcome.wireName,
      'message': message,
      'at': _now().toUtc().toIso8601String(),
    });
    final write = _pending.then((_) => _write(line));
    // כשל של כתיבה אחת מגיע לקורא שלה ואינו חוסם את הבאות בתור.
    _pending = write.catchError((Object _) {});
    return write;
  }

  Future<void> _write(String line) async {
    final file = File(p.join(await _resolveDataRoot(), fileName));
    await file.parent.create(recursive: true);
    await file.writeAsString('$line\n', mode: FileMode.append, flush: true);

    final lines = (await file.readAsLines())
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.length <= _maxLines) return;
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      '${lines.sublist(lines.length - _keptLines).join('\n')}\n',
      flush: true,
    );
    await tmp.rename(file.path);
  }
}
