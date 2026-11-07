import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/support/installed_plugin_windows_lifetime.dart';

const _campaign = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _token =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _runId = '42-1794010000000000';
const _creation = '134384800000000000';

Future<Map<String, Object?>> _exchange({
  Map<String, Object?> changes = const {},
  String? remove,
  List<int>? raw,
  bool sendReply = true,
  bool closeReply = true,
  Duration timeout = const Duration(seconds: 3),
}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  final release = Completer<void>();
  Socket? accepted;
  final serving = () async {
    final client = accepted = await server.first;
    final request = await client.fold<List<int>>(
      <int>[],
      (all, bytes) => all..addAll(bytes),
    );
    expect(jsonDecode(utf8.decode(request)), {
      'version': 1,
      'kind': 'hello',
      'campaignId': _campaign,
      'token': _token,
      'pid': 42,
      'runId': _runId,
      'creationFileTime': _creation,
    });
    final reply = <String, Object?>{
      'version': 1,
      'kind': 'ready',
      'campaignId': _campaign,
      'token': _token,
      'pid': 42,
      'runId': _runId,
      'creationFileTime': _creation,
      'executable': r'C:\probe\otzaria.exe',
      'acknowledgedAtUtc': '2026-11-07T00:00:00.0000000Z',
      'bootstrapQuiescent': true,
      ...changes,
    };
    if (remove != null) reply.remove(remove);
    if (sendReply) {
      client.add(raw ?? utf8.encode(jsonEncode(reply)));
      await client.flush();
    }
    if (closeReply) {
      await client.close();
    } else {
      await release.future;
    }
    return null;
  }();
  final operation = acknowledgeInstalledWindowsLifetime(
    processId: 42,
    runId: _runId,
    creationFileTime: _creation,
    environment: {
      'INSTALLED_PROBE_WINDOWS_PORT': '$port',
      'INSTALLED_PROBE_WINDOWS_CAMPAIGN': _campaign,
      'INSTALLED_PROBE_WINDOWS_TOKEN': _token,
    },
    timeout: timeout,
  );
  try {
    final results = await Future.wait<Object?>([
      operation,
      serving,
    ], eagerError: true);
    return results.first! as Map<String, Object?>;
  } finally {
    release.complete();
    accepted?.destroy();
    await server.close();
    try {
      await serving.timeout(const Duration(seconds: 2));
    } catch (_) {
      // Future.wait already observes server failures; cleanup must also finish.
    }
  }
}

void main() {
  test('acknowledges one exact lifetime and excludes the secret from evidence',
      () async {
    final acknowledgement = await _exchange();
    expect(acknowledgement['pid'], 42);
    expect(acknowledgement['runId'], _runId);
    expect(acknowledgement['creationFileTime'], _creation);
    expect(acknowledgement['bootstrapQuiescent'], isTrue);
    expect(acknowledgement.containsKey('token'), isFalse);
  });

  for (final entry in <String, Object?>{
    'version': 2,
    'kind': 'other',
    'campaignId': 'cccccccccccccccccccccccccccccccc',
    'token': 'wrong token',
    'pid': 43,
    'runId': '43-1794010000000000',
    'creationFileTime': '134384800000000001',
    'bootstrapQuiescent': false,
    'executable': 42,
    'acknowledgedAtUtc': 'not a date',
  }.entries) {
    test('rejects changed ${entry.key}', () async {
      await expectLater(
        _exchange(changes: {entry.key: entry.value}),
        throwsA(isA<FormatException>()),
      );
    });
  }

  test('rejects an empty executable', () async {
    await expectLater(
      _exchange(changes: {'executable': ''}),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a non-string acknowledgement time', () async {
    await expectLater(
      _exchange(changes: {'acknowledgedAtUtc': 42}),
      throwsA(isA<FormatException>()),
    );
  });

  test('requires the native creation time in the acknowledgement', () async {
    await expectLater(
      _exchange(remove: 'creationFileTime'),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects partial JSON and non-object responses', () async {
    for (final response in ['{ partial JSON', '[]', 'null']) {
      await expectLater(
        _exchange(raw: utf8.encode(response)),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('bounds acknowledgement bytes before accepting JSON', () async {
    await expectLater(
      _exchange(raw: List<int>.filled(4097, 32)),
      throwsA(isA<FormatException>()),
    );
  });

  test('does not acknowledge valid JSON before the observer closes the channel',
      () async {
    await expectLater(
      _exchange(
        closeReply: false,
        timeout: const Duration(seconds: 1),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('a silent observer cannot leave bootstrap pending without a deadline',
      () async {
    await expectLater(
      _exchange(
        sendReply: false,
        closeReply: false,
        timeout: const Duration(seconds: 1),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('rejects absent and malformed observer configuration before connecting',
      () async {
    final valid = <String, String>{
      'INSTALLED_PROBE_WINDOWS_PORT': '1',
      'INSTALLED_PROBE_WINDOWS_CAMPAIGN': _campaign,
      'INSTALLED_PROBE_WINDOWS_TOKEN': _token,
    };
    for (final environment in <Map<String, String>>[
      {},
      {...valid, 'INSTALLED_PROBE_WINDOWS_PORT': '0'},
      {...valid, 'INSTALLED_PROBE_WINDOWS_PORT': '65536'},
      {...valid, 'INSTALLED_PROBE_WINDOWS_PORT': '1.5'},
      {...valid, 'INSTALLED_PROBE_WINDOWS_CAMPAIGN': 'wrong'},
      {...valid, 'INSTALLED_PROBE_WINDOWS_TOKEN': 'wrong'},
    ]) {
      await expectLater(
        acknowledgeInstalledWindowsLifetime(
          processId: 42,
          runId: _runId,
          creationFileTime: _creation,
          environment: environment,
        ),
        throwsA(isA<ArgumentError>()),
      );
    }
  });

  test('the native creation API reports a real value only on Windows', () {
    if (Platform.isWindows) {
      expect(
        BigInt.parse(installedWindowsCreationFileTime()) > BigInt.zero,
        isTrue,
      );
    } else {
      expect(installedWindowsCreationFileTime, throwsUnsupportedError);
    }
  });
}
