import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_install_results_log.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late PluginInstallResultsLog log;
  late File file;

  setUp(() {
    root = Directory.systemTemp.createTempSync('plugin_install_results');
    file = File(p.join(root.path, PluginInstallResultsLog.resultsFileName));
    log = PluginInstallResultsLog(
      resolveDataRoot: () async => root.path,
      now: () => DateTime.utc(2026, 10, 12, 10),
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('שורת JSON לפי החוזה', () async {
    await log.append(
      path: r'D:\usb\a.otzplugin',
      outcome: PluginInstallOutcome.rejectedIncompatible,
      pluginId: 'a.b',
      version: '1.2.3',
      message: 'דורש 9.0.0',
    );
    await log.append(
      path: r'D:\usb\b.otzplugin',
      outcome: PluginInstallOutcome.failed,
    );

    final lines = file.readAsLinesSync().map(jsonDecode).toList();
    expect(lines.first, {
      'path': r'D:\usb\a.otzplugin',
      'pluginId': 'a.b',
      'version': '1.2.3',
      'outcome': 'rejected_incompatible',
      'message': 'דורש 9.0.0',
      'at': '2026-10-12T10:00:00.000Z',
    });
    expect(lines.last['pluginId'], isNull);
    expect(lines.last['outcome'], 'failed');
  });

  test('מעל 500 שורות — נשארות 200 האחרונות', () async {
    file.writeAsStringSync(
      '${List.generate(500, (i) => jsonEncode({'path': '$i'})).join('\n')}\n',
    );

    await log.append(path: 'new', outcome: PluginInstallOutcome.installed);

    final lines = file.readAsLinesSync();
    expect(lines.length, 200);
    expect(jsonDecode(lines.first)['path'], '301');
    expect(jsonDecode(lines.last)['path'], 'new');
  });

  test('כשל בכתיבה אחת אינו חוסם את הבאות', () async {
    var failNext = true;
    final flaky = PluginInstallResultsLog(
      resolveDataRoot: () async {
        if (failNext) {
          failNext = false;
          throw const FileSystemException('denied');
        }
        return root.path;
      },
    );

    await expectLater(
      flaky.append(path: 'x', outcome: PluginInstallOutcome.failed),
      throwsA(isA<FileSystemException>()),
    );
    await flaky.append(path: 'y', outcome: PluginInstallOutcome.installed);

    expect(file.readAsLinesSync().length, 1);
  });
}
