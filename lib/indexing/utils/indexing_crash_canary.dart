import 'dart:convert';
import 'dart:io';

/// ספר שנשאר באמצע אינדוקס כשהתהליך מת, פעמיים ברצף.
class IndexingCrashedBefore implements Exception {
  const IndexingCrashedBefore();

  @override
  String toString() => 'אינדוקס הספר הפיל את התוכנה פעמיים ברצף; הספר דולג';
}

/// מוני קריסות של ספרים שבאינדוקס וחסימות שטרם נחתמו באינדקס.
class IndexingCrashCanary {
  IndexingCrashCanary._(this._file) : _attempts = _read(_file);

  /// הריצה הפעילה; סגירה מסודרת של התוכנה מסיימת אותה ([finish]).
  static IndexingCrashCanary? current;

  static void start(
    String? indexPath, {
    Iterable<String> Function()? pendingKeys,
  }) {
    current = indexPath == null
        ? null
        : IndexingCrashCanary._(File('$indexPath.in_flight.json'));
    final canary = current;
    if (canary != null && canary.recovering && pendingKeys != null) {
      final keys = pendingKeys().toSet();
      final previousCount = canary._attempts.length;
      canary._attempts.removeWhere((key, _) => !keys.contains(key));
      if (canary._attempts.length != previousCount) canary._write();
    }
  }

  static const finishRequest = 'finishIndexingCrashCanary';

  static const maxAttempts = 2;

  final File _file;
  final Map<String, int> _attempts;
  final Set<String> _inFlight = {};
  final Set<String> _skipped = {};
  RandomAccessFile? _raf;

  /// ריצה קודמת מתה באמצע: מאנדקסים ספר-ספר, כדי שרק האשם ייספר.
  bool get recovering => _attempts.isNotEmpty;

  static Map<String, int> _read(File file) {
    try {
      return Map<String, int>.from(jsonDecode(file.readAsStringSync()) as Map);
    } catch (_) {
      return {};
    }
  }

  /// false לספר שכבר הפיל [maxAttempts] ריצות; החסימה נשמרת עד commit.
  bool begin(String key) {
    final attempts = _attempts[key] ?? 0;
    if (attempts >= maxAttempts) {
      _skipped.add(key);
      return false;
    }
    if (_inFlight.add(key)) {
      _attempts[key] = attempts + 1;
      _write();
    }
    return true;
  }

  void end(String key) {
    if (_skipped.contains(key)) return;
    if (!_inFlight.remove(key)) return;
    if (_attempts.remove(key) != null) _write();
  }

  /// רק דילוגים שנחתמו באינדקס יכולים לאבד את חסימת הקריסה.
  void committed(Set<String> indexedKeys) {
    if (_skipped.isEmpty) return;
    final saved = _skipped.where(indexedKeys.contains).toList();
    if (saved.isEmpty) return;
    saved.forEach(_attempts.remove);
    _skipped.removeAll(saved);
    _write();
  }

  /// מנקה רק ספרים שה-reader קרא מהאינדקס החתום בדיסק.
  void forgetIndexed(Iterable<String> committedKeys) {
    final previousCount = _attempts.length;
    committedKeys.forEach(_attempts.remove);
    if (_attempts.length != previousCount) _write();
  }

  /// הריצה הסתיימה (או התוכנה נסגרה) בלי שהתהליך מת — מה שבטיסה לא הפיל אותו.
  void finish() {
    if (identical(current, this)) current = null;
    _inFlight.toList().forEach(end);
    try {
      _raf?.closeSync();
      _raf = null;
    } catch (_) {}
  }

  // קובץ פתוח לאורך הריצה: פתיחה לכל כתיבה עלתה פי 10 (נמדד ב-Windows).
  void _write() {
    try {
      final bytes = utf8.encode(jsonEncode(_attempts));
      (_raf ??= _file.openSync(mode: FileMode.write))
        ..setPositionSync(0)
        ..writeFromSync(bytes)
        ..truncateSync(bytes.length);
    } catch (_) {}
  }
}
