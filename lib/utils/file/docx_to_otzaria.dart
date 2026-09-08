import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:otzaria/utils/file/document_conversion_exceptions.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/file/embedded_media.dart';
import 'package:otzaria/utils/file/zip_limits.dart';
import 'package:otzaria/utils/text/html_escape.dart';
import 'package:otzaria/utils/text/inline_style.dart';
import 'package:otzaria/utils/text/numeral_formats.dart';
import 'package:otzaria/utils/text/otzaria_markup.dart';
import 'package:xml/xml.dart' as xml;

/// גרסת מנוע ה-OOXML. **חובה להעלות ערך זה בכל שינוי שמשפיע על הפלט**
/// (עיצוב, כותרות, תמונות, טבלאות…). מטמון התוכן (`convertOoxmlWordWithCache`)
/// כולל את הגרסה במפתח-התוקף: העלאה כאן פוסלת אוטומטית את כל הרשומות שנוצרו
/// ע"י גרסה ישנה, וגורמת להמרה מחדש — כך משתמש שכבר פתח ספר יקבל את התצוגה
/// המשופרת בלי לגעת בקובץ.
/// v2: תמונות מוטמעות (data URI) וטבלאות עשירות. v3: רשימות ממוספרות
/// מקוננות (decimal/רומי/אותיות לטיניות/עבריות/multilevel) לפי numbering.xml.
/// v4: בקרות-תוכן (`w:sdt`) וטבלאות מקוננות בתאים — מניעת אובדן תוכן.
/// v5: תגיות אוצריא מילוליות בטקסט (`<b>`, `<big>`, `<h1>`–`<h6>`…) מזוהות
/// ומופעלות כעיצוב אמיתי במקום להיות מוצגות כטקסט (escape).
/// v6: תיבות-טקסט (`w:txbxContent`) — טקסט בתוך מסגרת, אולי על תמונת-רקע.
/// v7: דילוג על מסגרות-רקע דקורטיביות (`behindDoc`) שאינן ניתנות לרינדור.
/// v8: תמונות inline בתוך תיבת-טקסט אינן מזוהות בטעות כתמונת-רקע של התיבה.
/// v9: כותרות עם styleId מספרי (Word בעברית / המרה מ-HTML) לפי styles.xml
/// כולל ירושת `w:basedOn`, ו-`outlineLvl=9` ("Body Text") אינו נחשב לכותרת.
/// v10: מסמך שגופו אינו קריא זורק חריגה במקום להחזיר כותרת בלבד, ותמונות
/// SVG מוטמעות (המפה המשותפת ב-`embedded_media.dart` הכירה בהן; זו לא).
/// v11: `w:jc` לוגי (`start`/`end`) נפתר לפי `w:bidi`, תיבות-טקסט מזוהות לפי
/// שם מקומי (קידומת namespace אחרת שכפלה את תוכנן), ומילוי-תמונה של VML
/// (`v:fill type="frame"`) הוא תמונת הרקע של התיבה.
/// v12: יישור לוגי בפסקה RTL מדולג — מפיקי המסמכים חלוקים בפירושו, והכרעה
/// שגויה מיישרת קטע עברי שלם לצד ההפוך.
/// v13: ערכי צבע ויישור מהמסמך מסוננים לפני שהם נכנסים ל-`style` (מנע
/// הזרקת תגיות לגוף הספר), גוף הערת שוליים רב-פסקתית מופרד ברווח,
/// `w:customXml` שקוף, כל תיבות הטקסט בשייף מקובץ מרונדרות, `w:vMerge` בלי
/// תא פותח אינו נמחק, וכותרת עוברת trim.
/// v15: `w:hyperlink` הופך ל-`<a href="…">` אמיתי במקום לפלוט רק את טקסט
/// הקישור. יעד חיצוני (`r:id`) נפתר דרך `document.xml.rels` ומסונן ב-
/// `safeLinkTarget` (מקור יחיד, משותף עם ODT/HTML); יעד פנימי (`w:anchor`)
/// הופך ל-`href="#שם"`, וכותרת שסימניה (`w:bookmarkStart`) באותה פסקה שלה
/// היא היעד מקבלת `id` תואם — בדיוק המבנה שתוכן-עניינים אוטומטי של Word כותב.
const int kOoxmlWordConverterVersion = 15;

/// שם ותיק ל-[kOoxmlWordConverterVersion]. הערך משותף לכל פורמטי OOXML —
/// הם חולקים מנוע אחד, ולכן שינוי בפלט פוסל את המטמון של כולם יחד.
const int kDocxConverterVersion = kOoxmlWordConverterVersion;

// Windows-1255 Hebrew range: 0xC0–0xD8 and 0xE0–0xFA map to Unicode with offset 1264.
// 0xE0 (224) + 1264 = 1488 = U+05D0 = א, ... 0xFA (250) + 1264 = 1514 = U+05EA = ת
const _cp1255Offset = 1264;

String _decodeXmlBytes(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    final buf = StringBuffer();
    for (final b in bytes) {
      if (b < 0x80) {
        buf.writeCharCode(b);
      } else if ((b >= 0xC0 && b <= 0xD8) || (b >= 0xE0 && b <= 0xFA)) {
        buf.writeCharCode(b + _cp1255Offset);
      } else {
        buf.writeCharCode(b); // latin-1 fallback for other bytes
      }
    }
    return buf.toString();
  }
}

/// מונה רץ לסימוני הערות שוליים (משותף לגוף ולתאי טבלה).
class _FootnoteCounter {
  int _value = 1;
  int next() => _value++;
}

/// הגדרת רמה אחת ברשימה ממוספרת (`w:lvl` ב-numbering.xml).
class _NumLevel {
  /// `decimal` / `lowerRoman` / `upperLetter` / `hebrew1` / `bullet` …
  final String numFmt;

  /// תבנית התצוגה, למשל `%1.` או `%1.%2.` (multilevel).
  final String lvlText;

  /// ערך התחלה (`w:start`, ברירת מחדל 1).
  final int start;

  const _NumLevel(this.numFmt, this.lvlText, this.start);
}

/// משאבי המסמך המשותפים לכל פונקציות העיבוד: הערות שוליים, תמונות מוטמעות,
/// הגדרות רשימות, ומונים. מועבר במקום שורת פרמטרים ארוכה.
class _DocxContext {
  final Map<String, String> footnotes;

  /// `r:embed`/`r:id` → `data:image/...;base64,...` מוכן להטמעה (offline).
  final Map<String, String> images;

  /// `numId` → (`ilvl` → הגדרת הרמה). מקובץ numbering.xml.
  final Map<String, Map<int, _NumLevel>> numbering;

  /// `styleId` → רמת כותרת 1–6, מקובץ styles.xml.
  final Map<String, int> headingStyles;

  /// `rId` → כתובת יעד, מיחסי `hyperlink` ב-document.xml.rels.
  final Map<String, String> hyperlinkRels;

  /// שמות סימניה (`w:bookmarkStart`) שקישור פנימי (`w:anchor`) כלשהו במסמך
  /// מפנה אליהם. משמש כדי לפלוט `id` רק על כותרות שבאמת משמשות יעד — לא על
  /// כל סימניה במסמך (ראו את אותו עיקרון ב-HTML, `otzaria_markup.dart`).
  final Set<String> referencedAnchors;

  final _FootnoteCounter footnoteCounter = _FootnoteCounter();

  /// מונים רצים לרשימות: `numId` → (`ilvl` → הערך הנוכחי).
  final Map<String, Map<int, int>> _listCounters = {};

  _DocxContext(
    this.footnotes,
    this.images,
    this.numbering,
    this.headingStyles,
    this.hyperlinkRels,
    this.referencedAnchors,
  );

  /// מחזיר את תווית המספור/תבליט לפריט רשימה (למשל `1.`, `1.1.`, `א.`, `•`).
  /// מקדם את המונה המתאים ומאפס רמות עמוקות יותר (מבנה multilevel תקין).
  String listLabel(String? numId, int ilvl) {
    final levels = numId != null ? numbering[numId] : null;
    final lvl = levels?[ilvl];
    if (lvl == null) return '•'; // אין הגדרה — תבליט ברירת מחדל
    if (lvl.numFmt == 'bullet') return '•';

    final counters = _listCounters.putIfAbsent(numId!, () => {});
    counters[ilvl] = (counters[ilvl] ?? (lvl.start - 1)) + 1;
    counters.removeWhere((k, _) => k > ilvl); // איפוס רמות עמוקות יותר

    var label = lvl.lvlText;
    for (var k = 0; k <= ilvl; k++) {
      final kLvl = levels![k];
      if (kLvl == null) continue;
      final count = counters[k] ?? kLvl.start;
      label = label.replaceAll('%${k + 1}', _formatNum(count, kLvl.numFmt));
    }
    return label.isEmpty ? '•' : label;
  }
}

