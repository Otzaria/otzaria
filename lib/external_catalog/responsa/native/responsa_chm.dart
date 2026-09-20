import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// קריאת קובץ CHM — קובץ העזרה של Windows — דרך `itss.dll`.
///
/// **למה COM ולא מפענח משלנו.** תוכן CHM דחוס ב-LZX. מימוש עצמאי שלו הוא
/// כ-700 שורות של פענוח האפמן שאי אפשר לבדוק בלי קובץ אמיתי, ושגיאה בו
/// שקטה. ל-Windows יש כבר את המימוש הזה: `itss.dll` חושף את ה-CHM כ-
/// `IStorage` סטנדרטי. הוא קיים בכל גרסת Windows שאוצריא רצה עליה, ואינו
/// דורש התקנה, הרשאה או הגדרה.
///
/// **למה זה נדרש.** ב-`HELP/Respheb.chm` שבהתקנה של פרויקט השו"ת יושבת
/// "רשימת הספרים והמהדורות" — עמוד לכל חיבור, ובו שם המחבר (בשו"ת) ומקום
/// ושנת ההדפסה של המהדורה שהמאגר מבוסס עליה. זו המטא-דאטה היחידה שקיימת
/// בהתקנה בצורה קריאה: `FILE07`, שהוא מסד המטא-דאטה של התוכנה, ריק
/// (27 בייטים לא-אפס מתוך 1.47MB), והארכיון הראשי דחוס בפורמט פרטי.
///
/// כל כשל כאן מחזיר מפה ריקה ולא חריג: קובץ עזרה חסר, פגום או בגרסה
/// שמבנה התיקיות שלה שונה הוא מצב רגיל לחלוטין — הספרים עדיין ייבנו,
/// פשוט בלי מחבר ובלי מהדורה.
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

  /// תקרת גודל לקובץ בודד בתוך ה-CHM. עמוד ביבליוגרפיה הוא כמה קילובייטים;
  /// התקרה מגנה מפני קובץ עזרה חריג שיבלע זיכרון.
  static const int _maxEntryBytes = 4 * 1024 * 1024;

  /// תקרת זיכרון לקריאה כולה.
  @visibleForTesting
  static const int maxTotalBytesForBudget = 64 * 1024 * 1024;

  /// עומק מרבי של תיקיות בתוך ה-CHM.
  static const int _maxDepth = 8;

  /// קורא את כל ה-**קבצים** שתחת [folder] בתוך [chmPath], רקורסיבית.
  ///
  /// המפתח במפה הוא הנתיב היחסי ל-[folder], עם `/` כמפריד. הערך הוא
  /// התוכן הגולמי — הפענוח לטקסט שייך לקורא, כי CHM אינו מצהיר קידוד.
  static Map<String, Uint8List> read(
    String chmPath, {
    required List<String> folder,
  }) {
    try {
      return _read(chmPath, folder);
    } catch (error) {
      debugPrint('ResponsaChm: reading $chmPath failed: $error');
      return const {};
    }
  }

  static Map<String, Uint8List> _read(String chmPath, List<String> folder) {
    // `CoInitializeEx` מחזיר `RPC_E_CHANGED_MODE` כשהאיזולט כבר אתחל COM
    // במודל אחר. זה אינו כשל: אפשר להמשיך ולהשתמש ב-COM כרגיל, ורק אסור
    // לשחרר — האתחול שייך למי שעשה אותו.
    final initialized = _coInitializeEx(nullptr, _coinitApartmentThreaded);
    final owns = initialized == _sOk || initialized == _sFalse;

    // כל ידית ש-COM מחזיר נרשמת כאן ומשוחררת בסוף, בסדר הפוך. ניהול
    // ידני עם `try/finally` מקונן היה משאיר ידיות פתוחות בכל מסלול
    // יציאה מוקדם — והיו כאן שלושה כאלה.
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

      var current = root;
      for (final name in folder) {
        final child = _openStorage(current, name);
        if (child == nullptr) {
          debugPrint('ResponsaChm: "$name" not found in $chmPath');
          return const {};
        }
        handles.add(child);
        current = child;
      }

      final found = <String, Uint8List>{};
      _collect(current, '', found, 0, _Budget());
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

  /// אוסף רקורסיבית את כל הזרמים שתחת [storage].
  ///
  /// שני חסמים, ושניהם על **קובץ שאיננו מכירים**: עומק ותקציב זיכרון.
  /// ‏`Bblgrphy` של CD25 הוא 1,306 קבצים בשני מפלסים וכ-2MB, אבל אין
  /// ערובה למבנה של מהדורה אחרת, וקריאת קטלוג אינה מקום להיתקע בו או
  /// לבלוע בו מאות מגה-בייטים.
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
          // השם הוקצה על ידי COM ולא על ידינו. בלי השחרור הזה כל קריאת
          // קטלוג מדליפה את שמות 1,500 הקבצים שבקובץ העזרה.
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
  int _remaining = ResponsaChm.maxTotalBytesForBudget;

  bool get exhausted => _remaining <= 0;

  void spend(int bytes) => _remaining -= bytes;
}
