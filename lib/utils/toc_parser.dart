import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/data/data_providers/library_provider_manager.dart';

/// Shared TOC parsing utilities used by both the TextBook navigator and
/// the Shamor Zachor scanner. This ensures a single source of truth for
/// how headings are detected and converted to structures.
class TocParser {
  /// Parse TOC from a file path or database and return a flat structure compatible with
  /// Shamor Zachor scanner (list of maps with text/index/level).
  static Future<List<Map<String, dynamic>>> parseFlatFromFile(
      String bookPath) async {
    try {
      // Extract book title from path
      final bookTitle =
          bookPath.split(Platform.pathSeparator).last.replaceAll('.txt', '');

      // Try to get TOC from LibraryProviderManager (handles both DB and files)
      try {
        // Note: We don't have category/fileType here, so we pass empty strings
        // This relies on the fuzzy matching in LibraryProviderManager
        final tocEntries =
          await LibraryProviderManager.instance.getBookToc(bookTitle, '', 'txt');
        if (tocEntries != null && tocEntries.isNotEmpty) {
          // Convert hierarchical TOC to flat structure
          final flatToc = <Map<String, dynamic>>[];
          void flattenToc(List<TocEntry> entries) {
            for (final entry in entries) {
              flatToc.add({
                'text': entry.text,
                'index': entry.index,
                'level': entry.level,
              });
              if (entry.children.isNotEmpty) {
                flattenToc(entry.children);
              }
            }
          }

          flattenToc(tocEntries);
          return flatToc;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Error getting TOC from provider: $e');
        // Fall through to file reading
      }

      // Fallback to file reading
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
      final rawLine = lines[i];
      final line = rawLine.trimLeft();

      // Markdown headings: # .. ######
      // We require a space after the hashes to reduce false positives.
      final md = RegExp(r'^(#{1,6})\s+(.+?)\s*$').firstMatch(line);
      if (md != null) {
        final level = md.group(1)!.length;
        final text = md.group(2)!.trim();
        if (text.isNotEmpty) {
          headers.add(_Header(text: text, index: i, level: level));
        }
        continue;
      }

      // Match <h1>..</h1> up to <h6>
      final lower = line.toLowerCase();
      if (lower.startsWith('<h') && lower.length > 3) {
        final c = lower[2];
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

      // Removed fallback for bold-only lines as it was too broad
      // and incorrectly identified regular bold text as headers
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
