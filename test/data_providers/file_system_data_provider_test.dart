import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

import '../helpers/memory_settings_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FileSystemData.metadata', () {
    late Directory root;
    late _MetadataReadOverrides reads;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('otzaria-metadata-');
      reads = _MetadataReadOverrides();
      AppPaths.debugOverrideDataRootPath(path.join(root.path, 'data'));
      await Settings.init(cacheProvider: MemorySettingsCache());
      await Settings.setValue(SettingsRepository.keyLibraryPath, root.path);
    });

    tearDown(() async {
      AppPaths.debugOverrideDataRootPath(null);
      await root.delete(recursive: true);
    });

    test('הקטלוג הראשון מצטרף לקריאת הקורא ורענון קורא מחדש', () async {
      await IOOverrides.runWithIOOverrides(() async {
        final provider = FileSystemData();
        final repository = DataRepository(fileSystemData: provider);
        expect(reads.paths, isEmpty);

        final reader = provider.metadata;
        final initialCatalog = repository.library;
        expect(provider.metadata, same(reader));
        expect(reads.paths, [path.join(root.path, 'metadata.json')]);

        final refresh = repository.reloadLibrary();
        final refreshed = provider.metadata;
        expect(refreshed, isNot(same(reader)));
        expect(
          reads.paths,
          List.filled(2, path.join(root.path, 'metadata.json')),
        );

        reads.results[1].complete(
          jsonEncode([
            {
              'title': 'מ"ח',
              'heCategories': ['ראשונים', 'הלכה'],
              'order': 2.5,
            },
          ]),
        );
        await refresh;
        final entry = (await refreshed)['מח']!;
        expect(entry['heCategories'], 'ראשונים, הלכה');
        expect(entry['extraTitles'], ['מ"ח']);
        expect(entry['order'], 2);

        reads.results[0].complete(_metadataJson('ישן'));
        await initialCatalog;
        expect((await reader).keys, ['ישן']);
        expect(provider.metadata, same(refreshed));
      }, reads);
    });

    for (final (description, readerJson, readerMatcher) in [
      ('קריאה ישנה', _metadataJson('ישן'), completion(contains('ישן'))),
      ('JSON פגום', '[', throwsFormatException),
    ]) {
      test('רענון ראשון קורא מחדש בזמן שהקורא ממתין עם $description', () async {
        await IOOverrides.runWithIOOverrides(() async {
          final provider = FileSystemData();
          final repository = DataRepository(fileSystemData: provider);
          final reader = expectLater(provider.metadata, readerMatcher);

          final refresh = expectLater(repository.reloadLibrary(), completes);
          final refreshed = provider.metadata;
          final freshMetadata = expectLater(
            refreshed,
            completion(contains('תוקן')),
          );

          reads.results.skip(1).firstOrNull?.complete(_metadataJson('תוקן'));
          reads.results.first.complete(readerJson);
          await (reader, refresh, freshMetadata).wait;

          expect(
            reads.paths,
            List.filled(2, path.join(root.path, 'metadata.json')),
          );
          expect(provider.metadata, same(refreshed));
        }, reads);
      });
    }

    test('בנייה אחרי איפוס הספרייה קוראת מטא־נתונים מעודכנים', () async {
      await IOOverrides.runWithIOOverrides(() async {
        final provider = FileSystemData();
        final repository = DataRepository(fileSystemData: provider);
        final previous = provider.metadata;
        provider.clearBookCache();
        repository.invalidateLibraryCache();

        final catalog = repository.library;
        reads.results.first.complete(_metadataJson('לפני האיפוס'));
        reads.results.skip(1).firstOrNull?.complete(_metadataJson('חדש'));
        await catalog;

        expect(await provider.metadata, contains('חדש'));
        expect(await previous, contains('לפני האיפוס'));
      }, reads);
    });

    test('מטא־נתונים ממתינים שייכים לנתיב שפתח אותם', () async {
      final moved = await Directory(path.join(root.path, 'moved')).create();
      await IOOverrides.runWithIOOverrides(() async {
        final provider = FileSystemData();
        final previous = provider.metadata;
        provider.libraryPath = moved.path;
        final current = provider.metadata;

        reads.results[0].complete(_metadataJson('ישן'));
        expect((await previous).keys, ['ישן']);

        final catalog = DataRepository(fileSystemData: provider).library;
        expect(provider.metadata, same(current));
        expect(reads.paths, [
          path.join(root.path, 'metadata.json'),
          path.join(moved.path, 'metadata.json'),
        ]);
        reads.results[1].complete(_metadataJson('חדש'));
        await catalog;
        expect((await current).keys, ['חדש']);
      }, reads);
    });

    test('רענון מנסה שוב אחרי JSON פגום', () async {
      await IOOverrides.runWithIOOverrides(() async {
        final provider = FileSystemData();
        final invalid = expectLater(provider.metadata, throwsFormatException);
        reads.results.single.complete('[');
        await invalid;

        final catalog = provider.getLibrary();
        reads.results[1].complete(_metadataJson('תוקן'));
        await catalog;
        expect((await provider.metadata).keys, ['תוקן']);
      }, reads);
    });
  });

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
    const root = r'D:\HebrewBooks';

    setUp(() async {
      await Settings.init(cacheProvider: MemorySettingsCache());
      await Settings.setValue<String>(
        SettingsRepository.keyHebrewBooksPath,
        root,
      );
    });

    test('כונן לא מוכן מחזיר מפה ריקה', () async {
      final files = await IOOverrides.runZoned(
        () => FileSystemData.probeHebrewBooksPdfFilesByIds({123}),
        createFile: (p) => _ProbeFile(
          p,
          () async => throw FileSystemException('Exists failed', p, _notReady),
        ),
      );

      expect(files, isEmpty);
    });

    test('בודק מזהים במקביל עד שמונה בקשות פעילות', () async {
      var active = 0;
      var peak = 0;
      final files = await IOOverrides.runZoned(
        () => FileSystemData.probeHebrewBooksPdfFilesByIds({
          for (var id = 0; id < 12; id++) id,
        }),
        createFile: (p) => _ProbeFile(p, () async {
          active++;
          if (active > peak) peak = active;
          await Future<void>.delayed(Duration.zero);
          active--;
          return false;
        }),
      );

      expect(files, isEmpty);
      expect(peak, 8);
      expect(active, 0);
    });

    test('שומר קדימות שורש ומחזיר רק התאמות שלפני כשל הכונן', () async {
      final first = path.join(root, '1.pdf');
      final firstAlias = path.join(root, 'Books', 'hebrewbooks_org_1.pdf');
      final second = path.join(root, 'Books', '2.pdf');
      final fail = path.join(root, 'hebrewbooks_org_2.pdf');
      final later = path.join(root, '3.pdf');
      final candidates = {
        first,
        path.join(root, 'Books', '1.pdf'),
        firstAlias,
        second,
        later,
      };
      final files = await IOOverrides.runZoned(
        () => FileSystemData.probeHebrewBooksPdfFilesByIds({1, 2, 3}),
        createFile: (p) => _ProbeFile(p, () async {
          if (p == fail) {
            throw FileSystemException('Exists failed', p, _notReady);
          }
          return candidates.contains(p);
        }),
      );

      expect(files, {
        '1.pdf': first,
        'hebrewbooks_org_1.pdf': firstAlias,
        '2.pdf': second,
      });
      expect(
        files.keys,
        orderedEquals(['1.pdf', 'hebrewbooks_org_1.pdf', '2.pdf']),
      );
    });

    test('כשל בכונן ממתין רק לבדיקות שקדמו לו', () async {
      final first = Completer<bool>();
      final later = Completer<bool>();
      final laterError = Completer<bool>();
      final checked = <String>[];
      var returned = false;
      final probe =
          IOOverrides.runZoned(
            () => FileSystemData.probeHebrewBooksPdfFilesByIds({1, 2, 3, 4}),
            createFile: (p) => _ProbeFile(p, () async {
              final name = path.basename(p);
              checked.add(name);
              return switch (name) {
                '1.pdf' => first.future,
                '2.pdf' => throw FileSystemException(
                  'Exists failed',
                  p,
                  _notReady,
                ),
                '3.pdf' => later.future,
                '4.pdf' => laterError.future,
                _ => false,
              };
            }),
          ).then((files) {
            returned = true;
            return files;
          });

      try {
        await Future<void>.delayed(Duration.zero);
        expect(checked, orderedEquals(['1.pdf', '2.pdf', '3.pdf', '4.pdf']));
        expect(returned, isFalse);

        first.complete(true);
        await Future<void>.delayed(Duration.zero);
        expect(returned, isTrue);
        expect(await probe, {'1.pdf': path.join(root, '1.pdf')});

        later.complete(true);
        laterError.completeError(StateError('בדיקה מאוחרת נכשלה'));
        await Future<void>.delayed(Duration.zero);
        expect(checked, isNot(contains('hebrewbooks_org_3.pdf')));
      } finally {
        for (final pending in [first, later, laterError]) {
          if (!pending.isCompleted) pending.complete(false);
        }
      }
    });
  });
}

String _metadataJson(String title) => jsonEncode([
  {'title': title},
]);

final class _MetadataReadOverrides extends IOOverrides {
  final paths = <String>[];
  final results = <Completer<String>>[];

  @override
  File createFile(String filePath) {
    if (path.basename(filePath) != 'metadata.json') {
      return super.createFile(filePath);
    }
    return _MetadataFile(() {
      paths.add(filePath);
      final result = Completer<String>();
      results.add(result);
      return result.future;
    });
  }
}

class _MetadataFile implements File {
  _MetadataFile(this.readMetadata);

  final Future<String> Function() readMetadata;

  @override
  Future<String> readAsString({Encoding encoding = utf8}) => readMetadata();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

class _ProbeFile implements File {
  _ProbeFile(this.path, this._check);

  @override
  final String path;
  final Future<bool> Function() _check;

  @override
  Future<bool> exists() => _check();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
