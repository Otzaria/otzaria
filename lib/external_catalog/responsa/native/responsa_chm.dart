import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// קריאת CHM דרך `itss.dll` (COM) ולא מפענח LZX משלנו: קיים בכל Windows,
/// ושגיאה במפענח עצמאי שקטה. כל כשל מחזיר מפה ריקה - קובץ עזרה חסר הוא רגיל.
class ResponsaChm {
  ResponsaChm._();

  /// `CLSID_ITStorage` ו-`IID_IITStorage` — קבועים מתועדים של HTML Help.
  static const String _clsidITStorage =
      '{5d02926a-212e-11d0-9df9-00a0c922e6ec}';
  static const String _iidITStorage = '{88cc31de-27ab-11d0-9df9-00a0c922e6ec}';

  static const int _stgmRead = 0x00000000;
  static const int _stgmShareDenyWrite = 0x00000020;

  /// גודל `STATSTG` בתהליך 64-ביט.
  static const int _statStgSize = 80;

  /// סוג רשומה ב-`STATSTG.type`.
  static const int _typeStorage = 1;
  static const int _typeStream = 2;

  /// עמוד ביבליוגרפיה הוא כמה קילובייטים; התקרה מגנה מקובץ עזרה חריג.
  static const int _maxEntryBytes = 4 * 1024 * 1024;

  /// תקרת זיכרון לקריאה כולה.
  static const int _maxTotalBytes = 64 * 1024 * 1024;

  /// עומק מרבי של תיקיות בתוך ה-CHM.
  static const int _maxDepth = 8;

  /// נתיב פנימי (מפריד `/`) לתוכן גולמי - הפענוח לטקסט שייך לקורא, כי CHM
  /// אינו מצהיר קידוד.
  static Map<String, Uint8List> read(String chmPath) {
    try {
      return _read(chmPath);
    } catch (error) {
      debugPrint('ResponsaChm: reading $chmPath failed: $error');
      return const {};
    }
  }

  static Map<String, Uint8List> _read(String chmPath) {
    // `RPC_E_CHANGED_MODE` (COM כבר אותחל במודל אחר) אינו כשל, אבל אז אסור
    // לשחרר - האתחול שייך למי שעשה אותו.
    final initialized = _coInitializeEx(nullptr, _coinitApartmentThreaded);
    final owns = initialized == _sOk || initialized == _sFalse;

    // כל ידית COM נרשמת כאן ומשוחררת בסוף בסדר הפוך, כך שגם יציאה מוקדמת
    // לא משאירה ידיות פתוחות.
    final handles = <Pointer>[];
    final buffers = <Pointer>[];
    try {
      final clsid = _guid(_clsidITStorage);
      buffers.add(clsid);
      final iid = _guid(_iidITStorage);
      buffers.add(iid);
      final instance = calloc<Pointer>();
      buffers.add(instance);

      final created = _coCreateInstance(
        clsid,
        nullptr,
        _clsctxInprocServer,
        iid,
        instance,
      );
      if (created != _sOk) {
        debugPrint('ResponsaChm: ITStorage unavailable (0x${_hex(created)})');
        return const {};
      }
      handles.add(instance.value);

      final root = _openChm(instance.value, chmPath);
      if (root == nullptr) return const {};
      handles.add(root);

      final found = <String, Uint8List>{};
      _collect(root, '', found, 0, _Budget());
      return found;
    } finally {
      for (final handle in handles.reversed) {
        _release(handle);
      }
      for (final buffer in buffers) {
        calloc.free(buffer);
      }
      if (owns) _coUninitialize();
    }
  }

  static Pointer _openChm(Pointer itStorage, String chmPath) {
    final name = chmPath.toNativeUtf16();
    final out = calloc<Pointer>();
    try {
      final hr =
          _vtable<_StgOpenStorageNative>(
            itStorage,
            _slotStgOpenStorage,
          ).asFunction<_StgOpenStorageDart>()(
            itStorage,
            name,
            nullptr,
            _stgmRead | _stgmShareDenyWrite,
            nullptr,
            0,
            out,
          );
      if (hr != _sOk) {
        debugPrint('ResponsaChm: cannot open $chmPath (0x${_hex(hr)})');
        return nullptr;
      }
      return out.value;
    } finally {
      calloc.free(name);
      calloc.free(out);
    }
  }

