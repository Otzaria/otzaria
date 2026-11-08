import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/data/data_providers/hive_data_provider.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_network_access_resolver.dart';
import 'package:otzaria/plugins/services/plugin_network_fetch_service.dart';
import 'package:otzaria/plugins/services/plugin_network_gate.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:path/path.dart' as p;

import '../../../integration_test/support/installed_plugin_catalog.dart';
import '../../../integration_test/support/installed_plugin_fixture.dart';
import '../../../tool/perf_probe/src/installed_plugin_contract.dart';

Map<String, Object?> restoration(String scenario) => {
  'scenario': scenario,
  'sameInstanceId': true,
  'releasedByDispatcher': true,
  'controllerAbsentAfterDiscard': true,
  'hostWidgetRemovedBeforeRestore': true,
  'differentControllerObject': true,
  'differentNativeViewId': true,
  'differentDocument': true,
  'sdkBooted': true,
  'visibleStateMatches': true,
  'before': <String, Object?>{
    'pluginId': 'fixture',
    'instanceId': 'same',
    'nativeViewId': '41',
    'documentToken': 'old-document',
  },
  'after': <String, Object?>{
    'pluginId': 'fixture',
    'instanceId': 'same',
    'nativeViewId': '42',
    'documentToken': 'fresh-document',
  },
  'resumeMs': 12.5,
};

Map<String, Object?> completeReport() => {
  'phases': [
    for (final name in installedPluginRequiredPhases)
      {'name': name, 'status': 'passed'},
  ],
  'restorations': [
    for (final scenario in ['pressure', 'count', 'age', 'store'])
      restoration(scenario),
  ],
  'protectedControls': [
    for (final reason in [
      'noRestoreState',
      'unsavedChanges',
      'busyRpc',
      'contextMenu',
    ])
      {
        'firstBlockingReason': reason,
        'discardRequestId': 'one-request',
        'sameControllerAfterRequest': true,
        'released': false,
      },
  ],
  'quietWindows': [
    {'probeJsCalls': 0, 'probeNativeQueries': 0, 'elapsedMs': 1000.1},
  ],
  'policyRestored': true,
};

