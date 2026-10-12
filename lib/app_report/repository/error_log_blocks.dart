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
  CrashSignature get signature => CrashSignature.fromLogText(
    exceptionMessage: exceptionMessage ?? title,
    stackText: stackText,
  );
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
