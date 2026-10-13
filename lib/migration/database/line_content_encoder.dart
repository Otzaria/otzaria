import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart' as sqlite3;
import 'package:otzaria/migration/database/line_content_codec.dart';
import 'package:zstandard_native/zstandard_native_bindings.dart';

/// דוחס טקסט שורה למסגרת zstd של מילון אחד, שאותה [LineContentCodec] מפענח.
///
/// אחד לכל כותב; אינו בטוח לשימוש מכמה isolates. [dispose] משחרר את הזיכרון
/// הנייטיב מיד (מילון של 2MB) — אחרת הוא משתחרר רק באיסוף.
final class LineContentEncoder implements Finalizable {
  LineContentEncoder(Uint8List dictionary, {int level = defaultLevel}) {
    final lib = LineContentCodec.zstdLibrary();
    _zstd = ZstandardNativeBindings(lib);
    final freeCDict = _freeCDict ??= NativeFinalizer(
      lib.lookup<NativeFinalizerFunction>('ZSTD_freeCDict'),
    );
    final freeCCtx = _freeCCtx ??= NativeFinalizer(
      lib.lookup<NativeFinalizerFunction>('ZSTD_freeCCtx'),
    );
    final native = malloc<Uint8>(dictionary.length);
    try {
      native.asTypedList(dictionary.length).setAll(0, dictionary);
      _cdict = _zstd.ZSTD_createCDict(native.cast(), dictionary.length, level);
    } finally {
      malloc.free(native);
    }
    if (_cdict == nullptr) throw StateError('ZSTD_createCDict נכשל');
    freeCDict.attach(this, _cdict.cast(), detach: _cdictToken);
    _cctx = _zstd.ZSTD_createCCtx();
    if (_cctx == nullptr) {
      dispose();
      throw StateError('ZSTD_createCCtx נכשל');
    }
    freeCCtx.attach(this, _cctx.cast(), detach: _cctxToken);
    dictionaryId = _zstd.ZSTD_getDictID_fromCDict(_cdict);
  }

  /// רמה 3: בניית המילון והדחיסה מהירים, והיחס קרוב לרמות הגבוהות.
  static const defaultLevel = 3;

  static NativeFinalizer? _freeCDict;
  static NativeFinalizer? _freeCCtx;
  // ה-worker של הסנכרון נהרג בלי finally, ואז רק ה-finalizer משחרר.
  static final _freeBuffer = NativeFinalizer(malloc.nativeFree);

  late final ZstandardNativeBindings _zstd;
  Pointer<ZSTD_CDict> _cdict = nullptr;
  Pointer<ZSTD_CCtx> _cctx = nullptr;
  final _cdictToken = Object();
  final _cctxToken = Object();
  final _bufferToken = Object();
  Pointer<Uint8> _buffer = nullptr;
  int _capacity = 0;

  /// מזהה המילון שנכתב בכותרת כל מסגרת.
  late final int dictionaryId;

  /// מסגרת של [text], או null כשהדחיסה אינה חוסכת או שהשורה גדולה מדי לפענוח.
  Uint8List? encode(String text) {
    if (_cctx == nullptr) throw StateError('LineContentEncoder שוחרר');
    final bytes = utf8.encode(text);
    if (bytes.length > LineContentCodec.maxLineBytes) return null;
    final bound = _zstd.ZSTD_compressBound(bytes.length);
    final src = _reserve(bytes.length + bound);
    src.asTypedList(bytes.length).setAll(0, bytes);
    final dst = src + bytes.length;
    final written = _zstd.ZSTD_compress_usingCDict(
      _cctx,
      dst.cast(),
      bound,
      src.cast(),
      bytes.length,
      _cdict,
    );
    if (_zstd.ZSTD_isError(written) != 0) {
      throw StateError(
        'דחיסת zstd נכשלה: '
        '${_zstd.ZSTD_getErrorName(written).cast<Utf8>().toDartString()}',
      );
    }
    if (written >= bytes.length) return null;
    return Uint8List.fromList(dst.asTypedList(written));
  }

  Pointer<Uint8> _reserve(int bytes) {
    if (bytes > _capacity) {
      _freeOwnBuffer();
      _capacity = bytes < 64 * 1024 ? 64 * 1024 : bytes + bytes ~/ 4;
      _buffer = malloc<Uint8>(_capacity);
      _freeBuffer.attach(this, _buffer.cast(), detach: _bufferToken);
    }
    return _buffer;
  }

  void dispose() {
    if (_cctx != nullptr) {
      _freeCCtx!.detach(_cctxToken);
      _zstd.ZSTD_freeCCtx(_cctx);
      _cctx = nullptr;
    }
    if (_cdict != nullptr) {
      _freeCDict!.detach(_cdictToken);
      _zstd.ZSTD_freeCDict(_cdict);
      _cdict = nullptr;
    }
    _freeOwnBuffer();
  }

  void _freeOwnBuffer() {
    if (_buffer == nullptr) return;
    _freeBuffer.detach(_bufferToken);
    malloc.free(_buffer);
    _buffer = nullptr;
    _capacity = 0;
  }
}

/// מזהה מילון zstd מכותרתו (magic 0xEC30A437), או null למילון גולמי בלי מזהה.
int? zstdDictionaryId(Uint8List dictionary) {
  if (dictionary.length < 8) return null;
  final header = ByteData.sublistView(dictionary, 0, 8);
  if (header.getUint32(0, Endian.little) != 0xEC30A437) return null;
  final id = header.getUint32(4, Endian.little);
  return id == 0 ? null : id;
}

