import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:otzaria/utils/file/document_conversion_exceptions.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/file/zip_limits.dart';
import 'package:otzaria/utils/file/embedded_media.dart';
import 'package:otzaria/utils/text/html_escape.dart';
import 'package:otzaria/utils/text/inline_style.dart';
import 'package:otzaria/utils/text/numeral_formats.dart';
import 'package:otzaria/utils/text/otzaria_markup.dart';
import 'package:xml/xml.dart' as xml;

/// גרסת ממיר ה-ODT. **חובה להעלות בכל שינוי שמשפיע על הפלט** — הגרסה היא
/// חלק ממפתח-התוקף של המטמון, והעלאתה מפסלת רשומות ישנות וגורמת להמרה מחדש.
/// v2: `fo:color`/`xlink:href` עוברים escape כערכי מאפיין; content.xml פגום
/// זורק חריגה במקום להחזיר כותרת בלבד.
/// v3: טקסט מוסתר (`text:display="none"`) מדולג, וריאנטי קו תחתי וקו חוצה
/// כפול, מרקר (`fo:background-color`), יישור לוגי (`start`/`end`) לפי
/// `style:writing-mode`, ומאפייני טבלה (שורת כותרת, רקע תא, יישור אנכי, RTL).
/// v4: `text:s`/`text:tab` נושאים את עיצוב ה-run (הקו התחתי נקטע בין המילים),
/// spans סמוכים בעלי אותו סגנון ממוזגים, ויישור לוגי בפסקה RTL מדולג.
/// v5: `draw:image` עצמאי נפתר גם כשנתיבו יחסי (`./Pictures/…`), והתצוגה
/// המקדימה של החבילה (`Thumbnails/`) אינה נספרת בתקרת ההטמעה.
/// v6: חבילה בלי `office:text` זורקת חריגה, `draw:frame` ברמת הבלוק אינו
/// נמחק, `text:list-header` אינו ממוספר, צבעים מסוננים וכותרת עוברת trim.
const int kOdtConverterVersion = 8;

/// רווח קשיח. `text:s` ו-`text:tab` מייצגים רווחים שהמסמך דורש שיישמרו,
/// ורווח רגיל היה נבלע ברינדור ה-HTML.
const String _nbsp = ' ';

/// ממיר מסמך OpenDocument Text לטקסט של אוצריא.
///
/// הפלט מקיים את אותו חוזה markup של ממיר ה-Word (§24): כותרות `<h1>`–`<h6>`,
/// `<b>`/`<i>`/`<u>`/`<s>`, טבלאות, `<img>` עם data URI, והערות שוליים בתבנית
/// `<sup class="footnote-marker">N</sup><i class="footnote">…</i>`. כך תוכן
/// העניינים, החיפוש והאינדוקס עובדים על ODT בלי שום ידע על הפורמט.
///
/// [embedImages] כבוי משאיר את תגי ה-`<img>` עם `src` ריק — מבנה השורות נשמר
/// (ראו `docx_to_otzaria.dart` להסבר מדוע זה קריטי לאינדקסי ה-TOC).
String odtToText(Uint8List bytes, String title, {bool embedImages = true}) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    throw CorruptedDocumentException(format: DocumentFormat.odt, cause: e);
  }
  // מפענח ה-ZIP סובלני ומחזיר ארכיון ריק על קלט שאינו ZIP כלל. בלי הבדיקה
  // הזו קובץ פגום היה נפתח כספר ריק במקום לדווח על שגיאה.
  if (archive.isEmpty) {
    throw CorruptedDocumentException(
      format: DocumentFormat.odt,
      cause: 'החבילה אינה ארכיון ZIP תקין',
    );
  }
  assertSafeArchive(archive, format: DocumentFormat.odt);

  // ODF מוצפן שומר את מבנה ה-ZIP ומצפין את הרשומות; בלי הבדיקה content.xml
  // המוצפן נדחה כ-XML פגום, ודיווח הכשל מטעה.
  // בלי הקידומת: מניפסט עם namespace ברירת-מחדל כותב `<encryption-data/>`.
  final manifest = _fileNamed(archive, 'META-INF/manifest.xml');
  if (manifest != null &&
      _decodeXml(
        readArchiveEntry(manifest, format: DocumentFormat.odt),
      ).contains('encryption-data')) {
    throw EncryptedDocumentException(
      format: DocumentFormat.odt,
      cause: 'החבילה מוגנת בסיסמה',
    );
  }

  final content = _fileNamed(archive, 'content.xml');
  if (content == null) {
    throw CorruptedDocumentException(
      format: DocumentFormat.odt,
      cause: 'אין content.xml בחבילה',
    );
  }

  // פלט "כותרת בלבד" נראה כמו ספר תקין וריק: הוא נשמר במטמון, מאונדקס,
  // ומסמן כל הערה אישית שמעבר לשורה 1 כחסרה — לצמיתות.
  final xml.XmlDocument document;
  try {
    document = xml.XmlDocument.parse(
      _decodeXml(readArchiveEntry(content, format: DocumentFormat.odt)),
    );
  } catch (e) {
    if (e is DocumentConversionException) rethrow;
    throw CorruptedDocumentException(
      format: DocumentFormat.odt,
      cause: 'content.xml אינו XML תקין: $e',
    );
  }

  final output = <String>[
    otzariaInlineText('<h1>${escapeHtmlText(title)}</h1>'),
  ];

  final ctx = _OdtContext(
    styles: _extractStyles(document, archive),
    lists: _extractListStyles(document, archive),
    images: _extractImages(archive, embedImages: embedImages),
    fillImages: _extractFillImages(document, archive),
    noteFormats: _extractNoteFormats(document, archive),
  );

  // חבילה שאין בה `office:text` אינה מסמך טקסט — .ods ששמו שונה, או
  // content.xml קטוע. פלט "כותרת בלבד" היה נראה כספר תקין וריק, נשמר
  // במטמון, מאונדקס, ומסמן כל הערה אישית מעבר לשורה 1 כחסרה. מסמך **ריק
  // אך תקין** ממשיך להחזיר כותרת בלבד — `office:text` קיים ובלי ילדים.
  final text = document.rootElement
      .getElement('office:body')
      ?.getElement('office:text');
  if (text == null) {
    throw CorruptedDocumentException(
      format: DocumentFormat.odt,
      cause: 'אין office:text ב-content.xml',
    );
  }
  _processBlocks(text.childElements, ctx, output);

  return output.join('\n');
}

