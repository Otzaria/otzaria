import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/release/verify_release_draft.dart';

const _releaseId = '7';
const _repo = 'fixture/otzaria';

/// שרת שמחקה את ה-API של נכסי release ב-GitHub: רשימה, מחיקה והעלאה.
class _FakeRelease {
  final assets = <int, Map<String, Object?>>{};
  final uploads = <String>[];
  final deleted = <String>[];
  var failUploads = 0;
  final rejectedUploads = <String>{};
  var _nextId = 1;
  late HttpServer _server;

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  void add(String name, List<int> bytes, {String state = 'uploaded'}) {
    final id = _nextId++;
    assets[id] = {
      'id': id,
      'name': name,
      'size': bytes.length,
      'state': state,
      'digest': 'sha256:${sha256.convert(bytes)}',
    };
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    final response = request.response;
    final body = await request.fold<List<int>>([], (all, b) => all..addAll(b));
    if (request.method == 'GET' &&
        path == '/repos/$_repo/releases/$_releaseId/assets') {
      final page = int.parse(request.uri.queryParameters['page'] ?? '1');
      final perPage = int.parse(
        request.uri.queryParameters['per_page'] ?? '30',
      );
      final slice = assets.values.skip((page - 1) * perPage).take(perPage);
      response.write(jsonEncode(slice.toList()));
    } else if (request.method == 'DELETE' &&
        path.startsWith('/repos/$_repo/releases/assets/')) {
      final removed = assets.remove(int.parse(p.url.basename(path)));
      response.statusCode = removed == null ? 404 : 204;
      if (removed != null) deleted.add(removed['name']! as String);
    } else if (request.method == 'POST' &&
        path == '/repos/$_repo/releases/$_releaseId/assets') {
      final name = request.uri.queryParameters['name']!;
      if (failUploads > 0 || rejectedUploads.contains(name)) {
        if (failUploads > 0) failUploads--;
        response.statusCode = rejectedUploads.contains(name) ? 422 : 502;
      } else if (assets.values.any((a) => a['name'] == name)) {
        response.statusCode = 422;
      } else {
        add(name, body);
        uploads.add(name);
        response.statusCode = 201;
        response.write('{}');
      }
    } else {
      response.statusCode = 404;
    }
    await response.close();
  }
}

ReportedAsset _reported(String name, List<int> bytes) => ReportedAsset(
  name: name,
  size: bytes.length,
  sha256: sha256.convert(bytes).toString(),
);

DraftAsset _draft(
  int id,
  String name,
  List<int> bytes, {
  String state = 'uploaded',
  bool digest = true,
}) => DraftAsset(
  id: id,
  name: name,
  size: bytes.length,
  state: state,
  digest: digest ? 'sha256:${sha256.convert(bytes)}' : null,
);

