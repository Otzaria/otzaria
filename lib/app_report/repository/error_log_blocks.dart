import 'dart:convert';

import 'package:otzaria_report_contract/otzaria_report_contract.dart';

/// רשומה אחת מ-errors.txt, כולל הטקסט המלא שלה.
class ErrorLogBlock {
  const ErrorLogBlock({
    required this.title,
    required this.timestamp,
    required this.text,
  });

  final String title;
  final DateTime? timestamp;

  /// הרשומה כפי שנכתבה, כולל שורת הכותרת.
  final String text;

  bool get isStartupStall => title.startsWith('Startup stall');

  /// תקיעה בזמן ריצה שגלאי הנייטיב רשם (`hang_monitor.cpp`).
  bool get isAppHang => title == 'App hang';
  bool get isAppHangRecovered => title == 'App hang recovered';

  /// ה-thread נתקע בתוך מטפל חריגות (למשל של Sentry) אחרי חריגה נייטיבית:
  /// זו קריסה, וחתימתה מהחריגה ולא מהמחסנית התקועה.
  bool get isStuckInExceptionHandler =>
      isAppHang &&
      exceptionMessage == _stuckInHandlerMessage &&
      _nativeException != null;

  static const String _stuckInHandlerMessage =
      'AppHang: UI thread stuck in exception handler';

  /// `Code:` ו-`Address:` מהסעיף `--- Native exception` הראשון (החריגה המקורית).
  ({String code, String address})? get _nativeException {
    String? code;
    var inSection = false;
    for (final line in const LineSplitter().convert(text)) {
      if (line.startsWith('--- Native exception')) {
        inSection = true;
      } else if (!inSection) {
        continue;
      } else if (line.startsWith('---')) {
        return null;
      } else if (line.startsWith('Code:')) {
        code = line.substring(5).trim().split(' ').first.toLowerCase();
      } else if (line.startsWith('Address:') && code != null) {
        return (code: code, address: line.substring(8).trim());
      }
    }
    return null;
  }

  /// שגיאה לא מטופלת או תקיעה — ראיה לקריסה, בניגוד לאזהרות כמו `Slow startup`.
  bool get isCrashEvidence =>
      isStartupStall || title == 'FlutterError' || title == 'Unhandled Error';

  /// שורת `Exception:` (או `Message:` ברשומות נייטיב), אם קיימת.
  String? get exceptionMessage {
    for (final line in const LineSplitter().convert(text)) {
      for (final prefix in const ['Exception:', 'Message:']) {
        if (line.startsWith(prefix)) {
          return line.substring(prefix.length).trim();
        }
      }
    }
    return null;
  }

  /// השורות שאחרי `Stack:` / `Stack (module+RVA):`, עד בלוק משנה.
  String get stackText {
    final lines = const LineSplitter().convert(text);
    final stack = <String>[];
    var inStack = false;
    for (final line in lines) {
      if (!inStack) {
        inStack = line.trimRight().startsWith('Stack');
        continue;
      }
      if (line.trim().startsWith('---')) break;
      stack.add(line);
    }
    return stack.join('\n');
  }

  /// חתימה לפי ההודעה וה-stack; לרשומה בלי הודעה — לפי הכותרת.
  CrashSignature get signature {
    final native = isStuckInExceptionHandler ? _nativeException : null;
    if (native != null) {
      return _nativeCrashSignature(native.code, native.address);
    }
    return hangSignature;
  }

  /// [signature] בלי החלפה בחתימת החריגה — לתקיעה שהשתחררה, שאינה קריסה.
  CrashSignature get hangSignature {
    final message = exceptionMessage ?? title;
    if (!isAppHang) {
      return CrashSignature.fromLogText(
        exceptionMessage: message,
        stackText: stackText,
      );
    }
    return CrashSignature(
      exceptionType: CrashSignature.exceptionTypeFromMessage(message),
      frames: _hangSignatureFrames(stackText),
    );
  }
}

/// כמו `readMinidumpSignature`, כדי שהתקיעה תתקבץ עם ה-dump של אותה קריסה.
CrashSignature _nativeCrashSignature(String code, String address) {
  final frame = address.startsWith('0x') ? null : address;
  final type = frame == null ? code : '$code $frame';
  return CrashSignature(
    exceptionType: type.length <= CrashSignature.maxExceptionTypeLength
        ? type
        : type.substring(0, CrashSignature.maxExceptionTypeLength),
    frames: [?frame],
  );
}