/// ממיר מספר לתצוגה לפי פורמט המספור של Word.
String _formatNum(int n, String fmt) {
  switch (fmt) {
    case 'decimalZero':
      return n < 10 ? '0$n' : '$n';
    case 'lowerLetter':
      return toLatinLetters(n, upper: false);
    case 'upperLetter':
      return toLatinLetters(n, upper: true);
    case 'lowerRoman':
      return toRomanNumeral(n).toLowerCase();
    case 'upperRoman':
      return toRomanNumeral(n);
    case 'hebrew1':
    case 'hebrew2':
      return toHebrewNumeral(n);
    case 'none':
      return '';
    case 'decimal':
    default:
      return '$n';
  }
}

/// בונה מפת `numId` → (`ilvl` → [_NumLevel]) מקובץ numbering.xml.
Map<String, Map<int, _NumLevel>> _extractNumbering(Archive archive) {
  ArchiveFile? numFile;
  for (final f in archive) {
    if (f.isFile && f.name == 'word/numbering.xml') {
      numFile = f;
      break;
    }
  }
  if (numFile == null) return const {};

  final xml.XmlDocument doc;
  try {
    doc = xml.XmlDocument.parse(
      _decodeXmlBytes(readArchiveEntry(numFile, format: DocumentFormat.docx)),
    );
  } catch (_) {
    return const {};
  }

  // abstractNumId → (ilvl → level)
  final abstracts = <String, Map<int, _NumLevel>>{};
  for (final an in doc.findAllElements('w:abstractNum')) {
    final aid = an.getAttribute('w:abstractNumId');
    if (aid == null) continue;
    final levels = <int, _NumLevel>{};
    for (final lvl in an.findElements('w:lvl')) {
      final ilvl = int.tryParse(lvl.getAttribute('w:ilvl') ?? '');
      if (ilvl == null) continue;
      final fmt =
          lvl.getElement('w:numFmt')?.getAttribute('w:val') ?? 'decimal';
      final text = lvl.getElement('w:lvlText')?.getAttribute('w:val') ?? '';
      final start =
          int.tryParse(
            lvl.getElement('w:start')?.getAttribute('w:val') ?? '',
          ) ??
          1;
      levels[ilvl] = _NumLevel(fmt, text, start);
    }
    abstracts[aid] = levels;
  }

  // numId → abstractNumId → levels
  final result = <String, Map<int, _NumLevel>>{};
  for (final num in doc.findAllElements('w:num')) {
    final numId = num.getAttribute('w:numId');
    final aid = num.getElement('w:abstractNumId')?.getAttribute('w:val');
    if (numId != null && aid != null && abstracts.containsKey(aid)) {
      result[numId] = abstracts[aid]!;
    }
  }
  return result;
}

/// בונה מפת `styleId` → רמת כותרת 1–6 מקובץ styles.xml.
///
/// Word בעברית (וקבצים שהומרו מ-HTML) שומר styleId מספרי (`"2"`) בעוד שהשם
/// (`heading 2`) וה-`w:outlineLvl` יושבים רק בהגדרת הסגנון — בלי המפה הזו כל
/// הכותרות במסמכים כאלה מפוספסות.
///
/// שרשרת `w:basedOn` נפתרת: סגנון מותאם המבוסס על `Heading1` יורש ממנו את
/// ה-`outlineLvl` ואין לו משלו. `outlineLvl` מפורש *עוצר* את הירושה — גם
/// הערך 9 ("Body Text"), שהוא ביטול מכוון של רמת האב.
Map<String, int> _extractHeadingStyles(Archive archive) {
  ArchiveFile? stylesFile;
  for (final f in archive) {
    if (f.isFile && f.name == 'word/styles.xml') {
      stylesFile = f;
      break;
    }
  }
  if (stylesFile == null) return const {};

  try {
    return _headingStylesFrom(
      xml.XmlDocument.parse(
        _decodeXmlBytes(
          readArchiveEntry(stylesFile, format: DocumentFormat.docx),
        ),
      ),
    );
  } catch (_) {
    return const {};
  }
}

/// גוף [_extractHeadingStyles], על מסמך XML שכבר נקרא. WordML 2003 מחזיק
/// את הסגנונות באותו מסמך עם אותו אוצר-מילים, ולכן שני הדיאלקטים חולקים
/// את הפתירה הזו.
Map<String, int> _headingStylesFrom(xml.XmlDocument doc) {
  final defs = <String, ({String? name, String? outline, String? basedOn})>{};
  for (final style in doc.findAllElements('w:style')) {
    final type = style.getAttribute('w:type');
    if (type != null && type != 'paragraph') continue;
    final id = style.getAttribute('w:styleId');
    if (id == null) continue;
    defs[id] = (
      name: style.getElement('w:name')?.getAttribute('w:val'),
      outline: style
          .getElement('w:pPr')
          ?.getElement('w:outlineLvl')
          ?.getAttribute('w:val'),
      basedOn: style.getElement('w:basedOn')?.getAttribute('w:val'),
    );
  }

  final resolved = <String, int?>{};
  int? levelOf(String id, Set<String> chain) {
    if (resolved.containsKey(id)) return resolved[id];
    if (!chain.add(id)) return null; // basedOn מעגלי בקובץ פגום
    final def = defs[id];
    if (def == null) return null;

    // `outlineLvl` מפורש הוא המידע האמין וגובר על השם: סגנון בשם
    // "Heading 1 Draft" עם `outlineLvl=9` אינו כותרת. השם הוא פרוקסי בלבד,
    // ומשמש רק כשאין `outlineLvl` — ואז גם הירושה מ-basedOn נכנסת לתוקף.
    if (_hasOutlineValue(def.outline)) {
      final byOutline = _headingLevelFromOutline(def.outline);
      resolved[id] = byOutline;
      return byOutline;
    }

    var level = _headingLevelFromStyleName(def.name);
    if (level == null && def.basedOn != null) {
      level = levelOf(def.basedOn!, chain);
    }
    resolved[id] = level;
    return level;
  }

  final result = <String, int>{};
  for (final id in defs.keys) {
    final level = levelOf(id, <String>{});
    if (level != null) result[id] = level;
  }
  return result;
}

/// בונה מפת `rId` → `data:` URI עבור כל התמונות המוטמעות בקובץ — קריאה
/// אחת של ה-relationships + קבצי ה-media, והמרה ל-base64. הטמעה מלאה
/// (offline) ולא קישור חיצוני. פורמטים שהקורא לא תומך בהם מדולגים בשקט.
///
/// [embedImages] כבוי מחזיר URI ריק במקום ה-base64: תגי ה-`<img>` נשארים
/// במקומם ולכן מבנה השורות זהה — קריטי, כי אינדקסי ה-TOC וה-highlight
/// נבנים מהווריאנט חסר-התמונות ונקראים מול הווריאנט המלא.
Map<String, String> _extractImages(Archive archive, {bool embedImages = true}) {
  // שלב 1: rId → target ("media/imageN.png"), רק יחסים מסוג image.
  final rels = <String, String>{};
  for (final file in archive) {
    if (file.isFile && file.name == 'word/_rels/document.xml.rels') {
      try {
        final doc = xml.XmlDocument.parse(
          _decodeXmlBytes(readArchiveEntry(file, format: DocumentFormat.docx)),
        );
        for (final rel in doc.findAllElements('Relationship')) {
          if ((rel.getAttribute('Type') ?? '').endsWith('/image')) {
            final id = rel.getAttribute('Id');
            final target = rel.getAttribute('Target');
            if (id != null && target != null) rels[id] = target;
          }
        }
      } catch (_) {
        // rels פגום — ממשיכים בלי תמונות.
      }
      break;
    }
  }
  if (rels.isEmpty) return const {};

  // שלב 2: target → bytes → data URI. ממפים נתיב מלא בארכיב לתוכן.
  final mediaByPath = <String, ArchiveFile>{};
  for (final file in archive) {
    if (file.isFile && file.name.startsWith('word/media/')) {
      mediaByPath[file.name] = file;
    }
  }

  final images = <String, String>{};
  var embeddedBytes = 0;
  rels.forEach((id, target) {
    final mime = imageMimeForPath(target);
    if (mime == null) return; // פורמט לא נתמך
    final file = mediaByPath[_mediaPathFor(target)];
    if (file == null) return; // קובץ חסר, או יעד חיצוני אמיתי

    if (!embedImages) {
      images[id] = '';
      return;
    }
    if (file.size > EmbeddedMediaLimits.maxImageBytes ||
        embeddedBytes + file.size > EmbeddedMediaLimits.maxTotalImageBytes) {
      images[id] = '';
      return;
    }
    try {
      final content = readArchiveEntry(file, format: DocumentFormat.docx);
      images[id] = 'data:$mime;base64,${base64Encode(content)}';
      embeddedBytes += content.length;
    } catch (_) {
      images[id] = '';
    }
  });
  return images;
}

