import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

const int _chunkSize = FileBuffer.kDefaultBufferSize;

/// פותח ZIP לקריאה בזרימה, עבור isolate ברקע.
///
/// `readIntoSync` מחזיק חוצץ Dart בזמן גישה לדיסק ומעכב GC; `readSync` לא.
InputFileStream openZipInput(String path) =>
    InputFileStream.withFileBuffer(FileBuffer(_ReadSyncFileHandle(path)));

/// פורס את [entry] אל [dest]; none ו-deflate נכתבים אסינכרונית בזיכרון מוגבל.
///
/// מחזיר את מספר הבתים שנכתבו. זורק [ArchiveException] כשהתוכן גדול מהגודל
/// המוצהר. שאר השיטות משתמשות בפלט הסינכרוני המוגבל של archive.
Future<int> writeZipEntry(ArchiveFile entry, String dest) async {
  final zip = entry.rawContent;
  if (zip is! ZipFile) {
    throw ArchiveException('${entry.name} is not a zip entry');
  }
  final file = File(dest);
  await file.parent.create(recursive: true);
  // decodeLazy מחזיק בלוק מפוענח שלם; שומרים כאן על הפלט המוגבל של archive.
  final asyncWrites = switch (zip.compressionMethod) {
    CompressionType.none || CompressionType.deflate => true,
    CompressionType.bzip2 ||
    CompressionType.zstd ||
    CompressionType.lzma ||
    CompressionType.xz => false,
  };
  if (!asyncWrites) {
    final output = OutputFileStream(dest);
    final throwOnError = zip.throwOnError;
    final verify = zip.verify;
    try {
      try {
        zip.throwOnError = true;
        // LZMA עוצר בגודל המוצהר; CRC מזהה גם גודל שקרי שחתך את התוכן.
        zip.verify = verify || zip.compressionMethod == CompressionType.lzma;
        zip.decompress(output);
      } finally {
        zip.throwOnError = throwOnError;
        zip.verify = verify;
        await output.close();
      }
    } catch (_) {
      await file.delete();
      rethrow;
    }
    return output.length;
  }
  // subset שומר על מיקום התוכן של הרשומה עבור קריאות חוזרות.
  final stored = zip.getStream(decompress: false).subset();
  final output = await file.open(mode: FileMode.write);
  var written = 0;
  try {
    try {
      for (final chunk in _decodeChunks(stored, zip.compressionMethod)) {
        written += chunk.length;
        if (written > zip.uncompressedSize) {
          throw ArchiveException(
            '${entry.name} is larger than its declared ${zip.uncompressedSize} bytes',
          );
        }
        await output.writeFrom(chunk);
      }
    } finally {
      await output.close();
    }
  } catch (_) {
    // מנקים רק אחרי פתיחה מוצלחת לכתיבה, כדי לא למחוק יעד שלא ניתן לפתוח.
    await file.delete();
    rethrow;
  }
  return written;
}

Iterable<List<int>> _decodeChunks(
  InputStream stored,
  CompressionType compression,
) sync* {
  final filter = compression == CompressionType.deflate
      ? RawZLibFilter.inflateFilter(raw: true)
      : null;
  while (!stored.isEOS) {
    final chunk = stored.readBytes(_chunkSize).toUint8List();
    if (filter == null) {
      yield chunk;
      continue;
    }
    filter.process(chunk, 0, chunk.length);
    // processed מחזיר חוצץ פלט יחיד; ממתינים לכתיבתו לפני הרחבת הפלט הבא.
    for (
      var decoded = filter.processed(flush: false);
      decoded != null;
      decoded = filter.processed(flush: false)
    ) {
      yield decoded;
    }
  }
  if (filter != null) {
    for (
      var decoded = filter.processed(end: true);
      decoded != null;
      decoded = filter.processed(end: true)
    ) {
      yield decoded;
    }
  }
}

class _ReadSyncFileHandle extends AbstractFileHandle {
  _ReadSyncFileHandle(String path) : _file = File(path).openSync() {
    _length = _file!.lengthSync();
  }

  RandomAccessFile? _file;
  int _length = 0;
  int _position = 0;

  @override
  int get position => _position;

  @override
  set position(int p) {
    if (p == _position) return;
    _file!.setPositionSync(p);
    _position = p;
  }

  @override
  int get length => _length;

  @override
  bool get isOpen => _file != null;

  @override
  Future<void> close() async {
    final file = _file;
    _file = null;
    await file?.close();
  }

  @override
  void closeSync() {
    final file = _file;
    _file = null;
    file?.closeSync();
  }

  @override
  int readInto(Uint8List buffer, [int? length]) {
    final bytes = _file!.readSync(length ?? buffer.length);
    buffer.setRange(0, bytes.length, bytes);
    _position += bytes.length;
    return bytes.length;
  }

  @override
  void writeFromSync(List<int> buffer, [int start = 0, int? end]) =>
      throw UnsupportedError('A zip input is read-only');
}
