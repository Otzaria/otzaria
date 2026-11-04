import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_dev_watch_service.dart';

InstalledPlugin _devPlugin(String root) => InstalledPlugin(
  pluginId: 'dev.watch',
  name: 'Dev',
  version: '1.0.0',
  installPath: root,
  entrypointPath: 'index.html',
  enabled: true,
  pinned: false,
  manifest: PluginManifest.fromJson({
    'schemaVersion': 1,
    'id': 'dev.watch',
    'name': 'Dev',
    'version': '1.0.0',
    'entrypoint': 'index.html',
  }),
  installedAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  sourceType: 'development',
  devRootPath: root,
);

void main() {
  late Directory root;
  late PluginDevWatchService service;
  late List<PluginDevFsChange> changes;
  late StreamSubscription<PluginDevFsChange> sub;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('plugin-dev-watch-');
    service = PluginDevWatchService();
    changes = [];
    sub = service.events.listen(changes.add);
  });

  tearDown(() async {
    await sub.cancel();
    service.dispose();
    await root.delete(recursive: true);
  });

  Future<PluginDevFsChange> nextChange(Future<void> Function() write) async {
    final next = service.events.first;
    await write();
    return next.timeout(const Duration(seconds: 5));
  }

  test('ה-watch לא נפתח ב-isolate הראשי (#3984)', () async {
    var mainIsolateWatches = 0;
    await IOOverrides.runZoned(
      () async {
        service.syncWatchers([_devPlugin(root.path)]);
        await service.watching('dev.watch');
      },
      fsWatch: (path, events, recursive) {
        mainIsolateWatches++;
        return const Stream<FileSystemEvent>.empty();
      },
    );
    expect(mainIsolateWatches, 0);
  });

  test('שינויים מגיעים מסוכמים וקבצים מסוננים לא מפעילים אירוע', () async {
    service.syncWatchers([_devPlugin(root.path)]);
    await service.watching('dev.watch');

    final script = await nextChange(
      () => File('${root.path}/index.js').writeAsString('a'),
    );
    expect(script.pluginId, 'dev.watch');
    expect(script.manifestChanged, isFalse);

    changes.clear();
    await File('${root.path}/main.ts').writeAsString('a');
    await File('${root.path}/build.tmp').writeAsString('a');
    await Future<void>.delayed(const Duration(milliseconds: 900));
    expect(changes, isEmpty);

    final manifest = await nextChange(
      () => File('${root.path}/manifest.json').writeAsString('{}'),
    );
    expect(manifest.manifestChanged, isTrue);
  });

  test('stopWatcher עוצר את ההאזנה', () async {
    service.syncWatchers([_devPlugin(root.path)]);
    await service.watching('dev.watch');
    service.stopWatcher('dev.watch');

    await File('${root.path}/index.js').writeAsString('a');
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(changes, isEmpty);
  });
}
