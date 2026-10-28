import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'package:otzaria/utils/file/document_conversion_exceptions.dart';
import 'package:otzaria/utils/file/document_format.dart';
import 'package:otzaria/utils/file/html_to_otzaria.dart';

/// דף אינטרנט שנשמר בשם של מסמך Word. Word פותח אותו כרגיל ושומר אותו שוב
/// באותו פורמט, ולכן קבצים כאלה מסתובבים כ"קובצי .doc" לכל דבר.
enum WordWebPageKind {
  /// HTML רגיל, כמו בייצוא "שמור כ-Word" של אתרים.
  html,

  /// ארכיון MHTML ("דף אינטרנט בקובץ יחיד"): HTML ותמונות בקובץ MIME אחד.
  mhtml,
}

/// מזהה דף אינטרנט לפי ראש הקובץ. מחזיר `null` לכל תוכן אחר.
WordWebPageKind? sniffWordWebPage(Uint8List bytes) {
  final head = _decodeHead(bytes);
  final headers = _headerBlockPattern.firstMatch(head);
  if (headers != null &&
      _multipartRelatedPattern.hasMatch(head.substring(0, headers.start))) {
    return WordWebPageKind.mhtml;
  }
  if (_htmlStartPattern.hasMatch(head)) return WordWebPageKind.html;
  return null;
}

/// ממיר דף אינטרנט שזוהה ב-[sniffWordWebPage] דרך מנוע ה-HTML.
///
/// [format] הוא הפורמט שהסיומת הצהירה עליו, והוא זה שנרשם בחריגות.
String wordWebPageToText(
  Uint8List bytes,
  String title, {
  required WordWebPageKind kind,
  required DocumentFormat format,
  String? path,
  bool embedImages = true,
}) {
  switch (kind) {
    case WordWebPageKind.html:
      return htmlToText(
        bytes,
        title,
        format: format,
        embedImages: embedImages,
        baseDirectory: path == null ? null : p.dirname(path),
      );
    case WordWebPageKind.mhtml:
      final archive = _MhtmlArchive.parse(bytes, format: format, path: path);
      return htmlToText(
        archive.rootHtml,
        title,
        format: format,
        embedImages: embedImages,
        archivedImages: archive.lookupImage,
      );
  }
}

const int _sniffWindow = 8 * 1024;

final RegExp _headerBlockPattern = RegExp(r'\r?\n\r?\n');
final RegExp _multipartRelatedPattern = RegExp(
  r'^content-type:\s*multipart/related',
  caseSensitive: false,
  multiLine: true,
);
final RegExp _htmlStartPattern = RegExp(
  r'^\s*(?:<\?xml[^>]*>\s*)?(?:<!--[\s\S]*?-->\s*)*'
  r'<(?:!doctype\s+html|html[\s>])',
  caseSensitive: false,
);

/// ראש הקובץ כטקסט. Word שומר HTML גם ב-UTF-16, ולכן BOM מכריע; אחרת כל
/// בייט הוא תו, וזה מספיק לתגיות ולכותרות ה-ASCII שמחפשים כאן.
String _decodeHead(Uint8List bytes) {
  final length = bytes.length < _sniffWindow ? bytes.length : _sniffWindow;
  if (length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes, 2, length, littleEndian: true);
  }
  if (length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes, 2, length, littleEndian: false);
  }
  final start =
      length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF
      ? 3
      : 0;
  return latin1.decode(Uint8List.sublistView(bytes, start, length));
}

String _decodeUtf16(
  Uint8List bytes,
  int start,
  int end, {
  required bool littleEndian,
}) {
  final units = <int>[];
  for (var i = start; i + 1 < end; i += 2) {
    units.add(
      littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1],
    );
  }
  return String.fromCharCodes(units);
}

// ── MHTML ─────────────────────────────────────────────────────────────────

class _MhtmlPart {
  _MhtmlPart(this.headers, this._body);

  final Map<String, String> headers;
  final String _body;

