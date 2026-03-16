import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_commentary_selection.dart';

void main() {
  group('Page shape remaining commentators', () {
    test('returns all commentators when no dedicated slots are chosen', () {
      final commentators = resolveRemainingPageShapeCommentators(
        availableCommentators: const ['רש"י', 'תוספות', 'רמב"ן'],
        excludedCommentators: const [],
      );

      expect(commentators, ['רש"י', 'תוספות', 'רמב"ן']);
    });

    test('excludes commentators already shown in other slots', () {
      final commentators = resolveRemainingPageShapeCommentators(
        availableCommentators: const ['רש"י', 'תוספות', 'רמב"ן', 'רא"ש'],
        excludedCommentators: const ['רש"י', 'רמב"ן', 'רא"ש'],
      );

      expect(commentators, ['תוספות']);
    });

    test('formats special selection with a user-facing label', () {
      expect(
        formatPageShapeCommentatorSelection(
          pageShapeRemainingCommentatorsValue,
        ),
        pageShapeRemainingCommentatorsLabel,
      );
    });
  });
}
