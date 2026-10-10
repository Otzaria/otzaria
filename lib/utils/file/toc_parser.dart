import 'package:otzaria/models/books.dart';

/// Shared TOC parsing utilities used by both the TextBook navigator and
/// the Shamor Zachor scanner. This ensures a single source of truth for
/// how headings are detected and converted to structures.
/// סימון על תגית כותרת שמוציא אותה מתוכן העניינים (ומ-heRef): כותרת
/// עיצובית שאינה חלק מתוכן העניינים המוטמע של הספר (ראו epub_to_otzaria).
const String kTocExcludeAttr = 'data-toc="none"';

/// האם שורת `<h#...>` נושאת את סימון ההדרה בתגית הפתיחה.
bool isTocExcludedHeadingLine(String lowerLine) {
  final tagEnd = lowerLine.indexOf('>');
  return tagEnd > 0 && lowerLine.substring(0, tagEnd).contains(kTocExcludeAttr);
}

final RegExp _markdownHeading = RegExp(r'^(#{1,6})\s+(.+?)\s*$');

class TocParser {
  /// Parse TOC entries (hierarchical) from the full book content.
  static List<TocEntry> parseEntriesFromContent(String content) {
    final headers = _extractHeaders(content);
    return _buildHierarchy(headers);
  }

  /// Internal representation of a detected heading line.
  static List<_Header> _extractHeaders(String content) {
    final lines = content.split('\n');
    final List<_Header> headers = [];

    for (int i = 0; i < lines.length; i++) {
      final rawLine = lines[i];
      final line = rawLine.trimLeft();

      // Markdown headings: # .. ######
      // We require a space after the hashes to reduce false positives.
      final md = line.startsWith('#')
          ? _markdownHeading.firstMatch(line)
          : null;
      if (md != null) {
        final level = md.group(1)!.length;
        final text = md.group(2)!.trim();
        if (text.isNotEmpty) {
          headers.add(_Header(text: text, index: i, level: level));
        }
        continue;
      }

      // Match <h1>..</h1> up to <h6>
      // הורדת אותיות רק לשורה שנפתחת ב-<h — שורות הטקסט ארוכות ורובן כאלה.
      if (!line.startsWith('<h') && !line.startsWith('<H')) continue;
      final lower = line.toLowerCase();
      if (lower.length > 3) {
        final c = lower[2];
        final code = c.codeUnitAt(0);
        if (code >= '1'.codeUnitAt(0) && code <= '6'.codeUnitAt(0)) {
          if (isTocExcludedHeadingLine(lower)) continue;
          final level = int.tryParse(c) ?? 1;
          final text = _stripHtmlTags(line);
          if (text.isNotEmpty) {
            headers.add(_Header(text: text, index: i, level: level));
          }
          continue;
        }
      }

      // Removed fallback for bold-only lines as it was too broad
      // and incorrectly identified regular bold text as headers
    }

    return headers;
  }

  static List<TocEntry> _buildHierarchy(List<_Header> headers) {
    final List<TocEntry> roots = [];
    // שרשרת הכותרות הפתוחות: ההורה הוא הקודמת הקרובה שרמתה נמוכה יותר.
    final List<TocEntry> open = [];

    for (final h in headers) {
      while (open.isNotEmpty && open.last.level >= h.level) {
        open.removeLast();
      }
      final parent = open.isEmpty ? null : open.last;
      final entry = TocEntry(
        text: h.text,
        index: h.index,
        level: h.level,
        parent: parent,
      );
      (parent?.children ?? roots).add(entry);
      open.add(entry);
    }

    return roots;
  }

  static String _stripHtmlTags(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }
}

class _Header {
  final String text;
  final int index;
  final int level;
  _Header({required this.text, required this.index, required this.level});
}
