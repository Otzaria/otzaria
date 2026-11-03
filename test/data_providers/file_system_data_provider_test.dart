import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

import '../helpers/memory_settings_cache.dart';

void main() {
  group('FileSystemData.scanHebrewBooksPdfFilesAtPath', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria-hb-pdfs-');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('מאתר PDF כשהנתיב מצביע ישירות לתיקיית הספרים', () async {
      final pdf = File(path.join(tempDir.path, '123.pdf'));
      await pdf.writeAsBytes(const [1]);

      final files = await FileSystemData.scanHebrewBooksPdfFilesAtPath(
        tempDir.path,
      );

      expect(files, {'123.pdf': pdf.path});
    });

    test('מאתר PDF תחת Books כשהנתיב מצביע לשורש HebrewBooks', () async {
      final booksDir = Directory(path.join(tempDir.path, 'Books'));
      await booksDir.create();
      final pdf = File(path.join(booksDir.path, '456.pdf'));
      await pdf.writeAsBytes(const [1]);

      final files = await FileSystemData.scanHebrewBooksPdfFilesAtPath(
        tempDir.path,
      );

      expect(files, {'456.pdf': pdf.path});
    });

    test(
      'מאתר PDF שהוא קישור סמלי',
      () async {
        final sourceDir = Directory(path.join(tempDir.path, 'source'));
        await sourceDir.create();
        final target = File(path.join(sourceDir.path, '789.pdf'));
        await target.writeAsBytes(const [1]);
        final link = Link(path.join(tempDir.path, '789.pdf'));
        await link.create(target.path);

        final files = await FileSystemData.scanHebrewBooksPdfFilesAtPath(
          tempDir.path,
        );

        expect(files, {'789.pdf': link.path});
      },
      skip: Platform.isWindows
          ? 'יצירת symlink דורשת הרשאה מיוחדת ב-Windows'
          : false,
    );

    test('כונן לא מוכן מתנהג כתיקייה שלא קיימת', () async {
      final files = await IOOverrides.runZoned(
        () => FileSystemData.scanHebrewBooksPdfFilesAtPath(r'D:\HebrewBooks'),
        createDirectory: (p) => _NotReadyDirectory(p),
      );

      expect(files, isEmpty);
    });
  });

  group('FileSystemData.probeHebrewBooksPdfFilesByIds', () {
    setUp(() async {
      await Settings.init(cacheProvider: MemorySettingsCache());
      await Settings.setValue<String>(
        SettingsRepository.keyHebrewBooksPath,
        r'D:\HebrewBooks',
      );
    });

    test('כונן לא מוכן מחזיר מפה ריקה', () async {
      final files = await IOOverrides.runZoned(
        () => FileSystemData.probeHebrewBooksPdfFilesByIds({123}),
        createFile: (p) => _NotReadyFile(p),
      );

      expect(files, isEmpty);
    });
  });
}

const _notReady = OSError('The device is not ready', 21);

class _NotReadyDirectory implements Directory {
  _NotReadyDirectory(this.path);

  @override
  final String path;

  @override
  Directory get absolute => this;

  @override
  Future<bool> exists() async =>
      throw FileSystemException('Exists failed', path, _notReady);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NotReadyFile implements File {
  _NotReadyFile(this.path);

  @override
  final String path;

  @override
  Future<bool> exists() async =>
      throw FileSystemException('Exists failed', path, _notReady);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
