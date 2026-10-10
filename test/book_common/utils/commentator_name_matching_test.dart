import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/utils/commentator_name_matching.dart';

void main() {
  group('findMatchingCommentator without a commented book', () {
    test('a missing name matches nothing', () {
      expect(findMatchingCommentator(null, const ['רש"י על בראשית']), isNull);
    });

    test('an exact match wins over a longer name', () {
      expect(
        findMatchingCommentator('רש"י', const ['רש"י על בראשית', 'רש"י']),
        'רש"י',
      );
    });

    test('a prefix match wins over a containing name', () {
      expect(
        findMatchingCommentator('אבן עזרא', const [
          'פירוש אבן עזרא',
          'אבן עזרא על בראשית',
        ]),
        'אבן עזרא על בראשית',
      );
    });

    test('a containing name is matched', () {
      expect(
        findMatchingCommentator('אבן עזרא', const ['פירוש אבן עזרא']),
        'פירוש אבן עזרא',
      );
    });

    test('a name that contains an available one is matched last', () {
      expect(
        findMatchingCommentator('רמב"ן על בראשית', const ['רמב"ן']),
        'רמב"ן',
      );
    });

    test('a name with no match returns null', () {
      expect(findMatchingCommentator('ספורנו', const ['רש"י']), isNull);
    });
  });
}
