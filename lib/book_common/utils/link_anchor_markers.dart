import 'dart:typed_data';

import 'package:otzaria/divine_names/models/divine_name_forms.dart';
import 'package:otzaria/divine_names/models/divine_name_spans.dart';
import 'package:otzaria/divine_names/utils/divine_name_markers.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/personal_notes/utils/note_anchor_utils.dart';
import 'package:otzaria/book_common/utils/link_anchor_variants.dart';
import 'package:otzaria/utils/text/text_manipulation.dart'
    show HolyNameStyle, isHeadingLine;

/// סמני עוגן-מילה (טבלת link_anchor שבמסד): הזרקת אות סימון קטנה, למשל (א),
/// בנקודה המדויקת בשורת המקור שבה יושבת הערת המפרש.
///
/// `anchorStart` שמור במסד באופסט של *תווים גלויים* — תגי HTML לא נספרים,
/// entity (`&...;`) נספר כתו אחד — אותה מוסכמה של `line.charCount`. ההזרקה
/// חייבת לכן להיעשות על שורת המקור *כפי שנשמרה*, לפני כל עיבוד שמוסיף תוכן
/// גלוי (סימוני הערות אישיות וכד').

/// אות הסימון של קישור מעוגן: התווית ששמורה במסד, ואם אין — הרכיב האחרון של
/// ה-heRef של ההערה (מספר ההערה בגימטריה, כפי שמודפס). מחזיר null כשאין אות
/// לתצוגה — קישור כזה לא מקבל סמן.
String? anchorMarkerLetter(Link link) => _letterFor(link, link.anchorLabel);

/// סמן העוגן כפי שהוא מודפס בטקסט, בסוגרי הווריאנט של המפרש ([kLinkAnchorVariants]).
/// ⚠️ פאנלים חייבים לעבור דרך כאן — סוגריים קבועים לא יתאימו לטקסט.
String? anchorMarkerText(Link link) {
  final letter = anchorMarkerLetter(link);
  if (letter == null) return null;
  return wrapLinkAnchorLetter(letter, _stableStyleIndex(link.path2));
}

String? _letterFor(Link link, String? storedLabel) {
  final label = storedLabel?.trim();
  if (label != null && label.isNotEmpty) return _textPresentation(label);
  final tail = link.heRef.split(',').last.trim();
  final letters = tail.replaceAll(RegExp(r'["׳״]'), '');
  if (letters.isEmpty || letters.length > 4) return null;
  if (!RegExp(r'^[א-ת]+$').hasMatch(letters)) return null;
  return tail;
}

/// ♦ (U+2666) נתפס ע"י גופן האימוג'י ומוצג כיהלום אדום גדול (issue #1106);
/// ההחלפה ל-◆ (U+25C6), שאינו תו אימוג'י, שומרת את הצורה בצבע הטקסט.
String _textPresentation(String label) => label.replaceAll('♦', '◆');

/// הקצאת וריאנט טיפוגרפי קבוע לכל מפרש שיש לו עוגני-מילה — לסמני-האות
/// (עוגן-נקודה) בלבד, כדי שאפשר יהיה להבדיל בין מפרשים על אותו דף.
///
/// הווריאנט נגזר מהכותרת עצמה, ולכן אינו משתנה כשטעינת חלון גלילה מוסיפה
/// מפרשים חדשים לרשימה.
Map<String, int> anchorStyleIndexByCommentator(Iterable<Link> links) {
  final titles = links
      .where((link) => link.anchorStart != null)
      .map((link) => link.path2)
      .toSet();
  return {
    for (final title in titles) title: _stableStyleIndex(title),
  };
}

int _stableStyleIndex(String title) {
  var hash = 0x811c9dc5;
  for (final rune in title.runes) {
    hash = ((hash ^ rune) * 0x01000193) & 0xffffffff;
  }
  return hash % kLinkAnchorStyleCount;
}