/// בונה מפת `rId` → כתובת יעד עבור יחסי `hyperlink` ב-document.xml.rels.
///
/// חבילת WordML 2003 (הדיאלקט "אמיתי", לא Flat OPC) אינה מחזיקה קובץ יחסים
/// נפרד — קישור חיצוני שם אינו נפתר, ומוחזרת מפה ריקה; קישור פנימי
/// (`w:anchor`) עדיין עובד, כי הוא אינו תלוי ביחסים.
Map<String, String> _extractHyperlinkRels(Archive archive) {
  for (final file in archive) {
    if (file.isFile && file.name == 'word/_rels/document.xml.rels') {
      try {
        final doc = xml.XmlDocument.parse(
          _decodeXmlBytes(readArchiveEntry(file, format: DocumentFormat.docx)),
        );
        final rels = <String, String>{};
        for (final rel in doc.findAllElements('Relationship')) {
          if ((rel.getAttribute('Type') ?? '').endsWith('/hyperlink')) {
            final id = rel.getAttribute('Id');
            final target = rel.getAttribute('Target');
            if (id != null && target != null) rels[id] = target;
          }
        }
        return rels;
      } catch (_) {
        return const {}; // rels פגום — ממשיכים בלי קישורים חיצוניים.
      }
    }
  }
  return const {};
}

/// אוסף את שמות הסימניות (`w:anchor`) שקישור פנימי כלשהו ב-[body] מפנה
/// אליהן, כדי שכותרת תקבל `id` רק כשהיא באמת יעד של קישור פנימי.
Set<String> _collectHyperlinkAnchors(xml.XmlElement body) {
  final anchors = <String>{};
  for (final link in body.findAllElements('w:hyperlink')) {
    final anchor = link.getAttribute('w:anchor');
    if (anchor != null && anchor.isNotEmpty) anchors.add(anchor);
  }
  return anchors;
}

/// האם האלמנט הוא תוכן של תיבת-טקסט, בלי תלות בקידומת ה-namespace.
///
/// Word כותב את אותה תיבה פעמיים — DrawingML ו-VML לתאימות — ולעיתים
/// בקידומות שונות (`w:`, `wne:`). השוואה לקידומת אחת בלבד החמיצה את השנייה,
/// ואז תוכן התיבה נפלט גם בתוך המסגרת וגם כטקסט חופשי אחריה.
bool _isTextBoxContent(xml.XmlElement element) =>
    element.name.local == 'txbxContent';

Iterable<xml.XmlElement> _textBoxContents(xml.XmlElement root) =>
    root.descendantElements.where(_isTextBoxContent);

/// ממיר יעד של relationship לנתיב בתוך החבילה.
///
/// Word כותב למילוי-תמונה של שייפ יחס **חיצוני** שנתיבו הוא בעצם הפניה
/// לחבילה עצמה (`ooxWord://word/media/image12.png`). בלי הנרמול תמונת הרקע
/// של תיבת-טקסט אינה נמצאת. יעד חיצוני אמיתי (`http://…`) פשוט לא יתאים
/// לשום רשומה בארכיב — ואין כאן שום גישת רשת (§74).
String _mediaPathFor(String target) {
  final scheme = target.indexOf('://');
  final path = scheme < 0 ? target : target.substring(scheme + 3);
  if (path.startsWith('/')) return path.substring(1);
  return path.startsWith('word/') ? path : 'word/$path';
}

/// מחזיר את ה-data URI של תמונה מוטמעת ב-run (DrawingML `a:blip` או VML
/// `v:imagedata`), או `null`.
///
/// [includeShapeFill] מוסיף מילוי-תמונה של שייפ VML (`v:fill type="frame"`) —
/// כך נמצאת תמונת הרקע של תיבת-טקסט, שאינה `v:imagedata`.
String? _imageUriFromRun(
  xml.XmlElement run,
  Map<String, String> images, {
  bool skipTextBoxContent = false,
  bool includeShapeFill = false,
}) {
  if (images.isEmpty) return null;
  String? visit(xml.XmlElement element) {
    if (skipTextBoxContent && _isTextBoxContent(element)) {
      return null;
    }
    if (element.name.qualified == 'a:blip') {
      final id =
          element.getAttribute('r:embed') ?? element.getAttribute('r:link');
      final uri = id == null ? null : images[id];
      if (uri != null) return uri;
    }
    if (element.name.qualified == 'v:imagedata') {
      // `r:id` בחבילת OOXML; `src="wordml://…"` ב-WordML 2003, שבו התמונה
      // יושבת בתוך המסמך עצמו ואין לה relationship.
      final id = element.getAttribute('r:id') ?? element.getAttribute('src');
      final uri = id == null ? null : images[id];
      if (uri != null) return uri;
    }
    // `type="frame"` הוא מילוי-תמונה מתוח; מילוי דוגמה (`tile`/`pattern`) הוא
    // טקסטורה דקורטיבית שאין טעם להציג כתמונה.
    if (includeShapeFill &&
        element.name.qualified == 'v:fill' &&
        element.getAttribute('type') == 'frame') {
      final id = element.getAttribute('r:id') ?? element.getAttribute('src');
      final uri = id == null ? null : images[id];
      if (uri != null) return uri;
    }
    for (final child in element.childElements) {
      final uri = visit(child);
      if (uri != null) return uri;
    }
    return null;
  }

  return visit(run);
}

/// האם הגרפיקה היא תמונה צפה *מאחורי* הטקסט (`wp:anchor behindDoc="1"`) —
/// מסגרת/סימן-מים דקורטיבי שנועד לרקע-עמוד. במודל שורה-אחר-שורה של הקורא
/// אי אפשר לרנדר רקע-עמוד, וזה מופיע כבלוק ריק מבלבל — ולכן מדולג.
bool _isBehindDocDrawing(xml.XmlElement run) {
  for (final anchor in run.findAllElements('wp:anchor')) {
    final bd = anchor.getAttribute('behindDoc');
    if (bd == '1' || bd == 'true') return true;
  }
  return false;
}

/// מעבד גרפיקה ב-run ומחזיר HTML, או `null` אם אין.
///
/// - **תיבת-טקסט / שייפ עם טקסט** (`w:txbxContent`): הטקסט נעטף במסגרת
///   (`<div>` עם border). אם לשייפ יש גם תמונת-רקע — היא מוטמעת כ-
///   `background-image` (טקסט *על* התמונה). כך טקסט בתוך מסגרת לא נאבד.
/// - **תמונה בלבד**: `<img>` (data URI, offline).
/// - **מסגרת-רקע דקורטיבית** (`behindDoc`): מדולגת (ראו [_isBehindDocDrawing]).
String? _drawingHtmlFromRun(xml.XmlElement run, _DocxContext ctx) {
  // תמונת-רקע מאחורי הטקסט — לא ניתנת לרינדור כרקע-עמוד; מדלגים על התמונה
  // (אך עדיין מעבדים טקסט-בתיבה אם קיים, כדי לא לאבד תוכן).
  final imgUri = _isBehindDocDrawing(run)
      ? null
      : _imageUriFromRun(
          run,
          ctx.images,
          skipTextBoxContent: true,
          includeShapeFill: true,
        );

  // Word כותב את אותה תיבה פעמיים לתאימות (`mc:Choice` + `mc:Fallback`),
  // אך **שייף מקובץ** מכיל תיבות שונות באותו run. ההבחנה היא לפי התוכן:
  // לקיחת הראשונה בלבד מחקה את תיבות 2..N, ורינדור כולן שכפל את התאימות.
  final boxes = <xml.XmlElement>[];
  final seen = <String>{};
  for (final content in _textBoxContents(run)) {
    if (seen.add(content.innerText)) boxes.add(content);
  }

  // תיבה עם טקסט: עוטפים במסגרת (`<div>`), עם תמונת-הרקע אם קיימת. תיבה
  // ריקה מטקסט: נופלים לרינדור `<img>` הרגיל בהמשך — `<div>` ריק חסר גובה
  // ולא היה מציג את תמונת-הרקע ממילא.
  final rendered = <String>[];
  for (final txbx in boxes) {
    final parts = <String>[];
    for (final child in _collectChildren(txbx, const {'w:p', 'w:tbl'})) {
      if (child.name.qualified == 'w:p') {
        final inline = _renderParagraphInline(child, ctx);
        if (inline.trim().isNotEmpty) parts.add(inline.trim());
      } else {
        final nested = _buildTableHtml(child, ctx);
        if (nested != null) parts.add(nested);
      }
    }
    if (parts.isEmpty) continue;
    // תמונת-הרקע היא של השייף כולו, ולכן היא נמתחת על התיבה הראשונה בלבד.
    final bg = imgUri != null && rendered.isEmpty
        ? 'background-image: url($imgUri); background-size: contain; '
              'background-repeat: no-repeat; background-position: center; '
        : '';
    rendered.add(
      '<div style="${bg}border: 1px solid #999; '
      'padding: 8px; margin: 4px 0;">${parts.join('<br>')}</div>',
    );
  }
  if (rendered.isNotEmpty) return rendered.join();

  if (imgUri != null) return otzariaImage(imgUri);
  return null;
}

