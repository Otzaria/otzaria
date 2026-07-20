import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart' as xml;

import 'package:otzaria/utils/file/docx_to_otzaria.dart' show escapeHtmlText;
import 'package:otzaria/utils/file/text_encoding.dart'
    show decodeTextBytesSmart;

/// גרסת הממיר [epubToText] — **חובה להעלות בכל שינוי שמשפיע על הפלט**:
/// מטמון התוכן כולל את הגרסה במפתח-התוקף, והעלאה פוסלת רשומות ישנות.
const int kEpubConverterVersion = 10;

/// ממיר קובץ EPUB לפורמט הטקסט של אוצריא: שורת `<h1>` עם שם הספר, ואחריה
/// שורה לכל בלוק (פסקה/כותרת/טבלה/תמונה) לפי סדר פרקי ה-spine.
///
/// כותרות הפרקים (h1–h6 שבמקור) מוסטות רמה אחת מטה (h1→h2…) כך ששם הספר
/// נשאר הכותרת הראשית היחידה — ומהן נבנה תוכן העניינים (TocParser).
/// תמונות מוטמעות כ-data URI, והערות שוליים — סמנטיות (epub:type) או
/// מבוססות-קישור ([_resolveNoteref]) — מוצגות בפורמט ההערות של אוצריא,
/// כמו בממיר ה-DOCX.
String epubToText(Uint8List bytes, String title) {
  final List<String> output = ['<h1>${escapeHtmlText(title)}</h1>'];

  // ZipDecoder הוא stateful — מופע מקומי לכל המרה מונע דריסת מצב בין
  // קריאות מקבילות באותו isolate.
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    // ZIP פגום — מחזירים לפחות את כותרת הספר במקום לקרוס.
    return output.join('\n');
  }

  final files = _ArchiveFiles(archive);

  final opfPath = _findOpfPath(files);
  if (opfPath == null) return output.join('\n');

  final opfBytes = files.read(opfPath);
  if (opfBytes == null) return output.join('\n');

  final xml.XmlDocument opf;
  try {
    opf = xml.XmlDocument.parse(_decodeBytes(opfBytes));
  } catch (_) {
    return output.join('\n');
  }

  final opfDir = _dirOf(opfPath);
  final manifest = _parseManifest(opf, opfDir);
  final spine = _parseSpine(opf, manifest);
  final coverPath = _findCoverPath(opf, manifest);

  final ctx = _EpubContext(
    files: files,
    images: _buildImageMap(files, manifest, coverPath: coverPath),
  );

  // שלב 1: פירוק כל הפרקים ובניית אינדקס עוגנים (id) גלובלי — נדרש להערות
  // שוליים שגופן יושב בפרק אחר (קובץ הערות נפרד).
  final chapters = <({String path, dom.Element body})>[];
  for (final itemPath in spine) {
    final chapterBytes = files.read(itemPath);
    if (chapterBytes == null) continue;

    final dom.Document doc;
    try {
      doc = html_parser.parse(_decodeBytes(chapterBytes));
    } catch (_) {
      continue; // פרק פגום — ממשיכים לפרק הבא במקום לקרוס.
    }

    final body = doc.body;
    if (body == null) continue;

    chapters.add((path: itemPath, body: body));
    for (final e in body.querySelectorAll('[id]')) {
      if (e.id.isEmpty) continue;
      ctx.anchors['${itemPath.toLowerCase()}#${e.id}'] ??= e;
    }
  }

  // כותרות מה-TOC של הספר (NCX/nav) — לספרים שפרקיהם בלי תגיות כותרת:
  // רשומה בלי עוגן ממופה לתחילת הפרק, רשומה עם עוגן — לבלוק היעד.
  final chapterTocHeading = <String, (String, int)>{};
  for (final t in _parseTocEntries(files, manifest)) {
    final level = (t.depth + 1).clamp(2, 6).toInt();
    if (t.fragment == null || t.fragment!.isEmpty) {
      chapterTocHeading.putIfAbsent(t.pathLower, () => (t.title, level));
    } else {
      dom.Element? el = ctx.anchors['${t.pathLower}#${t.fragment}'];
      // עוגן inline (למשל <a id>) — מטפסים לבלוק העוטף, שם מקום הכותרת.
      while (el != null && !_isBlockElement(el)) {
        el = el.parent;
      }
      if (el == null || _headingTags.contains(el.localName)) continue;
      ctx.tocHeadings.putIfAbsent(el, () => (t.title, level));
    }
  }

  // שלב 2: סריקה מקדימה — סימון יעדי הערות לדיכוי, לפני הרינדור, כדי
  // שגוף הערה לא יופיע פעמיים גם כשהיעד קודם להפניה בסדר הפרקים.
  for (final ch in chapters) {
    ctx.baseDir = _dirOf(ch.path);
    ctx.chapterPath = ch.path;
    for (final a in ch.body.querySelectorAll('a')) {
      final target = _resolveNoteref(a, ctx)?.target;
      if (target != null) ctx.consumedNotes.add(target);
    }
  }

  // שלב 3: רינדור.
  for (final ch in chapters) {
    ctx.baseDir = _dirOf(ch.path);
    ctx.chapterPath = ch.path;
    ctx.pendingChapterHeading = chapterTocHeading[ch.path.toLowerCase()];
    _processBlockChildren(ch.body.nodes, ctx, output);
  }
  ctx.pendingChapterHeading = null;

  // כריכה מוצהרת (manifest) שלא הופיעה באף פרק — למשל עמוד כריכה
  // linear="no" שדולג — מוזרקת אחרי הכותרת, כך שהכריכה תמיד מוצגת.
  final coverUri = coverPath == null
      ? null
      : ctx.images[coverPath.toLowerCase()];
  if (coverUri != null && !output.any((l) => l.contains(coverUri))) {
    output.insert(1, '<img src="$coverUri" style="max-width: 100%;"/>');
  }

  return output.join('\n');
}