// ── מודל הסגנונות ─────────────────────────────────────────────────────────

/// סגנון ODT יחיד. `parent` נפתר בזמן שאילתה (עם הגנת-מעגל), כדי ששרשרת
/// ירושה ארוכה לא תידרש להיפתר מראש לכל סגנון.
class _OdtStyle {
  final String? parent;
  final bool? bold;
  final bool? italic;
  final bool? underline;
  final UnderlineKind? underlineKind;
  final bool? underlineDouble;
  final bool? underlineThick;
  final String? underlineColor;
  final bool? strike;
  final bool? strikeDouble;
  final String? color;

  /// מרקר על הטקסט, וגם צבע הרקע של תא בטבלה — ODF מתאר את שניהם באותו
  /// מאפיין, וההקשר (טקסט או תא) הוא שקובע.
  final String? background;
  final String? textAlign;
  final String? verticalAlign;

  /// יישור אנכי בתא (`style:vertical-align` ב-table-cell-properties).
  final String? cellVerticalAlign;

  /// `rl-tb` = כיוון ימין-לשמאל. קובע את משמעות `start`/`end`.
  final String? writingMode;
  final int? outlineLevel;

  /// טקסט שמסומן `text:display="none"` קיים במסמך ואינו אמור להיראות.
  final bool? hidden;

  /// מאפייני מסגרת גרפית (`style:graphic-properties`).
  final String? stroke;
  final String? fill;
  final String? fillImageName;

  const _OdtStyle({
    this.parent,
    this.bold,
    this.italic,
    this.underline,
    this.underlineKind,
    this.underlineDouble,
    this.underlineThick,
    this.underlineColor,
    this.strike,
    this.strikeDouble,
    this.color,
    this.background,
    this.textAlign,
    this.verticalAlign,
    this.cellVerticalAlign,
    this.writingMode,
    this.outlineLevel,
    this.hidden,
    this.stroke,
    this.fill,
    this.fillImageName,
  });
}

/// מאפייני מסגרת גרפית שהומרו למונחי התצוגה.
class _OdtFrameStyle {
  const _OdtFrameStyle({required this.hasBorder, this.backgroundImage});

  final bool hasBorder;
  final String? backgroundImage;
}

/// עיצוב מחושב לאחר פתירת שרשרת הירושה.
class _Formatting {
  bool bold = false;
  bool italic = false;
  bool underline = false;
  UnderlineKind underlineKind = UnderlineKind.single;
  bool underlineDouble = false;
  bool underlineThick = false;
  String? underlineColor;
  bool strike = false;
  bool strikeDouble = false;
  String? color;
  String? background;
  String? verticalAlign;
  bool hidden = false;

  _Formatting clone() => _Formatting()
    ..bold = bold
    ..italic = italic
    ..underline = underline
    ..underlineKind = underlineKind
    ..underlineDouble = underlineDouble
    ..underlineThick = underlineThick
    ..underlineColor = underlineColor
    ..strike = strike
    ..strikeDouble = strikeDouble
    ..color = color
    ..background = background
    ..verticalAlign = verticalAlign
    ..hidden = hidden;

  /// תגי הפתיחה והסגירה, נבנים יחד כדי שיישארו מסונכרנים.
  ({String open, String close}) get tags {
    final open = StringBuffer();
    final close = <String>[];
    void wrap(({String open, String close}) pair) {
      open.write(pair.open);
      close.insert(0, pair.close);
    }

    if (bold) wrap((open: '<b>', close: '</b>'));
    if (italic) wrap((open: '<i>', close: '</i>'));
    if (underline) {
      wrap(
        underlineTags(
          kind: underlineKind,
          color: underlineColor,
          thick: underlineThick,
          doubleLine: underlineDouble,
        ),
      );
    }
    if (strike) wrap(strikeTags(doubleLine: strikeDouble));
    final marker = background;
    if (marker != null) wrap(highlightTags(marker));
    if (verticalAlign == 'super') wrap((open: '<sup>', close: '</sup>'));
    if (verticalAlign == 'sub') wrap((open: '<sub>', close: '</sub>'));
    final textColor = color;
    if (textColor != null) wrap(colorTags(textColor));
    return (open: open.toString(), close: close.join());
  }

  bool get isPlain =>
      !bold &&
      !italic &&
      !underline &&
      !strike &&
      color == null &&
      background == null &&
      verticalAlign == null;
}

/// רמה אחת בסגנון רשימה.
class _OdtListLevel {
  /// `1` / `a` / `A` / `i` / `I` / `א` — ריק מסמן תבליט.
  final String numFormat;
  final String prefix;
  final String suffix;
  final int startValue;
  final int displayLevels;
  final String bulletChar;
  final bool isBullet;

  const _OdtListLevel({
    required this.numFormat,
    required this.prefix,
    required this.suffix,
    required this.startValue,
    required this.displayLevels,
    required this.bulletChar,
    required this.isBullet,
  });
}

class _OdtContext {
  final Map<String, _OdtStyle> styles;
  final Map<String, Map<int, _OdtListLevel>> lists;
  final Map<String, String> images;

  /// שם `draw:fill-image` → הנתיב שאליו הוא מצביע (`xlink:href`).
  final Map<String, String> fillImages;

  /// `text:note-class` → `style:num-format` מ-`text:notes-configuration`.
  final Map<String, String> noteFormats;

