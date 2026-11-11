import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as markdown;
import 'package:path/path.dart' as path;

import 'package:otzaria/utils/file/html_sanitizer.dart';
import 'package:otzaria/utils/file/embedded_media.dart';
import 'package:otzaria/utils/file/text_encoding.dart';
import 'package:otzaria/utils/text/heading_slug.dart';

/// גרסת הממיר. שינוי בפלט פוסל רק רשומות Cache של Markdown.
const int kMarkdownConverterVersion = 9;

/// מסומן על כל בלוק שנוצר מהמרת Markdown, כדי שהעיצוב הייעודי לא יחול על
/// ספרי אוצריא רגילים שחולקים את אותו מנוע תצוגה.
const String kMarkdownBlockClass = 'md-block';

/// תמונות עד 2MiB מוטמעות כדי שהספר ימשיך לעבוד גם לאחר העברתו.
const int _maxInlineImageSize = 2 * 1024 * 1024;

/// סיומות הקבצים שנקלטות כספרי Markdown.
const Set<String> kMarkdownExtensions = {'.md', '.markdown'};

/// האם הספר הוא Markdown. הקורא מציג HTML מומר, ולכן כל מסלול שעלול לערבב
/// שורות מקור בשורות מוצגות חייב לשאול כאן. רשומות ותיקות שמורות כ-`txt`.
bool isMarkdownBook({String? fileType, String? filePath}) {
  final type = fileType?.toLowerCase();
  if (type == 'md' || type == 'markdown') return true;
  final lowerPath = filePath?.toLowerCase();
  if (lowerPath == null) return false;
  return kMarkdownExtensions.any(lowerPath.endsWith);
}

/// תוצאת המרת Markdown, לרבות Metadata בסיסי מ־front matter.
class MarkdownConversionResult {
  const MarkdownConversionResult({required this.html, this.title, this.author});

  final String html;
  final String? title;
  final String? author;
}

/// ממיר ספר Markdown ל־HTML הפנימי של אוצריא.
class MarkdownToOtzaria {
  const MarkdownToOtzaria();

  static const _sanitizer = BookHtmlSanitizer();

  /// ממיר מקור Markdown. הנתיב משמש לפתרון תמונות יחסיות.
  Future<MarkdownConversionResult> convertSource(
    String source, {
    String? baseDirectory,
  }) async {
    final frontMatter = _extractFrontMatter(source);
    final fragment = _parseMarkdown(frontMatter.body);
    if (baseDirectory != null) {
      await _resolveLocalImages(fragment, baseDirectory);
    }
    return MarkdownConversionResult(
      html: _renderBookLines(fragment),
      title: frontMatter.metadata['title'],
      author: frontMatter.metadata['author'],
    );
  }

  /// משלים תמונות בפלט שנשלף ממטמון ההמרות. שאר הנרמול כבר אפוי במטמון,
  /// ולכן ספר בלי תמונות חוזר כמות שהוא בלי לפרסר מחדש את כל הספר.
  Future<String> finalizeCachedHtml(String html, String baseDirectory) async {
    if (!html.contains('<img')) return html;
    final fragment = html_parser.parseFragment(html);
    await _resolveLocalImages(fragment, baseDirectory);
    return _renderBookLines(fragment);
  }

  DocumentFragment _parseMarkdown(String body) {
    final sanitized = _sanitizer.sanitize(
      markdown.markdownToHtml(
        body,
        extensionSet: markdown.ExtensionSet.gitHubWeb,
      ),
    );
    final fragment = html_parser.parseFragment(sanitized);
    var removedImageSource = false;
    for (final image in fragment.querySelectorAll('img')) {
      final src = image.attributes['src']?.trim() ?? '';
      if (!_isRelativeUrl(src) && !_isEmbeddedImageUrl(src)) {
        image.attributes.remove('src');
        removedImageSource = true;
      }
    }
    final serialized = fragment.outerHtml;
    // סבב נוסף עשוי לשנות את הפלט, למשל ב־pre בתוך תא טבלה.
    if (!removedImageSource && serialized == sanitized) return fragment;
    return html_parser.parseFragment(serialized);
  }

  /// הנרמול המשותף לכל מסלולי ההמרה. כל שינוי כאן מחייב העלאת
  /// [kMarkdownConverterVersion], אחרת המטמון יגיש פלט ישן.
  String _renderBookLines(DocumentFragment fragment) {
    _assignHeadingIds(fragment);
    _applyBlockDirections(fragment);
    return _serializeBookLines(fragment);
  }

  Future<void> _resolveLocalImages(
    DocumentFragment fragment,
    String baseDirectory,
  ) async {
    var embeddedBytes = 0;
    for (final image in fragment.querySelectorAll('img')) {
      embeddedBytes += await _resolveLocalImage(
        image,
        baseDirectory,
        embeddedBytes: embeddedBytes,
      );
    }
  }

