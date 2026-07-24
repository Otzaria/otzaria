import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:otzaria/plugins/models/installed_plugin.dart';

class PluginDevFsChange {
  final String pluginId;
  final bool manifestChanged;
  final Set<String> changedPaths;

  PluginDevFsChange({
    required this.pluginId,
    required this.manifestChanged,
    required this.changedPaths,
  });
}

class PluginDevWatchService {
  final Map<String, StreamSubscription<FileSystemEvent>> _watchers = {};
  final Map<String, String> _watchedPaths = {};
  final Map<String, Timer> _debounceTimers = {};
  final Map<String, Set<String>> _pendingChanges = {};

  final _eventsController = StreamController<PluginDevFsChange>.broadcast();
  Stream<PluginDevFsChange> get events => _eventsController.stream;

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

  void _startWatcher(InstalledPlugin plugin) {
    final devRootPath = plugin.devRootPath;
    if (devRootPath == null) return;

    final dir = Directory(devRootPath);
    if (!dir.existsSync()) return;

    _watchedPaths[plugin.pluginId] = devRootPath;

    _watchers[plugin.pluginId] = dir.watch(recursive: true).listen((event) {
      final changedPath = event.path;
      final basename = p.basename(changedPath);

      if (basename == '.DS_Store' ||
          basename == 'Thumbs.db' ||
          basename.endsWith('.swp') ||
          basename.endsWith('.tmp') ||
          basename.endsWith('~') ||
          basename.endsWith('.ts') ||
          basename.endsWith('.tsx') ||
          basename.endsWith('.scss') ||
          basename.endsWith('.sass')) {
        return;
      }

      _pendingChanges.putIfAbsent(plugin.pluginId, () => <String>{});
      _pendingChanges[plugin.pluginId]!.add(changedPath);

      _debounceTimers[plugin.pluginId]?.cancel();
      _debounceTimers[plugin.pluginId] = Timer(
        const Duration(milliseconds: 300),
        () {
          _emitChange(plugin.pluginId, devRootPath);
        },
      );
    });
  }

  void _emitChange(String pluginId, String devRootPath) {
    final changes = _pendingChanges[pluginId] ?? <String>{};
    if (changes.isEmpty) return;

    final manifestPath = p.join(devRootPath, 'manifest.json');
    final manifestChanged =
        changes.contains(manifestPath) ||
        changes.any((path) => p.normalize(path) == p.normalize(manifestPath));

    final changeEvent = PluginDevFsChange(
      pluginId: pluginId,
      manifestChanged: manifestChanged,
      changedPaths: Set.from(changes),
    );

    _pendingChanges[pluginId]?.clear();
    _eventsController.add(changeEvent);
  }

  void stopWatcher(String pluginId) {
    _debounceTimers[pluginId]?.cancel();
    _debounceTimers.remove(pluginId);
    _watchers[pluginId]?.cancel();
    _watchers.remove(pluginId);
    _watchedPaths.remove(pluginId);
    _pendingChanges.remove(pluginId);
  }

  void dispose() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    for (final sub in _watchers.values) {
      sub.cancel();
    }
    _watchers.clear();
    _watchedPaths.clear();
    _pendingChanges.clear();
    _eventsController.close();
  }
}
