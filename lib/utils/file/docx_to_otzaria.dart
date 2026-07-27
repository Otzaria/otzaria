import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart' as xml;
import 'dart:convert';

/// גרסת הממיר [docxToText]. **חובה להעלות ערך זה בכל שינוי שמשפיע על הפלט**
/// (עיצוב, כותרות, תמונות, טבלאות…). מטמון התוכן ([convertDocxWithCache])
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
/// v9: כותרות עם styleId מספרי (Word בעברית / המרה מ-HTML) לפי styles.xml,
/// ו-`outlineLvl=9` ("Body Text") אינו נחשב עוד לכותרת.
const int kDocxConverterVersion = 9;

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

ZipDecoder? _zipDecoder;

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

  final _FootnoteCounter footnoteCounter = _FootnoteCounter();

  /// מונים רצים לרשימות: `numId` → (`ilvl` → הערך הנוכחי).
  final Map<String, Map<int, int>> _listCounters = {};

  _DocxContext(
    this.footnotes,
    this.images,
    this.numbering,
    this.headingStyles,
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
      return _toLetters(n, upper: false);
    case 'upperLetter':
      return _toLetters(n, upper: true);
    case 'lowerRoman':
      return _toRoman(n).toLowerCase();
    case 'upperRoman':
      return _toRoman(n);
    case 'hebrew1':
    case 'hebrew2':
      return _toHebrewNumeral(n);
    case 'none':
      return '';
    case 'decimal':
    default:
      return '$n';
  }
}

/// 1→a, 26→z, 27→aa … (bijective base-26).
String _toLetters(int n, {required bool upper}) {
  if (n <= 0) return '$n';
  final base = upper ? 65 : 97;
  final chars = <int>[];
  var x = n;
  while (x > 0) {
    x--;
    chars.add(base + (x % 26));
    x ~/= 26;
  }
  return String.fromCharCodes(chars.reversed);
}

/// ממיר מספר למספרה רומית (1–3999), אחרת מחזיר ספרות.
String _toRoman(int n) {
  if (n <= 0 || n > 3999) return '$n';
  const vals = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
  const syms = [
    'M',
    'CM',
    'D',
    'CD',
    'C',
    'XC',
    'L',
    'XL',
    'X',
    'IX',
    'V',
    'IV',
    'I',
  ];
  final buf = StringBuffer();
  var x = n;
  for (var i = 0; i < vals.length; i++) {
    while (x >= vals[i]) {
      buf.write(syms[i]);
      x -= vals[i];
    }
  }
  return buf.toString();
}

