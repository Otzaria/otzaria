import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/sharing_utils.dart';
import 'package:otzaria/tabs/models/tab.dart';

/// Simple mock tab for testing without dependencies
class MockTab extends OpenedTab {
  MockTab(super.title);

  @override
  Map<String, dynamic> toJson() => {'title': title, 'type': 'MockTab'};
}

/// Property-based tests for sharing utilities
///
/// These tests validate that sharing URL generation works correctly
/// and produces unique URLs for different sharing types.
void main() {
  group('Sharing Utils Property Tests', () {
    /// Property 3: Unique Sharing URL Generation
    /// Validates: Requirements 3.1, 3.2, 3.3, 3.4
    test('Property 3: Unique Sharing URL Generation', () {
      const int iterations = 100;
      final random = Random(42);

      for (int i = 0; i < iterations; i++) {
        // Generate random tab data using simple mock
        final title =
            'ספר ${_generateRandomHebrewText(random, random.nextInt(3) + 1)}';
        final tab = MockTab(title);
        final selectedText = random.nextBool()
            ? _generateRandomHebrewText(random, random.nextInt(50) + 1)
            : null;

        // Generate URLs using sharing utilities
        final bookLink = SharingUtils.generateBookLink(tab);
        final sectionLink = SharingUtils.generateSectionLink(tab);
        final highlightLink = SharingUtils.generateHighlightedTextLink(tab,
            selectedText: selectedText);

        // Property: All three URLs should be different
        expect(
          bookLink != sectionLink,
          isTrue,
          reason:
              'Book link and section link should be different (iteration $i)\n'
              'Book: $bookLink\nSection: $sectionLink',
        );

        expect(
          bookLink != highlightLink,
          isTrue,
          reason:
              'Book link and highlight link should be different (iteration $i)\n'
              'Book: $bookLink\nHighlight: $highlightLink',
        );

        expect(
          sectionLink != highlightLink,
          isTrue,
          reason:
              'Section link and highlight link should be different (iteration $i)\n'
              'Section: $sectionLink\nHighlight: $highlightLink',
        );

        // Property: All URLs should start with otzaria:// protocol
        expect(
          bookLink.startsWith('otzaria://'),
          isTrue,
          reason:
              'Book link should use otzaria protocol (iteration $i): $bookLink',
        );

        expect(
          sectionLink.startsWith('otzaria://'),
          isTrue,
          reason:
              'Section link should use otzaria protocol (iteration $i): $sectionLink',
        );

        expect(
          highlightLink.startsWith('otzaria://'),
          isTrue,
          reason:
              'Highlight link should use otzaria protocol (iteration $i): $highlightLink',
        );

        // Property: Section link should contain at least as much information as book link
        expect(
          sectionLink.length >= bookLink.length,
          isTrue,
          reason:
              'Section link should contain at least as much info as book link (iteration $i)',
        );

        // Property: Highlight link should contain at least as much information as section link
        expect(
          highlightLink.length >= sectionLink.length,
          isTrue,
          reason:
              'Highlight link should contain at least as much info as section link (iteration $i)',
        );

        // Property: URLs should contain encoded book title
        final encodedTitle = Uri.encodeComponent(tab.title);
        expect(
          bookLink.contains(encodedTitle),
          isTrue,
          reason:
              'Book link should contain encoded title (iteration $i): $bookLink',
        );

        expect(
          sectionLink.contains(encodedTitle),
          isTrue,
          reason:
              'Section link should contain encoded title (iteration $i): $sectionLink',
        );

        expect(
          highlightLink.contains(encodedTitle),
          isTrue,
          reason:
              'Highlight link should contain encoded title (iteration $i): $highlightLink',
        );

        // Property: If selected text provided, highlight link should contain it
        if (selectedText != null && selectedText.trim().isNotEmpty) {
          final encodedText = Uri.encodeComponent(selectedText.trim());
          expect(
            highlightLink.contains(encodedText) ||
                highlightLink.contains('text='),
            isTrue,
            reason:
                'Highlight link should contain encoded text or text parameter (iteration $i)',
          );
        }
      }
    });

    /// Property: URL encoding consistency
    /// For any text input, URL encoding should be consistent and reversible
    test('Property: URL encoding consistency', () {
      const int iterations = 50;
      final random = Random(42);

      for (int i = 0; i < iterations; i++) {
        final originalText =
            _generateRandomHebrewText(random, random.nextInt(10) + 1);
        final tab = MockTab(originalText);

        final bookLink = SharingUtils.generateBookLink(tab);
        final encodedTitle = Uri.encodeComponent(originalText);

        // Property: Encoded title should be decodable back to original
        final decodedTitle = Uri.decodeComponent(encodedTitle);
        expect(
          decodedTitle,
          equals(originalText),
          reason: 'URL encoding should be reversible (iteration $i)',
        );

        // Property: Book link should contain the encoded title
        expect(
          bookLink.contains(encodedTitle),
          isTrue,
          reason:
              'Book link should contain properly encoded title (iteration $i)',
        );
      }
    });

    /// Property: Link generation robustness
    /// For any valid tab, link generation should never fail or return empty strings
    test('Property: Link generation robustness', () {
      const int iterations = 50;
      final random = Random(42);

      for (int i = 0; i < iterations; i++) {
        final title = _generateRandomHebrewText(random, random.nextInt(5) + 1);
        final tab = MockTab(title);

        final bookLink = SharingUtils.generateBookLink(tab);
        final sectionLink = SharingUtils.generateSectionLink(tab);
        final highlightLink = SharingUtils.generateHighlightedTextLink(tab);

        // Property: Links should never be empty
        expect(
          bookLink.isNotEmpty,
          isTrue,
          reason: 'Book link should never be empty (iteration $i)',
        );

        expect(
          sectionLink.isNotEmpty,
          isTrue,
          reason: 'Section link should never be empty (iteration $i)',
        );

        expect(
          highlightLink.isNotEmpty,
          isTrue,
          reason: 'Highlight link should never be empty (iteration $i)',
        );

        // Property: Links should be valid URIs
        expect(
          () => Uri.parse(bookLink),
          returnsNormally,
          reason: 'Book link should be valid URI (iteration $i): $bookLink',
        );

        expect(
          () => Uri.parse(sectionLink),
          returnsNormally,
          reason:
              'Section link should be valid URI (iteration $i): $sectionLink',
        );

        expect(
          () => Uri.parse(highlightLink),
          returnsNormally,
          reason:
              'Highlight link should be valid URI (iteration $i): $highlightLink',
        );
      }
    });
  });
}

/// Helper function to generate random Hebrew text
String _generateRandomHebrewText(Random random, int wordCount) {
  final hebrewWords = [
    'תורה',
    'משנה',
    'גמרא',
    'הלכה',
    'אגדה',
    'מדרש',
    'זוהר',
    'קבלה',
    'תפילה',
    'ברכה',
    'מצוה',
    'שבת',
    'חג',
    'יום טוב',
    'ראש השנה',
    'יום כיפור',
    'סוכות',
    'פסח',
    'שבועות',
    'חנוכה',
    'פורים',
    'תשעה באב',
    'ספירת העומר',
    'בית המקדש',
    'כהן',
    'לוי',
    'ישראל',
    'נביא',
    'מלך',
    'שופט',
    'זקן'
  ];

  final words = <String>[];
  for (int i = 0; i < wordCount; i++) {
    words.add(hebrewWords[random.nextInt(hebrewWords.length)]);
  }

  return words.join(' ');
}
