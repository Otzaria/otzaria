import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;

import 'perf_fixture.dart';

const installedProbeId = 'org.otzaria.installed-resource-probe';
const installedBackgroundId = '$installedProbeId.background';
const installedStoreId = 'otzaria.plugins_directory';
const installedStoreCommit = '4517d39c4ecab632aff98e1c0e414881695961aa';
const installedStoreHashes = {
  'manifest.json':
      'a40e4225682f948d657e94086217f8400b4d708ec1eaa958e37621113bd12feb',
  'index.html':
      'c6495a41ffc31a8e4b23828b3537c40478d0aa7d45a3cf680534e4e0cd0fed2f',
  'restore-state.js':
      'f0324b025009e9594135b17b911366388959ab5398c0485ac11b0316cd59332f',
  'i18n/en.js':
      '54f9ec3b69a2858d2a1bb0f6d80f641397c3ff1fd286a83cdb5e751af3366ef2',
  'background.html':
      '0110c549b0350222c63c098843c9b6debdcd61cebd57d91b11874f07426fc975',
};

// The app supplies the SDK, boot payload and native bridge. This page supplies
// only controlled workload commands; no host policy or SDK is replaced here.
const installedPluginProbeHtml = r'''<!doctype html>
<html lang="he" dir="rtl"><meta charset="utf-8">
<title>Installed plugin resource fixture</title>
<style>body{font:20px sans-serif;margin:24px}#scroll{height:240px;overflow:auto}
#lines{height:2400px;background:linear-gradient(#eee,#aaa)}input{width:80%}</style>
<h1>בדיקת מופע תוסף</h1><input id="text" aria-label="מצב הבדיקה">
<div id="scroll"><div id="lines">תוכן מקומי קבוע לבדיקת גלילה ושחזור</div></div>
<script>
(() => {
  'use strict';
  const text = document.getElementById('text');
  const scroll = document.getElementById('scroll');
  const token = Array.from(crypto.getRandomValues(new Uint32Array(4)),
    x => x.toString(16).padStart(8, '0')).join('');
  const state = {ready:false, documentToken:token, bootCount:0, boot:null,
    error:null, acks:{}, requests:0, replies:0, requestJsonBytes:0,
    replyJsonBytes:0, busyPending:false, busyResult:null};
  const bytes = value => new TextEncoder().encode(JSON.stringify(value)).length;
  const fail = error => { state.error = String(error && error.message || error); };
  async function call(method, args) {
    state.requests++; state.requestJsonBytes += bytes({method, args});
    const result = await Otzaria.call(method, args);
    state.replies++; state.replyJsonBytes += bytes(result);
    if (!result || result.success !== true) throw new Error(method + ': ' + JSON.stringify(result));
    return result.data;
  }
  function view() { return {version:1, text:text.value, scrollTop:scroll.scrollTop}; }
  async function save(value) {
    if (await call('plugin.setRestoreState', {state:value}) !== true)
      throw new Error('Snapshot acknowledgement was not true');
  }
  async function boot(payload) {
    state.bootCount++; state.boot = payload;
    if (state.bootCount !== 1) throw new Error('Document received duplicate boot');
    const restored = payload && payload.restore && payload.restore.state;
    if (restored) {
      if (restored.version !== 1 || typeof restored.text !== 'string')
        throw new Error('Invalid restore payload');
      text.value = restored.text; scroll.scrollTop = restored.scrollTop;
    }
    if (payload.app.runMode === 'foreground') await save(view());
    state.ready = true;
  }
  const actions = {
    async state(args) { text.value = args.text; scroll.scrollTop = args.scrollTop;
      await save(view()); return view(); },
    async noSnapshot() { await save(null); return true; },
    async unsaved(args) { return call('ui.setUnsavedChanges', {hasChanges:args.value}); },
    async service(args) { return args.value
      ? call('reader.addContextMenuItem', {id:'resource-probe', label:'בדיקה', contexts:['reader-selection']})
      : call('reader.removeContextMenuItem', {id:'resource-probe'}); },
    async busy() {
      state.busyPending = true;
      call('ui.showConfirm', {title:'Installed resource probe: pending RPC',
        content:'Controlled read-only pending RPC; the runner closes this dialog.'})
        .then(value => {state.busyResult = value;})
        .catch(fail).finally(() => {state.busyPending = false;});
      return true;
    },
    async backgroundDone() { return call('plugin.backgroundDone', {}); }
  };
  window.installedPluginProbe = {
    read() { return {...state, view:view(), visibility:document.visibilityState,
      userAgent:navigator.userAgent, sdkBooted:Otzaria._booted === true}; },
    command(id, name, args) {
      if (!state.ready || !actions[name]) throw new Error('Invalid probe command');
      Promise.resolve().then(() => actions[name](args || {}))
        .then(value => {state.acks[id] = {ok:true, value};})
        .catch(error => {state.acks[id] = {ok:false, error:String(error)}; fail(error);});
      return id;
    }
  };
  window.addEventListener('error', event => fail(event.message));
  window.addEventListener('unhandledrejection', event => fail(event.reason));
  window.addEventListener('plugin.boot', event => { boot(event.detail).catch(fail); });
})();
</script></html>''';

