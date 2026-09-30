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

const String _namespace = 'otzaria.test.librarygate';

/// חלון מדומה: port במשבצת, ומאחוריו צד ה-peer האמיתי של [LibraryAccessGate].
class _FakeWindow {
  _FakeWindow(
    this.slot, {
    this.onSuspend,
    this.leaseCheckInterval = const Duration(seconds: 30),
  });

  final int slot;
  final Future<void> Function()? onSuspend;
  final Duration leaseCheckInterval;
  final List<String> calls = [];
  int replacedCallbacks = 0;
  late final LibraryAccessGate gate;
  ReceivePort? _port;

  void register() {
    gate = LibraryAccessGate(
      leaseCheckInterval: leaseCheckInterval,
      logError: (_, _, _) {},
      peerAccess: LibraryAccessRoutine(
        suspend: () async {
          calls.add('suspend');
          await onSuspend?.call();
        },
        resume: (dbReplaced) async => calls.add('resume:$dbReplaced'),
      ),
    )..onLibraryReplaced = () => replacedCallbacks++;
    final port = ReceivePort();
    expect(
      IsolateNameServer.registerPortWithName(
        port.sendPort,
        '$_namespace.$slot',
      ),
      isTrue,
    );
    port.listen((message) {
      final map = message as Map;
      final reply = map['reply'] as SendPort;
      final body = Map<String, dynamic>.from(map['body'] as Map);
      gate
          .handlePeerRequest(body)
          .then(
            (result) => reply.send({'ok': true, 'result': result}),
            onError: (Object e) => reply.send({'ok': false, 'error': '$e'}),
          );
    });
    _port = port;
  }

  /// חלון שנסגר: המשבצת משוחררת וה-port נסגר בלי לענות.
  void leave() {
    IsolateNameServer.removePortNameMapping('$_namespace.$slot');
    _port?.close();
    _port = null;
  }
}

LibraryAccessGate _coordinator({
  Duration ackTimeout = const Duration(seconds: 2),
  List<String>? log,
  LibraryAccessRoutine? selfAccess,
  bool renameProbe = false,
  bool Function(String)? isOpenInProcess,
}) => LibraryAccessGate(
  ackTimeout: ackTimeout,
  resumeTimeout: const Duration(seconds: 2),
  selfAccess:
      selfAccess ??
      LibraryAccessRoutine(suspend: () async {}, resume: (_) async {}),
  renameProbe: renameProbe,
  isOpenInProcess: isOpenInProcess ?? (_) => false,
  logError: (title, error, _) => log?.add('$title: $error'),
);

