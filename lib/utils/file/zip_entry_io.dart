import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart' as win32;

const int _chunkSize = FileBuffer.kDefaultBufferSize;

/// פותח ZIP לקריאה בזרימה, עבור isolate ברקע.
///
/// `readIntoSync` מחזיק חוצץ Dart בזמן גישה לדיסק ומעכב GC; `readSync` לא.
InputFileStream openZipInput(String path) =>
    InputFileStream.withFileBuffer(FileBuffer(_ReadSyncFileHandle(path)));

/// פורס את [entry] אל [dest] בזיכרון מוגבל, בלי לעכב את ה-GC של ה-UI.
///
/// מחזיר את מספר הבתים שנכתבו. זורק [ArchiveException] כשהתוכן גדול מהגודל
/// המוצהר. none ו-deflate נכתבים אסינכרונית; שאר השיטות דרך [_NativeWriteHandle].
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
    final output = OutputFileStream.withFileHandle(
      _NativeWriteHandle(dest),
      bufferSize: _chunkSize,
    );
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

/// קובץ לכתיבה בלבד שכותב דרך FFI שאינו leaf: בזמן הגישה לדיסק ה-thread
/// במצב native וה-GC אינו ממתין לו, בניגוד ל-`writeFromSync` שמחזיק חוצץ Dart.
class _NativeWriteHandle extends AbstractFileHandle {
  // החוצץ מוקצה רק אחרי פתיחה מוצלחת, כדי שכשל פתיחה לא ידליף אותו.
  _NativeWriteHandle(String path)
    : _file = _NativeFile.create(path),
      _buffer = malloc<Uint8>(_chunkSize);

  _NativeFile? _file;
  final Pointer<Uint8> _buffer;
  int _length = 0;

  @override
  int get position => _length;

  @override
  set position(int p) => throw UnsupportedError('A zip output is append-only');

  @override
  int get length => _length;

  @override
  bool get isOpen => _file != null;

  @override
  Future<void> close() async => closeSync();

  @override
  void closeSync() {
    final file = _file;
    if (file == null) return;
    _file = null;
    try {
      file.close();
    } finally {
      malloc.free(_buffer);
    }
  }

  @override
  int readInto(Uint8List buffer, [int? length]) =>
      throw UnsupportedError('A zip output is write-only');

  @override
  void writeFromSync(List<int> buffer, [int start = 0, int? end]) {
    end = RangeError.checkValidRange(start, end, buffer.length);
    final file = _file!;
    final view = _buffer.asTypedList(_chunkSize);
    for (var at = start; at < end; at += _chunkSize) {
      final count = min(_chunkSize, end - at);
      view.setRange(0, count, buffer, at);
      file.write(_buffer, count);
      _length += count;
    }
  }
}

sealed class _NativeFile {
  factory _NativeFile.create(String path) =>
      Platform.isWindows ? _WindowsFile(path) : _PosixFile(path);

  void write(Pointer<Uint8> data, int length);
  void close();
}

final class _WindowsFile implements _NativeFile {
  _WindowsFile(this._path) {
    final name = _windowsPath(_path).toNativeUtf16();
    try {
      final opened = win32.CreateFile(
        win32.PCWSTR(name),
        win32.GENERIC_WRITE,
        win32.FILE_SHARE_READ |
            win32.FILE_SHARE_WRITE |
            win32.FILE_SHARE_DELETE,
        null,
        win32.CREATE_ALWAYS,
        win32.FILE_ATTRIBUTE_NORMAL,
        null,
      );
      if (opened.value == win32.INVALID_HANDLE_VALUE) {
        throw FileSystemException(
          'CreateFileW',
          _path,
          OSError('', opened.error),
        );
      }
      _handle = opened.value;
    } finally {
      malloc.free(name);
    }
  }

  final String _path;
  late final win32.HANDLE _handle;

  @override
  void write(Pointer<Uint8> data, int length) {
    final written = malloc<Uint32>();
    try {
      final result = win32.WriteFile(_handle, data, length, written, null);
      if (!result.value) {
        throw FileSystemException(
          'WriteFile',
          _path,
          OSError('', result.error),
        );
      }
      // כתיבה סינכרונית לקובץ רגיל משלימה את כל הבקשה או נכשלת.
      if (written.value != length) {
        throw FileSystemException('Incomplete write', _path);
      }
    } finally {
      malloc.free(written);
    }
  }

  @override
  void close() => win32.CloseHandle(_handle);

  // כמו dart:io: קידומת רק לנתיב ארוך, אחרת היא מבטלת את נרמול Win32
  // (רווח או נקודה בסוף השם) ונוצר קובץ ש-dart:io לא ימצא.
  static String _windowsPath(String path) {
    if (path.startsWith(r'\\?\') || path.startsWith(r'\\.\')) return path;
    final absolute = p.normalize(p.absolute(path));
    if (absolute.length < win32.MAX_PATH) return absolute;
    return absolute.startsWith(r'\\')
        ? r'\\?\UNC\' + absolute.substring(2)
        : r'\\?\' + absolute;
  }
}

final class _PosixFile implements _NativeFile {
  _PosixFile(this._path) {
    using((arena) {
      _stream = _fopen(
        _path.toNativeUtf8(allocator: arena),
        'wb'.toNativeUtf8(allocator: arena),
      );
    });
    if (_stream == nullptr) throw FileSystemException('fopen', _path);
  }

  final String _path;
  late final Pointer<Void> _stream;

  @override
  void write(Pointer<Uint8> data, int length) {
    if (_fwrite(data, 1, length, _stream) != length) {
      throw FileSystemException('fwrite', _path);
    }
  }

  @override
  void close() {
    if (_fclose(_stream) != 0) throw FileSystemException('fclose', _path);
  }
}

final _libc = DynamicLibrary.process();
final _fopen = _libc
    .lookupFunction<
      Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>)
    >('fopen');
final _fwrite = _libc
    .lookupFunction<
      Size Function(Pointer<Uint8>, Size, Size, Pointer<Void>),
      int Function(Pointer<Uint8>, int, int, Pointer<Void>)
    >('fwrite');
final _fclose = _libc
    .lookupFunction<Int Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'fclose',
    );