/// רשומת תוכן-עניינים מ-NCX/nav: יעד (נתיב+עוגן), כותרת ועומק קינון.
class _TocRef {
  final String pathLower;
  final String? fragment;
  final String title;
  final int depth;
  const _TocRef(this.pathLower, this.fragment, this.title, this.depth);
}

xml.XmlElement? _childByLocal(xml.XmlElement parent, String local) {
  for (final c in parent.childElements) {
    if (c.name.local == local) return c;
  }
  return null;
}

/// קורא את רשומות ה-TOC של הספר: קודם מסמך הניווט של EPUB3 (`nav`), ואם
/// אין — `toc.ncx` של EPUB2. משמש לסינתוז כותרות בספרים שפרקיהם בלי
/// תגיות `<h1>`–`<h6>` (שמהן נבנה תוכן העניינים של אוצריא).
List<_TocRef> _parseTocEntries(
  _ArchiveFiles files,
  Map<String, _ManifestItem> manifest,
) {
  final entries = <_TocRef>[];

  void addEntry(String baseDir, String href, String title, int depth) {
    if (title.isEmpty || href.isEmpty) return;
    final hash = href.indexOf('#');
    final fragment = hash >= 0 ? href.substring(hash + 1) : null;
    final path = _resolveHref(baseDir, href);
    if (path.isEmpty) return;
    entries.add(_TocRef(path.toLowerCase(), fragment, title, depth));
  }

  // EPUB3: מסמך ניווט (properties="nav") — עץ <ol>/<li>/<a>.
  for (final item in manifest.values) {
    if (!item.properties.split(' ').contains('nav')) continue;
    final bytes = files.read(item.path);
    if (bytes == null) break;
    final dom.Document doc;
    try {
      doc = html_parser.parse(_decodeBytes(bytes));
    } catch (_) {
      break;
    }
    final navBase = _dirOf(item.path);
    dom.Element? toc;
    for (final nav in doc.querySelectorAll('nav')) {
      if (_hasEpubType(nav, const {'toc'})) {
        toc = nav;
        break;
      }
      toc ??= nav;
    }
    if (toc == null) break;

    void walkOl(dom.Element ol, int depth) {
      for (final li in ol.children.where((e) => e.localName == 'li')) {
        dom.Element? link;
        dom.Element? childOl;
        for (final c in li.children) {
          if (c.localName == 'a' && link == null) link = c;
          if (c.localName == 'ol' && childOl == null) childOl = c;
        }
        if (link != null) {
          addEntry(
            navBase,
            link.attributes['href'] ?? '',
            _collapseWhitespace(link.text).trim(),
            depth,
          );
        }
        if (childOl != null) walkOl(childOl, depth + 1);
      }
    }

    for (final ol in toc.children.where((e) => e.localName == 'ol')) {
      walkOl(ol, 1);
    }
    break;
  }
  if (entries.isNotEmpty) return entries;

  // EPUB2: קובץ NCX — עץ <navMap>/<navPoint>.
  for (final item in manifest.values) {
    final isNcx =
        item.mediaType == 'application/x-dtbncx+xml' ||
        item.path.toLowerCase().endsWith('.ncx');
    if (!isNcx) continue;
    final bytes = files.read(item.path);
    if (bytes == null) break;
    final xml.XmlDocument doc;
    try {
      doc = xml.XmlDocument.parse(_decodeBytes(bytes));
    } catch (_) {
      break;
    }
    final ncxBase = _dirOf(item.path);

    void walkNavPoints(Iterable<xml.XmlElement> elements, int depth) {
      for (final np in elements.where((e) => e.name.local == 'navPoint')) {
        final label = _childByLocal(np, 'navLabel');
        final text = label == null ? null : _childByLocal(label, 'text');
        final src = _childByLocal(np, 'content')?.getAttribute('src');
        if (text != null && src != null) {
          addEntry(
            ncxBase,
            src,
            _collapseWhitespace(text.innerText).trim(),
            depth,
          );
        }
        walkNavPoints(np.childElements, depth + 1);
      }
    }

    for (final el in doc.descendantElements) {
      if (el.name.local == 'navMap') {
        walkNavPoints(el.childElements, 1);
        break;
      }
    }
    break;
  }
  return entries;
}