/// מזריק את סמני העוגן לשורת ה-HTML הגולמית. הליכה אחת על השורה ממירה את
/// אופסט התווים-הגלויים לנקודת ההזרקה: לפני התו הגלוי הבא אחרי מיקום העוגן
/// (כך שהסמן לא ייכנס לתוך תג פתוח).
///
/// שני סוגי עוגנים (קישור יכול לשאת כמה, דרך anchorSpans):
///  - עוגן-נקודה (end == null): סמן אות מורם, למשל (א).
///  - עוגן-טווח (end != null, ציטוטי הלינקר): עטיפת הטווח דרך [wrapHtmlRanges]
///    — שסוגר/פותח סביב תגים לא-מאוזנים כדי לשמור קינון תקין. הטווח מעוצב
///    אחיד (צבע הנושא, בלי קו תחתון) ואינו נושא וריאנט טיפוגרפי.
///
/// בשורת כותרת (`<h1>`–`<h6>`) קישורי לינקר מדולגים לגמרי; שאר סוגי הקישורים
/// (סמני מפרשים וכד') מוזרקים כרגיל.
/// [lineIndex] (0-based) — כשמסופק, הסמנים נפלטים כ-`<a>` עם href
/// `otzaria://anchor?ref=<line>_<i>` (i = מיקום הקישור ב-[anchorLinks]), כדי
/// שריחוף/לחיצה יזהו את הקישור; עוגן-טווח מקבל גם `&range=1` — לחיצה עליו
/// מנווטת ישירות ליעד (ולא רק מקפיצה תצוגה). בלעדיו הכול `<span>` לא-אינטראקטיבי.
/// [rangesOnly] — רק ציטוטי הלינקר (עוגן-טווח); סמני-האות מדולגים. משמש
/// בחלוניות המפרשים והקישורים, שאינן מציגות סמני מפרש-על.
String injectLinkAnchorMarkers({
  required String rawLine,
  required List<Link> anchorLinks,
  required Map<String, int> styleIndexByCommentator,
  int? lineIndex,
  int? activeIndex,
  bool rangesOnly = false,
}) {
  final points = <({int at, int order, String html})>[];
  final ranges = <HtmlWrapRange>[];
  // כותרת היא כלי ניווט: ציטוט לינקר בתוכה הופך אותה לקישור לספר אחר.
  final skipLinker = isHeadingLine(rawLine);
  // כל המרה היא סריקה של השורה מתחילתה; שורה עם כמה מפרשים מעוגנים שואלת
  // לא פעם על אותו אופסט, ולכן שומרים את התוצאה לאורך הקריאה.
  final visibleAtRaw = <int, int>{};
  int toVisible(int rawOffset) =>
      visibleAtRaw[rawOffset] ??= _visibleOffsetAtRaw(rawLine, rawOffset);
  _VisibleChars? visibleChars;
  ({int count, int maxEnd})? rangeBounds;
  for (var linkIndex = 0; linkIndex < anchorLinks.length; linkIndex++) {
    final link = anchorLinks[linkIndex];
    // continue ולא סינון מראש: האינדקס מזהה את הקישור ב-href של הסמן.
    if (skipLinker && _isLinkerLink(link)) continue;
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
      final visibleStart = link.anchorOffsetsAreRaw
          ? toVisible(span.start)
          : span.start;
      final visibleEnd = end == null
          ? null
          : (link.anchorOffsetsAreRaw ? toVisible(end) : end);
      if (end != null && end > span.start) {
        // רק כשיש טווח בפועל: סמני נקודה אינם צריכים מפת תווים.
        final bounds = rangeBounds ??= _rangeBounds(anchorLinks, skipLinker);
        int rawStart;
        int rawEnd;
        if (bounds.count == 1) {
          // טווח יחיד נשאר במסלול הסורקים המקורי ללא הקצאת מערכים.
          rawStart = _rawStartOfVisible(rawLine, visibleStart);
          rawEnd = _rawEndOfVisible(rawLine, visibleEnd!);
        } else {
          // גם end גולמי הוא חסם עליון לספירה הגלויה: תגים/entities מצמצמים אותה.
          final chars = visibleChars ??= _VisibleChars(rawLine, bounds.maxEnd);
          rawStart = chars.rawStart(visibleStart);
          rawEnd = chars.rawEnd(visibleEnd!);
        }
        // עטיפה בתוך <sup> משאירה אותו sup עם markup (WidgetSpan שמתחלף ב-RTL).
        if (rawStart >= 5 &&
            rawLine.startsWith('<sup>', rawStart - 5) &&
            rawLine.startsWith('</sup>', rawEnd) &&
            rawLine.indexOf('</sup>', rawStart) == rawEnd) {
          rawStart -= 5;
          rawEnd += 6;
        }
        if (rawStart < rawEnd) {
          // עם lineIndex הטווח לחיץ/מרחף (a); בלעדיו — סימון בלבד (span).
          final tag = lineIndex == null ? 'span' : 'a';
          final href = lineIndex == null
              ? ''
              : ' href="otzaria://anchor?ref=${lineIndex}_$linkIndex&range=1"';
          ranges.add(
            HtmlWrapRange(
              start: rawStart,
              end: rawEnd,
              openTag: '<$tag class="link-anchor-range"$href>',
              closeTag: '</$tag>',
            ),
          );
        }
      } else {
        if (rangesOnly) continue;
        final letter = _letterFor(link, span.label);
        if (letter == null) continue;
        // a/span ולא sup: HtmlWidget מממש sup כ-WidgetSpan, ושניים+ בפסקת RTL
        // מוצגים בסדר תוכן הפוך. a נותר TextSpan (recognizer) — סדר RTL נשמר.
        final tag = lineIndex == null ? 'span' : 'a';
        final href = lineIndex == null
            ? ''
            : ' href="otzaria://anchor?ref=${lineIndex}_$linkIndex"';
        final activeClass = linkIndex == activeIndex
            ? ' link-anchor-active'
            : '';
        points.add((
          at: visibleStart,
          order: 1,
          html:
              '<$tag class="link-anchor link-anchor-$styleIndex$activeClass"$href>'
              '${wrapLinkAnchorLetter(letter, styleIndex)}</$tag>',
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

bool _isLinkerLink(Link link) =>
    LinkTypes.normalize(link.connectionType) == LinkTypes.linker;

({int count, int maxEnd}) _rangeBounds(List<Link> links, bool skipLinker) {
  var count = 0;
  var maxEnd = 0;
  void include(int? start, int? end) {
    if (start == null || start < 0 || end == null || end <= start) return;
    count++;
    if (end > maxEnd) maxEnd = end;
  }

  for (final link in links) {
    if (skipLinker && _isLinkerLink(link)) continue;
    if (link.anchorSpans.isEmpty) {
      include(link.anchorStart, link.anchorEnd);
    } else {
      for (final span in link.anchorSpans) {
        include(span.start, span.end);
      }
    }
  }
  return (count: count, maxEnd: maxEnd);
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

const _lt = 0x3C, _amp = 0x26;

/// עוטף את מופעי השמות [spans] של שורה בסמן שהרינדור ממיר לצורת התצוגה.
/// האופסטים גלויים, ולכן מותר להזריק קודם רק תגים (קישורי inline), לא תוכן.
/// מופע ששלדו אינו תואם את סוגו, או שחוצה תג, מושמט.
String wrapDivineNameSpans(String rawLine, List<DivineNameSpan> spans) {
  if (spans.isEmpty || rawLine.isEmpty) return rawLine;
  final visibleLength = _visibleOffsetAtRaw(rawLine, rawLine.length);
  final ranges = <HtmlWrapRange>[];
  for (final span in spans) {
    // מופע שחורג מסוף השורה מעיד על אופסטים שזזו.
    if (span.end > visibleLength) continue;
    final rawStart = _rawStartOfVisible(rawLine, span.start);
    final rawEnd = _rawEndOfVisible(rawLine, span.end);
    if (rawStart >= rawEnd) continue;
    final skeleton = divineNameSkeleton(rawLine.substring(rawStart, rawEnd));
    if (skeleton == null ||
        !divineNameSkeletonMatches(span.kind, skeleton) ||
        !divineNameHasWordBoundaries(rawLine, rawStart, rawEnd)) {
      continue;
    }
    ranges.add(
      HtmlWrapRange(
        start: rawStart,
        end: rawEnd,
        openTag: divineNameMarkerOpen(span.kind),
        closeTag: '</span>',
      ),
    );
  }
  return ranges.isEmpty ? rawLine : wrapHtmlRanges(rawLine, ranges);
}

/// [wrapDivineNameSpans] לשורה [lineIndex] (0-based) של ספר שמופעיו [names].
String injectDivineNameMarkers(
  String line,
  DivineNameSpans names,
  int lineIndex,
) => names.isEmpty ? line : wrapDivineNameSpans(line, names.spansAt(lineIndex));

/// מחיל על שורה [lineIndex] את מופעי השמות [names] ומחזיר אותה בלי סמנים —
/// למסלולי ההדפסה והייצוא, שאינם עוברים ב-`TextRendererService`.
/// [holyNameStyle] null משאיר את שם הוי"ה מהטבלה ככתבו (ה-regex רץ בנפרד).
String applyDivineNamesToLine(
  String line,
  DivineNameSpans names,
  int lineIndex, {
  required bool substituteOtherNames,
  HolyNameStyle? holyNameStyle,
}) {
  if (names.isEmpty || (!substituteOtherNames && holyNameStyle == null)) {
    return line;
  }
  final marked = injectDivineNameMarkers(line, names, lineIndex);
  if (identical(marked, line)) return line;
  return resolveDivineNameMarkers(
    marked,
    substituteOtherNames: substituteOtherNames,
    holyNameStyle: holyNameStyle,
  );
}

/// [applyDivineNamesToLine] על תוכן ספר שלם — שורה לכל `lineIndex`.
String applyDivineNamesToText(
  String text,
  DivineNameSpans names, {
  required bool substituteOtherNames,
  HolyNameStyle? holyNameStyle,
}) {
  if (names.isEmpty || (!substituteOtherNames && holyNameStyle == null)) {
    return text;
  }
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    lines[i] = applyDivineNamesToLine(
      lines[i],
      names,
      i,
      substituteOtherNames: substituteOtherNames,
      holyNameStyle: holyNameStyle,
    );
  }
  return lines.join('\n');
}

/// אינדקס גולמי של תחילת התו הגלוי מספר [visibleOffset] (אחרי תגים קודמים);
/// אורך המחרוזת כשהאופסט מעבר לסוף.
int _rawStartOfVisible(String html, int visibleOffset) {
  var visible = 0;
  var i = 0;
  final len = html.length;
  while (i < len) {
    if (html.codeUnitAt(i) == _lt) {
      final close = html.indexOf('>', i);
      if (close < 0) return len;
      i = close + 1;
    } else {
      if (visible == visibleOffset) return i;
      if (html.codeUnitAt(i) == _amp) {
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
    if (html.codeUnitAt(i) == _lt) {
      final close = html.indexOf('>', i);
      if (close < 0) return len;
      i = close + 1;
    } else {
      if (html.codeUnitAt(i) == _amp) {
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

/// גבולות גולמיים של התווים הגלויים הדרושים לטווחים, במעבר אחד:
/// שורה ארוכה נושאת מאות עוגני טווח,
/// וסריקה מתחילתה לכל טווח ריבועית. המפה נעצרת אחרי סוף הטווח הרחוק ביותר;
/// תג לא סגור עוצר את הספירה.
class _VisibleChars {
  final int _length;
  final Int32List _starts;
  final Int32List _ends;
  int _count = 0;

  _VisibleChars(String html, int maxEnd)
    : _length = html.length,
      _starts = Int32List(maxEnd < html.length ? maxEnd : html.length),
      _ends = Int32List(maxEnd < html.length ? maxEnd : html.length) {
    final len = html.length;
    var i = 0;
    while (i < len && _count < _starts.length) {
      if (html.codeUnitAt(i) == _lt) {
        final close = html.indexOf('>', i);
        if (close < 0) return;
        i = close + 1;
      } else {
        _starts[_count] = i;
        if (html.codeUnitAt(i) == _amp) {
          final end = (i + 10 < len) ? i + 10 : len;
          final j = html.indexOf(';', i + 1);
          i = (j > 0 && j < end) ? j + 1 : i + 1;
        } else {
          i++;
        }
        _ends[_count++] = i;
      }
    }
  }

  /// אינדקס גולמי של תחילת התו הגלוי מספר [visibleOffset] (אחרי תגים קודמים);
  /// אורך המחרוזת כשהאופסט מעבר לסוף.
  int rawStart(int visibleOffset) =>
      visibleOffset >= 0 && visibleOffset < _count
      ? _starts[visibleOffset]
      : _length;

  /// אינדקס גולמי מיד אחרי התו הגלוי מספר [visibleOffset]-1 — סוף טווח
  /// אקסקלוסיבי שאינו בולע תגים עוקבים.
  int rawEnd(int visibleOffset) {
    if (visibleOffset <= 0) return 0;
    return visibleOffset <= _count ? _ends[visibleOffset - 1] : _length;
  }
}

/// אופסט גולמי ← מספר התווים הגלויים שלפניו. ההיפוך של [_VisibleChars],
/// ולכן סופר בדיוק כמוהו: תג = 0, entity = 1, '&' בודד = 1.
int _visibleOffsetAtRaw(String html, int rawOffset) {
  final limit = rawOffset.clamp(0, html.length);
  var visible = 0;
  var i = 0;
  while (i < limit) {
    if (html.codeUnitAt(i) == _lt) {
      final close = html.indexOf('>', i);
      // תג שנחתך באמצע ע"י האופסט: מה שאחריו כבר לא נספר.
      if (close < 0 || close >= limit) break;
      i = close + 1;
    } else {
      if (html.codeUnitAt(i) == _amp) {
        final end = (i + 10 < html.length) ? i + 10 : html.length;
        final j = html.indexOf(';', i + 1);
        i = (j > 0 && j < end) ? j + 1 : i + 1;
      } else {
        i++;
      }
      visible++;
    }
  }
  return visible;
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
    final c = rawLine.codeUnitAt(i);
    if (c == _lt) {
      // הסמן שייך לתו הגלוי *הבא*: לפני תג פתיחה הוא נכנס עכשיו, אבל תג
      // סגירה נכתב קודם — אחרת הסמן נבלע בתוך האלמנט הנסגר ויורש את עיצובו.
      final isClosingTag = i + 1 < len && rawLine.codeUnitAt(i + 1) == 0x2F;
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
      if (c == _amp) {
        final end = (i + 10 < len) ? i + 10 : len;
        var j = i + 1;
        var terminated = false;
        while (j < end) {
          if (rawLine.codeUnitAt(j) == 0x3B) {
            terminated = true;
            break;
          }
          j++;
        }
        final entityEnd = terminated ? j + 1 : i + 1;
        out.write(rawLine.substring(i, entityEnd));
        i = entityEnd;
      } else {
        out.writeCharCode(c);
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