  Future<int> _resolveLocalImage(
    Element image,
    String baseDirectory, {
    required int embeddedBytes,
  }) async {
    final source = image.attributes['src'];
    if (source == null) {
      image.attributes.remove('src');
      return 0;
    }
    if (_isEmbeddedImageUrl(source)) return 0;
    if (!_isRelativeUrl(source)) {
      image.attributes.remove('src');
      return 0;
    }
    try {
      final decoded = Uri.decodeComponent(source.split('#').first);
      final realBase = await Directory(baseDirectory).resolveSymbolicLinks();
      final candidate = path.normalize(path.join(realBase, decoded));
      final resolved = await File(candidate).resolveSymbolicLinks();
      if (!path.isWithin(realBase, resolved)) {
        image.attributes.remove('src');
        return 0;
      }
      final file = File(resolved);
      final stat = await file.stat();
      final mime = imageMimeForPath(resolved);
      if (stat.type != FileSystemEntityType.file ||
          stat.size > _maxInlineImageSize ||
          stat.size > EmbeddedMediaLimits.maxImageBytes ||
          mime == null ||
          mime == 'image/svg+xml' ||
          embeddedBytes + stat.size > EmbeddedMediaLimits.maxTotalImageBytes) {
        image.attributes.remove('src');
        return 0;
      }
      final bytes = await file.readAsBytes();
      image.attributes['src'] = 'data:$mime;base64,${base64Encode(bytes)}';
      return bytes.length;
    } on FormatException {
      image.attributes.remove('src');
      return 0;
    } on FileSystemException {
      image.attributes.remove('src');
      return 0;
    }
  }

  void _applyBlockDirections(DocumentFragment fragment) {
    const blocks = {
      'blockquote',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'li',
      'p',
      'table',
      'td',
      'th',
    };
    for (final element in fragment.querySelectorAll('*')) {
      if (element.localName == 'pre' || element.localName == 'code') {
        element.attributes['dir'] = 'ltr';
      } else if (blocks.contains(element.localName)) {
        element.attributes['dir'] = _blockDirection(element);
      }
    }
  }

  void _assignHeadingIds(DocumentFragment fragment) {
    final occurrences = <String, int>{};
    for (final heading in fragment.querySelectorAll('h1, h2, h3, h4, h5, h6')) {
      final existing = heading.attributes['id']?.trim();
      final generatedByMarkdown = _isGeneratedMarkdownId(
        existing,
        heading.text,
      );
      final base = existing?.isNotEmpty == true && !generatedByMarkdown
          ? existing!
          : headingSlug(heading.text);
      if (base.isEmpty) continue;
      final occurrence = occurrences.update(
        base,
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      heading.attributes['id'] = occurrence == 0 ? base : '$base-$occurrence';
    }
  }

  bool _isGeneratedMarkdownId(String? id, String text) {
    if (id == null || id.isEmpty) return false;
    final legacy = text
        .trim()
        .toLowerCase()
        .replaceAll(_legacyIdSeparators, '-')
        .replaceAll(_legacyIdDisallowed, '');
    return id == legacy ||
        RegExp('^${RegExp.escape(legacy)}-\\d+\$').hasMatch(id);
  }
}

final _legacyIdSeparators = RegExp(r'[\s_]+');
final _legacyIdDisallowed = RegExp(r'[^a-z0-9-]');
final _lineBreak = RegExp(r'\r?\n');

({String body, Map<String, String> metadata}) _extractFrontMatter(
  String source,
) {
  final normalized = source.replaceFirst(String.fromCharCode(0xFEFF), '');
  // רוב המסמכים אינם פותחים ב-front matter; פיצול המסמך כולו רק כדי לבדוק
  // את השורה הראשונה הוא בזבוז על כל המרה.
  final firstBreak = normalized.indexOf('\n');
  final firstLine = firstBreak < 0
      ? normalized
      : normalized.substring(0, firstBreak);
  if (firstLine.trim() != '---') {
    return (body: normalized, metadata: const {});
  }
  final lines = normalized.split(_lineBreak);
  var end = -1;
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trim() == '---') {
      end = i;
      break;
    }
  }
  if (end < 0) return (body: normalized, metadata: const {});

  final metadata = <String, String>{};
  for (final line in lines.sublist(1, end)) {
    final separator = line.indexOf(':');
    if (separator <= 0) continue;
    final key = line.substring(0, separator).trim().toLowerCase();
    final value = line.substring(separator + 1).trim();
    if (key.isNotEmpty && value.isNotEmpty) metadata[key] = value;
  }
  return (body: lines.skip(end + 1).join('\n'), metadata: metadata);
}

bool _isRelativeUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      !uri.hasScheme &&
      !value.startsWith('/') &&
      !value.startsWith('#');
}

bool _isEmbeddedImageUrl(String value) =>
    value.trim().toLowerCase().startsWith('data:image/');

