import 'dart:io';
import 'dart:typed_data';

import 'package:otzaria/app_report/models/crash_signature.dart';

/// חתימת קריסה נייטיבית מ-minidump: קוד החריגה והמודול+היסט של כתובתה.
/// קורא רק את הכותרת, זרם החריגה ורשימת המודולים — לא את זיכרון התהליך.
Future<CrashSignature?> readMinidumpSignature(File file) async {
  RandomAccessFile? raf;
  try {
    raf = await file.open();
    final reader = _Reader(raf, await raf.length());

    final header = await reader.read(0, 32);
    if (header.getUint32(0, Endian.little) != _mdmpSignature) return null;
    final streamCount = header.getUint32(8, Endian.little);
    if (streamCount == 0 || streamCount > _maxStreams) return null;
    final directory = await reader.read(
      header.getUint32(12, Endian.little),
      streamCount * 12,
    );

    int? exceptionRva;
    int? moduleListRva;
    for (var i = 0; i < streamCount; i++) {
      final type = directory.getUint32(i * 12, Endian.little);
      final rva = directory.getUint32(i * 12 + 8, Endian.little);
      if (type == _exceptionStream) exceptionRva ??= rva;
      if (type == _moduleListStream) moduleListRva ??= rva;
    }
    if (exceptionRva == null) return null;

    // MINIDUMP_EXCEPTION_STREAM: ThreadId, יישור, ואז ExceptionCode/Flags/Record/Address.
    final exception = await reader.read(exceptionRva, 32);
    final code = exception.getUint32(8, Endian.little);
    final address = exception.getUint64(24, Endian.little);
    final codeText = '0x${code.toRadixString(16).padLeft(8, '0')}';

    String? frame;
    try {
      if (moduleListRva != null) {
        frame = await _moduleOffset(reader, moduleListRva, address);
      }
    } catch (_) {
      // רשימת מודולים פגומה לא מבטלת את קוד החריגה שכבר נקרא.
    }
    final type = frame == null ? codeText : '$codeText $frame';
    return CrashSignature(
      exceptionType: type.length <= CrashSignature.maxExceptionTypeLength
          ? type
          : type.substring(0, CrashSignature.maxExceptionTypeLength),
      frames: [?frame],
    );
  } catch (_) {
    return null;
  } finally {
    await raf?.close();
  }
}

const int _mdmpSignature = 0x504d444d; // 'MDMP'
const int _moduleListStream = 4;
const int _exceptionStream = 6;
const int _moduleEntrySize = 108;
const int _maxStreams = 1000;
const int _maxModules = 10000;
const int _maxNameBytes = 2048;

/// `module.dll+0x1e220` למודול שמכיל את [address]; רק שם הקובץ, בלי הנתיב.
Future<String?> _moduleOffset(_Reader reader, int listRva, int address) async {
  final count = (await reader.read(listRva, 4)).getUint32(0, Endian.little);
  if (count > _maxModules) return null;
  final modules = await reader.read(listRva + 4, count * _moduleEntrySize);
  for (var i = 0; i < count; i++) {
    final at = i * _moduleEntrySize;
    final base = modules.getUint64(at, Endian.little);
    final size = modules.getUint32(at + 8, Endian.little);
    if (address < base || address >= base + size) continue;
    final nameRva = modules.getUint32(at + 20, Endian.little);
    final length = (await reader.read(nameRva, 4)).getUint32(0, Endian.little);
    if (length == 0 || length > _maxNameBytes || length.isOdd) return null;
    final name = await reader.read(nameRva + 4, length);
    final path = String.fromCharCodes([
      for (var j = 0; j < length; j += 2) name.getUint16(j, Endian.little),
    ]);
    final basename = path.split(RegExp(r'[\\/]')).last;
    return '$basename+0x${(address - base).toRadixString(16)}';
  }
  return null;
}

class _Reader {
  _Reader(this._raf, this._length);

  final RandomAccessFile _raf;
  final int _length;

  /// קריאה בגבולות הקובץ; חריגה מהגבול זורקת וההפעלה מחזירה null.
  Future<ByteData> read(int offset, int count) async {
    if (offset < 0 || count < 0 || offset + count > _length) {
      throw const FormatException('minidump truncated');
    }
    await _raf.setPosition(offset);
    final bytes = await _raf.read(count);
    if (bytes.length != count) throw const FormatException('short read');
    return ByteData.sublistView(bytes);
  }
}
