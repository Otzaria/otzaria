import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:otzaria/plugins/services/plugin_network_access_resolver.dart';

/// Test-only service data; the real SDK permission checks remain active.
List<Map<String, Object?>> installedProbeCatalog() => [
  for (var index = 1; index <= 36; index++)
    {
      'id': 'probe-$index',
      'pluginUid': 'org.otzaria.catalog-fixture.$index',
      'name': 'Fixture ${index.toString().padLeft(2, '0')}',
      'shortDescription': 'Controlled book study fixture',
      'description':
          'Local service fixture for the installed store probe. ' * 60,
      'version': '1.0.0',
      'status': index.isEven ? 'stable' : 'beta',
      'tags': ['לימוד'],
      'downloadUrl': '/api/plugins/probe-$index/download',
      'publishedAt':
          '2026-01-${(index % 28 + 1).toString().padLeft(2, '0')}T00:00:00Z',
      'fileUpdatedAt':
          '2026-02-${(index % 28 + 1).toString().padLeft(2, '0')}T00:00:00Z',
      'author': 'Resource probe fixture',
      'downloadCount': 0,
    },
];

class InstalledProbeCatalog extends HttpOverrides {
  HttpServer? _server;
  HttpOverrides? _previous;
  final _clients = <HttpClient>[];
  final requests = <Map<String, Object?>>[];
  var _active = false;

  Iterable<Map<String, Object?>> get unexpectedBlockedRequests =>
      requests.where(
        (request) =>
            request['result'] == 'blockedBeforeTransport' &&
            request['classification'] != 'expectedPolicyBootstrap',
      );

  bool _isPolicyBootstrap(String method, Uri uri) {
    if (!_active || method != 'GET') return false;
    final expected = [
      PluginNetworkAccessResolver.officialAllowlistUri.toString(),
      PluginNetworkAccessResolver.officialAllowlistContentsApiUri.toString(),
    ];
    final step = requests
        .where(
          (request) => request['classification'] == 'expectedPolicyBootstrap',
        )
        .length;
    return step < expected.length && uri.toString() == expected[step];
  }

  Future<void> start() async {
    if (_active) throw StateError('Catalog fixture is already active');
    _previous = HttpOverrides.current;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((request) async {
      final path = request.uri.path;
      final catalog = installedProbeCatalog();
      final Object? data;
      var status = HttpStatus.ok;
      if (request.method != 'GET') {
        data = {'error': 'fixture_method_not_allowed'};
        status = HttpStatus.methodNotAllowed;
      } else if (path == '/api/plugins') {
        data = catalog;
      } else if (path == '/api/plugins/search') {
        final query = request.uri.queryParameters['q']?.toLowerCase() ?? '';
        final requestedStatus = request.uri.queryParameters['status'];
        data = {
          'results': catalog
              .where(
                (entry) =>
                    '${entry['name']} ${entry['shortDescription']}'
                        .toLowerCase()
                        .contains(query) &&
                    (requestedStatus == null ||
                        entry['status'] == requestedStatus),
              )
              .toList(),
          'relaxed': false,
        };
      } else {
        // A missing curated home exercises the store's supported all-view path.
        data = {'error': 'fixture_no_curated_home'};
        status = HttpStatus.notFound;
      }
      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(data));
      await request.response.close();
    });
    _active = true;
    HttpOverrides.global = this;
  }

  Uri _route(String method, Uri original) {
    final allowed =
        _active &&
        method == 'GET' &&
        original.scheme == 'https' &&
        original.host == 'otzaria.org' &&
        original.port == 443 &&
        original.userInfo.isEmpty &&
        {
          '/api/plugins',
          '/api/plugins/search',
          '/api/plugins/store-home',
        }.contains(original.path) &&
        original.queryParameters.keys.every(
          {'appVersion', 'q', 'status', 'limit'}.contains,
        );
    requests.add({
      'utc': DateTime.now().toUtc().toIso8601String(),
      'method': method,
      'url': original.toString(),
      'result': allowed ? 'localFixture' : 'blockedBeforeTransport',
      'classification': allowed
          ? 'fixtureCatalog'
          : _isPolicyBootstrap(method, original)
          ? 'expectedPolicyBootstrap'
          : 'unexpectedRequest',
    });
    if (!allowed) {
      throw StateError(
        'Probe blocked non-fixture HTTP request: $method $original',
      );
    }
    return original.replace(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: _server!.port,
      fragment: '',
    );
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
    _clients.add(client);
    return _CatalogHttpClient(client, _route);
  }

  Future<void> stop() async {
    if (!_active) return;
    _active = false;
    HttpOverrides.global = _previous;
    for (final client in _clients) {
      client.close(force: true);
    }
    await _server?.close(force: true);
  }

  Map<String, Object?> toJson() => {
    'mode': 'fixture-backed-catalog',
    'transport': 'Dart HttpClient exact GET routes to local loopback HTTP',
    'externalServiceMutations': 0,
    'productionCatalogTraffic': 0,
    'catalogEntryCount': 36,
    'policyBootstrapContract':
        'At most one blocked GET pair: official raw then Contents API. Further attempts invalidate this cold-resolver trial.',
    'expectedPolicyBootstrapCount': requests
        .where(
          (request) => request['classification'] == 'expectedPolicyBootstrap',
        )
        .length,
    'unexpectedBlockedRequestCount': unexpectedBlockedRequests.length,
    'requests': requests,
    'scope':
        'Dart HTTP clients in this app isolate; not a claim about all OS network traffic',
  };
}

// Unknown client operations fail closed. Only the package:http IOClient path
// and safe configuration fields used by the app are supported by this probe.
class _CatalogHttpClient implements HttpClient {
  _CatalogHttpClient(this._client, this._route);
  final HttpClient _client;
  final Uri Function(String, Uri) _route;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _client.openUrl(method, _route(method, url));
  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  void close({bool force = false}) => _client.close(force: force);
  @override
  Duration get idleTimeout => _client.idleTimeout;
  @override
  set idleTimeout(Duration value) => _client.idleTimeout = value;
  @override
  Duration? get connectionTimeout => _client.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => _client.connectionTimeout = value;
  @override
  int? get maxConnectionsPerHost => _client.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? value) =>
      _client.maxConnectionsPerHost = value;
  @override
  bool get autoUncompress => _client.autoUncompress;
  @override
  set autoUncompress(bool value) => _client.autoUncompress = value;
  @override
  String? get userAgent => _client.userAgent;
  @override
  set userAgent(String? value) => _client.userAgent = value;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Catalog fixture does not permit ${invocation.memberName}',
  );
}