/// מאתר את תמונת הכריכה המוצהרת: EPUB3 — פריט manifest עם
/// `properties="cover-image"`; EPUB2 — `<meta name="cover" content="id">`.
String? _findCoverPath(
  xml.XmlDocument opf,
  Map<String, _ManifestItem> manifest,
) {
  for (final item in manifest.values) {
    if (item.properties.split(' ').contains('cover-image')) return item.path;
  }
  for (final meta in _elementsByLocal(opf, 'meta')) {
    if (meta.getAttribute('name') == 'cover') {
      final item = manifest[meta.getAttribute('content')];
      if (item != null) return item.path;
    }
  }
  return null;
}

/// גישה לקבצי הארכיון לפי נתיב, עם fallback חסר-רגישות-לרישיות — קבצי EPUB
/// מהשטח לא תמיד עקביים ברישיות בין ה-OPF לשמות הקבצים בפועל.
class _ArchiveFiles {
  final Map<String, ArchiveFile> _byPath = {};
  final Map<String, ArchiveFile> _byLowerPath = {};

  _ArchiveFiles(Archive archive) {
    for (final file in archive) {
      if (!file.isFile) continue;
      final normalized = _normalizePath(file.name);
      _byPath[normalized] = file;
      _byLowerPath[normalized.toLowerCase()] = file;
    }
  }

  List<int>? read(String path) {
    final file = _byPath[path] ?? _byLowerPath[path.toLowerCase()];
    return file?.content;
  }

  Iterable<String> get paths => _byPath.keys;
}

/// משאבי הספר המשותפים לעיבוד הפרקים: מפת תמונות, אינדקס עוגנים גלובלי,
/// יעדי הערות שסומנו לדיכוי, והפרק הנוכחי (לפתרון נתיבים יחסיים).
class _EpubContext {
  final _ArchiveFiles files;

  /// נתיב מנורמל בארכיון → `data:image/...;base64,...` מוכן להטמעה.
  final Map<String, String> images;

  /// `path#id` (path באותיות קטנות) → האלמנט, מכל פרקי ה-spine.
  final Map<String, dom.Element> anchors = {};

  /// יעדי הערות שגופן מוזרק בנקודת ההפניה — מדולגים ברינדור (מניעת כפילות).
  final Set<dom.Element> consumedNotes = {};

  /// מטמון סיווג ההפניות — הסריקה המקדימה והרינדור עוברים על אותם קישורים.
  final Map<dom.Element, _NoterefResolution?> noterefCache = {};

  /// בלוק-יעד של רשומת TOC (עוגן) → (כותרת, רמה) לסינתוז לפני הבלוק —
  /// לספרים שמבנה הפרקים שלהם מוגדר ב-NCX/nav ולא בתגיות כותרת.
  final Map<dom.Element, (String, int)> tocHeadings = {};

  /// כותרת-פרק מה-TOC הממתינה לבלוק הראשון של הפרק הנוכחי.
  (String, int)? pendingChapterHeading;

  String baseDir = '';
  String chapterPath = '';
  int footnoteCounter = 1;

  _EpubContext({required this.files, required this.images});
}

/// פענוח בייטים לטקסט עם זיהוי BOM/UTF-16 — EPUB רשאי להישמר גם ב-UTF-16.
String _decodeBytes(List<int> bytes) => decodeTextBytesSmart(
  bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
);

/// מנרמל נתיב בתוך הארכיון: מפריד `/`, פתרון `.`/`..`, והסרת `/` מוביל.
String _normalizePath(String path) {
  final parts = path.replaceAll('\\', '/').split('/');
  final resolved = <String>[];
  for (final part in parts) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (resolved.isNotEmpty) resolved.removeLast();
      continue;
    }
    resolved.add(part);
  }
  return resolved.join('/');
}

String _dirOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}

/// href עם scheme (http:, mailto:, data:…) — יעד חיצוני לארכיון.
final _schemeRegExp = RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*:');

/// פותר href יחסי (כולל percent-encoding) לנתיב מנורמל בארכיון, בלי fragment.
/// קישור חיצוני (עם scheme) מחזיר '' — אינו קובץ בארכיון.
String _resolveHref(String baseDir, String href) {
  var h = href;
  final hash = h.indexOf('#');
  if (hash >= 0) h = h.substring(0, hash);
  final query = h.indexOf('?');
  if (query >= 0) h = h.substring(0, query);
  if (_schemeRegExp.hasMatch(h)) return '';
  try {
    h = Uri.decodeFull(h);
  } catch (_) {}
  if (h.isEmpty) return '';
  // נתיב שורש-מוחלט ('/x') נפתר משורש הארכיון, לא מתיקיית הפרק.
  if (h.startsWith('/')) return _normalizePath(h);
  return _normalizePath(baseDir.isEmpty ? h : '$baseDir/$h');
}

