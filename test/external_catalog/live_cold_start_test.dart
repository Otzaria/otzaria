// כלי מדידה ידני: **הפעלה קרה**. סוגר כל מופע, ממתין שהמצב יתייצב,
// ואז מבקש מאוצריא לפתוח ספר — בדיוק כמו שהמשתמש עושה כשבר אילן סגור.
//
// הבדיקה היא לא "האם נפתח" אלא **באיזה מופע נפתח**: מופע חונה מחוץ
// למסך פותח ספרים בהצלחה בלי שהמשתמש רואה דבר.
//
//   flutter test --run-skipped test/external_catalog/live_cold_start_test.dart
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_controller.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation_discovery.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_instance.dart';
import 'package:sqlite3/sqlite3.dart';

String _instances() => [
  for (final instance in ResponsaInstance.all())
    'pid=${instance.pid} usable=${instance.usable} '
        'onScreen=${instance.onScreen} minimized=${instance.minimized} '
        'mdi=${instance.openWindows}',
].join('\n    ');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cold start opens in a visible instance', () async {
    final path =
        Platform.environment['RESPONSA_DB'] ??
        '${Platform.environment['LOCALAPPDATA']}'
            r'\ResponsaBridge\responsa_catalog.db';
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    final row = db
        .select(
          'SELECT title, open_ref, alt_refs FROM books '
          "WHERE title LIKE '%${Platform.environment['RESPONSA_ONLY'] ?? 'תורת יקותיאל'}%' LIMIT 1",
        )
        .single;
    final installPath = db
        .select("SELECT value FROM db_meta WHERE key='install_path'")
        .map((r) => r['value'].toString())
        .firstOrNull;
    db.close();
    final title = row['title'].toString();
    final refs = <String>[
      row['open_ref'].toString(),
      ...(row['alt_refs']?.toString() ?? '')
          .split('\n')
          .where((s) => s.trim().isNotEmpty),
    ];
    print('book: $title');

    final kill = Process.runSync('taskkill', ['/F', '/IM', 'RESPONSA.exe']);
    print('taskkill(${kill.exitCode}): ${kill.stdout}${kill.stderr}');
    // המופע החונה נוצר בסגירה עצמה ומתרוקן מחלונותיו בכשבע שניות.
    // המתנה קצרה מזו בודקת מצב ביניים ולא את המצב שהמשתמש פוגש.
    await Future<void>.delayed(const Duration(seconds: 20));
    print('after kill:\n    ${_instances()}');

    final selection = ResponsaInstallationDiscovery.selectInstallation(
      preferredPath: installPath,
    );
    print(
      'selected: ${selection?.installation.installPath} '
      'instances=${selection?.instances.length} '
      'picked=${selection == null ? null : ResponsaInstance.pick(selection.instances)?.pid}',
    );

    final watch = Stopwatch()..start();
    final report = await ResponsaController(
      allowAutoStart: () => true,
    ).openBook(refs, expectedTitle: title, installPath: installPath);
    watch.stop();
    print(
      'open: ok=${report.ok} ${watch.elapsedMilliseconds}ms '
      'window=${report.window} failure=${report.failure?.name} '
      'msg=${report.message}',
    );
    print('after open:\n    ${_instances()}');

    expect(report.ok, isTrue, reason: report.message);

    // הספר חייב להיות בחלון שהמשתמש רואה.
    final hosting = ResponsaInstance.all()
        .where((i) => i.openWindows > 0 && i.usable)
        .toList();
    expect(
      hosting,
      isNotEmpty,
      reason: 'הספר נפתח, אך לא במופע שנמצא על המסך',
    );
  }, timeout: const Timeout(Duration(minutes: 10)));
}
