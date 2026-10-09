import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/core/messages/text_book_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/models/links.dart';

/// שורות המקור שקטע של [link] מכסה (קישור-טווח מכסה כמה).
int linkSegmentCount(Link link) =>
    (link.index2End ?? link.index2) - link.index2 + 1;

int linksSegmentCount(Iterable<Link> links) =>
    links.fold(0, (sum, link) => sum + linkSegmentCount(link));

/// מספר השורות בטקסט שנבחר, כשטווח השורות במקור אינו ידוע.
int countTextSegments(String text) {
  final count = text.split('\n').where((line) => line.trim().isNotEmpty).length;
  return count == 0 ? 1 : count;
}

/// מספר שורות המקור בטווח [start]..[end] (כולל), או לפי [text] כשהטווח חסר.
int selectionSegmentCount({int? start, int? end, required String text}) {
  if (start != null && end != null) return (end - start).abs() + 1;
  return countTextSegments(text);
}

/// האם מותר להעתיק [segmentCount] שורות; אחרת מציג הודעה ידידותית.
bool ensureCopyAllowed(BookProtection protection, int segmentCount) {
  if (protection.allowsCopyOf(segmentCount)) return true;
  UiSnack.show(
    TextBookMessages.copyLimitedByPublisher(protection.maxCopySegments!),
  );
  return false;
}

/// [text] אחרי מגבלת ההעתקה, לערוצים שאינם חוסמים (תוסף, קישור עם ציטוט):
/// רק השורות הראשונות עד המספר המותר.
String limitTextToCopySegments(BookProtection protection, String text) {
  final max = protection.maxCopySegments;
  if (max == null || countTextSegments(text) <= max) return text;
  final kept = <String>[];
  var segments = 0;
  for (final line in text.split('\n')) {
    if (line.trim().isNotEmpty && ++segments > max) break;
    kept.add(line);
  }
  return kept.join('\n').trimRight();
}
