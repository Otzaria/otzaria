import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/services/backup/backup_maintenance.dart';
import 'package:otzaria/settings/services/backup/backup_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late BackupStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_store_test');
    store = BackupStore.forBackupDir(tempDir.path);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<List<File>> blobFiles() async {
    final dir = Directory(store.objectsPath);
    if (!await dir.exists()) return [];
    return dir
        .list(recursive: true)
        .where((e) => e is File)
        .cast<File>()
        .toList();
  }

  test('roundtrip: putBytes ואז getBytes מחזיר את התוכן במדויק', () async {
    final bytes = utf8.encode('תוכן קובץ תוסף');
    final ref = await store.putBytes(bytes);
    expect(BackupStore.isHashRef(ref), isTrue);
    expect(await store.getBytes(ref), bytes);
    expect(await store.exists(ref), isTrue);
  });

  test('דה-דופליקציה: אותו תוכן נשמר פעם אחת בלבד', () async {
    final bytes = utf8.encode('אותו תוכן בדיוק');
    final ref1 = await store.putBytes(bytes);
    final ref2 = await store.putBytes(bytes);
    expect(ref1, ref2);
    expect(await blobFiles(), hasLength(1));
  });

  test('getBytes מחזיר null על blob חסר או פגום', () async {
    expect(await store.getBytes('sha256:${'0' * 64}'), isNull);

    final ref = await store.putBytes(utf8.encode('תוכן'));
    final hex = ref.substring(BackupStore.hashPrefix.length);
    final blobPath = p.join(store.objectsPath, hex.substring(0, 2), hex);
    await File(blobPath).writeAsBytes(gzip.encode(utf8.encode('שובש')));
    expect(await store.getBytes(ref), isNull);
  });

  group('sweep', () {
    test('blob יתום וישן נמחק; מופנה נשמר', () async {
      final kept = await store.putBytes(utf8.encode('מופנה'));
      final orphan = await store.putBytes(utf8.encode('יתום'));

      // מסמנים את שני הקבצים כישנים כדי לעבור את תקופת החסד
      final old = DateTime.now().subtract(const Duration(days: 60));
      for (final file in await blobFiles()) {
        await file.setLastModified(old);
      }

      final result = await store.sweep({kept});
      expect(result.deleted, 1);
      expect(await store.exists(kept), isTrue);
      expect(await store.exists(orphan), isFalse);
    });

    test('grace period: blob יתום אך טרי אינו נמחק', () async {
      final orphan = await store.putBytes(utf8.encode('יתום טרי'));
      final result = await store.sweep(const {});
      expect(result.deleted, 0);
      expect(await store.exists(orphan), isTrue);
    });
  });

  test('collectRefs אוסף הפניות מסעיפי files ו-data בלבד', () {
    final manifest = {
      'plugins': [
        {
          'files': {'a.js': 'sha256:${'a' * 64}', 'b.js': 'plain-base64=='},
          'data': {'c.json': 'sha256:${'c' * 64}'},
        },
      ],
      'bookmarks': [
        {'ref': 'sha256:not-a-plugin-section'},
      ],
    };
    expect(
      BackupStore.collectRefs(manifest),
      {'sha256:${'a' * 64}', 'sha256:${'c' * 64}'},
    );
  });

  group('BackupMaintenance helpers', () {
    test('parseBackupFileName מזהה timestamp ודגל ידני', () {
      final auto = BackupMaintenance.parseBackupFileName(
        p.join('x', 'otzaria_backup_2026-07-05T12-30-00.000.json'),
      );
      expect(auto, isNotNull);
      expect(auto!.isManual, isFalse);
      expect(auto.timestamp, DateTime(2026, 7, 5, 12, 30));

      final manual = BackupMaintenance.parseBackupFileName(
        p.join('x', 'otzaria_backup_2026-07-05T12-30-00.000_manual.json'),
      );
      expect(manual!.isManual, isTrue);

      expect(
        BackupMaintenance.parseBackupFileName(
          p.join('x', BackupMaintenance.archiveFileName),
        ),
        isNull,
      );
      expect(
        BackupMaintenance.parseBackupFileName(p.join('x', 'other.json')),
        isNull,
      );
    });

    test(
      'convertManifestToRefs מחליף base64 בהפניות ומשאיר הפניות קיימות',
      () async {
        final content = utf8.encode('קובץ תוסף');
        final existingRef = await store.putBytes(utf8.encode('כבר במחסן'));
        final manifest = <String, dynamic>{
          'version': '1.0',
          'plugins': [
            {
              'files': {
                'main.js': base64Encode(content),
                'old.js': existingRef,
              },
            },
          ],
        };

        await BackupMaintenance.convertManifestToRefs(manifest, store);

        expect(manifest['version'], '2.0');
        final files =
            ((manifest['plugins'] as List).first as Map)['files'] as Map;
        final newRef = files['main.js'] as String;
        expect(BackupStore.isHashRef(newRef), isTrue);
        expect(await store.getBytes(newRef), content);
        expect(files['old.js'], existingRef);
      },
    );
  });
}
