import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../../integration_test/support/installed_plugin_android_control.dart';

void main() {
  late Directory root;
  late Directory support;
  late File report;
  late HttpClient client;
  InstalledAndroidControl? control;
  StreamIterator<String>? events;
  const campaign = 'campaign-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final token = List.filled(64, 'b').join();
  late Uri base;

  Future<InstalledAndroidControl> start({
    String package = installedAndroidPackage,
    File? output,
    String expectedReportPath =
        'cache/otzaria-installed-probe-test/output/installed-plugin-report.json',
  }) async {
    final created = await InstalledAndroidControl.start(
      support: support,
      report: output ?? report,
      campaignId: campaign,
      token: token,
      runId: '123-456',
      processId: 123,
      package: package,
    );
    control = created;
    final bootstrap =
        jsonDecode(
              await File(
                p.join(
                  support.path,
                  installedAndroidDirectory,
                  campaign,
                  'bootstrap.json',
                ),
              ).readAsString(),
            )
            as Map;
    base = Uri.parse('http://127.0.0.1:${bootstrap['port']}');
    expect(bootstrap['reportPath'], expectedReportPath);
    return created;
  }

  Future<HttpClientResponse> getEvents({String? capability}) async {
    final request = await client.getUrl(base.resolve('/events'));
    request.headers.set('X-Installed-Probe', capability ?? token);
    return request.close();
  }

  Future<Map<String, Object?>> next() async {
    expect(await events!.moveNext().timeout(const Duration(seconds: 2)), true);
    return Map<String, Object?>.from(jsonDecode(events!.current) as Map);
  }

  Future<void> connect() async {
    final response = await getEvents();
    expect(response.statusCode, HttpStatus.ok);
    events = StreamIterator(
      response.transform(utf8.decoder).transform(const LineSplitter()),
    );
    expect(await next(), {
      ...control!.identity,
      'sequence': 0,
      'action': 'connected',
    });
    await control!.connected();
  }

  Future<int> reply(
    Map<String, Object?> command, {
    Map<String, Object?> overrides = const {},
    bool ok = true,
  }) async {
    final request = await client.postUrl(base.resolve('/reply'));
    request.headers.set('X-Installed-Probe', token);
    request.write(
      jsonEncode({
        ...command,
        'ok': ok,
        'result': {'nativeObserved': true},
        ...overrides,
      }),
    );
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('installed-android-control-');
    support = await Directory(p.join(root.path, 'files')).create();
    report = File(
      p.join(
        root.path,
        'cache',
        'otzaria-installed-probe-test',
        'output',
        'installed-plugin-report.json',
      ),
    );
    await report.parent.create(recursive: true);
    client = HttpClient();
    control = null;
    events = null;
  });

  tearDown(() async {
    client.close(force: true);
    await control?.close();
    await events?.cancel();
    await root.delete(recursive: true);
  });

  test(
    'refuses production package, external output and reused campaign',
    () async {
      await expectLater(
        start(package: 'org.otzaria.otzaria'),
        throwsArgumentError,
      );
      await expectLater(
        start(output: File(p.join(root.path, 'report.json'))),
        throwsArgumentError,
      );
      await start();
      await expectLater(start(), throwsStateError);
    },
  );

  test(
    'rejects unauthenticated and duplicate streams without releasing setup',
    () async {
      await start();
      final wrong = await getEvents(capability: 'wrong');
      expect(wrong.statusCode, HttpStatus.forbidden);
      await wrong.drain<void>();
      await expectLater(
        control!.connected(timeout: const Duration(milliseconds: 30)),
        throwsA(isA<TimeoutException>()),
      );
      await connect();
      final duplicate = await getEvents();
      expect(duplicate.statusCode, HttpStatus.conflict);
      await duplicate.drain<void>();
    },
  );

  test(
    'pushes commands once and rejects stale PID, sequence and document run replies',
    () async {
      await start();
      await connect();
      final pending = control!.request('home', {
        'documentToken': 'observed-document',
      });
      final command = await next();
      expect(command['sequence'], 1);
      expect(command['payload'], {'documentToken': 'observed-document'});
      for (final invalid in [
        {'pid': 124},
        {'runId': '123-stale'},
        {'sequence': 0},
        {'action': 'resume'},
      ]) {
        expect(await reply(command, overrides: invalid), HttpStatus.conflict);
      }
      expect(await reply(command), HttpStatus.noContent);
      expect(await pending, {'nativeObserved': true});
      final second = control!.request('quiet', {'durationMs': 1000});
      final current = await next();
      expect(current['sequence'], 2);
      expect(await reply(command), HttpStatus.conflict);
      expect(await reply(current), HttpStatus.noContent);
      await second;
    },
  );

  test(
    'a native failure fails the pending scenario rather than becoming an acknowledgement',
    () async {
      await start();
      await connect();
      final pending = control!.request('home', {});
      final failure = expectLater(pending, throwsStateError);
      expect(await reply(await next(), ok: false), HttpStatus.noContent);
      await failure;
    },
  );

  test(
    'a missing acknowledgement expires and a late one is rejected',
    () async {
      await start();
      await connect();
      final pending = control!.request(
        'home',
        {},
        timeout: const Duration(milliseconds: 70),
      );
      final failure = expectLater(pending, throwsA(isA<TimeoutException>()));
      final command = await next();
      await failure;
      expect(await reply(command), HttpStatus.conflict);
    },
  );

  test(
    'closing the control fails in-flight work and prevents another command',
    () async {
      await start();
      await connect();
      final pending = control!.request('home', {});
      final failure = expectLater(pending, throwsStateError);
      await next();
      await control!.close();
      await failure;
      await expectLater(control!.request('resume', {}), throwsStateError);
    },
  );

  test(
    'old connected state cannot acknowledge a command after host loss',
    () async {
      await start();
      await connect();
      await events!.cancel();
      client.close(force: true);
      await expectLater(
        control!.request(
          'home',
          {},
          timeout: const Duration(milliseconds: 100),
        ),
        throwsA(
          anyOf(
            isA<TimeoutException>(),
            isA<HttpException>(),
            isA<SocketException>(),
          ),
        ),
      );
    },
  );

  test(
    'completion binds exact report bytes to the actual framework verdict',
    () async {
      await start();
      await connect();
      final bytes = utf8.encode(
        '{"status":"failed","frameworkPassed":false}\n',
      );
      await report.writeAsBytes(bytes, flush: true);
      final finish = control!.finish(report, frameworkPassed: false);
      final command = await next();
      expect(command['action'], 'complete');
      expect(command['payload'], {
        'frameworkPassed': false,
        'reportBytes': bytes.length,
        'reportSha256': sha256.convert(bytes).toString(),
      });
      await reply(command);
      await finish;
    },
  );
  group('native private cache allocation', () {
    late PathProviderPlatform previousPaths;
    late _AndroidCachePaths nativePaths;

    setUp(() {
      previousPaths = PathProviderPlatform.instance;
      nativePaths = _AndroidCachePaths(p.join(root.path, 'cache'));
      PathProviderPlatform.instance = nativePaths;
    });

    tearDown(() {
      PathProviderPlatform.instance = previousPaths;
    });

    Future<File> outputIn(Directory allocated) async {
      final output = File(
        p.join(allocated.path, 'output', 'installed-plugin-report.json'),
      );
      await output.parent.create(recursive: true);
      return output;
    }

    test(
      'uses Android app cache when the VM temp root is code_cache and waits for authentication',
      () async {
        final codeCache = await Directory(
          p.join(root.path, 'code_cache'),
        ).create();
        final rejected = await codeCache.createTemp('otzaria-installed-probe-');
        await expectLater(
          start(output: await outputIn(rejected)),
          throwsArgumentError,
        );
        expect(
          await Directory(
            p.join(support.path, installedAndroidDirectory),
          ).exists(),
          false,
        );

        final allocated = await IOOverrides.runZoned(
          createInstalledAndroidProbeRoot,
          getSystemTempDirectory: () => codeCache,
        );
        expect(
          p.dirname(allocated.path),
          await Directory(p.join(root.path, 'cache')).resolveSymbolicLinks(),
        );
        expect(nativePaths.requests, 1);
        final output = await outputIn(allocated);
        await start(
          output: output,
          expectedReportPath:
              'cache/${p.basename(allocated.path)}/output/installed-plugin-report.json',
        );
        final bootstrap = await File(
          p.join(
            support.path,
            installedAndroidDirectory,
            campaign,
            'bootstrap.json',
          ),
        ).readAsString();
        expect(bootstrap, isNot(contains(token)));
        await expectLater(
          control!.connected(timeout: const Duration(milliseconds: 30)),
          throwsA(isA<TimeoutException>()),
        );
        await connect();
      },
    );

    test(
      'allocates distinct empty roots without reusing or modifying an existing cache run',
      () async {
        final existing = await Directory(
          p.join(root.path, 'cache', 'otzaria-installed-probe-existing'),
        ).create();
        final marker = File(p.join(existing.path, 'keep.txt'));
        await marker.writeAsString('retained evidence');
        final first = await createInstalledAndroidProbeRoot();
        final second = await createInstalledAndroidProbeRoot();
        final canonicalCache = await Directory(
          p.join(root.path, 'cache'),
        ).resolveSymbolicLinks();
        expect(
          {first.path, second.path, await existing.resolveSymbolicLinks()},
          hasLength(3),
        );
        for (final allocated in [first, second]) {
          expect(p.dirname(allocated.path), canonicalCache);
          expect(allocated.path, await allocated.resolveSymbolicLinks());
          expect(
            p.basename(allocated.path),
            matches(r'^otzaria-installed-probe-[A-Za-z0-9_-]+$'),
          );
          expect(await allocated.list().isEmpty, true);
        }
        expect(await marker.readAsString(), 'retained evidence');
        expect(nativePaths.requests, 2);
      },
    );

    test(
      'propagates missing platform cache and filesystem errors without falling back to VM temp',
      () async {
        final codeCache = await Directory(
          p.join(root.path, 'code_cache'),
        ).create();
        nativePaths.cachePath = null;
        await expectLater(
          IOOverrides.runZoned(
            createInstalledAndroidProbeRoot,
            getSystemTempDirectory: () => codeCache,
          ),
          throwsA(isA<MissingPlatformDirectoryException>()),
        );
        nativePaths.cachePath = p.join(root.path, 'missing-cache');
        await expectLater(
          IOOverrides.runZoned(
            createInstalledAndroidProbeRoot,
            getSystemTempDirectory: () => codeCache,
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(await codeCache.list().isEmpty, true);
        expect(await Directory(nativePaths.cachePath!).exists(), false);
        expect(nativePaths.requests, 2);
      },
    );

    test(
      'resolves the native cache alias before allocation and preserves the private bootstrap path',
      () async {
        final alias = Link(p.join(root.path, 'cache-alias'));
        await alias.create(nativePaths.cachePath!);
        nativePaths.cachePath = alias.path;
        final allocated = await createInstalledAndroidProbeRoot();
        expect(
          p.dirname(allocated.path),
          await Directory(p.join(root.path, 'cache')).resolveSymbolicLinks(),
        );
        expect(allocated.path, await allocated.resolveSymbolicLinks());
        await start(
          output: await outputIn(allocated),
          expectedReportPath:
              'cache/${p.basename(allocated.path)}/output/installed-plugin-report.json',
        );
      },
      skip: Platform.isWindows
          ? 'Creating symlinks needs a separate Windows privilege.'
          : false,
    );

    test(
      'rejects a report that escapes its fresh cache root through an output symlink',
      () async {
        final allocated = await createInstalledAndroidProbeRoot();
        final outside = await Directory(p.join(root.path, 'outside')).create();
        final alias = Link(p.join(allocated.path, 'output'));
        await alias.create(outside.path);
        await expectLater(
          start(
            output: File(p.join(alias.path, 'installed-plugin-report.json')),
          ),
          throwsArgumentError,
        );
        expect(await outside.list().isEmpty, true);
        expect(
          await Directory(
            p.join(support.path, installedAndroidDirectory),
          ).exists(),
          false,
        );
      },
      skip: Platform.isWindows
          ? 'Creating symlinks needs a separate Windows privilege.'
          : false,
    );

    test(
      'keeps sibling cache, other app and canonical traversal paths outside the accepted root',
      () async {
        for (final relative in [
          ['cache-other', 'otzaria-installed-probe-sibling'],
          ['other-app', 'cache', 'otzaria-installed-probe-foreign'],
          ['code_cache', 'otzaria-installed-probe-traversal'],
        ]) {
          final invalidRoot = Directory(p.joinAll([root.path, ...relative]));
          final invalidReport = await outputIn(invalidRoot);
          await expectLater(
            start(output: invalidReport),
            throwsArgumentError,
          );
        }
        final traversal = File(
          p.join(
            root.path,
            'cache',
            '..',
            'code_cache',
            'otzaria-installed-probe-traversal',
            'output',
            'installed-plugin-report.json',
          ),
        );
        await expectLater(start(output: traversal), throwsArgumentError);
        expect(
          await Directory(
            p.join(support.path, installedAndroidDirectory),
          ).exists(),
          false,
        );
      },
    );
  });
}

class _AndroidCachePaths extends PathProviderPlatform {
  _AndroidCachePaths(this.cachePath);

  String? cachePath;
  int requests = 0;

  @override
  Future<String?> getTemporaryPath() async {
    requests++;
    return cachePath;
  }
}