Future<void> rejectInstalledProbeLinks(String path) async {
  var current = p.normalize(p.absolute(path));
  while (true) {
    if (await FileSystemEntity.isLink(current)) {
      throw StateError('Probe paths must not traverse a symlink: $current');
    }
    final parent = p.dirname(current);
    if (p.equals(parent, current)) return;
    current = parent;
  }
}

Future<Map<String, String>> verifyInstalledStoreSource(Directory source) async {
  if (!p.isAbsolute(source.path)) {
    throw ArgumentError('The pinned store source path must be absolute.');
  }
  final actual = <String, String>{};
  for (final entry in installedStoreHashes.entries) {
    final path = p.join(source.path, entry.key);
    await rejectInstalledProbeLinks(path);
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError(
        'Pinned store input is not a regular file: ${entry.key}',
      );
    }
    final digest = (await sha256.bind(File(path).openRead()).first).toString();
    if (digest != entry.value) {
      throw StateError('Pinned store source mismatch: ${entry.key}');
    }
    actual[entry.key] = digest;
  }
  return actual;
}

/// Transport for physical-device builds; source bytes are checked before any
/// file is written. This is test input, not a production plugin installer.
Future<Directory> materializeInstalledStorePayload(
  Directory destination,
  String payload,
) async {
  if (!p.isAbsolute(destination.path)) {
    throw ArgumentError('Store transport destination must be absolute.');
  }
  await rejectInstalledProbeLinks(destination.path);
  if (await destination.exists() && !await destination.list().isEmpty) {
    throw StateError('Store transport destination must be empty.');
  }
  if (payload.isEmpty || payload.length > 256 * 1024) {
    throw ArgumentError(
      'Store transport must be nonempty and at most 256 KiB.',
    );
  }
  final compressed = base64Decode(payload);
  if (compressed.length > 128 * 1024) {
    throw ArgumentError('Compressed store transport exceeds 128 KiB.');
  }
  final decoded = BytesBuilder(copy: false);
  await for (final chunk in gzip.decoder.bind(Stream.value(compressed))) {
    if (decoded.length + chunk.length > 512 * 1024) {
      throw ArgumentError('Decoded store transport exceeds 512 KiB.');
    }
    decoded.add(chunk);
  }
  final contents = jsonDecode(utf8.decode(decoded.takeBytes()));
  if (contents is! Map ||
      contents.length != installedStoreHashes.length ||
      !contents.keys.every(installedStoreHashes.containsKey)) {
    throw ArgumentError(
      'Store transport must contain exactly the five pinned paths.',
    );
  }
  final verified = <String, List<int>>{};
  for (final entry in installedStoreHashes.entries) {
    final text = contents[entry.key];
    if (text is! String) {
      throw ArgumentError('Store transport files must be UTF-8 text.');
    }
    final bytes = utf8.encode(text);
    if (sha256.convert(bytes).toString() != entry.value) {
      throw StateError('Store transport hash mismatch: ${entry.key}');
    }
    verified[entry.key] = bytes;
  }
  await destination.create(recursive: true);
  for (final entry in verified.entries) {
    final file = File(p.join(destination.path, entry.key));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(entry.value, flush: true);
  }
  await verifyInstalledStoreSource(destination);
  return destination;
}

class InstalledPluginFixture {
  InstalledPluginFixture(this.root, this.storeSource);

