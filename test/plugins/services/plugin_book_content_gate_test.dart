import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_book_content_gate.dart';

const _long = Duration(seconds: 30);
final _owner = Object();

Future<T> _run<T>(
  Future<T> Function() load, {
  String plugin = 'scanner',
  Object? owner,
  Duration timeout = _long,
}) => PluginBookContentGate.runLoad(
  load,
  pluginId: plugin,
  owner: owner ?? _owner,
  timeout: timeout,
);

Matcher get _timeout => throwsA(
  isA<PluginBookContentQueueTimeout>().having(
    (e) => e.toString(),
    'message',
    startsWith('error.timeout'),
  ),
);

void main() {
  setUp(PluginBookContentGate.resetForTesting);
  tearDown(PluginBookContentGate.resetForTesting);

  test('תוסף אחד מריץ לכל היותר maxConcurrentLoads טעינות יחד', () async {
    var running = 0;
    var peak = 0;
    final releases = <Completer<void>>[];
    Future<int> load(int i) => _run(() async {
      running++;
      if (running > peak) peak = running;
      final release = Completer<void>();
      releases.add(release);
      await release.future;
      running--;
      return i;
    });

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
    final first = _run<void>(() => Future.error(StateError('read failed')));
    final second = _run(() => blocker.future);
    final third = _run(() async => 'done');

    await expectLater(first, throwsStateError);
    expect(await third, 'done');
    blocker.complete();
    await second;
  });

  test('ממתין שפג זמנו יוצא מהתור בלי לטעון ובלי לתפוס מקום', () async {
    final blockers = [Completer<void>(), Completer<void>()];
    final running = [for (final b in blockers) _run(() => b.future)];
    var timedOutRan = false;
    await expectLater(
      _run(() async {
        timedOutRan = true;
      }, timeout: const Duration(milliseconds: 10)),
      _timeout,
    );

    final next = _run(() async => 'next');
    blockers.first.complete();
    expect(await next, 'next');
    expect(timedOutRan, isFalse);
    blockers.last.complete();
    await Future.wait(running);
    expect(PluginBookContentGate.runningLoadsForTesting, 0);
  });

  test('ממתין שקיבל מקום אחרי תום התקציב לא טוען ומשחרר אותו', () async {
    final blockers = [Completer<void>(), Completer<void>()];
    final running = [for (final b in blockers) _run(() => b.future)];
    var lateRan = false;
    final late = _run(() async {
      lateRan = true;
    }, timeout: const Duration(milliseconds: 20));
    final failed = expectLater(late, _timeout);
    await pumpEventQueue();

    // ה-isolate עסוק עד אחרי ה-deadline, והמקום מתפנה לפני שהטיימר של הממתין רץ.
    final busy = Stopwatch()..start();
    while (busy.elapsed < const Duration(milliseconds: 60)) {}
    blockers.first.complete();
    await failed;
    expect(lateRan, isFalse);

    expect(await _run(() async => 'free'), 'free');
    blockers.last.complete();
    await Future.wait(running);
    expect(PluginBookContentGate.runningLoadsForTesting, 0);
  });

  test('תקיעה נמדדת מתחילת הטעינה, ומפל לא עוקף את התקרה', () async {
    PluginBookContentGate.stallAfter = const Duration(milliseconds: 20);
    var running = 0;
    var peak = 0;
    var overLimit = false;
    Future<void> load() => PluginBookContentGate.trackCall(
      'scanner',
      () => _run(() async {
        running++;
        if (running > peak) peak = running;
        final stalled =
            PluginBookContentGate.diagnostics!['stalledLoads']! as int;
        if (running > PluginBookContentGate.maxConcurrentLoads + stalled) {
          overLimit = true;
        }
        await Future<void>.delayed(const Duration(milliseconds: 60));
        running--;
      }, timeout: const Duration(milliseconds: 150)),
    );

    final results = await Future.wait([
      for (var i = 0; i < 40; i++)
        load().then((_) => true, onError: (Object _) => false),
    ]);
    expect(overLimit, isFalse);
    expect(peak, lessThanOrEqualTo(PluginBookContentGate.maxRunningLoads));
    expect(results, contains(true));
    expect(results, contains(false), reason: 'השאר פגו בתור');
    expect(PluginBookContentGate.runningLoadsForTesting, 0);
    expect(PluginBookContentGate.diagnostics!['stalledLoads'], 0);
  });

  test('תוסף עם טעינה תקועה לא טוען עוד, ותקרה תקועה נרשמת פעם אחת', () async {
    PluginBookContentGate.stallAfter = const Duration(milliseconds: 20);
    final reports = <List<String>>[];
    PluginBookContentGate.reportStalledCeiling = (ids) =>
        reports.add(ids.toList());
    final stuck = Completer<void>();
    addTearDown(() {
      if (!stuck.isCompleted) stuck.complete();
    });
    final stuckA = [for (var i = 0; i < 2; i++) _run(() => stuck.future)];
    await Future<void>.delayed(const Duration(milliseconds: 40));

    var aRan = false;
    await expectLater(
      _run(() async {
        aRan = true;
      }, timeout: const Duration(milliseconds: 50)),
      _timeout,
    );
    expect(aRan, isFalse, reason: 'יש מקומות פנויים, אבל ל-a יש טעינה תקועה');
    expect(await _run(() async => 'b', plugin: 'b'), 'b');
    expect(reports, isEmpty);

    final stuckB = [
      for (var i = 0; i < 2; i++) _run(() => stuck.future, plugin: 'b'),
    ];
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(reports, [
      ['scanner', 'b'],
    ]);

    stuck.complete();
    await Future.wait([...stuckA, ...stuckB]);
    expect(PluginBookContentGate.runningLoadsForTesting, 0);
    expect(await _run(() async => 'again'), 'again');
    expect(reports, hasLength(1));
  });

  test('תוסף בלי טעינה פעילה עוקף תור, והמקומות ניתנים בסבב', () async {
    final starts = <String>[];
    final releases = <String, Completer<void>>{};
    Future<void> load(String plugin, String name) => _run(() {
      starts.add(name);
      return (releases[name] = Completer<void>()).future;
    }, plugin: plugin);

    final all = [
      for (var i = 1; i <= 5; i++) load('a', 'a$i'),
      for (var i = 1; i <= 3; i++) load('b', 'b$i'),
    ];
    await pumpEventQueue();
    expect(starts, ['a1', 'a2', 'b1'], reason: 'b לא ממתין מאחורי התור של a');

    for (final name in ['a1', 'a2', 'b1', 'a3', 'b2', 'a4', 'b3', 'a5']) {
      releases[name]!.complete();
      await pumpEventQueue();
    }
    await Future.wait(all);
    expect(starts, ['a1', 'a2', 'b1', 'a3', 'b2', 'a4', 'b3', 'a5']);
  });

  test('ביטול לפי בעלים מכשיל רק את הממתינים שלו', () async {
    final closed = Object();
    final blockers = [Completer<void>(), Completer<void>()];
    final running = [for (final b in blockers) _run(() => b.future)];
    var cancelledRan = false;
    final cancelled = _run(() async {
      cancelledRan = true;
    }, owner: closed);
    final kept = _run(() async => 'kept');
    final failed = expectLater(
      cancelled,
      throwsA(predicate((e) => e.toString().contains('error.unavailable'))),
    );

    PluginBookContentGate.cancelWaiters(closed);
    await failed;
    blockers.first.complete();
    expect(await kept, 'kept');
    expect(cancelledRan, isFalse);
    blockers.last.complete();
    await Future.wait(running);
    expect(PluginBookContentGate.runningLoadsForTesting, 0);
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