  /// מונה רץ לסימוני הערות שוליים.
  int _footnoteNumber = 1;

  /// מונים רצים לרשימות: שם סגנון → (רמה → ערך נוכחי).
  final Map<String, Map<int, int>> _listCounters = {};

  _OdtContext({
    required this.styles,
    required this.lists,
    required this.images,
    required this.fillImages,
    this.noteFormats = const {},
  });

  /// ה-data URI של מדיה לפי ה-`xlink:href` שלה, או `null` כשאינה בחבילה.
  /// נתיב מדיה ב-ODF נכתב לעיתים יחסית (`./Pictures/x.png`).
  String? imageFor(String? href) => href == null
      ? null
      : images[href.startsWith('./') ? href.substring(2) : href];

  /// סימון ההערה הבא, בפורמט שהמסמך הגדיר לאותו `text:note-class`.
  /// פורמט שמבטל מספור חוזר לספרות: סימון ריק היה מנתק את גוף ההערה
  /// מהעוגן שלו בשכבת התצוגה.
  String nextNoteMarker(String? noteClass) {
    final value = _footnoteNumber++;
    final label = _formatOdtNumber(
      value,
      noteFormats[noteClass ?? 'footnote'] ?? '1',
    );
    return label.isEmpty ? '$value' : label;
  }

  /// פותר את שרשרת `style:parent-style-name` לעיצוב מחושב.
  /// הגנת-מעגל: סגנון שכבר ביקרנו בו עוצר את הפתירה.
  _Formatting formattingFor(String? styleName) {
    final result = _Formatting();
    final chain = _chainOf(styleName);
    // מהאב לבן — כך הצאצא דורס את האב.
    for (final style in chain.reversed) {
      if (style.bold != null) result.bold = style.bold!;
      if (style.italic != null) result.italic = style.italic!;
      if (style.underline != null) result.underline = style.underline!;
      if (style.underlineKind != null) {
        result.underlineKind = style.underlineKind!;
      }
      if (style.underlineDouble != null) {
        result.underlineDouble = style.underlineDouble!;
      }
      if (style.underlineThick != null) {
        result.underlineThick = style.underlineThick!;
      }
      if (style.underlineColor != null) {
        result.underlineColor = style.underlineColor;
      }
      if (style.strike != null) result.strike = style.strike!;
      if (style.strikeDouble != null) result.strikeDouble = style.strikeDouble!;
      if (style.color != null) result.color = style.color;
      if (style.background != null) result.background = style.background;
      if (style.hidden != null) result.hidden = style.hidden!;
      if (style.verticalAlign != null) {
        result.verticalAlign = style.verticalAlign;
      }
    }
    return result;
  }

  /// רמת הכותרת של סגנון פסקה, או `null` אם אינו כותרת.
  int? headingLevelFor(String? styleName) {
    for (final style in _chainOf(styleName)) {
      if (style.outlineLevel != null) return style.outlineLevel!.clamp(1, 6);
    }
    // ODF מייצר שמות כמו `Heading_20_2`; קובצי המרה משתמשים ב-`Heading 2`.
    for (final name in _chainNames(styleName)) {
      final level = _headingLevelFromName(name);
      if (level != null) return level;
    }
    return null;
  }

  /// היישור הפיזי של פסקה, או `null` כשאין מה לסמן.
  ///
  /// `start`/`end` הם יישור לוגי התלוי בכיוון הכתיבה. בפסקה RTL הם
  /// **מדולגים**: מסמך שהומר מ-Word נושא `end` שנועד להיות *ימין*, ובעוד
  /// שלפי תקן ODF הוא שמאל — הכרעה שגויה מיישרת קטע עברי שלם לצד ההפוך.
  String? textAlignFor(String? styleName) {
    String? raw;
    for (final style in _chainOf(styleName)) {
      if (style.textAlign != null) {
        raw = style.textAlign;
        break;
      }
    }
    if (raw == null) return null;
    if (raw == 'center' || raw == 'right' || raw == 'left') return raw;
    if (raw != 'start' && raw != 'end') return null;
    if (isRtlFor(styleName)) return null;
    return raw == 'start' ? 'left' : 'right';
  }

  /// כיוון הכתיבה של סגנון. ODF מגדיר `lr-tb` כברירת מחדל.
  bool isRtlFor(String? styleName) {
    for (final style in _chainOf(styleName)) {
      final mode = style.writingMode;
      if (mode != null) return mode.startsWith('rl');
    }
    return false;
  }

  /// צבע הרקע של תא בטבלה, או `null`. לבן ושקוף אינם רקע.
  String? cellBackgroundFor(String? styleName) {
    for (final style in _chainOf(styleName)) {
      final value = style.background;
      if (value == null) continue;
      final lower = value.toLowerCase();
      if (lower == 'transparent' || lower == '#ffffff') return null;
      return value;
    }
    return null;
  }

  String? cellVerticalAlignFor(String? styleName) {
    for (final style in _chainOf(styleName)) {
      if (style.cellVerticalAlign != null) return style.cellVerticalAlign;
    }
    return null;
  }

  /// מאפייני מסגרת גרפית: האם היא מציירת גבול, ומה תמונת הרקע שלה.
  _OdtFrameStyle frameStyleFor(String? styleName) {
    String? stroke;
    String? fill;
    String? fillImageName;
    for (final style in _chainOf(styleName)) {
      stroke ??= style.stroke;
      fill ??= style.fill;
      fillImageName ??= style.fillImageName;
    }
    final uri = imageFor(
      fillImageName == null ? null : fillImages[fillImageName],
    );
    return _OdtFrameStyle(
      hasBorder: stroke != null && stroke != 'none',
      backgroundImage: fill == 'bitmap' && uri != null && uri.isNotEmpty
          ? uri
          : null,
    );
  }

  List<_OdtStyle> _chainOf(String? styleName) {
    final chain = <_OdtStyle>[];
    final seen = <String>{};
    var current = styleName;
    while (current != null && seen.add(current)) {
      final style = styles[current];
      if (style == null) break;
      chain.add(style);
      current = style.parent;
    }
    return chain;
  }

