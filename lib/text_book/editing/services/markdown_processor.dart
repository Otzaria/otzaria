// lib/text_book/editing/services/markdown_processor.dart
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;

// אין צורך בייבוא שאינו בשימוש
// import '../models/editor_settings.dart';
// import 'link_sanitizer.dart';

/// Service for processing and sanitizing HTML content directly from the editor.
class MarkdownProcessor {
  const MarkdownProcessor();

  /// Cache for processed HTML to improve performance
  static final Map<String, String> _htmlCache = {};
  static const int _maxCacheSize = 100;

  /// Processes HTML input from the editor for the preview pane.
  /// It converts newlines to <br> tags and then sanitizes the HTML.
  /// This function is named markdownToHtml for consistency with your existing code.
  /// Uses caching for better performance.
  String markdownToHtml(String rawInput) {
    if (rawInput.isEmpty) return '';

    // Generate cache key from input hash
    final cacheKey = rawInput.hashCode.toString();

    // Check cache first
    if (_htmlCache.containsKey(cacheKey)) {
      return _htmlCache[cacheKey]!;
    }

    try {
      // Step 1: Convert all newline characters from the text editor into <br> tags.
      // This is the correct way to handle line breaks in an HTML context.
      String htmlWithBreaks = rawInput.replaceAll('\n', '<br>');

      // Step 2: Sanitize the HTML to remove any potentially unsafe tags or attributes.
      String sanitizedHtml = sanitizeHtml(htmlWithBreaks);

      // Step 3: Wrap the final content in an RTL div for correct text direction.
      final result = '<div dir="rtl">$sanitizedHtml</div>';

      // Cache the result
      _htmlCache[cacheKey] = result;

      // Clean up cache if too large
      if (_htmlCache.length > _maxCacheSize) {
        final keysToRemove = _htmlCache.keys
            .take(_htmlCache.length - _maxCacheSize)
            .toList();
        for (final key in keysToRemove) {
          _htmlCache.remove(key);
        }
      }

      return result;
    } catch (e) {
      // As a safe fallback, escape the raw input to prevent rendering broken HTML.
      return _escapeHtml(rawInput);
    }
  }

  /// Clears the HTML cache (useful when switching documents or for testing)
  static void clearCache() {
    _htmlCache.clear();
  }

  /// Sanitizes an HTML string, allowing only a safe subset of tags and attributes.
  String sanitizeHtml(String html) {
    if (html.isEmpty) return '';

    try {
      final document = html_parser.parse(html);
      final body = document.body;
      if (body == null) return '';

      // The key fix is here: we iterate over the body's children
      // and sanitize them, instead of trying to sanitize the body tag itself.
      body.nodes.toList().forEach(_sanitizeNode);

      return body.innerHtml;
    } catch (e) {
      return _escapeHtml(html);
    }
  }

  /// Recursively sanitizes a node, removing anything not on the allow-list.
  void _sanitizeNode(html_dom.Node node) {
    if (node is html_dom.Element) {
      // If the tag is not in our allow-list, replace it with its text content.
      if (!_getAllowedTags().contains(node.localName)) {
        node.replaceWith(html_dom.Text(node.text));
        return; // The node was replaced, so we stop processing this branch.
      }

      // Remove any attributes that are not explicitly allowed for the given tag.
      final allowedAttributes =
          _getAllowedAttributes()[node.localName] ?? const <String>{};
      final attributesToRemove = <dynamic>{};
      node.attributes.forEach((key, value) {
        if (!allowedAttributes.contains(key.toString())) {
          attributesToRemove.add(key);
        }
      });
      attributesToRemove.forEach(node.attributes.remove);
    }

    // Process all child nodes recursively.
    // We use toList() to create a copy, preventing modification errors during iteration.
    node.nodes.toList().forEach(_sanitizeNode);
  }

  /// Returns the set of all allowed HTML tags.
  Set<String> _getAllowedTags() {
    return {
      'p',
      'br',
      'b',
      'strong',
      'i',
      'em',
      'h1',
      'h2',
      'h3',
      'ul',
      'ol',
      'li',
      'a',
      'code',
      'pre',
      'blockquote',
      'div',
      'span',
    };
  }

  /// Returns a map of allowed attributes for each tag.
  Map<String, Set<String>> _getAllowedAttributes() {
    return {
      'a': {'href'},
      // All other tags have no allowed attributes by default.
    };
  }

  /// Escapes special HTML characters to prevent them from being interpreted as code.
  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;');
  }
}
