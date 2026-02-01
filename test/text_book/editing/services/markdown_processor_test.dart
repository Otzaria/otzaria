import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/editing/services/markdown_processor.dart';

void main() {
  group('MarkdownProcessor', () {
    late MarkdownProcessor processor;

    setUp(() {
      processor = const MarkdownProcessor();
    });

    group('Basic Markdown Conversion', () {
      test('should convert newlines to br tags', () {
        const markdown = '''Line 1
Line 2
Line 3''';

        final html = processor.markdownToHtml(markdown);

        expect(html, contains('Line 1<br>Line 2<br>Line 3'));
        expect(html, contains('dir="rtl"'));
      });

      test('should preserve text content', () {
        const markdown = '**bold text** and *italic text*';

        final html = processor.markdownToHtml(markdown);

        expect(html, contains('**bold text** and *italic text*'));
        expect(html, contains('dir="rtl"'));
      });

      test('should preserve link syntax', () {
        const markdown = '[link text](https://example.com)';

        final html = processor.markdownToHtml(markdown);

        expect(html, contains('[link text](https://example.com)'));
      });

      test('should preserve code block syntax', () {
        const markdown = '''```
code block
```''';

        final html = processor.markdownToHtml(markdown);

        expect(html, contains('```<br>code block<br>```'));
      });

      test('should preserve inline code syntax', () {
        const markdown = 'This is `inline code` text';

        final html = processor.markdownToHtml(markdown);

        expect(html, contains('This is `inline code` text'));
      });

      test('should preserve blockquote syntax', () {
        const markdown = '> This is a quote';

        final html = processor.markdownToHtml(markdown);

        expect(html, contains('&gt; This is a quote'));
      });

      test('should preserve list syntax', () {
        const markdown = '''- Item 1
- Item 2''';

        final html = processor.markdownToHtml(markdown);

        expect(html, contains('- Item 1<br>- Item 2'));
      });
    });

    group('HTML Sanitization', () {
      test('should remove script tags', () {
        const html = '<p>Safe content</p><script>alert("xss")</script>';

        final sanitized = processor.sanitizeHtml(html);

        expect(sanitized, contains('Safe content'));
        expect(sanitized, isNot(contains('<script>')));
        // Note: The text content of script tags is preserved but the tag itself is removed
      });

      test('should remove dangerous attributes', () {
        const html = '<p onclick="alert(\'xss\')">Content</p>';

        final sanitized = processor.sanitizeHtml(html);

        expect(sanitized, contains('Content'));
        expect(sanitized, isNot(contains('onclick')));
      });

      test('should allow safe tags and attributes', () {
        const html = '<p><strong>Bold</strong> and <em>italic</em></p>';

        final sanitized = processor.sanitizeHtml(html);

        expect(sanitized, contains('<strong>Bold</strong>'));
        expect(sanitized, contains('<em>italic</em>'));
      });

      test('should handle empty input', () {
        final result = processor.markdownToHtml('');
        expect(result, equals(''));
      });

      test('should escape HTML in plain text', () {
        const markdown = 'Text with <script> tags';

        final html = processor.markdownToHtml(markdown);

        // The processor converts newlines to <br> and wraps in RTL div
        // HTML entities are escaped during sanitization
        expect(html, contains('Text with'));
        expect(html, contains('tags'));
        expect(html, isNot(contains('<script>')));
      });
    });

    group('RTL Text Direction', () {
      test('should wrap content in RTL container', () {
        const markdown = 'Hebrew text';

        final html = processor.markdownToHtml(markdown);

        expect(html, contains('dir="rtl"'));
      });

      test('should handle code syntax', () {
        const markdown = '`code`';

        final html = processor.markdownToHtml(markdown);

        expect(html, contains('`code`'));
      });
    });

    group('Error Handling', () {
      test('should handle malformed HTML gracefully', () {
        const malformed = '<p>Unclosed tag';

        final sanitized = processor.sanitizeHtml(malformed);

        expect(sanitized, isA<String>());
        expect(sanitized, isNot(isEmpty));
      });
    });
  });
}
