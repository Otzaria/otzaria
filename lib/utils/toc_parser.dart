import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:otzaria/models/books.dart';

/// Shared TOC parsing utilities used by both the TextBook navigator and
/// the Shamor Zachor scanner. This ensures a single source of truth for
/// how headings are detected and converted to structures.
class TocParser {
  /// Parse TOC from a file path and return a flat structure compatible with
  /// Shamor Zachor scanner (list of maps with text/index/level).
  static Future<List<Map<String, dynamic>>> parseFlatFromFile(String bookPath) async {
    try {
      final file = File(bookPath);
      if (!await file.exists()) {
        if (kDebugMode) debugPrint('Book file not found: $bookPath');
        return [];
      }
      final content = await file.readAsString();
      final headers = _extractHeaders(content);
      return headers
          .map((h) => {
                'text': h.text,
                'index': h.index,
                'level': h.level,
              })
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('Error parsing TOC from $bookPath: $e');
      return [];
    }
  }

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
      final line = lines[i];

      // Match <h1>..</h1> up to <h6>
      if (line.startsWith('<h') && line.length > 3) {
        final c = line[2];
        final code = c.codeUnitAt(0);
        if (code >= '1'.codeUnitAt(0) && code <= '6'.codeUnitAt(0)) {
          final level = int.tryParse(c) ?? 1;
          final text = _stripHtmlTags(line);
          if (text.isNotEmpty) {
            headers.add(_Header(text: text, index: i, level: level));
          }
          continue;
        }
      }

      // Fallback: consider short bold-only lines as level-1 headers
      if (line.contains('<b>') && !line.contains('<br>')) {
        final text = _stripHtmlTags(line);
        if (text.isNotEmpty && text.length < 100) {
          headers.add(_Header(text: text, index: i, level: 1));
        }
      }
    }

    return headers;
  }

  static List<TocEntry> _buildHierarchy(List<_Header> headers) {
    final List<TocEntry> roots = [];
    final Map<int, TocEntry> parents = {};

    for (final h in headers) {
      if (h.level <= 1) {
        final root = TocEntry(text: h.text, index: h.index, level: 1);
        roots.add(root);
        parents[1] = root;
        continue;
      }

      final parent = parents[h.level - 1];
      final entry = TocEntry(
        text: h.text,
        index: h.index,
        level: h.level,
        parent: parent,
      );
      if (parent != null) {
        parent.children.add(entry);
      } else {
        // No known parent at level-1, treat as root to avoid losing headers
        roots.add(entry);
      }
      parents[h.level] = entry;
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