/// בתקיעה הפריימים העליונים הם המתנה של מערכת ההפעלה, זהה לכל התקיעות.
const Set<String> _systemModules = {
  'ntdll.dll',
  'win32u.dll',
  'kernelbase.dll',
  'kernel32.dll',
  'user32.dll',
  'gdi32.dll',
  'gdi32full.dll',
  'combase.dll',
  'ole32.dll',
  'rpcrt4.dll',
  'sechost.dll',
  'advapi32.dll',
  'ucrtbase.dll',
  'msvcrt.dll',
  'msvcp140.dll',
  'vcruntime140.dll',
  'vcruntime140_1.dll',
};

/// פריימי app.so הראשונים הם לרוב SDK כללי (`existsSync`) והקורא עמוק יותר, ולכן
/// נלקחים 8, ארבעה בכל פריט, כי השרת מקבל עד [CrashSignature.maxFrames] פריטים.
const int _hangDartFrames = 8;
const int _hangDartFramesPerEntry = 4;

/// הנייטיב כותב [_hangTopFrames] פריימים עליונים, `... (N frames omitted) ...` ותחתית.
/// החתימה רק מהראש, כמו ברשומות שנחתכו בעבר ב-48, כדי שלא תשתנה עם עומק המחסנית.
const int _hangTopFrames = 48;

List<String> _hangSignatureFrames(String stackText) {
  final frames = const LineSplitter()
      .convert(stackText)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .takeWhile((line) => !line.startsWith('...'))
      .take(_hangTopFrames)
      .toList();
  bool isDart(String frame) => frame.toLowerCase().startsWith('app.so+');
  final dartAt = frames.indexWhere(isDart);
  if (dartAt < 0) return _nativeHangFrames(frames);

  // מתחת לרצף הראשון יש רק כניסת המנוע ולולאת ההודעות, זהות לכל תקיעה.
  var run = frames.skip(dartAt).takeWhile(isDart);
  // מחסנית שמתחילה ב-Dart: הפריים העליון הוא PC של קוד רץ, לא כתובת חזרה, וזז.
  if (dartAt == 0 && run.length > 1) run = run.skip(1);
  // כפילויות (רקורסיה) נדחסות, כדי שעומק שונה לא ישנה את החתימה.
  final distinct = run.toSet().take(_hangDartFrames).toList();
  return [
    for (var i = 0; i < distinct.length; i += _hangDartFramesPerEntry)
      distinct.skip(i).take(_hangDartFramesPerEntry).join(' '),
  ];
}

/// תקיעה בלי קוד Dart: הפריימים הראשונים שאינם המתנה של מערכת ההפעלה.
List<String> _nativeHangFrames(List<String> frames) {
  final kept = frames.where((frame) {
    final plus = frame.indexOf('+');
    return plus <= 0 ||
        !_systemModules.contains(frame.substring(0, plus).toLowerCase());
  }).toList();
  final hasFrame = kept.any((f) => CrashSignature.normalizeFrame(f) != null);
  return CrashSignature.selectFrames((hasFrame ? kept : frames).join('\n'));
}

final RegExp _blockHeader = RegExp(r'^===\s+(.*?)\s+(\S+)\s+===\s*$');

/// מפענח את errors.txt לרשומות. טקסט שלפני הכותרת הראשונה (זנב חתוך) נזרק.
List<ErrorLogBlock> parseErrorLogBlocks(String content) {
  final blocks = <ErrorLogBlock>[];
  String? title;
  DateTime? timestamp;
  var buffer = StringBuffer();

  void flush() {
    if (title == null) return;
    blocks.add(
      ErrorLogBlock(
        title: title,
        timestamp: timestamp,
        text: buffer.toString().trimRight(),
      ),
    );
  }

  for (final line in const LineSplitter().convert(content)) {
    final header = _blockHeader.firstMatch(line);
    if (header != null) {
      flush();
      title = header.group(1)!.trim();
      timestamp = DateTime.tryParse(header.group(2)!);
      buffer = StringBuffer()..writeln(line);
      continue;
    }
    if (title != null) buffer.writeln(line);
  }
  flush();
  return blocks;
}

/// רשומות מ-[since] והלאה, מהחדשה לישנה, בגבול [maxBytes] — הישנות נשמטות.
String recentErrorLogExcerpt(
  String content, {
  required DateTime since,
  required int maxBytes,
}) {
  final recent =
      parseErrorLogBlocks(
          content,
        ).where((block) => !(block.timestamp?.isBefore(since) ?? true)).toList()
        ..sort((a, b) => b.timestamp!.compareTo(a.timestamp!));
  final kept = <String>[];
  var bytes = 0;
  for (final block in recent) {
    final size = utf8.encode(block.text).length + 2;
    if (bytes + size > maxBytes) break;
    kept.add(block.text);
    bytes += size;
  }
  // בקובץ עצמו הסדר כרונולוגי, וכך קל יותר לקרוא.
  return kept.reversed.join('\n\n');
}
