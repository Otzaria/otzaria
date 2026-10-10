import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/utils/indexing_crash_canary.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'commit מנקה רק דילוג שנחתם, ומשמר ספר שעדיין מחולץ וספר שלא נבדק',
    () async {
      final temp = await Directory.systemTemp.createTemp('canary_commit_');
      addTearDown(() => temp.delete(recursive: true));
      final index = p.join(temp.path, 'index');
      final file = File('$index.in_flight.json')
        ..writeAsStringSync(jsonEncode({'skipped': 2, 'unvisited': 2}));
      IndexingCrashCanary.start(index);
      final canary = IndexingCrashCanary.current!;
      addTearDown(canary.finish);
      expect(canary.begin('skipped'), isFalse);
      expect(canary.begin('prefetched'), isTrue);
      canary.committed({'skipped'});
      expect(jsonDecode(file.readAsStringSync()), {
        'unvisited': 2,
        'prefetched': 1,
      });
      canary.finish();
      expect(jsonDecode(file.readAsStringSync()), {'unvisited': 2});
    },
  );

  test('ריצה בריאה אינה מחשבת את קבוצת הספרים לצורך ניקוי קריסות', () async {
    final temp = await Directory.systemTemp.createTemp('canary_lazy_');
    addTearDown(() => temp.delete(recursive: true));
    IndexingCrashCanary.start(
      p.join(temp.path, 'index'),
      pendingKeys: () {
        fail('ריצה ללא קריסה קודמת אינה צריכה לסרוק ספרים שוב');
      },
    );
    IndexingCrashCanary.current!.finish();
  });

  test('דילוג על ספר קורס נשמר גם כשספר נוסף מפיל את אותה אצווה', () async {
    final temp = await Directory.systemTemp.createTemp('canary_batch_');
    addTearDown(() => temp.delete(recursive: true));
    final index = p.join(temp.path, 'index');
    final file = File('$index.in_flight.json')
      ..writeAsStringSync(jsonEncode({'a': 2, 'b': 1}));
    IndexingCrashCanary.start(index);
    final canary = IndexingCrashCanary.current!;
    addTearDown(canary.finish);
    expect(canary.begin('a'), isFalse);
    canary.end('a');
    expect(canary.begin('b'), isTrue);
    expect(jsonDecode(file.readAsStringSync()), {'a': 2, 'b': 2});
  });

  test('ספר שבטיסה בסגירה מסודרת אינו נספר כקריסה (issue #2038)', () async {
    final tempDir = await Directory.systemTemp.createTemp('canary_');
    addTearDown(() => tempDir.delete(recursive: true));
    final index = p.join(tempDir.path, 'index');
    File('$index.in_flight.json').writeAsStringSync(jsonEncode({'a': 1}));

    IndexingCrashCanary.start(index);
    final canary = IndexingCrashCanary.current!;
    expect(canary.recovering, isTrue);
    expect(canary.begin('a'), isTrue);
    canary.finish();
    expect(IndexingCrashCanary.current, isNull);

    IndexingCrashCanary.start(index);
    expect(IndexingCrashCanary.current!.recovering, isFalse);
    IndexingCrashCanary.current!.finish();
  });
}
