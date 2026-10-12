import 'dart:convert';

import 'package:crypto/crypto.dart';

/// חתימת קריסה: סוג החריגה ועד 3 פריימים מנורמלים, לקיבוץ דיווחים זהים בשרת.
class CrashSignature {
  const CrashSignature({required this.exceptionType, required this.frames});

  static const int maxFrames = 3;
  static const int maxExceptionTypeLength = 200;
  static const int maxFrameLength = 300;

  final String exceptionType;
  final List<String> frames;

  static const String _ownPackage = 'package:otzaria/';

  /// חתימה מחריגה חיה: שם הטיפוס בזמן ריצה + ה-stack.
  factory CrashSignature.fromError(Object error, StackTrace? stackTrace) {
    return CrashSignature(
      exceptionType: _clamp(
        error.runtimeType.toString(),
        maxExceptionTypeLength,
      ),
      frames: selectFrames(stackTrace?.toString() ?? ''),
    );
  }

  /// חתימה מטקסט שנקרא מהלוג: שורת `Exception:` ושורות ה-stack.
  factory CrashSignature.fromLogText({
    required String exceptionMessage,
    required String stackText,
  }) {
    return CrashSignature(
      exceptionType: exceptionTypeFromMessage(exceptionMessage),
      frames: selectFrames(stackText),
    );
  }

  /// `FormatException: x` → `FormatException`; הודעה חופשית מנוקה ממספרים
  /// וממחרוזות מצוטטות, כדי שאותה תקלה תקבל אותה חתימה.
  static String exceptionTypeFromMessage(String message) {
    final firstLine = message.trim().split('\n').first.trim();
    final colon = firstLine.indexOf(':');
    if (colon > 0) {
      final prefix = firstLine.substring(0, colon).trim();
      if (RegExp(r'^[A-Za-z_$][\w$<>,.? ]*$').hasMatch(prefix) &&
          !prefix.contains('  ')) {
        return _clamp(prefix, maxExceptionTypeLength);
      }
    }
    final stable = firstLine
        .replaceAll(
          RegExp(
            r"'[^']*'|"
            r'"[^"]*"',
          ),
          "''",
        )
        .replaceAll(RegExp(r'\d+'), '#');
    return _clamp(stable.isEmpty ? 'Unknown' : stable, maxExceptionTypeLength);
  }

  /// בוחר עד 3 פריימים: קודם פריימים של אוצריא, אחרת הראשונים שבמחסנית.
  static List<String> selectFrames(String stackText) {
    final normalized = <String>[];
    for (final line in const LineSplitter().convert(stackText)) {
      final frame = normalizeFrame(line);
      if (frame != null) normalized.add(frame);
    }
    final own = normalized.where((f) => f.contains(_ownPackage)).toList();
    final chosen = own.isNotEmpty ? own : normalized;
    return chosen.take(maxFrames).toList();
  }

  /// פריים אחד בלי מספור, שורה:עמודה ונתיב מוחלט. null לשורה שאינה פריים
  /// יציב (ריקה, השהיה אסינכרונית, כתובת זיכרון גולמית).
  static String? normalizeFrame(String line) {
    var frame = line.trim();
    if (frame.isEmpty || frame == '<asynchronous suspension>') return null;
    if (frame.startsWith('...')) return null;
    frame = frame.replaceFirst(RegExp(r'^#\d+\s+'), '');
    // כתובת מוחלטת משתנה בין הרצות (ASLR); מודול+RVA נשאר יציב.
    if (RegExp(r'^0x[0-9a-fA-F]+$').hasMatch(frame)) return null;

    frame = frame.replaceAllMapped(
      RegExp(r'file:///?[^\s)]+'),
      (m) => _basename(m.group(0)!.replaceFirst(RegExp(r'^file:///?'), '')),
    );
    frame = frame.replaceAllMapped(
      RegExp(r'(?<=^|[\s(])(?:[A-Za-z]:[\\/]|/)[^\s():]*[\\/]([^\s():\\/]+)'),
      (m) => m.group(1)!,
    );
    frame = frame
        .replaceAll(RegExp(r':\d+(?::\d+)?(?=\)|\s|$)'), '')
        .replaceAll(RegExp(r'\s+\d+(?::\d+)?(?=\s)'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (frame.isEmpty) return null;
    return _clamp(frame, maxFrameLength);
  }

  /// hash החתימה כפי שהשרת מחשב אותו: sha256 של הסוג והפריימים בשורות.
  String get hash => sha256
      .convert(utf8.encode('$exceptionType\n${frames.join('\n')}'))
      .toString();

  Map<String, dynamic> toJson() => {
    'exceptionType': exceptionType,
    'frames': frames,
  };

  static CrashSignature? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = json['exceptionType'];
    if (type is! String) return null;
    final frames = json['frames'];
    return CrashSignature(
      exceptionType: type,
      frames: frames is List
          ? frames.whereType<String>().toList()
          : const <String>[],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CrashSignature &&
      other.exceptionType == exceptionType &&
      _listEquals(other.frames, frames);

  @override
  int get hashCode => Object.hash(exceptionType, Object.hashAll(frames));

  @override
  String toString() => 'CrashSignature($exceptionType, $frames)';

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _basename(String path) {
    final parts = path.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? path : parts.last;
  }

  static String _clamp(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);
}
