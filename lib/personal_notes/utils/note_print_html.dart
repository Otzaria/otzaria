import 'dart:convert';

import 'package:otzaria/personal_notes/models/personal_note.dart';

/// הערה כפסקאות HTML פנים-שורתי שההדפסה והוורד מבינים. קישור http נשמר
/// כטקסט, וקישור פנימי של התוכנה מושמט.
List<String> noteHtmlParagraphs({
  required String content,
  required String contentPlain,
  required PersonalNoteContentFormat format,
}) {
  List<String> fromPlain() =>
      contentPlain.trimRight().split('\n').map(escapePrintHtml).toList();

  if (format != PersonalNoteContentFormat.quillDelta) {
    return fromPlain();
  }
  try {
    final decoded = jsonDecode(content) as List<dynamic>;
    final paragraphs = <String>[];
    final current = StringBuffer();
    for (final op in decoded) {
      if (op is! Map<String, dynamic>) continue;
      final insert = op['insert'];
      if (insert is! String) continue;
      final rawAttributes = op['attributes'];
      final attributes = rawAttributes is Map<String, dynamic>
          ? rawAttributes
          : null;
      final parts = insert.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) {
          current.write(_styledHtml(parts[i], attributes));
        }
        if (i < parts.length - 1) {
          paragraphs.add(current.toString());
          current.clear();
        }
      }
    }
    if (current.isNotEmpty) paragraphs.add(current.toString());
    return paragraphs;
  } catch (_) {
    return fromPlain();
  }
}

String _styledHtml(String text, Map<String, dynamic>? attributes) {
  var html = escapePrintHtml(text);
  final link = attributes?['link'];
  if (link is String && link.startsWith('http') && text.trim().isNotEmpty) {
    html = '$html (${escapePrintHtml(link)})';
  }
  if (attributes?['bold'] == true) html = '<b>$html</b>';
  if (attributes?['italic'] == true) html = '<i>$html</i>';
  if (attributes?['underline'] == true) html = '<u>$html</u>';
  if (attributes?['strike'] == true) html = '<s>$html</s>';
  final script = attributes?['script'];
  if (script == 'super') html = '<sup>$html</sup>';
  if (script == 'sub') html = '<sub>$html</sub>';
  return html;
}

String escapePrintHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
