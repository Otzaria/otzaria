import 'dart:async';
import 'dart:convert';

import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/database/plugin_database_service.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_network_gate.dart';

class FixtureRegistry extends PluginRegistryRepository {
  final denied = <String>{};
  final identities = <String>[];

  @override
  Future<bool?> getPermission(String pluginId, String permission) async {
    identities.add(pluginId);
    return !denied.contains('$pluginId:$permission');
  }
}

class FixtureServices implements PluginBridgeAdapter {
  FixtureServices(this.plugin, this.registry, this.storage);

  @override
  final InstalledPlugin plugin;
  final FixtureRegistry registry;
  final Map<String, Map<String, dynamic>> storage;
  final notifications = <Map<String, dynamic>>[];
  final requests = <String>[];
  final done = Completer<void>();
  final cancellations = <String>[];
  final cancelled = Completer<void>();
  final networkStarted = Completer<void>();
  final releaseNetwork = Completer<void>();
  bool holdNetwork = false;
  int calls = 0;
  Future<dynamic> Function(String, Map<String, dynamic>)? rpcOverride;

  @override
  Future<T> withWindowDependencies<T>(
    Future<T> Function() action, {
    String? domain,
    String? rpcAction,
  }) => action();

  @override
  Future<dynamic> execute(
    String domain,
    String action,
    Map<String, dynamic> args, {
    PluginRpcEventSink? eventSink,
  }) async {
    calls++;
    final method = '$domain.$action';
    requests.add(method);
    if (rpcOverride != null) return rpcOverride!(method, args);
    switch (method) {
      case 'network.fetchStream':
        final cancelId = args['__cancelStreamId'] as String?;
        if (cancelId != null) {
          cancellations.add(cancelId);
          if (!cancelled.isCompleted) cancelled.complete();
          return null;
        }
        final decision = await evaluatePluginNetworkAccess(
          uri: Uri.parse(args['url'] as String),
          pluginId: plugin.pluginId,
          manifest: plugin.manifest,
          registry: registry,
        );
        if (decision != PluginNetworkDecision.allowed) {
          throw PluginDatabaseException('error.forbidden', decision.name);
        }
        if (!networkStarted.isCompleted) networkStarted.complete();
        await eventSink!('__otzaria.network.fetchStream.chunk', {
          'streamId': args['__streamId'],
          'chunk': {
            'type': 'response',
            'status': 200,
            'ok': true,
            'headers': {},
          },
        });
        if (holdNetwork) {
          await Future.any([releaseNetwork.future, cancelled.future]);
          return null;
        }
        final body = jsonEncode([
          {
            'id': 'demo',
            'pluginUid': 'fixture.demo',
            'name': 'Demo',
            'version': '2.0.0',
          },
          {
            'id': 'new',
            'pluginUid': 'fixture.new',
            'name': 'New',
            'version': '1.0.0',
          },
          {
            'id': 'future',
            'pluginUid': 'fixture.future',
            'version': '9.0.0',
            'compatibleWith': '99.0.0',
          },
        ]);
        for (final part in [
          body.substring(0, body.length ~/ 2),
          body.substring(body.length ~/ 2),
        ]) {
          await eventSink('__otzaria.network.fetchStream.chunk', {
            'streamId': args['__streamId'],
            'chunk': {'type': 'data', 'body': part},
          });
        }
        return null;
      case 'plugin.listInstalled':
        return [
          {
            'pluginId': 'fixture.demo',
            'name': 'Demo',
            'version': '1.0.0',
            'sourceType': 'packaged',
          },
        ];
      case 'notifications.showInApp':
        notifications.add(Map.of(args));
        return null;
      case 'plugin.backgroundDone':
        if (!done.isCompleted) done.complete();
        return null;
      case 'storage.set':
        (storage[plugin.pluginId] ??= {})[args['key'] as String] =
            args['value'];
        return null;
      case 'storage.get':
        return storage[plugin.pluginId]?[args['key']];
      default:
        throw PluginDatabaseException(
          'error.unavailable',
          'No fixture for $method',
        );
    }
  }

  void cancelOutstanding() {
    if (!cancelled.isCompleted) cancelled.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

InstalledPlugin fixturePlugin(Map<String, dynamic> fixture, {String? id}) {
  final manifestJson = Map<String, dynamic>.from(fixture['manifest'] as Map);
  if (id != null) manifestJson['id'] = id;
  final manifest = PluginManifest.fromJson(manifestJson);
  return InstalledPlugin(
    pluginId: manifest.id,
    name: manifest.name,
    version: manifest.version,
    installPath: '',
    entrypointPath: manifest.entrypoint,
    enabled: true,
    pinned: false,
    manifest: manifest,
    installedAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

const fixtureAppContext = <String, dynamic>{
  'version': '1.0.0',
  'platform': 'linux',
  'runMode': 'background',
  'language': 'en',
};
