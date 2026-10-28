import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;

import 'package:otzaria/utils/file/document_conversion_exceptions.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/file/embedded_media.dart';
import 'package:otzaria/utils/file/text_encoding.dart';
import 'package:otzaria/utils/file/toc_parser.dart' show kTocExcludeAttr;
import 'package:otzaria/utils/text/css_whitelist.dart';
import 'package:otzaria/utils/text/html_escape.dart';
import 'package:otzaria/utils/text/inline_style.dart';
import 'package:otzaria/utils/text/numeral_formats.dart';
import 'package:otzaria/utils/text/otzaria_markup.dart';

/// גרסת ממיר ה-HTML — **חובה להעלות בכל שינוי שמשפיע על הפלט**: הגרסה היא
/// חלק ממפתח-התוקף של מטמון ההמרות, והעלאתה פוסלת רשומות ישנות.
const int kHtmlConverterVersion = 3;

/// מגבלות משאבים על מסמך HTML.
///
/// בניגוד ל-DOCX ול-EPUB, קובץ HTML מגיע לרוב מהאינטרנט ולא ממפיק מסמכים.
/// המגבלות כאן הן מה שמונע ממנו למשוך את ההמרה לזיכרון בלתי מוגבל או
/// לרקורסיה עמוקה.
class HtmlLimits {
  /// גודל המקור המרבי. מסמך גדול מכך אינו ספר אלא dump.
  static const int maxSourceBytes = 64 * 1024 * 1024;

  /// עומק הקינון המרבי בהליכה על העץ. מסמך אמיתי רחוק מכאן; מסמך שנבנה
  /// כדי להפיל את הממיר מגיע לאלפים.
  static const int maxNestingDepth = 200;

  /// מספר ההצהרות המרבי ב-`style` יחיד. מעבר לכך אין מה לנתח.
  static const int maxStyleDeclarations = 64;

  /// אורך מרבי לערך `id` שנשמר כעוגן.
  static const int maxAnchorIdLength = 128;
}

/// ממיר מסמך HTML עצמאי (.html/.htm) לפורמט הטקסט של אוצריא: שורת `<h1>`
/// עם שם הספר, ואחריה שורה לכל בלוק (פסקה/כותרת/טבלה/תמונה).
///
/// **חוזה האבטחה — הפלט נבנה מאפס ולעולם אינו מעתיק markup מהמקור.** אין
/// מסלול שבו תגית או מאפיין מהקובץ מגיעים כמות שהם לגוף הספר: כל תגית
/// נכתבת מרשימת ההיתר של הממיר, וכל ערך שנכנס ל-`style`/`href`/`src` עובר
/// אימות מוקלד. משמעות מעשית:
///
/// * `<script>`, `<style>`, `<iframe>`, `<object>`, `<embed>`, `<svg>` ופקדי
///   טופס — נמחקים **עם תוכנם**; תוכנם אינו טקסט קריא.
/// * מאפייני `on…` (כל מטפלי האירועים) פשוט אינם קיימים בפלט.
/// * `href` מוגבל ל-[kAllowedLinkSchemes], לעוגן פנימי ולקישורים שפותחים ספר
///   (`book://`, [isOtzariaBookLink]) — `javascript:`, `data:` ושאר פעולות
///   `otzaria://` נופלות מחוץ לרשימה, והקישור מוצג כטקסט.
/// * `src` של תמונה מוגבל ל-data URI מאומת או לקובץ **בתוך תיקיית הספר**;
///   כתובת רשת מדולגת — אין גישת רשת בהמרה ואין בקורא.
/// * תגית שאינה מוכרת אינה מוחקת תוכן: היא נפתחת (unwrap) והטקסט שבתוכה
///   נשמר. אובדן עיצוב מותר; אובדן תוכן — לא.
///
/// [embedImages] `false` משמר את תגי התמונה בלי לקרוא את הבייטים — הפלט
/// שומר על **אותו מספר שורות** בדיוק, שאם לא כן אינדקסי תוכן העניינים
/// וההערות האישיות היו זזים מול מה שהקורא רואה.
/// [baseDirectory] היא תיקיית קובץ ה-HTML, שרק בתוכה נפתרות תמונות יחסיות.
/// [archivedImages] מחליף אותה כשהתמונות שמורות בתוך המסמך עצמו (MHTML).
/// [format] היא הסיומת שזוהתה בפועל, והיא זו שנרשמת בחריגות. בלעדיה כל כשל
/// של קובץ .htm היה מדווח כ-.html — בניגוד לעיקרון ש-`fileType` הוא זהות
/// ולא תווית.
String htmlToText(
  Uint8List bytes,
  String title, {
  bool embedImages = true,
  String? baseDirectory,
  ArchivedImageLookup? archivedImages,
  DocumentFormat format = DocumentFormat.html,
  int maxTotalEmbeddedImageBytes = EmbeddedMediaLimits.maxTotalImageBytes,
}) {
  // מכולה בינארית שהוסוותה בסיומת .html: פענוח הבייטים שלה כטקסט מייצר
  // ג'יבריש עברי שנראה כספר תקין לגמרי — והוא נשמר במטמון ונכנס לאינדקס.
  if (isBinaryContainerHeader(bytes)) {
    throw UnsupportedDocumentFormatException(
      format: format,
      cause: 'הקובץ הוא מכולה בינארית ואינו HTML',
    );
  }
  if (bytes.length > HtmlLimits.maxSourceBytes) {
    throw CorruptedDocumentException(
      format: format,
      cause: 'מסמך של ${bytes.length} בתים (מעל ${HtmlLimits.maxSourceBytes})',
    );
  }

  // `otzariaInlineText` על הכותרת: שם קובץ יכול להכיל שורה חדשה, והיא
  // הייתה מפצלת את שורה 0 לשתיים — ואז שכבת המטמון, שמזהה את שורת הכותרת
  // לפי הקידומת `<h1>`, מחליפה חצי שורה.
  final output = <String>[
    otzariaInlineText('<h1>${escapeHtmlText(title)}</h1>'),
  ];

  final dom.Document document;
  try {
    document = html_parser.parse(
      _stripSelfClosingRawTextTags(_decodeHtmlBytes(bytes)),
    );
  } catch (e) {
    throw CorruptedDocumentException(format: format, cause: e);
  }

  final root = document.body ?? document.documentElement;
  if (root == null) return output.join('\n');

  final ctx = _HtmlContext(
    images: _HtmlImageResolver(
      baseDirectory: baseDirectory,
      archivedImages: archivedImages,
      embedImages: embedImages,
      maxTotalBytes: maxTotalEmbeddedImageBytes,
    ),
    referencedAnchors: _collectReferencedAnchors(document),
  );
  // גם אחרי מגבלת העומק של הממיר, `package:html` עצמו מהלך רקורסיבית על
  // העץ (טקסט של תת-עץ, בוררים). מסמך מקונן לעומק קיצוני מפיל שם את
  // המחסנית, ו-`StackOverflowError` שבורח מכאן היה חוצה את גבול ה-isolate
  // כשגיאה שהצנרת אינה מצפה לה במקום כחריגת "קובץ פגום".
  try {
    _processBlockChildren(
      root.nodes,
      ctx,
      output,
      depth: 0,
      // `dir` יושב לרוב על `<html>`, שאינו אחד הצמתים שעוברים כאן — בלי
      // הזריעה מסמך שכולו LTR היה נקרא בכיווניות ברירת המחדל של הקורא.
      inherited: _rootStyle(document.documentElement),
    );
  } on StackOverflowError {
    throw CorruptedDocumentException(
      format: format,
      cause: 'קינון עמוק מדי במסמך',
    );
  }
  return output.join('\n');
}

// ── קידוד ─────────────────────────────────────────────────────────────────

/// מפענח את בייטי המסמך לטקסט.
///
/// סדר ההכרעה זהה לזה של הדפדפן: BOM גובר על הכול, ואחריו הצהרת
/// `<meta charset>`. ההצהרה מתקבלת **רק** כשהיא וההכרעה האוטומטית שתיהן
/// קידוד עברי מדור קודם — שם הזיהוי בוחר בין Windows-1255, ISO-8859-8 ו-CP862
/// לפי ניקוד, וההצהרה היא עדות טובה יותר. הצהרה שסותרת UTF-8/16/32 שאומת
/// **אינה** מתקבלת: זו בדיוק המלכודת שהופכת ספר תקין לג'יבריש, שכן דפים ישנים
/// רבים נשמרו מחדש ב-UTF-8 בלי לעדכן את התגית.
String _decodeHtmlBytes(Uint8List bytes) {
  final detected = decodeTextBytesSmartDetailed(bytes);
  if (detected.hadBom) return detected.text;

  final declared = _declaredCharset(bytes);
  if (declared == null || declared == detected.encoding) return detected.text;
  if (declared.isLegacyHebrew && detected.encoding.isLegacyHebrew) {
    return decodeTextBytesWith(bytes, declared);
  }
  return detected.text;
}

/// חלון הסריקה אחרי הצהרת הקידוד. לפי תקן ה-HTML היא חייבת לשבת ב-1024
/// הבתים הראשונים; החלון כאן רחב יותר כדי לסלוח למסמכים לא-תקניים.
const int _charsetSniffWindow = 8 * 1024;

final RegExp _metaCharsetPattern = RegExp(
  r'''<meta[^>]+charset\s*=\s*["'\s]?([a-zA-Z0-9_\-]+)''',
  caseSensitive: false,
);

/// שמות הקידודים שהצהרת המסמך יכולה לנקוב בהם, מנורמלים.
const Map<String, TextEncoding> _charsetAliases = {
  'utf-8': TextEncoding.utf8,
  'utf8': TextEncoding.utf8,
  'windows-1255': TextEncoding.windows1255,
  'cp1255': TextEncoding.windows1255,
  'x-cp1255': TextEncoding.windows1255,
  'iso-8859-8': TextEncoding.iso88598,
  'iso-8859-8-i': TextEncoding.iso88598,
  'iso8859-8': TextEncoding.iso88598,
  'ibm862': TextEncoding.cp862,
  'cp862': TextEncoding.cp862,
  'dos-862': TextEncoding.cp862,
  'utf-16': TextEncoding.utf16LE,
  'utf-16le': TextEncoding.utf16LE,
  'utf-16be': TextEncoding.utf16BE,
};

