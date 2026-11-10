@TestOn('vm')
library;

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
    output = Directory(p.join(sandbox.path, 'target'))..createSync();
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  test('extracts nested stored and deflated entries without eager reads',
      () async {
    final payload = Uint8List(4 * 1024 * 1024);
    for (var i = 0; i < payload.length; i++) {
      payload[i] = (i * 17) & 0xff;
    }
    final package = Archive()
      ..addFile(ArchiveFile.string('manifest.json', '{"id":"fixture"}')
        ..compression = CompressionType.none)
      ..addFile(ArchiveFile.bytes('assets/large.bin', payload))
      ..addFile(ArchiveFile.string('assets/info.txt', 'test content'));
    final zip = File(p.join(sandbox.path, 'plugin.zip'))
      ..writeAsBytesSync(ZipEncoder().encodeBytes(package));

    await extractPluginArchive(zip.path, output.path);

    expect(
      File(p.join(output.path, 'manifest.json')).readAsStringSync(),
      '{"id":"fixture"}',
    );
    expect(File(p.join(output.path, 'assets/large.bin')).readAsBytesSync(),
        payload);
    expect(
      File(p.join(output.path, 'assets/info.txt')).readAsStringSync(),
      'test content',
    );
  });

  test('rejects ZIP path traversal outside the extraction directory',
      () async {
    final marker = File(p.join(sandbox.path, 'escape.txt'));
    final zip = File(p.join(sandbox.path, 'traversal.zip'))
      ..writeAsBytesSync(ZipEncoder().encodeBytes(
          Archive()..addFile(ArchiveFile.string('../escape.txt', 'escape'))));

    await expectLater(
      extractPluginArchive(zip.path, output.path),
      throwsA(isA<FormatException>()),
    );
    expect(marker.existsSync(), isFalse);
  });

  test('a corrupt archive fails without leaving its input handle open',
      () async {
    final zip = File(p.join(sandbox.path, 'invalid.zip'))
      ..writeAsBytesSync([0, 1, 2, 3]);

    await expectLater(
      extractPluginArchive(zip.path, output.path),
      throwsA(isA<ArchiveException>()),
    );
    // The worker may immediately remove a downloaded package on failure.
    expect(() => zip.deleteSync(), returnsNormally);
  });
}
