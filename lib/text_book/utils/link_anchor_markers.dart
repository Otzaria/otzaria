import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/utils/note_anchor_utils.dart';

/// סמני עוגן-מילה (טבלת link_anchor שבמסד): הזרקת אות סימון קטנה, למשל (א),
/// בנקודה המדויקת בשורת המקור שבה יושבת הערת המפרש.
///
/// `anchorStart` שמור במסד באופסט של *תווים גלויים* — תגי HTML לא נספרים,
/// entity (`&...;`) נספר כתו אחד — אותה מוסכמה של `line.charCount`. ההזרקה
/// חייבת לכן להיעשות על שורת המקור *כפי שנשמרה*, לפני כל עיבוד שמוסיף תוכן
/// גלוי (סימוני הערות אישיות וכד').

/// מספר וריאנטי הטיפוגרפיה של הסמנים (ראו SmartTextWidget.customStylesBuilder).
const int kLinkAnchorStyleCount = 6;

/// אות הסימון של קישור מעוגן: התווית ששמורה במסד, ואם אין — הרכיב האחרון של
/// ה-heRef של ההערה (מספר ההערה בגימטריה, כפי שמודפס). מחזיר null כשאין אות
/// לתצוגה — קישור כזה לא מקבל סמן.
String? anchorMarkerLetter(Link link) => _letterFor(link, link.anchorLabel);

String? _letterFor(Link link, String? storedLabel) {
  final label = storedLabel?.trim();
  if (label != null && label.isNotEmpty) return label;
  final tail = link.heRef.split(',').last.trim();
  final letters = tail.replaceAll(RegExp(r'["׳״]'), '');
  if (letters.isEmpty || letters.length > 4) return null;
  if (!RegExp(r'^[א-ת]+$').hasMatch(letters)) return null;
  return tail;
}

/// הקצאת וריאנט טיפוגרפי קבוע לכל מפרש שיש לו עוגני-מילה: לפי סדר אלפביתי של
/// כותרות המפרשים — דטרמיניסטי לאורך כל הספר, כך שכל מפרש שומר על עיצובו.
Map<String, int> anchorStyleIndexByCommentator(Iterable<Link> links) {
  final titles = links
      .where((link) => link.anchorStart != null)
      .map((link) => link.path2)
      .toSet()
      .toList()
    ..sort();
  return {
    for (var i = 0; i < titles.length; i++)
      titles[i]: i % kLinkAnchorStyleCount,
  };
}

/// מזריק את סמני העוגן לשורת ה-HTML הגולמית. הליכה אחת על השורה ממירה את
/// אופסט התווים-הגלויים לנקודת ההזרקה: לפני התו הגלוי הבא אחרי מיקום העוגן
/// (כך שהסמן לא ייכנס לתוך תג פתוח).
///
/// שני סוגי עוגנים (קישור יכול לשאת כמה, דרך anchorSpans):
///  - עוגן-נקודה (end == null): סמן אות מורם, למשל (א).
///  - עוגן-טווח (end != null, ציטוטים מ-charLevelData): עטיפת הטווח דרך
///    [wrapHtmlRanges] — שסוגר/פותח סביב תגים לא-מאוזנים כדי לשמור קינון
///    תקין — באותו וריאנט סגנון של המפרש.
String injectLinkAnchorMarkers({
  required String rawLine,
  required List<Link> anchorLinks,
  required Map<String, int> styleIndexByCommentator,
}) {
  final points = <({int at, int order, String html})>[];
  final ranges = <HtmlWrapRange>[];
  for (final link in anchorLinks) {
    final spans = link.anchorSpans.isNotEmpty
        ? link.anchorSpans
        : [
            if (link.anchorStart != null)
              LinkAnchorSpan(
                start: link.anchorStart!,
                end: link.anchorEnd,
                label: link.anchorLabel,
              ),
          ];
    final styleIndex = styleIndexByCommentator[link.path2] ?? 0;
    for (final span in spans) {
      if (span.start < 0) continue;
      final end = span.end;
      if (end != null && end > span.start) {
        final rawStart = _rawStartOfVisible(rawLine, span.start);
        final rawEnd = _rawEndOfVisible(rawLine, end);
        if (rawStart < rawEnd) {
          ranges.add(HtmlWrapRange(
            start: rawStart,
            end: rawEnd,
            openTag: '<span class="link-anchor-range link-anchor-$styleIndex">',
            closeTag: '</span>',
          ));
        }
      } else {
        final letter = _letterFor(link, span.label);
        if (letter == null) continue;
        // span ולא sup: HtmlWidget מממש sup כ-WidgetSpan, ושניים+ בפסקת RTL
        // מוצגים בסדר תוכן הפוך. ההגבהה נעשית ב-CSS (customStylesBuilder).
        points.add((
          at: span.start,
          order: 1,
          html:
              '<span class="link-anchor link-anchor-$styleIndex">($letter)</span>',
        ));
      }
    }
  }
  // טווחים קודם (על אופסטים גולמיים של השורה המקורית); סמני הנקודה מוזרקים
  // אחר-כך לפי אופסטים גלויים, שהתגים שנוספו לא משנים. טווחים חופפים:
  // wrapHtmlRanges שומר את הראשון ומדלג על החופף לו — ויתור מכוון על
  // הדגשה כפולה כדי לא לייצר HTML מוצלב.
  var result = ranges.isEmpty ? rawLine : wrapHtmlRanges(rawLine, ranges);
  return _injectAtVisibleOffsets(result, points);
}