/// הקידוד שהמסמך מצהיר עליו, או `null` כשאין הצהרה מוכרת. הקריאה היא
/// כ-code units של ASCII: שם הקידוד הוא ASCII בכל הקידודים שמדובר בהם.
TextEncoding? _declaredCharset(Uint8List bytes) {
  final limit = bytes.length < _charsetSniffWindow
      ? bytes.length
      : _charsetSniffWindow;
  final head = String.fromCharCodes(bytes, 0, limit);
  final match = _metaCharsetPattern.firstMatch(head);
  if (match == null) return null;
  return _charsetAliases[match.group(1)!.toLowerCase()];
}

/// תג raw-text סוגר-עצמו (`<script/>`, `<title/>`) — חוקי ב-XHTML, אך בפרסינג
/// HTML התג נחשב פתוח וכל שאר המסמך נבלע כטקסט גולמי. תג כזה ריק ממילא.
final RegExp _selfClosingRawTextTag = RegExp(
  r'<(?:script|style|title|textarea)\b[^<>]*/>',
  caseSensitive: false,
);

String _stripSelfClosingRawTextTags(String html) =>
    html.replaceAll(_selfClosingRawTextTag, '');

// ── מצב ההמרה ─────────────────────────────────────────────────────────────

class _HtmlContext {
  _HtmlContext({required this.images, required this.referencedAnchors});

  final _HtmlImageResolver images;

  /// ה-`id`/`name` שקישור פנימי במסמך מפנה אליהם. רק הם נשמרים כעוגנים,
  /// כדי שהפלט לא יתמלא ב-`<a id>` שאיש אינו מפנה אליהם.
  final Set<String> referencedAnchors;

  /// בתוך `<pre>` — רווחים ושורות חדשות הם תוכן ואין לכווץ אותם.
  bool preserveWhitespace = false;

  /// ה-`id`ים שכבר נפלטו, כדי שעוגן כפול לא יופיע פעמיים.
  final Set<String> emittedAnchors = {};

  /// גופי הערות שכבר הוזרקו בנקודת ההפניה שלהם.
  final Set<dom.Element> consumedFootnoteBodies = {};

  /// מיקום כל צומת בין אחיו, לפי ההורה — נבנה פעם אחת לכל הורה.
  ///
  /// בלעדיו כל חיפוש אח הוא `indexOf` בעלות O(n), ומסמך עם אלפי סימוני
  /// הערות באותה פסקה הופך לריבועי: מיליון סימונים נמדדו בדקות.
  final Map<dom.Node, Map<dom.Node, int>> _siblingIndex = {};

  int indexAmongSiblings(dom.Node parent, dom.Node node) {
    final positions = _siblingIndex.putIfAbsent(parent, () {
      final built = <dom.Node, int>{};
      for (var i = 0; i < parent.nodes.length; i++) {
        built[parent.nodes[i]] = i;
      }
      return built;
    });
    return positions[node] ?? -1;
  }

  /// עוגנים של עטיפות שקופות, שממתינים לשורת התוכן הבאה. עטיפה אינה שורה
  /// בפני עצמה, ופליטת `<a id>` לבדה הייתה מייצרת שורה ריקה בקורא.
  final List<String> _pendingAnchors = [];

  void deferAnchor(String anchor) => _pendingAnchors.add(anchor);

  /// מוציא עוגן ממתין אחד, לשיבוץ ישיר בתגית (למשל `id` על `<h2>`).
  /// כך עוטף שכל תוכנו כותרת אינו מייצר שורת-עוגן ריקה לפניה.
  String? takePendingAnchor() =>
      _pendingAnchors.isEmpty ? null : _pendingAnchors.removeAt(0);

  /// מסיר עוגן שעדיין ממתין ומחזיר אותו, או `null` אם כבר נפלט.
  /// משמש עוטף שתת-העץ שלו לא ייצר אף שורה — היעד שלו לא ייעלם.
  String? takeDeferred(String anchor) =>
      _pendingAnchors.remove(anchor) ? anchor : null;

  /// קידומת העוגנים לשורה הנפלטת כעת — הממתינים ואחריהם העוגן שלה עצמה.
  String anchorPrefix(String? own) {
    if (_pendingAnchors.isEmpty && own == null) return '';
    final anchors = [..._pendingAnchors, ?own];
    _pendingAnchors.clear();
    return anchors
        .where(emittedAnchors.add)
        .map((a) => '<a id="${escapeHtmlAttribute(a)}"></a>')
        .join();
  }
}

/// כל היעדים של קישורים פנימיים (`href="#…"`) במסמך.
///
/// ההליכה איטרטיבית ולא דרך `querySelectorAll`: המימוש שלו ב-package:html
/// רקורסיבי לעומק העץ, ומסמך של 130KB עם קינון עמוק הפיל את המחסנית —
/// לפני שמגבלת העומק של הממיר בכלל הספיקה לרוץ.
Set<String> _collectReferencedAnchors(dom.Document document) {
  final anchors = <String>{};
  final stack = <dom.Node>[document];
  while (stack.isNotEmpty) {
    final node = stack.removeLast();
    if (node is dom.Element && node.localName == 'a') {
      final href = node.attributes['href'];
      if (href != null && href.startsWith('#') && href.length > 1) {
        anchors.add(_decodeFragment(href.substring(1)));
      }
    }
    stack.addAll(node.nodes);
  }
  return anchors;
}

String _decodeFragment(String raw) {
  try {
    return Uri.decodeComponent(raw);
  } catch (_) {
    return raw;
  }
}

// ── תמונות ────────────────────────────────────────────────────────────────

/// טיפוסי התמונה שמותר להטמיע ממסמך HTML.
///
/// SVG **אינו** ברשימה, בשונה מ-EPUB ו-ODT: הוא מסמך XML שיכול לשאת
/// `<script>`, וקובץ HTML מגיע לרוב מהאינטרנט ולא ממפיק מסמכים. מנוע התצוגה
/// אינו מרנדר SVG בלאו הכי, כך שהאיסור אינו עולה דבר — אבל הוא מונע מהמטמון
/// ומהאינדקס להחזיק סקריפט חי.
const Set<String> _embeddableImageMimes = {
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/bmp',
  'image/webp',
};

/// `data:<mime>;base64,<payload>` — הצורה היחידה שמתקבלת. data URI שאינו
/// base64 (`data:image/svg+xml,<svg …>`) נדחה: הוא נושא markup חי.
final RegExp _dataUriPattern = RegExp(
  r'^data:([a-zA-Z0-9./+-]+)\s*;\s*base64\s*,',
  caseSensitive: false,
);

/// תמונה ששמורה בתוך המסמך עצמו, לפי ה-`src` שלה; `null` כשאין כזו.
typedef ArchivedImageLookup =
    ({String mime, Uint8List bytes})? Function(String src);

/// תוצאת פתרון תמונה: האם יש בכלל מה להציג, ומה ה-URI.
///
/// ההפרדה חיונית: ההחלטה **האם** לפלוט `<img>` חייבת להיות זהה בשני מצבי
/// [htmlToText] — אחרת מספר השורות משתנה בין הווריאנט המוצג לזה שמאונדקס.
class _ResolvedImage {
  const _ResolvedImage(this.uri);
  const _ResolvedImage.missing() : uri = null;

  final String? uri;
  bool get exists => uri != null;
}

class _HtmlImageResolver {
  _HtmlImageResolver({
    required this.baseDirectory,
    this.archivedImages,
    required this.embedImages,
    required this.maxTotalBytes,
  });

  final String? baseDirectory;
  final ArchivedImageLookup? archivedImages;
  final bool embedImages;
  final int maxTotalBytes;

  int _embeddedBytes = 0;
  final Map<String, _ResolvedImage> _cache = {};

  /// פותר `src` של תמונה. מחזיר [_ResolvedImage.missing] כשאין מה להציג —
  /// ואז התג עצמו אינו נפלט כלל.
  _ResolvedImage resolve(String? src) {
    final value = src?.trim();
    if (value == null || value.isEmpty) return const _ResolvedImage.missing();
    final cached = _cache[value];
    if (cached != null) return cached;
    return _cache[value] = _resolveUncached(value);
  }

  _ResolvedImage _resolveUncached(String src) {
    if (_dataUriPattern.hasMatch(src)) return _resolveDataUri(src);
    final archived = archivedImages;
    if (archived != null) return _resolveArchived(archived(src));
    return _resolveLocalFile(src);
  }

  _ResolvedImage _resolveArchived(({String mime, Uint8List bytes})? image) {
    if (image == null || !_embeddableImageMimes.contains(image.mime)) {
      return const _ResolvedImage.missing();
    }
    if (!_reserve(image.bytes.length)) return const _ResolvedImage.missing();
    return _ResolvedImage(
      embedImages
          ? 'data:${image.mime};base64,${base64Encode(image.bytes)}'
          : '',
    );
  }

  _ResolvedImage _resolveDataUri(String src) {
    final match = _dataUriPattern.firstMatch(src)!;
    final mime = match.group(1)!.toLowerCase();
    if (!_embeddableImageMimes.contains(mime)) {
      return const _ResolvedImage.missing();
    }
    final Uint8List data;
    try {
      data = base64Decode(
        src.substring(match.end).replaceAll(_base64Whitespace, ''),
      );
    } catch (_) {
      return const _ResolvedImage.missing();
    }
    if (!_reserve(data.length)) return const _ResolvedImage.missing();
    // הקידוד מחדש מהבייטים המפוענחים הוא מה שמבטיח שהמחרוזת שנכנסת לגוף
    // הספר היא base64 תקין ולא טקסט שרירותי שהמסמך שתל אחרי הפסיק.
    return _ResolvedImage(
      embedImages ? 'data:$mime;base64,${base64Encode(data)}' : '',
    );
  }

