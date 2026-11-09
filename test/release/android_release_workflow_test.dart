import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

void main() {
  final workflow =
      loadYaml(
            File('.github/workflows/build-and-announce.yml').readAsStringSync(),
          )
          as YamlMap;
  final jobs = workflow['jobs'] as YamlMap;

  YamlMap step(String job, String name) =>
      ((jobs[job] as YamlMap)['steps'] as YamlList).cast<YamlMap>().singleWhere(
        (entry) => entry['name'] == name,
      );

  test(
    'אותם APK ומטא־נתונים מגיעים לארטיפקט, לשחרור ולחבילת FULL',
    () async {
      final temp = Directory.systemTemp.createTempSync('android-release-flow');
      addTearDown(() => temp.deleteSync(recursive: true));

      File write(String path, String contents) {
        final file = File(p.join(temp.path, path));
        file.parent.createSync(recursive: true);
        return file..writeAsStringSync(contents);
      }

      void sdkTool(String name, String output) {
        final file = write(
          'sdk/build-tools/36.0.0/$name',
          '#!/usr/bin/env python3\nprint(${jsonEncode(output)})\n',
        );
        expect(Process.runSync('chmod', ['+x', file.path]).exitCode, 0);
      }

      write(
        'tool/release/android_release_metadata.py',
        File('tool/release/android_release_metadata.py').readAsStringSync(),
      );
      write(
        'tool/release/pack_android_full.sh',
        File('tool/release/pack_android_full.sh').readAsStringSync(),
      );
      final apk = [0x50, 0x4b, 0x03, 0x04, 0xff, 0x00, 0xc0];
      write(
        'build/app/outputs/flutter-apk/app-direct-release.apk',
        '',
      ).writeAsBytesSync(apk);
      sdkTool(
        'aapt',
        "package: name='org.otzaria.otzaria' versionCode='99803' versionName='0.9.98'\n"
            "sdkVersion:'23'\ntargetSdkVersion:'36'\n"
            "uses-permission: name='android.permission.REQUEST_INSTALL_PACKAGES'\n"
            "native-code: 'arm64-v8a'\n",
      );
      sdkTool(
        'apksigner',
        'Signer #1 certificate SHA-256 digest: ${'ab' * 32}',
      );

      Future<void> runStep(String job, String name) async {
        final result = await Process.run(
          'bash',
          ['-euo', 'pipefail', '-c', step(job, name)['run'] as String],
          workingDirectory: temp.path,
          environment: {'ANDROID_SDK_ROOT': p.join(temp.path, 'sdk')},
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      }

      await runStep('build_android', 'Prepare Android update artifacts');
      final artifactPath =
          step('build_android', 'Upload apk')['with']['path'] as String;
      final artifact = Directory(p.join(temp.path, artifactPath));
      expect(
        artifact.listSync().map((entry) => p.basename(entry.path)),
        unorderedEquals(['otzaria-android.apk', 'otzaria-android.json']),
      );
      final metadataBytes = File(
        p.join(artifact.path, 'otzaria-android.json'),
      ).readAsBytesSync();
      final metadata = jsonDecode(utf8.decode(metadataBytes)) as Map;
      expect(metadata['versionCode'], 99803);
      expect(metadata['apk'], {
        'name': 'otzaria-android.apk',
        'size': apk.length,
        'sha256': sha256.convert(apk).toString(),
      });
      final upload =
          step('build_android', 'Upload release assets')['run'] as String;
      for (final entry in artifact.listSync().cast<File>()) {
        expect(upload, contains('$artifactPath${p.basename(entry.path)}'));
        final target = write('android-apk/${p.basename(entry.path)}', '');
        entry.copySync(target.path);
      }

      write('pubspec.yaml', 'version: 0.9.98+99803\n');
      for (final kind in ['library', 'library-index']) {
        write(
          'full_installer/otzaria-android-full/otzaria-0.9.98-$kind.tar.zst.manifest.json',
          '{}',
        );
      }
      await runStep('build_android_full', 'Create Android FULL bundle');
      final zip = ZipDecoder().decodeBytes(
        File(p.join(temp.path, 'otzaria-android-full.zip')).readAsBytesSync(),
      );
      expect(
        zip.findFile('otzaria-android-full/otzaria-android.apk')?.content,
        apk,
      );
      expect(
        zip.findFile('otzaria-android-full/otzaria-android.json')?.content,
        metadataBytes,
      );
    },
    skip: Platform.isWindows
        ? 'הפקת ה-APK ב-CI משתמשת ב-Bash ובכלי Linux'
        : false,
  );

  test('local Android packaging selects the direct flavor', () {
    final commands = File('create.bat').readAsLinesSync();
    expect(
      commands.singleWhere((line) => line.startsWith('call flutter build apk')),
      contains('--flavor direct'),
    );
    for (final platform in ['windows', 'linux']) {
      expect(commands, contains('call flutter build $platform'));
    }
  });

  test(
    'local launch configurations keep Android flavors platform-specific',
    () {
      final launch =
          jsonDecode(File('.vscode/launch.json').readAsStringSync()) as Map;
      final configs = (launch['configurations'] as List).cast<Map>();
      for (final mode in ['debug', 'profile']) {
        final android = configs.singleWhere(
          (entry) =>
              (entry['name'] as String).contains('Android') &&
              (entry['flutterMode'] ?? 'debug') == mode,
        );
        expect(android['toolArgs'], containsAllInOrder(['--flavor', 'direct']));
        final other = configs.singleWhere(
          (entry) =>
              !(entry['name'] as String).contains('Android') &&
              (entry['flutterMode'] ?? 'debug') == mode,
        );
        expect(other['toolArgs'], isNot(contains('--flavor')));
      }
      for (final config in configs) {
        expect(config['program'], 'lib/main.dart');
        expect(
          config['toolArgs'],
          contains('--dart-define-from-file=dart_defines.local.json'),
        );
      }
      final pubspec =
          loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
      expect(
        (pubspec['flutter'] as YamlMap).containsKey('default-flavor'),
        isFalse,
      );
    },
  );

  test('local Android instructions include the direct flavor', () {
    expect(
      File('README.md').readAsStringSync(),
      contains(
        'flutter run --flavor direct --dart-define-from-file=dart_defines.local.json',
      ),
    );
  });

  test('Google Play consumes the output of the Play flavor', () {
    final play =
        loadYaml(
              File(
                '.github/workflows/deploy-google-play.yml',
              ).readAsStringSync(),
            )
            as YamlMap;
    final steps = (play['jobs']['deploy_play']['steps'] as YamlList)
        .cast<YamlMap>();
    final build = steps.singleWhere(
      (entry) => entry['name'] == 'Build Android App Bundle',
    );
    final upload = steps.singleWhere(
      (entry) => entry['name'] == 'Upload to Google Play Production',
    );
    expect(build['run'], contains('--flavor play'));
    expect(
      upload['with']['releaseFiles'],
      'build/app/outputs/bundle/playRelease/app-play-release.aab',
    );
  });
}
