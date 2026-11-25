import 'dart:async';

import 'package:flutter/services.dart';

/// Sends the same framework message as an engine memory-pressure notification.
///
/// The installed app's system-channel handler remains in place. The reply is
/// awaited so callers cannot inspect the reader before its observers run.
Future<void> notifyInstalledPluginMemoryPressure({
  Duration timeout = const Duration(seconds: 15),
}) {
  final acknowledged = Completer<void>();
  final channel = SystemChannels.system;
  ServicesBinding.instance.channelBuffers.push(
    channel.name,
    channel.codec.encodeMessage(const {'type': 'memoryPressure'}),
    (_) => acknowledged.complete(),
  );
  return acknowledged.future.timeout(
    timeout,
    onTimeout: () => throw TimeoutException(
      'The flutter/system memoryPressure notification was not acknowledged',
      timeout,
    ),
  );
}