  final Directory root;
  final Directory storeSource;
  late PerfFixture appFixture;
  late Map<String, String> sourceHashes;
  late String identity;
  final installedIds = <String>[];

  Future<void> prepare() async {
    if (!p.isAbsolute(root.path) ||
        p.isWithin(root.path, storeSource.path) ||
        p.isWithin(storeSource.path, root.path) ||
        p.equals(root.path, storeSource.path)) {
      throw ArgumentError('Use separate absolute fixture and source paths.');
    }
    await rejectInstalledProbeLinks(root.path);
    if (await root.exists() && !await root.list().isEmpty) {
      throw StateError('Installed probe requires a fresh empty fixture root.');
    }
    sourceHashes = await verifyInstalledStoreSource(storeSource);
    await root.create(recursive: true);
    appFixture = PerfFixture(Directory(p.join(root.path, 'app-fixture')));
    await appFixture.prepare(preparationOnly: true);
    // The pinned store needs network permission, served only by the local
    // fail-closed catalog fixture. All update/sync/analytics settings stay off.
    final settings = await Hive.openBox<dynamic>(
      HiveCache.keyName,
      path: appFixture.appDataPath,
    );
    try {
      await settings.put(SettingsRepository.keyOfflineMode, false);
    } finally {
      await settings.close();
    }
    identity = sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'schema': 1,
              'appFixture': appFixture.id,
              'controlledHtml': sha256
                  .convert(utf8.encode(installedPluginProbeHtml))
                  .toString(),
              'storeSource': sourceHashes,
            }),
          ),
        )
        .toString();
    await File(
      p.join(root.path, '.otzaria-installed-plugin-probe'),
    ).writeAsString(
      jsonEncode({'schemaVersion': 1, 'fixtureSha256': identity}),
      flush: true,
    );
  }

  Future<void> installControlled(String id, {bool background = false}) async {
    final directory = await Directory(p.join(root.path, id)).create();
    await File(p.join(directory.path, 'index.html')).writeAsString(
      installedPluginProbeHtml,
    );
    final permissions = background
        ? ['app.run_on_startup', 'app.startup_contributions']
        : ['reader.context_menu'];
    final manifest = PluginManifest.fromJson({
      'schemaVersion': 1,
      'id': id,
      'name': 'בדיקת משאבי תוסף',
      'version': '1.0.0',
      'entrypoint': 'index.html',
      'permissions': permissions,
      'network': {'enabled': false},
      'contributes': {
        'toolTab': {'allowMultipleInstances': true},
        if (background) ...{
          'background': {'entrypoint': 'index.html'},
          'startup': {
            'activationEvents': ['app.startup'],
          },
        },
      },
    });
    await _save(manifest, directory, {
      for (final permission in permissions) permission: true,
    });
  }

  Future<void> installStore() async {
    final destination = await Directory(
      p.join(root.path, 'pinned-store'),
    ).create();
    for (final name in installedStoreHashes.keys) {
      final output = File(p.join(destination.path, name));
      await output.parent.create(recursive: true);
      await File(p.join(storeSource.path, name)).copy(output.path);
    }
    await verifyInstalledStoreSource(destination);
    final raw = await File(
      p.join(destination.path, 'manifest.json'),
    ).readAsString();
    final manifest = PluginManifest.fromJson(
      jsonDecode(raw.replaceFirst('\uFEFF', '')) as Map<String, dynamic>,
    );
    if (manifest.id != installedStoreId || manifest.version != '2.13.0') {
      throw StateError('Unexpected pinned store identity');
    }
    await _save(manifest, destination, {
      for (final permission in manifest.permissions)
        permission: permission == 'network.access',
    });
  }

  Future<void> _save(
    PluginManifest manifest,
    Directory directory,
    Map<String, bool> permissions,
  ) async {
    final now = DateTime.utc(2020);
    await PluginRegistryRepository().savePluginWithPermissions(
      InstalledPlugin(
        pluginId: manifest.id,
        name: manifest.name,
        version: manifest.version,
        installPath: directory.path,
        entrypointPath: 'index.html',
        enabled: true,
        pinned: false,
        manifest: manifest,
        installedAt: now,
        updatedAt: now,
      ),
      permissions,
    );
    installedIds.add(manifest.id);
  }
}
