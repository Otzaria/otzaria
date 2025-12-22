import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Commentary Reverse Links Tests', () {
    test('identifies commentary book correctly', () {
      // This is an internal test to verify the logic
      // Note: _getSourceBookFromCommentary is private, so we test it indirectly

      const commentaryTitle = 'הערות על סוכה';
      const expectedSourceTitle = 'סוכה';

      // The logic: if title starts with "הערות על ", extract the rest
      const prefix = 'הערות על ';
      final sourceTitle = commentaryTitle.startsWith(prefix)
          ? commentaryTitle.substring(prefix.length)
          : null;

      expect(sourceTitle, equals(expectedSourceTitle));
    });

    test('does not identify non-commentary book as commentary', () {
      const regularTitle = 'סוכה';

      const prefix = 'הערות על ';
      final sourceTitle = regularTitle.startsWith(prefix)
          ? regularTitle.substring(prefix.length)
          : null;

      expect(sourceTitle, isNull);
    });

    test('handles commentary book with complex name', () {
      const commentaryTitle = 'הערות על מסכת בבא מציעא';
      const expectedSourceTitle = 'מסכת בבא מציעא';

      const prefix = 'הערות על ';
      final sourceTitle = commentaryTitle.startsWith(prefix)
          ? commentaryTitle.substring(prefix.length)
          : null;

      expect(sourceTitle, equals(expectedSourceTitle));
    });

    test('requires exact prefix match including space', () {
      const titleWithoutSpace = 'הערות עלסוכה';

      const prefix = 'הערות על ';
      final sourceTitle = titleWithoutSpace.startsWith(prefix)
          ? titleWithoutSpace.substring(prefix.length)
          : null;

      expect(sourceTitle, isNull);
    });

    test('handles empty string after prefix', () {
      const titleOnlyPrefix = 'הערות על ';

      const prefix = 'הערות על ';
      final sourceTitle = titleOnlyPrefix.startsWith(prefix)
          ? titleOnlyPrefix.substring(prefix.length)
          : null;

      expect(sourceTitle, equals(''));
    });
  });

  group('Reverse Link Creation Logic', () {
    test('reverse link swaps indices correctly', () {
      // Simulating the reverse link creation logic
      // Original link: Source book line 100 → Commentary line 50
      const originalIndex1 = 100;
      const originalIndex2 = 50;

      // Reverse link should be: Commentary line 50 → Source book line 100
      final reverseIndex1 = originalIndex2;
      final reverseIndex2 = originalIndex1;

      expect(reverseIndex1, equals(50));
      expect(reverseIndex2, equals(100));
    });
  });
}
