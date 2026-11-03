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

  // Python stdlib: ZIP_LZMA; XZ uses lzma.compress(FORMAT_XZ), ZIP method 95.
  String compressedFixture(CompressionType compression) =>
      'test/fixtures/zip/${compression.name}_16mb_zeros.zip';

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

  String writeZip(
    Uint8List data,
    CompressionType compression, {
    int? level,
  }) {
    final archive = Archive()
      ..add(
        ArchiveFile.bytes('dir/data.bin', data)
          ..compression = compression
          ..compressionLevel = level,
      );
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

    test('פורס פלט דחיס מאוד בשיטת ${compression.name}', () async {
      final data = Uint8List(16 * 1024 * 1024);
      // XZEncoder stores uncompressed chunks; this fixture uses real LZMA2.
      final input = openZipInput(
        compression == CompressionType.xz
            ? compressedFixture(compression)
            : writeZip(data, compression, level: 9),
      );
      try {
        final entry = ZipDecoder().decodeStream(input).single;
        if (compression != CompressionType.none) {
          expect(
            (entry.rawContent! as ZipFile).compressedSize,
            lessThan(64 * 1024),
          );
        }
        final dest = p.join(temp.path, 'out.bin');
        expect(await writeZipEntry(entry, dest), data.length);
        final output = File(dest).openSync();
        try {
          var length = 0;
          while (length < data.length) {
            final chunk = output.readSync(64 * 1024);
            expect(chunk, isNotEmpty);
            expect(chunk.every((byte) => byte == 0), isTrue);
            length += chunk.length;
          }
          expect(output.readSync(1), isEmpty);
        } finally {
          output.closeSync();
        }
      } finally {
        input.closeSync();
      }
    });

    for (final declaredSize in [0, 1, 1024 * 1024 + 1]) {
      test(
        '${compression.name}: גודל מוצהר $declaredSize מסיר פלט חלקי',
        () async {
          final input = openZipInput(
            writeZip(Uint8List(16 * 1024 * 1024), compression),
          );
          try {
            final entry = ZipDecoder().decodeStream(input).single;
            (entry.rawContent! as ZipFile).uncompressedSize = declaredSize;
            final dest = p.join(temp.path, 'out.bin');
            await expectLater(
              writeZipEntry(entry, dest),
              throwsA(isA<ArchiveException>()),
            );
            expect(File(dest).existsSync(), isFalse);
          } finally {
            input.closeSync();
          }
        },
      );
    }

    test('${compression.name}: רשומה ריקה', () async {
      final input = openZipInput(writeZip(Uint8List(0), compression));
      try {
        final dest = p.join(temp.path, 'empty.bin');
        expect(
          await writeZipEntry(ZipDecoder().decodeStream(input).single, dest),
          0,
        );
        expect(File(dest).lengthSync(), 0);
      } finally {
        input.closeSync();
      }
    });

    if (compression != CompressionType.none) {
      test('${compression.name}: פלט פגום נמחק', () async {
        final path = writeZip(Uint8List(1024), compression);
        final bytes = File(path).readAsBytesSync();
        final header = ByteData.sublistView(bytes);
        final start =
            30 +
            header.getUint16(26, Endian.little) +
            header.getUint16(28, Endian.little);
        bytes.fillRange(start, start + 4, 0);
        File(path).writeAsBytesSync(bytes);
        final input = openZipInput(path);
        try {
          final dest = p.join(temp.path, 'out.bin');
          await expectLater(
            writeZipEntry(ZipDecoder().decodeStream(input).single, dest),
            throwsA(isA<FormatException>()),
          );
          expect(File(dest).existsSync(), isFalse);
        } finally {
          input.closeSync();
        }
      });
    }
  }

  for (final compression in [CompressionType.lzma, CompressionType.xz]) {
    test('${compression.name}: תוכן משתנה נשמר עם אימות פעיל וכבוי', () async {
      final input = openZipInput(
        'test/fixtures/zip/${compression.name}_3mb_pattern.zip',
      );
      try {
        final entry = ZipDecoder().decodeStream(input).single;
        final zip = entry.rawContent! as ZipFile;
        expect(zip.compressionMethod, compression);
        final expected = Uint8List.fromList(
          List.generate(3 * 1024 * 1024 + 123, (i) => i % 251),
        );
        final dest = p.join(temp.path, 'out.bin');
        for (final verify in [false, true]) {
          zip.verify = verify;
          zip.throwOnError = verify;
          expect(await writeZipEntry(entry, dest), expected.length);
          expect(File(dest).readAsBytesSync(), expected);
          expect(zip.verify, verify);
          expect(zip.throwOnError, verify);
        }
      } finally {
        input.closeSync();
      }
    });

    test(
      '${compression.name}: רשומה דחוסה אמיתית ניתנת לקריאה חוזרת',
      () async {
        final input = openZipInput(compressedFixture(compression));
        try {
          final entry = ZipDecoder().decodeStream(input).single;
          final zip = entry.rawContent! as ZipFile;
          expect(zip.compressionMethod, compression);
          expect(zip.compressedSize, lessThan(64 * 1024));
          final dest = p.join(temp.path, 'out.bin');
          for (var i = 0; i < 2; i++) {
            expect(await writeZipEntry(entry, dest), 16 * 1024 * 1024);
            expect(File(dest).readAsBytesSync(), Uint8List(16 * 1024 * 1024));
            expect(zip.throwOnError, isFalse);
            expect(zip.verify, isFalse);
          }
          expect(entry.readBytes(), Uint8List(16 * 1024 * 1024));
        } finally {
          input.closeSync();
        }
      },
    );

    for (final declaredSize in [0, 1, 1024 * 1024 + 1, 32 * 1024 * 1024]) {
      test(
        '${compression.name}: גודל שקרי ברשומה אמיתית ($declaredSize)',
        () async {
          final input = openZipInput(compressedFixture(compression));
          try {
            final entry = ZipDecoder().decodeStream(input).single;
            final zip = entry.rawContent! as ZipFile;
            zip.uncompressedSize = declaredSize;
            final dest = p.join(temp.path, 'out.bin');
            await expectLater(
              writeZipEntry(entry, dest),
              throwsFormatException,
            );
            expect(File(dest).existsSync(), isFalse);
            expect(zip.throwOnError, isFalse);
            expect(zip.verify, isFalse);
          } finally {
            input.closeSync();
          }
        },
      );
    }
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

  for (final compression in [CompressionType.lzma, CompressionType.xz]) {
    test(
      '${compression.name}: פענוח רשומה אמיתית פגומה מנקה את היעד',
      () async {
        final bytes = File(compressedFixture(compression)).readAsBytesSync();
        final header = ByteData.sublistView(bytes);
        final start =
            30 +
            header.getUint16(26, Endian.little) +
            header.getUint16(28, Endian.little);
        bytes.fillRange(start, start + 4, 0);
        final path = p.join(temp.path, 'corrupt.zip');
        File(path).writeAsBytesSync(bytes);
        final input = openZipInput(path);
        try {
          final entry = ZipDecoder().decodeStream(input).single;
          final zip = entry.rawContent! as ZipFile;
          final dest = p.join(temp.path, 'out.bin');
          await expectLater(writeZipEntry(entry, dest), throwsFormatException);
          expect(File(dest).existsSync(), isFalse);
          expect(zip.throwOnError, isFalse);
          expect(zip.verify, isFalse);
        } finally {
          input.closeSync();
        }
      },
    );
  }

  for (final compression in CompressionType.values) {
    test(
      '${compression.name}: כשל פתיחה אינו מוחק יעד קיים',
      () async {
        final input = openZipInput(
          writeZip(Uint8List(10), compression),
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
}
