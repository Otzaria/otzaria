/// זיהוי קישורים בטקסט חופשי של הערות אישיות.
///
/// [linkifyDeltaOps] הופך כתובות שהודבקו כטקסט רגיל בתוך Quill Delta
/// (`otzaria://`, `zayit://`, `http(s)://`) למקטעים עם attribute של link,
/// כך שהן מוצגות ולחיצות כמו קישור שנוסף דרך הדיאלוג המובנה.
library;

final RegExp _urlPattern = RegExp(
  r'(?:otzaria|zayit|https?)://[^\s]+',
  caseSensitive: false,
);

/// תווי פיסוק שמסיימים משפט ולא שייכים לכתובת עצמה.
const String _trailingPunctuation = '.,;:!?)]}\'"';

/// מחזיר את הכתובת ללא פיסוק נגרר (למשל נקודה בסוף משפט).
String _stripTrailingPunctuation(String url) {
  var end = url.length;
  while (end > 0 && _trailingPunctuation.contains(url[end - 1])) {
    end--;
  }
  return url.substring(0, end);
}

/// עובר על אופרציות של Quill Delta ומחיל attribute של link על כתובות
/// שמופיעות כטקסט רגיל. אופרציות שכבר מקושרות, או שאינן טקסט, נשמרות כמות שהן.
List<dynamic> linkifyDeltaOps(List<dynamic> ops) {
  final result = <dynamic>[];
  for (final op in ops) {
    if (op is! Map<String, dynamic>) {
      result.add(op);
      continue;
    }
    final insert = op['insert'];
    final attributes = op['attributes'];
    final hasLink =
        attributes is Map<String, dynamic> && attributes['link'] != null;
    if (insert is! String || hasLink) {
      result.add(op);
      continue;
    }

    var cursor = 0;
    var changed = false;
    for (final match in _urlPattern.allMatches(insert)) {
      final url = _stripTrailingPunctuation(match.group(0)!);
      if (url.isEmpty) continue;
      if (match.start > cursor) {
        result.add({
          'insert': insert.substring(cursor, match.start),
          'attributes': ?attributes,
        });
      }
      result.add({
        'insert': url,
        'attributes': {
          if (attributes is Map<String, dynamic>) ...attributes,
          'link': url,
        },
      });
      cursor = match.start + url.length;
      changed = true;
    }

    if (!changed) {
      result.add(op);
      continue;
    }
    if (cursor < insert.length) {
      result.add({
        'insert': insert.substring(cursor),
        'attributes': ?attributes,
      });
    }
  }
  return result;
}
