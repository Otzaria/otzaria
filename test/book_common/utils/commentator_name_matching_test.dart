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

    test('a matching base name wins over a containing name', () {
      expect(
        findMatchingCommentator('אבן עזרא', const [
          'פירוש אבן עזרא',
          'אבן עזרא על בראשית',
        ]),
        'אבן עזרא על בראשית',
      );
    });

    test('a containing name is not the same commentator', () {
      expect(
        findMatchingCommentator('אבן עזרא', const ['פירוש אבן עזרא']),
        isNull,
      );
    });

    test('a containing name with the same collective title is matched', () {
      expect(
        findMatchingCommentator(
          'אבן עזרא',
          const ['פירוש אבן עזרא'],
          identities: {
            'פירוש אבן עזרא': CommentatorIdentity(collectiveTitle: 'אבן עזרא'),
          },
        ),
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

  group('commentator identity (issue #2704)', () {
    test('a collective title that differs from the base name matches', () {
      final identities = {
        'פסקי הרא"ש על מכות': CommentatorIdentity(collectiveTitle: 'רא״ש'),
      };
      const available = ['פסקי הרא"ש על מכות', 'תוספות הרא"ש על מכות'];

      expect(
        commentatorKey(
          'פסקי הרא"ש על מכות',
          commentedBookTitle: 'מכות',
          identities: identities,
        ),
        'רא"ש',
      );
      expect(
        findMatchingCommentator(
          'רא"ש',
          available,
          commentedBookTitle: 'מכות',
          identities: identities,
        ),
        'פסקי הרא"ש על מכות',
      );
      expect(
        findMatchingCommentator(
          'פסקי הרא"ש',
          available,
          commentedBookTitle: 'מכות',
          identities: identities,
        ),
        'פסקי הרא"ש על מכות',
        reason: 'a base name saved by an older version still matches',
      );
      expect(
        findMatchingCommentator(
          'רא"ש',
          available,
          commentedBookTitle: 'מכות',
        ),
        isNull,
        reason: 'without the book identities only the base name is known',
      );
    });

    test('a key that only starts another key does not match', () {
      expect(
        findMatchingCommentator(
          'תוספות הרא"ש',
          const ['תוספות על ברכות'],
          commentedBookTitle: 'ברכות',
        ),
        isNull,
      );
    });

    test('several matches prefer the commentary on this book, then links', () {
      final identities = {
        'רי"ף שבת': CommentatorIdentity(collectiveTitle: 'רי"ף', linkCount: 90),
        'רי"ף ברכות': CommentatorIdentity(
          collectiveTitle: 'רי"ף',
          linkCount: 10,
        ),
        'רי"ף ברכות (דפוס)': CommentatorIdentity(
          collectiveTitle: 'רי"ף',
          linkCount: 40,
        ),
      };

      expect(
        findMatchingCommentator(
          'רי"ף',
          const ['רי"ף שבת', 'רי"ף ברכות'],
          commentedBookTitle: 'ברכות',
          identities: identities,
        ),
        'רי"ף ברכות',
      );
      expect(
        findMatchingCommentator(
          'רי"ף',
          const ['רי"ף שבת', 'רי"ף ברכות (דפוס)'],
          commentedBookTitle: 'ברכות',
          identities: identities,
        ),
        'רי"ף שבת',
        reason: 'neither comments on this book, so more links win',
      );
    });

    test('a legacy full title is keyed by its own book identity', () {
      final identities = {
        'רי"ף בבא מציעא': CommentatorIdentity(
          collectiveTitle: 'רי"ף',
          baseBookTitle: 'בבא מציעא',
        ),
        'רי"ף שבת': CommentatorIdentity(collectiveTitle: 'רי"ף', linkCount: 90),
        'רי"ף ברכות': CommentatorIdentity(
          collectiveTitle: 'רי"ף',
          linkCount: 10,
        ),
      };

      expect(
        findMatchingCommentator(
          'רי"ף בבא מציעא',
          const ['רי"ף שבת', 'רי"ף ברכות'],
          commentedBookTitle: 'ברכות',
          identities: identities,
        ),
        'רי"ף ברכות',
      );
      expect(
        findMatchingCommentator(
          'יכין מקואות',
          const ['יכין נדה'],
          commentedBookTitle: 'משנה נדה',
          identities: {
            'יכין מקואות': CommentatorIdentity(baseBookTitle: 'משנה מקואות'),
          },
        ),
        'יכין נדה',
        reason: 'without a collective title the base is taken from its book',
      );
    });
  });
}
