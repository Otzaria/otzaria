import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/release/generate_app_file_manifest.dart';

const _archive = 'otzaria-linux-full.tar.zst';
const _appManifest = 'otzaria-app-files-linux-x64.json';
const _oldTag = '0.10.1+1';
const _newTag = '0.10.1+2';

void main() {
  late Directory temp;
  late Directory assets;
  late Directory output;
  late File newArchive;
  late File newManifest;
  late Map<String, String> environment;

  Future<void> run(String executable, List<String> args) async {
    final result = await Process.run(executable, args);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }

  Future<({File archive, File manifest})> bundle(String tag) async {
    final parent = Directory(p.join(temp.path, tag))..createSync();
    final root = Directory(p.join(parent.path, 'otzaria-linux-full', 'app'))
      ..createSync(recursive: true);
    File(p.join(root.path, 'app.txt')).writeAsStringSync('application $tag');
    writeInstalledReleaseStamp(
      root: root,
      releaseTag: tag,
      releaseVersion: '0.10.1',
      platform: 'linux',
      architecture: 'x64',
    );
    final manifest = File(p.join(parent.path, _appManifest))
      ..writeAsStringSync(
        jsonEncode(
          buildAppFileManifest(
            releaseTag: tag,
            releaseVersion: '0.10.1',
            platform: 'linux',
            architecture: 'x64',
            root: root,
          ),
        ),
      );
    final library = File(
      p.join(parent.path, 'otzaria-linux-full', 'library_db', 'seforim.db'),
    );
    library.parent.createSync(recursive: true);
    library.writeAsBytesSync(List.filled(2000, 42));
    final tar = p.join(parent.path, 'bundle.tar');
    await run('tar', ['-C', parent.path, '-cf', tar, 'otzaria-linux-full']);
    final archive = File(p.join(parent.path, _archive));
    await run('zstd', ['-q', tar, '-o', archive.path]);
    return (archive: archive, manifest: manifest);
  }

  Future<void> splitBase() async {
    final file = File(p.join(assets.path, _archive));
    final bytes = file.readAsBytesSync();
    final parts = <Map<String, Object?>>[];
    // חוצים את כותרת zstd והמסגרות: כל חלק חייב להיכנס לאותו זרם חילוץ.
    for (var offset = 0, index = 0; offset < bytes.length; index++) {
      final end = (offset + 17).clamp(0, bytes.length);
      final content = bytes.sublist(offset, end);
      final name = '$_archive.part-${index.toString().padLeft(3, '0')}';
      File(p.join(assets.path, name)).writeAsBytesSync(content);
      parts.add({
        'name': name,
        'size': content.length,
        'sha256': sha256.convert(content).toString(),
      });
      offset = end;
    }
    File(p.join(assets.path, '$_archive.manifest.json')).writeAsStringSync(
      jsonEncode({
        'schemaVersion': 1,
        'archive': _archive,
        'size': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
        'parts': parts,
      }),
    );
    file.deleteSync();
  }

  Future<ProcessResult> build() => Process.run('bash', [
    'tool/release/build_update_packages.sh',
    'x64',
    _newTag,
    newManifest.path,
    newArchive.path,
    output.path,
    '1',
  ], environment: environment);

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('linux-split-update-');
    assets = Directory(p.join(temp.path, 'assets'))..createSync();
    output = Directory(p.join(temp.path, 'packages'))..createSync();
    final old = await bundle(_oldTag);
    old.archive.copySync(p.join(assets.path, _archive));
    old.manifest.copySync(p.join(assets.path, _appManifest));
    final newer = await bundle(_newTag);
    newArchive = newer.archive;
    newManifest = newer.manifest;
    final bin = Directory(p.join(temp.path, 'bin'))..createSync();
    final gh = File(p.join(bin.path, 'gh'))
      ..writeAsStringSync(r'''#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
args = sys.argv[1:]
with open(os.environ['GH_CALLS'], 'a') as log:
    log.write(json.dumps(args) + '\n')
if args[0] == 'api':
    print('0.10.1+1')
    sys.exit(0)
if args[:2] == ['release', 'list']:
    print('0.10.1+1')
    sys.exit(0)
if args[:2] != ['release', 'download'] or args[2] != '0.10.1+1':
    sys.exit(1)
name = args[args.index('--pattern') + 1]
source = pathlib.Path(os.environ['GH_ASSETS']) / name
if not source.is_file():
    sys.exit(1)
if '--output' in args:
    with source.open('rb') as data:
        shutil.copyfileobj(data, sys.stdout.buffer)
else:
    shutil.copyfile(source, pathlib.Path(args[args.index('--dir') + 1]) / name)
''');
    await run('chmod', ['+x', gh.path]);
    environment = {
      'PATH':
          '${bin.path}${Platform.isWindows ? ';' : ':'}${Platform.environment['PATH']}',
      'UPDATE_PACKAGES_PLATFORM': 'linux',
      'UPDATE_PACKAGES_SOURCE_REPO': 'fixture/release',
      'GH_ASSETS': assets.path,
      'GH_CALLS': p.join(temp.path, 'gh-calls.jsonl'),
    };
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('מקור Linux נשמר ב-artifacts גם אחרי פיצול נכסי ההעלאה', () async {
    final workflow = File(
      '.github/workflows/build-and-announce.yml',
    ).readAsStringSync();
    final publish = workflow.substring(
      workflow.indexOf('- name: Publish differential update packages (Linux)'),
    );
    expect(
      publish,
      contains('artifacts/otzaria-linux-full/otzaria-linux-full.tar.zst'),
    );
    expect(
      publish,
      contains(
        'artifacts/otzaria-linux-full-\$arch/otzaria-linux-full-\$arch.tar.zst',
      ),
    );
    final upload = Directory(p.join(temp.path, 'release-files'))..createSync();
    newArchive.copySync(p.join(upload.path, _archive));
    final split = await Process.run(
      'bash',
      [
        'tool/release/split_oversized_assets.sh',
        upload.path,
        _archive,
      ],
      environment: {'SPLIT_THRESHOLD': '20', 'SPLIT_PART_SIZE': '17'},
    );
    expect(split.exitCode, 0, reason: '${split.stdout}\n${split.stderr}');
    expect(File(p.join(upload.path, _archive)).existsSync(), isFalse);
    final result = await build();
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(output.listSync(), isNotEmpty);
  });

  test('בסיס קודם יחיד עדיין מפיק חבילות מאומתות', () async {
    final result = await build();
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(output.listSync(), isNotEmpty);
  });

  test('בסיס קודם מפוצל מוזרם לפי המניפסט ומפיק חבילות מאומתות', () async {
    await splitBase();
    final result = await build();
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(
      output.listSync(),
      isNotEmpty,
      reason: '${result.stdout}\n${result.stderr}',
    );
    final calls = File(
      environment['GH_CALLS']!,
    ).readAsLinesSync().map((s) => jsonDecode(s) as List);
    for (final call in calls.where((args) => args[1] == 'download')) {
      expect(call[2], _oldTag);
      expect(call[call.indexOf('--repo') + 1], 'fixture/release');
    }
  });

  for (final corrupt in [false, true]) {
    test('חלק ${corrupt ? 'פגום' : 'חסר'} אינו מפיק חבילת עדכון', () async {
      await splitBase();
      final part = File(p.join(assets.path, '$_archive.part-001'));
      if (corrupt) {
        part.writeAsBytesSync(List.filled(part.lengthSync(), 0));
      } else {
        part.deleteSync();
      }
      final result = await build();
      expect(result.exitCode, 0);
      expect(output.listSync(), isEmpty);
    });
  }
}
