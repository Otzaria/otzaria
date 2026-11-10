@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:otzaria/plugins/services/plugin_archive_extractor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  late Directory output;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('otz-plugin-stream-');
    output = Directory(p.join(sandbox.path, 'OutputRoot'))..createSync();
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  test(
    'extracts nested stored and deflated entries without eager reads',
    () async {
      final payload = Uint8List(4 * 1024 * 1024);
      for (var i = 0; i < payload.length; i++) {
        payload[i] = (i * 17) & 0xff;
      }
      final package = Archive()
        ..addFile(
          ArchiveFile.string('manifest.json', '{"id":"fixture"}')
            ..compression = CompressionType.none,
        )
        ..addFile(ArchiveFile.bytes('assets/large.bin', payload))
        ..addFile(ArchiveFile.string('assets/info.txt', 'test content'));
      final zip = File(p.join(sandbox.path, 'plugin.zip'))
        ..writeAsBytesSync(ZipEncoder().encodeBytes(package));

      await extractPluginArchive(zip.path, output.path);

      expect(
        File(p.join(output.path, 'manifest.json')).readAsStringSync(),
        '{"id":"fixture"}',
      );
      expect(
        File(p.join(output.path, 'assets/large.bin')).readAsBytesSync(),
        payload,
      );
      expect(
        File(p.join(output.path, 'assets/info.txt')).readAsStringSync(),
        'test content',
      );
    },
  );

  test('preserves destination and entry path case', () async {
    final zip = File(p.join(sandbox.path, 'mixed_case.zip'))
      ..writeAsBytesSync(
        ZipEncoder().encodeBytes(
          Archive()
            ..addFile(ArchiveFile.directory('Assets/'))
            ..addFile(ArchiveFile.string('Assets/Index.HTML', 'content'))
            ..addFile(
              ArchiveFile.string('Nested/../Assets/Resolved.TXT', 'resolved'),
            )
            ..addFile(ArchiveFile.string('Manifest.JSON', 'manifest')),
        ),
      );

    await extractPluginArchive(zip.path, p.relative(output.path));

    expect(
      output
          .listSync(recursive: true)
          .map(
            (entry) =>
                p.relative(entry.path, from: output.path).replaceAll('\\', '/'),
          ),
      unorderedEquals([
        'Assets',
        'Assets/Index.HTML',
        'Assets/Resolved.TXT',
        'Manifest.JSON',
      ]),
    );
    expect(
      sandbox.listSync().whereType<Directory>().map(
        (dir) => p.basename(dir.path),
      ),
      ['OutputRoot'],
    );
  });

  test('rejects rooted paths and parent traversal in ZIP entries', () async {
    final marker = File(p.join(sandbox.path, 'escape.txt'));
    final paths = [
      '../escape.txt',
      'nested/../../escape.txt',
      '../OutputRoot/escape.txt',
      '../outputroot/escape.txt',
      marker.path,
      p.join(output.path, 'escape.txt'),
      if (Platform.isWindows) ...[
        r'..\escape.txt',
        r'nested\..\..\escape.txt',
        r'..\outputroot\escape.txt',
        r'\escape.txt',
        r'\\server\share\escape.txt',
      ],
    ];
    for (var i = 0; i < paths.length; i++) {
      final bytes = ZipEncoder().encodeBytes(
        Archive()..addFile(ArchiveFile.string(paths[i], 'escape')),
      );
      if (paths[i].contains('\\')) {
        // ZipEncoder ממיר ל-/; משחזרים גם נתיבי ZIP עם backslashes גולמיים.
        final name = utf8.encode(paths[i]);
        final central = ByteData.sublistView(
          bytes,
        ).getUint32(bytes.length - 22 + 16, Endian.little);
        bytes.setRange(30, 30 + name.length, name);
        bytes.setRange(central + 46, central + 46 + name.length, name);
      }
      final zip = File(p.join(sandbox.path, 'traversal_$i.zip'))
        ..writeAsBytesSync(bytes);

      await expectLater(
        extractPluginArchive(zip.path, output.path),
        throwsA(isA<FormatException>()),
        reason: paths[i],
      );
      expect(marker.existsSync(), isFalse, reason: paths[i]);
      expect(output.listSync(), isEmpty, reason: paths[i]);
    }
  });

  test(
    'rejects a directory entry that resolves to the extraction root',
    () async {
      final zip = File(p.join(sandbox.path, 'root_directory.zip'))
        ..writeAsBytesSync(
          ZipEncoder().encodeBytes(
            Archive()..addFile(ArchiveFile.directory('.')),
          ),
        );

      await expectLater(
        extractPluginArchive(zip.path, output.path),
        throwsA(isA<FormatException>()),
      );
      expect(output.listSync(), isEmpty);
    },
  );

  test(
    'a corrupt archive fails without leaving its input handle open',
    () async {
      final zip = File(p.join(sandbox.path, 'invalid.zip'))
        ..writeAsBytesSync([0, 1, 2, 3]);

      await expectLater(
        extractPluginArchive(zip.path, output.path),
        throwsA(isA<ArchiveException>()),
      );
      // The worker may immediately remove a downloaded package on failure.
      expect(() => zip.deleteSync(), returnsNormally);
    },
  );
}
