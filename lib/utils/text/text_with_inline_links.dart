/// Utility functions for embedding inline links (character-based links) in text
library;

import 'package:otzaria/generated_links/models/generated_inline_link.dart';
import 'package:otzaria/models/links.dart';

/// Adds inline links to text based on character positions (start/end).
///
/// Takes a plain text string and a list of links with start/end positions,
/// and returns HTML with <a> tags inserted at the exact character positions.
///
/// Links are styled to match the theme with underline decoration.
/// The URL format is: otzaria://inline-link?path={path}&index={index}&ref={ref}
String addInlineLinksToText(String text, List<Link> linksForLine) {
  // Safety check - if text is empty or already has our inline links, return as-is
  if (text.isEmpty || text.contains('otzaria://inline-link')) {
    return text;
  }

  // Filter only links that have start and end positions
  final inlineLinks = linksForLine
      .where((link) => link.start != null && link.end != null)
      .toList();

  if (inlineLinks.isEmpty) {
    return text;
  }

  // Sort links by start position to process them in order
  inlineLinks.sort((a, b) => a.start!.compareTo(b.start!));

  // Build the text with links inserted
  final buffer = StringBuffer();
  int currentPos = 0;

  for (final link in inlineLinks) {
    final start = link.start!;
    final end = link.end!;

    // Validate positions
    if (start < 0 || end > text.length || start >= end) {
      continue; // Skip invalid links
    }

    // Skip if this link overlaps with previous one
    if (start < currentPos) {
      continue;
    }

    // Add text before the link (without escaping - keep original HTML if exists)
    if (start > currentPos) {
      buffer.write(text.substring(currentPos, start));
    }

    // Add the link
    final linkText = text.substring(start, end);
    final encodedPath = Uri.encodeComponent(link.path2);
    final encodedRef = Uri.encodeComponent(link.heRef);
    final url =
        'otzaria://inline-link?path=$encodedPath&index=${link.index2}&ref=$encodedRef';

    buffer.write('<a href="$url" style="text-decoration: underline;">');
    buffer.write(linkText);
    buffer.write('</a>');

    currentPos = end;
  }

  // Add remaining text after the last link
  if (currentPos < text.length) {
    buffer.write(text.substring(currentPos));
  }

  return buffer.toString();
}

/// מזריק `<a>` tags לפי [GeneratedInlineLink] ברשימה.
///
/// ה-URL: `otzaria://generated-link?book={title}&index0={index0}&ref={ref}`
String addGeneratedInlineLinksToText(
  String text,
  List<GeneratedInlineLink> links,
) {
  if (text.isEmpty || links.isEmpty) return text;

  final sorted = links.toList()..sort((a, b) => a.start.compareTo(b.start));

  final buffer = StringBuffer();
  int currentPos = 0;

  for (final link in sorted) {
    final start = link.start;
    final end = link.end;

    if (start < 0 || end > text.length || start >= end) continue;
    if (start < currentPos) continue;

    if (start > currentPos) buffer.write(text.substring(currentPos, start));

    final encodedBook = Uri.encodeComponent(link.target.bookTitle);
    final encodedRef = Uri.encodeComponent(link.target.displayRef);
    final bookIdParam = link.target.targetBookId != null
        ? '&bookId=${link.target.targetBookId}'
        : '';
    final url =
        'otzaria://generated-link?book=$encodedBook$bookIdParam&index0=${link.target.targetIndex}&ref=$encodedRef';

    buffer
      ..write('<a class="generated-inline-link" href="$url">')
      ..write(text.substring(start, end))
      ..write('</a>');

    currentPos = end;
  }

  if (currentPos < text.length) buffer.write(text.substring(currentPos));

  return buffer.toString();
}

/// מייצג קישור מנורמל — מכיל start/end ביחס לטקסט הגולמי + פונקציית בניית HTML.
class _NormalizedLink {
  final int start;
  final int end;
  final String Function(String linkText) buildTag;

  const _NormalizedLink(this.start, this.end, this.buildTag);
}

/// מזריק קישורי DB וקישורים שנוצרו מקומית בפעולה אחת על הטקסט הגולמי.
///
/// כך start/end של שני הסוגים מתייחסים תמיד לטקסט המקורי ולא
/// לטקסט שכבר הוזרקו בו תגיות.
String addAllInlineLinksToText(
  String text,
  List<Link> dbLinks,
  List<GeneratedInlineLink> generatedLinks,
) {
  if (text.isEmpty) return text;

  final normalized = <_NormalizedLink>[];

  for (final link in dbLinks) {
    final start = link.start;
    final end = link.end;
    if (start == null || end == null) continue;
    if (start < 0 || end > text.length || start >= end) continue;
    final encodedPath = Uri.encodeComponent(link.path2);
    final encodedRef = Uri.encodeComponent(link.heRef);
    final url =
        'otzaria://inline-link?path=$encodedPath&index=${link.index2}&ref=$encodedRef';
    normalized.add(_NormalizedLink(
      start,
      end,
      (t) => '<a href="$url" style="text-decoration: underline;">$t</a>',
    ));
  }

  for (final link in generatedLinks) {
    final start = link.start;
    final end = link.end;
    if (start < 0 || end > text.length || start >= end) continue;
    final encodedBook = Uri.encodeComponent(link.target.bookTitle);
    final encodedRef = Uri.encodeComponent(link.target.displayRef);
    final bookIdParam = link.target.targetBookId != null
        ? '&bookId=${link.target.targetBookId}'
        : '';
    final url =
        'otzaria://generated-link?book=$encodedBook$bookIdParam&index0=${link.target.targetIndex}&ref=$encodedRef';
    normalized.add(_NormalizedLink(
      start,
      end,
      (t) => '<a class="generated-inline-link" href="$url">$t</a>',
    ));
  }

  if (normalized.isEmpty) return text;

  normalized.sort((a, b) => a.start.compareTo(b.start));

  final buffer = StringBuffer();
  int currentPos = 0;

  for (final link in normalized) {
    if (link.start < currentPos) continue; // חפיפה — דלג
    if (link.start > currentPos) {
      buffer.write(text.substring(currentPos, link.start));
    }
    buffer.write(link.buildTag(text.substring(link.start, link.end)));
    currentPos = link.end;
  }

  if (currentPos < text.length) buffer.write(text.substring(currentPos));
  return buffer.toString();
}