/// תגיות העיצוב של פורמט הטקסט של אוצריא, ללא מאפיינים (attributes).
/// מסמכי Word שנוצרו מהדבקת טקסט בפורמט אוצריא מכילים אותן כטקסט גלוי —
/// [escapeHtmlText] הופך אותן ל-`&lt;b&gt;` והקורא מציג אותן כטקסט משובש
/// (וב-RTL אף מבולגן ויזואלית). כאן הן מזוהות *אחרי* ההרכבה ומוחזרות
/// לתגיות אמיתיות.
final RegExp _otzariaTagEntityRegExp = RegExp(
  r'&lt;(/?)(b|i|u|big|small|sup|sub|br|h[1-6])&gt;',
  caseSensitive: false,
);

/// מחזיר תגיות אוצריא מילוליות (שעברו escape) לתגיות פעילות.
///
/// הזיהוי נעשה על טקסט הפסקה המורכב (ולא על כל run בנפרד) כדי לתפוס גם
/// תגית שפוצלה בין כמה runs ע"י Word — כל תו עבר escape בנפרד אך רצף
/// הישויות `&lt;h4&gt;` נשאר שלם לאחר האיחוד.
String _unescapeOtzariaTags(String text) {
  if (!text.contains('&lt;')) return text;
  return text.replaceAllMapped(
    _otzariaTagEntityRegExp,
    (m) => '<${m[1]}${m[2]}>',
  );
}

/// בודק מאפיין on/off של Word (`CT_OnOff`, וכן `w:u`): קיים *ומופעל*.
///
/// `w:val="false"/"0"/"off"/"none"` = כבוי — Word משתמש בזה כדי לבטל עיצוב
/// שעבר בירושה מהסגנון (למשל פסקה שמבטלת הדגשה של Heading). בלי הבדיקה הזו
/// `<w:b w:val="0"/>` היה נחשב מודגש בטעות, ו-`<w:u w:val="none"/>` קו תחתי.
bool _isOnOff(xml.XmlElement? el) {
  if (el == null) return false;
  final val = el.getAttribute('w:val');
  if (val == null) return true; // קיום בלי val = מופעל
  final v = val.toLowerCase();
  return v != 'false' && v != '0' && v != 'off' && v != 'none';
}

/// תגי הקו התחתי של run, לפי `w:u` (סוג/צבע/עובי).
({String open, String close}) _underlineTagsFor(xml.XmlElement u) {
  final val = (u.getAttribute('w:val') ?? 'single').toLowerCase();
  return underlineTags(
    kind: underlineKindFromName(val),
    color: cssColorForWordHex(u.getAttribute('w:color')),
    thick: val.contains('thick') || val.endsWith('heavy'),
  );
}

/// מקטע טקסט מעוצב בודד (run לאחר עיבוד). [open]/[close] הן תגיות העטיפה
/// (למשל `<b><span style="color:#X">` ו-`</span></b>`), ו-[text] הטקסט הפנימי.
///
/// המבנה הזה מאפשר *מיזוג* מקטעים סמוכים בעלי עטיפה זהה לפני בניית ה-HTML —
/// קריטי לביצועים: Word מפצל פסקה מעוצבת לעשרות runs זהים, ובלי מיזוג כל
/// אחד היה מקבל עותק מלא של תגיות העיצוב (ניפוח HTML/זיכרון של פי עשרות).
/// [raw] מסמן תוכן מוכן (סימון הערת שוליים) שאין לעטוף ואין למזג.
class _Seg {
  final String open;
  final String close;
  final String text;
  final bool raw;
  const _Seg(this.open, this.close, this.text) : raw = false;
  const _Seg.raw(this.text) : open = '', close = '', raw = true;
}

/// ממפה את *שם* סגנון הפסקה לרמת כותרת 1–6, או `null` אם אינו כותרת.
///
/// Word — וגם הייצוא של אוצריא עצמה — כותבים את הסגנון בשם (`Heading1`,
/// `Heading 2`, `Title`, `כותרת 1`) ולא במספר. הזיהוי הקודם השתמש ב-
/// `double.tryParse` ולכן פספס את *כל* הכותרות.
int? _headingLevelFromStyleName(String? styleVal) {
  if (styleVal == null) return null;
  final lower = styleVal.toLowerCase();
  if (lower == 'title') return 1;

  final en = RegExp(r'heading\s*([1-6])').firstMatch(lower);
  if (en != null) return int.parse(en.group(1)!);

  final he = RegExp(r'כותרת\s*([1-6])').firstMatch(styleVal);
  if (he != null) return int.parse(he.group(1)!);

  return null;
}

/// האם `w:outlineLvl` קיים עם ערך חוקי (0–9), כולל 9 שמבטל רמת מתאר.
bool _hasOutlineValue(String? val) {
  final level = val != null ? int.tryParse(val) : null;
  return level != null && level >= 0 && level <= 9;
}

/// ממיר `w:outlineLvl` לרמת כותרת 1–6, או `null` אם אינו כותרת.
///
/// ב-OOXML הערך 9 פירושו "Body Text" — ביטול *מפורש* של רמת מתאר, ולא כותרת
/// עמוקה. בלי הבדיקה כל פסקה כזו הייתה הופכת ל-`<h6>` ומזהמת את תוכן העניינים.
int? _headingLevelFromOutline(String? val) {
  final o = val != null ? int.tryParse(val) : null;
  if (o == null || o < 0 || o >= 9) return null;
  return (o + 1).clamp(1, 6);
}

/// מעבד run בודד ל-[_Seg] (עטיפה + טקסט), או `null` אם הוא ריק/מוסתר.
///
/// תומך ב-`w:br`/`w:tab` בתוך ה-run, ומזהה הדגשה/נטייה גם בווריאנט
/// complex-script (`w:bCs`/`w:iCs`) — קריטי לעברית. גופן (`w:rFonts`)
/// וצבע שחור/ברירת-מחדל מנוקים כדי לא לשבור את גופן הקריאה ואת מצב כהה.
///
/// תגיות העטיפה נבנות מבפנים החוצה (עילי/תחתי הכי פנימי, מודגש הכי חיצוני),
/// כך שכל run בעל אותו עיצוב מקבל [open] זהה וניתן למיזוג.
_Seg? _processRunSeg(xml.XmlElement node) {
  final rPr = node.getElement('w:rPr');

  // טקסט מוסתר (`w:vanish`) — לא מוצג (משמש לאינדקסים/הערות נסתרות).
  if (rPr != null && _isOnOff(rPr.getElement('w:vanish'))) {
    return null;
  }

  final buf = StringBuffer();
  for (final child in node.childElements) {
    switch (child.name.qualified) {
      case 'w:t':
        buf.write(escapeHtmlText(otzariaInlineText(child.innerText)));
      case 'w:br':
        buf.write('<br>');
      case 'w:tab':
        buf.write(' ');
    }
  }
  final text = buf.toString();
  if (text.isEmpty) return null;
  if (rPr == null) return _Seg('', '', text);

  // נצבר מבפנים החוצה; ה-open נבנה הפוך (חיצוני קודם), ה-close כסדר הצבירה.
  final opens = <String>[];
  final closes = <String>[];
  void wrap(String openTag, String closeTag) {
    opens.add(openTag);
    closes.add(closeTag);
  }

  // עילי/תחתי (`w:vertAlign`) — הכי פנימי, צמוד לטקסט.
  final vertAlign = rPr.getElement('w:vertAlign')?.getAttribute('w:val');
  if (vertAlign == 'superscript') {
    wrap('<sup>', '</sup>');
  } else if (vertAlign == 'subscript') {
    wrap('<sub>', '</sub>');
  }

  // צבע: רק צבע אמיתי (לא שחור/auto) — שחור שובר מצב כהה.
  final color = cssColorForWordHex(
    rPr.getElement('w:color')?.getAttribute('w:val'),
  );
  if (color != null) {
    final tags = colorTags(color);
    wrap(tags.open, tags.close);
  }

  // סימון/מרקר צבעוני (`w:highlight`) → רקע צבעוני. שחור מותר כאן: מרקר
  // שחור הוא בחירה מכוונת של המחבר, בשונה מצבע טקסט שחור שהוא ברירת מחדל.
  final bg = cssColorForWordName(
    rPr.getElement('w:highlight')?.getAttribute('w:val'),
    allowBlack: true,
  );
  if (bg != null) {
    final tags = highlightTags(bg);
    wrap(tags.open, tags.close);
  }

  // קו חוצה: כפול (`w:dstrike`) → line-through double; יחיד → `<s>`.
  final isDoubleStrike = _isOnOff(rPr.getElement('w:dstrike'));
  if (isDoubleStrike || _isOnOff(rPr.getElement('w:strike'))) {
    final tags = strikeTags(doubleLine: isDoubleStrike);
    wrap(tags.open, tags.close);
  }

  // קו תחתי — `w:u w:val="none"` מבטל. קו פשוט → `<u>`; סוג מותאם
  // (כפול/מנוקד/מקווקו/גלי/עבה/צבעוני) → `<span>` עם text-decoration.
  final u = rPr.getElement('w:u');
  if (_isOnOff(u)) {
    final tags = _underlineTagsFor(u!);
    wrap(tags.open, tags.close);
  }

  // נטוי — כולל וריאנט complex-script של עברית
  if (_isOnOff(rPr.getElement('w:i')) || _isOnOff(rPr.getElement('w:iCs'))) {
    wrap('<i>', '</i>');
  }

  // מודגש — כולל וריאנט complex-script של עברית (הכי חיצוני)
  if (_isOnOff(rPr.getElement('w:b')) || _isOnOff(rPr.getElement('w:bCs'))) {
    wrap('<b>', '</b>');
  }

  return _Seg(opens.reversed.join(), closes.join(), text);
}

