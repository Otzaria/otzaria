import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/otzaria_capabilities.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('capabilities'));
  tearDown(() => root.deleteSync(recursive: true));

  Map<String, Object?> content({
    String version = '0.9.98',
    String build = '99802',
  }) => OtzariaCapabilities.build(
    packageInfo: PackageInfo(
      appName: 'otzaria',
      packageName: 'otzaria',
      version: version,
      buildNumber: build,
    ),
    arch: 'arm64',
    portable: true,
    exePath: r'D:\Otzaria\otzaria.exe',
    libraryDbPath: r'D:\Otzaria\otzaria_data\books\seforim.db',
  );

  test('שדות החוזה, כולל מקטע ה-hotfix בגרסה', () {
    final c = content();
    expect(c['formatVersion'], 1);
    expect(c['appVersion'], '0.9.98.2');
    expect(c['buildNumber'], 99802);
    expect(c['arch'], 'arm64');
    expect(c['portable'], true);
    expect(c['readableDbSchemaVersion'], isA<int>());
    expect(c['reportsQueueFormat'], 1);
    expect(c['pluginInstallResults'], 1);
    expect(content(build: '99800')['appVersion'], '0.9.98');
  });

  test('נכתב רק כשהתוכן השתנה, באופן אטומי', () async {
    final file = File(p.join(root.path, OtzariaCapabilities.fileName));

    expect(
      await OtzariaCapabilities.writeIfChanged(root.path, content()),
      true,
    );
    final first = jsonDecode(file.readAsStringSync()) as Map;
    expect(first['writtenAt'], isA<String>());
    expect(first['appVersion'], '0.9.98.2');

    expect(
      await OtzariaCapabilities.writeIfChanged(root.path, content()),
      false,
    );
    expect(
      await OtzariaCapabilities.writeIfChanged(
        root.path,
        content(version: '0.9.99', build: '99900'),
      ),
      true,
    );
    expect(jsonDecode(file.readAsStringSync())['appVersion'], '0.9.99');
    expect(File('${file.path}.tmp').existsSync(), isFalse);
    expect(file.readAsBytesSync().take(3), isNot([0xEF, 0xBB, 0xBF]));
  });

  test('ארכיטקטורה מזוהה', () {
    expect([
      'x64',
      'arm64',
      'universal',
    ], contains(OtzariaCapabilities.currentArch()));
  });
}
