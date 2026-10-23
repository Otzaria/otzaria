import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_handler.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_file_download_service.dart';
import 'package:otzaria/plugins/services/plugin_file_server.dart';
import 'package:otzaria/plugins/services/plugin_network_access_resolver.dart';
import 'package:otzaria/plugins/services/plugin_remote_file_cache.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:path/path.dart' as p;

class _MockHistoryBloc extends Mock implements HistoryBloc {}

class _MockTabsBloc extends Mock implements TabsBloc {}

class _MockNavigationBloc extends Mock implements NavigationBloc {}

class _MockCalendarCubit extends Mock implements CalendarCubit {}

class _MockWorkspaceBloc extends Mock implements WorkspaceBloc {}

class _MockSearchRepository extends Mock implements SearchRepository {}

class _MockPersonalNotesRepository extends Mock
    implements PersonalNotesRepository {}

class _MockBookOpenCoordinator extends Mock implements BookOpenCoordinator {}

/// הרשאות ו-KV בזיכרון, לפי תוסף — כמו ה-DB האמיתי.
class _Registry extends PluginRegistryRepository {
  final Set<String> granted;
  final Map<String, String> kv = {};

  /// השהיה בכל קריאה/כתיבה של KV, כמו DB אמיתי — חושפת קריאה-שינוי-כתיבה שאינם
  /// מסודרים.
  Future<void> Function()? kvDelay;

  _Registry(this.granted);

  @override
  Future<bool?> getPermission(String pluginId, String permission) async =>
      granted.contains(permission);

  @override
  Future<void> setKV(
    String pluginId,
    String namespace,
    String key,
    String valueJson,
  ) async {
    await kvDelay?.call();
    kv['$pluginId/$namespace/$key'] = valueJson;
  }

  @override
  Future<String?> getKV(String pluginId, String namespace, String key) async {
    await kvDelay?.call();
    return kv['$pluginId/$namespace/$key'];
  }
}

