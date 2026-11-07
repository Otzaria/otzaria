import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/attached_find_ref_worker.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/migration/database/query_loader.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';

import '../helpers/seforim_fixture_db.dart';

Future<int> _one(SeforimRepository repository) async => 1;
Future<int> _hang(SeforimRepository repository) => Completer<int>().future;
AttachedDbJob<int> _logged(int value, SendPort events) => (repository) async {
  await repository.database.database;
  events.send(value);
  return value;
};

AttachedDbJob<int> _gated(int value, SendPort events) => (repository) async {
  final gate = ReceivePort();
  events.send(value);
  events.send(gate.sendPort);
  try {
    await gate.first;
    return value;
  } finally {
    gate.close();
  }
};

const _resetPing = 'ping-after-reset';
const _workerExited = 'worker-exited';
const _cleanupCompleted = 'synchronous-cleanup-completed';

AttachedDbJob<int> _holdSynchronousCleanup(
  SendPort events,
  String releasePath,
) => (_) async {
  try {
    return 1;
  } finally {
    final release = File(releasePath);
    events.send(Isolate.current.controlPort);
    // A synchronous cleanup cannot consume an ordinary release-port message.
    while (!release.existsSync()) {}
    events.send(_cleanupCompleted);
  }
};

Future<int> _bookCount(SeforimRepository repository) async {
  final database = await repository.database.database;
  return database.select('SELECT COUNT(*) FROM book').first.columnAt(0) as int;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final worker = AttachedFindRefWorker.instance;
  late Directory directory;
  late String path;
  late (Duration, Duration) timeouts;
  final scopes = <int>[];

  int scope() {
    final value = AttachedFindRefWorker.allocateSearchScope();
    scopes.add(value);
    return value;
  }

  setUp(() async {
    await QueryLoader.initialize();
    await worker.reset();
    directory = await Directory.systemTemp.createTemp('attached_worker_batch');
    path = SeforimFixtureDb.create(directory, SeforimFixtureVariant.full);
    timeouts = (
      AttachedFindRefWorker.callTimeout,
      AttachedFindRefWorker.perCallTimeout,
    );
  });

  tearDown(() async {
    await worker.reset();
    for (final value in scopes) {
      worker.releaseSearchScope(value);
    }
    scopes.clear();
    AttachedFindRefWorker.callTimeout = timeouts.$1;
    AttachedFindRefWorker.perCallTimeout = timeouts.$2;
    await directory.delete(recursive: true);
  });

  test('חלון נוסף מקבל תור בין ספרי האצווה ושומר על סדר התוצאות', () async {
    final events = ReceivePort();
    addTearDown(events.close);
    final started = Completer<SendPort>();
    final order = <int>[];
    events.listen((message) {
      if (message is SendPort) {
        started.complete(message);
      } else {
        order.add(message as int);
      }
    });
    final first = worker.runBatch(
      path,
      immutable: false,
      version: 'v',
      jobs: [
        _gated(1, events.sendPort),
        _logged(2, events.sendPort),
        _logged(3, events.sendPort),
      ],
      searchScope: scope(),
      searchEpoch: 0,
    );
    final gate = await started.future;
    final second = worker.runBatch(
      path,
      immutable: false,
      version: 'v',
      jobs: [_logged(9, events.sendPort)],
      searchScope: scope(),
      searchEpoch: 0,
    );
    await Future<void>.delayed(Duration.zero);
    gate.send(null);
    expect(await second, [9]);
    expect(await first, [1, 2, 3]);
    expect(order, [1, 9, 2, 3]);
  });

  test('ביטול scope עוצר אחרי הספר הפעיל ואינו מבטל חלון אחר', () async {
    final events = ReceivePort();
    addTearDown(events.close);
    final started = Completer<SendPort>();
    final order = <int>[];
    events.listen((message) {
      if (message is SendPort) {
        started.complete(message);
      } else {
        order.add(message as int);
      }
    });
    final firstScope = scope();
    final first = worker.runBatch(
      path,
      immutable: false,
      version: 'v',
      jobs: [_gated(1, events.sendPort), _logged(2, events.sendPort)],
      searchScope: firstScope,
      searchEpoch: 0,
    );
    final cancelled = expectLater(first, throwsA(isA<FindRefQueryCancelled>()));
    final gate = await started.future;
    worker.cancelSearchScope(firstScope, 1);
    final second = worker.runBatch(
      path,
      immutable: false,
      version: 'v',
      jobs: [_logged(9, events.sendPort)],
      searchScope: scope(),
      searchEpoch: 0,
    );
    gate.send(null);
    await cancelled;
    expect(await second, [9]);
    expect(order, [1, 9]);
    expect(
      await worker.run(path, immutable: false, version: 'v', job: _one),
      1,
    );
  });

  test('cancel ואז release אינם מחיים את האצווה הפעילה', () async {
    final events = ReceivePort();
    addTearDown(events.close);
    final started = Completer<SendPort>();
    final order = <int>[];
    events.listen((message) {
      if (message is SendPort) {
        started.complete(message);
      } else {
        order.add(message as int);
      }
    });
    final id = scope();
    final pending = worker.runBatch(
      path,
      immutable: false,
      version: 'v',
      jobs: [_gated(1, events.sendPort), _logged(2, events.sendPort)],
      searchScope: id,
      searchEpoch: 0,
    );
    final failure = expectLater(pending, throwsA(isA<FindRefQueryCancelled>()));
    final gate = await started.future;
    worker.cancelSearchScope(id, 1);
    worker.releaseSearchScope(id);
    gate.send(null);
    await failure;
    expect(order, [1]);
    expect(
      await worker.run(path, immutable: false, version: 'v', job: _one),
      1,
    );
  });

  for (final background in [false, true]) {
    test('timeout משחרר ממתינים, השבתת מסד: ${!background}', () async {
      final otherPath = '${directory.path}/other.db';
      await File(path).copy(otherPath);
      await worker.run(path, immutable: false, version: 'v', job: _one);
      await worker.run(otherPath, immutable: false, version: 'v', job: _one);
      AttachedFindRefWorker.callTimeout = const Duration(milliseconds: 100);
      final active = worker.run(
        path,
        immutable: false,
        version: 'v',
        job: _hang,
        background: background,
      );
      final activeFailure = expectLater(
        active,
        throwsA(isA<TimeoutException>()),
      );
      final queued = worker.run(
        otherPath,
        immutable: false,
        version: 'v',
        job: _one,
      );
      final queuedFailure = expectLater(queued, throwsA(isA<StateError>()));
      await activeFailure;
      await queuedFailure.timeout(const Duration(seconds: 5));
      if (!background) {
        await expectLater(
          worker.run(path, immutable: false, version: 'v', job: _one),
          throwsA(isA<StateError>()),
        );
      }
      AttachedFindRefWorker.callTimeout = timeouts.$1;
      expect(
        await worker.run(otherPath, immutable: false, version: 'v', job: _one),
        1,
      );
      if (background) {
        expect(
          await worker.run(path, immutable: false, version: 'v', job: _one),
          1,
        );
      }
    });
  }

  test('reset אינו קוטע cleanup סינכרוני ומבטל את הקריאה הממתינה', () async {
    final release = File('${directory.path}/release');
    final events = ReceivePort();
    final started = Completer<Isolate>();
    final firstControlResponse = Completer<String>();
    final exited = Completer<void>();
    final observed = <String>[];
    final subscription = events.listen((message) {
      if (message is SendPort) {
        observed.add('synchronous-cleanup-started');
        started.complete(Isolate(message));
        return;
      }
      final event = message as String;
      observed.add(event);
      if ((event == _resetPing || event == _workerExited) &&
          !firstControlResponse.isCompleted) {
        firstControlResponse.complete(event);
      }
      if (event == _workerExited) exited.complete();
    });
    addTearDown(() async {
      release.createSync();
      await worker.reset();
      await subscription.cancel();
      events.close();
    });
    final active = worker.run(
      path,
      immutable: false,
      version: 'v',
      job: _holdSynchronousCleanup(events.sendPort, release.path),
    );
    final cancelled = expectLater(active, throwsA(isA<StateError>()));
    final isolate = await started.future;
    // One response port preserves the order of cleanup, ping, and real exit.
    isolate.addOnExitListener(events.sendPort, response: _workerExited);
    final closing = worker.reset();
    isolate.ping(
      events.sendPort,
      response: _resetPing,
      priority: Isolate.immediate,
    );
    try {
      expect(
        await firstControlResponse.future,
        _resetPing,
        reason: 'reset must defer exit until the synchronous cleanup returns',
      );
    } finally {
      // Release even when immediate kill makes the assertion fail.
      release.createSync();
      await closing;
      await exited.future;
      await cancelled;
      printOnFailure('Worker reset event order: $observed');
    }
    expect(observed, [
      'synchronous-cleanup-started',
      _resetPing,
      _cleanupCompleted,
      _workerExited,
    ]);
    expect(
      await worker.run(path, immutable: false, version: 'v', job: _bookCount),
      greaterThan(0),
    );
  });

  test('reset בזמן spawn משחרר את הבקשה ואפשר לפתוח שוב', () async {
    final pending = worker.run(path, immutable: false, version: 'v', job: _one);
    final failure = expectLater(pending, throwsA(isA<StateError>()));
    worker.reset();
    await failure.timeout(const Duration(seconds: 5));
    expect(
      await worker.run(path, immutable: false, version: 'v', job: _one),
      1,
    );
  });

  test('scope ששוחרר בזמן spawn אינו מגיש אצווה ישנה', () async {
    final id = scope();
    final pending = worker.runBatch(
      path,
      immutable: false,
      version: 'v',
      jobs: [_one],
      searchScope: id,
      searchEpoch: 0,
    );
    final failure = expectLater(pending, throwsA(isA<FindRefQueryCancelled>()));
    worker.cancelSearchScope(id, 1);
    worker.releaseSearchScope(id);
    await failure;
    expect(
      await worker.run(path, immutable: false, version: 'v', job: _one),
      1,
    );
  });
}