  List<String> _chainNames(String? styleName) {
    final names = <String>[];
    final seen = <String>{};
    var current = styleName;
    while (current != null && seen.add(current)) {
      names.add(current);
      current = styles[current]?.parent;
    }
    return names;
  }

  /// תווית הפריט הבא ברשימה (`1.`, `א.`, `•`), תוך קידום המונה ואיפוס
  /// הרמות העמוקות ממנה.
  String listLabel(String? listStyleName, int level) {
    final levels = listStyleName == null ? null : lists[listStyleName];
    final definition = levels?[level];
    if (definition == null || definition.isBullet) {
      final bullet = definition?.bulletChar ?? '';
      return bullet.isEmpty ? '•' : bullet;
    }

    final key = listStyleName!;
    final counters = _listCounters.putIfAbsent(key, () => {});
    counters[level] = (counters[level] ?? (definition.startValue - 1)) + 1;
    counters.removeWhere((k, _) => k > level);

    final parts = <String>[];
    final from = (level - definition.displayLevels + 1).clamp(0, level);
    for (var i = from; i <= level; i++) {
      final levelDefinition = levels![i] ?? definition;
      final value = counters[i] ?? levelDefinition.startValue;
      parts.add(_formatOdtNumber(value, levelDefinition.numFormat));
    }
    final label = '${definition.prefix}${parts.join('.')}${definition.suffix}';
    return label.isEmpty ? '•' : label;
  }

  /// מאפס את מוני הרשימה עבור סגנון — נקרא כשמתחילה רשימה חדשה ברמה 0.
  void resetList(String? listStyleName) {
    if (listStyleName != null) _listCounters.remove(listStyleName);
  }
}

/// ממיר מספר לפי `style:num-format` של ODF.
String _formatOdtNumber(int n, String format) {
  if (format.isEmpty) return '';
  switch (format) {
    case 'a':
      return toLatinLetters(n, upper: false);
    case 'A':
      return toLatinLetters(n, upper: true);
    case 'i':
      return toRomanNumeral(n).toLowerCase();
    case 'I':
      return toRomanNumeral(n);
    default:
      // ODF מסמן מספור עברי בתו הראשון של סדרת האותיות.
      if (format.startsWith('א')) return toHebrewNumeral(n);
      return '$n';
  }
}

int? _headingLevelFromName(String name) {
  final normalized = name.replaceAll('_20_', ' ').toLowerCase();
  if (normalized == 'title') return 1;
  final match = RegExp(r'^heading\s*(\d+)$').firstMatch(normalized);
  if (match == null) return null;
  return int.tryParse(match.group(1)!)?.clamp(1, 6);
}

// ── חילוץ ממשאבי החבילה ───────────────────────────────────────────────────

ArchiveFile? _fileNamed(Archive archive, String name) {
  for (final file in archive) {
    if (file.isFile && file.name == name) return file;
  }
  return null;
}

/// מעביר את `styles.xml` של הארכיון ל-[collect]. קובץ חסר או פגום — וגם
/// כשל באיסוף ממנו — אינו מפיל את הייבוא; הקורא ממשיך בלעדיו.
void _collectGlobalStyles(
  Archive archive,
  void Function(xml.XmlDocument document) collect,
) {
  final globalStyles = _fileNamed(archive, 'styles.xml');
  if (globalStyles == null) return;
  try {
    collect(
      xml.XmlDocument.parse(
        _decodeXml(readArchiveEntry(globalStyles, format: DocumentFormat.odt)),
      ),
    );
  } catch (_) {
    // ממשיכים בלי הסגנונות הגלובליים (§45).
  }
}

String _decodeXml(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes, allowInvalid: true);
  }
}

/// אוסף את הגדרות הסגנון מ-`content.xml` (automatic-styles) ומ-`styles.xml`
/// (styles + automatic-styles). סגנון מקומי גובר על גלובלי בעל אותו שם.
Map<String, _OdtStyle> _extractStyles(
  xml.XmlDocument content,
  Archive archive,
) {
  final styles = <String, _OdtStyle>{};

  void collect(xml.XmlDocument document) {
    for (final element in document.findAllElements('style:style')) {
      final name = element.getAttribute('style:name');
      if (name == null) continue;
      styles[name] = _parseStyle(element);
    }
  }

  // styles.xml פגום — ממשיכים עם הסגנונות המקומיים בלבד (§45).
  _collectGlobalStyles(archive, collect);
  collect(content);
  return styles;
}