  /// חסמי עומק וזיכרון: אין ערובה למבנה הקובץ במהדורה אחרת (ב-CD25 כ-2MB
  /// בשני מפלסים).
  static void _collect(
    Pointer storage,
    String prefix,
    Map<String, Uint8List> into,
    int depth,
    _Budget budget,
  ) {
    if (depth > _maxDepth || budget.exhausted) return;
    for (final entry in _entries(storage)) {
      if (budget.exhausted) return;
      final path = prefix.isEmpty ? entry.name : '$prefix/${entry.name}';
      if (entry.type == _typeStorage) {
        final child = _openStorage(storage, entry.name);
        if (child == nullptr) continue;
        try {
          _collect(child, path, into, depth + 1, budget);
        } finally {
          _release(child);
        }
        continue;
      }
      if (entry.type != _typeStream) continue;
      if (entry.size <= 0 || entry.size > _maxEntryBytes) continue;
      final bytes = _readStream(storage, entry.name, entry.size);
      if (bytes == null) continue;
      into[path] = bytes;
      budget.spend(bytes.length);
    }
  }

  static List<({String name, int type, int size})> _entries(Pointer storage) {
    final out = calloc<Pointer>();
    try {
      final hr = _vtable<_EnumElementsNative>(
        storage,
        _slotEnumElements,
      ).asFunction<_EnumElementsDart>()(storage, 0, nullptr, 0, out);
      if (hr != _sOk) return const [];
      final enumerator = out.value;
      final next = _vtable<_NextNative>(
        enumerator,
        _slotNext,
      ).asFunction<_NextDart>();
      final stat = calloc<Uint8>(_statStgSize);
      final fetched = calloc<Uint32>();
      final found = <({String name, int type, int size})>[];
      try {
        while (next(enumerator, 1, stat, fetched) == _sOk &&
            fetched.value == 1) {
          final namePointer = stat.cast<Pointer<Utf16>>().value;
          if (namePointer == nullptr) continue;
          final data = ByteData.sublistView(stat.asTypedList(_statStgSize));
          found.add((
            name: namePointer.toDartString(),
            type: data.getUint32(8, Endian.little),
            size: data.getUint64(16, Endian.little),
          ));
          // השם הוקצה על ידי COM, ובלי שחרור כל קריאה מדליפה את כל השמות.
          _coTaskMemFree(namePointer.cast());
        }
      } finally {
        calloc.free(stat);
        calloc.free(fetched);
        _release(enumerator);
      }
      return found;
    } finally {
      calloc.free(out);
    }
  }

  static Pointer _openStorage(Pointer parent, String name) {
    final text = name.toNativeUtf16();
    final out = calloc<Pointer>();
    try {
      final hr =
          _vtable<_OpenStorageNative>(
            parent,
            _slotOpenStorage,
          ).asFunction<_OpenStorageDart>()(
            parent,
            text,
            nullptr,
            _stgmRead | _stgmShareDenyWrite,
            nullptr,
            0,
            out,
          );
      return hr == _sOk ? out.value : nullptr;
    } finally {
      calloc.free(text);
      calloc.free(out);
    }
  }

  static Uint8List? _readStream(Pointer parent, String name, int size) {
    final text = name.toNativeUtf16();
    final out = calloc<Pointer>();
    try {
      final hr =
          _vtable<_OpenStreamNative>(
            parent,
            _slotOpenStream,
          ).asFunction<_OpenStreamDart>()(
            parent,
            text,
            nullptr,
            _stgmRead | _stgmShareDenyWrite,
            0,
            out,
          );
      if (hr != _sOk) return null;
      final stream = out.value;
      final buffer = calloc<Uint8>(size);
      final read = calloc<Uint32>();
      try {
        final result = Uint8List(size);
        var filled = 0;
        // `IStream::Read` רשאי להחזיר פחות ממה שביקשנו גם כשהזרם תקין.
        while (filled < size) {
          final status =
              _vtable<_ReadNative>(stream, _slotRead).asFunction<_ReadDart>()(
                stream,
                (buffer + filled).cast(),
                size - filled,
                read,
              );
          if (status != _sOk || read.value == 0) break;
          filled += read.value;
        }
        if (filled == 0) return null;
        result.setRange(0, filled, buffer.asTypedList(filled));
        return filled == size
            ? result
            : Uint8List.sublistView(result, 0, filled);
      } finally {
        calloc.free(buffer);
        calloc.free(read);
        _release(stream);
      }
    } finally {
      calloc.free(text);
      calloc.free(out);
    }
  }

  // ----------------------------------------------------------- COM plumbing

  static const int _sOk = 0;

  /// `S_FALSE` — COM כבר אותחל באותו מודל. גם כאן האיזון מחייב שחרור.
  static const int _sFalse = 1;