/// בונה HTML ממקטעים (`_Seg`) עם מיזוג מקטעים סמוכים בעלי עטיפה זהה —
/// תגיות העיצוב נכתבות פעם אחת לכל רצף, במקום לכל run בנפרד (מונע ניפוח
/// HTML/זיכרון מ-runs מפוצלים של Word). מקטע raw (הערת שוליים, קישור) אינו
/// ממוזג. נקרא גם על תוכן פנימי של קישור, ולכן עומד לבד מ-[_renderParagraphInline].
String _buildSegsHtml(List<_Seg> segs) {
  final buf = StringBuffer();
  var i = 0;
  while (i < segs.length) {
    final s = segs[i];
    if (s.raw) {
      buf.write(s.text);
      i++;
      continue;
    }
    buf.write(s.open);
    buf.write(s.text);
    var j = i + 1;
    while (j < segs.length && !segs[j].raw && segs[j].open == s.open) {
      buf.write(segs[j].text);
      j++;
    }
    buf.write(s.close);
    i = j;
  }
  return buf.toString();
}

/// מוצא את `w:hyperlink` המכיל את [run], אם יש, בלי לחצות את גבול [paragraph]
/// (תיבת-טקסט מרונדרת בקריאה נפרדת שהפסקה שלה היא כבר `w:p` הפנימי, ולכן
/// הקישור העוטף את התיבה כולה אינו נראה משם — מחוץ לתחום המשימה הזו).
xml.XmlElement? _hyperlinkAncestor(
  xml.XmlElement run,
  xml.XmlElement paragraph,
) {
  xml.XmlNode? node = run.parent;
  while (node != null && node != paragraph) {
    if (node is xml.XmlElement && node.name.qualified == 'w:hyperlink') {
      return node;
    }
    node = node.parent;
  }
  return null;
}

/// כתובת היעד של `w:hyperlink`, מסוננת דרך [safeLinkTarget] (מקור יחיד
/// לאימות סכימה, משותף עם ODT ו-HTML) — או `null` אם אין יעד תקין.
///
/// `w:anchor` (סימניה פנימית) גובר: קישור עם שני המאפיינים אינו תקין ב-Word,
/// אך אם קרה — יעד פנימי עדיף על יעד שאולי אינו נפתר בכלל.
String? _resolveHyperlinkHref(xml.XmlElement hyperlink, _DocxContext ctx) {
  final anchor = hyperlink.getAttribute('w:anchor');
  if (anchor != null && anchor.isNotEmpty) {
    return safeLinkTarget('#$anchor');
  }
  final rId = hyperlink.getAttribute('r:id');
  final target = rId == null ? null : ctx.hyperlinkRels[rId];
  return target == null ? null : safeLinkTarget(target);
}

/// מרנדר את תוכן הפסקה (כל ה-runs לפי הסדר) כולל הערות שוליים inline
/// בפורמט שהקורא של אוצריא מציג כמפרש בצד:
///   `<sup class="footnote-marker">N</sup><i class="footnote">גוף</i>`
///
/// `w:hyperlink` עוטף היגד ב-`<a href="…">` (ראו [_resolveHyperlinkHref]):
/// ה-runs שבתוכו מזוהים לפי ההורה הקרוב ביותר ([_hyperlinkAncestor]) ונאספים
/// לקבוצה נפרדת, שתוכנה נבנה ונעטף כמקטע raw יחיד במקומו המקורי ברצף.
String _renderParagraphInline(xml.XmlElement paragraph, _DocxContext ctx) {
  // runs של תיבת-טקסט ושל הערה inline מעובדים בתוך היחידה שלהם; בלי דילוג
  // כאן `findAllElements` תופס אותם שוב והתוכן נפלט פעמיים.
  final nestedRuns = <xml.XmlElement>{};
  for (final tb in _textBoxContents(paragraph)) {
    nestedRuns.addAll(tb.findAllElements('w:r'));
  }
  for (final note in paragraph.findAllElements('w:footnote')) {
    nestedRuns.addAll(note.findAllElements('w:r'));
  }

  // שלב 1: איסוף מקטעים (segments) מכל ה-runs לפי הסדר.
  final segs = <_Seg>[];
  xml.XmlElement? currentLink;
  var linkSegs = <_Seg>[];

  void flushLink() {
    if (currentLink == null) return;
    final inner = _buildSegsHtml(linkSegs);
    if (inner.isNotEmpty) {
      final href = _resolveHyperlinkHref(currentLink!, ctx);
      segs.add(
        _Seg.raw(
          href == null
              ? inner
              : '<a href="${escapeHtmlAttribute(href)}">$inner</a>',
        ),
      );
    }
    currentLink = null;
    linkSegs = <_Seg>[];
  }

  for (final run in paragraph.findAllElements('w:r')) {
    if (nestedRuns.contains(run)) continue; // מעובד בתיבת-הטקסט / בהערה

    final link = _hyperlinkAncestor(run, paragraph);
    if (link != currentLink) {
      flushLink();
      currentLink = link;
    }
    final target = currentLink != null ? linkSegs : segs;

    final footnoteRef = run.getElement('w:footnoteReference');
    if (footnoteRef != null) {
      final id = footnoteRef.getAttribute('w:id');
      if (id != null && ctx.footnotes.containsKey(id)) {
        final n = ctx.footnoteCounter.next();
        target.add(
          _Seg.raw(otzariaFootnote('$n', escapeHtmlText(ctx.footnotes[id]!))),
        );
      }
      continue;
    }

    // WordML 2003 אינו מפריד את ההערות לחלק משלהן — גוף ההערה יושב בתוך
    // ה-run עצמו. בלי הטיפול כאן הוא היה זולג לגוף הפסקה כטקסט רגיל.
    final inlineFootnote = run.getElement('w:footnote');
    if (inlineFootnote != null) {
      final body = escapeHtmlText(inlineFootnote.innerText).trim();
      if (body.isNotEmpty) {
        final n = ctx.footnoteCounter.next();
        target.add(_Seg.raw(otzariaFootnote('$n', body)));
      }
      continue;
    }

    // גרפיקה: תיבת-טקסט (במסגרת, אולי על תמונת-רקע) או תמונה — מקטע raw.
    final drawingHtml = _drawingHtmlFromRun(run, ctx);
    if (drawingHtml != null) {
      target.add(_Seg.raw(drawingHtml));
      continue;
    }

    final seg = _processRunSeg(run);
    if (seg != null) target.add(seg);
  }
  flushLink(); // קישור שנמצא בסוף הפסקה, בלי run רגיל אחריו שיסגור אותו.

  // תגיות אוצריא שהוקלדו כטקסט במסמך (הדבקה מפורמט אוצריא) מופעלות כעיצוב.
  return _unescapeOtzariaTags(_buildSegsHtml(segs));
}

/// שם הסימניה (`w:bookmarkStart`) שבתוך [paragraph], אם היא יעד של קישור
/// פנימי כלשהו במסמך (`w:anchor` ב-[referencedAnchors]) — כדי לפלוט `id` על
/// הכותרת עצמה. תוכן העניינים האוטומטי של Word עוטף בדיוק כך: `bookmarkStart`
/// באותה פסקה של הכותרת שהוא מסמן.
String? _headingBookmarkId(
  xml.XmlElement paragraph,
  Set<String> referencedAnchors,
) {
  if (referencedAnchors.isEmpty) return null;
  for (final bookmark in paragraph.findAllElements('w:bookmarkStart')) {
    final name = bookmark.getAttribute('w:name');
    if (name != null && referencedAnchors.contains(name)) return name;
  }
  return null;
}

