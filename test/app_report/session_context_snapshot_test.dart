import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/services/session_context_snapshot.dart';
import 'package:otzaria/app_report/services/unclean_exit_detector.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late String path;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('otzaria_session_context_');
    path = p.join(tmp.path, 'logs', SessionContextSnapshot.fileName);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Map<String, dynamic> readSaved() =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  test('ההפעלה הקודמת נקראת לפני שהנוכחית דורסת אותה', () async {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'savedAt': '2026-11-15T23:00:00.000Z',
          'pid': -1,
          'context': {'screen': 'search'},
        }),
      );
    final snapshot = SessionContextSnapshot(
      path: path,
      capture: () => {
        'context': {'screen': 'reading'},
      },
    );
    addTearDown(snapshot.stop);

    await snapshot.start();

    final previous = await snapshot.previous;
    expect(previous?['context'], {'screen': 'search'});
    expect(readSaved()['context'], {'screen': 'reading'});
    expect(readSaved()['pid'], pid);
  });

  group('previousFor', () {
    final crashed = SessionLock(
      pid: 4242,
      version: '1',
      startedAt: DateTime.utc(2026, 11, 15, 22),
    );

    SessionContextSnapshot saved({required int pid, required String at}) {
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'savedAt': at,
            'pid': pid,
            'context': {'screen': 'search'},
          }),
        );
      return SessionContextSnapshot(
        path: path,
        capture: () => {},
        systemEvents: (_) async => const [],
      );
    }

    test('נשמרה בהפעלה שקרסה: מצורפת', () async {
      final snapshot = saved(pid: 4242, at: '2026-11-15T23:00:00.000Z');
      expect(
        (await snapshot.previousFor(crashed))?['context'],
        {'screen': 'search'},
      );
    });

    test('נשארה מהפעלה שלפניה (תהליך אחר): לא מצורפת', () async {
      final snapshot = saved(pid: 77, at: '2026-11-15T23:00:00.000Z');
      expect(await snapshot.previousFor(crashed), isNull);
    });

    test('אותו מספר תהליך, אבל נשמרה לפני תחילת ההפעלה: לא מצורפת', () async {
      final snapshot = saved(pid: 4242, at: '2026-11-15T21:59:59.000Z');
      expect(await snapshot.previousFor(crashed), isNull);
    });

    test('אירועי המערכת מצורפים גם בלי תמונה, ונקראים פעם אחת', () async {
      var calls = 0;
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({'savedAt': '2026-11-15T23:00:00.000Z', 'pid': 77}),
        );
      final snapshot = SessionContextSnapshot(
        path: path,
        capture: () => {},
        systemEvents: (session) async {
          calls++;
          return [
            {'provider': 'Application Error', 'pid': session.pid},
          ];
        },
      );
      final first = await snapshot.previousFor(crashed);
      expect(first?['systemEvents'], [
        {'provider': 'Application Error', 'pid': 4242},
      ]);
      expect(first?.containsKey('context'), isFalse);
      await snapshot.previousFor(crashed);
      expect(calls, 1);
    });

    test('בלי נעילה (ANR): אין התאמה אמינה להפעלה', () async {
      final snapshot = saved(pid: 77, at: '2026-11-15T23:00:00.000Z');
      expect(await snapshot.previousFor(null), isNull);
    });
  });

  test('קובץ חסר או פגום: אין הקשר קודם', () async {
    expect(await SessionContextSnapshot(path: path).previous, isNull);
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{"pid": 1, "context"');
    expect(await SessionContextSnapshot(path: path).previous, isNull);
  });

  test('זיכרון ומקום פנוי נדגמים לכל היותר פעם בפרק הזמן', () async {
    var minute = 0;
    var samples = 0;
    final snapshot = SessionContextSnapshot(
      path: path,
      capture: () => {
        'context': {'screen': 'reading'},
      },
      clock: () => DateTime.utc(2026, 11, 16, 12, minute),
      sampleResources: () async => {'processCommitMb': 100 + samples++},
    );

    await snapshot.record();
    expect(readSaved()['resources'], {
      'sampledAt': '2026-11-16T12:00:00.000Z',
      'processCommitMb': 100,
    });
    minute = 4;
    await snapshot.record();
    expect(samples, 1);
    minute = 5;
    await snapshot.record();
    expect(samples, 2);
    expect(readSaved()['resources']['processCommitMb'], 101);
  });

  test('נכתב מחדש רק כשהתוכן השתנה', () async {
    var screen = 'reading';
    var tick = 0;
    final snapshot = SessionContextSnapshot(
      path: path,
      capture: () => {
        'context': {'screen': screen},
      },
      clock: () => DateTime.utc(2026, 11, 16, 12, 0, tick),
    );

    await snapshot.record();
    final first = readSaved()['savedAt'];
    tick++;
    await snapshot.record();
    expect(readSaved()['savedAt'], first);

    screen = 'search';
    tick++;
    await snapshot.record();
    expect(readSaved()['context'], {'screen': 'search'});
    expect(readSaved()['savedAt'], isNot(first));
    expect(File('$path.tmp').existsSync(), isFalse);
  });
}