/// עוטף טווח תווים-גלויים [start, end) של שורת HTML בתגי פתיחה/סגירה, תוך
/// שמירת קינון תקין סביב תגים לא-מאוזנים (דרך [wrapHtmlRanges]).
/// משמש להדגשת הציטוט (linkedAnchor) בתוך קטע המפרש בפאנל.
String wrapVisibleRange({
  required String html,
  required int start,
  required int end,
  required String openTag,
  required String closeTag,
}) {
  if (start < 0 || end <= start) return html;
  final rawStart = _rawStartOfVisible(html, start);
  final rawEnd = _rawEndOfVisible(html, end);
  if (rawStart >= rawEnd) return html;
  return wrapHtmlRanges(html, [
    HtmlWrapRange(
      start: rawStart,
      end: rawEnd,
      openTag: openTag,
      closeTag: closeTag,
    ),
  ]);
}

/// אינדקס גולמי של תחילת התו הגלוי מספר [visibleOffset] (אחרי תגים קודמים);
/// אורך המחרוזת כשהאופסט מעבר לסוף.
int _rawStartOfVisible(String html, int visibleOffset) {
  var visible = 0;
  var i = 0;
  final len = html.length;
  while (i < len) {
    if (html[i] == '<') {
      final close = html.indexOf('>', i);
      if (close < 0) return len;
      i = close + 1;
    } else {
      if (visible == visibleOffset) return i;
      if (html[i] == '&') {
        final end = (i + 10 < len) ? i + 10 : len;
        final j = html.indexOf(';', i + 1);
        i = (j > 0 && j < end) ? j + 1 : i + 1;
      } else {
        i++;
      }
      visible++;
    }
  }
  return len;
}

/// אינדקס גולמי מיד אחרי התו הגלוי מספר [visibleOffset]-1 — סוף טווח
/// אקסקלוסיבי שאינו בולע תגים עוקבים.
int _rawEndOfVisible(String html, int visibleOffset) {
  if (visibleOffset <= 0) return 0;
  var visible = 0;
  var i = 0;
  final len = html.length;
  while (i < len) {
    if (html[i] == '<') {
      final close = html.indexOf('>', i);
      if (close < 0) return len;
      i = close + 1;
    } else {
      if (html[i] == '&') {
        final end = (i + 10 < len) ? i + 10 : len;
        final j = html.indexOf(';', i + 1);
        i = (j > 0 && j < end) ? j + 1 : i + 1;
      } else {
        i++;
      }
      visible++;
      if (visible == visibleOffset) return i;
    }
  }
  return len;
}

String _injectAtVisibleOffsets(
  String rawLine,
  List<({int at, int order, String html})> markers,
) {
  if (markers.isEmpty) return rawLine;
  markers.sort((a, b) {
    final byAt = a.at.compareTo(b.at);
    return byAt != 0 ? byAt : a.order.compareTo(b.order);
  });

  final out = StringBuffer();
  var visible = 0;
  var next = 0;
  var i = 0;
  final len = rawLine.length;

  void flushMarkersAt(int visibleCount) {
    while (next < markers.length && markers[next].at <= visibleCount) {
      out.write(markers[next].html);
      next++;
    }
  }

  while (i < len) {
    final c = rawLine[i];
    if (c == '<') {
      // הסמן שייך לתו הגלוי *הבא*: לפני תג פתיחה הוא נכנס עכשיו, אבל תג
      // סגירה נכתב קודם — אחרת הסמן נבלע בתוך האלמנט הנסגר ויורש את עיצובו.
      final isClosingTag = i + 1 < len && rawLine[i + 1] == '/';
      if (!isClosingTag) {
        flushMarkersAt(visible);
      }
      final close = rawLine.indexOf('>', i);
      if (close < 0) {
        out.write(rawLine.substring(i));
        i = len;
        break;
      }
      out.write(rawLine.substring(i, close + 1));
      i = close + 1;
    } else {
      // תו גלוי (או entity שנספר כתו אחד) — סמנים שמקומם כאן נכנסים לפניו.
      flushMarkersAt(visible);
      if (c == '&') {
        final end = (i + 10 < len) ? i + 10 : len;
        var j = i + 1;
        var terminated = false;
        while (j < end) {
          if (rawLine[j] == ';') {
            terminated = true;
            break;
          }
          j++;
        }
        final entityEnd = terminated ? j + 1 : i + 1;
        out.write(rawLine.substring(i, entityEnd));
        i = entityEnd;
      } else {
        out.write(c);
        i++;
      }
      visible++;
    }
  }
  // סמנים שנותרו (בסוף השורה או מעבר לאורכה) מוזרקים בסוף.
  while (next < markers.length) {
    out.write(markers[next].html);
    next++;
  }
  return out.toString();
}