  /// תמונה שיושבת לצד קובץ ה-HTML. כתובת רשת, `file:` ו-`//host/x` נופלות
  /// כאן: אין להן נתיב מקומי בתוך תיקיית הספר, וטעינה מהרשת אסורה בהמרה
  /// ובקורא כאחד.
  _ResolvedImage _resolveLocalFile(String src) {
    final base = baseDirectory;
    if (base == null) return const _ResolvedImage.missing();
    if (src.startsWith('//') || src.startsWith('/')) {
      return const _ResolvedImage.missing();
    }
    if (_schemePattern.hasMatch(src)) return const _ResolvedImage.missing();

    var relative = src.split('#').first.split('?').first;
    if (relative.isEmpty) return const _ResolvedImage.missing();
    try {
      relative = Uri.decodeComponent(relative);
    } catch (_) {}

    final resolved = p.normalize(p.join(base, relative));
    final String realBase;
    final String realResolved;
    try {
      realBase = Directory(base).resolveSymbolicLinksSync();
      realResolved = File(resolved).resolveSymbolicLinksSync();
    } catch (_) {
      return const _ResolvedImage.missing();
    }
    // מסמך זדוני יכול לבקש `../../` — התמונה נקראת רק מתוך תיקיית הספר.
    if (!p.isWithin(realBase, realResolved)) {
      return const _ResolvedImage.missing();
    }

    final mime = imageMimeForPath(realResolved);
    if (mime == null || !_embeddableImageMimes.contains(mime)) {
      return const _ResolvedImage.missing();
    }

    final file = File(realResolved);
    final FileStat stat;
    try {
      stat = file.statSync();
    } catch (_) {
      return const _ResolvedImage.missing();
    }
    if (stat.type != FileSystemEntityType.file) {
      return const _ResolvedImage.missing();
    }
    if (!_reserve(stat.size)) return const _ResolvedImage.missing();

    // הקריאה מתבצעת בשני המצבים, גם כשהתוכן אינו נדרש. `statSync` יכול
    // להצליח בזמן ש-`readAsBytesSync` נכשל (הרשאות, כונן רשת מנותק,
    // OneDrive "files on demand") — ואז רק אחד משני הווריאנטים היה מגלה
    // זאת, ומספר השורות שלהם היה נבדל. האינדקס ותוכן העניינים היו זזים
    // בשורה מול מה שהקורא מציג.
    final Uint8List bytes;
    try {
      bytes = file.readAsBytesSync();
    } catch (_) {
      return const _ResolvedImage.missing();
    }
    if (!embedImages) return const _ResolvedImage('');
    return _ResolvedImage('data:$mime;base64,${base64Encode(bytes)}');
  }

  /// גובה מהתקציב המצטבר. חורג — התמונה אינה מוצגת, בשני המצבים כאחד.
  bool _reserve(int size) {
    if (size <= 0 || size > EmbeddedMediaLimits.maxImageBytes) return false;
    if (_embeddedBytes + size > maxTotalBytes) return false;
    _embeddedBytes += size;
    return true;
  }
}

/// רווח קשיח (U+00A0). נבנה מקוד התו ולא נכתב כתו: תו בלתי-נראה בקוד המקור
/// נעלם בעריכה, ואז ההזחה של רשימה מקוננת נבלעת בלי שאיש ישים לב.
final String _nbsp = String.fromCharCode(0xA0);

final RegExp _base64Whitespace = RegExp(r'\s');
final RegExp _schemePattern = RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*:');

// ── רשימות התגיות ─────────────────────────────────────────────────────────

/// תגיות שנמחקות **עם תוכנן**: קוד, עיצוב, מדיה שאינה נתמכת ופקדי טופס.
/// תוכנן אינו טקסט קריא, ו-unwrap שלהן היה שופך קוד JavaScript לגוף הספר.
const Set<String> _droppedTags = {
  'applet',
  'area',
  'audio',
  'base',
  'button',
  'canvas',
  'datalist',
  'dialog',
  'embed',
  'frame',
  'frameset',
  'head',
  'iframe',
  'input',
  'link',
  'map',
  'meta',
  'meter',
  'noframes',
  'noscript',
  'object',
  'optgroup',
  'option',
  'param',
  'progress',
  'script',
  'select',
  'source',
  'style',
  'svg',
  'template',
  'textarea',
  'title',
  'track',
  'video',
};

/// אלמנטים שנחשבים בלוק — כלומר שוברים שורת ספר.
///
/// `<img>` **אינו** ברשימה: הוא inline בטבעו, ומהרגע שהיה נחשב בלוק הוא
/// נעלם מכל מקום שאוסף תוכן כ-inline (פריט רשימה, תא בטבלה) — כי אין לו
/// ילדים לרדת אליהם. תמונה שעומדת לבדה בעטיפה הופכת ממילא לשורה משלה.
const Set<String> _blockTags = {
  'address', 'article', 'aside', 'blockquote', 'caption', 'center', 'details',
  'div', 'dd', 'dl', 'dt', 'fieldset', 'figcaption', 'figure', 'footer',
  'form', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hgroup', 'hr',
  'legend', 'li', 'main', 'menu', 'nav', 'ol', 'p', 'pre', 'section',
  'summary', 'table', 'tbody', 'td', 'tfoot', 'th', 'thead', 'tr', 'ul', //
};

/// תגיות inline שנשמרות כמו-שהן. השאר (span/label/q…) שקופות — העיצוב שלהן,
/// אם הוצהר ב-`style`, נקרא בנפרד.
///
/// המיפוי הוא ל**תגית שמנוע התצוגה מכיר**: `<cite>` ו-`<var>` מוצגים נטויים
/// והמנוע מכיר אותם, אבל `<i>` נתמך גם במצב הקריאה הרציפה ולכן הוא היעד.
const Map<String, String> _inlineKeepTags = {
  'b': 'b', 'strong': 'b',
  'i': 'i', 'em': 'i', 'cite': 'i', 'dfn': 'i', 'var': 'i',
  'u': 'u', 'ins': 'u',
  's': 's', 'del': 's', 'strike': 's',
  'sub': 'sub', 'sup': 'sup',
  'small': 'small', 'big': 'big',
  'code': 'code', 'kbd': 'code', 'samp': 'code', 'tt': 'code',
  // קו מנוקד. `<acronym>` הוצא מהתקן אך הקורא מציג אותו זהה ל-`<abbr>`.
  'abbr': 'abbr', 'acronym': 'abbr',
  // פירוש קטן מעל מילה. בלי שימור התגיות שני הטקסטים נדבקים זה לזה
  // («אנפיןפנים») — כלומר אובדן תוכן ולא רק אובדן עיצוב.
  'ruby': 'ruby', 'rt': 'rt', 'rp': 'rp', //
};

bool _isBlockElement(dom.Node node) =>
    node is dom.Element && _blockTags.contains(node.localName);

bool _containsBlockChildren(dom.Element e) => e.nodes.any(_isBlockElement);

// ── הליכה על בלוקים ───────────────────────────────────────────────────────

/// מעבד רצף צאצאים ומוסיף שורות ל-[output]. רצף inline בין בלוקים (טקסט
/// חשוף בתוך `div`) נאסף לשורת פסקה משלו, כדי שלא ייבלע.
void _processBlockChildren(
  List<dom.Node> nodes,
  _HtmlContext ctx,
  List<String> output, {
  required int depth,
  _BlockStyle? inherited,
}) {
  if (depth > HtmlLimits.maxNestingDepth) return;

  final inlineRun = <dom.Node>[];

  void flushInlineRun() {
    if (inlineRun.isEmpty) return;
    final buf = StringBuffer();
    for (final node in inlineRun) {
      _renderInlineNode(node, ctx, buf, depth: depth + 1);
    }
    inlineRun.clear();
    _addLine(output, buf.toString(), inherited, ctx);
  }

  for (final node in nodes) {
    if (node is dom.Element && _droppedTags.contains(node.localName)) {
      continue;
    }
    if (_isBlockElement(node)) {
      flushInlineRun();
      _processBlockElement(
        node as dom.Element,
        ctx,
        output,
        depth: depth,
        inherited: inherited,
      );
    } else {
      inlineRun.add(node);
    }
  }
  flushInlineRun();
}