_OdtStyle _parseStyle(xml.XmlElement element) {
  final textProperties = element.getElement('style:text-properties');
  final paragraphProperties = element.getElement('style:paragraph-properties');
  final cellProperties = element.getElement('style:table-cell-properties');
  final tableProperties = element.getElement('style:table-properties');
  final graphicProperties = element.getElement('style:graphic-properties');

  final weight = textProperties?.getAttribute('fo:font-weight');
  final style = textProperties?.getAttribute('fo:font-style');
  final underline = textProperties?.getAttribute(
    'style:text-underline-style',
  );
  final underlineType = textProperties?.getAttribute(
    'style:text-underline-type',
  );
  final underlineWidth = textProperties?.getAttribute(
    'style:text-underline-width',
  );
  final underlineColor = textProperties?.getAttribute(
    'style:text-underline-color',
  );
  final strike = textProperties?.getAttribute(
    'style:text-line-through-style',
  );
  final strikeType = textProperties?.getAttribute(
    'style:text-line-through-type',
  );
  final color = textProperties?.getAttribute('fo:color');
  final position = textProperties?.getAttribute('style:text-position');
  final display = textProperties?.getAttribute('text:display');

  // רקע: על טקסט זהו מרקר, ועל תא זהו צבע התא. אותו מאפיין בדיוק, ולכן
  // הוא נקרא משניהם וההקשר בשאילתה הוא שמכריע.
  final background =
      textProperties?.getAttribute('fo:background-color') ??
      cellProperties?.getAttribute('fo:background-color');

  return _OdtStyle(
    parent: element.getAttribute('style:parent-style-name'),
    bold: weight == null ? null : (weight == 'bold' || weight == '700'),
    italic: style == null ? null : (style == 'italic' || style == 'oblique'),
    underline: underline == null ? null : underline != 'none',
    underlineKind: underline == null || underline == 'none'
        ? null
        : underlineKindFromName(underline),
    underlineDouble: underlineType == null ? null : underlineType == 'double',
    underlineThick: underlineWidth == null
        ? null
        : (underlineWidth == 'bold' ||
              underlineWidth == 'thick' ||
              underlineWidth.startsWith('bold')),
    underlineColor:
        underlineColor == null || underlineColor.toLowerCase() == 'font-color'
        ? null
        : underlineColor,
    strike: strike == null ? null : strike != 'none',
    strikeDouble: strikeType == null ? null : strikeType == 'double',
    // הצבעים מגיעים מתוך המסמך ונכנסים ל-`style="…"`; סינון כאן חוסם ערך
    // שנועד להיחלץ מהמאפיין ולהזריק תגיות משלו לגוף הספר.
    color: color == null || color.toLowerCase() == '#000000'
        ? null
        : sanitizeCssColor(color),
    background: sanitizeCssColor(background),
    textAlign: paragraphProperties?.getAttribute('fo:text-align'),
    verticalAlign: position == null
        ? null
        : position.startsWith('super')
        ? 'super'
        : position.startsWith('sub')
        ? 'sub'
        : null,
    cellVerticalAlign: cssVerticalAlign(
      cellProperties?.getAttribute('style:vertical-align'),
    ),
    writingMode:
        paragraphProperties?.getAttribute('style:writing-mode') ??
        cellProperties?.getAttribute('style:writing-mode') ??
        tableProperties?.getAttribute('style:writing-mode'),
    outlineLevel: int.tryParse(
      element.getAttribute('style:default-outline-level') ?? '',
    ),
    hidden: display == null ? null : display == 'none',
    stroke: graphicProperties?.getAttribute('draw:stroke'),
    fill: graphicProperties?.getAttribute('draw:fill'),
    fillImageName: graphicProperties?.getAttribute('draw:fill-image-name'),
  );
}

/// בונה מפת שם `draw:fill-image` → נתיב המדיה שלו. זהו הקישור בין מסגרת
/// שממולאת בתמונה לבין הקובץ עצמו — תמונת הרקע של תיבת-טקסט.
Map<String, String> _extractFillImages(
  xml.XmlDocument content,
  Archive archive,
) {
  final fills = <String, String>{};

  void collect(xml.XmlDocument document) {
    for (final element in document.findAllElements('draw:fill-image')) {
      final name = element.getAttribute('draw:name');
      final href = element.getAttribute('xlink:href');
      if (name != null && href != null) fills[name] = href;
    }
  }

  // styles.xml פגום — ממשיכים בלי תמונות מילוי.
  _collectGlobalStyles(archive, collect);
  collect(content);
  return fills;
}

/// בונה מפת שם-סגנון-רשימה → (רמה → הגדרה).
Map<String, Map<int, _OdtListLevel>> _extractListStyles(
  xml.XmlDocument content,
  Archive archive,
) {
  final lists = <String, Map<int, _OdtListLevel>>{};

  void collect(xml.XmlDocument document) {
    for (final listStyle in document.findAllElements('text:list-style')) {
      final name = listStyle.getAttribute('style:name');
      if (name == null) continue;
      final levels = <int, _OdtListLevel>{};
      for (final level in listStyle.childElements) {
        final rawLevel = level.getAttribute('text:level');
        final index = (int.tryParse(rawLevel ?? '') ?? 1) - 1;
        if (index < 0) continue;
        final isBullet = level.name.qualified == 'text:list-level-style-bullet';
        levels[index] = _OdtListLevel(
          numFormat: level.getAttribute('style:num-format') ?? '1',
          prefix: level.getAttribute('style:num-prefix') ?? '',
          suffix: level.getAttribute('style:num-suffix') ?? '',
          startValue:
              int.tryParse(level.getAttribute('text:start-value') ?? '') ?? 1,
          displayLevels:
              int.tryParse(level.getAttribute('text:display-levels') ?? '') ??
              1,
          bulletChar: level.getAttribute('text:bullet-char') ?? '•',
          isBullet:
              isBullet || level.name.qualified == 'text:list-level-style-image',
        );
      }
      lists[name] = levels;
    }
  }

  // סגנונות רשימה גלובליים פגומים — נופלים לתבליט ברירת מחדל.
  _collectGlobalStyles(archive, collect);
  collect(content);
  return lists;
}

/// בונה מפת `text:note-class` → `style:num-format` מתוך
/// `text:notes-configuration` (issue #1239).
///
/// ההגדרה יושבת ב-styles.xml, אך content.xml יכול לדרוס אותה — ולכן
/// הסריקה בשני הקבצים, בסדר הזה.
Map<String, String> _extractNoteFormats(
  xml.XmlDocument content,
  Archive archive,
) {
  final formats = <String, String>{};

  void collect(xml.XmlDocument document) {
    for (final config in document.findAllElements(
      'text:notes-configuration',
    )) {
      final noteClass = config.getAttribute('text:note-class');
      final format = config.getAttribute('style:num-format');
      if (noteClass != null && format != null) {
        formats[noteClass] = format;
      }
    }
  }

  // הגדרת הערות גלובלית פגומה — המספור נשאר בספרות.
  _collectGlobalStyles(archive, collect);
  collect(content);
  return formats;
}