/// ממיר מספר לאות עברית (גימטרייה) ללא גרשיים — למספור רשימות `hebrew1`.
/// מדויק עד 499; מעבר לכך נופל לספרות (רשימות ארוכות כאלה נדירות).
String _toHebrewNumeral(int n) {
  if (n <= 0 || n > 499) return '$n';
  const ones = ['', 'א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ז', 'ח', 'ט'];
  const tens = ['', 'י', 'כ', 'ל', 'מ', 'נ', 'ס', 'ע', 'פ', 'צ'];
  const hundreds = ['', 'ק', 'ר', 'ש', 'ת'];
  final buf = StringBuffer();
  var x = n;
  if (x >= 100) {
    buf.write(hundreds[x ~/ 100]);
    x %= 100;
  }
  if (x == 15) {
    buf.write('טו');
  } else if (x == 16) {
    buf.write('טז');
  } else {
    if (x >= 10) {
      buf.write(tens[x ~/ 10]);
      x %= 10;
    }
    if (x > 0) buf.write(ones[x]);
  }
  return buf.toString();
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
    doc = xml.XmlDocument.parse(_decodeXmlBytes(numFile.content));
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
Map<String, int> _extractHeadingStyles(Archive archive) {
  ArchiveFile? stylesFile;
  for (final f in archive) {
    if (f.isFile && f.name == 'word/styles.xml') {
      stylesFile = f;
      break;
    }
  }
  if (stylesFile == null) return const {};

  final xml.XmlDocument doc;
  try {
    doc = xml.XmlDocument.parse(_decodeXmlBytes(stylesFile.content));
  } catch (_) {
    return const {};
  }

  final result = <String, int>{};
  for (final style in doc.findAllElements('w:style')) {
    final type = style.getAttribute('w:type');
    if (type != null && type != 'paragraph') continue;
    final id = style.getAttribute('w:styleId');
    if (id == null) continue;

    final level =
        _headingLevelFromStyleName(
          style.getElement('w:name')?.getAttribute('w:val'),
        ) ??
        _headingLevelFromOutline(
          style
              .getElement('w:pPr')
              ?.getElement('w:outlineLvl')
              ?.getAttribute('w:val'),
        );
    if (level != null) result[id] = level;
  }
  return result;
}

/// מחזיר את ה-MIME של תמונה לפי סיומת, או `null` אם הקורא לא יודע לרנדר
/// אותה (EMF/WMF/TIFF — פורמטים ישנים של Word שאינם נתמכים ב-HtmlWidget).
String? _imageMime(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.png')) return 'image/png';
  if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
  if (p.endsWith('.gif')) return 'image/gif';
  if (p.endsWith('.bmp')) return 'image/bmp';
  if (p.endsWith('.webp')) return 'image/webp';
  return null;
}

/// בונה מפת `rId` → `data:` URI עבור כל התמונות המוטמעות בקובץ — קריאה
/// אחת של ה-relationships + קבצי ה-media, והמרה ל-base64. הטמעה מלאה
/// (offline) ולא קישור חיצוני. פורמטים שהקורא לא תומך בהם מדולגים בשקט.
Map<String, String> _extractImages(Archive archive) {
  // שלב 1: rId → target ("media/imageN.png"), רק יחסים מסוג image.
  final rels = <String, String>{};
  for (final file in archive) {
    if (file.isFile && file.name == 'word/_rels/document.xml.rels') {
      try {
        final doc = xml.XmlDocument.parse(_decodeXmlBytes(file.content));
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
  rels.forEach((id, target) {
    final mime = _imageMime(target);
    if (mime == null) return; // פורמט לא נתמך
    final fullPath = target.startsWith('/')
        ? target.substring(1)
        : 'word/$target';
    final file = mediaByPath[fullPath];
    if (file == null) return; // קובץ חסר
    images[id] = 'data:$mime;base64,${base64Encode(file.content)}';
  });
  return images;
}

/// מחזיר את ה-data URI של תמונה מוטמעת ב-run (DrawingML `a:blip` או VML
/// `v:imagedata`), או `null`.
String? _imageUriFromRun(
  xml.XmlElement run,
  Map<String, String> images, {
  bool skipTextBoxContent = false,
}) {
  if (images.isEmpty) return null;
  String? visit(xml.XmlElement element) {
    if (skipTextBoxContent && element.name.qualified == 'w:txbxContent') {
      return null;
    }
    if (element.name.qualified == 'a:blip') {
      final id =
          element.getAttribute('r:embed') ?? element.getAttribute('r:link');
      final uri = id == null ? null : images[id];
      if (uri != null) return uri;
    }
    if (element.name.qualified == 'v:imagedata') {
      final id = element.getAttribute('r:id');
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
      : _imageUriFromRun(run, ctx.images, skipTextBoxContent: true);

  xml.XmlElement? txbx;
  for (final t in run.findAllElements('w:txbxContent')) {
    txbx = t;
    break;
  }

  if (txbx != null) {
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
    // תיבה עם טקסט: עוטפים במסגרת (`<div>`), עם תמונת-הרקע אם קיימת.
    // תיבה ריקה מטקסט: נופלים לרינדור `<img>` הרגיל בהמשך — `<div>` ריק חסר
    // גובה ולא היה מציג את תמונת-הרקע ממילא.
    if (parts.isNotEmpty) {
      final bg = imgUri != null
          ? 'background-image: url($imgUri); background-size: contain; '
                'background-repeat: no-repeat; background-position: center; '
          : '';
      return '<div style="${bg}border: 1px solid #999; '
          'padding: 8px; margin: 4px 0;">${parts.join('<br>')}</div>';
    }
  }

  if (imgUri != null) return '<img src="$imgUri" style="max-width: 100%;"/>';
  return null;
}

/// Escape של תווי HTML בתוכן *טקסט* (לא בתגיות שאנו מוסיפים), כדי שתוכן
/// שמכיל `<`/`>`/`&` (נוסחאות, סוגריים מחודדים, "ר' & ...") לא ישבור את
/// הרנדור — `HtmlWidget` היה מפרש `<` כתחילת תגית ומבלגן את כל המשך הפסקה.
String _escapeHtml(String s) {
  if (!s.contains('&') && !s.contains('<') && !s.contains('>')) return s;
  return s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

/// גרסה ציבורית של [_escapeHtml] — לשימוש בהזרקת כותרת הספר במטמון
/// (`docx_cache`), כדי ששם קובץ עם `<`/`&` לא ישבור את ה-HTML.
String escapeHtmlText(String s) => _escapeHtml(s);

/// תגיות העיצוב של פורמט הטקסט של אוצריא, ללא מאפיינים (attributes).
/// מסמכי Word שנוצרו מהדבקת טקסט בפורמט אוצריא מכילים אותן כטקסט גלוי —
/// [_escapeHtml] הופך אותן ל-`&lt;b&gt;` והקורא מציג אותן כטקסט משובש
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

/// ממיר ערך `w:highlight` (מרקר צבעוני) לצבע CSS, או `null` אם אין/לבטל.
///
/// רוב 16 ערכי ה-highlight של Word הם שמות צבע תקניים ב-CSS
/// (`yellow`, `darkblue`, `lightgray`...). היוצא דופן הוא `darkYellow`
/// שאין לו שם CSS — ממופה ל-HEX. `none` = ללא סימון.
String? _highlightColor(String val) {
  final v = val.toLowerCase();
  if (v == 'none') return null;
  if (v == 'darkyellow') return '#808000';
  return v;
}

/// ממפה ערך `w:u w:val` (סוג הקו התחתי של Word) לערך `text-decoration-style`
/// של CSS שהקורא תומך בו (`solid`/`double`/`dotted`/`dashed`/`wavy`).
/// `single`/`thick`/`words` → `solid` (מוחזר `null` כדי לחסוך style מיותר).
String? _underlineStyleCss(String val) {
  final v = val.toLowerCase();
  if (v == 'double') return 'double';
  if (v.startsWith('wav')) return 'wavy'; // wave, wavyHeavy, wavyDouble
  if (v.startsWith('dot')) return 'dotted'; // dotted, dottedHeavy, dotDash…
  if (v.startsWith('dash')) return 'dashed'; // dash, dashLong, dashedHeavy…
  return null; // single, thick, words, solid
}

/// בונה את ה-CSS של קו תחתי מותאם (סוג/צבע/עובי) עבור `<span>`, או `null`
/// כשמדובר בקו פשוט (single) ללא צבע — שאז עדיף `<u>` (שניתן למזג).
String? _underlineSpanStyle(xml.XmlElement u) {
  final val = u.getAttribute('w:val') ?? 'single';
  final color = u.getAttribute('w:color');
  final styleCss = _underlineStyleCss(val);
  final isThick =
      val.toLowerCase().contains('thick') ||
      val.toLowerCase().endsWith('heavy');
  final hasColor = color != null && color.toLowerCase() != 'auto';

  if (styleCss == null && !isThick && !hasColor) return null; // קו פשוט → <u>

  final css = StringBuffer('text-decoration: underline');
  if (styleCss != null) css.write(' $styleCss');
  css.write(';');
  if (hasColor) css.write(' text-decoration-color: #$color;');
  if (isThick) css.write(' text-decoration-thickness: 2px;');
  return css.toString();
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
        buf.write(_escapeHtml(child.innerText));
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
  final color = rPr.getElement('w:color')?.getAttribute('w:val');
  if (color != null) {
    final c = color.toLowerCase();
    if (c != '000000' && c != 'auto') {
      wrap('<span style="color:#$color">', '</span>');
    }
  }

  // סימון/מרקר צבעוני (`w:highlight`) → רקע צבעוני.
  final highlight = rPr.getElement('w:highlight')?.getAttribute('w:val');
  if (highlight != null) {
    final bg = _highlightColor(highlight);
    if (bg != null) wrap('<span style="background-color:$bg">', '</span>');
  }

  // קו חוצה: כפול (`w:dstrike`) → line-through double; יחיד → `<s>`.
  if (_isOnOff(rPr.getElement('w:dstrike'))) {
    wrap('<span style="text-decoration: line-through double;">', '</span>');
  } else if (_isOnOff(rPr.getElement('w:strike'))) {
    wrap('<s>', '</s>');
  }

  // קו תחתי — `w:u w:val="none"` מבטל. קו פשוט → `<u>`; סוג מותאם
  // (כפול/מנוקד/מקווקו/גלי/עבה/צבעוני) → `<span>` עם text-decoration.
  final u = rPr.getElement('w:u');
  if (_isOnOff(u)) {
    final spanStyle = _underlineSpanStyle(u!);
    wrap(
      spanStyle == null ? '<u>' : '<span style="$spanStyle">',
      spanStyle == null ? '</u>' : '</span>',
    );
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

/// מרנדר את תוכן הפסקה (כל ה-runs לפי הסדר) כולל הערות שוליים inline
/// בפורמט שהקורא של אוצריא מציג כמפרש בצד:
///   `<sup class="footnote-marker">N</sup><i class="footnote">גוף</i>`
String _renderParagraphInline(xml.XmlElement paragraph, _DocxContext ctx) {
  // runs שבתוך תיבות-טקסט (`w:txbxContent`) מעובדים *בתוך* התיבה (ב-
  // _drawingHtmlFromRun), לא inline — אחרת findAllElements היה תופס אותם
  // פעמיים. אוספים אותם לדילוג.
  final txbxRuns = <xml.XmlElement>{};
  for (final tb in paragraph.findAllElements('w:txbxContent')) {
    txbxRuns.addAll(tb.findAllElements('w:r'));
  }

  // שלב 1: איסוף מקטעים (segments) מכל ה-runs לפי הסדר.
  final segs = <_Seg>[];
  for (final run in paragraph.findAllElements('w:r')) {
    if (txbxRuns.contains(run)) continue; // מעובד בתוך תיבת-הטקסט

    final footnoteRef = run.getElement('w:footnoteReference');
    if (footnoteRef != null) {
      final id = footnoteRef.getAttribute('w:id');
      if (id != null && ctx.footnotes.containsKey(id)) {
        final n = ctx.footnoteCounter.next();
        segs.add(
          _Seg.raw(
            '<sup class="footnote-marker">$n</sup>'
            '<i class="footnote">${_escapeHtml(ctx.footnotes[id]!)}</i>',
          ),
        );
      }
      continue;
    }

    // גרפיקה: תיבת-טקסט (במסגרת, אולי על תמונת-רקע) או תמונה — מקטע raw.
    final drawingHtml = _drawingHtmlFromRun(run, ctx);
    if (drawingHtml != null) {
      segs.add(_Seg.raw(drawingHtml));
      continue;
    }

    final seg = _processRunSeg(run);
    if (seg != null) segs.add(seg);
  }

  // שלב 2: בנייה עם מיזוג מקטעים סמוכים בעלי עטיפה זהה — תגיות העיצוב
  // נכתבות פעם אחת לכל רצף, במקום לכל run בנפרד (מונע ניפוח HTML/זיכרון
  // מ-runs מפוצלים של Word). מקטע raw (הערת שוליים) אינו ממוזג.
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
  // תגיות אוצריא שהוקלדו כטקסט במסמך (הדבקה מפורמט אוצריא) מופעלות כעיצוב.
  return _unescapeOtzariaTags(buf.toString());
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

  // כותרת: קודם לפי שם הסגנון, אחרת לפי הגדרת הסגנון ב-styles.xml (styleId
  // מספרי), ולבסוף גיבוי שפה-אגנוסטי דרך outlineLvl של הפסקה עצמה.
  final styleVal = pPr?.getElement('w:pStyle')?.getAttribute('w:val');
  final level =
      _headingLevelFromStyleName(styleVal) ??
      (styleVal != null ? ctx.headingStyles[styleVal] : null) ??
      _headingLevelFromOutline(
        pPr?.getElement('w:outlineLvl')?.getAttribute('w:val'),
      );

  if (level != null) {
    output.add('<h$level>$text</h$level>');
    return;
  }

  // רשימה: קידומת תבליט עם הזחה לפי רמת הקינון — לא `<ul>` (שנשבר בין שורות).
  final numPr = pPr?.getElement('w:numPr');
  if (numPr != null) {
    final numId = numPr.getElement('w:numId')?.getAttribute('w:val');
    final ilvl =
        int.tryParse(numPr.getElement('w:ilvl')?.getAttribute('w:val') ?? '') ??
        0;
    final label = ctx.listLabel(numId, ilvl);
    final indent = '    ' * ilvl;
    text = '$indent$label $text';
  }

  // יישור מפורש (`w:jc`) — center/right/left. `both`/`start`/`end` נופלים
  // לברירת המחדל של אוצריא (justify ב-RTL) ולכן אינם נעטפים.
  // חל רק על פסקת גוף: כותרות כבר חזרו ב-return למעלה, כדי לא לעטוף `<h>`
  // ב-`<div>` (מה שהיה שובר את זיהוי הכותרות ב-TocParser).
  final jc = pPr?.getElement('w:jc')?.getAttribute('w:val');
  final align = switch (jc) {
    'center' => 'center',
    'right' => 'right',
    'left' => 'left',
    _ => null,
  };
  if (align != null) {
    text = '<div style="text-align: $align;">$text</div>';
  }

  output.add(text);
}

/// מספר עמודות ה-grid שתא תופס (`w:gridSpan`, ברירת מחדל 1).
int _gridSpanOf(xml.XmlElement cell) {
  final v = cell
      .getElement('w:tcPr')
      ?.getElement('w:gridSpan')
      ?.getAttribute('w:val');
  return (v != null ? int.tryParse(v) : null) ?? 1;
}

/// האם התא הוא המשך מיזוג אנכי (`w:vMerge` ללא `restart`) — כלומר ממוזג
/// עם התא שמעליו ואין לפלוט עבורו `<td>`.
bool _isVMergeContinue(xml.XmlElement cell) {
  final vm = cell.getElement('w:tcPr')?.getElement('w:vMerge');
  return vm != null && vm.getAttribute('w:val') != 'restart';
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

      // תא המשך-מיזוג-אנכי: מדולג (כלול ב-rowspan של התא העליון).
      if (_isVMergeContinue(cell)) {
        colPos += span;
        continue;
      }

      final tcPr = cell.getElement('w:tcPr');
      final vMergeVal = tcPr?.getElement('w:vMerge')?.getAttribute('w:val');

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
      final vAlign = tcPr?.getElement('w:vAlign')?.getAttribute('w:val');

      final attrs = StringBuffer();
      if (span > 1) attrs.write(' colspan="$span"');
      if (rowspan > 1) attrs.write(' rowspan="$rowspan"');
      final styles = <String>['border: 1px solid #999', 'padding: 4px 8px'];
      if (shd != null) {
        final f = shd.toLowerCase();
        if (f != 'auto' && f != 'ffffff') styles.add('background-color: #$shd');
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
  return '<table$dir style="border-collapse: collapse; '
      'border: 1px solid #999;">$rows</table>';
}

/// Extracts footnotes from the document
Map<String, String> _extractFootnotes(Archive archive) {
  final footnotes = <String, String>{};

  for (final file in archive) {
    if (file.isFile && file.name == 'word/footnotes.xml') {
      try {
        final content = _decodeXmlBytes(file.content);
        final document = xml.XmlDocument.parse(content);

        final footnoteNodes = document.findAllElements('w:footnote');
        for (final footnote in footnoteNodes) {
          final id = footnote.getAttribute('w:id');
          if (id != null && id != '-1' && id != '0') {
            // Skip automatic footnotes
            final text = footnote
                .findAllElements('w:t')
                .map((e) => e.innerText)
                .join('');
            footnotes[id] = text;
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

/// Converts a docx file to text.
/// Marks up headings, lists, text styling, and includes footnotes inline.
String docxToText(Uint8List bytes, String title) {
  _zipDecoder ??= ZipDecoder();

  final archive = _zipDecoder!.decodeBytes(bytes);
  final ctx = _DocxContext(
    _extractFootnotes(archive),
    _extractImages(archive),
    _extractNumbering(archive),
    _extractHeadingStyles(archive),
  );
  final List<String> list = ['<h1>${_escapeHtml(title)}</h1>'];

  for (final file in archive) {
    if (file.isFile && file.name == 'word/document.xml') {
      final fileContent = _decodeXmlBytes(file.content);
      final xml.XmlDocument document;
      try {
        document = xml.XmlDocument.parse(fileContent);
      } catch (_) {
        // document.xml פגום — מחזירים לפחות את כותרת הספר במקום לקרוס.
        break;
      }

      final body = document.rootElement.getElement('w:body');
      if (body == null) break;

      _processBlockChildren(body.childElements, ctx, list);
      break;
    }
  }

  return list.join('\n');
}

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
    }
  }
}