  String get contentType => headers['content-type'] ?? '';
  String get mimeType => contentType.split(';').first.trim().toLowerCase();

  /// התוכן המפוענח, או `null` כשהקידוד שבור.
  Uint8List? decode() {
    final encoding = (headers['content-transfer-encoding'] ?? '')
        .trim()
        .toLowerCase();
    try {
      return switch (encoding) {
        'base64' => base64Decode(_body.replaceAll(_whitespace, '')),
        'quoted-printable' => _decodeQuotedPrintable(_body),
        _ => latin1.encode(_body),
      };
    } on FormatException {
      return null;
    }
  }
}

class _MhtmlArchive {
  _MhtmlArchive._(this.rootHtml, this._rootLocation, this._resources);

  final Uint8List rootHtml;
  final Uri? _rootLocation;
  final List<_MhtmlPart> _resources;

  static _MhtmlArchive parse(
    Uint8List bytes, {
    required DocumentFormat format,
    String? path,
  }) {
    Never fail(String cause) => throw CorruptedDocumentException(
      path: path,
      format: format,
      cause: cause,
    );

    // latin1 ממפה כל בייט לתו אחד, כך שהמבנה נשמר והבייטים חוזרים כמו שהם.
    final text = latin1.decode(bytes);
    final (topHeaders, body) = _splitHeaders(text);
    final contentType = topHeaders['content-type'] ?? '';
    final boundary = _headerParam(contentType, 'boundary');
    if (boundary == null || boundary.isEmpty) fail('ארכיון MHTML בלי boundary');

    final parts = _splitParts(body, boundary);
    final start = _headerParam(contentType, 'start');
    final root =
        _findByContentId(parts, start) ??
        parts.where((part) => part.mimeType == 'text/html').firstOrNull;
    if (root == null) fail('אין בארכיון MHTML דף HTML');

    final html = root.decode();
    if (html == null) fail('קידוד שבור בדף ה-HTML של הארכיון');

    return _MhtmlArchive._(
      _withCharsetBom(html, _headerParam(root.contentType, 'charset')),
      _parseLocation(root.headers['content-location']),
      [
        for (final part in parts)
          if (!identical(part, root)) part,
      ],
    );
  }

  /// תמונה מתוך הארכיון לפי `src` שלה: `cid:`, או כתובת יחסית לדף הראשי.
  ({String mime, Uint8List bytes})? lookupImage(String src) {
    final part = src.toLowerCase().startsWith('cid:')
        ? _findByContentId(_resources, src.substring(4))
        : _findByLocation(src);
    if (part == null) return null;
    final bytes = part.decode();
    if (bytes == null) return null;
    return (mime: part.mimeType, bytes: bytes);
  }

  _MhtmlPart? _findByLocation(String src) {
    final Uri? target;
    try {
      target = _rootLocation?.resolve(src) ?? Uri.parse(src);
    } on FormatException {
      return null;
    }
    final wanted = target.toString();
    for (final part in _resources) {
      if (_parseLocation(part.headers['content-location'])?.toString() ==
          wanted) {
        return part;
      }
    }
    return null;
  }
}

_MhtmlPart? _findByContentId(List<_MhtmlPart> parts, String? id) {
  final wanted = _stripAngles(id);
  if (wanted == null || wanted.isEmpty) return null;
  for (final part in parts) {
    if (_stripAngles(part.headers['content-id']) == wanted) return part;
  }
  return null;
}

String? _stripAngles(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null) return null;
  if (trimmed.startsWith('<') && trimmed.endsWith('>')) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

Uri? _parseLocation(String? location) {
  final value = location?.trim();
  if (value == null || value.isEmpty) return null;
  return Uri.tryParse(value);
}