/// בונה מפת נתיב-תמונה → data URI. ODF מאחסן את המדיה תחת `Pictures/`.
///
/// תמונה שחורגת מ-[EmbeddedMediaLimits] או שרשומתה פגומה נשארת כתג ריק —
/// תמונה אחת אינה שווה כשל של המסמך כולו.
Map<String, String> _extractImages(
  Archive archive, {
  required bool embedImages,
}) {
  final images = <String, String>{};
  var embeddedBytes = 0;
  for (final file in archive) {
    if (!file.isFile) continue;
    // התצוגה המקדימה של החבילה אינה תוכן המסמך, ולכן אין להטמיע אותה —
    // ובעיקר אין לתת לה לאכול מתקרת ההטמעה הכוללת.
    if (file.name.startsWith('Thumbnails/')) continue;
    final mime = imageMimeForPath(file.name);
    if (mime == null) continue;
    if (!embedImages ||
        file.size > EmbeddedMediaLimits.maxImageBytes ||
        embeddedBytes + file.size > EmbeddedMediaLimits.maxTotalImageBytes) {
      images[file.name] = '';
      continue;
    }
    try {
      final content = readArchiveEntry(file, format: DocumentFormat.odt);
      images[file.name] = 'data:$mime;base64,${base64Encode(content)}';
      embeddedBytes += content.length;
    } catch (_) {
      images[file.name] = '';
    }
  }
  return images;
}

// ── עיבוד הגוף ────────────────────────────────────────────────────────────

/// תקרת עומק לקינון XML. מסמך אמיתי רחוק מכאן; `content.xml` עם אלפי
/// אלמנטים מקוננים הקריס את המחסנית לפני שהיא נקבעה.
const int _maxNestingDepth = 100;

/// מעל התקרה מפסיקים לרדת אך **שומרים את הטקסט**: `return` שקט היה מייצר
/// פלט "כותרת בלבד" — בדיוק אובדן הנתונים שההגנה נועדה למנוע.
void _emitDeepText(Iterable<xml.XmlElement> children, List<String> output) {
  for (final element in children) {
    final text = escapeHtmlText(element.innerText).trim();
    if (text.isNotEmpty) output.add(text);
  }
}

/// [listLevel] הוא `null` מחוץ לרשימה — כך רשימה מקוננת (שיושבת בתוך
/// `text:list-item`) יודעת שעליה להעמיק רמה, ופסקה בתוך פריט מקבלת תווית
/// גם כשלרשימה אין שם סגנון.
void _processBlocks(
  Iterable<xml.XmlElement> children,
  _OdtContext ctx,
  List<String> output, {
  int? listLevel,
  String? listStyleName,
  int depth = 0,
}) {
  if (depth > _maxNestingDepth) {
    _emitDeepText(children, output);
    return;
  }
  for (final element in children) {
    switch (element.name.qualified) {
      case 'text:h':
        _processHeading(element, ctx, output, depth: depth);
      case 'text:p':
        _processParagraph(
          element,
          ctx,
          output,
          listLevel: listLevel,
          listStyleName: listStyleName,
          depth: depth,
        );
      case 'text:list':
        _processList(
          element,
          ctx,
          output,
          level: listLevel == null ? 0 : listLevel + 1,
          depth: depth + 1,
        );
      case 'table:table':
        final html = _buildTableHtml(element, ctx, depth: depth + 1);
        if (html != null) output.add(html);
      // מסגרת צפה מותרת גם כילד ישיר של `office:text`, ולא רק בתוך פסקה.
      // בלי הענף הזה תוכן תיבות-הטקסט ברמת הבלוק נמחק בשקט.
      case 'draw:frame':
      case 'draw:image':
        final media = _renderImage(element, ctx, depth: depth + 1);
        if (media.isNotEmpty) output.add(media);
      // מכולות שקופות: מדלגים על העטיפה וממשיכים בילדים כדי לא לאבד תוכן.
      case 'text:section':
      case 'office:text':
      case 'text:index-body':
      case 'text:table-of-content':
        _processBlocks(element.childElements, ctx, output, depth: depth + 1);
    }
  }
}

void _processHeading(
  xml.XmlElement element,
  _OdtContext ctx,
  List<String> output, {
  int depth = 0,
}) {
  final text = _renderInline(element, ctx, depth: depth);
  if (text.trim().isEmpty) return;
  final styleName = element.getAttribute('text:style-name');
  final level =
      int.tryParse(element.getAttribute('text:outline-level') ?? '')?.clamp(
        1,
        6,
      ) ??
      ctx.headingLevelFor(styleName) ??
      1;
  output.add('<h$level>${text.trim()}</h$level>');
}

void _processParagraph(
  xml.XmlElement element,
  _OdtContext ctx,
  List<String> output, {
  int? listLevel,
  String? listStyleName,
  int depth = 0,
}) {
  var text = _renderInline(element, ctx, depth: depth);
  if (text.trim().isEmpty) return;

  final styleName = element.getAttribute('text:style-name');

  // פסקה שסגנונה כותרת — גם כשהיא `text:p` ולא `text:h` (מסמכים שהומרו).
  final level = ctx.headingLevelFor(styleName);
  if (level != null && listLevel == null) {
    output.add('<h$level>${text.trim()}</h$level>');
    return;
  }

  if (listLevel != null) {
    final label = ctx.listLabel(listStyleName, listLevel);
    final indent = _nbsp * 4 * listLevel;
    text = '$indent$label $text';
  }

  final align = ctx.textAlignFor(styleName);
  if (align != null) {
    text = '<div style="text-align: $align;">$text</div>';
  }

  output.add(text);
}

