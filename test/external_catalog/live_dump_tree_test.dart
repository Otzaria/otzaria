// כלי מחקר ידני: מוריד את עץ הקטלוג המלא של בר אילן לקובץ TSV, כדי
// שאפשר יהיה לתכנן את כללי השמות והקטגוריות על נתונים אמיתיים בלי
// להריץ סריקה חיה בכל איטרציה. אינו חלק מחבילת הבדיקות האוטומטית.
//
// הרצה: flutter test test/external_catalog/live_dump_tree_test.dart --plain-name dump
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_automation.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_installation_discovery.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_instance.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_profile.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_tree_reader.dart';
import 'package:otzaria/external_catalog/responsa/native/responsa_win32.dart';

void main() {
  test('dump', () {
    final target = Platform.environment['RESPONSA_DUMP'];
    if (target == null) {
      print('set RESPONSA_DUMP to the output path');
      return;
    }

    final selection = ResponsaInstallationDiscovery.selectInstallation();
    expect(selection, isNotNull, reason: 'no installation found');
    expect(
      selection!.instances,
      isNotEmpty,
      reason: 'בר אילן must be running for the dump',
    );
    final instance = ResponsaInstance.pick(selection.instances)!;
    print('installation: ${selection.installation.installPath}');

    final version =
        ResponsaInstallationDiscovery.versionFromWindowTitle(
          ResponsaWin32.windowText(instance.hwnd),
        ) ??
        selection.installation.version;
    final automation = ResponsaAutomation(
      pid: instance.pid,
      profile: ResponsaVersionProfile.forVersion(version),
    );
    final dialog = automation.ensureCitationDialog(
      ResponsaDeadline(const Duration(seconds: 60)),
    );
    final tree =
        ResponsaTreeReader.findCatalogTree(dialog.hwnd) ??
        ResponsaTreeReader.findCatalogTree(dialog.container);
    expect(tree, isNotNull, reason: 'catalog tree not found');

    final watch = Stopwatch()..start();
    final nodes = ResponsaTreeReader.walk(
      pid: instance.pid,
      treeHandle: tree!,
      progressEvery: 20000,
      onProgress: (n) => print('  scanned $n (${watch.elapsed.inSeconds}s)'),
    );
    print('nodes: ${nodes.length} in ${watch.elapsed}');

    // כתיבה סינכרונית בקבוצות. `IOSink.close()` מחזיר Future, והבדיקה
    // מסתיימת לפניו — כך נכתבו 153 שורות מתוך 1.25 מיליון.
    final file = File(target).openSync(mode: FileMode.write);
    final buffer = StringBuffer('level\tparam\tchildren\tname\n');
    for (final node in nodes) {
      buffer.writeln(
        '${node.level}\t${node.param}\t${node.childCount}\t'
        '${node.name.replaceAll('\t', ' ').replaceAll('\n', ' ')}',
      );
      if (buffer.length > 4 << 20) {
        file.writeStringSync(buffer.toString());
        buffer.clear();
      }
    }
    file.writeStringSync(buffer.toString());
    file.closeSync();
    print('written to $target');
  }, timeout: const Timeout(Duration(minutes: 20)));
}