/// מעבד פסקה בודדת ומוסיף אותה ל-[output] (אם אינה ריקה).
/// מטפל בכותרות (לפי שם הסגנון/outlineLvl) וברשימות (קידומת תבליט).
void _processParagraph(
  xml.XmlElement paragraph,
  _DocxContext ctx,
  List<String> output,
) {
  var text = _renderParagraphInline(paragraph, ctx);
  if (text.trim().isEmpty) return;

  final pPr = paragraph.getElement('w:pPr');

  // כותרת: `outlineLvl` על הפסקה עצמה הוא עיצוב ישיר וגובר על הסגנון (כולל
  // 9 = "Body Text" שמבטל כותרת). בהיעדרו — שם הסגנון, ואז הגדרת הסגנון
  // ב-styles.xml (styleId מספרי / ירושת basedOn).
  final styleVal = pPr?.getElement('w:pStyle')?.getAttribute('w:val');
  final outlineVal = pPr?.getElement('w:outlineLvl')?.getAttribute('w:val');
  final level = _hasOutlineValue(outlineVal)
      ? _headingLevelFromOutline(outlineVal)
      : _headingLevelFromStyleName(styleVal) ??
            (styleVal != null ? ctx.headingStyles[styleVal] : null);

  if (level != null) {
    // trim: תווית תוכן העניינים נגזרת מטקסט הכותרת, ורווח מוביל/עוקב
    // (`xml:space="preserve"`) היה מייצר ערך TOC שונה לאותה כותרת בדיוק.
    final bookmarkId = _headingBookmarkId(paragraph, ctx.referencedAnchors);
    final idAttr = bookmarkId == null
        ? ''
        : ' id="${escapeHtmlAttribute(bookmarkId)}"';
    output.add('<h$level$idAttr>${text.trim()}</h$level>');
    return;
  }

  // רשימה: קידומת תבליט עם הזחה לפי רמת הקינון — לא `<ul>` (שנשבר בין שורות).
  // `w:numPr` ב-OOXML; `w:listPr` ב-WordML 2003, שם המזהה הוא `w:ilfo`
  // ו-Word אף כותב שם את התווית המחושבת עצמה ב-`wx:t`.
  final numPr = pPr?.getElement('w:numPr') ?? pPr?.getElement('w:listPr');
  if (numPr != null) {
    final numId =
        numPr.getElement('w:numId')?.getAttribute('w:val') ??
        numPr.getElement('w:ilfo')?.getAttribute('w:val');
    final ilvl =
        int.tryParse(numPr.getElement('w:ilvl')?.getAttribute('w:val') ?? '') ??
        0;
    // תווית שהמסמך עצמו חישב אמינה מכל שחזור שלנו מהגדרת הרשימה.
    final rendered = numPr.getElement('wx:t')?.getAttribute('wx:val')?.trim();
    final label = (rendered != null && rendered.isNotEmpty)
        ? escapeHtmlText(rendered)
        : ctx.listLabel(numId, ilvl);
    final indent = '    ' * ilvl;
    text = '$indent$label $text';
  }

  // יישור מפורש (`w:jc`). `both` נופל לברירת המחדל של אוצריא ואינו נעטף.
  // חל רק על פסקת גוף: כותרות כבר חזרו ב-return למעלה, כדי לא לעטוף `<h>`
  // ב-`<div>` (מה שהיה שובר את זיהוי הכותרות ב-TocParser).
  final align = _alignmentFromJc(
    pPr?.getElement('w:jc')?.getAttribute('w:val'),
    isRtl: _isOnOff(pPr?.getElement('w:bidi')),
  );
  if (align != null) {
    text = '<div style="text-align: $align;">$text</div>';
  }

  output.add(text);
}

/// ממיר `w:jc` ליישור CSS, או `null` כשאין יישור מפורש.
///
/// `start`/`end` הם יישור *לוגי* התלוי בכיוון הפסקה (`w:bidi`). Word 2013
/// ואילך כותב אותם במקום `left`/`right`, ולכן התעלמות מהם השאירה מסמכים
/// שלמים בלי שום יישור. בפסקה שכיוונה RTL הם **מדולגים**: מפיקי המסמכים
/// חלוקים בפירושם, והכרעה שגויה מיישרת קטע עברי שלם לצד ההפוך.
String? _alignmentFromJc(String? jc, {required bool isRtl}) => switch (jc) {
  'center' => 'center',
  'right' => 'right',
  'left' => 'left',
  'start' => isRtl ? null : 'left',
  'end' => isRtl ? null : 'right',
  _ => null,
};

/// מספר עמודות ה-grid שתא תופס (`w:gridSpan`, ברירת מחדל 1).
int _gridSpanOf(xml.XmlElement cell) {
  final v = cell
      .getElement('w:tcPr')
      ?.getElement('w:gridSpan')
      ?.getAttribute('w:val');
  return (v != null ? int.tryParse(v) : null) ?? 1;
}

/// אלמנט המיזוג האנכי של התא. WordML 2003 כותב `w:vmerge` באות קטנה,
/// ולכן החיפוש הוא לפי שם מקומי ללא תלות ברישיות.
xml.XmlElement? _vMergeOf(xml.XmlElement cell) {
  final tcPr = cell.getElement('w:tcPr');
  if (tcPr == null) return null;
  for (final child in tcPr.childElements) {
    if (child.name.local.toLowerCase() == 'vmerge') return child;
  }
  return null;
}

/// האם התא הוא המשך מיזוג אנכי (`w:vMerge` ללא `restart`) — כלומר ממוזג
/// עם התא שמעליו ואין לפלוט עבורו `<td>`.
bool _isVMergeContinue(xml.XmlElement cell) {
  final vm = _vMergeOf(cell);
  return vm != null && vm.getAttribute('w:val') != 'restart';
}

/// האם באותה עמדת grid יש מעל [row] תא שפותח את המיזוג ויבלע את ההמשך.
///
/// מטפסים מעל שרשרת תאי-ההמשך; התא הראשון שאינו המשך חייב להצהיר
/// `w:vMerge w:val="restart"`. תא רגיל אינו בולע דבר (ה-rowspan נספר רק
/// מ-`restart`), ולכן דילוג על ההמשך היה מוחק את תוכנו.
bool _hasVMergeStartAbove(
  List<xml.XmlElement> rows,
  int row,
  int gridPos,
) {
  for (var above = row - 1; above >= 0; above--) {
    final cell = _cellAtGridPos(rows[above], gridPos);
    if (cell == null) return false;
    if (_isVMergeContinue(cell)) continue;
    return _vMergeOf(cell)?.getAttribute('w:val') == 'restart';
  }
  return false;
}

/// אוסף ילדים ישירים מהסוגים שב-[tags], תוך פתיחה *שקופה* של בקרות-תוכן
/// (`w:sdt`) רקורסיבית. ב-Word שורות/תאים/בלוקים עלולים להיות עטופים ב-sdt,
/// ו-`findElements` ישיר היה מחמיץ אותם ומאבד תוכן.
List<xml.XmlElement> _collectChildren(xml.XmlElement parent, Set<String> tags) {
  final result = <xml.XmlElement>[];
  for (final child in parent.childElements) {
    final name = child.name.qualified;
    if (tags.contains(name)) {
      result.add(child);
    } else if (name == 'w:sdt') {
      final content = child.getElement('w:sdtContent');
      if (content != null) result.addAll(_collectChildren(content, tags));
    } else if (name == 'w:customXml') {
      result.addAll(_collectChildren(child, tags));
    }
  }
  return result;
}

/// מחזיר את התא שמתחיל בעמדת ה-grid [targetPos] בשורה [row], או `null`.
xml.XmlElement? _cellAtGridPos(xml.XmlElement row, int targetPos) {
  var pos = 0;
  for (final cell in _collectChildren(row, const {'w:tc'})) {
    if (pos == targetPos) return cell;
    pos += _gridSpanOf(cell);
    if (pos > targetPos) break;
  }
  return null;
}

/// מעבד טבלה ל-`<table>` אמיתי (שורה אחת ב-output, כי שורה=widget בקורא).
/// תומך ב: מיזוג אופקי (`gridSpan`→colspan) ואנכי (`vMerge`→rowspan), רקע
/// תאים (`w:shd`), יישור אנכי (`w:vAlign`), שורת כותרת (`w:tblHeader`→`<th>`),
/// וכיוון RTL (`w:bidiVisual`). מסגרות נוצרות ב-CSS (border-collapse).
void _processTable(
  xml.XmlElement table,
  _DocxContext ctx,
  List<String> output,
) {
  final html = _buildTableHtml(table, ctx);
  if (html != null) output.add(html);
}

