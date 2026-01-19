/// Utility functions for embedding inline links (character-based links) in text
library;

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
    final url = 'otzaria://inline-link?path=$encodedPath&index=${link.index2}&ref=$encodedRef';
    
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
