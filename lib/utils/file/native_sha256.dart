import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// SHA-256 כ-hex קטן דרך BCrypt ב-Windows ו-CommonCrypto ב-macOS.
/// בשאר הפלטפורמות או בכשל טעינה משתמש ב-package:crypto; יש להריץ ב-isolate.
Future<String> sha256OfFileFast(
  String path, {
  @visibleForTesting NativeSha256 Function()? loadNative,
}) async {
  NativeSha256? native;
  try {
    native = (loadNative ?? _platformNative)?.call();
  } on ArgumentError catch (e) {
    debugPrint('native sha256 unavailable, using package:crypto: $e');
  }
  if (native == null) {
    return (await sha256.bind(File(path).openRead()).first).toString();
  }
  return _hashFile(path, native);
}

NativeSha256 Function()? get _platformNative {
  if (Platform.isWindows) return _bcrypt;
  if (Platform.isMacOS) return _commonCrypto;
  return null;
}

NativeSha256 _commonCrypto() {
  final lib = DynamicLibrary.open('/usr/lib/system/libcommonCrypto.dylib');
  final init = lib
      .lookupFunction<
        Int32 Function(Pointer<Uint32>),
        int Function(Pointer<Uint32>)
      >('CC_SHA256_Init');
  final update = lib
      .lookupFunction<
        Int32 Function(Pointer<Uint32>, Pointer<Uint8>, Uint32),
        int Function(Pointer<Uint32>, Pointer<Uint8>, int)
      >('CC_SHA256_Update');
  final finish = lib
      .lookupFunction<
        Int32 Function(Pointer<Uint8>, Pointer<Uint32>),
        int Function(Pointer<Uint8>, Pointer<Uint32>)
      >('CC_SHA256_Final');
  // CommonDigest.h: CC_SHA256_CTX = count[2], hash[8], wbuf[16] of CC_LONG.
  final context = calloc<Uint32>(26);
  void check(int status, String operation) {
    if (status != 1) throw StateError('$operation failed: $status');
  }

  return NativeSha256(
    () => check(init(context), 'CC_SHA256_Init'),
    (data, length) => check(update(context, data, length), 'CC_SHA256_Update'),
    (out) => check(finish(out, context), 'CC_SHA256_Final'),
    () => calloc.free(context),
  );
}

/// init -> update* -> finish (32 בתים ל-out) -> dispose.
class NativeSha256 {
  const NativeSha256(this.init, this.update, this.finish, this.dispose);
  final void Function() init;
  final void Function(Pointer<Uint8> data, int length) update;
  final void Function(Pointer<Uint8> out) finish;
  final void Function() dispose;
}

const _chunkBytes = 8 * 1024 * 1024;

String _hashFile(String path, NativeSha256 hasher) {
  final buffer = calloc<Uint8>(_chunkBytes);
  final out = calloc<Uint8>(32);
  RandomAccessFile? file;
  try {
    file = File(path).openSync();
    hasher.init();
    final view = buffer.asTypedList(_chunkBytes);
    for (var n = file.readIntoSync(view); n > 0; n = file.readIntoSync(view)) {
      hasher.update(buffer, n);
    }
    hasher.finish(out);
    return out
        .asTypedList(32)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  } finally {
    file?.closeSync();
    hasher.dispose();
    calloc.free(buffer);
    calloc.free(out);
  }
}

NativeSha256 _bcrypt() {
  final lib = DynamicLibrary.open('bcrypt.dll');
  final open = lib
      .lookupFunction<
        Int32 Function(
          Pointer<Pointer<Void>>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          Uint32,
        ),
        int Function(
          Pointer<Pointer<Void>>,
          Pointer<Utf16>,
          Pointer<Utf16>,
          int,
        )
      >('BCryptOpenAlgorithmProvider');
  final getProperty = lib
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<Utf16>,
          Pointer<Uint32>,
          Uint32,
          Pointer<Uint32>,
          Uint32,
        ),
        int Function(
          Pointer<Void>,
          Pointer<Utf16>,
          Pointer<Uint32>,
          int,
          Pointer<Uint32>,
          int,
        )
      >('BCryptGetProperty');
  final create = lib
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<Pointer<Void>>,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint8>,
          Uint32,
          Uint32,
        ),
        int Function(
          Pointer<Void>,
          Pointer<Pointer<Void>>,
          Pointer<Uint8>,
          int,
          Pointer<Uint8>,
          int,
          int,
        )
      >('BCryptCreateHash');
  final hashData = lib
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32, Uint32),
        int Function(Pointer<Void>, Pointer<Uint8>, int, int)
      >('BCryptHashData');
  final finish = lib
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32, Uint32),
        int Function(Pointer<Void>, Pointer<Uint8>, int, int)
      >('BCryptFinishHash');
  final destroy = lib
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('BCryptDestroyHash');
  final close = lib
      .lookupFunction<
        Int32 Function(Pointer<Void>, Uint32),
        int Function(Pointer<Void>, int)
      >('BCryptCloseAlgorithmProvider');

  final alg = calloc<Pointer<Void>>();
  final hash = calloc<Pointer<Void>>();
  Pointer<Uint8> object = nullptr;
  void check(int status, String what) {
    if (status != 0) {
      throw StateError('$what failed: 0x${status.toRadixString(16)}');
    }
  }

  return NativeSha256(
    () {
      final name = 'SHA256'.toNativeUtf16();
      final prop = 'ObjectLength'.toNativeUtf16();
      final len = calloc<Uint32>(2); // [0]=ObjectLength, [1]=bytes written
      try {
        check(open(alg, name, nullptr, 0), 'BCryptOpenAlgorithmProvider');
        check(
          getProperty(alg.value, prop, len.cast(), 4, len + 1, 0),
          'BCryptGetProperty',
        );
        object = calloc<Uint8>(len.value);
        check(
          create(alg.value, hash, object, len.value, nullptr, 0, 0),
          'BCryptCreateHash',
        );
      } finally {
        calloc.free(name);
        calloc.free(prop);
        calloc.free(len);
      }
    },
    (data, n) => check(hashData(hash.value, data, n, 0), 'BCryptHashData'),
    (out) => check(finish(hash.value, out, 32, 0), 'BCryptFinishHash'),
    () {
      if (hash.value != nullptr) destroy(hash.value);
      if (alg.value != nullptr) close(alg.value, 0);
      calloc.free(object);
      calloc.free(alg);
      calloc.free(hash);
    },
  );
}