  static const int _coinitApartmentThreaded = 2;
  static const int _clsctxInprocServer = 1;

  /// מיקומים ב-vtable. `IUnknown` תופס 0–2 בכל ממשק.
  static const int _slotStgOpenStorage = 7; // IITStorage
  static const int _slotOpenStream = 4; // IStorage
  static const int _slotOpenStorage = 6; // IStorage
  static const int _slotEnumElements = 11; // IStorage
  static const int _slotNext = 3; // IEnumSTATSTG
  static const int _slotRead = 3; // ISequentialStream
  static const int _slotRelease = 2; // IUnknown

  static final DynamicLibrary _ole32 = DynamicLibrary.open('ole32.dll');

  static final _coInitializeEx = _ole32
      .lookupFunction<
        Int32 Function(Pointer, Uint32),
        int Function(Pointer, int)
      >('CoInitializeEx');

  static final _coCreateInstance = _ole32
      .lookupFunction<
        Int32 Function(Pointer, Pointer, Uint32, Pointer, Pointer<Pointer>),
        int Function(Pointer, Pointer, int, Pointer, Pointer<Pointer>)
      >('CoCreateInstance');

  static final _coUninitialize = _ole32
      .lookupFunction<Void Function(), void Function()>('CoUninitialize');

  static final _coTaskMemFree = _ole32
      .lookupFunction<Void Function(Pointer), void Function(Pointer)>(
        'CoTaskMemFree',
      );

  static final _clsidFromString = _ole32
      .lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer),
        int Function(Pointer<Utf16>, Pointer)
      >('CLSIDFromString');

  static Pointer<Uint8> _guid(String value) {
    final out = calloc<Uint8>(16);
    final text = value.toNativeUtf16();
    try {
      final hr = _clsidFromString(text, out);
      if (hr != _sOk) {
        calloc.free(out);
        throw StateError('CLSIDFromString($value) = 0x${_hex(hr)}');
      }
      return out;
    } finally {
      calloc.free(text);
    }
  }

  static Pointer<NativeFunction<T>> _vtable<T extends Function>(
    Pointer object,
    int slot,
  ) => (object.cast<Pointer<Pointer<NativeFunction<T>>>>().value + slot).value;

  static void _release(Pointer object) {
    if (object == nullptr) return;
    _vtable<_ReleaseNative>(object, _slotRelease).asFunction<_ReleaseDart>()(
      object,
    );
  }

  static String _hex(int value) => (value & 0xFFFFFFFF).toRadixString(16);
}

typedef _StgOpenStorageNative =
    Int32 Function(
      Pointer,
      Pointer<Utf16>,
      Pointer,
      Uint32,
      Pointer,
      Uint32,
      Pointer<Pointer>,
    );
typedef _StgOpenStorageDart =
    int Function(
      Pointer,
      Pointer<Utf16>,
      Pointer,
      int,
      Pointer,
      int,
      Pointer<Pointer>,
    );

typedef _OpenStorageNative = _StgOpenStorageNative;
typedef _OpenStorageDart = _StgOpenStorageDart;

typedef _OpenStreamNative =
    Int32 Function(
      Pointer,
      Pointer<Utf16>,
      Pointer,
      Uint32,
      Uint32,
      Pointer<Pointer>,
    );
typedef _OpenStreamDart =
    int Function(Pointer, Pointer<Utf16>, Pointer, int, int, Pointer<Pointer>);

typedef _EnumElementsNative =
    Int32 Function(Pointer, Uint32, Pointer, Uint32, Pointer<Pointer>);
typedef _EnumElementsDart =
    int Function(Pointer, int, Pointer, int, Pointer<Pointer>);

typedef _NextNative = Int32 Function(Pointer, Uint32, Pointer, Pointer<Uint32>);
typedef _NextDart = int Function(Pointer, int, Pointer, Pointer<Uint32>);

typedef _ReadNative =
    Int32 Function(Pointer, Pointer<Uint8>, Uint32, Pointer<Uint32>);
typedef _ReadDart = int Function(Pointer, Pointer<Uint8>, int, Pointer<Uint32>);

typedef _ReleaseNative = Uint32 Function(Pointer);
typedef _ReleaseDart = int Function(Pointer);

/// תקציב הזיכרון של קריאה אחת.
class _Budget {
  int _remaining = ResponsaChm._maxTotalBytes;

  bool get exhausted => _remaining <= 0;

  void spend(int bytes) => _remaining -= bytes;
}