void main() {
  final windows = <_FakeWindow>[];

  _FakeWindow window(
    int slot, {
    Future<void> Function()? onSuspend,
    Duration leaseCheckInterval = const Duration(seconds: 30),
  }) {
    final w = _FakeWindow(
      slot,
      onSuspend: onSuspend,
      leaseCheckInterval: leaseCheckInterval,
    )..register();
    windows.add(w);
    return w;
  }

  setUp(() {
    WindowBus.namespace = _namespace;
    expect(WindowBus.instance.register(), 1);
  });

  tearDown(() {
    for (final w in windows) {
      w.leave();
    }
    windows.clear();
    LibrarySuspensionMarker.resetForTesting();
    WindowBus.instance.unregister();
    for (var i = 1; i <= WindowBus.slotCount; i++) {
      IsolateNameServer.removePortNameMapping('$_namespace.$i');
    }
    WindowBus.namespace = 'otzaria.window';
  });

  test('כל החלונות מאשרים סגירה, וה-resume מעביר את התוצאה', () async {
    final a = window(2);
    final b = window(3);
    final gate = _coordinator();

    final suspension = await gate.suspendAll();
    expect(suspension.releasedSlots, {2, 3});
    expect(a.calls, ['suspend']);
    expect(b.calls, ['suspend']);
    expect(a.gate.isPeerSuspended, isTrue);
    expect(LibrarySuspensionMarker.isRegistered, isTrue);

    await gate.resumeAll(suspension, dbReplaced: true);
    expect(a.calls, ['suspend', 'resume:true']);
    expect(b.calls, ['suspend', 'resume:true']);
    expect(a.replacedCallbacks, 1);
    expect(a.gate.isPeerSuspended, isFalse);
    expect(LibrarySuspensionMarker.isRegistered, isFalse);
  });

  test('resume בלי החלפה אינו מרענן את עץ הספרייה', () async {
    final a = window(2);
    final gate = _coordinator();
    await gate.resumeAll(await gate.suspendAll(), dbReplaced: false);
    expect(a.calls, ['suspend', 'resume:false']);
    expect(a.replacedCallbacks, 0);
  });

  test('חלון שלא מאשר בזמן: כשל ברור, וכולם מחודשים', () async {
    final slowRelease = Completer<void>();
    final good = window(2);
    final slow = window(3, onSuspend: () => slowRelease.future);
    final log = <String>[];
    final gate = _coordinator(
      ackTimeout: const Duration(milliseconds: 200),
      log: log,
    );

    await expectLater(
      gate.suspendAll(),
      throwsA(
        isA<LibrarySuspendFailed>().having((e) => e.slots, 'slots', [3]),
      ),
    );
    expect(good.calls, ['suspend', 'resume:false']);
    expect(LibrarySuspensionMarker.isRegistered, isFalse);
    expect(gate.isSuspending, isFalse);
    expect(log.first, contains('windows 3'));

    // ה-resume נשלח גם לחלון האיטי, ורץ אצלו אחרי שהסגירה מסתיימת.
    slowRelease.complete();
    await slow.gate.peerIdle;
    await pumpEventQueue();
    expect(slow.calls, ['suspend', 'resume:false']);
    expect(slow.gate.isPeerSuspended, isFalse);
  });

  test('חלון שנכשל בשחרור מכשיל את ההשעיה', () async {
    final good = window(2);
    window(3, onSuspend: () async => throw StateError('worker stuck'));
    final gate = _coordinator();

    await expectLater(gate.suspendAll(), throwsA(isA<LibrarySuspendFailed>()));
    expect(good.calls, ['suspend', 'resume:false']);
    expect(LibrarySuspensionMarker.isRegistered, isFalse);
  });

  test('חלון שנסגר באמצע הפרוטוקול אינו מכשיל את ההשעיה', () async {
    late _FakeWindow leaving;
    final stays = window(2);
    leaving = window(
      3,
      onSuspend: () {
        leaving.leave();
        return Completer<void>().future;
      },
    );
    final gate = _coordinator(ackTimeout: const Duration(milliseconds: 300));

    final suspension = await gate.suspendAll();
    expect(suspension.releasedSlots, {2});
    await gate.resumeAll(suspension, dbReplaced: false);
    expect(stays.calls, ['suspend', 'resume:false']);
  });

  test('חלון שנרשם באמצע ההשעיה מקבל suspend בסבב הבא', () async {
    _FakeWindow? newcomer;
    window(
      2,
      onSuspend: () async {
        newcomer = window(3);
      },
    );
    final gate = _coordinator();

    final suspension = await gate.suspendAll();
    expect(suspension.releasedSlots, {2, 3});
    expect(newcomer!.calls, ['suspend']);
    await gate.resumeAll(suspension, dbReplaced: true);
    expect(newcomer!.calls, ['suspend', 'resume:true']);
  });

  test('ההשעיה אינה רה-אנטרנטית, וסימון תפוס חוסם מתאם שני', () async {
    final gate = _coordinator();
    final suspension = await gate.suspendAll();
    await expectLater(gate.suspendAll(), throwsStateError);
    await expectLater(
      _coordinator().suspendAll(),
      throwsA(isA<LibrarySuspendFailed>()),
    );
    await gate.resumeAll(suspension, dbReplaced: false);
    await gate.resumeAll(suspension, dbReplaced: false);
    expect(LibrarySuspensionMarker.isRegistered, isFalse);
  });

  test('resume שאבד: החלון מתחדש לבד כשהסימון נעלם', () async {
    final a = window(2, leaseCheckInterval: const Duration(milliseconds: 30));
    final gate = _coordinator();
    await gate.suspendAll();
    // מדמה resume שלא הגיע: רק הסימון מוסר.
    LibrarySuspensionMarker.release();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await a.gate.peerIdle;
    expect(a.calls, ['suspend', 'resume:true']);
    expect(a.gate.isPeerSuspended, isFalse);
  });

  test('suspend כפול לאותה פעולה נענה בלי סגירה נוספת', () async {
    final a = window(2);
    final first = await a.gate.handlePeerRequest({
      'type': LibraryAccessGate.requestSuspend,
      'operationId': 'op',
    });
    final second = await a.gate.handlePeerRequest({
      'type': LibraryAccessGate.requestSuspend,
      'operationId': 'op',
    });
    expect(first, {'released': true});
    expect(second, {'released': true});
    expect(a.calls, ['suspend']);
    expect(
      await a.gate.handlePeerRequest({
        'type': LibraryAccessGate.requestResume,
        'operationId': 'other',
      }),
      isFalse,
    );
    expect(a.gate.isPeerSuspended, isTrue);
  });

  group('runExclusive', () {
    late Directory temp;
    setUp(() => temp = Directory.systemTemp.createTempSync('gate_test_'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('סוגר ומחדש את החלון הזה ואת האחרים, עם התוצאה', () async {
      final a = window(2);
      final self = <String>[];
      final gate = _coordinator(
        renameProbe: true,
        selfAccess: LibraryAccessRoutine(
          suspend: () async => self.add('suspend'),
          resume: (dbReplaced) async => self.add('resume:$dbReplaced'),
        ),
      );
      final dbPath = p.join(temp.path, 'seforim.db');
      File(dbPath).writeAsStringSync('db');

      final result = await gate.runExclusive(
        dbPath: dbPath,
        body: (scope) async {
          expect(a.gate.isPeerSuspended, isTrue);
          expect(self, ['suspend']);
          scope.markDbReplaced();
          return 7;
        },
      );
      expect(result, 7);
      expect(self, ['suspend', 'resume:true']);
      expect(a.calls, ['suspend', 'resume:true']);
      expect(File(dbPath).readAsStringSync(), 'db');
      expect(File('$dbPath.release-probe').existsSync(), isFalse);
    });

    test('כשל ב-body מחדש את כולם בלי דגל החלפה', () async {
      final a = window(2);
      final gate = _coordinator();
      await expectLater(
        gate.runExclusive<void>(
          dbPath: p.join(temp.path, 'missing.db'),
          body: (_) async => throw StateError('boom'),
        ),
        throwsStateError,
      );
      expect(a.calls, ['suspend', 'resume:false']);
      expect(LibrarySuspensionMarker.isRegistered, isFalse);
    });

    test('zdb שעדיין פתוח בתהליך: body לא רץ וכולם מחודשים', () async {
      final a = window(2);
      final log = <String>[];
      final gate = _coordinator(isOpenInProcess: (_) => true, log: log);
      var ran = false;
      await expectLater(
        gate.runExclusive(
          dbPath: p.join(temp.path, 'seforim.zdb'),
          body: (_) async => ran = true,
        ),
        throwsA(isA<LibraryStillOpenException>()),
      );
      expect(ran, isFalse);
      expect(a.calls, ['suspend', 'resume:false']);
      expect(log.single, contains('zvfs'));
    });

    test(
      'מסד רגיל שעדיין פתוח נתפס ב-rename probe ונשאר במקומו',
      () async {
        final dbPath = p.join(temp.path, 'seforim.db');
        final db = sqlite3.sqlite3.open(dbPath)..execute('CREATE TABLE t(x)');
        addTearDown(db.close);
        final gate = _coordinator(renameProbe: true);
        await expectLater(
          gate.verifyReleased(dbPath),
          throwsA(isA<LibraryStillOpenException>()),
        );
        expect(File(dbPath).existsSync(), isTrue);
      },
      skip: !Platform.isWindows,
    );
  });
}