/// בונה את ה-HTML של טבלה (`<table>…</table>`), או `null` אם ריקה. מופרד
/// מ-[_processTable] כדי לאפשר הטמעת טבלה מקוננת בתוך תא (recursion).
String? _buildTableHtml(xml.XmlElement table, _DocxContext ctx) {
  final rowEls = _collectChildren(table, const {'w:tr'});
  if (rowEls.isEmpty) return null;

  final isRtl = table.getElement('w:tblPr')?.getElement('w:bidiVisual') != null;

  final rows = StringBuffer();
  for (var r = 0; r < rowEls.length; r++) {
    final row = rowEls[r];
    final isHeader =
        row.getElement('w:trPr')?.getElement('w:tblHeader') != null;
    final tag = isHeader ? 'th' : 'td';

    final cellsBuf = StringBuffer();
    var colPos = 0;
    for (final cell in _collectChildren(row, const {'w:tc'})) {
      final span = _gridSpanOf(cell);

      // תא המשך-מיזוג-אנכי: מדולג (כלול ב-rowspan של התא העליון). בלי תא
      // פותח מעליו — טבלה שפוצלה בין מקטעים, או `w:vMerge` בשורה הראשונה —
      // אין מי שיבלע אותו, ודילוג היה מוחק את תוכנו.
      if (_isVMergeContinue(cell) && _hasVMergeStartAbove(rowEls, r, colPos)) {
        colPos += span;
        continue;
      }

      final tcPr = cell.getElement('w:tcPr');
      final vMergeVal = _vMergeOf(cell)?.getAttribute('w:val');

      // rowspan: אם זה restart, סופרים תאי-המשך בשורות הבאות באותה עמדה.
      var rowspan = 1;
      if (vMergeVal == 'restart') {
        for (var rr = r + 1; rr < rowEls.length; rr++) {
          final below = _cellAtGridPos(rowEls[rr], colPos);
          if (below != null && _isVMergeContinue(below)) {
            rowspan++;
          } else {
            break;
          }
        }
      }

      final shd = tcPr?.getElement('w:shd')?.getAttribute('w:fill');
      // הערכים מגיעים מתוך המסמך ונכנסים ל-`style="…"`; בלי סינון, ערך
      // שמכיל גרש נחלץ מהמאפיין ומזריק תגיות משלו לגוף הספר — ומשם הן
      // מגיעות גם לתוכן העניינים ולאינדקס.
      final vAlign = cssVerticalAlign(
        tcPr?.getElement('w:vAlign')?.getAttribute('w:val'),
      );

      final attrs = StringBuffer();
      if (span > 1) attrs.write(' colspan="$span"');
      if (rowspan > 1) attrs.write(' rowspan="$rowspan"');
      final styles = <String>['border: 1px solid #999', 'padding: 4px 8px'];
      if (shd != null) {
        final f = shd.toLowerCase();
        final fill = f == 'auto' || f == 'ffffff'
            ? null
            : sanitizeCssColor('#$shd');
        if (fill != null) styles.add('background-color: $fill');
      }
      if (vAlign != null) styles.add('vertical-align: $vAlign');
      attrs.write(' style="${styles.join('; ')}"');

      // תוכן התא: פסקאות וטבלאות מקוננות לפי הסדר (גם אם עטופות ב-sdt),
      // כדי לא לאבד תוכן מקונן.
      final parts = <String>[];
      for (final child in _collectChildren(cell, const {'w:p', 'w:tbl'})) {
        if (child.name.qualified == 'w:p') {
          final inline = _renderParagraphInline(child, ctx);
          if (inline.trim().isNotEmpty) parts.add(inline.trim());
        } else {
          final nested = _buildTableHtml(child, ctx);
          if (nested != null) parts.add(nested);
        }
      }

      cellsBuf.write('<$tag$attrs>${parts.join('<br>')}</$tag>');
      colPos += span;
    }

    if (cellsBuf.isNotEmpty) rows.write('<tr>$cellsBuf</tr>');
  }

  if (rows.isEmpty) return null;
  final dir = isRtl ? ' dir="rtl"' : '';
  return '${otzariaTableOpen(attributes: dir)}$rows</table>';
}