/// Word מצהיר `charset="unicode"` על UTF-16LE. בלי BOM מנוע ה-HTML היה מנחש,
/// ולכן ההצהרה של הארכיון הופכת ל-BOM.
Uint8List _withCharsetBom(Uint8List html, String? charset) {
  if (html.length >= 2 &&
      ((html[0] == 0xFF && html[1] == 0xFE) ||
          (html[0] == 0xFE && html[1] == 0xFF))) {
    return html;
  }
  final bom = switch (charset?.toLowerCase()) {
    'unicode' || 'utf-16' || 'utf-16le' => const [0xFF, 0xFE],
    'unicodefffe' || 'utf-16be' => const [0xFE, 0xFF],
    _ => null,
  };
  if (bom == null) return html;
  return Uint8List(html.length + 2)
    ..setRange(0, 2, bom)
    ..setRange(2, html.length + 2, html);
}

(Map<String, String>, String) _splitHeaders(String text) {
  final separator = _headerBlockPattern.firstMatch(text);
  final headerText = separator == null
      ? text
      : text.substring(0, separator.start);
  final body = separator == null ? '' : text.substring(separator.end);

  final headers = <String, String>{};
  String? lastName;
  for (final line in headerText.split(_lineBreak)) {
    if (line.isEmpty) continue;
    // שורת המשך (folding) מתחילה ברווח ושייכת לכותרת הקודמת.
    if ((line.startsWith(' ') || line.startsWith('\t')) && lastName != null) {
      headers[lastName] = '${headers[lastName]} ${line.trim()}';
      continue;
    }
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    lastName = line.substring(0, colon).trim().toLowerCase();
    headers[lastName] = line.substring(colon + 1).trim();
  }
  return (headers, body);
}

List<_MhtmlPart> _splitParts(String body, String boundary) {
  final delimiter = '--$boundary';
  final parts = <_MhtmlPart>[];
  var index = body.startsWith(delimiter)
      ? 0
      : _nextDelimiter(body, delimiter, 0);
  while (index >= 0) {
    final afterDelimiter = index + delimiter.length;
    if (body.startsWith('--', afterDelimiter)) break;
    final lineEnd = body.indexOf('\n', afterDelimiter);
    if (lineEnd < 0) break;
    final next = _nextDelimiter(body, delimiter, lineEnd);
    var content = body.substring(lineEnd + 1, next < 0 ? body.length : next);
    // שבירת השורה שלפני ה-delimiter שייכת לו ולא לתוכן החלק.
    if (content.endsWith('\n')) {
      content = content.substring(0, content.length - 1);
    }
    if (content.endsWith('\r')) {
      content = content.substring(0, content.length - 1);
    }
    final (headers, partBody) = _splitHeaders(content);
    parts.add(_MhtmlPart(headers, partBody));
    index = next;
  }
  return parts;
}

/// מיקום ה-delimiter הבא שפותח שורה, או `-1`.
int _nextDelimiter(String body, String delimiter, int from) {
  final index = body.indexOf('\n$delimiter', from);
  return index < 0 ? -1 : index + 1;
}

String? _headerParam(String header, String name) {
  final match = RegExp(
    ';\\s*$name\\s*=\\s*(?:"([^"]*)"|([^;\\s]+))',
    caseSensitive: false,
  ).firstMatch(header);
  if (match == null) return null;
  return match.group(1) ?? match.group(2);
}

Uint8List _decodeQuotedPrintable(String body) {
  final buffer = <int>[];
  for (var i = 0; i < body.length; i++) {
    final unit = body.codeUnitAt(i);
    if (unit != 0x3D) {
      buffer.add(unit);
      continue;
    }
    // `=` בסוף שורה הוא שבירה רכה: השורה ממשיכה בשורה הבאה.
    if (body.startsWith('\r\n', i + 1)) {
      i += 2;
      continue;
    }
    if (body.startsWith('\n', i + 1)) {
      i += 1;
      continue;
    }
    final value = i + 2 < body.length
        ? int.tryParse(body.substring(i + 1, i + 3), radix: 16)
        : null;
    if (value == null) {
      buffer.add(unit);
      continue;
    }
    buffer.add(value);
    i += 2;
  }
  return Uint8List.fromList(buffer);
}

final RegExp _whitespace = RegExp(r'\s');
final RegExp _lineBreak = RegExp(r'\r?\n');