void _processList(
  xml.XmlElement element,
  _OdtContext ctx,
  List<String> output, {
  required int level,
  int depth = 0,
}) {
  if (depth > _maxNestingDepth) {
    _emitDeepText(element.childElements, output);
    return;
  }
  final styleName =
      element.getAttribute('text:style-name') ?? _inheritedListStyle(element);
  if (level == 0) ctx.resetList(styleName);

  for (final item in element.childElements) {
    switch (item.name.qualified) {
      case 'text:list-item':
        _processBlocks(
          item.childElements,
          ctx,
          output,
          listLevel: level,
          listStyleName: styleName,
          depth: depth + 1,
        );
      // כותרת רשימה היא פסקת מבוא ואינה פריט ממוספר; מספורה הסיטה את כל
      // הרשימה שאחריה ב-1.
      case 'text:list-header':
        _processBlocks(item.childElements, ctx, output, depth: depth + 1);
      case 'text:list':
        _processList(item, ctx, output, level: level + 1, depth: depth + 1);
    }
  }
}

/// רשימה מקוננת אינה חוזרת על שם הסגנון; מטפסים להורה הקרוב שמגדיר אותו.
String? _inheritedListStyle(xml.XmlElement element) {
  xml.XmlNode? node = element.parent;
  while (node is xml.XmlElement) {
    if (node.name.qualified == 'text:list') {
      final name = node.getAttribute('text:style-name');
      if (name != null) return name;
    }
    node = node.parent;
  }
  return null;
}

/// מקטע טקסט מעוצב אחד. [raw] מסמן תוכן מוכן (תמונה, הערה) שאין לעטוף.
class _Segment {
  const _Segment(this.open, this.close, this.text) : raw = false;
  const _Segment.raw(this.text) : open = '', close = '', raw = true;

  final String open;
  final String close;
  final String text;
  final bool raw;
}

/// מרנדר את תוכן הפסקה/הכותרת ל-HTML inline.
String _renderInline(
  xml.XmlElement element,
  _OdtContext ctx, {
  _Formatting? inherited,
  int depth = 0,
}) {
  final segments = <_Segment>[];
  _collectInline(element, ctx, segments, inherited: inherited, depth: depth);
  return _joinSegments(segments);
}

/// מחבר מקטעים, וממזג רצף בעל אותה עטיפה לתג אחד.
///
/// המיזוג אינו קוסמטי: ODF מפצל משפט לכמה `text:span` בעלי אותו סגנון,
/// ובלעדיו הקו התחתי **נקטע בין המילים** וההדגשה בחיפוש נשברת.
String _joinSegments(List<_Segment> segments) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < segments.length) {
    final segment = segments[i];
    if (segment.raw) {
      buffer.write(segment.text);
      i++;
      continue;
    }
    buffer.write(segment.open);
    buffer.write(segment.text);
    var j = i + 1;
    while (j < segments.length &&
        !segments[j].raw &&
        segments[j].open == segment.open) {
      buffer.write(segments[j].text);
      j++;
    }
    buffer.write(segment.close);
    i = j;
  }
  return buffer.toString();
}

void _collectInline(
  xml.XmlElement element,
  _OdtContext ctx,
  List<_Segment> segments, {
  _Formatting? inherited,
  int depth = 0,
}) {
  final formatting =
      inherited ?? ctx.formattingFor(element.getAttribute('text:style-name'));

  void addText(String text) {
    if (text.isEmpty || formatting.hidden) return;
    if (formatting.isPlain) {
      segments.add(_Segment('', '', text));
      return;
    }
    final tags = formatting.tags;
    segments.add(_Segment(tags.open, tags.close, text));
  }

  // מעל התקרה מפסיקים לרדת אך שומרים את הטקסט — עומק אינו סיבה לאבד תוכן.
  if (depth > _maxNestingDepth) {
    addText(escapeHtmlText(element.innerText));
    return;
  }

  for (final node in element.children) {
    if (node is xml.XmlText || node is xml.XmlCDATA) {
      addText(escapeHtmlText(otzariaInlineText(node.value ?? '')));
      continue;
    }
    if (node is! xml.XmlElement) continue;

    switch (node.name.qualified) {
      case 'text:span':
        _collectInline(
          node,
          ctx,
          segments,
          inherited: _merge(
            formatting,
            ctx.formattingFor(node.getAttribute('text:style-name')),
          ),
          depth: depth + 1,
        );
      case 'text:a':
        final href = node.getAttribute('xlink:href');
        final inner = _renderInline(
          node,
          ctx,
          inherited: formatting,
          depth: depth + 1,
        );
        final safeHref = href == null
            ? null
            : safeLinkTarget(href, allowBookLinks: true);
        segments.add(
          _Segment.raw(
            safeHref == null
                ? inner
                : '<a href="${escapeHtmlAttribute(safeHref)}">$inner</a>',
          ),
        );
      // רווח וטאב נושאים את עיצוב ה-run שהם יושבים בו; פליטתם חשופה קטעה
      // את הקו התחתי בדיוק בין המילים.
      case 'text:s':
        final count = int.tryParse(node.getAttribute('text:c') ?? '') ?? 1;
        addText(_nbsp * count);
      case 'text:tab':
        addText(_nbsp * 4);
      case 'text:line-break':
        segments.add(const _Segment.raw('<br>'));
      case 'text:note':
        segments.add(_Segment.raw(_renderNote(node, ctx, depth: depth + 1)));
      case 'draw:frame':
      case 'draw:image':
        segments.add(_Segment.raw(_renderImage(node, ctx, depth: depth + 1)));
      case 'text:bookmark':
      case 'text:bookmark-start':
      case 'text:bookmark-end':
      case 'text:soft-page-break':
      case 'text:sequence-decl':
      case 'office:annotation':
        break; // ללא ייצוג חזותי
      default:
        // אלמנט לא מוכר (שדות, סימוני שינוי): שומרים את הטקסט שבתוכו.
        _collectInline(
          node,
          ctx,
          segments,
          inherited: formatting,
          depth: depth + 1,
        );
    }
  }
}