/// טקסט הערת שוליים כשורה אחת.
///
/// גבול פסקה, `w:br` ו-`w:tab` הופכים לרווח: חיבור כל ה-`w:t` במחרוזת ריקה
/// מדביק את המילה האחרונה של פסקה אחת לראשונה של הבאה, והחיפוש על הצירוף
/// מפסיק למצוא. אותה תבנית בדיוק בממירי ODT ו-Word הבינארי.
String _footnoteText(xml.XmlElement footnote) {
  final buffer = StringBuffer();
  for (final node in footnote.descendantElements) {
    switch (node.name.qualified) {
      case 'w:t':
        buffer.write(node.innerText);
      case 'w:p':
      case 'w:br':
      case 'w:tab':
        buffer.write(' ');
    }
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Extracts footnotes from the document
Map<String, String> _extractFootnotes(Archive archive) {
  final footnotes = <String, String>{};

  for (final file in archive) {
    if (file.isFile && file.name == 'word/footnotes.xml') {
      try {
        // הערות השוליים הן תוכן הספר, ולכן הן עוברות את אימות הגודל בפועל
        // כמו גוף המסמך; styles/numbering הם מטא-דאטה ונסבלים.
        final content = _decodeXmlBytes(
          readArchiveEntry(file, format: DocumentFormat.docx),
        );
        final document = xml.XmlDocument.parse(content);

        final footnoteNodes = document.findAllElements('w:footnote');
        for (final footnote in footnoteNodes) {
          final id = footnote.getAttribute('w:id');
          if (id != null && id != '-1' && id != '0') {
            // Skip automatic footnotes
            footnotes[id] = _footnoteText(footnote);
          }
        }
      } catch (_) {
        // footnotes.xml פגום — ממשיכים בלי הערות במקום לקרוס.
      }
      break;
    }
  }

  return footnotes;
}

/// ממיר מסמך Word מבוסס OOXML (DOCX/DOCM/DOTX/DOTM) לטקסט של אוצריא.
/// מסמן כותרות, רשימות ועיצוב, ומשלב הערות שוליים inline.
///
/// כל ארבעת הפורמטים חולקים את אותו מבנה חבילה (`word/document.xml`,
/// `styles.xml`, `numbering.xml`) ולכן את אותו מנוע. [format] נשמר בחוזה כדי
/// שההבחנה תישמר בשגיאות ובמטמון — ולא כדי לגזור ממנו התנהגות המרה.
///
/// [embedImages] כבוי משמיט את ה-base64 ומשאיר את תגי התמונה — ראו
/// [_extractImages].
String ooxmlWordToText(
  Uint8List bytes,
  String title, {
  required DocumentFormat format,
  bool embedImages = true,
}) {
  assert(
    format.isOoxmlWord,
    'ooxmlWordToText נקרא עם ${format.extension} שאינו OOXML Word',
  );
  // מופע מקומי ולא מודולרי: `ZipDecoder` שומר מצב ומחזיק את חוצץ הבייטים של
  // המסמך האחרון לכל אורך חיי ה-isolate. גם התועלת אפסית — כל המרה רצה
  // ב-`Isolate.run` נפרד, וסטטיקה היא פר-isolate.
  // חבילת OOXML מוצפנת אינה ZIP אלא מכולת OLE. בלעדי הבדיקה היא נדחית
  // כ"קובץ פגום", והמשתמש מחפש שיבוש שאינו קיים.
  if (hasOleContainerSignature(bytes)) {
    throw EncryptedDocumentException(
      format: format,
      cause: 'החבילה מוצפנת (מכולת OLE במקום ZIP)',
    );
  }
  // ה-decode על ZIP פגום זורק `RangeError` — חריגה שאינה
  // [DocumentConversionException] ולכן בורחת מכל מטפל בצנרת ומפילה סריקה
  // שלמה בגלל ספר אחד.
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    throw CorruptedDocumentException(format: format, cause: e);
  }
  // מפענח ה-ZIP סובלני ומחזיר ארכיון ריק על קלט שאינו ZIP כלל. בלי הבדיקה
  // הזו קובץ טקסט ששמו .docx היה נפתח כספר ריק במקום לדווח על שגיאה.
  if (archive.isEmpty) {
    throw CorruptedDocumentException(
      format: format,
      cause: 'החבילה אינה ארכיון ZIP תקין',
    );
  }
  assertSafeArchive(archive, format: format);
  return ooxmlWordArchiveToText(
    archive,
    title,
    format: format,
    embedImages: embedImages,
  );
}

/// ממיר חבילת OOXML **שכבר נפרסה** לטקסט של אוצריא.
///
/// נקודת הכניסה של פורמט Flat OPC (‎.xml‎), שאין לו ZIP לפרוס: הוא בונה את
/// אותה [Archive] מתוך רשומות ה-XML ומגיע לאותו מנוע בדיוק.
String ooxmlWordArchiveToText(
  Archive archive,
  String title, {
  required DocumentFormat format,
  bool embedImages = true,
}) {
  final List<String> list = [
    otzariaInlineText('<h1>${escapeHtmlText(title)}</h1>'),
  ];

  // גוף המסמך חסר או אינו קריא = כשל מפורש. פלט "כותרת בלבד" נראה כמו ספר
  // תקין וריק: הוא נשמר במטמון, מאונדקס, ומסמן כל הערה אישית כחסרה.
  final entry = archive.files.firstWhere(
    (file) => file.isFile && file.name == 'word/document.xml',
    orElse: () => throw CorruptedDocumentException(
      format: format,
      cause: 'אין word/document.xml בחבילה',
    ),
  );

  final xml.XmlDocument document;
  try {
    document = xml.XmlDocument.parse(
      _decodeXmlBytes(readArchiveEntry(entry, format: format)),
    );
  } catch (e) {
    if (e is DocumentConversionException) rethrow;
    throw CorruptedDocumentException(
      format: format,
      cause: 'word/document.xml אינו קריא: $e',
    );
  }

  final body = document.rootElement.getElement('w:body');
  if (body == null) {
    throw CorruptedDocumentException(
      format: format,
      cause: 'ל-word/document.xml אין w:body',
    );
  }

  final ctx = _DocxContext(
    _extractFootnotes(archive),
    _extractImages(archive, embedImages: embedImages),
    _extractNumbering(archive),
    _extractHeadingStyles(archive),
    _extractHyperlinkRels(archive),
    _collectHyperlinkAnchors(body),
  );
  _processBlockChildren(body.childElements, ctx, list);

  return list.join('\n');
}

/// ממיר DOCX. wrapper דק מעל [ooxmlWordToText] — קיים כדי שקוראים ותיקים
/// (וטסטים) לא ישתנו.
String docxToText(Uint8List bytes, String title) =>
    ooxmlWordToText(bytes, title, format: DocumentFormat.docx);

// ── WordML 2003 ───────────────────────────────────────────────────────────

/// ממיר מסמך **WordprocessingML 2003** (‎.xml‎ עם שורש `w:wordDocument`).
///
/// הדיאלקט חולק עם OOXML את כל אוצר-המילים של הגוף (`w:p`, `w:r`, `w:rPr`,
/// `w:tbl`) ולכן את אותו מנוע רינדור. שונים רק מקורות המשאבים: הסגנונות,
/// הרשימות, התמונות וההערות יושבים כולם **בתוך אותו מסמך** ולא בקבצים
/// נפרדים בחבילה.
String wordMl2003ToText(
  xml.XmlDocument document,
  String title, {
  required DocumentFormat format,
  bool embedImages = true,
}) {
  final root = document.rootElement;
  final body = root.getElement('w:body');
  if (body == null) {
    throw CorruptedDocumentException(
      format: format,
      cause: 'אין w:body במסמך WordML',
    );
  }

  final ctx = _DocxContext(
    // ההערות אינן חלק נפרד — הן inline, ומטופלות ב-_renderParagraphInline.
    const {},
    _extractWordMlImages(root, embedImages: embedImages),
    _extractWordMlNumbering(root),
    _headingStylesFrom(document),
    // אין קובץ יחסים בדיאלקט הזה — קישור חיצוני (r:id) אינו נפתר, רק פנימי.
    const {},
    _collectHyperlinkAnchors(body),
  );

  final list = <String>[
    otzariaInlineText('<h1>${escapeHtmlText(title)}</h1>'),
  ];
  _processBlockChildren(body.childElements, ctx, list);
  return list.join('\n');
}

/// אוסף את התמונות המוטמעות של WordML 2003 (`w:binData`) כ-data URI.
/// המפתח הוא השם שמופיע ב-`v:imagedata src` (`wordml://…`).
Map<String, String> _extractWordMlImages(
  xml.XmlElement root, {
  required bool embedImages,
}) {
  final images = <String, String>{};
  var embeddedBytes = 0;
  for (final data in root.descendantElements) {
    if (data.name.local != 'binData') continue;
    final name = data.getAttribute('w:name');
    if (name == null) continue;
    final mime = imageMimeForPath(name);
    if (mime == null) continue;
    if (!embedImages) {
      images[name] = '';
      continue;
    }
    // ה-base64 שבמסמך גדול פי ~4/3 מהתמונה; התקרה נבדקת על הגודל המפוענח.
    final encoded = data.innerText.replaceAll(RegExp(r'\s'), '');
    if (encoded.length ~/ 4 * 3 > EmbeddedMediaLimits.maxImageBytes ||
        embeddedBytes + encoded.length ~/ 4 * 3 >
            EmbeddedMediaLimits.maxTotalImageBytes) {
      images[name] = '';
      continue;
    }
    // base64 פגום זורק — תמונה אחת אינה שווה כשל של המסמך כולו.
    try {
      embeddedBytes += base64Decode(encoded).length;
      images[name] = 'data:$mime;base64,$encoded';
    } catch (_) {
      images[name] = '';
    }
  }
  return images;
}

/// בונה את מפת הרשימות של WordML 2003: `ilfo` → (`ilvl` → הגדרה).
///
/// המבנה מקביל ל-numbering.xml אך בשמות אחרים: `w:listDef` במקום
/// `w:abstractNum`, ו-`w:nfc` (קוד מספרי) במקום `w:numFmt` (שם).
Map<String, Map<int, _NumLevel>> _extractWordMlNumbering(xml.XmlElement root) {
  final lists = root.getElement('w:lists');
  if (lists == null) return const {};

  final defs = <String, Map<int, _NumLevel>>{};
  for (final def in lists.findElements('w:listDef')) {
    final id = def.getAttribute('w:listDefId');
    if (id == null) continue;
    final levels = <int, _NumLevel>{};
    for (final lvl in def.findElements('w:lvl')) {
      final ilvl = int.tryParse(lvl.getAttribute('w:ilvl') ?? '');
      if (ilvl == null) continue;
      levels[ilvl] = _NumLevel(
        _numberFormatForNfc(lvl.getElement('w:nfc')?.getAttribute('w:val')),
        lvl.getElement('w:lvlText')?.getAttribute('w:val') ?? '',
        int.tryParse(lvl.getElement('w:start')?.getAttribute('w:val') ?? '') ??
            1,
      );
    }
    defs[id] = levels;
  }

  final result = <String, Map<int, _NumLevel>>{};
  for (final list in lists.findElements('w:list')) {
    final ilfo = list.getAttribute('w:ilfo');
    final defId = list.getElement('w:ilst')?.getAttribute('w:val');
    if (ilfo != null && defId != null && defs.containsKey(defId)) {
      result[ilfo] = defs[defId]!;
    }
  }
  return result;
}

/// קודי `MSONFC` → שמות `w:numFmt`, כדי שמנוע המספור יישאר אחד.
String _numberFormatForNfc(String? nfc) => switch (int.tryParse(nfc ?? '')) {
  0 => 'decimal',
  1 => 'upperRoman',
  2 => 'lowerRoman',
  3 => 'upperLetter',
  4 => 'lowerLetter',
  22 => 'decimalZero',
  23 => 'bullet',
  45 || 47 => 'hebrew1',
  255 => 'none',
  _ => 'decimal',
};

/// מעבד רצף אלמנטי-בלוק (ילדי body / sdtContent) *לפי הסדר*: פסקאות,
/// טבלאות, ובקרות-תוכן (`w:sdt`). ה-sdt עטיפה שקופה — יורדים ל-`w:sdtContent`
/// ומעבדים את ילדיו רקורסיבית, כדי לא לאבד תוכן שעטוף בבקרת-תוכן (טפסים).
void _processBlockChildren(
  Iterable<xml.XmlElement> children,
  _DocxContext ctx,
  List<String> output,
) {
  for (final element in children) {
    switch (element.name.qualified) {
      case 'w:p':
        _processParagraph(element, ctx, output);
      case 'w:tbl':
        _processTable(element, ctx, output);
      case 'w:sdt':
        final content = element.getElement('w:sdtContent');
        if (content != null) {
          _processBlockChildren(content.childElements, ctx, output);
        }
      // עטיפות שקופות: `w:customXml` מגיע ממסמכי Word 2003, מטפסים וממערכות
      // DMS, ו-`wx:sect` מ-WordML 2003. בלי הירידה דרכן תוכנן נמחק בשקט.
      case 'w:customXml':
      case 'wx:sect':
      case 'wx:sub-section':
        _processBlockChildren(element.childElements, ctx, output);
    }
  }
}