void main() {
  final preparedSource = Platform.environment['INSTALLED_PROBE_STORE_SOURCE'];
  group('document snapshot decoding', () {
    for (final raw in [null, 'null']) {
      test('a pending ${raw.runtimeType} reply cannot claim readiness', () {
        final value = decodeInstalledPluginSnapshot(raw);
        expect(value, isEmpty);
        expect(value['ready'], isNot(true));
        expect(value['sdkBooted'], isNot(true));
        expect(value['documentToken'], isNull);
      });
    }
    test('native maps and JSON preserve the observed document and view', () {
      const snapshot = <String, Object?>{
        'documentToken': 'new-store-document',
        'sdkBooted': true,
        'ready': true,
        'view': {'search': 'Fixture', 'scrollTop': 420},
      };
      expect(decodeInstalledPluginSnapshot(snapshot), snapshot);
      expect(decodeInstalledPluginSnapshot(jsonEncode(snapshot)), snapshot);
    });
    test('malformed non-null data remains a failure', () {
      for (final raw in [
        '{broken',
        '[]',
        'true',
        '7',
        '"ready"',
        <Object?>[],
        false,
        7,
        <Object, Object?>{1: 'invalid key'},
      ]) {
        expect(
          () => decodeInstalledPluginSnapshot(raw),
          throwsA(anyOf(isA<FormatException>(), isA<TypeError>())),
          reason: 'Non-object snapshot: $raw',
        );
      }
    });
  });
  group('restoration evidence contract', () {
    test(
      'accepts observed identity changes and the four complete scenarios',
      () {
        expect(installedReportErrors(completeReport()), isEmpty);
      },
    );
    for (final field in [
      'sameInstanceId',
      'releasedByDispatcher',
      'controllerAbsentAfterDiscard',
      'hostWidgetRemovedBeforeRestore',
      'differentControllerObject',
      'differentDocument',
      'sdkBooted',
      'visibleStateMatches',
    ]) {
      test('rejects missing $field even with preserved Dart state', () {
        final proof = restoration('pressure')..[field] = false;
        expect(installedRestoreErrors(proof), isNotEmpty);
      });
    }
    test('accepts a recycled native ID after real release and recreation', () {
      final proof = restoration('pressure')..['differentNativeViewId'] = false;
      (proof['after'] as Map)['nativeViewId'] =
          (proof['before'] as Map)['nativeViewId'];
      expect(installedRestoreErrors(proof), isEmpty);
    });
    test('native ID observation availability is not a lifecycle gate', () {
      final proof = restoration('pressure')..['differentNativeViewId'] = null;
      (proof['after'] as Map)['nativeViewId'] = null;
      expect(installedRestoreErrors(proof), isEmpty);
    });
    test('rejects a reused document even when claimed to be new', () {
      final proof = restoration('pressure');
      (proof['after'] as Map)['documentToken'] =
          (proof['before'] as Map)['documentToken'];
      expect(installedRestoreErrors(proof), isNotEmpty);
    });
    test('rejects a new instance masquerading as restored instance', () {
      final proof = restoration('pressure');
      (proof['after'] as Map)['instanceId'] = 'replacement';
      expect(installedRestoreErrors(proof), isNotEmpty);
    });
    test('rejects partial phases and a missing policy case', () {
      final report = completeReport();
      (report['phases'] as List).removeLast();
      (report['restorations'] as List).removeLast();
      expect(installedReportErrors(report), hasLength(2));
    });
    test('rejects guards subjected to different pressure requests', () {
      final report = completeReport();
      ((report['protectedControls'] as List).first as Map)['discardRequestId'] =
          'different';
      expect(installedReportErrors(report), isNotEmpty);
    });
    test('does not treat all possible blockers as first observed reasons', () {
      final report = completeReport();
      ((report['protectedControls'] as List).first
              as Map)['firstBlockingReason'] =
          'notReady';
      expect(installedReportErrors(report), isNotEmpty);
    });
    test('rejects a discarded protected instance', () {
      final report = completeReport();
      ((report['protectedControls'] as List).first as Map)['released'] = true;
      expect(installedReportErrors(report), isNotEmpty);
    });
    test('rejects JS and native queries in quiet windows', () {
      for (final key in ['probeJsCalls', 'probeNativeQueries']) {
        final report = completeReport();
        ((report['quietWindows'] as List).first as Map)[key] = 1;
        expect(installedReportErrors(report), isNotEmpty);
      }
    });
    test('rejects an override left installed after completion', () {
      expect(
        installedReportErrors(completeReport()..['policyRestored'] = false),
        isNotEmpty,
      );
    });
  });

  group('read-only local catalog transport', () {
    late InstalledProbeCatalog catalog;
    late PluginNetworkFetchService network;
    HttpOverrides? previous;
    setUp(() async {
      previous = HttpOverrides.current;
      catalog = InstalledProbeCatalog();
      await catalog.start();
      network = PluginNetworkFetchService();
    });
    tearDown(() async {
      network.dispose();
      await catalog.stop();
      expect(HttpOverrides.current, same(previous));
    });
    test(
      'real network service streams fixture catalog with exact source query spelling',
      () async {
        final response = await network.fetchStream(
          Uri.parse('https://otzaria.org/api/plugins?appVersion=0.9.98.1'),
        );
        expect(response.status, 200);
        final entries = jsonDecode(await response.body.join()) as List;
        expect(entries, hasLength(36));
        expect(
          entries.every(
            (entry) => (entry as Map)['pluginUid'].startsWith(
              'org.otzaria.catalog-fixture.',
            ),
          ),
          true,
        );
        expect(catalog.requests.single['result'], 'localFixture');
      },
    );
    test(
      'search returns controlled matching status and curated home is explicitly missing',
      () async {
        final response = await network.fetchStream(
          Uri.parse(
            'https://otzaria.org/api/plugins/search?q=Fixture&status=beta&limit=50',
          ),
        );
        final result = jsonDecode(await response.body.join()) as Map;
        expect(result['results'], hasLength(18));
        expect(
          (result['results'] as List).every(
            (entry) => (entry as Map)['status'] == 'beta',
          ),
          true,
        );
        final home = await network.fetchStream(
          Uri.parse('https://otzaria.org/api/plugins/store-home'),
        );
        expect(home.status, 404);
        await home.body.drain<void>();
      },
    );
    for (final entry in [
      ('POST', 'https://otzaria.org/api/plugins'),
      ('GET', 'https://otzaria.org/api/plugins/probe-1/download'),
      ('GET', 'https://otzaria.org/api/plugins/probe-1/install-token'),
      ('GET', 'https://example.invalid/api/plugins'),
      ('GET', 'http://otzaria.org/api/plugins'),
      ('GET', 'https://otzaria.org:444/api/plugins'),
      ('GET', 'https://user@otzaria.org/api/plugins'),
      ('GET', 'https://otzaria.org/api/plugins?unexpected=1'),
    ]) {
      test('blocks ${entry.$1} ${entry.$2} before network transport', () async {
        await expectLater(
          network.fetchStream(Uri.parse(entry.$2), method: entry.$1),
          throwsStateError,
        );
        expect(catalog.requests.single['result'], 'blockedBeforeTransport');
        expect(catalog.unexpectedBlockedRequests, hasLength(1));
      });
    }
    test(
      'keeps exact official GET refresh routes blocked and audited',
      () async {
        final expected = [
          PluginNetworkAccessResolver.officialAllowlistUri,
          PluginNetworkAccessResolver.officialAllowlistContentsApiUri,
        ];
        for (final uri in expected) {
          await expectLater(network.fetchStream(uri), throwsStateError);
        }
        expect(
          catalog.requests.map((request) => request['url']),
          expected.map((uri) => uri.toString()),
        );
        expect(
          catalog.requests.every(
            (request) =>
                request['result'] == 'blockedBeforeTransport' &&
                request['classification'] == 'expectedPolicyBootstrap',
          ),
          isTrue,
        );
        expect(catalog.unexpectedBlockedRequests, isEmpty);
        expect(catalog.toJson()['expectedPolicyBootstrapCount'], 2);
        expect(catalog.toJson()['unexpectedBlockedRequestCount'], 0);
      },
    );
    test(
      'does not excuse near-match or non-GET policy refresh traffic',
      () async {
        final raw = PluginNetworkAccessResolver.officialAllowlistUri;
        final api = PluginNetworkAccessResolver.officialAllowlistContentsApiUri;
        for (final (method, uri) in [
          ('POST', raw),
          ('HEAD', api),
          ('GET', raw.replace(scheme: 'http')),
          ('GET', raw.replace(port: 444)),
          ('GET', raw.replace(userInfo: 'probe')),
          ('GET', raw.replace(host: 'example.invalid')),
          ('GET', raw.replace(path: '${raw.path}/extra')),
          ('GET', raw.replace(fragment: 'extra')),
          ('GET', raw.replace(query: 'extra=1')),
          ('GET', api.replace(query: 'ref=main')),
          ('GET', api.replace(query: 'ref=dev&extra=1')),
          ('GET', api.replace(query: 'ref=dev&ref=dev')),
        ]) {
          await expectLater(
            network.fetchStream(uri, method: method),
            throwsStateError,
          );
          expect(catalog.requests.last['classification'], 'unexpectedRequest');
          expect(
            catalog.unexpectedBlockedRequests,
            hasLength(catalog.requests.length),
          );
        }
        expect(catalog.toJson()['expectedPolicyBootstrapCount'], 0);
      },
    );
    test(
      'retains unexpected order, duplicates and repeated refresh pairs',
      () async {
        final raw = PluginNetworkAccessResolver.officialAllowlistUri;
        final api = PluginNetworkAccessResolver.officialAllowlistContentsApiUri;
        for (final uri in [api, raw, raw, api, raw, api]) {
          await expectLater(network.fetchStream(uri), throwsStateError);
        }
        expect(catalog.requests.map((request) => request['classification']), [
          'unexpectedRequest',
          'expectedPolicyBootstrap',
          'unexpectedRequest',
          'expectedPolicyBootstrap',
          'unexpectedRequest',
          'unexpectedRequest',
        ]);
        expect(
          catalog.requests.every(
            (request) => request['result'] == 'blockedBeforeTransport',
          ),
          isTrue,
        );
        expect(catalog.unexpectedBlockedRequests, hasLength(4));
        expect(catalog.toJson()['expectedPolicyBootstrapCount'], 2);
        expect(catalog.toJson()['unexpectedBlockedRequestCount'], 4);
      },
    );
    test(
      'an expected fallback does not hide later blocked Store traffic',
      () async {
        await expectLater(
          network.fetchStream(PluginNetworkAccessResolver.officialAllowlistUri),
          throwsStateError,
        );
        expect(catalog.unexpectedBlockedRequests, isEmpty);
        expect(catalog.toJson()['unexpectedBlockedRequestCount'], 0);
        await expectLater(
          network.fetchStream(
            Uri.parse('https://otzaria.org/api/plugins/probe-1/install-token'),
          ),
          throwsStateError,
        );
        await catalog.stop();
        expect(HttpOverrides.current, same(previous));
        expect(catalog.requests, hasLength(2));
        expect(catalog.toJson()['expectedPolicyBootstrapCount'], 1);
        expect(catalog.unexpectedBlockedRequests, hasLength(1));
        expect(catalog.toJson()['unexpectedBlockedRequestCount'], 1);
      },
    );
  });

  test(
    'cold real Store permission resolver retains blocked fallback audit',
    () async {
      final temporary = await Directory(
        await Directory.systemTemp.resolveSymbolicLinks(),
      ).createTemp('installed-cold-policy-');
      final fixture = InstalledPluginFixture(
        Directory(p.join(temporary.path, 'app')),
        Directory(preparedSource!),
      );
      final catalog = InstalledProbeCatalog();
      final previous = HttpOverrides.current;
      PluginNetworkFetchService? network;
      try {
        await catalog.start();
        network = PluginNetworkFetchService();
        await fixture.prepare();
        await Settings.init(cacheProvider: HiveCache());
        await fixture.installStore();
        final registry = PluginRegistryRepository();
        final store = (await registry.getPlugin(installedStoreId))!;
        expect(
          PluginNetworkAccessResolver.instance.cachedOfficialAllowlist,
          isNull,
        );
        for (final permission in store.manifest.permissions) {
          expect(
            await registry.getPermission(installedStoreId, permission),
            permission == 'network.access',
          );
        }
        final uri = Uri.parse('https://otzaria.org/api/plugins');
        final allowed = await evaluatePluginNetworkAccess(
          uri: uri,
          pluginId: installedStoreId,
          manifest: store.manifest,
          registry: registry,
        );
        expect(allowed, PluginNetworkDecision.allowed);
        expect(catalog.requests.map((request) => request['url']), [
          PluginNetworkAccessResolver.officialAllowlistUri.toString(),
          PluginNetworkAccessResolver.officialAllowlistContentsApiUri
              .toString(),
        ]);
        expect(
          catalog.requests.every(
            (request) =>
                request['method'] == 'GET' &&
                request['result'] == 'blockedBeforeTransport' &&
                request['classification'] == 'expectedPolicyBootstrap',
          ),
          isTrue,
        );
        expect(
          PluginNetworkAccessResolver.instance.cachedOfficialAllowlist,
          isNull,
        );
        final response = await network.fetchStream(uri);
        expect(response.status, 200);
        expect(jsonDecode(await response.body.join()), hasLength(36));
        expect(catalog.unexpectedBlockedRequests, isEmpty);
        expect(catalog.toJson()['expectedPolicyBootstrapCount'], 2);
        expect(catalog.toJson()['requests'], hasLength(3));
        await registry.savePluginWithPermissions(store, {
          for (final permission in store.manifest.permissions)
            permission: false,
        });
        expect(
          await evaluatePluginNetworkAccess(
            uri: uri,
            pluginId: installedStoreId,
            manifest: store.manifest,
            registry: registry,
          ),
          PluginNetworkDecision.permissionMissing,
        );
        expect(catalog.requests, hasLength(3));
      } finally {
        network?.dispose();
        await catalog.stop();
        expect(HttpOverrides.current, same(previous));
        await PluginSystemDatabase.instance.close();
        await Hive.close();
        await temporary.delete(recursive: true);
      }
    },
    skip: preparedSource == null
        ? 'Pinned Store source is required; CI prepares it before these tests.'
        : false,
  );

  group('isolated fixture input guards', () {
    late Directory temporary;
    setUp(() async {
      temporary = await Directory(
        await Directory.systemTemp.resolveSymbolicLinks(),
      ).createTemp('installed-plugin-probe-test-');
    });
    tearDown(() async {
      await temporary.delete(recursive: true);
    });
    test(
      'rejects populated app roots without modifying existing bytes',
      () async {
        final root = await Directory(
          p.join(temporary.path, 'existing'),
        ).create();
        final userData = File(p.join(root.path, 'do-not-touch'));
        await userData.writeAsString('original');
        await expectLater(
          InstalledPluginFixture(
            root,
            Directory(p.join(temporary.path, 'source')),
          ).prepare(),
          throwsStateError,
        );
        expect(await userData.readAsString(), 'original');
        expect(await root.list().length, 1);
      },
    );
    test(
      'rejects source bytes that differ from pinned public commit',
      () async {
        await File(p.join(temporary.path, 'manifest.json')).writeAsString('{}');
        await expectLater(
          verifyInstalledStoreSource(temporary),
          throwsStateError,
        );
      },
    );
    test('rejects a directory in place of a pinned source file', () async {
      await Directory(p.join(temporary.path, 'manifest.json')).create();
      await expectLater(
        verifyInstalledStoreSource(temporary),
        throwsStateError,
      );
    });
    test('rejects relative source paths', () async {
      await expectLater(
        verifyInstalledStoreSource(Directory('relative')),
        throwsArgumentError,
      );
    });
    test('transport rejects path traversal before writing files', () async {
      final destination = Directory(p.join(temporary.path, 'decoded'));
      final payload = base64Encode(
        gzip.encode(utf8.encode(jsonEncode({'../outside': 'x'}))),
      );
      await expectLater(
        materializeInstalledStorePayload(destination, payload),
        throwsArgumentError,
      );
      expect(await destination.exists(), false);
    });
    test(
      'transport validates all five hashes before creating destination',
      () async {
        final destination = Directory(p.join(temporary.path, 'decoded'));
        final payload = base64Encode(
          gzip.encode(
            utf8.encode(
              jsonEncode({
                for (final path in installedStoreHashes.keys)
                  path: 'wrong source',
              }),
            ),
          ),
        );
        await expectLater(
          materializeInstalledStorePayload(destination, payload),
          throwsStateError,
        );
        expect(await destination.exists(), false);
      },
    );
    test('transport bounds decompressed input', () async {
      final destination = Directory(p.join(temporary.path, 'decoded'));
      final payload = base64Encode(
        gzip.encode(utf8.encode('x' * (512 * 1024 + 1))),
      );
      await expectLater(
        materializeInstalledStorePayload(destination, payload),
        throwsArgumentError,
      );
      expect(await destination.exists(), false);
    });
    test(
      'prepared pinned source survives device transport byte-for-byte',
      () async {
        final source = Directory(preparedSource!);
        final expected = await verifyInstalledStoreSource(source);
        final files = <String, String>{};
        for (final path in installedStoreHashes.keys) {
          final bytes = await File(p.join(source.path, path)).readAsBytes();
          final hasBom =
              bytes.length >= 3 &&
              bytes[0] == 0xef &&
              bytes[1] == 0xbb &&
              bytes[2] == 0xbf;
          files[path] = hasBom
              ? '\uFEFF${utf8.decode(bytes.sublist(3))}'
              : utf8.decode(bytes);
        }
        final payload = base64Encode(
          gzip.encode(utf8.encode(jsonEncode(files))),
        );
        final result = await materializeInstalledStorePayload(
          Directory(p.join(temporary.path, 'decoded')),
          payload,
        );
        expect(await verifyInstalledStoreSource(result), expected);
      },
      skip: preparedSource == null
          ? 'Optional pinned source input; CI prepares it before these tests.'
          : false,
    );
    test(
      'rejects traversal through a symlink',
      () async {
        final real = await Directory(p.join(temporary.path, 'real')).create();
        final alias = Link(p.join(temporary.path, 'alias'));
        await alias.create(real.path);
        await expectLater(
          rejectInstalledProbeLinks(p.join(alias.path, 'new-root')),
          throwsStateError,
        );
      },
      skip: Platform.isWindows
          ? 'Creating symlinks needs a separate Windows privilege.'
          : false,
    );
  });
}
