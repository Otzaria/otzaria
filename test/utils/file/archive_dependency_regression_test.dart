import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('truncated archive integers stay within a file-backed subset', () {
    final dir = Directory.systemTemp.createTempSync('archive-dependency-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File(p.join(dir.path, 'header.bin'))
      ..writeAsBytesSync(List.filled(32, 0xff));
    final input = InputFileStream(file.path);
    addTearDown(input.closeSync);
    final readers = <(int, int Function(InputStream))>[
      (2, (stream) => stream.readUint16()),
      (3, (stream) => stream.readUint24()),
      (4, (stream) => stream.readUint32()),
      (8, (stream) => stream.readUint64()),
    ];
    for (final (width, read) in readers) {
      for (var available = 0; available < width; available++) {
        final subset = input.subset(position: 5, length: available);
        expect(read(subset), 0, reason: 'width=$width, left=$available');
        expect(subset.position, available);
        expect(subset.length, 0);
        expect(subset.isEOS, isTrue);
      }
    }
    expect(input.position, 0);
  });

  test(
    'recompressing lazy GZip input preserves its final position and bytes',
    () {
      final data = List<int>.generate(65543, (index) => index * 73 & 0xff);
      final source = GZipDecoder().decodeLazy(
        InputMemoryStream(GZipEncoder().encodeBytes(data)),
        verify: true,
      );
      addTearDown(source.closeSync);
      final output = OutputMemoryStream();
      GZipEncoder().encodeStream(source, output);
      expect(source.position, data.length);
      expect(source.isEOS, isTrue);
      expect(GZipDecoder().decodeBytes(output.getBytes(), verify: true), data);
    },
  );
}
