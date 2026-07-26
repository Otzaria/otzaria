/// סמני-מספר מודפסים בגוף הספר, כגון (9), שמפנים להערה בספר "הערות על ..."
/// המקושר כמפרש (משפחת "חברותא" וכדומה). הסמן כבר קיים בטקסט השמור — כאן רק
/// עוטפים אותו בעוגן, כדי שריחוף עליו יציג את ההערה בחלונית התצוגה המקדימה.
library;

import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

final RegExp _markerRegExp = RegExp(r'\(\d{1,3}\)');

/// ההערה עצמה נפתחת באותו סמן שמודפס בגוף הספר, למשל "(9) לכאורה יש לעיין...".
final RegExp _noteOpeningMarkerRegExp = RegExp(r'^\s*\(\s*(\d{1,3})\s*\)');

/// קישורי ההערות הממוספרות של השורה: מפרשים שכותרתם "הערות...".
///
/// זהו הסינון היחיד שאפשר לעשות באופן סינכרוני בזמן רינדור — התאמת הסמן
/// להערה עצמה נעשית לפי תוכן ההערה, בזמן הריחוף ([numberedNoteLinkFromUrl]).
List<Link> numberedNoteLinks(List<Link> linksForLine) => linksForLine
    .where(
      (link) =>
          LinkTypes.isDependentTextLink(link.connectionType) &&
          link.path2.isNotEmpty &&
          link.index2 > 0 &&
          utils.getTitleFromPath(link.path2).startsWith('הערות'),
    )
    .toList();

/// עוטף כל סמן-מספר בשורה בעוגן ריחוף, בלי לשנות את הטקסט הגלוי.
///
/// הסריקה מדלגת על תוכן שבתוך תגי HTML, ומוסיפה תגים בלבד — ולכן אופסטי
/// התווים-הגלויים של השורה נשמרים, ואפשר להזריק אחר-כך סמני עוגן-מילה.
String addNumberedNoteMarkerLinks(String html, {required int lineIndex}) {
  if (!html.contains('(')) return html;

  final out = StringBuffer();
  var i = 0;
  final len = html.length;
  var wrapped = false;
  while (i < len) {
    if (html[i] == '<') {
      final close = html.indexOf('>', i);
      if (close < 0) break;
      out.write(html.substring(i, close + 1));
      i = close + 1;
      continue;
    }
    final next = html.indexOf('<', i);
    final segmentEnd = next < 0 ? len : next;
    final segment = html.substring(i, segmentEnd);
    out.write(
      segment.replaceAllMapped(_markerRegExp, (match) {
        wrapped = true;
        final marker = match[0]!;
        final number = marker.substring(1, marker.length - 1);
        return '<a class="numbered-note-marker" '
            'href="otzaria://note-marker?line=$lineIndex&num=$number">'
            '$marker</a>';
      }),
    );
    i = segmentEnd;
  }
  if (i < len) out.write(html.substring(i));
  return wrapped ? out.toString() : html;
}

/// מאתר מבין [linksForLine] את ההערה שנפתחת בסמן שב-[url].
///
/// טעינת תוכן הקישורים ממוטמעת ב-[Link.content], ולכן ריחוף חוזר מיידי.
/// מחזיר null כשאין התאמה — אז לא מוצגת חלונית כלל.
Future<Link?> numberedNoteLinkFromUrl(
  String url,
  List<Link> linksForLine,
) async {
  final uri = Uri.tryParse(url);
  if (uri?.scheme != 'otzaria' || uri?.host != 'note-marker') return null;
  final number = uri!.queryParameters['num'];
  if (number == null || number.isEmpty) return null;

  final candidates = numberedNoteLinks(linksForLine);
  for (final link in candidates) {
    final String content;
    try {
      content = await link.content;
    } catch (_) {
      continue;
    }
    final match = _noteOpeningMarkerRegExp.firstMatch(
      utils.stripHtmlIfNeeded(content),
    );
    if (match != null && match.group(1) == number) return link;
  }
  return null;
}

/// מספר השורה שממנה נשלח [url] של סמן-מספר.
int? noteMarkerLineFromUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri?.scheme != 'otzaria' || uri?.host != 'note-marker') return null;
  return int.tryParse(uri!.queryParameters['line'] ?? '');
}
