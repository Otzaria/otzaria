import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
    expect(
      bootstrap['reportPath'],
      'cache/otzaria-installed-probe-test/output/installed-plugin-report.json',
    );
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
}
