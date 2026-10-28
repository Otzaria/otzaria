import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

const int _chunkSize = 1024 * 1024;

/// פותח ZIP לקריאה בזרימה, עבור isolate ברקע.
///
/// `readIntoSync`, שבו משתמש [InputFileStream] הרגיל, עוצר את ה-GC של כל
/// ה-isolates עד שהקריאה מהדיסק מסתיימת; `readSync` לא (#3418).
InputFileStream openZipInput(String path) =>
    InputFileStream.withFileBuffer(FileBuffer(_ReadSyncFileHandle(path)));

/// פורס את [entry] אל [dest] בנתחים של 1MB, בכתיבה אסינכרונית.
///
/// מחזיר את מספר הבתים שנכתבו. זורק [ArchiveException] כשהתוכן גדול מהגודל
/// המוצהר, כמו `writeContent` של package:archive.
Future<int> writeZipEntry(ArchiveFile entry, String dest) async {
  final zip = entry.rawContent;
  if (zip is! ZipFile) {
    throw ArchiveException('${entry.name} is not a zip entry');
  }
  // subset: מיקום משלו, כדי שלא לקדם את התוכן השמור של הרשומה עצמה.
  final stored = zip.getStream(decompress: false).subset();
  final content = switch (zip.compressionMethod) {
    CompressionType.none => stored,
    CompressionType.deflate => ZLibDecoder().decodeLazy(stored, raw: true),
    CompressionType.bzip2 => BZip2Decoder().decodeLazy(stored),
    CompressionType.zstd => ZstdDecoder().decodeLazy(stored),
  };
  final file = File(dest);
  await file.parent.create(recursive: true);
  final output = await file.open(mode: FileMode.write);
  var written = 0;
  try {
    try {
      // isEOS ולא נתח ריק: קריאה מעבר לסוף זורקת RangeError ב-InputDecodeStream.
      while (!content.isEOS) {
        final chunk = content.readBytes(_chunkSize).toUint8List();
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