/// איטרציה על אלמנטים לפי שם מקומי, בלי תלות ב-namespace prefix —
/// container.xml וה-OPF מגיעים עם default namespaces משתנים בין קבצים.
Iterable<xml.XmlElement> _elementsByLocal(xml.XmlNode root, String local) =>
    root.descendantElements.where((e) => e.name.local == local);

/// מאתר את נתיב קובץ ה-OPF דרך `META-INF/container.xml`, עם fallback לחיפוש
/// ישיר של קובץ `.opf` בארכיון (קבצים שאינם תקניים לגמרי).
String? _findOpfPath(_ArchiveFiles files) {
  final containerBytes = files.read('META-INF/container.xml');
  if (containerBytes != null) {
    try {
      final doc = xml.XmlDocument.parse(_decodeBytes(containerBytes));
      for (final rootfile in _elementsByLocal(doc, 'rootfile')) {
        final fullPath = rootfile.getAttribute('full-path');
        if (fullPath != null && fullPath.isNotEmpty) {
          return _normalizePath(fullPath);
        }
      }
    } catch (_) {}
  }
  for (final path in files.paths) {
    if (path.toLowerCase().endsWith('.opf')) return path;
  }
  return null;
}

class _ManifestItem {
  final String path;
  final String mediaType;
  final String properties;
  const _ManifestItem(this.path, this.mediaType, this.properties);
}

/// `id` → פריט manifest עם נתיב פתור (יחסית לתיקיית ה-OPF).
Map<String, _ManifestItem> _parseManifest(xml.XmlDocument opf, String opfDir) {
  final items = <String, _ManifestItem>{};
  for (final item in _elementsByLocal(opf, 'item')) {
    final id = item.getAttribute('id');
    final href = item.getAttribute('href');
    if (id == null || href == null) continue;
    items[id] = _ManifestItem(
      _resolveHref(opfDir, href),
      item.getAttribute('media-type') ?? '',
      item.getAttribute('properties') ?? '',
    );
  }
  return items;
}

/// נתיבי פרקי התוכן לפי סדר ה-spine. פריטי `linear="no"` ומסמך הניווט
/// (`properties="nav"`) מדולגים — הם עמודי עזר, לא תוכן הספר.
List<String> _parseSpine(
  xml.XmlDocument opf,
  Map<String, _ManifestItem> manifest,
) {
  final result = <String>[];
  final seen = <String>{};
  for (final itemref in _elementsByLocal(opf, 'itemref')) {
    if (itemref.getAttribute('linear') == 'no') continue;
    final idref = itemref.getAttribute('idref');
    final item = idref != null ? manifest[idref] : null;
    if (item == null) continue;
    if (item.properties.split(' ').contains('nav')) continue;
    // spine פגום שמפנה לאותו קובץ פעמיים — בלי הסינון התוכן היה מוכפל.
    if (!seen.add(item.path)) continue;
    result.add(item.path);
  }
  return result;
}

const _imageMediaTypes = {
  'image/jpeg': 'image/jpeg',
  'image/png': 'image/png',
  'image/gif': 'image/gif',
  'image/svg+xml': 'image/svg+xml',
  'image/webp': 'image/webp',
  'image/bmp': 'image/bmp',
};

String? _mediaTypeFromExtension(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.svg')) return 'image/svg+xml';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.bmp')) return 'image/bmp';
  return null;
}

/// תקרת גודל לתמונה מוטמעת. הטקסט המלא (כולל ה-base64) נשמר במטמון
/// cache.db ובזיכרון — תמונה ענקית הייתה מנפחת את שניהם; מעליה מדולגת.
const _maxEmbeddedImageBytes = 4 * 1024 * 1024;

/// תקרה מוגדלת לתמונת הכריכה — כריכות סרוקות כבדות במיוחד, ויש רק אחת.
const _maxEmbeddedCoverBytes = 10 * 1024 * 1024;

/// נתיב מנורמל → data URI, לכל תמונות ה-manifest (עובד גם offline).
Map<String, String> _buildImageMap(
  _ArchiveFiles files,
  Map<String, _ManifestItem> manifest, {
  String? coverPath,
}) {
  final images = <String, String>{};
  for (final item in manifest.values) {
    final mediaType =
        _imageMediaTypes[item.mediaType] ?? _mediaTypeFromExtension(item.path);
    if (mediaType == null) continue;
    final maxBytes = item.path == coverPath
        ? _maxEmbeddedCoverBytes
        : _maxEmbeddedImageBytes;
    final bytes = files.read(item.path);
    if (bytes == null || bytes.length > maxBytes) continue;
    // ??= — המופע הראשון גובר (עקבי עם קדימות ההתאמה המדויקת בארכיון).
    images[item.path.toLowerCase()] ??=
        'data:$mediaType;base64,${base64Encode(bytes)}';
  }
  return images;
}

