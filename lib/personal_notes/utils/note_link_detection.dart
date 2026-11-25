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

/// כתובת קישור להערה אישית לפי מזהה ההערה, שאינו משתנה בגיבוי ובשחזור.
String personalNoteLinkUrl(String noteId) => Uri(
  scheme: 'otzaria',
  host: 'note',
  queryParameters: {'id': noteId},
).toString();

/// מזהה ההערה שהקישור [url] מפנה אליה, או null כשאינו קישור להערה.
String? personalNoteLinkTarget(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'otzaria' || uri.host != 'note') {
    return null;
  }
  try {
    final id = uri.queryParameters['id'];
    return id == null || id.isEmpty ? null : id;
  } on FormatException {
    return null;
  }
}

final _noteLinkPattern = RegExp(
  r'(?:otzaria|zayit|https?)://[^\s"<>{}\x5c]+',
  caseSensitive: false,
);

/// מחליף ב-[text] קישורים להערות שמזהן מופיע ב-[ids] בקישור למזהה החדש.
String remapPersonalNoteLinks(String text, Map<String, String> ids) {
  if (ids.isEmpty) return text;
  return text.replaceAllMapped(_noteLinkPattern, (match) {
    final raw = match.group(0)!;
    final unpunctuated = _stripTrailingPunctuation(raw);
    final fullTarget = ids[personalNoteLinkTarget(raw)];
    if (fullTarget != null) return personalNoteLinkUrl(fullTarget);
    final target = ids[personalNoteLinkTarget(unpunctuated)];
    if (target == null) return raw;
    return personalNoteLinkUrl(target) + raw.substring(unpunctuated.length);
  });
}
