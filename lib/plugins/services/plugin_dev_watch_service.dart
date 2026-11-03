import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/plugins/models/installed_plugin.dart';

class PluginDevFsChange {
  final String pluginId;
  final bool manifestChanged;

  PluginDevFsChange({
    required this.pluginId,
    required this.manifestChanged,
  });
}

class PluginDevWatchService {
  static PluginDevWatchService? _shared;
  static int _users = 0;

  /// כל חלונות ה-isolate חולקים מאזין קבצים אחד.
  static PluginDevWatchService acquire() {
    _users++;
    return _shared ??= PluginDevWatchService();
  }

  static void release() {
    if (--_users != 0) return;
    _shared?.dispose();
    _shared = null;
  }

  final _handled = Expando<Future<void>>();

  /// הטעינה מתבצעת פעם אחת; כל חלון ממתין לאותה תוצאה ומרענן את ה-UI שלו.
  Future<void> handleOnce(
    PluginDevFsChange change,
    Future<void> Function() reload,
  ) => _handled[change] ??= Future.sync(reload);

  final Map<String, _WatchIsolate> _watchers = {};
  final Map<String, String> _watchedPaths = {};

  final _eventsController = StreamController<PluginDevFsChange>.broadcast();
  Stream<PluginDevFsChange> get events => _eventsController.stream;

  /// מסתיים כשה-isolate של [pluginId] כבר מאזין לתיקייה.
  @visibleForTesting
  Future<void> watching(String pluginId) =>
      _watchers[pluginId]?.ready.future ?? Future<void>.value();

  void syncWatchers(List<InstalledPlugin> devPlugins) {
    // localhost_dev plugins reload via HMR — no filesystem to watch.
    final newIds = devPlugins
        .where((p) => !p.isLocalhostDev)
        .map((e) => e.pluginId)
        .toSet();
    final currentIds = _watchers.keys.toSet();

    for (final currId in currentIds) {
      if (!newIds.contains(currId)) {
        stopWatcher(currId);
      }
    }

    for (final plugin in devPlugins) {
      if (plugin.isLocalhostDev) continue;
      if (!_watchers.containsKey(plugin.pluginId) ||
          _watchedPaths[plugin.pluginId] != plugin.devRootPath) {
        if (_watchers.containsKey(plugin.pluginId)) {
          stopWatcher(plugin.pluginId);
        }
        _startWatcher(plugin);
      }
    }
  }

  // ב-Windows ה-SDK מריץ stat סינכרוני על כל אירוע בתוך ה-isolate המאזין (#3984),
  // ולכן ההאזנה כולה רצה ב-isolate נפרד.
  void _startWatcher(InstalledPlugin plugin) {
    final devRootPath = plugin.devRootPath;
    if (devRootPath == null) return;
    final pluginId = plugin.pluginId;

    final watcher = _WatchIsolate();
    _watchers[pluginId] = watcher;
    _watchedPaths[pluginId] = devRootPath;

    watcher.port.listen((message) {
      if (message is bool) {
        _eventsController.add(
          PluginDevFsChange(pluginId: pluginId, manifestChanged: message),
        );
      } else if (message == _readyMessage) {
        watcher.markReady();
      } else if (message == _missingMessage && _watchers[pluginId] == watcher) {
        stopWatcher(pluginId);
      }
    });
    watcher.isolate =
        Isolate.spawn(_watchIsolateMain, (
          watcher.port.sendPort,
          devRootPath,
        ), debugName: 'plugin-dev-watch:$pluginId').then((isolate) {
          if (watcher.closed) isolate.kill(priority: Isolate.immediate);
          return isolate;
        });
  }

  void stopWatcher(String pluginId) {
    _watchers.remove(pluginId)?.close();
    _watchedPaths.remove(pluginId);
  }

  void dispose() {
    for (final watcher in _watchers.values) {
      watcher.close();
    }
    _watchers.clear();
    _watchedPaths.clear();
    _eventsController.close();
  }
}

const _readyMessage = 'ready';
const _missingMessage = 'missing';

class _WatchIsolate {
  final port = ReceivePort();
  final ready = Completer<void>();
  Future<Isolate>? isolate;
  bool closed = false;

  void markReady() {
    if (!ready.isCompleted) ready.complete();
  }

  void close() {
    closed = true;
    port.close();
    markReady();
    isolate?.then((i) => i.kill(priority: Isolate.immediate));
  }
}

bool _isIgnoredFile(String basename) =>
    basename == '.DS_Store' ||
    basename == 'Thumbs.db' ||
    basename.endsWith('.swp') ||
    basename.endsWith('.tmp') ||
    basename.endsWith('~') ||
    basename.endsWith('.ts') ||
    basename.endsWith('.tsx') ||
    basename.endsWith('.scss') ||
    basename.endsWith('.sass');

/// שולח `bool` (האם manifest.json השתנה) לכל קבוצת שינויים אחרי debounce.
void _watchIsolateMain((SendPort, String) args) {
  final (sendPort, devRootPath) = args;
  final dir = Directory(devRootPath);
  if (!dir.existsSync()) {
    sendPort.send(_missingMessage);
    return;
  }

  final manifestPath = p.normalize(p.join(devRootPath, 'manifest.json'));
  final pending = <String>{};
  Timer? debounce;

  dir.watch(recursive: true).listen((event) {
    if (_isIgnoredFile(p.basename(event.path))) return;
    pending.add(event.path);
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), () {
      if (pending.isEmpty) return;
      final manifestChanged = pending.any(
        (path) => p.normalize(path) == manifestPath,
      );
      pending.clear();
      sendPort.send(manifestChanged);
    });
  });
  sendPort.send(_readyMessage);
}