void _processBlockElement(
  dom.Element e,
  _HtmlContext ctx,
  List<String> output, {
  required int depth,
  _BlockStyle? inherited,
}) {
  final tag = e.localName ?? '';
  if (_droppedTags.contains(tag)) return;
  final declarations = _parseStyleAttribute(e.attributes['style']);
  if (_isHidden(e, declarations)) return;

  final style = _BlockStyle.of(e, declarations, inherited);
  final anchor = _anchorFor(e, ctx);

  /// עיצוב הבלוק עצמו — נצמד רק לבלוק שנפלט כשורה אחת (ראו [_BlockStyle.css]).
  _BlockStyle leafStyle() => style.withCss(
    cssStyleFrom(
      declarations,
      blockOnly: true,
      skip: _blockStyleProperties,
    ),
  );

  switch (tag) {
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
      // הסטה רמה אחת מטה — `<h1>` שמור לשם הספר (שורת הפתיחה).
      final level = (int.parse(tag.substring(1)) + 1).clamp(2, 6);
      final text = _renderInlineChildren(e, ctx, depth: depth + 1).trim();
      if (text.isEmpty) return;
      // הכותרת אינה נעטפת ב-`<div>`: `TocParser` מזהה כותרת רק בשורה שפותחת
      // ב-`<h#`, ועטיפה הייתה מוציאה אותה מתוכן העניינים. לכן גם העוגן
      // והכיווניות יושבים על התגית עצמה.
      // עוגן של עוטף נכנס אל תוך תגית הכותרת עצמה, ולא כשורה נפרדת לפניה:
      // שורה שכולה `<a id>` מתרנדרת ריקה בקורא ותופסת אינדקס.
      final headingAnchor = anchor ?? ctx.takePendingAnchor();
      final attributes = StringBuffer();
      if (headingAnchor != null) {
        attributes.write(' id="$headingAnchor"');
        ctx.emittedAnchors.add(headingAnchor);
      }
      // כותרת עיצובית שהמחבר הוציא במפורש מתוכן העניינים. בלי השימור
      // כאן היא מזהמת את עץ הספר — וזו הסיבה היחידה שהמאפיין קיים.
      if (_isTocExcluded(e)) attributes.write(' $kTocExcludeAttr');
      if (style.emittedDirection != null) {
        attributes.write(' dir="${style.emittedDirection}"');
      }
      final headingCss = leafStyle().css;
      final headingStyles = [
        if (style.align != null) 'text-align: ${style.align}',
        ?headingCss,
      ];
      if (headingStyles.isNotEmpty) {
        attributes.write(' style="${headingStyles.join('; ')}"');
      }
      // עוגן ממתין של עטיפה נפלט לפני הכותרת ולא בתוכה: שורה שאינה פותחת
      // ב-`<h#` אינה נקלטת ב-`TocParser`.
      _emit(output, ctx.anchorPrefix(null));
      _emit(output, '<h$level$attributes>$text</h$level>');

    case 'p':
    case 'figcaption':
    case 'dt':
    case 'dd':
    case 'legend':
      _addLine(
        output,
        _renderInlineChildren(e, ctx, depth: depth + 1),
        leafStyle(),
        ctx,
        anchor: anchor,
      );

    // `<address>` ו-`<blockquote>` הם שורה משל עצמם, אבל התגית עצמה נשמרת:
    // הקורא מציג את הראשון נטוי ואת השני מוזח משני הצדדים, וזה מה שהמחבר
    // התכוון אליו. `<blockquote>` שבתוכו בלוקים מתפרק לשורות שלהם.
    case 'address':
      _addWrappedLine(output, e, ctx, style, anchor, tag, depth: depth);

    case 'blockquote':
      if (_containsBlockChildren(e)) {
        if (anchor != null) ctx.deferAnchor(anchor);
        _processBlockChildren(
          e.nodes,
          ctx,
          output,
          depth: depth + 1,
          inherited: style,
        );
      } else {
        _addWrappedLine(output, e, ctx, style, anchor, tag, depth: depth);
      }

    // קטע מתקפל. `<summary>` הוא הכיתוב הגלוי, וכל השאר מוצג רק בלחיצה —
    // ולכן **כל התג חייב להיות בשורה אחת**. פירוקו לשורות היה חושף את התוכן
    // המוסתר ומאבד את ההתקפלות.
    case 'details':
      _emitDetails(output, e, ctx, style, anchor, depth: depth);

    // `<summary>` מחוץ ל-`<details>` הוא כיתוב רגיל.
    case 'summary':
      _addLine(
        output,
        _renderInlineChildren(e, ctx, depth: depth + 1),
        leafStyle(),
        ctx,
        anchor: anchor,
      );

    // `<caption>` נפלט בתוך `<table>` (ראו [_buildTableHtml]); כאן הוא מגיע
    // רק כשהוא יתום, ואז הוא שורת כיתוב.
    case 'caption':
      _addLine(
        output,
        _renderInlineChildren(e, ctx, depth: depth + 1),
        leafStyle(),
        ctx,
        anchor: anchor,
      );

    case 'pre':
      final previous = ctx.preserveWhitespace;
      ctx.preserveWhitespace = true;
      final text = _renderInlineChildren(e, ctx, depth: depth + 1);
      ctx.preserveWhitespace = previous;
      if (text.trim().isEmpty) return;
      // הכיווניות אינה נכפית: `<pre>` עברי אינו נדיר בספרי קודש, וכפיית
      // LTR הייתה הופכת אותו. הקורא מסדר לפי התו החזק הראשון.
      final preCss = leafStyle().css;
      _emit(
        output,
        '${ctx.anchorPrefix(anchor)}'
        '<pre${preCss == null ? '' : ' style="$preCss"'}>$text</pre>',
      );

    case 'ol':
    case 'ul':
    case 'menu':
      _processList(
        e,
        ctx,
        output,
        ordered: tag == 'ol',
        listDepth: 0,
        depth: depth,
        inherited: style,
      );

    case 'table':
      final table = _buildTableHtml(e, ctx, depth: depth + 1);
      if (table != null) _emit(output, '${ctx.anchorPrefix(anchor)}$table');

    // קו מפריד — שורה משל עצמו, וניתן לעצב אותו (`border-top`).
    case 'hr':
      final css = cssStyleFrom(declarations, blockOnly: true);
      _emit(
        output,
        '${ctx.anchorPrefix(anchor)}'
        '<hr${css == null ? '' : ' style="$css"'}>',
      );

    default:
      // div/section/article/figure/form וכו' — עטיפות שקופות:
      // יורדים לילדיהן. עטיפה שכל תוכנה inline הופכת לשורת פסקה אחת.
      if (_containsBlockChildren(e)) {
        if (anchor != null) ctx.deferAnchor(anchor);
        _processBlockChildren(
          e.nodes,
          ctx,
          output,
          depth: depth + 1,
          inherited: style,
        );
        // תת-העץ לא ייצר אף שורה שתישא את העוגן (כל תוכנו היה מוסתר או
        // ריק). פליטתו כשורה משלו כאן עדיפה על השארתו ממתין — אחרת הוא
        // היה נצמד לשורה הבאה, שאינה קשורה אליו כלל.
        if (anchor != null) {
          final orphan = ctx.takeDeferred(anchor);
          if (orphan != null) _emit(output, ctx.anchorPrefix(orphan));
        }
      } else {
        _addLine(
          output,
          _renderInlineChildren(e, ctx, depth: depth + 1),
          leafStyle(),
          ctx,
          anchor: anchor,
        );
      }
  }
}

/// מוסיף שורת ספר אחת, עטופה בעיצוב הבלוק שלה. שורה ריקה אינה נוספת —
/// והעוגן שהיה מיועד לה ממתין לשורה הבאה, כדי שקישור פנימי לא יאבד את יעדו.
void _addLine(
  List<String> output,
  String html,
  _BlockStyle? style,
  _HtmlContext ctx, {
  String? anchor,
  String indent = '',
}) {
  final text = _trimSoftWhitespace(html);
  if (text.isEmpty) {
    if (anchor != null) ctx.deferAnchor(anchor);
    return;
  }
  // ההזחה נוספת אחרי ה-trim: היא חלק מהתצוגה של פריט רשימה מקונן, ולא
  // רווח מיותר של המסמך.
  final body = '$indent$text';
  _emit(output, '${ctx.anchorPrefix(anchor)}${style?.wrap(body) ?? body}');
}

/// שורת ספר שהתגית עצמה נשמרת בה (`<address>`, `<blockquote>`) — הקורא מציג
/// אותה בעיצוב משלה, וזו כוונת המחבר.
void _addWrappedLine(
  List<String> output,
  dom.Element e,
  _HtmlContext ctx,
  _BlockStyle style,
  String? anchor,
  String tag, {
  required int depth,
}) {
  final text = _renderInlineChildren(e, ctx, depth: depth + 1).trim();
  if (text.isEmpty) {
    if (anchor != null) ctx.deferAnchor(anchor);
    return;
  }
  final css = cssStyleFrom(
    _parseStyleAttribute(e.attributes['style']),
    blockOnly: true,
    skip: _blockStyleProperties,
  );
  final attributes = StringBuffer();
  if (css != null) attributes.write(' style="$css"');
  _emit(
    output,
    '${ctx.anchorPrefix(anchor)}'
    '${style.wrap('<$tag$attributes>$text</$tag>')}',
  );
}

/// קטע מתקפל, כשורת פלט אחת.
void _emitDetails(
  List<String> output,
  dom.Element e,
  _HtmlContext ctx,
  _BlockStyle style,
  String? anchor, {
  required int depth,
}) {
  final summary = StringBuffer();
  final bodyNodes = <dom.Node>[];
  for (final node in e.nodes) {
    if (node is dom.Element && node.localName == 'summary' && summary.isEmpty) {
      _renderInlineNode2(node, ctx, summary, depth: depth + 1);
      continue;
    }
    bodyNodes.add(node);
  }
  // הגוף נאסף לחלקים ומחובר ב-`<br>`, ולא בשרשור ישיר: שתי פסקאות שנדבקות
  // במחרוזת ריקה מייצרות מילה מזויפת שהחיפוש עליה אינו מוצא דבר — אותו
  // מלכוד שמתועד ב-[_collectCellParts].
  final parts = <String>[];
  _collectCellParts(bodyNodes, ctx, parts, depth: depth + 1);
  final body = parts.join('<br>');
  if (summary.isEmpty && body.trim().isEmpty) return;

  final css = cssStyleFrom(
    _parseStyleAttribute(e.attributes['style']),
    blockOnly: true,
    skip: _blockStyleProperties,
  );
  final attributes = StringBuffer();
  // `open` הוא מאפיין בוליאני — הקורא פותח את הקטע מלכתחילה.
  if (e.attributes.containsKey('open')) attributes.write(' open');
  if (css != null) attributes.write(' style="$css"');
  _emit(
    output,
    '${ctx.anchorPrefix(anchor)}'
    '${style.wrap('<details$attributes>'
    '<summary>${summary.toString().trim()}</summary>'
    '${body.trim()}'
    '</details>')}',
  );
}

/// מרנדר את **ילדי** האלמנט כ-inline, בלי לפלוט את התגית שלו — לתגיות
/// שהקורא מרכיב בעצמו (`<summary>` בתוך `<details>`).
void _renderInlineNode2(
  dom.Element e,
  _HtmlContext ctx,
  StringBuffer buffer, {
  required int depth,
}) {
  for (final child in e.nodes) {
    _renderInlineNode(child, ctx, buffer, depth: depth + 1);
  }
}

/// התכונות ש-[_BlockStyle] כבר כותב בעצמו — כתיבתן שוב מתוך ה-`style` המקורי
/// הייתה מכפילה את אותה הצהרה על אותו אלמנט.
const Set<String> _blockStyleProperties = {'text-align', 'direction'};

