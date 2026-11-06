import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:otzaria/utils/file/zstd_library.dart';
import 'package:zstandard_native/zstandard_native_bindings.dart';

/// מפענח zstd בזרימה שמוזן בנתחים מכל מקור (חלקים, ערוץ SAF) ומוסר את
/// הפלט לצרכן, בלי קובץ ביניים.
class ZstdStreamDecoder {
  ZstdStreamDecoder(DynamicLibrary lib, {this.requireContentChecksum = false})
    : _zstd = ZstandardNativeBindings(lib) {
    _inSize = zstdInputChunkBytes;
    _outSize = zstdOutputChunkBytes;
    _stream = _zstd.ZSTD_createDStream();
    if (_stream == nullptr) throw StateError('ZSTD_createDStream נכשל');
    try {
      _inNative = malloc.allocate<Uint8>(_inSize);
      _outNative = malloc.allocate<Uint8>(_outSize);
      _inBuf = malloc<ZSTD_inBuffer_s>();
      _outBuf = malloc<ZSTD_outBuffer_s>();
      _check(_zstd.ZSTD_initDStream(_stream), 'ZSTD_initDStream');
      _check(
        _zstd.ZSTD_DCtx_setParameter(
          _stream,
          ZSTD_dParameter.ZSTD_d_windowLogMax,
          zstdWindowLogMax(),
        ),
        'ZSTD_DCtx_setParameter',
      );
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  final ZstandardNativeBindings _zstd;
  final bool requireContentChecksum;
  final _frameHead = <int>[];
  late final int _inSize;
  late final int _outSize;
  late final Pointer<ZSTD_DCtx> _stream;
  Pointer<Uint8> _inNative = nullptr;
  Pointer<Uint8> _outNative = nullptr;
  Pointer<ZSTD_inBuffer_s> _inBuf = nullptr;
  Pointer<ZSTD_outBuffer_s> _outBuf = nullptr;
  int _lastRet = 0;
  int _inputBytesConsumed = 0;

  /// בייטים שהמפענח כבר צרך מכל הקריאות, גם בתוך נתח קלט דחוס יחיד.
  int get inputBytesConsumed => _inputBytesConsumed;
  bool _fedAny = false;
  bool _disposed = false;

  void _check(int code, String what) {
    if (_zstd.ZSTD_isError(code) != 0) {
      final name = _zstd.ZSTD_getErrorName(code).cast<Utf8>().toDartString();
      final errorCode = _zstd.ZSTD_getErrorCode(code);
      if (what != 'פענוח zstd' ||
          errorCode == ZSTD_ErrorCode.ZSTD_error_memory_allocation ||
          errorCode ==
              ZSTD_ErrorCode.ZSTD_error_frameParameter_windowTooLarge) {
        throw StateError('$what נכשל: $name');
      }
      throw FormatException('$what נכשל: $name');
    }
  }

  /// מפענח את [input]. [onOutput] מקבל תצוגה על זיכרון נייטיב שתקפה רק
  /// עד שה-Future שלו מסתיים — הצרכן חייב לכתוב/להעתיק אותה עד אז.
  Future<void> add(
    List<int> input,
    Future<void> Function(Uint8List output) onOutput,
  ) async {
    var offset = 0;
    final inView = _inNative.asTypedList(_inSize);
    while (offset < input.length) {
      final take = (input.length - offset).clamp(0, _inSize);
      inView.setRange(0, take, input, offset);
      offset += take;
      _fedAny = true;
      _inBuf.ref
        ..src = _inNative.cast()
        ..size = take
        ..pos = 0;
      while (_inBuf.ref.pos < _inBuf.ref.size) {
        if (requireContentChecksum && _frameHead.length < 5) {
          final start = _inBuf.ref.pos;
          final end = (start + 5 - _frameHead.length).clamp(start, take);
          _frameHead.addAll(Uint8List.sublistView(inView, start, end));
          if (_frameHead.length == 5 && !frameHasContentChecksum(_frameHead)) {
            throw const FormatException(
              'לא ניתן לאמת את הארכיון: חסר checksum בתוכן frame של zstd; '
              'נדרש קובץ המניפסט שלו',
            );
          }
        }
        _outBuf.ref
          ..dst = _outNative.cast()
          ..size = _outSize
          ..pos = 0;
        final before = _inBuf.ref.pos;
        _lastRet = _zstd.ZSTD_decompressStream(_stream, _outBuf, _inBuf);
        _check(_lastRet, 'פענוח zstd');
        _inputBytesConsumed += _inBuf.ref.pos - before;
        // libzstd עוצר בסוף כל frame, גם כשבאותו נתח מתחיל ה-frame הבא.
        if (_lastRet == 0) _frameHead.clear();
        if (_outBuf.ref.pos > 0) {
          await onOutput(_outNative.asTypedList(_outBuf.ref.pos));
        }
      }
    }
  }

  /// מוודא שהקלט הסתיים בסוף frame שלם — אחרת הארכיון קטוע.
  void close() {
    if (!_fedAny || _lastRet != 0) {
      throw const FormatException('הארכיון קטוע — ייתכן שחסר חלק בסופו');
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _zstd.ZSTD_freeDStream(_stream);
    malloc
      ..free(_inNative)
      ..free(_outNative)
      ..free(_inBuf)
      ..free(_outBuf);
  }

  /// האם הקלט מתחיל ב-frame של zstd שנושא checksum של התוכן. בלי מניפסט
  /// זה האימות היחיד ששינוי בתוכן ייתפס.
  static bool frameHasContentChecksum(List<int> head) {
    if (head.length < 5) return false;
    final isMagic =
        head[0] == 0x28 &&
        head[1] == 0xB5 &&
        head[2] == 0x2F &&
        head[3] == 0xFD;
    return isMagic && (head[4] & 0x04) != 0;
  }
}