/// הערת שוליים/סיום — אותה תבנית כמו בממיר Word, כדי ששכבת התצוגה תזהה
/// אותה בלי לדעת מאיזה פורמט הגיעה.
String _renderNote(xml.XmlElement note, _OdtContext ctx, {int depth = 0}) {
  final body = note.getElement('text:note-body');
  if (body == null) return '';
  final parts = <String>[];
  for (final child in body.childElements) {
    final rendered = _renderInline(child, ctx, depth: depth + 1);
    if (rendered.trim().isNotEmpty) parts.add(rendered.trim());
  }
  if (parts.isEmpty) return '';
  return otzariaFootnote(
    ctx.nextNoteMarker(note.getAttribute('text:note-class')),
    parts.join(' '),
  );
}

/// מרנדר `draw:frame`. מסגרת היא מכולה כללית: היא עוטפת תמונה, אך גם
/// **תיבת-טקסט** — ומסמכים שהומרו מ-Word בנויים כמעט כולם מתיבות כאלה.
/// החזרת מחרוזת ריקה עליהן מחקה את רוב תוכן המסמך.
String _renderImage(xml.XmlElement element, _OdtContext ctx, {int depth = 0}) {
  final images = [
    if (element.name.qualified == 'draw:image') element,
    ...element.descendantElements.where(
      (e) => e.name.qualified == 'draw:image',
    ),
  ];
  for (final image in images) {
    final uri = ctx.imageFor(image.getAttribute('xlink:href'));
    if (uri != null) return otzariaImage(uri);
  }

  final textBox = element.getElement('draw:text-box');
  if (textBox == null) return '';
  final lines = <String>[];
  _processBlocks(textBox.childElements, ctx, lines, depth: depth + 1);
  if (lines.isEmpty) return '';
  final body = lines.join('<br>');

  // רק מסגרת שמציירת גבול נעטפת: מסמך שהומר מ-Word בנוי כמעט כולו ממסגרות
  // פריסה בלתי-נראות, ועטיפתן הייתה מציירת מאות תיבות מדומות.
  final frameStyle = ctx.frameStyleFor(element.getAttribute('draw:style-name'));
  if (!frameStyle.hasBorder && frameStyle.backgroundImage == null) return body;

  final background = frameStyle.backgroundImage;
  final backgroundCss = background == null
      ? ''
      : 'background-image: url($background); background-size: contain; '
            'background-repeat: no-repeat; background-position: center; ';
  return '<div style="${backgroundCss}border: 1px solid #999; '
      'padding: 8px; margin: 4px 0;">$body</div>';
}

_Formatting _merge(_Formatting parent, _Formatting child) {
  final merged = parent.clone();
  if (child.bold) merged.bold = true;
  if (child.italic) merged.italic = true;
  if (child.underline) {
    merged.underline = true;
    merged.underlineKind = child.underlineKind;
    merged.underlineDouble = child.underlineDouble;
    merged.underlineThick = child.underlineThick;
    if (child.underlineColor != null) {
      merged.underlineColor = child.underlineColor;
    }
  }
  if (child.strike) {
    merged.strike = true;
    merged.strikeDouble = child.strikeDouble;
  }
  if (child.hidden) merged.hidden = true;
  if (child.color != null) merged.color = child.color;
  if (child.background != null) merged.background = child.background;
  if (child.verticalAlign != null) merged.verticalAlign = child.verticalAlign;
  return merged;
}

// ── טבלאות ────────────────────────────────────────────────────────────────

String? _buildTableHtml(
  xml.XmlElement table,
  _OdtContext ctx, {
  int depth = 0,
}) {
  // מעל התקרה הטבלה מוצגת כטקסט רץ — עדיף על אובדן התוכן שבתאים.
  if (depth > _maxNestingDepth) {
    final text = escapeHtmlText(table.innerText).trim();
    return text.isEmpty ? null : text;
  }
  final rows = <String>[];
  for (final (row, isHeader) in _tableRows(table)) {
    final tag = isHeader ? 'th' : 'td';
    final cells = <String>[];
    for (final cell in row.childElements) {
      if (cell.name.qualified == 'table:covered-table-cell') continue;
      if (cell.name.qualified != 'table:table-cell') continue;

      final inner = <String>[];
      _processBlocks(cell.childElements, ctx, inner, depth: depth + 1);
      final span =
          int.tryParse(
            cell.getAttribute('table:number-columns-spanned') ?? '',
          ) ??
          1;
      final rowSpan =
          int.tryParse(cell.getAttribute('table:number-rows-spanned') ?? '') ??
          1;

      final cellStyle = cell.getAttribute('table:style-name');
      final styles = <String>[otzariaTableCellStyle];
      final background = ctx.cellBackgroundFor(cellStyle);
      if (background != null) {
        styles.add('background-color: $background');
      }
      final vAlign = ctx.cellVerticalAlignFor(cellStyle);
      if (vAlign != null) styles.add('vertical-align: $vAlign');

      final attributes = StringBuffer('<$tag style="${styles.join('; ')}"');
      if (span > 1) attributes.write(' colspan="$span"');
      if (rowSpan > 1) attributes.write(' rowspan="$rowSpan"');
      attributes.write('>');
      cells.add('$attributes${inner.join('<br>')}</$tag>');
    }
    if (cells.isNotEmpty) rows.add('<tr>${cells.join()}</tr>');
  }
  if (rows.isEmpty) return null;
  final isRtl = ctx.isRtlFor(table.getAttribute('table:style-name'));
  return '${otzariaTableOpen(attributes: isRtl ? ' dir="rtl"' : '')}'
      '${rows.join()}</table>';
}

/// שורות הטבלה, עם סימון האם השורה יושבת ב-`table:table-header-rows`.
Iterable<(xml.XmlElement, bool)> _tableRows(
  xml.XmlElement table, {
  bool inHeader = false,
}) sync* {
  for (final child in table.childElements) {
    switch (child.name.qualified) {
      case 'table:table-row':
        yield (child, inHeader);
      case 'table:table-header-rows':
        yield* _tableRows(child, inHeader: true);
      case 'table:table-row-group':
        yield* _tableRows(child, inHeader: inHeader);
    }
  }
}