/// גוזם רווח לבן מקצות השורה — **בלי** לגעת ברווח קשיח.
///
/// `String.trim()` של דארט מסיר גם U+00A0, שהוא בדיוק התו שהמחבר כתב
/// (`&nbsp;`) כדי שהרווח **לא** יתכווץ: הזחת פסקה בתחילת שורה נמחקה.
String _trimSoftWhitespace(String s) {
  var start = 0;
  var end = s.length;
  while (start < end && _isSoftWhitespace(s.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _isSoftWhitespace(s.codeUnitAt(end - 1))) {
    end--;
  }
  return start == 0 && end == s.length ? s : s.substring(start, end);
}

bool _isSoftWhitespace(int unit) =>
    unit == 0x20 ||
    unit == 0x09 ||
    unit == 0x0A ||
    unit == 0x0D ||
    unit == 0x0C;

/// שורת פלט אחת. פלט אוצריא מופרד ב-`\n`, ולכן שורה חדשה **בתוך** התוכן
/// הייתה מפצלת פסקה לכמה "שורות" ומסיטה את אינדקסי תוכן העניינים ואת עוגני
/// ההערות האישיות מול מה שהקורא רואה.
void _emit(List<String> output, String html) {
  if (html.isEmpty) return;
  output.add(otzariaInlineText(html));
}

// ── עיצוב ברמת הבלוק ──────────────────────────────────────────────────────

/// היישור והכיווניות של בלוק, אחרי יישוב `style`, מאפיינים מדור קודם
/// (`align`/`dir`) והתגית עצמה (`<center>`), וירושה מהעוטף.
class _BlockStyle {
  const _BlockStyle({this.align, this.direction, this.css});

  final String? align;
  final String? direction;

  /// שאר הצהרות ה-CSS של הבלוק (מסגרת, ריווח, גופן…). **אינה נורשת**:
  /// מסגרת של עוטף אינה יכולה להימתח על כמה שורות ספר נפרדות, ולכן היא
  /// נשמרת רק לבלוק שנפלט כשורה אחת.
  final String? css;

  _BlockStyle withCss(String? value) =>
      _BlockStyle(align: align, direction: direction, css: value);

  static _BlockStyle of(
    dom.Element e,
    Map<String, String> declarations,
    _BlockStyle? inherited,
  ) {
    final direction =
        _cssDirection(declarations['direction']) ??
        _cssDirection(e.attributes['dir']) ??
        inherited?.direction;
    final align = e.localName == 'center'
        ? 'center'
        : _cssTextAlign(
            declarations['text-align'] ?? e.attributes['align'],
            isRtl: direction == 'rtl',
          );
    return _BlockStyle(align: align ?? inherited?.align, direction: direction);
  }

  /// הכיווניות שיש לכתוב בפועל.
  ///
  /// `rtl` **אינו** נכתב לעולם: הקורא כולו RTL (locale he_IL), ולכן ההצהרה
  /// היא no-op — ומסמך עברי מצהיר עליה כמעט על כל אלמנט, כך שכתיבתה הייתה
  /// עוטפת כל שורה בספר ב-`<div>` מיותר.
  String? get emittedDirection => direction == 'ltr' ? 'ltr' : null;

  /// עוטף שורת תוכן. `<div>` נכתב רק כשיש מה להצהיר עליו — עטיפה ריקה
  /// מנפחת כל שורה בספר.
  String wrap(String html) {
    final dir = emittedDirection;
    if (align == null && dir == null && css == null) return html;
    final attributes = StringBuffer();
    if (dir != null) attributes.write(' dir="$dir"');
    final styles = [if (align != null) 'text-align: $align', ?css];
    if (styles.isNotEmpty) attributes.write(' style="${styles.join('; ')}"');
    return '<div$attributes>$html</div>';
  }
}

/// הכיווניות של `<html>` בלבד — היישור שלו אינו רלוונטי (הוא חל על כל
/// המסמך ואינו הצהרה על בלוק מסוים).
_BlockStyle? _rootStyle(dom.Element? root) {
  if (root == null) return null;
  final direction =
      _cssDirection(
        _parseStyleAttribute(root.attributes['style'])['direction'],
      ) ??
      _cssDirection(root.attributes['dir']);
  return direction == null ? null : _BlockStyle(direction: direction);
}

String? _cssDirection(String? value) => switch (value?.trim().toLowerCase()) {
  'rtl' => 'rtl',
  'ltr' => 'ltr',
  _ => null,
};

/// יישור לערך CSS, לפי **כלל היישור** של חוזה ההמרה: `center` תמיד נכתב,
/// ערך פיזי נכתב (HTML מצהיר על יישור רק כשהוא מפורש), `justify` נופל
/// לברירת המחדל של אוצריא, וערך לוגי (`start`/`end`) מדולג בבלוק RTL —
/// שם המפיקים חלוקים בפירושו, וההכרעה השגויה מיישרת ספר שלם לצד ההפוך.
String? _cssTextAlign(String? value, {required bool isRtl}) =>
    switch (value?.trim().toLowerCase()) {
      'center' => 'center',
      'left' => 'left',
      'right' => 'right',
      'start' => isRtl ? null : 'left',
      'end' => isRtl ? null : 'right',
      _ => null,
    };

// ── רשימות ────────────────────────────────────────────────────────────────

/// רשימות מרונדרות כשורות עם קידומת והזחה לפי עומק — לא `<ol>`/`<ul>`,
/// שנשברים בפורמט שורה-לכל-בלוק, באותה גישה כמו בממירי DOCX ו-EPUB.
///
/// **שורה לכל פריט** ולא רשימה אחת בשורה: זו היחידה שהערה אישית, סימנייה
/// ותוצאת חיפוש נתלות בה, ורשימה שלמה בשורה אחת הייתה הופכת עשרה פריטים
/// לעוגן בודד.
void _processList(
  dom.Element list,
  _HtmlContext ctx,
  List<String> output, {
  required bool ordered,
  required int listDepth,
  required int depth,
  _BlockStyle? inherited,
}) {
  if (depth > HtmlLimits.maxNestingDepth) return;

  final marker = _ListMarker.of(list, ordered: ordered);
  final items = list.children.where((e) => e.localName == 'li').toList();
  // `reversed` — המספור יורד מאורך הרשימה ועד 1, אלא אם `start` הצהיר אחרת.
  // נספרים רק הפריטים הנראים, כדי שהספירה תסתיים ב-1 ולא באמצע.
  final isReversed = list.attributes.containsKey('reversed');
  var number =
      int.tryParse(list.attributes['start'] ?? '') ??
      (isReversed ? items.where(_isVisibleListItem).length : 1);
  // ההזחה נכתבת ברווחים קשיחים: HTML מכווץ רווח מוביל, ובלעדיהם פריט מקונן
  // היה מוצג באותו מקום כמו פריט ברמה הראשונה.
  final indent = _nbsp * 4 * listDepth;

  // תוכן שיושב ישירות ב-`<ol>`/`<ul>` ואינו `<li>` — HTML לא תקני, אבל
  // קיים בשטח. בלי האיסוף כאן הוא לא היה נסרק **אף פעם** והטקסט היה נעלם.
  final strays = <dom.Node>[];
  void flushStrays() {
    if (strays.isEmpty) return;
    final pending = List<dom.Node>.of(strays);
    strays.clear();
    _processBlockChildren(
      pending,
      ctx,
      output,
      depth: depth + 1,
      inherited: inherited,
    );
  }

  for (final node in list.nodes) {
    if (node is! dom.Element || node.localName != 'li') {
      strays.add(node);
      continue;
    }
    flushStrays();
    final item = node;
    final declarations = _parseStyleAttribute(item.attributes['style']);
    if (_isHidden(item, declarations)) continue;
    number = int.tryParse(item.attributes['value'] ?? '') ?? number;

    final style = _BlockStyle.of(item, declarations, inherited).withCss(
      cssStyleFrom(
        declarations,
        blockOnly: true,
        skip: _blockStyleProperties,
      ),
    );
    final anchor = _anchorFor(item, ctx);

    final nested = <dom.Element>[];
    final content = <dom.Node>[];
    for (final node in item.nodes) {
      if (node is dom.Element && _droppedTags.contains(node.localName)) {
        continue;
      }
      // רשימה מקוננת מוסתרת מדולגת כליל — לא נאספת ולא מרונדרת.
      if (node is dom.Element && _isElementHidden(node)) continue;
      if (node is dom.Element &&
          const {'ol', 'ul', 'menu'}.contains(node.localName)) {
        nested.add(node);
        continue;
      }
      content.add(node);
    }

    // תוכן הפריט נאסף לחלקים ומחובר ב-`<br>`: בלוק בתוך פריט (פסקה, כותרת)
    // נשאר באותה שורה — פיצולו היה מנתק את התווית מהתוכן שהיא מתארת — אבל
    // בלי מפריד שתי פסקאות היו נדבקות למילה אחת שהחיפוש אינו מוצא.
    final parts = <String>[];
    _collectCellParts(content, ctx, parts, depth: depth + 1);
    final text = parts.join('<br>').trim();
    if (text.isNotEmpty) {
      // ההזחה והתווית עוברות כקידומת ולא כחלק מהתוכן: `_addLine` מריץ
      // `trim()` על התוכן, ו-`trim()` של דארט מסיר גם רווח קשיח — כך
      // שתווית `none` (שכולה רווח קשיח) הייתה נבלעת.
      _addLine(
        output,
        text,
        style,
        ctx,
        anchor: anchor,
        indent: '$indent${marker.labelFor(number)} ',
      );
    } else if (anchor != null) {
      ctx.deferAnchor(anchor);
    }
    // המונה מתקדם גם על פריט ריק: הדפדפן סופר אותו, ודילוג היה מסיט את
    // מספרי כל הפריטים שאחריו מול המסמך המקורי.
    number += isReversed ? -1 : 1;
    for (final child in nested) {
      _processList(
        child,
        ctx,
        output,
        ordered: child.localName == 'ol',
        listDepth: listDepth + 1,
        depth: depth + 1,
        inherited: style,
      );
    }
  }
  flushStrays();
}

/// פריט רשימה שאינו מוסתר — רק אלה נספרים למספור יורד.
bool _isVisibleListItem(dom.Element item) => !_isElementHidden(item);

/// קיצור ל-[_isHidden] כשההצהרות עדיין לא פורסרו.
bool _isElementHidden(dom.Element e) =>
    _isHidden(e, _parseStyleAttribute(e.attributes['style']));

/// סוג התווית של רשימה, לפי `type` או `list-style-type`.
class _ListMarker {
  const _ListMarker._(this._format);

  final String? _format;

  static _ListMarker of(dom.Element list, {required bool ordered}) {
    // `list-style-type` הוא מילת מפתח של CSS וחסר רגישות לרישיות; המאפיין
    // `type` דווקא **רגיש** לה — `type="i"` ו-`type="I"` הם פורמטים שונים.
    final declared =
        _parseStyleAttribute(list.attributes['style'])['list-style-type'] ??
        list.attributes['type']?.trim();
    return _ListMarker._(declared ?? (ordered ? 'decimal' : null));
  }

  String labelFor(int number) => switch (_format) {
    'a' => '${toLatinLetters(number, upper: false)}.',
    'A' => '${toLatinLetters(number, upper: true)}.',
    'i' => '${toRomanNumeral(number).toLowerCase()}.',
    'I' => '${toRomanNumeral(number)}.',
    _ => switch (_format?.toLowerCase()) {
      'lower-alpha' ||
      'lower-latin' => '${toLatinLetters(number, upper: false)}.',
      'upper-alpha' ||
      'upper-latin' => '${toLatinLetters(number, upper: true)}.',
      'lower-roman' => '${toRomanNumeral(number).toLowerCase()}.',
      'upper-roman' => '${toRomanNumeral(number)}.',
      'hebrew' => '${toHebrewNumeral(number)}.',
      'lower-greek' => '${_greekLetter(number)}.',
      'decimal-leading-zero' => '${number < 10 ? '0$number' : '$number'}.',
      '1' || 'decimal' => '$number.',
      'circle' => '◦',
      'square' => '▪',
      // `none` — הזחה בלי סימן. רווח קשיח, שכן HTML מכווץ רווח מוביל.
      'none' => _nbsp,
      _ => '•',
    },
  };
}

/// אות יוונית קטנה למספר (α, β, γ …). מעבר ל-24 חוזר לספרות — רשימה יוונית
/// ארוכה מכך אינה קיימת בפועל.
String _greekLetter(int n) {
  const letters = 'αβγδεζηθικλμνξοπρστυφχψω';
  return n >= 1 && n <= letters.length ? letters[n - 1] : '$n';
}

// ── טבלאות ────────────────────────────────────────────────────────────────

/// שורות הטבלה הישירות בלבד (כולל דרך thead/tbody/tfoot) — לא שורות של
/// טבלאות מקוננות בתאים, שמרונדרות רקורסיבית בתוך התא שלהן.
List<dom.Element> _directTableRows(dom.Element table) {
  final rows = <dom.Element>[];
  for (final child in table.children) {
    // שורה או קבוצת שורות מוסתרת מדולגת, כמו כל טקסט מוסתר.
    if (_isElementHidden(child)) continue;
    if (child.localName == 'tr') {
      rows.add(child);
    } else if (const {'thead', 'tbody', 'tfoot'}.contains(child.localName)) {
      rows.addAll(
        child.children.where(
          (e) => e.localName == 'tr' && !_isElementHidden(e),
        ),
      );
    }
  }
  return rows;
}

/// טבלה → `<table>` בשורת פלט אחת (שורה = widget בקורא), כולל
/// colspan/rowspan, רקע תא, יישור אנכי וטבלאות מקוננות.
String? _buildTableHtml(
  dom.Element table,
  _HtmlContext ctx, {
  required int depth,
}) {
  if (depth > HtmlLimits.maxNestingDepth) return null;
  final rows = _directTableRows(table);

  // `<caption>` הוא כיתוב הטבלה ומוצג מעליה. בלי הפליטה כאן הוא נשמט
  // לחלוטין: הוא אינו שורת טבלה, ומסלול הבלוקים אינו יורד לתוך `<table>`.
  // הוא נאסף **לפני** בדיקת השורות, כדי שטבלה שכל תוכנה כיתוב לא תיעלם.
  final caption = StringBuffer();
  for (final child in table.children) {
    if (child.localName != 'caption') continue;
    final declarations = _parseStyleAttribute(child.attributes['style']);
    if (_isHidden(child, declarations)) break;
    final text = _renderInlineChildren(child, ctx, depth: depth + 1).trim();
    if (text.isEmpty) break;
    final css = cssStyleFrom(declarations, blockOnly: true);
    caption.write(
      '<caption${css == null ? '' : ' style="$css"'}>$text</caption>',
    );
    break;
  }

  if (rows.isEmpty && caption.isEmpty) return null;

  final tableDir = _cssDirection(
    _parseStyleAttribute(table.attributes['style'])['direction'] ??
        table.attributes['dir'],
  );

  // כמו בשורת תוכן — רק `ltr` נכתב; RTL הוא ברירת המחדל של הקורא.
  final tableAttributes = StringBuffer();
  if (tableDir == 'ltr') tableAttributes.write(' dir="ltr"');

  // `cellpadding` מתורגם ל-`padding` בפועל על כל תא: חוזה ה-markup של
  // אוצריא כותב `padding` inline לכל תא, והוא דורס כל `cellpadding=` —
  // כך שכתיבת המאפיין לבדה הייתה מאפיין מת.
  final cellPadding = positiveIntegerAttribute(
    table.attributes['cellpadding'],
  );

  final buffer = StringBuffer(
    otzariaTableOpen(attributes: tableAttributes.toString()),
  )..write(caption);

  for (final row in rows) {
    final cells = StringBuffer();
    for (final cell in row.children) {
      final tag = cell.localName;
      if (tag != 'td' && tag != 'th') continue;
      final declarations = _parseStyleAttribute(cell.attributes['style']);
      if (_isHidden(cell, declarations)) continue;

      final attributes = StringBuffer();
      // אימות מספרי-חיובי — העתקה מילולית הייתה מאפשרת הזרקת HTML ממסמך
      // זדוני, וערכי אפס/שלילי שוברים רינדור במנועי תצוגה מסוימים.
      final colspan = int.tryParse(cell.attributes['colspan'] ?? '');
      final rowspan = int.tryParse(cell.attributes['rowspan'] ?? '');
      if (colspan != null && colspan > 1) {
        attributes.write(' colspan="$colspan"');
      }
      if (rowspan != null && rowspan > 1) {
        attributes.write(' rowspan="$rowspan"');
      }

      // חוזה ה-markup של אוצריא הוא הבסיס; `cellpadding` של המסמך דורס בו
      // את הריווח, ואחריו באות ההצהרות של התא עצמו.
      final styles = <String>[
        cellPadding == null
            ? otzariaTableCellStyle
            : otzariaTableCellStyle.replaceFirst(
                RegExp(r'padding:[^;]*'),
                'padding: ${cellPadding}px',
              ),
      ];
      // רקע לבן מדולג בכל הפורמטים — הוא ברירת המחדל ושובר את המצב הכהה.
      final fill = _sanitizeBackground(
        declarations['background-color'] ??
            declarations['background'] ??
            cell.attributes['bgcolor'],
      );
      if (fill != null) styles.add('background-color: $fill');
      final vAlign = cssVerticalAlign(
        _lowerDeclaration(declarations, 'vertical-align') ??
            cell.attributes['valign'],
      );
      if (vAlign != null) styles.add('vertical-align: $vAlign');
      final align = _cssTextAlign(
        declarations['text-align'] ?? cell.attributes['align'],
        isRtl: tableDir == 'rtl',
      );
      if (align != null) styles.add('text-align: $align');
      // שאר ההצהרות של התא — צבע, גופן, גודל, מסגרת. בלעדיהן הדוגמה
      // המתועדת «ניתן לעצב תא בודד ככל תג אחר» אינה עובדת.
      final cellCss = cssStyleFrom(
        declarations,
        blockOnly: true,
        skip: const {
          'text-align',
          'direction',
          'vertical-align',
          'background-color',
          'background',
          'padding',
        },
      );
      if (cellCss != null) styles.add(cellCss);
      attributes.write(' style="${styles.join('; ')}"');

      final parts = <String>[];
      _collectCellParts(cell.nodes, ctx, parts, depth: depth + 1);
      cells.write('<$tag$attributes>${parts.join('<br>')}</$tag>');
    }
    if (cells.isNotEmpty) buffer.write('<tr>$cells</tr>');
  }
  buffer.write('</table>');
  return buffer.toString();
}

/// צבע רקע שראוי לצייר. רקע **לבן** מדולג בכל הפורמטים — הוא ברירת המחדל
/// ושובר את המצב הכהה. רקע שחור דווקא נשמר: הוא בחירה מכוונת של המחבר.
/// אוסף את תוכן התא לחלקים שיחוברו ב-`<br>`.
///
/// תא הוא שורת פלט אחת, ולכן כל הבלוקים שבו נדחסים אליה — אבל **לא בלי
/// מפריד**: חיבור שתי פסקאות במחרוזת ריקה מדביק את המילה האחרונה של האחת
/// לראשונה של הבאה, והחיפוש על הצירוף שנוצר אינו מוצא דבר.
void _collectCellParts(
  List<dom.Node> nodes,
  _HtmlContext ctx,
  List<String> parts, {
  required int depth,
}) {
  if (depth > HtmlLimits.maxNestingDepth) return;
  final inline = StringBuffer();

  void flushInline() {
    final text = inline.toString().trim();
    inline.clear();
    if (text.isNotEmpty) parts.add(text);
  }

  for (final node in nodes) {
    // בדיקת ההסתרה חלה גם כאן: זהו מסלול האיסוף של תא, פריט רשימה וגוף
    // `<details>`, ובלעדיה טקסט שהמחבר הסתיר היה מגיע לגוף הספר ולאינדקס
    // דרך שלושתם — בעקיפה של הבדיקה שבמסלול הרגיל.
    if (node is dom.Element &&
        _isHidden(node, _parseStyleAttribute(node.attributes['style']))) {
      continue;
    }
    if (node is dom.Element && node.localName == 'table') {
      flushInline();
      final nested = _buildTableHtml(node, ctx, depth: depth + 1);
      if (nested != null) parts.add(nested);
      continue;
    }
    if (_isBlockElement(node)) {
      flushInline();
      final element = node as dom.Element;
      // עטיפה שקופה בתוך התא — יורדים לתוכה, אחרת טבלה מקוננת שיושבת בתוך
      // `<div>` הייתה נשטחת לטקסט.
      if (_containsBlockChildren(element)) {
        _collectCellParts(element.nodes, ctx, parts, depth: depth + 1);
      } else {
        final text = _renderInlineChildren(
          element,
          ctx,
          depth: depth + 1,
        ).trim();
        if (text.isNotEmpty) parts.add(text);
      }
      continue;
    }
    _renderInlineNode(node, ctx, inline, depth: depth + 1);
  }
  flushInline();
}

String? _sanitizeBackground(String? value) {
  final color = sanitizeCssColorValue(_contentColor(value));
  if (color == null) return null;
  final lower = color.toLowerCase();
  return lower == '#ffffff' || lower == '#fff' || lower == 'white'
      ? null
      : color;
}

// ── הליכה על inline ───────────────────────────────────────────────────────

String _renderInlineChildren(
  dom.Element parent,
  _HtmlContext ctx, {
  required int depth,
}) {
  final buffer = StringBuffer();
  for (final node in parent.nodes) {
    _renderInlineNode(node, ctx, buffer, depth: depth);
  }
  return buffer.toString();
}

void _renderInlineNode(
  dom.Node node,
  _HtmlContext ctx,
  StringBuffer buffer, {
  required int depth,
}) {
  if (depth > HtmlLimits.maxNestingDepth) return;

  if (node is dom.Text) {
    buffer.write(_renderText(node.data, ctx));
    return;
  }
  if (node is! dom.Element) return;

  final tag = node.localName ?? '';
  if (_droppedTags.contains(tag)) return;
  // גוף הערה שכבר הוזרק בנקודת ההפניה — פליטתו שוב הייתה מכפילה אותו.
  if (ctx.consumedFootnoteBodies.contains(node)) return;

  final declarations = _parseStyleAttribute(node.attributes['style']);
  if (_isHidden(node, declarations)) return;

  if (tag == 'br') {
    buffer.write('<br>');
    return;
  }
  if (tag == 'wbr') return;
  if (tag == 'img') {
    final img = _imgHtml(node, ctx);
    if (img != null) buffer.write(img);
    return;
  }

  // הערת שוליים שנכתבה במנגנון של אוצריא — נפלטת מחדש דרך חוזה ה-markup,
  // כך שהמסמך אינו תורם מחרוזת `class` משלו לגוף הספר.
  if (_emitFootnote(node, tag, ctx, buffer, depth: depth)) return;

  final anchor = _anchorFor(node, ctx);
  if (anchor != null && ctx.emittedAnchors.add(anchor)) {
    buffer.write('<a id="${escapeHtmlAttribute(anchor)}"></a>');
  }

  final formatting = _inlineFormatting(node, tag, declarations);
  buffer.write(formatting.open);
  if (tag == 'a') {
    _renderLink(node, ctx, buffer, depth: depth);
  } else {
    for (final child in node.nodes) {
      _renderInlineNode(child, ctx, buffer, depth: depth + 1);
    }
  }
  buffer.write(formatting.close);
}

/// המחלקות שמסמן הערה ושגוף הערה נכתבים בהן במנגנון של אוצריא.
const String _footnoteMarkerClass = 'footnote-marker';
const String _footnoteBodyClass = 'footnote';

/// פולט הערת שוליים כשהאלמנט הוא מסמן הערה. מחזיר האם טופל.
///
/// שני ה-class האלה הם ה**מנגנון** של הקורא, לא עיצוב: גוף ההערה מוסר מגוף
/// הספר ומוצג כמפרש בחלונית הצד, ואינו מזהם את החיפוש. מסמך HTML שכתוב לפי
/// המדריך מקבל אותו מנגנון בדיוק — ולכן זהו הצירוף היחיד שהממיר מזהה
/// מתוך `class` של המקור. שאר השמות השמורים (`link-anchor`,
/// `book-note-marker`) קשורים למכונת הקישורים וההערות של הקורא, ומסמך זר
/// שהיה מגדיר אותם היה מזייף ממשק.
bool _emitFootnote(
  dom.Element e,
  String tag,
  _HtmlContext ctx,
  StringBuffer buffer, {
  required int depth,
}) {
  if (tag != 'sup' || !e.classes.contains(_footnoteMarkerClass)) return false;
  final marker = _collapseWhitespace(e.text).trim();
  if (marker.isEmpty) return false;

  // גוף ההערה הוא ה-`<i class="footnote">` שצמוד למסמן. הצמידות היא מה
  // שהקורא מזהה, ולכן רק אח **מיד** אחריו נחשב.
  final body = _nextElementSibling(e, ctx);
  final isFootnoteBody =
      body != null &&
      body.localName == 'i' &&
      body.classes.contains(_footnoteBodyClass);
  if (!isFootnoteBody) {
    buffer.write(otzariaFootnoteMarker(escapeHtmlText(marker)));
    return true;
  }

  // מרגע שזוהה כגוף הערה הוא נצרך בכל מקרה — גם כשלא ייפלט. אחרת הוא היה
  // מרונדר שוב במסלול ה-inline הרגיל, והתוכן היה מופיע פעמיים.
  ctx.consumedFootnoteBodies.add(body);

  // גוף מוסתר אינו נפלט: טקסט שהמחבר הסתיר מדולג בכל הפורמטים, וכאן הוא
  // היה עוקף את הבדיקה שבמסלול הרגיל ומגיע גם לאינדקס.
  if (_isHidden(body, _parseStyleAttribute(body.attributes['style']))) {
    buffer.write(otzariaFootnoteMarker(escapeHtmlText(marker)));
    return true;
  }

  final inner = StringBuffer();
  for (final child in body.nodes) {
    _renderInlineNode(child, ctx, inner, depth: depth + 1);
  }
  buffer.write(
    otzariaFootnote(escapeHtmlText(marker), inner.toString().trim()),
  );
  return true;
}

/// האלמנט שבא מיד אחרי [e] בין אחיו, כשאין ביניהם אלא רווח לבן.
///
/// המיקום נשלף ממפת האחים של ההקשר ולא ב-`indexOf`: זהו המסלול החם של
/// מסמך עם אלפי סימוני הערות, ו-`indexOf` הפך אותו לריבועי.
dom.Element? _nextElementSibling(dom.Element e, _HtmlContext ctx) {
  final parent = e.parent;
  if (parent == null) return null;
  final siblings = parent.nodes;
  final index = ctx.indexAmongSiblings(parent, e);
  if (index < 0) return null;
  for (var i = index + 1; i < siblings.length; i++) {
    final node = siblings[i];
    if (node is dom.Element) return node;
    if (node is dom.Text && node.data.trim().isEmpty) continue;
    return null;
  }
  return null;
}

String _renderText(String data, _HtmlContext ctx) {
  if (!ctx.preserveWhitespace) {
    return escapeHtmlText(_collapseWhitespace(data));
  }
  // בתוך `<pre>` שורה חדשה היא תוכן — אבל שורת ספר אחת אינה יכולה להכיל
  // `\n`, ולכן היא הופכת ל-`<br>`.
  return escapeHtmlText(data).replaceAll(_lineBreaks, '<br>');
}

/// קישור: נכתב רק כשיעדו עבר את [safeLinkTarget]. יעד שנפסל מאבד את התגית
/// בלבד — הטקסט שבתוכו נשמר במלואו.
///
/// קישורים לספרי הספרייה מותרים כאן ולא בשאר הממירים: הפעולה שהם מפעילים —
/// פתיחת ספר בלשונית — אינה מסוכנת. `file:`
/// דווקא נחסמת: מסמך שהמשתמש הוריד מהאינטרנט אינו אמור לקבל קישור שפותח
/// קובץ שרירותי במחשב בתוכנת ברירת המחדל שלו.
void _renderLink(
  dom.Element a,
  _HtmlContext ctx,
  StringBuffer buffer, {
  required int depth,
}) {
  final href = a.attributes['href'];
  final target = href == null
      ? null
      : safeLinkTarget(href, allowBookLinks: true);

  final inner = StringBuffer();
  for (final child in a.nodes) {
    _renderInlineNode(child, ctx, inner, depth: depth + 1);
  }
  if (target == null) {
    buffer.write(inner);
    return;
  }
  buffer.write('<a href="${escapeHtmlAttribute(target)}">$inner</a>');
}

/// תמונה. `width`/`height` נשמרים כפי שהמסמך הצהיר עליהם — הם מאומתים
/// כמספר שלם חיובי, שכן העתקה מילולית הייתה מאפשרת הזרקת מאפיינים.
String? _imgHtml(dom.Element e, _HtmlContext ctx) {
  final resolved = ctx.images.resolve(e.attributes['src']);
  if (!resolved.exists) return null;
  final alt = e.attributes['alt']?.trim();
  final title = e.attributes['title']?.trim();
  return otzariaImage(
    resolved.uri!,
    width: positiveIntegerAttribute(e.attributes['width']),
    height: positiveIntegerAttribute(e.attributes['height']),
    alt: alt == null || alt.isEmpty ? null : escapeHtmlAttribute(alt),
    title: title == null || title.isEmpty ? null : escapeHtmlAttribute(title),
  );
}

/// העיצוב שיש לעטוף בו את תוכן האלמנט: התגית עצמה, ההצהרות ב-`style`,
/// ומאפייני `<font>` מדור קודם — שנפוצים מאוד בקובצי HTML עבריים ישנים.
({String open, String close}) _inlineFormatting(
  dom.Element e,
  String tag,
  Map<String, String> declarations,
) {
  final opens = <String>[];
  final closes = <String>[];

  void wrap(({String open, String close}) tags) {
    opens.add(tags.open);
    closes.insert(0, tags.close);
  }

  // התכונות שהומרו לתגית — אין לכתוב אותן שוב בתוך ה-`style` שנפלט.
  final consumed = <String>{};

  final kept = _inlineKeepTags[tag];
  if (kept != null) {
    opens.add('<$kept>');
    closes.insert(0, '</$kept>');
  } else if (tag == 'mark') {
    wrap(highlightTags('yellow'));
  }

  // `<b>`/`<i>`/`<u>` מועדפים על ההצהרה המקבילה: הם נתמכים גם במצב הקריאה
  // הרציפה, שבו התכונות המקבילות אינן מוצגות.
  if (_isBoldDeclaration(_lowerDeclaration(declarations, 'font-weight'))) {
    opens.add('<b>');
    closes.insert(0, '</b>');
    consumed.add('font-weight');
  }
  if (_lowerDeclaration(declarations, 'font-style') == 'italic') {
    opens.add('<i>');
    closes.insert(0, '</i>');
    consumed.add('font-style');
  }
  final decoration =
      _lowerDeclaration(declarations, 'text-decoration-line') ??
      _lowerDeclaration(declarations, 'text-decoration');
  // שלוש הצורות עוברות **כמות שהן** דרך מסנן ה-CSS ולא מומרות לתגיות:
  // `overline` (אין לו תגית מקבילה), `none` (תגית אינה יכולה לבטל קו
  // שנקבע בחוץ), ועובי מוצהר (`text-decoration-thickness` על `<span>`
  // פנימי אינו חל על הקו של ה-`<u>` שעוטף אותו — הצהרה מתה).
  final hasThickness = declarations.containsKey('text-decoration-thickness');
  if (decoration != null &&
      !decoration.contains('overline') &&
      !decoration.contains('none') &&
      !hasThickness) {
    consumed.addAll(const [
      'text-decoration',
      'text-decoration-line',
      'text-decoration-style',
      'text-decoration-color',
    ]);
    // CSS מחיל סגנון וצבע אחד על **כל** הקווים של ההצהרה, ולכן `double`
    // שנקרא כאן חל גם על הקו התחתי וגם על הקו החוצה.
    final kind = _underlineKindOf(
      _lowerDeclaration(declarations, 'text-decoration-style') ?? decoration,
    );
    // הצבע יכול להיות מוצהר בנפרד או להיות אחד הטוקנים של הקיצור
    // (`text-decoration: underline #00A000`) — בלי הקריאה מהקיצור הוא אבד.
    final color =
        sanitizeCssColorValue(
          _contentColor(declarations['text-decoration-color']),
        ) ??
        _decorationColorToken(decoration);
    if (decoration.contains('underline')) {
      wrap(underlineTags(kind: kind, color: color));
    }
    if (decoration.contains('line-through')) {
      wrap(strikeTags(doubleLine: kind == UnderlineKind.double));
    }
  }

  // הצבעים מטופלים **כאן בלבד**, ולכן הם נצרכים תמיד — גם כשהערך נדחה.
  // בלי זה מסנן ה-CSS היה כותב אותם בחזרה, וכלל הניקוי של שחור ולבן (שובר
  // את המצב הכהה) היה נעקף בשקט.
  consumed.addAll(const ['color', 'background-color', 'background']);

  final color = _htmlContentColor(
    declarations['color'] ?? (tag == 'font' ? e.attributes['color'] : null),
  );
  if (color != null) wrap(colorTags(color));

  final highlight = _sanitizeBackground(
    declarations['background-color'] ?? declarations['background'],
  );
  if (highlight != null) wrap(highlightTags(highlight));

  // כל שאר ההצהרות שמנוע התצוגה מכיר — גופן, גודל, גובה שורה, מסגרת, ריווח,
  // צל, כיווניות כפויה וכו'. הן נכתבות אחרי התגיות כדי שה-`<span>` יהיה
  // הפנימי ביותר ולא יבטל אותן.
  final css = cssStyleFrom(declarations, skip: consumed);
  if (css != null) {
    opens.add('<span style="$css">');
    closes.insert(0, '</span>');
  }

  return (open: opens.join(), close: closes.join());
}

/// צבע טקסט מתוך מסמך HTML. שחור מנוקה (הוא שובר את המצב הכהה), ומילות
/// מפתח שאינן צבע מדולגות; שאר הצורות — כולל `rgb()`/`hsl()` — נשמרות.
String? _htmlContentColor(String? value) {
  final v = _contentColor(value);
  if (v == null || v == 'black' || v == '#000' || v == '#000000') return null;
  return sanitizeCssColorValue(v);
}

/// הצבע שבתוך הקיצור `text-decoration`, אם יש בו כזה.
///
/// טוקן שאינו סוג-קו ואינו סגנון-קו הוא הצבע. בלי הקריאה הזו
/// `text-decoration: underline #00A000` היה מאבד את הצבע לגמרי.
String? _decorationColorToken(String declaration) {
  for (final token in declaration.split(RegExp(r'\s+'))) {
    if (token.isEmpty) continue;
    if (const {
      'underline',
      'overline',
      'line-through',
      'none',
      'solid',
      'double',
      'dotted',
      'dashed',
      'wavy',
    }.contains(token)) {
      continue;
    }
    final color = sanitizeCssColorValue(_contentColor(token));
    if (color != null) return color;
  }
  return null;
}

/// סוג הקו התחתי מתוך `text-decoration`/`text-decoration-style`.
///
/// [underlineKindFromName] מתאים לערך של Word/ODF, שהוא **מילה אחת**;
/// ב-CSS הסוג יושב באמצע הצהרה מרובת-מילים (`underline dotted red`).
UnderlineKind _underlineKindOf(String declaration) {
  if (declaration.contains('wavy')) return UnderlineKind.wavy;
  if (declaration.contains('dotted')) return UnderlineKind.dotted;
  if (declaration.contains('dashed')) return UnderlineKind.dashed;
  if (declaration.contains('double')) return UnderlineKind.double;
  return UnderlineKind.single;
}

/// מילות המפתח של CSS שאינן צבע. הן עוברות את [sanitizeCssColor] (הוא מקבל
/// כל שם צבע), אבל כתיבתן לגוף הספר רק מנפחת כל שורה בלי לצבוע דבר.
const Set<String> _nonColorKeywords = {
  'currentcolor',
  'inherit',
  'initial',
  'revert',
  'transparent',
  'unset',
};

String? _contentColor(String? value) {
  final v = value?.trim().toLowerCase();
  if (v == null || v.isEmpty || _nonColorKeywords.contains(v)) return null;
  return v;
}

/// האם ההצהרה היא בדיוק "מודגש", ולכן ראויה לתגית `<b>` — שנתמכת גם במצב
/// הקריאה הרציפה, שבו `font-weight` אינו מוצג.
///
/// דרגות עובי אחרות (`600` חצי-מודגש, `900` הכבד ביותר) **אינן** מומרות:
/// הן הצהרה מדויקת של המחבר, והמרתן ל-`<b>` הייתה משטחת את כולן לאותו עובי.
/// הן עוברות כהצהרת CSS דרך המסנן.
bool _isBoldDeclaration(String? value) => value == 'bold' || value == '700';

// ── עוגנים, סגנון והסתרה ──────────────────────────────────────────────────

/// ה-`id` שיש לפלוט עבור [e], או `null` כשאיש אינו מפנה אליו.
///
/// רק יעדים שקישור פנימי במסמך מצביע עליהם נשמרים: כך `<a href="#הערה-1">`
/// ממשיך לנווט בקורא (`HtmlLinkHandler` מאתר את השורה לפי `id="…"`), בלי
/// שכל `id` עיצובי במסמך ינפח את גוף הספר.
String? _anchorFor(dom.Element e, _HtmlContext ctx) {
  for (final name in const ['id', 'name']) {
    final raw = e.attributes[name]?.trim();
    if (raw == null ||
        raw.isEmpty ||
        raw.length > HtmlLimits.maxAnchorIdLength) {
      continue;
    }
    if (!ctx.referencedAnchors.contains(raw)) continue;
    // הרישום כ"נפלט" נעשה בכתיבה בפועל ([_HtmlContext.anchorPrefix]) ולא
    // כאן: אלמנט יכול לתבוע עוגן ואז לא לפלוט שורה כלל (כותרת ריקה, טבלה
    // בלי שורות, תמונה שנפסלה) — ואז העוגן היה "נגנב" ואף אלמנט אחר עם
    // אותו `id` לא היה מקבל אותו. התוצאה: קישור פנימי מת.
    if (ctx.emittedAnchors.contains(raw)) return null;
    return raw;
  }
  return null;
}

/// האם הכותרת סומנה במסמך כמוצאת מתוכן העניינים (`data-toc="none"`).
bool _isTocExcluded(dom.Element e) =>
    e.attributes['data-toc']?.trim().toLowerCase() == 'none';

/// האם האלמנט מוסתר. טקסט מוסתר מדולג לחלוטין בכל הפורמטים — הצגתו הייתה
/// שופכת לגוף הספר תוכן שהמחבר הסתיר, ומכניסה אותו גם לאינדקס.
bool _isHidden(dom.Element e, Map<String, String> declarations) {
  if (e.attributes.containsKey('hidden')) return true;
  if (_lowerDeclaration(declarations, 'display') == 'none') return true;
  return _lowerDeclaration(declarations, 'visibility') == 'hidden';
}

/// מפרק `style="…"` למפה של הצהרות מנורמלות.
///
/// הערכים כאן **אינם** נכתבים לפלט כמות שהם: כל אחד מהם עובר אימות מוקלד
/// ([sanitizeCssColor], [cssVerticalAlign], [_cssTextAlign]) לפני שהוא נכנס
/// ל-`style` שהממיר מייצר. בלי זה, ערך שמכיל גרש נחלץ מהמאפיין ומזריק
/// תגיות משלו לגוף הספר — ומשם הן מגיעות גם לתוכן העניינים ולאינדקס.
Map<String, String> _parseStyleAttribute(String? value) {
  if (value == null || value.isEmpty) return const {};
  final declarations = <String, String>{};
  for (final part in value.split(';')) {
    if (declarations.length >= HtmlLimits.maxStyleDeclarations) break;
    final colon = part.indexOf(':');
    if (colon <= 0) continue;
    final name = part.substring(0, colon).trim().toLowerCase();
    // הערך נשמר **כפי שנכתב**. הורדת רישיות גורפת הייתה הורסת שם גופן
    // (`'SBL Hebrew'` → `'sbl hebrew'`); כל מאמת מנרמל בעצמו את מה שאצלו
    // חסר-רגישות.
    final declared = part.substring(colon + 1).trim();
    if (name.isEmpty || declared.isEmpty) continue;
    declarations[name] = declared;
  }
  return declarations;
}

/// ערך הצהרה באותיות קטנות, להשוואת מילות מפתח.
String? _lowerDeclaration(Map<String, String> declarations, String property) =>
    declarations[property]?.toLowerCase();

final RegExp _lineBreaks = RegExp(r'\r\n|\r|\n');
final RegExp _whitespaceRun = RegExp(r'[ \t\r\n\f]+');

/// רק כשיש באמת מה לכווץ — רווח בודד רגיל אינו מצדיק אלוקציה.
final RegExp _collapsibleWhitespace = RegExp(r'[\t\r\n\f]| {2,}');

String _collapseWhitespace(String s) =>
    s.contains(_collapsibleWhitespace) ? s.replaceAll(_whitespaceRun, ' ') : s;