/// ערך מאפיין גם כשהמפתח אינו String רגיל (package:html שומר מאפייני
/// namespace כמו `epub:type` תחת מפתח מסוג AttributeName).
String? _attr(dom.Element e, String name) {
  final direct = e.attributes[name];
  if (direct != null) return direct;
  for (final entry in e.attributes.entries) {
    if (entry.key.toString() == name) return entry.value;
  }
  return null;
}

const _footnoteTypes = {'footnote', 'rearnote', 'endnote'};

bool _hasEpubType(dom.Element e, Set<String> types) {
  final t = _attr(e, 'epub:type');
  if (t == null) return false;
  return t.split(' ').any(types.contains);
}

/// תקרת אורך (בתווים) ליעד של הערה *היריסטית*. קישור-סַמָּן מספרי עלול
/// להצביע גם על פרק שלם (עמוד תוכן עניינים ממוספר) — יעד ארוך מכך אינו
/// הערה, והקישור נשאר טקסט רגיל בלי לדכא את היעד.
const _maxHeuristicNoteLength = 1000;

/// טקסט-סַמָּן של הפניית הערה: מספר, כוכבית/פגיון, אות בודדת, או אות/יות
/// עבריות עם גרש/גרשיים (א׳, י"א) — אופציונלית בסוגריים ([1], (א)).
final _noteMarkerRegExp = RegExp(
  r'^[\[\(]?([0-9]{1,4}|[*†‡§]|[a-zA-Z]|'
  "[א-ת]{1,2}[\"״]?[א-ת]?[׳']?"
  r')[\]\)]?$',
);

bool _isNoteMarkerText(String raw) {
  final t = _collapseWhitespace(raw).trim();
  if (t.isEmpty || t.length > 6) return false;
  return _noteMarkerRegExp.hasMatch(t);
}

/// קישור-חזרה בתוך גוף הערה (חץ/סימן שמוביל בחזרה לטקסט) — מדולג בשליפה.
final _backlinkSymbolRegExp = RegExp('^[↩↵⤴⤶←→↑⬆^«»]+\$');

/// סוגריים עוטפים של סַמָּן הערה — להסרה לפני השוואה לגוף ההערה.
final _markerTrimRegExp = RegExp(r'^[\[\(]+|[\]\)]+$');

/// יעד הפניית הערה שנפתר. [target] יכול להיות null עבור `epub:type="noteref"`
/// מפורש שהעוגן שלו חסר — עדיין מרונדר כסמן, רק בלי גוף.
class _NoterefResolution {
  final dom.Element? target;
  const _NoterefResolution(this.target);
}

/// מסווג קישור כהפניית הערת שוליים ומאתר את גוף ההערה. שלושה מסלולים:
/// `epub:type="noteref"` מפורש; יעד שהוא הערה סמנטית (`epub:type="footnote"`);
/// או היריסטיקה — טקסט-סַמָּן קצר ([_isNoteMarkerText]) שמצביע לעוגן קיים
/// ולא-ארוך. מחזיר null כשהקישור אינו הערה.
_NoterefResolution? _resolveNoteref(dom.Element a, _EpubContext ctx) =>
    ctx.noterefCache.putIfAbsent(a, () => _resolveNoterefUncached(a, ctx));

_NoterefResolution? _resolveNoterefUncached(dom.Element a, _EpubContext ctx) {
  final href = a.attributes['href'] ?? '';
  final hash = href.indexOf('#');
  final id = hash >= 0 ? href.substring(hash + 1) : '';
  final isExplicit = _hasEpubType(a, const {'noteref'});
  if (id.isEmpty) return isExplicit ? const _NoterefResolution(null) : null;

  final pathPart = hash > 0 ? href.substring(0, hash) : '';
  final targetPath = pathPart.isEmpty
      ? ctx.chapterPath
      : _resolveHref(ctx.baseDir, href);
  final target = ctx.anchors['${targetPath.toLowerCase()}#$id'];

  if (isExplicit) return _NoterefResolution(target);
  if (target == null) return null;
  if (_hasEpubType(target, _footnoteTypes)) return _NoterefResolution(target);
  // כותרות הן יעדי ניווט, לא גופי הערות — בלי הבדיקה קישור-סַמָּן קצר
  // לכותרת קצרה היה מעלים אותה מהספר ומתוכן העניינים.
  if (_headingTags.contains(target.localName)) return null;
  if (!_isNoteMarkerText(a.text)) return null;
  if (target.text.length > _maxHeuristicNoteLength) return null;
  return _NoterefResolution(target);
}

const _headingTags = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};

