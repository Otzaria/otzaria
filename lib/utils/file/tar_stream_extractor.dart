import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:otzaria/utils/file/zstd_stream_extractor.dart'
    show ZstdOutputLimitExceeded;
import 'package:seforim_library_updater/seforim_library_updater.dart'
    show kDefaultMaxExtractedBytes;

/// פורס tar שמגיע בנתחים (ustar, GNU long names ו-pax) ישירות לתיקייה,
/// בלי לשמור את ה-tar. כל רשומה חייבת לשבת תחת [rootFolder] (null — כל שורש),
/// ונתיב שבורח מהיעד נדחה. [add] מסתיים רק אחרי שכל הכתיבות שלו הסתיימו.
class TarStreamExtractor {
  TarStreamExtractor(
    this.destination, {
    required this.rootFolder,
    this.maxOutputBytes = kDefaultMaxExtractedBytes,
    this.checkCancelled,
    this.onWrite,
  }) {
    if (maxOutputBytes <= 0) {
      throw ArgumentError.value(maxOutputBytes, 'maxOutputBytes');
    }
  }

  final String destination;
  final String? rootFolder;
  final int maxOutputBytes;
  final void Function()? checkCancelled;

  /// נקרא לפני כל כתיבה פיזית, לרבות עותקים של רשומות hardlink.
  final void Function(int bytes)? onWrite;
  int _outputBytes = 0;

  static const _block = 512;
  static const _maxMetaEntrySize = 1 << 20;
  // תקרה על קבצים פתוחים בו-זמנית (ב-macOS המגבלה היא 256); ה-IO מקבילי ממילא
  // עד 32.
  static const _maxInFlight = 32;

  final _header = BytesBuilder(copy: true);
  RandomAccessFile? _file;
  Future<void>? _write;
  final _inFlight = <Future<void>>[];
  BytesBuilder? _meta;
  int _metaType = 0;
  int _remaining = 0;
  int _padding = 0;
  String? _pendingPath;
  String? _pendingLinkPath;
  int? _pendingSize;
  bool _ended = false;
  int _filesWritten = 0;

  /// מספר הקבצים הרגילים שנכתבו.
  int get filesWritten => _filesWritten;

  Future<void> add(Uint8List data) async {
    try {
      checkCancelled?.call();
      await _feed(data);
    } catch (_) {
      try {
        await _drain();
      } catch (_) {}
      rethrow;
    }
    await _drain();
    checkCancelled?.call();
  }

  Future<void> _feed(Uint8List data) async {
    var offset = 0;
    while (offset < data.length) {
      checkCancelled?.call();
      if (_ended) return;
      if (_remaining > 0) {
        final take = (data.length - offset).clamp(0, _remaining);
        _consumeData(data, offset, take);
        offset += take;
        _remaining -= take;
        if (_remaining == 0) _finishEntry();
        continue;
      }
      if (_padding > 0) {
        final take = (data.length - offset).clamp(0, _padding);
        offset += take;
        _padding -= take;
        continue;
      }
      final need = _block - _header.length;
      final take = (data.length - offset).clamp(0, need);
      _header.add(Uint8List.sublistView(data, offset, offset + take));
      offset += take;
      if (_header.length == _block) await _onHeader(_header.takeBytes());
    }
  }

  /// מוודא שה-tar לא נקטע באמצע רשומה וסוגר את הקובץ הפתוח.
  void close() {
    checkCancelled?.call();
    final midEntry = _remaining > 0 || _header.length > 0 || _meta != null;
    _closeFile();
    if (midEntry) {
      throw const FormatException('הארכיון קטוע — רשומה לא הושלמה');
    }
    if (_filesWritten == 0) {
      throw const FormatException('הארכיון ריק');
    }
  }

  /// סוגר קובץ פתוח בלי בדיקות — לניקוי אחרי כשל או ביטול.
  void abort() => _closeFile();

  // קבצים שהסתיימו באותו נתח נכתבים ונסגרים במקביל; המתנה לכל אחד הייתה
  // מוסיפה סבב IO לכל קובץ קטן.
  void _closeFile() {
    final file = _file;
    final write = _write;
    _file = null;
    _write = null;
    if (file == null) return;
    if (write == null) {
      file.closeSync();
    } else {
      _inFlight.add(write.whenComplete(file.close));
    }
  }

  Future<void> _drain() async {
    final pending = [..._inFlight, ?_write];
    _inFlight.clear();
    _write = null;
    await Future.wait(pending);
  }