/// כיוון של בלוק תוכן, נגזר מהטקסט שמחוץ ל-`code`/`pre`: טוקני קוד לטיניים
/// בפתח שורה עברית (למשל «`side` — העוגן») סיווגו אותה כ-LTR והפכו אותה.
String _blockDirection(Element element) {
  String? firstStrongOutsideCode(Node node) {
    if (node is Text) return _firstStrongDirection(node.text);
    if (node is Element && const {'code', 'pre'}.contains(node.localName)) {
      return null;
    }
    for (final child in node.nodes) {
      final direction = firstStrongOutsideCode(child);
      // Stop as soon as the first strong character is known. Building the
      // entire descendant text here was costly for long tables and lists,
      // especially because their descendants are also checked individually.
      if (direction != null) return direction;
    }
    return null;
  }

  return firstStrongOutsideCode(element) ??
      _firstStrongDirection(element.text) ??
      'rtl';
}

/// `'rtl'`/`'ltr'` לפי התו החזק הראשון, או null כשאין בטקסט תו חזק כלל.
String? _firstStrongDirection(String text) {
  for (final rune in text.runes) {
    if ((rune >= 0x0590 && rune <= 0x05FF) ||
        (rune >= 0xFB1D && rune <= 0xFB4F)) {
      return 'rtl';
    }
    if ((rune >= 0x0041 && rune <= 0x005A) ||
        (rune >= 0x0061 && rune <= 0x007A)) {
      return 'ltr';
    }
  }
  return null;
}

/// עוטפים שקופים שיש לפרק. מסמך עברי נפתח לרוב ב-`<div dir="rtl">` שעוטף את
/// כל הגוף, ובלי פירוקו הספר כולו נשמר כשורה אחת — בלי תוכן עניינים וניווט.
const _transparentContainers = {'div', 'section', 'article', 'main'};

const _blockLevelTags = {
  'blockquote',
  'div',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'hr',
  'ol',
  'p',
  'pre',
  'section',
  'article',
  'main',
  'table',
  'ul',
};

/// כל אלמנט בלוק נשמר כשורת מקור אחת, בהתאם למודל הקריאה של אוצריא.
String _serializeBookLines(DocumentFragment fragment) {
  final lines = <String>[];
  _collectBookLines(fragment.nodes, lines, inheritedDir: null);
  return lines.join('\n');
}

void _collectBookLines(
  List<Node> nodes,
  List<String> lines, {
  required String? inheritedDir,
}) {
  for (final node in nodes) {
    if (node is Text) {
      if (node.text.trim().isEmpty) continue;
      final html = _asBookLine(htmlEscape.convert(node.text));
      if (html.trim().isNotEmpty) lines.add(html);
      continue;
    }
    if (node is! Element) continue;

    if (_transparentContainers.contains(node.localName) &&
        _hasBlockChild(node)) {
      _collectBookLines(
        node.nodes,
        lines,
        inheritedDir: node.attributes['dir'] ?? inheritedDir,
      );
      continue;
    }

    if (!_carriesContent(node)) continue;

    // כיווניות של עוטף שפורק נשמרת על הבלוקים שאין להם כיווניות משלהם
    // (למשל `ul`/`ol`/`table`), כדי לא לאבד את כוונת המחבר.
    if (inheritedDir != null && !node.attributes.containsKey('dir')) {
      node.attributes['dir'] = inheritedDir;
    }

    // סימון מקור: ה-HTML של אוצריא משותף לכל סוגי הספרים, ולכן העיצוב
    // הייעודי ל-Markdown חייב להיות ניתן לזיהוי ולא לחול על ספרים אחרים.
    node.classes.add(kMarkdownBlockClass);

    final html = _asBookLine(node.outerHtml);
    if (html.trim().isNotEmpty) lines.add(html);
  }
}

bool _hasBlockChild(Element element) => element.children.any(
  (child) => _blockLevelTags.contains(child.localName),
);

/// אלמנט ריק (למשל `<i>\n</i>` מתגית פתוחה) אינו שורת ספר. `hr`/`img` ועוגני
/// יעד ריקים (`<a name="…">`) כן — הם היעד של קישורים פנימיים.
bool _carriesContent(Element element) {
  if (element.text.trim().isNotEmpty) return true;
  if (const {'hr', 'img'}.contains(element.localName)) return true;
  if (element.attributes.containsKey('id') ||
      element.attributes.containsKey('name')) {
    return true;
  }
  return element.querySelectorAll('a[name], a[id], hr, img').isNotEmpty;
}

String _asBookLine(String serialized) =>
    serialized.replaceAll('\r\n', '\n').replaceAll('\n', '&#10;');

/// Worker סינכרוני לשימוש ב־Isolate ובמטמון ההמרות הקיים. תמונות מקומיות
/// נפתרות אחר כך ב-[MarkdownToOtzaria.finalizeCachedHtml] — כאן אין נתיב.
String markdownBytesToHtml(Uint8List bytes, String title) {
  const converter = MarkdownToOtzaria();
  final body = _extractFrontMatter(decodeTextBytesSmart(bytes)).body;
  return converter._renderBookLines(converter._parseMarkdown(body));
}
