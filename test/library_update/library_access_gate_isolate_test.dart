import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/library_suspension_marker.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/library_update/services/library_access_gate.dart';
import 'package:path/path.dart' as p;

/// חלונות אמיתיים הם isolates באותו תהליך; כאן כל "חלון" הוא isolate שמחזיק
/// את המסד פתוח ב-SQLite, ורק IsolateNameServer מחבר ביניהם — כמו באפליקציה.
const String _namespace = 'otzaria.test.librarygate.isolates';

Future<void> _peerMain(List<Object> args) async {
  final slot = args[0] as int;
  final dbPath = args[1] as String;
  final ready = args[2] as SendPort;
  final honest = args[3] as bool;
  WindowBus.namespace = _namespace;

  sqlite3.Database open() =>
      sqlite3.sqlite3.open(dbPath, mode: sqlite3.OpenMode.readOnly);
  sqlite3.Database? db = open();
  final gate = LibraryAccessGate(
    logError: (_, _, _) {},
    peerAccess: LibraryAccessRoutine(
      suspend: () async {
        if (!honest) return;
        db?.close();
        db = null;
      },
      resume: (_) async => db ??= open(),
    ),
  );

  final port = ReceivePort();
  IsolateNameServer.registerPortWithName(port.sendPort, '$_namespace.$slot');
  port.listen((message) {
    final map = message as Map;
    final reply = map['reply'] as SendPort;
    final body = Map<String, dynamic>.from(map['body'] as Map);
    if (body['type'] == 'status') {
      final current = db;
      reply.send({
        'ok': true,
        'result': {
          'open': current != null,
          'value': current?.select('SELECT v FROM t').first['v'],
        },
      });
      return;
    }
    gate
        .handlePeerRequest(body)
        .then(
          (result) => reply.send({'ok': true, 'result': result}),
        );
  });
  ready.send(true);
}

Future<void> _waiterMain(SendPort done) async {
  WindowBus.namespace = _namespace;
  await LibrarySuspensionMarker.waitUntilReleased(
    poll: const Duration(milliseconds: 100),
  );
  done.send(true);
}

void _writeDb(String path, String value) {
  final db = sqlite3.sqlite3.open(path);
  try {
    db
      ..execute('CREATE TABLE t(v TEXT)')
      ..execute('INSERT INTO t VALUES (?)', [value]);
  } finally {
    db.close();
  }
}

void main() {
  late Directory temp;
  late String dbPath;
  final isolates = <Isolate>[];

  Future<void> spawnPeer(int slot, {bool honest = true}) async {
    final ready = ReceivePort();
    isolates.add(
      await Isolate.spawn(_peerMain, [slot, dbPath, ready.sendPort, honest]),
    );
    await ready.first;
  }

  Future<Map> status(int slot) async =>
      (await WindowBus.instance.request(slot, const {'type': 'status'}))!
          as Map;

  LibraryAccessGate coordinator() => LibraryAccessGate(
    ackTimeout: const Duration(seconds: 5),
    resumeTimeout: const Duration(seconds: 5),
    selfAccess: LibraryAccessRoutine(
      suspend: () async {},
      resume: (_) async {},
    ),
    logError: (_, _, _) {},
  );

  setUp(() {
    WindowBus.namespace = _namespace;
    expect(WindowBus.instance.register(), 1);
    temp = Directory.systemTemp.createTempSync('gate_isolates_');
    dbPath = p.join(temp.path, 'seforim.db');
    _writeDb(dbPath, 'old');
  });

  tearDown(() async {
    for (final isolate in isolates) {
      isolate.kill(priority: Isolate.immediate);
    }
    isolates.clear();
    LibrarySuspensionMarker.resetForTesting();
    WindowBus.instance.unregister();
    for (var i = 1; i <= WindowBus.slotCount; i++) {
      IsolateNameServer.removePortNameMapping('$_namespace.$i');
    }
    WindowBus.namespace = 'otzaria.window';
    // ה-isolate שנהרג משחרר את ה-handle באיחור קל.
    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        temp.deleteSync(recursive: true);
        break;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  test('שני חלונות סוגרים, המסד מוחלף, והם נפתחים על המסד החדש', () async {
    await spawnPeer(2);
    await spawnPeer(3);
    expect((await status(2))['value'], 'old');

    final newPath = '$dbPath.new';
    _writeDb(newPath, 'new');
    await coordinator().runExclusive(
      dbPath: dbPath,
      body: (scope) async {
        expect((await status(2))['open'], isFalse);
        expect((await status(3))['open'], isFalse);
        File(dbPath).deleteSync();
        File(newPath).renameSync(dbPath);
        scope.markDbReplaced();
      },
    );

    expect(await status(2), {'open': true, 'value': 'new'});
    expect(await status(3), {'open': true, 'value': 'new'});
  });

  test(
    'חלון שמאשר בלי לסגור נתפס באימות, וההחלפה לא מתבצעת',
    () async {
      await spawnPeer(2, honest: false);
      var ran = false;
      await expectLater(
        coordinator().runExclusive(
          dbPath: dbPath,
          body: (_) async => ran = true,
        ),
        throwsA(isA<LibraryStillOpenException>()),
      );
      expect(ran, isFalse);
      expect(File(dbPath).existsSync(), isTrue);
      expect(await status(2), {'open': true, 'value': 'old'});
    },
    skip: !Platform.isWindows,
  );

  test('חלון שנפתח בזמן ההשעיה ממתין עד resume', () async {
    final gate = coordinator();
    final suspension = await gate.suspendAll();

    final done = ReceivePort();
    final finished = Completer<void>();
    done.listen((_) => finished.complete());
    isolates.add(await Isolate.spawn(_waiterMain, done.sendPort));

    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(finished.isCompleted, isFalse);

    await gate.resumeAll(suspension, dbReplaced: true);
    await finished.future.timeout(const Duration(seconds: 3));
    done.close();
  });
}