  // writeFromSync מחזיק את ה-buffer לכל אורך הכתיבה, וה-GC של כל ה-isolates
  // ממתין לו; בדיסק עמוס זה תוקע את ה-UI (#3332).
  void _consumeData(Uint8List data, int offset, int length) {
    if (length == 0) return;
    final file = _file;
    if (file != null) {
      _reserveOutput(length);
      // writeFrom מעתיק את הנתונים כבר בקריאה; view ולא offset, אחרת כל
      // ה-buffer נשלח.
      _write = file.writeFrom(
        Uint8List.sublistView(data, offset, offset + length),
      );
      return;
    }
    final meta = _meta;
    if (meta != null) {
      if (meta.length + length > _maxMetaEntrySize) {
        throw const FormatException('רשומת מטא-דאטה גדולה מדי בארכיון');
      }
      meta.add(Uint8List.sublistView(data, offset, offset + length));
    }
  }

  void _reserveOutput(int bytes) {
    checkCancelled?.call();
    if (bytes > maxOutputBytes - _outputBytes) {
      throw ZstdOutputLimitExceeded(maxOutputBytes);
    }
    onWrite?.call(bytes);
    _outputBytes += bytes;
  }

  Future<void> _copyHardlink(String source, String target) async {
    final inputFile = File(source);
    final outputFile = File(target);
    if (p.equals(p.absolute(source), p.absolute(target)) ||
        (await outputFile.exists() &&
            await FileSystemEntity.identical(
              await inputFile.resolveSymbolicLinks(),
              await outputFile.resolveSymbolicLinks(),
            ))) {
      throw const FormatException('קישור קשיח מפנה אל עצמו');
    }
    final input = await inputFile.open();
    RandomAccessFile? output;
    try {
      final size = await input.length();
      if (size > maxOutputBytes - _outputBytes) {
        throw ZstdOutputLimitExceeded(maxOutputBytes);
      }
      checkCancelled?.call();
      final out = output = await outputFile.open(mode: FileMode.write);
      final buffer = Uint8List(1 << 20);
      var read = 0;
      while (true) {
        checkCancelled?.call();
        final count = await input.readInto(buffer);
        if (count == 0) break;
        if (count > size - read) {
          throw const FormatException('מקור הקישור הקשיח השתנה במהלך הקריאה');
        }
        _reserveOutput(count);
        await out.writeFrom(buffer, 0, count);
        read += count;
        checkCancelled?.call();
      }
      if (read != size) {
        throw const FormatException('מקור הקישור הקשיח נקטע במהלך הקריאה');
      }
      await out.flush();
      checkCancelled?.call();
    } finally {
      await output?.close();
      await input.close();
    }
  }

  Future<void> _onHeader(Uint8List h) async {
    if (h.every((b) => b == 0)) {
      _ended = true;
      return;
    }
    _verifyChecksum(h);
    final type = h[156];
    final isMeta = type == 0x4C || type == 0x4B || type == 0x78 || type == 0x67;
    final headerSize = _parseNumber(h, 124, 12);
    final size = isMeta ? headerSize : (_pendingSize ?? headerSize);
    // שדה ה-prefix קיים רק ב-POSIX ustar; ב-GNU אותם בתים הם שדות אחרים.
    final isPosixUstar = h[257] == 0x75 && h[262] == 0;
    // שם ארוך (GNU/pax) קוטע את השדה הקצר, לפעמים באמצע תו UTF-8.
    final name = isMeta
        ? ''
        : _pendingPath ??
              (isPosixUstar
                  ? _joinPrefix(
                      _parseString(h, 345, 155),
                      _parseString(h, 0, 100),
                    )
                  : _parseString(h, 0, 100));
    final linkName = type == 0x31
        ? _pendingLinkPath ?? _parseString(h, 157, 100)
        : '';
    _remaining = size;
    _padding = (_block - size % _block) % _block;

    switch (type) {
      case 0x4C || 0x4B || 0x78 || 0x67: // L, K, x, g
        _meta = BytesBuilder(copy: true);
        _metaType = type;
      case 0x30 || 0x00 || 0x37: // קובץ רגיל
        _resetPending();
        final target = _resolve(name);
        if (target != null) {
          final file = File(target);
          // שמות שונים עשויים להפנות לאותו קובץ (Unicode, אותיות גדולות).
          if (_inFlight.length >= _maxInFlight ||
              (_inFlight.isNotEmpty && file.existsSync())) {
            await _drain();
          }
          await Directory(p.dirname(target)).create(recursive: true);
          _file = file.openSync(mode: FileMode.writeOnly);
          _filesWritten++;
        }
      case 0x35: // תיקייה
        _resetPending();
        final target = _resolve(name);
        if (target != null) await Directory(target).create(recursive: true);
      case 0x31: // קישור קשיח — עותק של קובץ שכבר נפרס
        _resetPending();
        final target = _resolve(name);
        final source = _resolve(linkName);
        if (target == null || source == null) {
          throw FormatException('קישור לא תקין בארכיון: $name');
        }
        await _drain();
        await Directory(p.dirname(target)).create(recursive: true);
        await _copyHardlink(source, target);
        _filesWritten++;
      default:
        // קישורים סימבוליים והתקנים אינם חלק מהספרייה — מדלגים על התוכן.
        _resetPending();
    }
    if (_remaining == 0) _finishEntry();
  }

