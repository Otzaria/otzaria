import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_book_content_gate.dart';

const _long = Duration(seconds: 30);

void main() {
  setUp(PluginBookContentGate.resetForTesting);
  tearDown(PluginBookContentGate.resetForTesting);

  test('לא יותר מ-maxConcurrentLoads טעינות רצות יחד', () async {
    var running = 0;
    var peak = 0;
    final releases = <Completer<void>>[];
    Future<int> load(int i) => PluginBookContentGate.runLoad(() async {
      running++;
      if (running > peak) peak = running;
      final release = Completer<void>();
      releases.add(release);
      await release.future;
      running--;
      return i;
    }, timeout: _long);

    final results = Future.wait([for (var i = 0; i < 6; i++) load(i)]);
    await pumpEventQueue();
    expect(running, PluginBookContentGate.maxConcurrentLoads);
    expect(
      PluginBookContentGate.diagnostics,
      isNull,
      reason: 'טעינות בלי קריאת תוסף אינן נספרות לתוסף',
    );

    while (releases.any((r) => !r.isCompleted)) {
      releases.firstWhere((r) => !r.isCompleted).complete();
      await pumpEventQueue();
    }
    expect(await results, [0, 1, 2, 3, 4, 5]);
    expect(peak, PluginBookContentGate.maxConcurrentLoads);
  });

  test('טעינה שנכשלת משחררת את מקומה לממתין הבא', () async {
    final blocker = Completer<void>();
    final first = PluginBookContentGate.runLoad<void>(
      () => Future.error(StateError('read failed')),
      timeout: _long,
    );
    final second = PluginBookContentGate.runLoad(
      () => blocker.future,
      timeout: _long,
    );
    final third = PluginBookContentGate.runLoad(
      () async => 'done',
      timeout: _long,
    );

    await expectLater(first, throwsStateError);
    expect(await third, 'done');
    blocker.complete();
    await second;
  });

  test('ממתין שפג זמנו יוצא מהתור בלי לתפוס מקום', () async {
    final blockers = [Completer<void>(), Completer<void>()];
    final running = [
      for (final b in blockers)
        PluginBookContentGate.runLoad(() => b.future, timeout: _long),
    ];
    var timedOutRan = false;
    final timedOut = PluginBookContentGate.runLoad(() async {
      timedOutRan = true;
    }, timeout: const Duration(milliseconds: 10));
    await expectLater(
      timedOut,
      throwsA(
        predicate((e) => e.toString().contains('error.timeout')),
      ),
    );

    final next = PluginBookContentGate.runLoad(
      () async => 'next',
      timeout: _long,
    );
    blockers.first.complete();
    expect(await next, 'next');
    expect(timedOutRan, isFalse);
    blockers.last.complete();
    await Future.wait(running);

    // כל המקומות התפנו: שתי טעינות חדשות רצות מיד.
    final started = <int>[];
    final hold = Completer<void>();
    final fresh = [
      for (var i = 0; i < 2; i++)
        PluginBookContentGate.runLoad(() {
          started.add(i);
          return hold.future;
        }, timeout: Duration.zero),
    ];
    await pumpEventQueue();
    expect(started, [0, 1]);
    hold.complete();
    await Future.wait(fresh);
  });

  test('טעינה תקועה מפנה את מקומה בתום ה-timeout שלה', () async {
    final stuck = Completer<void>();
    addTearDown(() {
      if (!stuck.isCompleted) stuck.complete();
    });
    final stalled = [
      for (var i = 0; i < 2; i++)
        PluginBookContentGate.runLoad(
          () => stuck.future,
          timeout: const Duration(milliseconds: 20),
        ),
    ];
    final next = PluginBookContentGate.runLoad(
      () async => 'next',
      timeout: _long,
    );
    expect(await next, 'next');
    expect(stuck.isCompleted, isFalse);

    stuck.complete();
    await Future.wait(stalled);
    final fresh = [
      for (var i = 0; i < 2; i++)
        PluginBookContentGate.runLoad(() async => i, timeout: Duration.zero),
    ];
    expect(await Future.wait(fresh), [0, 1]);
  });

  test('מונה התוסף סופר פעילות ושיא ומתאפס גם בחריגה', () async {
    final hold = Completer<void>();
    final calls = [
      PluginBookContentGate.trackCall('scanner', () => hold.future),
      PluginBookContentGate.trackCall('scanner', () => hold.future),
      PluginBookContentGate.trackCall<void>(
        'scanner',
        () => Future.error(Exception('error.not_found')),
      ),
      PluginBookContentGate.trackCall('other', () async {}),
    ];
    final failed = expectLater(calls[2], throwsException);
    await pumpEventQueue();

    var plugins =
        PluginBookContentGate.diagnostics!['plugins'] as Map<String, Object>;
    expect(plugins['scanner'], {'active': 2, 'peak': 3, 'calls': 3});
    expect(plugins['other'], {'active': 0, 'peak': 1, 'calls': 1});

    hold.complete();
    await failed;
    await Future.wait([calls[0], calls[1], calls[3]]);
    plugins =
        PluginBookContentGate.diagnostics!['plugins'] as Map<String, Object>;
    expect(plugins['scanner'], {'active': 0, 'peak': 3, 'calls': 3});
  });
}
