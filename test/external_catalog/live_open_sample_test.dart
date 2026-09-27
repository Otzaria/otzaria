// כלי מדידה ידני: פותח מדגם ספרים אקראי בבר אילן החי ומדווח הצלחות, כשלים וזמנים.
// RESPONSA_DB=<catalog.db> RESPONSA_N=40 RESPONSA_SEED=7 flutter test --run-skipped test/external_catalog/live_open_sample_test.dart
@Tags(['live'])
library;

// כלי מדידה ידני: הפלט שלו הוא **התוצר**, והוא נקרא בטרמינל.
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_controller.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('open sample', () async {
    final path =
        Platform.environment['RESPONSA_DB'] ??
        '${Platform.environment['LOCALAPPDATA']}'
            r'\ResponsaBridge\responsa_catalog.db';
    final count = int.parse(Platform.environment['RESPONSA_N'] ?? '25');
    final seed = int.parse(Platform.environment['RESPONSA_SEED'] ?? '7');
    final only = Platform.environment['RESPONSA_ONLY'];

    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    final rows = db
        .select('SELECT title, open_ref, alt_refs FROM books')
        .map(
          (r) => (
            title: r['title'].toString(),
            refs: <String>[
              r['open_ref'].toString(),
              ...(r['alt_refs']?.toString() ?? '')
                  .split('\n')
                  .where((s) => s.trim().isNotEmpty),
            ],
          ),
        )
        .toList();
    final installPath = db
        .select("SELECT value FROM db_meta WHERE key='install_path'")
        .map((r) => r['value'].toString())
        .firstOrNull;
    db.close();
    print('catalog: ${rows.length} books from $installPath');

    final picked = only != null
        ? rows.where((r) => r.title.contains(only)).take(count).toList()
        : (List.of(rows)..shuffle(Random(seed))).take(count).toList();

    final controller = ResponsaController(allowAutoStart: () => true);
    var ok = 0;
    final times = <int>[];
    final failures = <String>[];

    for (final row in picked) {
      final watch = Stopwatch()..start();
      final report = await controller.openBook(
        row.refs,
        expectedTitle: row.title,
        installPath: installPath,
      );
      watch.stop();
      if (report.ok) {
        ok++;
        times.add(watch.elapsedMilliseconds);
        print(
          '  OK   ${watch.elapsedMilliseconds}ms  ${row.title}'
          '  [${report.usedRef}] -> ${report.window}',
        );
      } else {
        failures.add(
          '${row.title}\n       failure=${report.failure?.name}'
          '\n       tried=${report.triedRefs}\n       msg=${report.message}',
        );
        print(
          '  FAIL ${watch.elapsedMilliseconds}ms  ${row.title}'
          '  ${report.failure?.name}',
        );
      }
    }

    times.sort();
    print('\n=== $ok/${picked.length} opened');
    if (times.isNotEmpty) {
      print('median ${times[times.length ~/ 2]}ms, max ${times.last}ms');
    }
    for (final failure in failures) {
      print('  - $failure');
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}