/// שולף את טקסט ההערה מהיעד: מדלג על קישורי-חזרה (סַמָּן/חץ), ומסיר סַמָּן
/// פותח שמשכפל את סמן ההפניה (ההערה "1. גוף" כשהקישור הוא "1").
String _extractNoteBody(dom.Element target, String marker) {
  final buf = StringBuffer();
  void walk(dom.Node node) {
    if (node is dom.Text) {
      buf.write(node.data);
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName ?? '';
    if (tag == 'script' || tag == 'style') return;
    if (tag == 'a') {
      final t = _collapseWhitespace(node.text).trim();
      if (_isNoteMarkerText(t) || _backlinkSymbolRegExp.hasMatch(t)) return;
    }
    node.nodes.forEach(walk);
  }

  walk(target);
  var text = _collapseWhitespace(buf.toString()).trim();

  final core = marker.replaceAll(_markerTrimRegExp, '');
  if (core.isNotEmpty) {
    text = text.replaceFirst(
      RegExp(r'^[\[\(]?' + RegExp.escape(core) + r'[\]\)]?[\s.,:;)\-]+'),
      '',
    );
  }
  return text;
}

final _whitespaceRun = RegExp(r'[ \t\r\n\f]+');

/// רק כשיש באמת מה לכווץ — רווח בודד רגיל אינו מצדיק אלוקציה.
final _collapsibleWhitespace = RegExp(r'[\t\r\n\f]| {2,}');

String _collapseWhitespace(String s) =>
    s.contains(_collapsibleWhitespace) ? s.replaceAll(_whitespaceRun, ' ') : s;

const _blockTags = {
  'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'div', 'section', 'article',
  'aside', 'blockquote', 'ol', 'ul', 'li', 'table', 'figure', 'figcaption',
  'header', 'footer', 'main', 'nav', 'pre', 'hr', 'img', 'details',
  'summary', 'dl', 'dt', 'dd', //
};

bool _isBlockElement(dom.Node node) =>
    node is dom.Element && _blockTags.contains(node.localName);

bool _containsBlockChildren(dom.Element e) => e.nodes.any(_isBlockElement);

/// מעבד רצף צאצאי-בלוק לפי הסדר ומוסיף שורות ל-[output].
/// רצף inline בין בלוקים (טקסט חשוף בתוך div) נאסף לשורת פסקה משלו.
void _processBlockChildren(
  List<dom.Node> nodes,
  _EpubContext ctx,
  List<String> output,
) {
  final inlineRun = <dom.Node>[];

  void flushInlineRun() {
    if (inlineRun.isEmpty) return;
    final buf = StringBuffer();
    for (final node in inlineRun) {
      _renderInlineNode(node, ctx, buf);
    }
    inlineRun.clear();
    final text = buf.toString().trim();
    if (text.isEmpty) return;
    // תוכן inline ראשון בפרק — פולט לפניו כותרת-פרק ממתינה מה-TOC.
    final pending = ctx.pendingChapterHeading;
    if (pending != null) {
      ctx.pendingChapterHeading = null;
      output.add(_tocHeadingLine(pending));
      if (_isDupOfSynthesized(text, pending.$1)) return;
    }
    output.add(text);
  }

  for (final node in nodes) {
    if (_isBlockElement(node)) {
      flushInlineRun();
      _processBlockElement(node as dom.Element, ctx, output);
    } else {
      inlineRun.add(node);
    }
  }
  flushInlineRun();
}

void _processBlockElement(
  dom.Element e,
  _EpubContext ctx,
  List<String> output,
) {
  // גוף הערת שוליים (סמנטי או שסומן בסריקה המקדימה) — תוכנו כבר מוזרק
  // בנקודת ההפניה.
  if (_hasEpubType(e, _footnoteTypes) || ctx.consumedNotes.contains(e)) {
    return;
  }

  final tag = e.localName ?? '';
  final isHeading = _headingTags.contains(tag);
  const leafTags = {
    'p', 'figcaption', 'summary', 'dt', 'dd', 'pre', //
    'ol', 'ul', 'table', 'img', 'hr',
  };
  final isTransparentWrapper =
      !isHeading && !leafTags.contains(tag) && _containsBlockChildren(e);

  // כותרות מסונתזות מה-TOC (ספרים בלי תגיות כותרת): כותרת-עוגן נפלטת לפני
  // בלוק היעד, וכותרת-פרק ממתינה — לפני הבלוק הראשון שאינו עטיפה. פרק
  // שנפתח בכותרת אמיתית מייתר את הסינתוז.
  String? synthesizedTitle;
  final anchorHeading = ctx.tocHeadings.remove(e);
  if (isHeading) {
    ctx.pendingChapterHeading = null;
  } else if (anchorHeading != null) {
    ctx.pendingChapterHeading = null;
    output.add(_tocHeadingLine(anchorHeading));
    synthesizedTitle = anchorHeading.$1;
  } else if (!isTransparentWrapper && ctx.pendingChapterHeading != null) {
    final pending = ctx.pendingChapterHeading!;
    ctx.pendingChapterHeading = null;
    output.add(_tocHeadingLine(pending));
    synthesizedTitle = pending.$1;
  }

  switch (tag) {
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
      final text = _renderInlineChildren(e, ctx).trim();
      if (text.isEmpty) return;
      // הסטה רמה אחת מטה — h1 שמור לשם הספר (שורת הפתיחה).
      final level = (int.parse(tag.substring(1)) + 1).clamp(2, 6);
      output.add('<h$level>$text</h$level>');
    case 'p':
    case 'figcaption':
    case 'summary':
    case 'dt':
    case 'dd':
    case 'pre':
      final text = _renderInlineChildren(e, ctx).trim();
      if (text.isEmpty || _isDupOfSynthesized(text, synthesizedTitle)) return;
      output.add(text);
    case 'ol':
      _processList(e, ctx, output, ordered: true, depth: 0);
    case 'ul':
      _processList(e, ctx, output, ordered: false, depth: 0);
    case 'table':
      final tableHtml = _buildTableHtml(e, ctx);
      if (tableHtml != null) output.add(tableHtml);
    case 'img':
      final img = _imgHtml(e, ctx);
      if (img != null) output.add(img);
    case 'hr':
      return;
    case 'blockquote':
      if (_containsBlockChildren(e)) {
        _processBlockChildren(e.nodes, ctx, output);
      } else {
        final text = _renderInlineChildren(e, ctx).trim();
        if (text.isEmpty || _isDupOfSynthesized(text, synthesizedTitle)) return;
        output.add(text);
      }
    default:
      // div/section/article/aside/figure וכו' — עטיפות שקופות: יורדים
      // לילדים; עטיפה שכל תוכנה inline הופכת לשורת פסקה אחת.
      if (_containsBlockChildren(e)) {
        _processBlockChildren(e.nodes, ctx, output);
      } else {
        final text = _renderInlineChildren(e, ctx).trim();
        if (text.isEmpty || _isDupOfSynthesized(text, synthesizedTitle)) return;
        output.add(text);
      }
  }
}

String _tocHeadingLine((String, int) heading) =>
    '<h${heading.$2}>${escapeHtmlText(heading.$1)}</h${heading.$2}>';

/// האם הבלוק הוא רק כפילות של הכותרת שסונתזה זה-עתה מה-TOC (פסקת-כותרת
/// מעוצבת שממנה נלקחה הכותרת) — ואז מדלגים עליו למניעת טקסט כפול.
bool _isDupOfSynthesized(String blockHtml, String? synthesizedTitle) {
  if (synthesizedTitle == null) return false;
  final plain = blockHtml.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  return plain == synthesizedTitle.trim();
}

/// רשימות מרונדרות כשורות עם קידומת והזחה לפי עומק — לא `<ol>`/`<ul>`
/// (שנשברים בפורמט שורה-לכל-בלוק), באותה גישה כמו ממיר ה-DOCX.
void _processList(
  dom.Element list,
  _EpubContext ctx,
  List<String> output, {
  required bool ordered,
  required int depth,
}) {
  var number = int.tryParse(list.attributes['start'] ?? '') ?? 1;
  final indent = '    ' * depth;

  for (final child in list.children) {
    if (child.localName != 'li') continue;
    // פריט שהוא גוף הערה (רשימת הערות בסוף פרק) — הוזרק בנקודת ההפניה.
    if (ctx.consumedNotes.contains(child)) continue;

    final nestedLists = <dom.Element>[];
    final buf = StringBuffer();
    for (final node in child.nodes) {
      if (node is dom.Element &&
          (node.localName == 'ol' || node.localName == 'ul')) {
        nestedLists.add(node);
        continue;
      }
      if (_isBlockElement(node)) {
        buf.write(_renderInlineChildren(node as dom.Element, ctx));
        buf.write(' ');
        continue;
      }
      _renderInlineNode(node, ctx, buf);
    }

    final text = buf.toString().trim();
    if (text.isNotEmpty) {
      final label = ordered ? '${number++}.' : '•';
      output.add('$indent$label $text');
    }
    for (final nested in nestedLists) {
      _processList(
        nested,
        ctx,
        output,
        ordered: nested.localName == 'ol',
        depth: depth + 1,
      );
    }
  }
}

/// שורות הטבלה הישירות בלבד (כולל דרך thead/tbody/tfoot) — לא שורות של
/// טבלאות מקוננות בתאים, שמרונדרות רקורסיבית בתוך התא שלהן.
List<dom.Element> _directTableRows(dom.Element table) {
  final rows = <dom.Element>[];
  for (final child in table.children) {
    if (child.localName == 'tr') {
      rows.add(child);
    } else if (const {'thead', 'tbody', 'tfoot'}.contains(child.localName)) {
      rows.addAll(child.children.where((e) => e.localName == 'tr'));
    }
  }
  return rows;
}

/// טבלה → `<table>` בשורת פלט אחת (שורה=widget בקורא), כולל colspan/rowspan
/// וטבלאות מקוננות בתאים.
String? _buildTableHtml(dom.Element table, _EpubContext ctx) {
  final rows = _directTableRows(table);
  if (rows.isEmpty) return null;

  final buf = StringBuffer(
    '<table style="border-collapse: collapse; width: 100%;">',
  );
  for (final row in rows) {
    buf.write('<tr>');
    for (final cell in row.children) {
      final tag = cell.localName;
      if (tag != 'td' && tag != 'th') continue;
      final attrs = StringBuffer();
      // אימות מספרי-חיובי — העתקה מילולית הייתה מאפשרת הזרקת HTML מ-EPUB
      // זדוני, וערכי אפס/שלילי שוברים רינדור במנועי תצוגה מסוימים.
      final colspan = int.tryParse(cell.attributes['colspan'] ?? '');
      final rowspan = int.tryParse(cell.attributes['rowspan'] ?? '');
      if (colspan != null && colspan > 0) attrs.write(' colspan="$colspan"');
      if (rowspan != null && rowspan > 0) attrs.write(' rowspan="$rowspan"');
      final content = StringBuffer();
      for (final node in cell.nodes) {
        if (node is dom.Element && node.localName == 'table') {
          final nested = _buildTableHtml(node, ctx);
          if (nested != null) content.write(nested);
        } else {
          _renderInlineNode(node, ctx, content);
        }
      }
      buf.write(
        '<$tag$attrs style="border: 1px solid #999; padding: 4px;">'
        '${content.toString().trim()}</$tag>',
      );
    }
    buf.write('</tr>');
  }
  buf.write('</table>');
  return buf.toString();
}

String? _imgHtml(dom.Element e, _EpubContext ctx) {
  // גם `<image>` של SVG (עטיפת הכריכה הנפוצה) — href/xlink:href.
  final src =
      e.attributes['src'] ?? e.attributes['href'] ?? _attr(e, 'xlink:href');
  if (src == null || src.isEmpty) return null;
  final resolved = _resolveHref(ctx.baseDir, src).toLowerCase();
  final uri = ctx.images[resolved];
  if (uri == null) return null; // תמונה חיצונית/חסרה — אין מה להטמיע.
  return '<img src="$uri" style="max-width: 100%;"/>';
}

String _renderInlineChildren(dom.Element parent, _EpubContext ctx) {
  final buf = StringBuffer();
  for (final node in parent.nodes) {
    _renderInlineNode(node, ctx, buf);
  }
  return buf.toString();
}

/// תגיות inline שנשמרות כמו-שהן בפורמט אוצריא. השאר (span/a/code…) שקופות —
/// עיצוב ה-CSS של ה-EPUB ממילא אינו זמין בקורא.
const _inlineKeepTags = {
  'b': 'b', 'strong': 'b',
  'i': 'i', 'em': 'i', 'cite': 'i', 'dfn': 'i', 'var': 'i',
  'u': 'u', 'ins': 'u',
  's': 's', 'del': 's', 'strike': 's',
  'sub': 'sub', 'sup': 'sup',
  'small': 'small', 'big': 'big', //
};

void _renderInlineNode(dom.Node node, _EpubContext ctx, StringBuffer buf) {
  if (node is dom.Text) {
    buf.write(escapeHtmlText(_collapseWhitespace(node.data)));
    return;
  }
  if (node is! dom.Element) return;
  if (ctx.consumedNotes.contains(node)) {
    return; // גוף הערה inline — הוזרק בנקודת ההפניה.
  }

  final tag = node.localName ?? '';

  if (tag == 'br') {
    buf.write('<br>');
    return;
  }
  if (tag == 'img' || tag == 'image') {
    final img = _imgHtml(node, ctx);
    if (img != null) buf.write(img);
    return;
  }
  if (tag == 'a' && _renderNoteref(node, ctx, buf)) return;

  // סקריפטים/סגנונות אינם תוכן.
  if (tag == 'script' || tag == 'style' || tag == 'template') return;

  final mapped = _inlineKeepTags[tag];
  if (mapped != null) {
    buf.write('<$mapped>');
    for (final child in node.nodes) {
      _renderInlineNode(child, ctx, buf);
    }
    buf.write('</$mapped>');
    return;
  }

  for (final child in node.nodes) {
    _renderInlineNode(child, ctx, buf);
  }
}

/// הפניית הערת שוליים ([_resolveNoteref]) — מרונדרת בפורמט ההערות של
/// אוצריא, כמו בממיר ה-DOCX. מחזיר האם טופל.
bool _renderNoteref(dom.Element a, _EpubContext ctx, StringBuffer buf) {
  final res = _resolveNoteref(a, ctx);
  if (res == null) return false;

  final markerText = _collapseWhitespace(a.text).trim();
  final marker = markerText.isNotEmpty
      ? escapeHtmlText(markerText)
      : '${ctx.footnoteCounter++}';

  buf.write('<sup class="footnote-marker">$marker</sup>');
  final target = res.target;
  if (target != null) {
    final body = _extractNoteBody(target, markerText);
    if (body.isNotEmpty) {
      buf.write('<i class="footnote">${escapeHtmlText(body)}</i>');
    }
  }
  return true;
}
