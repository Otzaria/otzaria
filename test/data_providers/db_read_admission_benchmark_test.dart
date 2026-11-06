import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';

// Factory at top level avoids capturing the test's unsendable Flutter state.
Future<int> Function() _heldRead(SendPort ready, int value) => () async {
  final release = ReceivePort();
  ready.send([value, release.sendPort]);
  try {
    await release.first;
    return value;
  } finally {
    release.close();
  }
};

// These APIs also exist at the baseline. Each live count is confirmed by a
// handshake from a real isolate; this does not simulate blocked SQLite/FFI IO.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('held fallback reads stay bounded across timeout periods', () async {
    const submitted = 48;
    const tick = Duration(milliseconds: 50);
    DbReadWorker.stallTimeout = tick;
    final ready = ReceivePort();
    final releases = <int, SendPort>{};
    var released = false;
    final samples = <Map<String, Object>>[];
    var started = 0;
    var live = 0;
    var peakLive = 0;
    var rejected = 0;
    var rejectedBeforeStart = 0;
    final rejectionTypes = <String, int>{};
    final subscription = ready.listen((message) {
      final values = message as List;
      final id = values[0] as int;
      final release = values[1] as SendPort;
      releases[id] = release;
      started++;
      live++;
      if (live > peakLive) peakLive = live;
      if (released) release.send(null);
    });
    bool completed(int id) {
      if (releases.remove(id) == null) return false;
      live--;
      return true;
    }

    final watch = Stopwatch()..start();
    final reads = [
      for (var i = 0; i < submitted; i++)
        DbReadWorker.runFallbackOnFreshIsolate(
          _heldRead(ready.sendPort, i),
        ).then<Object?>(
          (value) {
            completed(i);
            return value;
          },
          onError: (Object error) {
            if (!completed(i)) rejectedBeforeStart++;
            rejected++;
            rejectionTypes.update(
              error.runtimeType.toString(),
              (count) => count + 1,
              ifAbsent: () => 1,
            );
            return error.toString();
          },
        ),
    ];
    try {
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(tick);
        samples.add({
          'elapsedMs': watch.elapsedMilliseconds,
          'started': started,
          'live': live,
          'queuedFutures': submitted - started - rejectedBeforeStart,
          'rejected': rejected,
          'rssBytes': ProcessInfo.currentRss,
        });
      }
    } finally {
      released = true;
      for (final release in releases.values) {
        release.send(null);
      }
      await Future.wait(reads);
      await subscription.cancel();
      ready.close();
      DbReadWorker.stallTimeout = const Duration(seconds: 10);
    }
    expect(started, greaterThan(0), reason: 'Must start real isolates');
    expect(rejectionTypes.keys, everyElement('DbReadWorkerBusy'));
    expect(live, 0);
    expect(await DbReadWorker.runFallbackOnFreshIsolate(() => 123), 123);
    // ignore: avoid_print
    print(
      jsonEncode({
        'scenario': 'held_fallback_admission',
        'measurement': 'isolate_handshake',
        'liveDefinition': 'handshaken isolates awaiting completion',
        'queuedDefinition': 'not started or spawn not yet handshaken',
        'label': const String.fromEnvironment(
          'DB_READ_BENCHMARK_LABEL',
          defaultValue: 'local',
        ),
        'os': Platform.operatingSystem,
        'timeoutMs': tick.inMilliseconds,
        'submitted': submitted,
        'peakLive': peakLive,
        'peakRssBytes': ProcessInfo.maxRss,
        'rejected': rejected,
        'rejectionTypes': rejectionTypes,
        'recovered': live == 0,
        'samples': samples,
      }),
    );
    DbReadWorker.disposeForTesting();
  }, skip: !const bool.fromEnvironment('RUN_DB_READ_ADMISSION_BENCHMARK'));
}
