import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:path/path.dart' as p;

/// Deliberately ignores plugin.suspended, to observe the native scheduler.
/// Production plugins should stop their own recurring work on that event.
/// No network, media, SDK RPC or logging runs during a quiet interval.
const appleActivityFixtureHtml = r'''<!doctype html><html lang="en">
<meta charset="utf-8"><title>Apple plugin activity fixture</title>
<h1>Apple activity fixture</h1><p>Local, bounded, timestamped work.</p>
<script>
(() => {
  'use strict';
  const capacity = 32768;
  const token = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
  let phase = 'boot';
  let armCount = 0;
  let stateCanary = 'not-armed';
  let bootCount = 0;
  let boot = null;
  let ready = false;
  const errors = [];
  let droppedErrors = 0;
  const lifecycle = [];
  const commands = [];
  const streams = {};
  const stamp = () => ({wallMs: Date.now(), monoMs: performance.now()});
  function reset(name) {
    streams[name] = {total: 0, dropped: 0, callbacks: []};
  }
  for (const name of ['interval', 'raf', 'localAsync']) reset(name);
  function record(name) {
    const stream = streams[name];
    stream.total++;
    if (stream.callbacks.length < capacity) stream.callbacks.push(stamp());
    else stream.dropped++;
  }
  setInterval(() => record('interval'), 250);
  function frame() { record('raf'); requestAnimationFrame(frame); }
  requestAnimationFrame(frame);
  async function localAsync() {
    // A timer, a Promise continuation and a local computation. This is not an
    // Otzaria RPC, so it cannot renew the background host's idle lease.
    await new Promise(resolve => setTimeout(resolve, 349));
    await Promise.resolve(17 * 23);
    record('localAsync');
    void localAsync();
  }
  void localAsync();
  for (const topic of ['plugin.suspended', 'plugin.resumed']) {
    window.addEventListener(topic, () => {
      if (lifecycle.length < 256) lifecycle.push({topic, ...stamp()});
    });
  }
  window.addEventListener('plugin.boot', event => {
    bootCount++;
    boot = {runMode: event.detail.app.runMode,
            instanceId: event.detail.app.instanceId ?? null};
    if (ready) return;
    // The installed host injects this SDK. Never substitute a fixture stub.
    Otzaria.on('reader.context_menu_item_clicked', detail => {
      if (commands.length < 256) commands.push({nonce: detail.probeNonce, ...stamp()});
    });
    ready = true;
  });
  function fail(error) {
    if (errors.length < 256) errors.push(String(error));
    else droppedErrors++;
  }
  window.addEventListener('error', e => fail(e.message));
  window.addEventListener('unhandledrejection', e => fail(e.reason));
  window.appleActivity = {
    arm(name) {
      if (!ready) throw new Error('The real plugin SDK has not booted');
      phase = name;
      stateCanary = `${token}/local-state/${name}/${++armCount}`;
      for (const name of Object.keys(streams)) reset(name);
      return this.read();
    },
    read() {
      return {schemaVersion: 1, phase, documentToken: token, stateCanary, bootCount, boot,
        ready, timeOrigin: performance.timeOrigin, readAt: stamp(),
        documentHidden: document.hidden, visibilityState: document.visibilityState,
        streams, lifecycle, commands, errors, droppedErrors};
    }
  };
})();
</script></html>''';

const appleForegroundId = 'org.otzaria.apple-activity.foreground';
const appleKeepAliveId = 'org.otzaria.apple-activity.keep-alive';
const appleIdleControlId = 'org.otzaria.apple-activity.idle-control';

String get appleActivityFixtureSha256 =>
    sha256.convert(utf8.encode(appleActivityFixtureHtml)).toString();

/// Called after app.main has initialized Settings and the normal registry.
Future<void> installAppleActivityFixture(
  Directory root,
  String id, {
  bool background = false,
  bool keepAlive = false,
}) async {
  if (keepAlive && !background) {
    throw ArgumentError('Only the background fixture may request keep-alive.');
  }
  final directory = await Directory(p.join(root.path, id)).create();
  await File(p.join(directory.path, 'index.html')).writeAsString(
    appleActivityFixtureHtml,
    flush: true,
  );
  final permissions = [
    'reader.context_menu',
    if (background) ...['app.run_on_startup', 'app.startup_contributions'],
    if (keepAlive) 'app.background_keep_alive',
  ];
  final manifest = PluginManifest.fromJson({
    'schemaVersion': 1,
    'id': id,
    'name': 'Apple activity fixture',
    'version': '1.0.0',
    'entrypoint': 'index.html',
    'permissions': permissions,
    'network': {'enabled': false},
    if (background) 'background': {'entrypoint': 'index.html'},
    'contributes': {
      'toolTab': {'allowMultipleInstances': true},
      if (background)
        'startup': {
          'activationEvents': ['app.startup'],
          'keepAlive': keepAlive,
        },
    },
  });
  await PluginRegistryRepository().savePluginWithPermissions(
    InstalledPlugin(
      pluginId: id,
      name: manifest.name,
      version: manifest.version,
      installPath: directory.path,
      entrypointPath: 'index.html',
      enabled: true,
      pinned: false,
      manifest: manifest,
      installedAt: DateTime.utc(2020),
      updatedAt: DateTime.utc(2020),
    ),
    {for (final permission in permissions) permission: true},
  );
}