/// כותב שורות דחוסות ל-user_books.db עם מילון ש-seforim.db ([_source]) מספק.
///
/// המילון מועתק ל-`zstd_dict` של מסד היעד, כך שהקריאה לעולם אינה תלויה
/// ב-seforim.db. כשאין מילון מתאים — [encoderFor] מחזיר null והשורות נשמרות כטקסט.
final class LineContentWriter {
  LineContentWriter(
    this._source, {
    this.level = LineContentEncoder.defaultLevel,
    this.minBookChars = defaultMinBookChars,
  });

  /// כ-3MB של טקסט עברי: מתחת לזה מילון של 2MB אינו מחזיר את עצמו.
  static const defaultMinBookChars = 1536 * 1024;

  final sqlite3.Database _source;
  final int level;

  /// גודל ספר (בתווים) שממנו מעתיקים מילון למסד שעוד אין בו.
  final int minBookChars;

  bool _sourceRead = false;
  ({int id, Uint8List dict})? _dictionary;
  LineContentEncoder? _encoder;
  int? _encoderRowId;
  final Map<int, int> _bookChars = {};

  /// גודל הספר [bookId] בתווים, לפני כתיבת שורותיו.
  void announceBook(int bookId, int chars) => _bookChars[bookId] = chars;

  /// המקודד ל-[target], אחרי שהמילון שלו הועתק אליו. נקרא בתוך הטרנזקציה
  /// שכותבת את השורות, כדי שמסגרת לא תישמר בלי המילון שלה.
  LineContentEncoder? encoderFor(
    sqlite3.Database target, {
    required int bookId,
  }) {
    final installed = _installedEncoder(target);
    if (installed != null) return installed;
    if ((_bookChars[bookId] ?? 0) < minBookChars) return null;
    final dictionary = _readSourceDictionary();
    if (dictionary == null) return null;
    // בכל אצווה: טרנזקציה שבוטלה מבטלת גם את העתקת המילון.
    if (!_install(target, dictionary)) return null;
    return _encoderOf(dictionary.id, dictionary.dict);
  }

  /// מילון שכבר ב-[target] משמש גם לספרים הבאים: מילון חדש מהספרייה היה
  /// מוסיף עוד 2MB בכל אימון מחדש שם.
  LineContentEncoder? _installedEncoder(sqlite3.Database target) {
    final hasTable = target.select(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'zstd_dict'",
    );
    if (hasTable.isEmpty) return null;
    final ids = target.select('SELECT id FROM zstd_dict ORDER BY id DESC');
    if (ids.isEmpty) return null;
    final rowId = ids.first.values.first! as int;
    if (rowId == _encoderRowId) return _encoder;
    final dict = target
        .select('SELECT dict FROM zstd_dict WHERE id = ?', [rowId])
        .first
        .values
        .first;
    if (dict is! Uint8List || zstdDictionaryId(dict) == null) return null;
    return _encoderOf(rowId, dict);
  }

  LineContentEncoder _encoderOf(int rowId, Uint8List dict) {
    if (rowId == _encoderRowId) return _encoder!;
    _encoder?.dispose();
    _encoder = LineContentEncoder(dict, level: level);
    _encoderRowId = rowId;
    return _encoder!;
  }

  ({int id, Uint8List dict})? _readSourceDictionary() {
    if (_sourceRead) return _dictionary;
    _sourceRead = true;
    try {
      final hasTable = _source.select(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'zstd_dict'",
      );
      if (hasTable.isEmpty) return null;
      // המילון האחרון: אחרי אימון מחדש בספרייה השורות החדשות שם נדחסות בו.
      final rows = _source.select(
        'SELECT dict FROM zstd_dict ORDER BY id DESC LIMIT 1',
      );
      if (rows.isEmpty) return null;
      final dict = rows.first.values.first;
      if (dict is! Uint8List) return null;
      final id = zstdDictionaryId(dict);
      if (id == null) return null;
      return _dictionary = (id: id, dict: dict);
    } on sqlite3.SqliteException {
      return null;
    }
  }

  /// מוסיף את המילון ל-[target] אם חסר; false כשמזהה שלו תפוס במילון אחר.
  static bool _install(
    sqlite3.Database target,
    ({int id, Uint8List dict}) dictionary,
  ) {
    target.execute(
      'CREATE TABLE IF NOT EXISTS zstd_dict '
      '(id INTEGER PRIMARY KEY NOT NULL, dict BLOB NOT NULL)',
    );
    final same = target.select(
      'SELECT dict = ?2 FROM zstd_dict WHERE id = ?1',
      [
        dictionary.id,
        dictionary.dict,
      ],
    );
    if (same.isNotEmpty) return same.first.values.first == 1;
    // מילונים קיימים לא נמחקים: מסגרות ישנות מפוענחות רק בהם.
    for (final row in target.select('SELECT dict FROM zstd_dict')) {
      final existing = row.values.first;
      if (existing is Uint8List &&
          zstdDictionaryId(existing) == dictionary.id) {
        return _sameBytes(existing, dictionary.dict);
      }
    }
    target.execute('INSERT OR IGNORE INTO zstd_dict (id, dict) VALUES (?, ?)', [
      dictionary.id,
      dictionary.dict,
    ]);
    return target.updatedRows == 1;
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void dispose() {
    _encoder?.dispose();
    _encoder = null;
    _encoderRowId = null;
  }
}