void main() {
  group('checkDraft', () {
    final a = utf8.encode('installer');
    final b = utf8.encode('zip');

    test('טיוטה שמחזיקה בדיוק את מה שדווח עוברת', () {
      final check = checkDraft(
        reported: [_reported('a.exe', a), _reported('b.zip', b)],
        draft: [_draft(1, 'a.exe', a), _draft(2, 'b.zip', b, digest: false)],
      );
      expect(check.problems, isEmpty);
      expect(check.extra, isEmpty);
    });

    test('נכס חסר, חלקי, בגודל אחר או ב-hash אחר — כל אחד מדווח', () {
      final check = checkDraft(
        reported: [
          _reported('missing.exe', a),
          _reported('starter.exe', a),
          _reported('short.zip', b),
          _reported('other.zip', b),
        ],
        draft: [
          _draft(1, 'starter.exe', a, state: 'starter'),
          _draft(2, 'short.zip', utf8.encode('zi')),
          _draft(3, 'other.zip', utf8.encode('zap')),
        ],
      );
      expect(check.problems, hasLength(4));
      expect(check.problems[0], contains('missing.exe is missing'));
      expect(check.problems[1], contains('incomplete'));
      expect(check.problems[2], contains('2 bytes on the draft'));
      expect(check.problems[3], contains('other.zip on the draft has sha256:'));
    });

    test('נכס שאף job לא דיווח הוא שארית', () {
      final check = checkDraft(
        reported: [_reported('a.exe', a)],
        draft: [_draft(1, 'a.exe', a), _draft(2, 'old.exe.part-000', b)],
      );
      expect(check.problems, isEmpty);
      expect(check.extra.single.name, 'old.exe.part-000');
    });
  });

  group('mergeReportedAssets', () {
    test('אותו קובץ משני jobs נספר פעם אחת', () {
      final script = utf8.encode('#!/bin/sh');
      final merged = mergeReportedAssets([
        _reported('assemble_split_asset.sh', script),
        _reported('b.zip', [1]),
        _reported('assemble_split_asset.sh', script),
      ]);
      expect(merged.map((a) => a.name), ['assemble_split_asset.sh', 'b.zip']);
    });

    test('שני קבצים שונים באותו שם נכשלים', () {
      expect(
        () => mergeReportedAssets([
          _reported('a.exe', [1]),
          _reported('a.exe', [2]),
        ]),
        throwsA(isA<DraftVerificationException>()),
      );
    });
  });

  group('verifyReleaseDraft מול השרת', () {
    late Directory temp;
    late _FakeRelease release;
    late Directory records;

    void record(String name, Map<String, List<int>> files) {
      final dir = Directory(p.join(records.path, name))
        ..createSync(recursive: true);
      File(p.join(dir.path, kUploadRecordName)).writeAsStringSync(
        jsonEncode([
          for (final MapEntry(:key, :value) in files.entries)
            _reported(key, value).toJson(),
        ]),
      );
      for (final MapEntry(:key, :value) in files.entries) {
        if (key.endsWith('.json')) {
          File(p.join(dir.path, key)).writeAsBytesSync(value);
        }
      }
    }

    Future<void> verify(List<String> required) => verifyReleaseDraft(
      releaseId: _releaseId,
      records: records,
      filesDir: Directory(p.join(temp.path, 'release-files')),
      assetsOut: File(p.join(temp.path, 'release-assets.json')),
      requiredRecords: required,
      api: release.url,
      repo: _repo,
      token: 'token',
    );

    setUp(() async {
      temp = Directory.systemTemp.createTempSync('release_draft_verify_');
      records = Directory(p.join(temp.path, 'records'))..createSync();
      release = _FakeRelease();
      await release.start();
    });

    tearDown(() async {
      await release.stop();
      temp.deleteSync(recursive: true);
    });

    test('רשומה חסרה של job חובה עוצרת לפני כל פנייה', () async {
      record('otzaria-release-record-windows', {'a.exe': utf8.encode('a')});
      await expectLater(
        verify([
          'otzaria-release-record-windows',
          'otzaria-release-record-macos',
        ]),
        throwsA(
          isA<DraftVerificationException>().having(
            (e) => e.message,
            'message',
            contains('otzaria-release-record-macos'),
          ),
        ),
      );
    });

    test('שאריות נמחקות, וחבילות העדכון אינן נכסי בנייה', () async {
      final exe = utf8.encode('exe');
      final manifest = utf8.encode('{"parts": []}');
      final update = utf8.encode('patch');
      record('otzaria-release-record-windows', {
        'a.exe': exe,
        'a.exe.manifest.json': manifest,
      });
      record('otzaria-release-record-update-packages-windows', {
        'otzaria-update-windows-x64-1-2.zip': update,
      });
      release
        ..add('a.exe', exe)
        ..add('a.exe.manifest.json', manifest)
        ..add('otzaria-update-windows-x64-1-2.zip', update)
        ..add('stale.exe', utf8.encode('old'));

      await verify(['otzaria-release-record-windows']);

      expect(release.deleted, ['stale.exe']);
      final assets =
          jsonDecode(
                File(
                  p.join(temp.path, 'release-assets.json'),
                ).readAsStringSync(),
              )
              as List;
      expect(assets.map((a) => (a as Map)['name']), [
        'a.exe',
        'a.exe.manifest.json',
      ]);
      expect(
        File(
          p.join(temp.path, 'release-files', 'a.exe.manifest.json'),
        ).readAsStringSync(),
        '{"parts": []}',
      );
      expect(
        File(
          p.join(temp.path, 'release-files', kUploadRecordName),
        ).existsSync(),
        isFalse,
      );
    });

    test('נכס שגודלו שונה בטיוטה עוצר את הפרסום ואינו מוחק דבר', () async {
      record('otzaria-release-record-windows', {'a.exe': utf8.encode('exe')});
      release
        ..add('a.exe', utf8.encode('ex'))
        ..add('stale.exe', utf8.encode('old'));
      await expectLater(
        verify(['otzaria-release-record-windows']),
        throwsA(isA<DraftVerificationException>()),
      );
      expect(release.deleted, isEmpty);
    });

    test('רשימת הנכסים נקראת על פני כמה עמודים', () async {
      final files = {
        for (var i = 0; i < 130; i++) 'part-$i.bin': utf8.encode('part $i'),
      };
      record('otzaria-release-record-library', files);
      files.forEach(release.add);
      await verify(['otzaria-release-record-library']);
      expect(release.deleted, isEmpty);
    });
  });

  group('upload_release_assets.sh', () {
    final script = File('tool/release/upload_release_assets.sh').absolute.path;
    late Directory temp;
    late _FakeRelease release;

    // bash, curl, jq ו-split קיימים בכל runner של ה-workflow; במחשב בלעדיהם
    // הבדיקות מדולגות. ב-Windows, bash שב-System32 הוא WSL — OTZARIA_TEST_BASH.
    final bash = Platform.environment['OTZARIA_TEST_BASH'] ?? 'bash';
    final tools = () {
      try {
        return Process.runSync(bash, [
          '-c',
          'command -v jq && command -v curl && command -v split',
        ]).exitCode;
      } on ProcessException {
        return 1;
      }
    }();
    final skip = tools == 0 ? false : 'bash, curl, jq and split are required';

    Future<ProcessResult> upload(
      List<String> files, {
      Map<String, String> env = const {},
    }) => Process.run(
      bash,
      [script, _releaseId, 'release-record', ...files],
      workingDirectory: temp.path,
      environment: {
        'GH_TOKEN': 'token',
        'GITHUB_REPOSITORY': _repo,
        'GITHUB_API_URL': release.url,
        'RELEASE_UPLOAD_URL': release.url,
        'RELEASE_UPLOAD_RETRY_DELAY': '0',
        ...env,
      },
    );

    File file(String name, List<int> bytes) =>
        File(p.join(temp.path, name))..writeAsBytesSync(bytes);

    List<Map<String, Object?>> recorded() =>
        (jsonDecode(
                  File(
                    p.join(temp.path, 'release-record', kUploadRecordName),
                  ).readAsStringSync(),
                )
                as List)
            .cast<Map<String, Object?>>();

    setUp(() async {
      temp = Directory.systemTemp.createTempSync('release_draft_upload_');
      release = _FakeRelease();
      await release.start();
    });

    tearDown(() async {
      await release.stop();
      temp.deleteSync(recursive: true);
    });

    test('מעלה, רושם גודל ו-sha256, ומעתיק את נכסי ה-JSON לרשומה', () async {
      file('otzaria-macos.dmg', utf8.encode('dmg'));
      file('otzaria-app-files-macos-universal.json', utf8.encode('{}'));
      final result = await upload([
        'otzaria-macos.dmg',
        '--optional',
        'otzaria-app-files-macos-universal.json',
        'Otzaria-Download-Assistant-macos.zip',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stdout,
        contains('Otzaria-Download-Assistant-macos.zip is missing'),
      );
      expect(release.uploads, [
        'otzaria-app-files-macos-universal.json',
        'otzaria-macos.dmg',
      ]);
      expect(recorded().last, {
        'name': 'otzaria-macos.dmg',
        'size': 3,
        'sha256': sha256.convert(utf8.encode('dmg')).toString(),
      });
      expect(
        File(
          p.join(
            temp.path,
            'release-record',
            'otzaria-app-files-macos-universal.json',
          ),
        ).existsSync(),
        isTrue,
      );
      expect(
        temp.listSync().map((e) => p.basename(e.path)),
        isNot(contains(startsWith('.release-upload'))),
      );
    }, skip: skip);

    test('קובץ חובה חסר מפיל את ההעלאה', () async {
      final result = await upload(['otzaria-macos.dmg']);
      expect(result.exitCode, isNot(0));
      expect(release.uploads, isEmpty);
    }, skip: skip);

    test('קובץ זהה שכבר עלה אינו עולה שוב, ועותק ישן מוחלף', () async {
      final same = utf8.encode('same');
      release
        ..add('a.zip', same)
        ..add('b.zip', utf8.encode('stale'));
      file('a.zip', same);
      file('b.zip', utf8.encode('fresh'));
      final result = await upload(['a.zip', 'b.zip']);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(release.uploads, ['b.zip']);
      expect(release.deleted, ['b.zip']);
      expect(
        release.assets.values.firstWhere((a) => a['name'] == 'b.zip')['size'],
        5,
      );
    }, skip: skip);

    test('העלאה שנכשלה מנוסה שוב', () async {
      file('a.zip', utf8.encode('zip'));
      release.failUploads = 2;
      final result = await upload(['a.zip']);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(release.uploads, ['a.zip']);
    }, skip: skip);

    test('כשל סמלים ברשות אינו מונע העלאת מתקין ורשומה', () async {
      const symbols = 'otzaria-native-symbols-x64.zip';
      const installer = 'otzaria-windows.zip';
      file(symbols, utf8.encode('pdbs'));
      file(installer, utf8.encode('installer'));
      release.rejectedUploads.add(symbols);
      final result = await upload([installer, '--best-effort', symbols]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(release.uploads, [installer]);
      expect(recorded().map((asset) => asset['name']), [installer]);
      expect(result.stdout, contains('release goes out without it'));
    }, skip: skip);

    test('סמלים שעלו בהצלחה נכללים ברשומה וסמלים חסרים מותרים', () async {
      const symbols = 'otzaria-native-symbols-arm64.zip';
      file(symbols, utf8.encode('pdbs'));
      file('otzaria-windows_arm64.zip', utf8.encode('installer'));
      final result = await upload([
        'otzaria-windows_arm64.zip',
        '--best-effort',
        symbols,
        'otzaria-native-symbols-x64.zip',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(recorded().map((asset) => asset['name']), [
        symbols,
        'otzaria-windows_arm64.zip',
      ]);
      expect(release.uploads, [symbols, 'otzaria-windows_arm64.zip']);
    }, skip: skip);

    test('כשל העלאה של מתקין חובה עדיין מפיל את ההעלאה', () async {
      file('installer.zip', utf8.encode('installer'));
      file('symbols.zip', utf8.encode('pdbs'));
      release.rejectedUploads.add('installer.zip');
      final result = await upload([
        'installer.zip',
        '--best-effort',
        'symbols.zip',
      ]);
      expect(result.exitCode, isNot(0));
      expect(
        File(
          p.join(temp.path, 'release-record', kUploadRecordName),
        ).existsSync(),
        isFalse,
      );
    }, skip: skip);

    test('קובץ optional קיים שנכשל בהעלאה עדיין נחשב לכשל', () async {
      file('manifest.json', utf8.encode('{}'));
      release.rejectedUploads.add('manifest.json');
      final result = await upload(['--optional', 'manifest.json']);
      expect(result.exitCode, isNot(0));
    }, skip: skip);

    test('FULL מעל הסף עולה כחלקים ומניפסט, בלי סקריפטי הרכבה', () async {
      final big = List<int>.generate(250, (i) => i % 256);
      final full = file('otzaria-linux-full.tar.zst', big);
      final result = await upload(
        ['otzaria-linux-full.tar.zst'],
        env: {'SPLIT_THRESHOLD': '100', 'SPLIT_PART_SIZE': '96'},
      );
      expect(
        result.exitCode,
        0,
        reason: '${result.stdout}\n${result.stderr}',
      );
      // סקריפטי ההרכבה עולים רק מ-build_library_assets: checkout של Windows
      // מחזיק אותם לפעמים ב-CRLF, ושני jobs היו מדווחים קבצים שונים באותו שם.
      expect(release.uploads..sort(), [
        'otzaria-linux-full.tar.zst.manifest.json',
        'otzaria-linux-full.tar.zst.part-000',
        'otzaria-linux-full.tar.zst.part-001',
        'otzaria-linux-full.tar.zst.part-002',
      ]);
      // הקובץ של ה-job נשאר: הפיצול נעשה על קישור בתיקיית ההעלאה.
      expect(full.readAsBytesSync(), big);
      expect(
        recorded().map((a) => a['name']),
        contains('otzaria-linux-full.tar.zst.manifest.json'),
      );
      expect(
        File(
          p.join(
            temp.path,
            'release-record',
            'otzaria-linux-full.tar.zst.manifest.json',
          ),
        ).existsSync(),
        isTrue,
      );
    }, skip: skip);
    test('סקריפטי ההרכבה עולים כשהם מועברים במפורש', () async {
      for (final name in [
        'assemble_split_asset.sh',
        'assemble_split_asset.ps1',
      ]) {
        file(name, utf8.encode('assemble $name'));
      }
      final result = await upload([
        'assemble_split_asset.sh',
        'assemble_split_asset.ps1',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(release.uploads..sort(), [
        'assemble_split_asset.ps1',
        'assemble_split_asset.sh',
      ]);
    }, skip: skip);

    // ב-macOS ה-split של BSD; בלי GNU split החלקים נחתכים ב-dd לאותם שמות.
    test('split_release_asset.sh בלי GNU split מפיק אותם חלקים', () async {
      final archive = file(
        'otzaria-macos-full.tar.zst',
        List<int>.generate(250, (i) => (i * 7) % 256),
      );
      final bin = Directory(p.join(temp.path, 'bin'))..createSync();
      File(p.join(bin.path, 'split')).writeAsStringSync('#!/bin/sh\nexit 1\n');
      Future<Map<String, String>> cut(String out, {bool gnu = true}) async {
        final result = await Process.run(
          bash,
          [
            File('tool/release/split_release_asset.sh').absolute.path,
            archive.path,
            p.join(temp.path, out),
            '96',
          ],
          environment: gnu
              ? null
              : {
                  'PATH':
                      '${bin.path}${Platform.isWindows ? ';' : ':'}'
                      '${Platform.environment['PATH']}',
                },
        );
        expect(result.exitCode, 0, reason: '${result.stderr}');
        return {
          for (final f in Directory(p.join(temp.path, out)).listSync())
            p.basename(f.path): sha256
                .convert((f as File).readAsBytesSync())
                .toString(),
        };
      }

      final gnu = await cut('gnu');
      expect(gnu.keys, hasLength(4));
      expect(await cut('dd', gnu: false), gnu);
    }, skip: skip);

    test('שם DEB עם + עולה, מוחלף ונרשם כמות שהוא', () async {
      const deb = 'otzaria-0.9.98+99802-linux.deb';
      release.add(deb, utf8.encode('stale'));
      file(deb, utf8.encode('fresh deb'));
      final result = await upload([deb]);
      expect(
        result.exitCode,
        0,
        reason: '${result.stdout}\n${result.stderr}',
      );
      expect(release.deleted, [deb]);
      expect(release.uploads, [deb]);
      expect(recorded().single['name'], deb);

      // העלאה חוזרת של אותו קובץ מזוהה כזהה ואינה עולה שוב.
      final again = await upload([deb]);
      expect(again.exitCode, 0, reason: '${again.stdout}\n${again.stderr}');
      expect(release.uploads, [deb]);
    }, skip: skip);
  });
}