  void _finishEntry() {
    _closeFile();
    final meta = _meta;
    if (meta == null) return;
    _meta = null;
    final bytes = meta.takeBytes();
    switch (_metaType) {
      case 0x4C:
        _pendingPath = _decodeName(bytes);
      case 0x4B:
        _pendingLinkPath = _decodeName(bytes);
      case 0x78:
        _applyPax(bytes);
    }
  }

  void _resetPending() {
    _pendingPath = null;
    _pendingLinkPath = null;
    _pendingSize = null;
  }

  void _applyPax(Uint8List bytes) {
    var offset = 0;
    while (offset < bytes.length) {
      final space = bytes.indexOf(0x20, offset);
      if (space < 0) break;
      final length = int.tryParse(ascii.decode(bytes.sublist(offset, space)));
      if (length == null || length <= 0 || offset + length > bytes.length) {
        throw const FormatException('רשומת pax פגומה בארכיון');
      }
      final record = utf8.decode(bytes.sublist(space + 1, offset + length - 1));
      final eq = record.indexOf('=');
      if (eq > 0) {
        final key = record.substring(0, eq);
        final value = record.substring(eq + 1);
        switch (key) {
          case 'path':
            _pendingPath = value;
          case 'linkpath':
            _pendingLinkPath = value;
          case 'size':
            _pendingSize = int.tryParse(value);
        }
      }
      offset += length;
    }
  }

  /// הנתיב המלא ביעד, או null לרשומת שורש. זורק על נתיב שבורח מהיעד או
  /// שאינו תחת [rootFolder].
  String? _resolve(String name) {
    final segments = name
        .split('/')
        .where((s) => s.isNotEmpty && s != '.')
        .toList();
    final unsafe =
        name.startsWith('/') ||
        segments.any((s) => s == '..' || s.contains('\\') || s.contains(':'));
    if (unsafe) throw FormatException('נתיב לא בטוח בארכיון: $name');
    final root = rootFolder;
    if (root == null) {
      if (segments.isEmpty) return null;
    } else {
      if (segments.isEmpty || segments.first != root) {
        throw FormatException('מבנה הארכיון אינו צפוי: $name');
      }
      if (segments.length == 1) return null;
    }
    return p.joinAll([destination, ...segments]);
  }

  void _verifyChecksum(Uint8List h) {
    final stored = _parseNumber(h, 148, 8);
    var sum = 0;
    for (var i = 0; i < _block; i++) {
      sum += (i >= 148 && i < 156) ? 0x20 : h[i];
    }
    if (sum != stored) {
      throw const FormatException('כותרת פגומה בארכיון (checksum)');
    }
  }

  static String _joinPrefix(String prefix, String name) =>
      prefix.isEmpty ? name : '$prefix/$name';

  static String _parseString(Uint8List h, int offset, int length) {
    var end = offset;
    while (end < offset + length && h[end] != 0) {
      end++;
    }
    return _decodeName(Uint8List.sublistView(h, offset, end));
  }

  static String _decodeName(Uint8List bytes) {
    var end = bytes.length;
    while (end > 0 && bytes[end - 1] == 0) {
      end--;
    }
    try {
      return utf8.decode(Uint8List.sublistView(bytes, 0, end));
    } on FormatException {
      throw const FormatException('שם קובץ בארכיון אינו בקידוד UTF-8');
    }
  }

  /// שדה מספרי: אוקטלי, או base-256 (הביט העליון דלוק) לקבצים מעל 8GB.
  static int _parseNumber(Uint8List h, int offset, int length) {
    if (h[offset] & 0x80 != 0) {
      var value = h[offset] & 0x7F;
      for (var i = offset + 1; i < offset + length; i++) {
        value = (value << 8) | h[i];
      }
      return value;
    }
    final text = ascii
        .decode(Uint8List.sublistView(h, offset, offset + length))
        .replaceAll('\u0000', '')
        .trim();
    if (text.isEmpty) return 0;
    final value = int.tryParse(text, radix: 8);
    if (value == null) throw const FormatException('כותרת פגומה בארכיון');
    return value;
  }
}