InstalledPlugin _plugin(String id, List<String> allowlist) => InstalledPlugin(
  pluginId: id,
  name: id,
  version: '1.0.0',
  installPath: '/',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: true,
  manifest: PluginManifest(
    schemaVersion: 1,
    id: id,
    name: id,
    version: '1.0.0',
    description: '',
    author: '',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '1.0.0',
    sdkVersion: '1.x',
    permissions: const [],
    networkEnabled: true,
    networkAllowlist: allowlist,
    toolTabTitle: id,
    toolTabOrder: 1,
    defaultPinned: true,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

/// גוף PDF מינימלי: ui.printFile בודק `%PDF-` בתחילת הקובץ.
final _pdfBody = utf8.encode('%PDF-1.4 test');

Matcher _failsWith(String code) => throwsA(
  isA<Exception>().having((e) => e.toString(), 'message', contains(code)),
);

void main() {
  const remoteHost = 'https://example.org/books';
  late Directory tempDir;
  late PluginFileServer fileServer;
  late PluginRemoteFileCache cache;
  late PluginNetworkAccessResolver originalResolver;
  late HttpClient httpClient;
  late List<({String path, String jobName})> printed;
  late bool userActivated;
  late Completer<bool>? printGate;
  late void Function()? onPrintEntered;
  var httpHits = 0;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('plugin_remote_file_');
    cache = PluginRemoteFileCache(root: Directory(p.join(tempDir.path, 'c')));
    fileServer = PluginFileServer(remoteFileCache: cache);
    httpClient = HttpClient();
    printed = [];
    userActivated = true;
    printGate = null;
    onPrintEntered = null;
    httpHits = 0;
    originalResolver = PluginNetworkAccessResolver.instance;
    PluginNetworkAccessResolver.instance = PluginNetworkAccessResolver(
      client: MockClient(
        (_) async => http.Response(
          remoteHost,
          200,
          headers: {'content-type': 'text/plain'},
        ),
      ),
    );
  });

  tearDown(() async {
    PluginNetworkAccessResolver.instance = originalResolver;
    httpClient.close(force: true);
    await fileServer.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  PluginFileDownloadService serving(
    List<int> body, {
    Map<String, String> headers = const {},
  }) => PluginFileDownloadService(
    client: MockClient((_) async {
      httpHits++;
      return http.Response.bytes(body, 200, headers: headers);
    }),
  );

  PluginBridgeAdapter buildAdapter({
    String pluginId = 'test.plugin',
    List<String> allowlist = const [remoteHost],
    Set<String> granted = const {'network.access'},
    PluginFileDownloadService? downloader,
    PluginRemoteFileCache? remoteCache,
    _Registry? registry,
    Future<String?> Function({List<String>? allowedExtensions, String? title})?
    pickFile,
  }) {
    return PluginBridgeAdapter(
      _plugin(pluginId, allowlist),
      dependencies: PluginBridgeDependencies(
        historyBloc: _MockHistoryBloc(),
        tabsBloc: _MockTabsBloc(),
        navigationBloc: _MockNavigationBloc(),
        calendarCubit: _MockCalendarCubit(),
        workspaceBloc: _MockWorkspaceBloc(),
        searchRepository: _MockSearchRepository(),
        personalNotesRepository: _MockPersonalNotesRepository(),
        bookOpenCoordinator: _MockBookOpenCoordinator(),
        themePayloadBuilder: () => <String, dynamic>{},
        showConfirmDialog: ({required title, required content}) async => true,
        showWarningDialog:
            ({required title, required content, required subtitle}) async =>
                true,
        pickFile: pickFile,
        hasUserActivation: (pluginId, instanceId) async => userActivated,
        printPluginFile: (file, {required jobName}) async {
          printed.add((path: file.path, jobName: jobName));
          onPrintEntered?.call();
          return await (printGate?.future ?? Future.value(true));
        },
      ),
      pluginRepository: registry ?? _Registry(granted),
      fileServer: fileServer,
      remoteFileCache: remoteCache ?? cache,
      fileDownloadService: downloader ?? serving(_pdfBody),
    );
  }

  Future<Map<String, dynamic>> fetchFile(
    PluginBridgeAdapter adapter, [
    Map<String, dynamic> args = const {},
  ]) async => Map<String, dynamic>.from(
    await adapter.execute('network', 'fetchFile', {
          'url': '$remoteHost/sample.pdf',
          ...args,
        })
        as Map,
  );

  group('network.fetchFile', () {
    test(
      'מחזיר token, url, שם, גודל ו-mime; הקובץ אינו בתיקיית המשתמש',
      () async {
        final registry = _Registry({'network.access'});
        final adapter = buildAdapter(registry: registry);

        final res = await fetchFile(adapter);

        expect(res['name'], 'sample.pdf');
        expect(res['size'], _pdfBody.length);
        expect(res['mime'], 'application/pdf');
        expect(res.containsKey('path'), isFalse);
        // grant לקריאה בלבד, באותו מנגנון של fs.pickUserFile.
        final grants = jsonDecode(
          registry.kv['test.plugin/_internal/user_file_grants']!,
        );
        expect(grants[res['token']]['access'], 'read');
        expect(cache.owns(grants[res['token']]['path'] as String), isTrue);
      },
    );

    test(
      'ה-URL מוגש ל-iframe של התוסף, ו-fs.resolveFileUrl עובד עליו',
      () async {
        final adapter = buildAdapter();
        final res = await fetchFile(adapter);

        final request = await httpClient.getUrl(
          Uri.parse(res['url'] as String),
        );
        final response = await request.close();
        expect(response.statusCode, 200);
        expect(response.headers.value('x-frame-options'), isNull);
        expect(
          response.headers.value('content-security-policy'),
          startsWith('frame-ancestors'),
        );
        expect(await response.expand((c) => c).toList(), _pdfBody);

        await fileServer.close(); // כמו reload
        final resolved =
            await adapter.execute('fs', 'resolveFileUrl', {
                  'token': res['token'],
                })
                as Map;
        expect(resolved['name'], 'sample.pdf');
        expect(resolved['size'], _pdfBody.length);
      },
    );

    test('כתובת שאינה ב-allowlist נחסמת בלי בקשה', () async {
      final adapter = buildAdapter();
      await expectLater(
        adapter.execute('network', 'fetchFile', {'url': 'https://evil.test/a'}),
        _failsWith('error.forbidden'),
      );
      expect(httpHits, 0);
    });

    test('בלי הרשאת network.access', () async {
      final adapter = buildAdapter(granted: const {});
      await expectLater(
        fetchFile(adapter),
        _failsWith('error.permission_denied'),
      );
      expect(httpHits, 0);
    });

    test('url חסר או לא תקין', () async {
      final adapter = buildAdapter();
      await expectLater(
        adapter.execute('network', 'fetchFile', {}),
        _failsWith('error.invalid_params'),
      );
    });

    test('maxBytes ו-timeoutMs לא חוקיים נדחים לפני הורדה', () async {
      final adapter = buildAdapter();
      for (final args in [
        {'maxBytes': 0},
        {'maxBytes': PluginRemoteFileCache.maxBytesLimit + 1},
        {'maxBytes': '10'},
        {'timeoutMs': -1},
        {'timeoutMs': PluginRemoteFileCache.maxTimeout.inMilliseconds + 1},
      ]) {
        await expectLater(
          fetchFile(adapter, args),
          _failsWith('error.invalid_params'),
          reason: '$args',
        );
      }
      expect(httpHits, 0);
    });

    test('קובץ מעל maxBytes: error.too_large ואין שאריות', () async {
      final adapter = buildAdapter(downloader: serving(List.filled(100, 1)));
      await expectLater(
        fetchFile(adapter, {'maxBytes': 10}),
        _failsWith('error.too_large'),
      );
      expect(
        cache.root.existsSync() ? cache.root.listSync(recursive: true) : [],
        everyElement(isA<Directory>()),
      );
    });

    test('כשל הורדה (HTTP 404) מחזיר שגיאה בלי token', () async {
      final registry = _Registry({'network.access'});
      final adapter = buildAdapter(
        registry: registry,
        downloader: PluginFileDownloadService(
          client: MockClient((_) async => http.Response('', 404)),
        ),
      );
      await expectLater(fetchFile(adapter), _failsWith('404'));
      expect(registry.kv['test.plugin/_internal/user_file_grants'], isNull);
    });

    test('network.localhost: שרת מקומי אמיתי, בלי allowlist גלובלי', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.headers.contentType = ContentType(
          'application',
          'pdf',
        );
        request.response.add(utf8.encode('%PDF-local'));
        await request.response.close();
      });
      final adapter = buildAdapter(
        allowlist: const ['127.0.0.1'],
        granted: const {'network.localhost'},
        downloader: PluginFileDownloadService(),
      );

      final res = await fetchFile(adapter, {
        'url': 'http://127.0.0.1:${server.port}/doc',
      });

      expect(res['name'], 'doc.pdf');
      expect(res['size'], 10);
    });

    test('fs.revokeFile מוחק גם את הקובץ מהמטמון', () async {
      final registry = _Registry({'network.access', 'fs.user_files.read'});
      final adapter = buildAdapter(registry: registry);
      final res = await fetchFile(adapter);
      final path =
          jsonDecode(
                registry.kv['test.plugin/_internal/user_file_grants']!,
              )[res['token']]['path']
              as String;
      expect(File(path).existsSync(), isTrue);

      await adapter.execute('fs', 'revokeFile', {'token': res['token']});

      expect(File(path).existsSync(), isFalse);
      await expectLater(
        adapter.execute('fs', 'resolveFileUrl', {'token': res['token']}),
        _failsWith('error.not_found'),
      );
    });

    test('הורדה חדשה מנקה מה-KV grants של קבצים שפונו מהמכסה', () async {
      final registry = _Registry({'network.access'});
      final small = PluginRemoteFileCache(
        root: Directory(p.join(tempDir.path, 'small')),
        quotaBytes: _pdfBody.length,
      );
      final adapter = buildAdapter(registry: registry, remoteCache: small);

      final first = await fetchFile(adapter);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final second = await fetchFile(adapter);

      final grants =
          jsonDecode(registry.kv['test.plugin/_internal/user_file_grants']!)
              as Map;
      expect(grants.containsKey(first['token']), isFalse);
      expect(grants.containsKey(second['token']), isTrue);
    });
  });

  group('network.fetchFile — אבטחה ועמידות', () {
    // שרת מותר שמפנה ל-127.0.0.1. ללא network.localhost היעד השני חסום.
    PluginFileDownloadService redirectingToLoopback(void Function() onHit) =>
        PluginFileDownloadService(
          client: MockClient((request) async {
            if (request.url.host == '127.0.0.1') {
              onHit();
              return http.Response.bytes(_pdfBody, 200);
            }
            return http.Response(
              '',
              302,
              headers: {'location': 'http://127.0.0.1:9/secret.pdf'},
            );
          }),
        );

    test('redirect ל-loopback נחסם בלי network.localhost', () async {
      var hits = 0;
      final adapter = buildAdapter(
        allowlist: const [remoteHost, '127.0.0.1'],
        downloader: redirectingToLoopback(() => hits++),
      );

      await expectLater(fetchFile(adapter), _failsWith('error.forbidden'));
      expect(hits, 0);
    });

    test('network.download: אותה חסימה של redirect ל-loopback', () async {
      var hits = 0;
      final adapter = buildAdapter(
        allowlist: const [remoteHost, '127.0.0.1'],
        downloader: redirectingToLoopback(() => hits++),
      );

      await expectLater(
        adapter.execute('network', 'download', {
          'url': '$remoteHost/sample.pdf',
        }),
        _failsWith('error.forbidden'),
      );
      expect(hits, 0);
    });

    test('redirect ל-loopback עובר כשיש network.localhost', () async {
      var hits = 0;
      final adapter = buildAdapter(
        allowlist: const [remoteHost, '127.0.0.1'],
        granted: const {'network.access', 'network.localhost'},
        downloader: redirectingToLoopback(() => hits++),
      );

      final res = await fetchFile(adapter);

      expect(hits, 1);
      expect(res['name'], 'sample.pdf');
    });

    test('fetchFile מקבילים: כל ה-grants נשמרים ועובדים', () async {
      final registry = _Registry({'network.access'})
        ..kvDelay = () => Future<void>.delayed(const Duration(milliseconds: 5));
      final adapter = buildAdapter(registry: registry);

      final results = await Future.wait([
        fetchFile(adapter),
        fetchFile(adapter),
        fetchFile(adapter),
      ]);

      final grants =
          jsonDecode(registry.kv['test.plugin/_internal/user_file_grants']!)
              as Map;
      expect(grants, hasLength(3));
      for (final res in results) {
        expect(grants, contains(res['token']));
        final resolved =
            await adapter.execute('fs', 'resolveFileUrl', {
                  'token': res['token'],
                })
                as Map;
        expect(resolved['name'], 'sample.pdf');
      }
    });

    test('כשל כתיבה מחזיר error.internal בלי נתיב דיסק', () async {
      final blocker = File(p.join(tempDir.path, 'blocker'))
        ..writeAsStringSync('x');
      final adapter = buildAdapter(
        remoteCache: PluginRemoteFileCache(root: Directory(blocker.path)),
      );

      Object? error;
      try {
        await fetchFile(adapter);
      } catch (e) {
        error = e;
      }

      expect(error.toString(), contains('error.internal'));
      expect(error.toString(), isNot(contains(tempDir.path)));
      expect(error.toString(), isNot(contains('blocker')));
    });

    test('הרשאות: fetchFile בלי הרשאת fs; השאר דורשים fs.user_files.read', () {
      expect(
        PluginBridgeHandler.methodPermissions['network.fetchFile'],
        PluginBridgeHandler.noManifestPermission,
      );
      for (final method in [
        'fs.resolveFileUrl',
        'fs.readTextFile',
        'fs.revokeFile',
      ]) {
        expect(
          PluginBridgeHandler.methodPermissions[method],
          'fs.user_files.read',
          reason: method,
        );
      }
    });
  });

  test('שלילת קריאת קבצים אישיים חוסמת printFile דרך הגשר', () async {
    final registry = _Registry({'fs.user_files.read'});
    final pdf = File(p.join(tempDir.path, 'private.pdf'))
      ..writeAsBytesSync(_pdfBody);
    final adapter = buildAdapter(
      registry: registry,
      pickFile: ({allowedExtensions, title}) async => pdf.path,
    );
    final picked = await adapter.execute('fs', 'pickUserFile', {}) as Map;
    registry.granted.remove('fs.user_files.read');
    await fileServer.revokeAllForPlugin('test.plugin');
    final handler = PluginBridgeHandler(
      _plugin('test.plugin', const []),
      adapter: adapter,
      registry: registry,
    );

    final result =
        await handler.handleRpcForTesting([
              {
                'method': 'ui.printFile',
                'payload': {'token': picked['token']},
              },
            ])
            as Map;

    expect(result['success'], isFalse);
    expect((result['error'] as Map)['code'], 'error.permission_denied');
    expect(printed, isEmpty);
  });

  test('מטמון של תוסף אחר אינו פוטר קובץ אישי מהרשאת קריאה', () async {
    final other = await cache.fetch(
      'other.plugin',
      Uri.parse('$remoteHost/other.pdf'),
      downloader: serving(_pdfBody),
      isAllowed: (_) async => true,
    );
    final registry = _Registry({'fs.user_files.read'});
    final adapter = buildAdapter(
      registry: registry,
      pickFile: ({allowedExtensions, title}) async => other.path,
    );
    final picked = await adapter.execute('fs', 'pickUserFile', {}) as Map;
    registry.granted.remove('fs.user_files.read');
    await fileServer.revokeAllForPlugin('test.plugin');
    expect(File(other.path).existsSync(), isTrue);
    final handler = PluginBridgeHandler(
      _plugin('test.plugin', const []),
      adapter: adapter,
      registry: registry,
    );

    final result =
        await handler.handleRpcForTesting([
              {
                'method': 'ui.printFile',
                'payload': {'token': picked['token']},
              },
            ])
            as Map;

    expect(result['success'], isFalse);
    expect((result['error'] as Map)['code'], 'error.permission_denied');
    expect(printed, isEmpty);
    registry.granted.add('fs.user_files.read');
    await adapter.execute('fs', 'revokeFile', {'token': picked['token']});
    expect(File(other.path).existsSync(), isTrue);
  });

  test('printFile של מטמון מרוחק עובד דרך הגשר בהרשאת רשת בלבד', () async {
    final registry = _Registry({'network.access'});
    final adapter = buildAdapter(registry: registry);
    final fetched = await fetchFile(adapter);
    final handler = PluginBridgeHandler(
      _plugin('test.plugin', const [remoteHost]),
      adapter: adapter,
      registry: registry,
    );

    final result =
        await handler.handleRpcForTesting([
              {
                'method': 'ui.printFile',
                'payload': {'token': fetched['token']},
              },
            ])
            as Map;

    expect(result['success'], isTrue);
    expect(printed, hasLength(1));
  });

  test('גם grants של הורדות ריקות מוגבלים ומתפנים', () async {
    final registry = _Registry({'network.access'});
    final adapter = buildAdapter(registry: registry, downloader: serving([]));
    for (var i = 0; i < 130; i++) {
      await fetchFile(adapter, {'url': '$remoteHost/$i.pdf'});
    }
    final grants =
        jsonDecode(
              registry.kv['test.plugin/_internal/user_file_grants']!,
            )
            as Map;
    expect(grants.length, lessThanOrEqualTo(128));
    expect(
      Directory(p.join(cache.root.path, 'test.plugin')).listSync().length,
      lessThanOrEqualTo(128),
    );
  });

  for (final phase in ['headers', 'body', 'grant']) {
    test('revoke בזמן $phase אינו משאיר קובץ או grant חדש', () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final registry = _Registry({'network.access'});
      final downloader = PluginFileDownloadService(
        client: MockClient.streaming((_, _) async {
          if (phase == 'headers') {
            started.complete();
            await release.future;
          }
          Stream<List<int>> body() async* {
            if (phase == 'body') {
              started.complete();
              await release.future;
            }
            yield _pdfBody;
          }

          return http.StreamedResponse(body(), 200);
        }),
      );
      if (phase == 'grant') {
        registry.kvDelay = () async {
          if (!started.isCompleted) {
            started.complete();
            await release.future;
          }
        };
      }
      final adapter = buildAdapter(registry: registry, downloader: downloader);
      final running = fetchFile(adapter);
      final failed = expectLater(running, _failsWith('error.unavailable'));
      await started.future;
      await fileServer.revokeAllForPlugin('test.plugin');
      release.complete();
      await failed;
      expect(
        Directory(p.join(cache.root.path, 'test.plugin')).existsSync(),
        isFalse,
      );
      expect(
        jsonDecode(
          registry.kv['test.plugin/_internal/user_file_grants'] ?? '{}',
        ),
        isEmpty,
      );
    });
  }

  group('ui.printFile', () {
    test('מדפיס PDF שהורד; שם העבודה ברירת מחדל הוא שם הקובץ', () async {
      final adapter = buildAdapter();
      final res = await fetchFile(adapter);

      expect(
        await adapter.execute('ui', 'printFile', {'token': res['token']}),
        {
          'printed': true,
        },
      );
      expect(printed.single.jobName, 'sample.pdf');
      expect(cache.owns(printed.single.path), isTrue);

      await adapter.execute('ui', 'printFile', {
        'token': res['token'],
        'jobName': ' הגהה ',
      });
      expect(printed.last.jobName, 'הגהה');
    });

    test('עובד גם על קובץ שהמשתמש בחר ב-fs.pickUserFile', () async {
      final pdf = File(p.join(tempDir.path, 'mine.pdf'))
        ..writeAsBytesSync(_pdfBody);
      final adapter = buildAdapter(
        granted: const {'fs.user_files.read'},
        pickFile: ({allowedExtensions, title}) async => pdf.path,
      );
      final picked = await adapter.execute('fs', 'pickUserFile', {}) as Map;

      await adapter.execute('ui', 'printFile', {'token': picked['token']});

      expect(p.basename(printed.single.path), 'mine.pdf');
    });

    test('ביטול בדיאלוג מוחזר כ-printed:false', () async {
      final adapter = buildAdapter();
      final res = await fetchFile(adapter);
      printGate = Completer<bool>()..complete(false);

      expect(
        await adapter.execute('ui', 'printFile', {'token': res['token']}),
        {
          'printed': false,
        },
      );
    });

    test('קובץ שאינו PDF: error.unsupported', () async {
      final adapter = buildAdapter(
        downloader: serving(utf8.encode('hello')),
      );
      final res = await fetchFile(adapter, {'url': '$remoteHost/notes.txt'});

      await expectLater(
        adapter.execute('ui', 'printFile', {'token': res['token']}),
        _failsWith('error.unsupported'),
      );
      expect(printed, isEmpty);
    });

    test('token חסר: invalid_params; לא מוכר: not_found', () async {
      final adapter = buildAdapter();
      await expectLater(
        adapter.execute('ui', 'printFile', {}),
        _failsWith('error.invalid_params'),
      );
      await expectLater(
        adapter.execute('ui', 'printFile', {'token': 'nope'}),
        _failsWith('error.not_found'),
      );
    });

    test('token של תוסף אחר: not_found, בלי הדפסה', () async {
      final registry = _Registry({'network.access'});
      final owner = buildAdapter(registry: registry);
      final other = buildAdapter(pluginId: 'other.plugin', registry: registry);
      final res = await fetchFile(owner);

      await expectLater(
        other.execute('ui', 'printFile', {'token': res['token']}),
        _failsWith('error.not_found'),
      );
      expect(printed, isEmpty);
    });

    test('בלי מחוות משתמש: error.forbidden, בלי הדפסה', () async {
      final adapter = buildAdapter();
      final res = await fetchFile(adapter);
      userActivated = false;

      await expectLater(
        adapter.execute('ui', 'printFile', {'token': res['token']}),
        _failsWith('error.forbidden'),
      );
      expect(printed, isEmpty);
    });

    test('סיומת .pdf על תוכן שאינו PDF: error.unsupported', () async {
      final adapter = buildAdapter(
        downloader: serving(utf8.encode('<html>404</html>')),
      );
      final res = await fetchFile(adapter, {'url': '$remoteHost/doc.pdf'});

      await expectLater(
        adapter.execute('ui', 'printFile', {'token': res['token']}),
        _failsWith('error.unsupported'),
      );
      expect(printed, isEmpty);
    });

    test('%PDF- מתקבל בתוך 1024 הבייטים הראשונים ולא אחריהם', () async {
      final nearStart = [...List.filled(500, 0x20), ..._pdfBody];
      final tooLate = [...List.filled(1100, 0x20), ..._pdfBody];

      final ok = buildAdapter(downloader: serving(nearStart));
      final okRes = await fetchFile(ok);
      await ok.execute('ui', 'printFile', {'token': okRes['token']});
      expect(printed, hasLength(1));

      final lateAdapter = buildAdapter(downloader: serving(tooLate));
      final lateRes = await fetchFile(lateAdapter);
      await expectLater(
        lateAdapter.execute('ui', 'printFile', {'token': lateRes['token']}),
        _failsWith('error.unsupported'),
      );
      expect(printed, hasLength(1));
    });

    test('jobName: חייב להיות מחרוזת, מנוקה מתווי בקרה ונחתך', () async {
      final adapter = buildAdapter();
      final res = await fetchFile(adapter);

      await expectLater(
        adapter.execute('ui', 'printFile', {
          'token': res['token'],
          'jobName': 7,
        }),
        _failsWith('error.invalid_params'),
      );
      expect(printed, isEmpty);

      await adapter.execute('ui', 'printFile', {
        'token': res['token'],
        'jobName': String.fromCharCodes([0x20, 0x61, 0, 0x62, 10, 0x7f, 0x63]),
      });
      expect(printed.last.jobName, 'abc');

      await adapter.execute('ui', 'printFile', {
        'token': res['token'],
        'jobName': String.fromCharCodes(List.filled(200, 0x1F600)),
      });
      expect(printed.last.jobName.runes.length, 120);

      // רק תווי בקרה: חוזרים לשם הקובץ.
      await adapter.execute('ui', 'printFile', {
        'token': res['token'],
        'jobName': String.fromCharCodes([1, 2, 3]),
      });
      expect(printed.last.jobName, 'sample.pdf');
    });

    test('דיאלוג אחד בכל רגע', () async {
      final adapter = buildAdapter();
      final res = await fetchFile(adapter);
      final gate = printGate = Completer<bool>();
      final entered = Completer<void>();
      final reentered = Completer<void>();
      onPrintEntered = () =>
          (entered.isCompleted ? reentered : entered).complete();

      final first = adapter.execute('ui', 'printFile', {'token': res['token']});
      try {
        // לפני הדיאלוג יש פעולות קובץ אסינכרוניות; ממתינים לכניסה בפועל.
        await Future.any([entered.future, first]);
        expect(entered.isCompleted, isTrue);
        final second = adapter.execute('ui', 'printFile', {
          'token': res['token'],
        });
        // כניסה שגויה של השנייה הייתה ממתינה ל-gate עד timeout.
        await Future.any([
          second.then<void>((_) {}, onError: (Object _) {}),
          reentered.future,
        ]);
        if (reentered.isCompleted) gate.complete(true);
        await expectLater(second, _failsWith('error.forbidden'));
      } finally {
        if (!gate.isCompleted) gate.complete(true);
      }
      expect(await first, {'printed': true});
      expect(printed, hasLength(1));
    });
  });
}
