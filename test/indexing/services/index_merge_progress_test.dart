import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/indexing_work_status.dart';
import 'package:otzaria/indexing/services/index_merge_progress.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory indexDir;

  setUp(() {
    indexDir = Directory.systemTemp.createTempSync('merge_progress_test_');
  });

  tearDown(() {
    if (indexDir.existsSync()) indexDir.deleteSync(recursive: true);
  });

  void writeFile(String name, int bytes) {
    File(p.join(indexDir.path, name)).writeAsBytesSync(List.filled(bytes, 0));
  }

  test('לא נפתח כשאין תיקייה', () {
    expect(
      IndexMergeProgress.start(p.join(indexDir.path, 'missing'), (_) {}),
      isNull,
    );
  });

  test('לא נפתח כשאין קבצי סגמנט', () {
    writeFile('meta.json', 500);
    writeFile('otzaria_index_meta.json', 200);
    expect(IndexMergeProgress.start(indexDir.path, (_) {}), isNull);
  });

  test('מדווח את יחס הקבצים החדשים לגודל הסגמנטים שנכנסו למיזוג', () async {
    writeFile('aaa.store', 600);
    writeFile('aaa.term', 400);
    writeFile('meta.json', 9999); // אינו קובץ סגמנט — לא נספר בבסיס

    final reported = <double>[];
    final tracker = IndexMergeProgress.start(indexDir.path, reported.add);
    addTearDown(() => tracker?.stop());
    expect(tracker, isNotNull);

    writeFile('bbb.store', 250); // 250/1000
    await Future<void>.delayed(IndexMergeProgress.samplingInterval * 2);
    expect(reported.last, closeTo(0.25, 0.001));

    writeFile('bbb.term', 250); // 500/1000
    await Future<void>.delayed(IndexMergeProgress.samplingInterval * 2);
    expect(reported.last, closeTo(0.5, 0.001));
  });

  test('לא מגיע ל-100% גם כשהסגמנט החדש גדול מהמקור', () async {
    writeFile('aaa.store', 100);
    final reported = <double>[];
    final tracker = IndexMergeProgress.start(indexDir.path, reported.add);
    addTearDown(() => tracker?.stop());

    writeFile('bbb.store', 500);
    await Future<void>.delayed(IndexMergeProgress.samplingInterval * 2);
    expect(reported.last, 0.99);
  });

  test('stop מפסיק את הדיווח', () async {
    writeFile('aaa.store', 100);
    final reported = <double>[];
    final tracker = IndexMergeProgress.start(indexDir.path, reported.add)!;

    await Future<void>.delayed(IndexMergeProgress.samplingInterval * 2);
    tracker.stop();
    final countAfterStop = reported.length;

    writeFile('bbb.store', 50);
    await Future<void>.delayed(IndexMergeProgress.samplingInterval * 2);
    expect(reported.length, countAfterStop);
  });

  test('האחוז המוצג מעוגל כלפי מטה', () {
    expect(formatFinalizingPercent(0.0), '0%');
    expect(formatFinalizingPercent(0.999), '99%');
    expect(formatFinalizingPercent(1.0), '100%');
  });
}
