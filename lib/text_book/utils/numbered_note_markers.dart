/// סמני הערה מודפסים בגוף הספר — מספר כגון (9), או אות בתוך `<sup>` כגון
/// `<sup>(א)</sup>` — שמפנים להערה בספר "הערות על ..." המקושר כמפרש
/// (משפחת "חברותא", "שמירת שבת כהלכתה" וכדומה). הסמן כבר קיים בטקסט השמור —
/// כאן רק עוטפים אותו בעוגן, כדי שריחוף עליו יציג את ההערה בחלונית התצוגה.
library;

import 'package:otzaria/text_book/models/book_notes.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

final RegExp _markerRegExp = RegExp(r'\(\d{1,4}\)');

/// תבנית האות: גימטריה בלבד, עם כוכביות שמבדילות סמן חוזר ("כא*").
const String _letterToken = r'[א-ת]{1,6}\*{0,2}';

/// סמן-אות מזוהה רק בתוך `<sup>` חשוף. אות בסוגריים שכיחה בגוף הטקסט עצמו
/// (מאות מופעים לכרך), ובלעדי ההגבלה הזאת היו נעטפים סמנים מדומים.
final RegExp _supLetterMarkerRegExp = RegExp(
  '<sup>\\s*\\(\\s*($_letterToken)\\s*\\)\\s*</sup>',
  caseSensitive: false,
);

/// ההערה עצמה נפתחת באותו סמן שמודפס בגוף הספר, למשל "(9) לכאורה יש לעיין...".
final RegExp _noteOpeningMarkerRegExp = RegExp(
  '^\\s*\\(\\s*(\\d{1,4}|$_letterToken)\\s*\\)',
);

final RegExp _anchorOpenRegExp = RegExp(
  r'^<a(?:\s[^>]*[^/>])?>$',
  caseSensitive: false,
);
final RegExp _anchorCloseRegExp = RegExp(r'^</a\s*>$', caseSensitive: false);

/// קישורי ההערות הממוספרות של השורה.
///
/// הזיהוי הוא לפי סוג הקישור [LinkTypes.footnotes] — נתון שנכתב ב-DB. כותרת
/// שמתחילה ב"הערות" נשארת כקבלה תאימות־לאחור בלבד, לקישורים ישנים שנשמרו
/// כ-COMMENTARY: היא ניחוש, והיא מפספסת כל ספר הערות ששמו אינו בתבנית הזאת.
///
/// זהו הסינון היחיד שאפשר לעשות באופן סינכרוני בזמן רינדור — התאמת הסמן
/// להערה עצמה נעשית לפי תוכן ההערה, בזמן הריחוף ([numberedNoteLinkFromUrl]).
List<Link> numberedNoteLinks(List<Link> linksForLine) => linksForLine
    .where(
      (link) =>
          LinkTypes.isDependentTextLink(link.connectionType) &&
          link.path2.isNotEmpty &&
          link.index2 > 0 &&
          (LinkTypes.normalize(link.connectionType) == LinkTypes.footnotes ||
              utils.getTitleFromPath(link.path2).startsWith('הערות')),
    )
    .toList();

/// עוגן הריחוף של סמן אחד — [visible] הוא הסמן כפי שהוא מודפס.
String _markerAnchor(String token, String visible, int lineIndex) =>
    '<a class="numbered-note-marker" '
    'href="otzaria://note-marker?line=$lineIndex'
    '&num=${Uri.encodeQueryComponent(token)}">'
    '$visible</a>';

/// עוטף כל סמן הערה בשורה בעוגן ריחוף, בלי לשנות את הטקסט הגלוי.
///
/// הסריקה מדלגת על תוכן שבתוך תגי HTML, ומוסיפה תגים בלבד — ולכן אופסטי
/// התווים-הגלויים של השורה נשמרים, ואפשר להזריק אחר-כך סמני עוגן-מילה.
/// סמן שכבר נמצא בתוך `<a>` נשאר כמו שהוא — עוגן מקונן הוא HTML לא חוקי
/// ומפרק את הקישור הקיים.
String addNumberedNoteMarkerLinks(String html, {required int lineIndex}) {
  if (!html.contains('(')) return html;

  final out = StringBuffer();
  var i = 0;
  final len = html.length;
  var wrapped = false;
  var anchorDepth = 0;
  while (i < len) {
    if (html[i] == '<') {
      if (anchorDepth == 0) {
        final supMatch = _supLetterMarkerRegExp.matchAsPrefix(html, i);
        if (supMatch != null) {
          wrapped = true;
          out.write(
            _markerAnchor(supMatch.group(1)!, supMatch.group(0)!, lineIndex),
          );
          i = supMatch.end;
          continue;
        }
      }
      final close = html.indexOf('>', i);
      if (close < 0) break;
      final tag = html.substring(i, close + 1);
      if (_anchorOpenRegExp.hasMatch(tag)) {
        anchorDepth++;
      } else if (_anchorCloseRegExp.hasMatch(tag) && anchorDepth > 0) {
        anchorDepth--;
      }
      out.write(tag);
      i = close + 1;
      continue;
    }
    final next = html.indexOf('<', i);
    final segmentEnd = next < 0 ? len : next;
    final segment = html.substring(i, segmentEnd);
    if (anchorDepth > 0) {
      out.write(segment);
    } else {
      out.write(
        segment.replaceAllMapped(_markerRegExp, (match) {
          wrapped = true;
          final marker = match[0]!;
          return _markerAnchor(
            marker.substring(1, marker.length - 1),
            marker,
            lineIndex,
          );
        }),
      );
    }
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
  if (candidates.isEmpty) return null;
  // טעינה מקבילה — סריקה סדרתית הייתה מצטברת להשהיה של כמה קריאות קובץ.
  final contents = await Future.wait(
    candidates.map(
      (link) => link.content.then<String?>((c) => c, onError: (_) => null),
    ),
  );
  for (var index = 0; index < candidates.length; index++) {
    final content = contents[index];
    if (content == null) continue;
    final match = _noteOpeningMarkerRegExp.firstMatch(
      utils.stripHtmlIfNeeded(content),
    );
    if (match != null && match.group(1) == number) return candidates[index];
  }
  return null;
}

/// מבין הערות השורה מהמסד ([notes], `line_note`) — זו שנפתחת בסמן שב-[url],
/// או שאות-ההפניה שלה היא הסמן. null כשאין התאמה.
BookNote? numberedBookNoteFromUrl(String url, List<BookNote> notes) {
  final uri = Uri.tryParse(url);
  if (uri?.scheme != 'otzaria' || uri?.host != 'note-marker') return null;
  final number = uri!.queryParameters['num'];
  if (number == null || number.isEmpty) return null;
  for (final note in notes) {
    final marker = note.marker;
    final markerText = marker == null
        ? null
        : utils.stripHtmlIfNeeded(marker).trim();
    if (markerText == number || markerText == '($number)') return note;
    final match = _noteOpeningMarkerRegExp.firstMatch(
      utils.stripHtmlIfNeeded(note.body),
    );
    if (match != null && match.group(1) == number) return note;
  }
  return null;
}

/// מספר השורה שממנה נשלח [url] של סמן-מספר.
int? noteMarkerLineFromUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri?.scheme != 'otzaria' || uri?.host != 'note-marker') return null;
  return int.tryParse(uri!.queryParameters['line'] ?? '');
}
