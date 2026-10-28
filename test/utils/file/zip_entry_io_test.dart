import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/zip_entry_io.dart';
import 'package:path/path.dart' as p;
import 'package:posix/posix.dart' as posix;

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('zip_entry_io_'));
  tearDown(() => temp.deleteSync(recursive: true));

  // יותר מנתח אחד של 1MB, וחלקו לא דחיס, כדי שהפריסה תעבור כמה סבבים.
  Uint8List payload() {
    final random = Random(7);
    return Uint8List.fromList(
      List.generate(
        3 * 1024 * 1024 + 123,
        (i) => i.isEven ? random.nextInt(256) : i % 7,
      ),
    );
  }

  String writeZip(Uint8List data, CompressionType compression) {
    final archive = Archive()
      ..add(ArchiveFile.bytes('dir/data.bin', data)..compression = compression);
    final path = p.join(temp.path, 'in.zip');
    File(path).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
    return path;
  }

  for (final compression in CompressionType.values) {
    test('פורס רשומה ${compression.name} בזרימה', () async {
      final data = payload();
      final input = openZipInput(writeZip(data, compression));
      try {
        final entry = ZipDecoder().decodeStream(input).single;
        final dest = p.join(temp.path, 'out', 'data.bin');
        expect(await writeZipEntry(entry, dest), data.length);
        expect(File(dest).readAsBytesSync(), data);
        expect(entry.readBytes(), data);
      } finally {
        input.closeSync();
      }
    });
  }

  test('תוכן גדול מהגודל המוצהר נעצר', () async {
    final input = openZipInput(writeZip(payload(), CompressionType.deflate));
    try {
      final entry = ZipDecoder().decodeStream(input).single;
      (entry.rawContent! as ZipFile).uncompressedSize = 1024 * 1024 + 1;
      await expectLater(
        writeZipEntry(entry, p.join(temp.path, 'out.bin')),
        throwsA(isA<ArchiveException>()),
      );
      expect(File(p.join(temp.path, 'out.bin')).existsSync(), isFalse);
    } finally {
      input.closeSync();
    }
  });

  test(
    'כשל פתיחה אינו מוחק יעד קיים',
    () async {
      final input = openZipInput(
        writeZip(Uint8List(10), CompressionType.deflate),
      );
      final dest = File(p.join(temp.path, 'readonly.bin'))
        ..writeAsStringSync('keep');
      posix.chmod(dest.path, '444');
      try {
        await expectLater(
          writeZipEntry(ZipDecoder().decodeStream(input).single, dest.path),
          throwsA(isA<FileSystemException>()),
        );
        expect(dest.readAsStringSync(), 'keep');
      } finally {
        posix.chmod(dest.path, '644');
        input.closeSync();
      }
    },
    skip: Platform.isWindows || posix.getuid() == 0
        ? 'דורש משתמש POSIX שאינו root'
        : false,
  );
}
