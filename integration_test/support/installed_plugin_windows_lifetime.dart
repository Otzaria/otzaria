import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

String installedWindowsCreationFileTime() {
  if (!Platform.isWindows) {
    throw UnsupportedError('Native process creation time requires Windows.');
  }
  final times = calloc<FILETIME>(4);
  try {
    final result = GetProcessTimes(
      GetCurrentProcess(),
      times,
      times + 1,
      times + 2,
      times + 3,
    );
    if (!result.value) {
      throw StateError('GetProcessTimes failed: ${result.error}');
    }
    return ((times.ref.dwHighDateTime << 32) | times.ref.dwLowDateTime)
        .toString();
  } finally {
    calloc.free(times);
  }
}

Future<Map<String, Object?>> acknowledgeInstalledWindowsLifetime({
  required int processId,
  required String runId,
  required String creationFileTime,
  required Map<String, String> environment,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final port = int.tryParse(environment['INSTALLED_PROBE_WINDOWS_PORT'] ?? '');
  final campaign = environment['INSTALLED_PROBE_WINDOWS_CAMPAIGN'] ?? '';
  final token = environment['INSTALLED_PROBE_WINDOWS_TOKEN'] ?? '';
  if (port == null ||
      port < 1 ||
      port > 65535 ||
      !RegExp(r'^[0-9a-f]{32}$').hasMatch(campaign) ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
    throw ArgumentError('The Windows lifetime observer must arm this launch.');
  }
  Socket? socket;
  var finished = false;
  final operation = () async {
    final connected = socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      port,
      timeout: timeout,
    );
    if (finished) {
      connected.destroy();
      throw StateError('The Windows bootstrap deadline has expired.');
    }
    final incoming = connected.fold<List<int>>(<int>[], (response, bytes) {
      if (response.length + bytes.length > 4096) {
        throw const FormatException(
          'The lifetime acknowledgement exceeds 4096 bytes.',
        );
      }
      return response..addAll(bytes);
    });
    final outgoing = () async {
      connected.add(
        utf8.encode(
          jsonEncode({
            'version': 1,
            'kind': 'hello',
            'campaignId': campaign,
            'token': token,
            'pid': processId,
            'runId': runId,
            'creationFileTime': creationFileTime,
          }),
        ),
      );
      await connected.flush();
      // Half-close the request so a second or truncated JSON message is rejected.
      await connected.close();
      return null;
    }();
    final exchanged = await Future.wait<Object?>([
      incoming,
      outgoing,
    ], eagerError: true);
    final response = exchanged[0]! as List<int>;
    final value = jsonDecode(utf8.decode(response));
    if (value is! Map<String, dynamic> ||
        value['version'] != 1 ||
        value['kind'] != 'ready' ||
        value['campaignId'] != campaign ||
        value['token'] != token ||
        value['pid'] != processId ||
        value['runId'] != runId ||
        value['creationFileTime'] != creationFileTime ||
        value['bootstrapQuiescent'] != true ||
        value['executable'] is! String ||
        (value['executable'] as String).isEmpty ||
        value['acknowledgedAtUtc'] is! String ||
        DateTime.tryParse(value['acknowledgedAtUtc'] as String) == null) {
      throw const FormatException(
        'The Windows observer did not acknowledge this exact lifetime.',
      );
    }
    return <String, Object?>{...value}..remove('token');
  }();
  try {
    return await operation.timeout(timeout);
  } finally {
    finished = true;
    socket?.destroy();
  }
}
