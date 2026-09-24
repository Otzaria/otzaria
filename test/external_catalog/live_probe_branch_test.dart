// כלי מדידה ידני: קורא ענף בודד בעץ הקטלוג, שוב ושוב, כדי לבדוק אם
// הוא יציב. ענף שמחזיר תוכן שונה בקריאה שנייה מעיד על כשל בסריקה
// ולא על מבנה אמיתי בתוכנה.
//
//   RESPONSA_PATH='אנציקלופדיות שונות > מנהגי החגים > עשרת ימי תשובה ויום הכיפורים' \
//     flutter test --run-skipped test/external_catalog/live_probe_branch_test.dart
@Tags(['live'])
library;

// כלי מדידה ידני: הפלט שלו הוא **התוצר**, והוא נקרא בטרמינל.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_automation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation_discovery.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_instance.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_launcher.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_profile.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_tree_reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('read one branch twice', () async {
    final path = (Platform.environment['RESPONSA_PATH'] ?? '')
        .split(' > ')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    expect(path, isNotEmpty, reason: 'set RESPONSA_PATH');

    final launch = await ResponsaLauncher.ensureRunning();
    expect(launch.running, isTrue, reason: launch.message);
    final selection = ResponsaInstallationDiscovery.selectInstallation();
    final instance = ResponsaInstance.pick(selection!.instances);
    expect(instance, isNotNull, reason: 'בר אילן חייב לרוץ');

    final automation = ResponsaAutomation(
      pid: instance!.pid,
      profile: ResponsaVersionProfile.forVersion(
        ResponsaInstallationDiscovery.versionFromWindowTitle(instance.title),
      ),
    );
    final dialog = automation.ensureCitationDialog(
      ResponsaDeadline(const Duration(seconds: 60)),
    );
    final tree =
        ResponsaTreeReader.findCatalogTree(dialog.hwnd) ??
        ResponsaTreeReader.findCatalogTree(dialog.container);
    expect(tree, isNotNull, reason: 'לא נמצא עץ הקטלוג');

    for (var round = 1; round <= 2; round++) {
      final watch = Stopwatch()..start();
      final children = ResponsaTreeReader.childrenAtPath(
        pid: instance.pid,
        treeHandle: tree!,
        path: path,
      );
      print(
        '--- round $round (${watch.elapsedMilliseconds}ms): '
        '${children?.length} children of ${path.join(' > ')}',
      );
      for (final child in (children ?? const []).take(12)) {
        print(
          '    k=${(child.param >> 16) & 0xFF} c=${child.childCount} '
          'param=${child.param}  ${child.name}',
        );
      }
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
